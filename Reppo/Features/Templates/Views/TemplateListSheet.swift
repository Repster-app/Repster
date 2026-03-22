// TemplateListSheet.swift
// Bottom sheet showing saved templates for the user to select and start a workout from.
// Also hosts reviewed template import and the ChatGPT prompt-helper flow.

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TemplateListSheet: View {

    @State private var viewModel: TemplateListViewModel
    @State private var showImportPicker = false
    @State private var showAIHelper = false
    @State private var isImportingTemplate = false
    @State private var exportingTemplateId: UUID? = nil
    @State private var shareSheetItem: TemplateShareItem? = nil
    @State private var actionAlert: TemplateActionAlert? = nil
    @State private var pendingImportReview: PendingTemplateImportReview? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(ServiceContainer.self) private var services

    let onStartWorkout: () -> Void
    let onCreateTemplate: () -> Void
    let onEditTemplate: (UUID) -> Void

    init(
        templateService: any TemplateServiceProtocol,
        onStartWorkout: @escaping () -> Void,
        onCreateTemplate: @escaping () -> Void,
        onEditTemplate: @escaping (UUID) -> Void
    ) {
        _viewModel = State(initialValue: TemplateListViewModel(templateService: templateService))
        self.onStartWorkout = onStartWorkout
        self.onCreateTemplate = onCreateTemplate
        self.onEditTemplate = onEditTemplate
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.bgSubtle)
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 16)

            HStack {
                Text("Templates")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                HStack(spacing: 8) {
                    actionPill(title: "AI Helper", systemImage: "sparkles", accent: true) {
                        showAIHelper = true
                    }

                    actionPill(title: "Import", systemImage: "square.and.arrow.down") {
                        showImportPicker = true
                    }

                    Button {
                        onCreateTemplate()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("New")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accent)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            Text("Select a template to start your workout")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if viewModel.templates.isEmpty {
                emptyState
            } else {
                templateList
            }

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.bg)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCard.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.bgCard)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.reppoTemplate]
        ) { result in
            handleImportSelection(result)
        }
        .sheet(item: $shareSheetItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
        .sheet(isPresented: $showAIHelper) {
            AITemplateHelperSheet(
                viewModel: viewModel,
                exerciseService: services.exerciseService,
                onImported: handleImportedTemplate
            )
        }
        .sheet(item: $pendingImportReview) { item in
            TemplateImportReviewSheet(
                preview: item.preview,
                viewModel: viewModel,
                exerciseService: services.exerciseService,
                onImported: handleImportedTemplate
            )
        }
        .task {
            await viewModel.loadTemplates()
        }
        .alert("Delete Template?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            Button("Delete", role: .destructive) {
                Task { await viewModel.performDelete() }
            }
        } message: {
            Text("This will permanently delete this template. This action cannot be undone.")
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            if isImportingTemplate || exportingTemplateId != nil {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.accent)
                        Text(isImportingTemplate ? "Preparing import..." : "Preparing export...")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(24)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundColor(.textTertiary)

            Text("No templates yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textSecondary)

            Text("Create your first template or save one after finishing a workout")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.templates) { template in
                    TemplateCardView(
                        template: template,
                        isExporting: exportingTemplateId == template.id,
                        onTap: {
                            Task {
                                do {
                                    _ = try await viewModel.startWorkoutFromTemplate(template.id)
                                    dismiss()
                                    onStartWorkout()
                                } catch {
                                    print("[TemplateListSheet] Start from template failed: \(error)")
                                }
                            }
                        },
                        onExport: {
                            Task { await exportTemplate(template) }
                        },
                        onEdit: {
                            onEditTemplate(template.id)
                            dismiss()
                        },
                        onDelete: {
                            viewModel.confirmDelete(template.id)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func actionPill(
        title: String,
        systemImage: String,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(accent ? .white : .accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(accent ? Color.accent.opacity(0.88) : Color.accentSoft)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            actionAlert = TemplateActionAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )

        case .success(let url):
            Task {
                await importTemplate(from: url)
            }
        }
    }

    private func importTemplate(from url: URL) async {
        isImportingTemplate = true
        defer { isImportingTemplate = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let preview = try await viewModel.previewTemplateImport(data: data)

            if preview.unresolvedExercises.isEmpty {
                let importedId = try await viewModel.finalizeTemplateImport(preview, resolutions: [])
                handleImportedTemplate(importedId)
            } else {
                pendingImportReview = PendingTemplateImportReview(preview: preview)
            }
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func exportTemplate(_ template: TemplateSummary) async {
        exportingTemplateId = template.id
        defer { exportingTemplateId = nil }

        do {
            let data = try await viewModel.exportTemplate(template.id)
            let url = try temporaryShareURL(
                filename: sanitizedFilename(template.name),
                fileExtension: "reppotemplate",
                data: data
            )
            shareSheetItem = TemplateShareItem(url: url)
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func handleImportedTemplate(_ importedId: UUID) {
        Task {
            await viewModel.loadTemplates()
            let importedName = viewModel.templates.first(where: { $0.id == importedId })?.name ?? "Template"
            actionAlert = TemplateActionAlert(
                title: "Template Imported",
                message: "\"\(importedName)\" was added to your templates."
            )
        }
    }
}

private struct AITemplateHelperSheet: View {
    let viewModel: TemplateListViewModel
    let exerciseService: any ExerciseServiceProtocol
    let onImported: (UUID) -> Void

    @State private var draftText: String = ""
    @State private var isPreparingContext = false
    @State private var isPreviewing = false
    @State private var shareSheetItem: TemplateShareItem? = nil
    @State private var actionAlert: TemplateActionAlert? = nil
    @State private var pendingImportReview: PendingTemplateImportReview? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    helperIntro
                    contextCard
                    promptCard
                    draftCard
                }
                .padding(16)
            }
            .background(Color.bg)
            .navigationTitle("AI Template Helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $shareSheetItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
        .sheet(item: $pendingImportReview) { item in
            TemplateImportReviewSheet(
                preview: item.preview,
                viewModel: viewModel,
                exerciseService: exerciseService,
                onImported: { importedId in
                    onImported(importedId)
                    dismiss()
                }
            )
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            if isPreparingContext || isPreviewing {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.accent)
                        Text(isPreparingContext ? "Preparing context export..." : "Previewing template...")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(24)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var helperIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export your current exercise library, copy a prompt into ChatGPT, then paste the JSON response here.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textPrimary)

            Text("Any exercise the AI cannot match will be reviewed before the template is saved.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(16)
        .background(Color.bgCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Export Context")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Share a JSON file containing your existing exercises and lightweight stats.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.textSecondary)

            Button {
                Task { await exportContext() }
            } label: {
                Label("Share Context JSON", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.bgCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Copy Prompt")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Use this prompt with the exported context file. ChatGPT should return JSON only.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.textSecondary)

            Text(AITemplatePromptBuilder.prompt)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.bg)
                .cornerRadius(10)

            Button {
                UIPasteboard.general.string = AITemplatePromptBuilder.prompt
                actionAlert = TemplateActionAlert(
                    title: "Prompt Copied",
                    message: "Paste the prompt into ChatGPT alongside the exported context JSON."
                )
            } label: {
                Label("Copy Prompt", systemImage: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color.bgCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. Paste AI JSON")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Paste the full JSON response from ChatGPT, then preview the import.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.textSecondary)

            TextEditor(text: $draftText)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.textPrimary)
                .frame(minHeight: 220)
                .padding(8)
                .background(Color.bg)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.border, lineWidth: 1)
                )

            Button {
                Task { await previewDraftImport() }
            } label: {
                Label("Preview Import", systemImage: "sparkles.rectangle.stack")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(Color.bgCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private func exportContext() async {
        isPreparingContext = true
        defer { isPreparingContext = false }

        do {
            let data = try await viewModel.exportAITemplateContext()
            let url = try temporaryShareURL(
                filename: "reppo-ai-template-context-\(timestampString())",
                fileExtension: "json",
                data: data
            )
            shareSheetItem = TemplateShareItem(url: url)
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func previewDraftImport() async {
        isPreviewing = true
        defer { isPreviewing = false }

        do {
            let data = Data(draftText.utf8)
            let preview = try await viewModel.previewTemplateImport(data: data)
            pendingImportReview = PendingTemplateImportReview(preview: preview)
        } catch {
            actionAlert = TemplateActionAlert(
                title: "Preview Failed",
                message: error.localizedDescription
            )
        }
    }
}

private struct TemplateImportReviewSheet: View {
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
            summaryRow(label: "Source", value: preview.source == .aiTemplateDraft ? "AI Draft" : "Template Archive")
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

private struct PendingTemplateImportReview: Identifiable {
    let id = UUID()
    let preview: TemplateImportPreview
}

private struct TemplateActionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct TemplateShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private enum ImportResolutionChoice: String, CaseIterable {
    case mapExisting
    case createNew
}

private enum AITemplatePromptBuilder {
    static var prompt: String {
        """
        You are generating JSON for the Reppo app.
        Use the attached exercise context JSON as the source of truth.
        Prefer exercises that already exist in the context. If you recommend a new exercise, generate a new UUID and include full metadata.
        Return JSON only. Do not wrap it in markdown.

        Output schema:
        {
          "version": 1,
          "templateName": "Upper A",
          "notes": "Optional template notes",
          "exercises": [
            {
              "exerciseId": "UUID",
              "exerciseName": "Bench Press",
              "equipmentType": "barbell",
              "trackingType": "weightReps",
              "primaryMuscle": "chest",
              "secondaryMuscles": ["triceps"],
              "movementPattern": "press",
              "unilateral": false,
              "bilateralLoadFactor": null,
              "bodyweightFactor": 0,
              "weightIncrement": 2.5,
              "defaultRestTime": 120,
              "fatigueRate": null,
              "recoveryConstant": null,
              "orderInTemplate": 1,
              "supersetGroupKey": "A",
              "restTimeSeconds": 120,
              "notes": "Optional exercise notes",
              "sets": [
                {
                  "setType": "working",
                  "targetRepMin": 6,
                  "targetRepMax": 8,
                  "targetRIR": 2,
                  "orderInExercise": 1
                }
              ]
            }
          ]
        }

        Important rules:
        - Copy exerciseId exactly from the context when using an existing exercise.
        - Keep enum values exact.
        - equipmentType values: \(EquipmentType.allCases.map(\.rawValue).joined(separator: ", "))
        - trackingType values: \(TrackingType.allCases.map(\.rawValue).joined(separator: ", "))
        - movementPattern values: \(MovementPattern.allCases.map(\.rawValue).joined(separator: ", ")) or null
        - setType values: \(SetType.allCases.map(\.rawValue).joined(separator: ", "))
        - Keep exercises in the intended display order using orderInTemplate.
        - Use matching supersetGroupKey values such as A, B, or C for exercises that belong together.
        """
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension UTType {
    static let reppoTemplate = UTType(exportedAs: "com.magnusespensen.reppo.template", conformingTo: .json)
}

private func matchDescription(_ method: TemplateExerciseMatchMethod) -> String {
    switch method {
    case .exerciseId:
        return "exercise ID"
    case .normalizedName:
        return "normalized name"
    case .manualMapping:
        return "manual mapping"
    case .createNew:
        return "new exercise creation"
    }
}

private func exerciseMetadataSummary(_ exercise: TemplateImportExercisePreview) -> String {
    var parts: [String] = [
        exercise.exercise.equipmentType.displayName,
        exercise.exercise.trackingType.displayName
    ]

    if let primaryMuscle = ExercisePrimaryGroup.normalizedValue(exercise.exercise.primaryMuscle) {
        parts.append(ExercisePrimaryGroup.displayName(for: primaryMuscle))
    }

    if let restTime = exercise.restTimeSeconds {
        parts.append(formatRestTime(restTime))
    }

    parts.append("\(exercise.sets.count) set\(exercise.sets.count == 1 ? "" : "s")")
    return parts.joined(separator: " | ")
}

private func formatRestTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainder = seconds % 60
    if minutes > 0, remainder > 0 {
        return "\(minutes)m \(remainder)s rest"
    }
    if minutes > 0 {
        return "\(minutes)m rest"
    }
    return "\(seconds)s rest"
}

private func temporaryShareURL(
    filename: String,
    fileExtension: String,
    data: Data
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(filename)
        .appendingPathExtension(fileExtension)
    try data.write(to: url, options: .atomic)
    return url
}

private func sanitizedFilename(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = trimmed.isEmpty ? "template" : trimmed
    let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    let components = fallback.components(separatedBy: invalidCharacters)
    return components.joined(separator: "-")
}

private func timestampString() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}
