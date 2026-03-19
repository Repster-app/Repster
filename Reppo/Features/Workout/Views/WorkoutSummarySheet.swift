// WorkoutSummarySheet.swift
// Workout summary sheet shown when user taps "Finish Workout".
// Spec: FR-008 (Workout summary with stats, notes, RPE)
// Contract: WP07 T032 (summary view), T033 (notes + RPE), T035 (save & close)
//
// Displays workout stats computed from in-memory ViewModel state.
// User can add notes and select session RPE (1-10) before saving.

import SwiftUI

/// Summary sheet presenting workout statistics, notes, and RPE input.
///
/// Shown as a sheet from ActiveWorkoutView when "Finish" is tapped.
/// "Save & Close" calls ViewModel.finishWorkout() then dismisses.
struct WorkoutSummarySheet: View {

    // MARK: - Dependencies

    /// The ViewModel providing workout data and finish action.
    var viewModel: ActiveWorkoutViewModel

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// User-editable workout title (pre-populated with time-based default).
    @State private var workoutTitle: String = ""

    /// Free-form workout notes.
    @State private var notes: String = ""

    /// Selected session RPE (1-10), nil if not set.
    @State private var selectedRPE: Int? = nil

    /// Whether the save operation is in progress.
    @State private var isSaving = false

    /// Whether the discard confirmation alert is showing.
    @State private var showDiscardAlert = false

    /// Whether the discard operation is in progress.
    @State private var isDiscarding = false

    /// Shared controller for the save-as-template prompt flow.
    @State private var saveAsTemplateController = SaveWorkoutAsTemplateController()

    /// Whether the template was saved successfully (shows confirmation).
    @State private var templateSavedSuccessfully = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let summary = viewModel.computeSummary() {
                        // Date + Duration header
                        headerSection(summary: summary)

                        // Stats cards row
                        statsRow(summary: summary)

                        // Per-exercise breakdown
                        if !summary.exerciseSummaries.isEmpty {
                            exerciseList(summary: summary)
                        }

                        // Workout title input
                        titleSection

                        // Notes input (T033)
                        notesSection

                        // RPE selector (T033)
                        rpeSelector

                        // Save as Template button
                        saveAsTemplateButton

                        // Discard workout button
                        discardButton
                    } else {
                        // Empty workout fallback
                        emptyWorkoutMessage
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.bg)
            .navigationTitle("Workout Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Close") {
                        Task { await saveAndClose() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
        }
        .onAppear {
            // Pre-populate title with time-based default (Strava-style)
            workoutTitle = viewModel.workout?.displayTitle ?? "Workout"
            // Pre-populate notes from existing workout data
            notes = viewModel.workout?.notes ?? ""
        }
        .saveWorkoutAsTemplatePrompt(
            controller: saveAsTemplateController,
            workoutId: viewModel.workout?.id,
            onSaved: { _ in
                templateSavedSuccessfully = true
            },
            onError: { error in
                print("[WorkoutSummarySheet] Save as template failed: \(error)")
            }
        )
    }

    // MARK: - Header Section

    /// Date and formatted workout duration.
    private func headerSection(summary: WorkoutSummaryData) -> some View {
        VStack(spacing: 4) {
            Text(summary.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            Text(formatDuration(summary.duration))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
        .padding(.top, 20)
    }

    // MARK: - Stats Row

    /// Horizontal row of stat cards (Sets, Volume, PRs).
    private func statsRow(summary: WorkoutSummaryData) -> some View {
        HStack(spacing: 12) {
            statCard(label: "Sets", value: "\(summary.totalSets)")
            statCard(label: "Volume", value: formatVolume(summary.totalVolume))
            if summary.prsHit > 0 {
                statCard(label: "PRs", value: "\(summary.prsHit)", highlight: true)
            }
        }
    }

    /// A single stat card with label and value.
    private func statCard(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(highlight ? .gold : .textPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(highlight ? Color.goldSoft : Color.bgCard)
        .cornerRadius(10)
    }

    // MARK: - Exercise List

    /// Per-exercise breakdown showing name, set count, best weight, and PR indicator.
    private func exerciseList(summary: WorkoutSummaryData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercises")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)

            ForEach(summary.exerciseSummaries) { exercise in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(exercise.exerciseName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.textPrimary)
                            if exercise.hadPR {
                                PRBadgeView(status: .current)
                            }
                        }
                        Text("\(exercise.setCount) sets")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    if let weight = exercise.bestWeight {
                        Text(formatWeight(weight))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.bgCard)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Title Section

    /// Text field for naming the workout. Pre-populated with time-based default.
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workout Title")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
            TextField("", text: $workoutTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.textPrimary)
                .padding(12)
                .background(Color.bgInput)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Notes Section (T033)

    /// Free-form text editor for workout notes.
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
            TextEditor(text: $notes)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color.bgInput)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.border, lineWidth: 1)
                )
                .font(.system(size: 15))
                .foregroundColor(.textPrimary)
        }
    }

    // MARK: - RPE Selector (T033)

    /// Horizontal row of 1-10 RPE buttons. Tapping the selected RPE deselects it.
    private var rpeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session RPE")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { rpe in
                    Button("\(rpe)") {
                        selectedRPE = (selectedRPE == rpe) ? nil : rpe
                    }
                    .font(.system(size: 14, weight: selectedRPE == rpe ? .bold : .regular))
                    .foregroundColor(selectedRPE == rpe ? .white : .textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(selectedRPE == rpe ? Color.accent : Color.bgSubtle)
                    .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Save as Template

    /// Button to save the workout structure as a reusable template.
    private var saveAsTemplateButton: some View {
        Button {
            saveAsTemplateController.begin(defaultName: workoutTitle.isEmpty ? "Workout" : workoutTitle)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                Text(templateSavedSuccessfully ? "Template Saved ✓" : "Save as Template")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(templateSavedSuccessfully ? .success : .accent)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(templateSavedSuccessfully ? Color.successSoft : Color.accentSoft)
            .cornerRadius(10)
        }
        .disabled(templateSavedSuccessfully || saveAsTemplateController.isSaving)
    }

    // MARK: - Discard Workout

    /// Destructive button to discard the workout entirely.
    /// Shows a confirmation alert before permanently deleting.
    private var discardButton: some View {
        Button(role: .destructive) {
            showDiscardAlert = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("Discard Workout")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.red.opacity(0.1))
            .cornerRadius(10)
        }
        .disabled(isDiscarding)
        .padding(.top, 8)
        .alert("Discard Workout?", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                Task { await discardAndClose() }
            }
        } message: {
            Text("This will permanently delete this workout and all its sets. This action cannot be undone.")
        }
    }

    // MARK: - Empty State

    /// Shown when computeSummary() returns nil (no active workout).
    private var emptyWorkoutMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 40))
                .foregroundColor(.textTertiary)
            Text("No workout data")
                .font(.headline)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Actions (T035)

    /// Save notes/RPE via ViewModel.finishWorkout(), then dismiss the sheet.
    private func saveAndClose() async {
        isSaving = true
        await viewModel.finishWorkout(
            title: workoutTitle.isEmpty ? nil : workoutTitle,
            notes: notes.isEmpty ? nil : notes,
            perceivedEffort: selectedRPE.map(Double.init)
        )
        isSaving = false
        dismiss()
    }

    /// Discard the workout via ViewModel.discardWorkout(), then dismiss the sheet.
    private func discardAndClose() async {
        isDiscarding = true
        await viewModel.discardWorkout()
        isDiscarding = false
        dismiss()
    }

    // MARK: - Formatting Helpers

    /// Format duration as "Xh Ym" or "Xm".
    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Format volume with thousands separator and "kg" suffix.
    private func formatVolume(_ volume: Double) -> String {
        if volume == 0 { return "0 kg" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: volume)) ?? "\(Int(volume))"
        return "\(formatted) kg"
    }

    /// Format weight using locale-aware decimal separator.
    private func formatWeight(_ weight: Double) -> String {
        "\(UnitConversion.formatWeight(weight)) kg"
    }
}

@Observable
@MainActor
final class SaveWorkoutAsTemplateController {
    var showPrompt = false
    var templateName = ""
    var isSaving = false

    func begin(defaultName: String) {
        let trimmedName = defaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        templateName = trimmedName.isEmpty ? "Workout" : trimmedName
        showPrompt = true
    }

    func save(
        workoutId: UUID,
        templateService: any TemplateServiceProtocol
    ) async throws -> String {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Workout" : trimmedName
        _ = try await templateService.createTemplateFromWorkout(workoutId, name: resolvedName)
        showPrompt = false
        return resolvedName
    }
}

struct TemplateSaveFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct SaveWorkoutAsTemplatePromptModifier: ViewModifier {
    @Environment(ServiceContainer.self) private var services
    @Bindable var controller: SaveWorkoutAsTemplateController

    let workoutId: UUID?
    let onSaved: (String) -> Void
    let onError: (Error) -> Void

    func body(content: Content) -> some View {
        content.alert("Save as Template", isPresented: $controller.showPrompt) {
            TextField("Template name", text: $controller.templateName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                guard let workoutId else { return }
                Task { await handleSave(workoutId: workoutId) }
            }
        } message: {
            Text("Save this workout's exercises and set structure as a reusable template. Weights are not included.")
        }
    }

    private func handleSave(workoutId: UUID) async {
        do {
            let savedName = try await controller.save(
                workoutId: workoutId,
                templateService: services.templateService
            )
            onSaved(savedName)
        } catch {
            onError(error)
        }
    }
}

extension View {
    func saveWorkoutAsTemplatePrompt(
        controller: SaveWorkoutAsTemplateController,
        workoutId: UUID?,
        onSaved: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) -> some View {
        modifier(
            SaveWorkoutAsTemplatePromptModifier(
                controller: controller,
                workoutId: workoutId,
                onSaved: onSaved,
                onError: onError
            )
        )
    }
}
