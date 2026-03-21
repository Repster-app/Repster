// WorkoutSummarySheet.swift
// Workout summary sheet shown when user taps "Finish Workout".
// Spec: FR-008 (Workout summary with stats, notes, RPE)
// Contract: WP07 T032 (summary view), T033 (notes + RPE), T035 (save & close)
//
// Redesigned as a layered single sheet: core summary and save inputs first,
// lower-frequency actions tucked behind secondary disclosure.

import SwiftUI

/// Summary sheet presenting workout statistics, notes, and effort input.
///
/// Shown as a sheet from ActiveWorkoutView when "Finish" is tapped.
/// "Save & Close" calls ViewModel.finishWorkout() then dismisses.
struct WorkoutSummarySheet: View {

    private enum FocusField: Hashable {
        case title
    }

    private enum FatigueFeedbackSelection: Equatable {
        case lessAggressive
        case aboutRight
        case moreAggressive
    }

    // MARK: - Dependencies

    /// The ViewModel providing workout data and finish action.
    var viewModel: ActiveWorkoutViewModel

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusField?

    // MARK: - State

    /// User-editable workout title. Empty means "use the automatic title".
    @State private var workoutTitle: String = ""

    /// Free-form workout notes.
    @State private var notes: String = ""

    /// Optional session effort value on a 1-10 scale.
    @State private var selectedEffort: Double? = nil

    /// Per-exercise fatigue feedback selections.
    @State private var fatigueSelections: [UUID: FatigueFeedbackSelection] = [:]

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

    /// Whether the inline title editor is expanded.
    @State private var isEditingTitle = false

    /// Whether suggestion feedback is expanded.
    @State private var isSuggestionFeedbackExpanded = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if let summary = viewModel.computeSummary() {
                ScrollView {
                    VStack(spacing: 18) {
                        recapHero(summary: summary)

                        if !summary.exerciseSummaries.isEmpty {
                            exerciseRecapSection(summary: summary)
                        }

                        if !exercisesForFeedback(summary: summary).isEmpty {
                            suggestionFeedbackSection(summary: summary)
                        }

                        secondaryActionsSection
                        notesSection
                        effortSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            } else {
                emptyWorkoutMessage
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.workout != nil {
                saveActionBar
            }
        }
        .onAppear {
            workoutTitle = viewModel.workout?.title ?? ""
            notes = viewModel.workout?.notes ?? ""

            if let perceivedEffort = viewModel.workout?.perceivedEffort {
                selectedEffort = min(max(perceivedEffort.rounded(), 1), 10)
            }
        }
        .alert("Discard Workout?", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                Task { await discardAndClose() }
            }
        } message: {
            Text("This will permanently delete this workout and all its sets. This action cannot be undone.")
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

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                dismiss()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.textSecondary)
            .frame(width: 72, alignment: .leading)

            Spacer()

            Text("Workout complete")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Spacer()

            Color.clear
                .frame(width: 72, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
        }
    }

    // MARK: - Recap Hero

    private func recapHero(summary: WorkoutSummaryData) -> some View {
        VStack(spacing: 10) {
            Text(summary.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            sectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    summaryTitleSection

                    HStack(spacing: 10) {
                        compactSummaryMetric(
                            label: "Time",
                            value: formatDuration(summary.duration),
                            prominent: true
                        )
                        compactSummaryMetric(label: "Sets", value: "\(summary.totalSets)")
                        compactSummaryMetric(label: "Volume", value: formatVolume(summary.totalVolume))
                    }

                    if summary.prsHit > 0 {
                        HStack(spacing: 8) {
                            PRBadgeView(status: .current)

                            Text(summary.prsHit == 1 ? "1 PR this session" : "\(summary.prsHit) PRs this session")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func compactSummaryMetric(label: String, value: String, prominent: Bool = false) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: prominent ? 20 : 18, weight: .bold, design: prominent ? .rounded : .default))
                .monospacedDigit()
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.horizontal, 8)
        .background(prominent ? Color.accentSoft : Color.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }

    // MARK: - Title

    private var summaryTitleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditingTitle.toggle()
                }

                if isEditingTitle {
                    focusedField = .title
                } else {
                    focusedField = nil
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workout title")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)

                        Text(resolvedWorkoutTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Label(isEditingTitle ? "Done" : "Edit", systemImage: isEditingTitle ? "checkmark.circle.fill" : "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isEditingTitle ? .accent : .textSecondary)
                }
            }
            .buttonStyle(.plain)

            if isEditingTitle {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: $workoutTitle, prompt: Text(automaticWorkoutTitle))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.bgInput)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.border, lineWidth: 1)
                        }
                        .focused($focusedField, equals: .title)

                    Text("Leave blank to keep the automatic title.")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading(
                    title: "Notes",
                    subtitle: "Optional quick note"
                )

                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Add a quick note...")
                            .font(.system(size: 15))
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                    }

                    TextEditor(text: $notes)
                        .font(.system(size: 15))
                        .foregroundColor(.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 64)
                        .textInputAutocapitalization(.sentences)
                }
                .background(Color.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.border, lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Effort

    private var effortSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text("How hard did it feel?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Text(effortValueLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selectedEffort == nil ? .textSecondary : .textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.bgInput)
                        .clipShape(Capsule())
                }

                if selectedEffort != nil {
                    Button("Clear") {
                        selectedEffort = nil
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                }

                Slider(value: effortSliderBinding, in: 1...10, step: 1)
                    .tint(.accent)

                HStack {
                    Text("Easy")
                    Spacer()
                    Text("Max")
                }
                .font(.caption)
                .foregroundColor(.textTertiary)
            }
        }
    }

    // MARK: - Exercise Recap

    private func exerciseRecapSection(summary: WorkoutSummaryData) -> some View {
        return sectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeading(
                    title: "Exercises",
                    subtitle: "\(summary.exerciseSummaries.count) logged"
                )

                VStack(spacing: 0) {
                    ForEach(Array(summary.exerciseSummaries.enumerated()), id: \.element.id) { index, exercise in
                        exerciseSummaryRow(exercise)

                        if index < summary.exerciseSummaries.count - 1 {
                            Rectangle()
                                .fill(Color.border)
                                .frame(height: 1)
                        }
                    }
                }
                .background(Color.bgInput.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func exerciseSummaryRow(_ exercise: ExerciseSummary) -> some View {
        HStack(spacing: 10) {
            Text(exercise.exerciseName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            HStack(spacing: 8) {
                Text("\(exercise.setCount) sets")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .frame(width: 44, alignment: .trailing)

                exercisePRTag(isVisible: exercise.hadPR)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func exercisePRTag(isVisible: Bool) -> some View {
        Text("PR")
            .font(.caption.weight(.semibold))
            .foregroundColor(.gold)
            .padding(.horizontal, 8)
            .frame(width: 46, height: 24)
            .background(Color.goldSoft)
            .clipShape(Capsule())
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(!isVisible)
    }

    // MARK: - Suggestion Feedback

    private func suggestionFeedbackSection(summary: WorkoutSummaryData) -> some View {
        let feedbackExercises = exercisesForFeedback(summary: summary)

        return sectionCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSuggestionFeedbackExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                    sectionHeading(
                        title: "Suggestion feedback",
                        subtitle: "Only adjust this if the weight changes felt noticeably off."
                    )

                        Spacer()

                        Image(systemName: isSuggestionFeedbackExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isSuggestionFeedbackExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your feedback helps fine-tune how quickly future suggestions taper within a workout.")
                            .font(.caption)
                            .foregroundColor(.textSecondary)

                        ForEach(feedbackExercises) { exercise in
                            fatigueFeedbackRow(exercise: exercise)
                        }
                    }
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func fatigueFeedbackRow(exercise: ExerciseSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.exerciseName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    fatigueFeedbackButtons(for: exercise)
                }

                VStack(spacing: 8) {
                    fatigueFeedbackButtons(for: exercise)
                }
            }
        }
        .padding(14)
        .background(Color.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func fatigueFeedbackButtons(for exercise: ExerciseSummary) -> some View {
        feedbackButton(
            title: "Too much drop",
            isSelected: fatigueSelections[exercise.id] == .lessAggressive,
            color: .success
        ) {
            fatigueSelections[exercise.id] = fatigueSelections[exercise.id] == .lessAggressive ? nil : .lessAggressive
        }

        feedbackButton(
            title: "About right",
            isSelected: fatigueSelections[exercise.id] == .aboutRight,
            color: .accent
        ) {
            fatigueSelections[exercise.id] = fatigueSelections[exercise.id] == .aboutRight ? nil : .aboutRight
        }

        feedbackButton(
            title: "Not enough drop",
            isSelected: fatigueSelections[exercise.id] == .moreAggressive,
            color: .orange
        ) {
            fatigueSelections[exercise.id] = fatigueSelections[exercise.id] == .moreAggressive ? nil : .moreAggressive
        }
    }

    private func feedbackButton(title: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(isSelected ? .white : color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? color : Color.bg)
                )
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.clear : color.opacity(0.25), lineWidth: 1)
        }
    }

    // MARK: - Secondary Actions

    private var secondaryActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    saveAsTemplateController.begin(defaultName: resolvedWorkoutTitle)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: templateSavedSuccessfully ? "checkmark.circle.fill" : "doc.text")
                        Text(templateSavedSuccessfully ? "Template Saved" : "Save as Template")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(templateSavedSuccessfully ? .success : .accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(templateSavedSuccessfully ? Color.successSoft : Color.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(templateSavedSuccessfully || saveAsTemplateController.isSaving || isSaving || viewModel.workout?.id == nil)

                Button(role: .destructive) {
                    showDiscardAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Discard Workout")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color.dangerSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isDiscarding || isSaving)
            }

            if templateSavedSuccessfully {
                Text("Template saved for reuse.")
                    .font(.caption)
                    .foregroundColor(.success)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Save Bar

    private var saveActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)

            Button {
                Task { await saveAndClose() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(isSaving ? "Saving..." : "Save & Close")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving || isDiscarding)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(Color.bg)
    }

    // MARK: - Empty State

    private var emptyWorkoutMessage: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "figure.walk")
                .font(.system(size: 40))
                .foregroundColor(.textTertiary)

            Text("No workout data")
                .font(.headline)
                .foregroundColor(.textSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func saveAndClose() async {
        isSaving = true

        for (exerciseId, selection) in fatigueSelections {
            let nudge: FatigueNudge?
            switch selection {
            case .lessAggressive:
                nudge = .lessAggressive
            case .aboutRight:
                nudge = nil
            case .moreAggressive:
                nudge = .moreAggressive
            }

            if let nudge {
                try? await viewModel.fatigueLearningService.applyManualNudge(
                    exerciseId: exerciseId,
                    nudge: nudge
                )
            }
        }

        await viewModel.finishWorkout(
            title: normalizedWorkoutTitle,
            notes: normalizedNotes,
            perceivedEffort: selectedEffort
        )

        isSaving = false

        if viewModel.isWorkoutFinished {
            dismiss()
        }
    }

    private func discardAndClose() async {
        isDiscarding = true
        await viewModel.discardWorkout()
        isDiscarding = false

        if viewModel.isWorkoutFinished {
            dismiss()
        }
    }

    // MARK: - Formatting

    private var automaticWorkoutTitle: String {
        viewModel.workout?.displayTitle ?? "Workout"
    }

    private var normalizedWorkoutTitle: String? {
        let trimmed = workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var resolvedWorkoutTitle: String {
        normalizedWorkoutTitle ?? automaticWorkoutTitle
    }

    private var effortSliderBinding: Binding<Double> {
        Binding(
            get: { selectedEffort ?? 5 },
            set: { selectedEffort = $0.rounded() }
        )
    }

    private var effortValueLabel: String {
        guard let selectedEffort else { return "Optional" }
        return "\(Int(selectedEffort))/10"
    }

    private var weightUnitLabel: String {
        viewModel.unitPreference == .imperial ? "lbs" : "kg"
    }

    private func exercisesForFeedback(summary: WorkoutSummaryData) -> [ExerciseSummary] {
        summary.exerciseSummaries.filter { viewModel.exerciseIdsWithPredictions.contains($0.id) }
    }

    private func sectionHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }

    private func displayWeight(_ kg: Double) -> Double {
        viewModel.unitPreference == .imperial ? UnitConversion.kgToLbs(kg) : kg
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatVolume(_ volume: Double) -> String {
        let convertedVolume = displayWeight(volume)
        if convertedVolume == 0 { return "0 \(weightUnitLabel)" }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: convertedVolume)) ?? "\(Int(convertedVolume))"
        return "\(formatted) \(weightUnitLabel)"
    }

    private func formatWeight(_ weight: Double) -> String {
        let convertedWeight = displayWeight(weight)
        return "\(UnitConversion.formatWeight(convertedWeight)) \(weightUnitLabel)"
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
