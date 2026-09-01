// TemplateImportReviewSheet.swift
// Reviewing an imported template before it is saved: what matched, and what needs a decision.
//
// Shared by both import paths — a `.repstertemplate` archive and an AI-authored draft — because
// either can reference an exercise this library does not have.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TemplateImportReviewSheet: View {
    let preview: TemplateImportPreview
    let viewModel: TemplateListViewModel
    let exerciseService: any ExerciseServiceProtocol
    let onImported: (UUID) -> Void

    @State private var allExercises: [Exercise] = []
    @State private var selectedActions: [UUID: ImportResolutionChoice] = [:]
    @State private var selectedExerciseIds: [UUID: UUID] = [:]
    @State private var isLoadingExercises = false
    @State private var isImporting = false
    @State private var actionAlert: TemplateActionAlert? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                summarySection

                if !preview.resolvedExercises.isEmpty {
                    matchedExercisesSection
                }

                if !preview.unresolvedExercises.isEmpty {
                    unresolvedExercisesSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(importButtonTitle) {
                        Task { await finalizeImport() }
                    }
                    .disabled(!canImport || isImporting)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loadExercisesIfNeeded()
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.accent)
                        Text("Importing template...")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(24)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            summaryRow(label: "Source", value: "Template Archive")
            summaryRow(label: "Template", value: preview.templateName)
            summaryRow(label: "Exercises", value: "\(preview.exercises.count)")
            summaryRow(label: "Matched", value: "\(preview.resolvedExercises.count)")
            summaryRow(label: "Needs Review", value: "\(preview.unresolvedExercises.count)")

            if let notes = preview.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        // Free text, whether it was typed here or arrived in an import.
                        .replayMasked()
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Summary")
        }
    }

    private var matchedExercisesSection: some View {
        Section {
            ForEach(preview.resolvedExercises) { exercise in
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exercise.name)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    if let matchedExercise = exercise.matchedExercise {
                        Text("Matched to \(matchedExercise.name) by \(matchDescription(matchedExercise.method)).")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Matched Exercises")
        }
    }

    private var unresolvedExercisesSection: some View {
        Section {
            if isLoadingExercises {
                ProgressView("Loading exercises...")
            }

            ForEach(preview.unresolvedExercises) { exercise in
                VStack(alignment: .leading, spacing: 12) {
                    Text(exercise.exercise.name)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    Text(exerciseMetadataSummary(exercise))
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)

                    Picker("Resolution", selection: actionBinding(for: exercise.id)) {
                        Text("Map Existing").tag(ImportResolutionChoice.mapExisting)
                        Text("Create New").tag(ImportResolutionChoice.createNew)
                    }
                    .pickerStyle(.segmented)

                    if selectedActions[exercise.id, default: .mapExisting] == .mapExisting {
                        Picker("Existing Exercise", selection: mappedExerciseBinding(for: exercise.id)) {
                            Text("Select Exercise").tag(Optional<UUID>.none)
                            ForEach(allExercises, id: \.id) { existingExercise in
                                Text(existingExercise.name).tag(Optional(existingExercise.id))
                            }
                        }
                    } else {
                        Text("A new exercise will be created from the imported metadata before the template is saved.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }

                    if let notes = exercise.notes, !notes.isEmpty {
                        Text("Notes: \(notes)")
                            .font(.footnote)
                            .foregroundStyle(Color.textTertiary)
                            .replayMasked()
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("Needs Review")
        } footer: {
            Text("Every unresolved exercise must be mapped to an existing one or explicitly created as new.")
        }
    }

    private var canImport: Bool {
        preview.unresolvedExercises.allSatisfy { exercise in
            switch selectedActions[exercise.id, default: .mapExisting] {
            case .mapExisting:
                return selectedExerciseIds[exercise.id] != nil
            case .createNew:
                return true
            }
        }
    }

    private var importButtonTitle: String {
        preview.unresolvedExercises.isEmpty ? "Import" : "Save Template"
    }

    private func loadExercisesIfNeeded() async {
        guard !preview.unresolvedExercises.isEmpty else { return }

        isLoadingExercises = true
        defer { isLoadingExercises = false }

        do {
            allExercises = try await exerciseService.fetchAllExercises()
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Load Failed",
                message: error.localizedDescription
            )
        }
    }

    private func finalizeImport() async {
        isImporting = true
        defer { isImporting = false }

        do {
            let resolutions = preview.unresolvedExercises.map { exercise in
                switch selectedActions[exercise.id, default: .mapExisting] {
                case .mapExisting:
                    return TemplateImportExerciseResolution(
                        previewExerciseId: exercise.id,
                        action: .mapToExisting,
                        existingExerciseId: selectedExerciseIds[exercise.id]
                    )
                case .createNew:
                    return TemplateImportExerciseResolution(
                        previewExerciseId: exercise.id,
                        action: .createNew
                    )
                }
            }

            let importedId = try await viewModel.finalizeTemplateImport(preview, resolutions: resolutions)
            onImported(importedId)
            dismiss()
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func actionBinding(for previewExerciseId: UUID) -> Binding<ImportResolutionChoice> {
        Binding(
            get: { selectedActions[previewExerciseId, default: .mapExisting] },
            set: { selectedActions[previewExerciseId] = $0 }
        )
    }

    private func mappedExerciseBinding(for previewExerciseId: UUID) -> Binding<UUID?> {
        Binding(
            get: { selectedExerciseIds[previewExerciseId] },
            set: { selectedExerciseIds[previewExerciseId] = $0 }
        )
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}


struct PendingTemplateImportReview: Identifiable {
    let id = UUID()
    let preview: TemplateImportPreview
}

struct TemplateActionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct TemplateShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum ImportResolutionChoice: String, CaseIterable {
    case mapExisting
    case createNew
}
