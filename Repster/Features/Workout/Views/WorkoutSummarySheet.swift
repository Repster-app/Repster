// WorkoutSummarySheet.swift
// Workout summary sheet shown when user taps "Finish Workout".
// Spec: FR-008 (Workout summary with stats, notes, RPE)
// Contract: WP07 T032 (summary view), T033 (notes + RPE), T035 (save & close)
//
// Redesigned as a layered single sheet: core summary and save inputs first,
// lower-frequency actions tucked behind secondary disclosure.

import SwiftUI

/// Preferences for the Coach surfaces on this screen.
enum CoachPreferences {
    static let summaryTeaserKey = "coach.showsSummaryTeaser"

    /// Whether the unbuilt "Analyse with Coach" teaser is shown on the summary sheet.
    ///
    /// Defaults to `true` but is readable from `UserDefaults`, so the teaser can be pulled
    /// without a release if Coach slips. A permanent "Soon" is a broken promise, and per
    /// REPSTER_COACH_SCOPING §2.5 the coach cannot initiate — this is one of the few moments
    /// it has the user's attention, so it has to be credible or absent.
    static var showsSummaryTeaser: Bool {
        UserDefaults.standard.object(forKey: summaryTeaserKey) as? Bool ?? true
    }
}

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
    @Environment(ServiceContainer.self) private var services
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

    /// Whether the details screen is pushed.
    @State private var showDetails = false

    /// Whether the share preview is showing.
    @State private var showSharePreview = false

    /// MET-based active-energy estimate for this session, or `nil` when no bodyweight has
    /// ever been logged. Deliberately independent of `HealthKitPreferences.writesEstimatedEnergy`:
    /// "show me my own estimate" and "write this to my Move ring" are different consents, and
    /// reusing one flag for both would blank this line for anyone who declined the Health write.
    @State private var estimatedCalories: Int?

    /// The summary as it stood the moment saving or discarding began.
    ///
    /// `finishWorkout` clears the ViewModel's workout state *before* it signals
    /// dismissal, so recomputing during the closing animation would blank this
    /// sheet out to "No workout data" while it is still on screen.
    @State private var frozenSummary: WorkoutSummaryData?

    /// The automatic title as it stood alongside `frozenSummary`, so the heading
    /// does not fall back to a generic "Workout" while the sheet slides away.
    @State private var frozenTitle: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar

                if let summary = displaySummary {
                    ScrollView {
                        VStack(spacing: 14) {
                            recapHero(summary: summary)

                            if !summary.exerciseSummaries.isEmpty {
                                exerciseRecapSection(summary: summary)
                            }

                            if CoachPreferences.showsSummaryTeaser {
                                coachTeaserCard
                            }

                            addDetailsRow
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    emptyWorkoutMessage
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.workout != nil || viewModel.isWorkoutFinished {
                    saveActionBar
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showDetails) {
                detailsScreen
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear {
            workoutTitle = viewModel.workout?.title ?? ""
            notes = viewModel.workout?.notes ?? ""

            if let perceivedEffort = viewModel.workout?.perceivedEffort {
                selectedEffort = min(max(perceivedEffort.rounded(), 1), 10)
            }
        }
        .task {
            await loadCalorieEstimate()
        }
        .sheet(isPresented: $showSharePreview) {
            if let summary = displaySummary {
                WorkoutSharePreviewSheet(data: shareCardData(summary: summary))
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
                dbg("[WorkoutSummarySheet] Save as template failed: \(error)")
            }
        )
    }

    // MARK: - Summary Source

    /// Live summary while the workout exists, then the frozen one while closing.
    ///
    /// Once either action starts, the frozen copy wins outright rather than being a fallback for
    /// `nil`. `computeSummary()` reads live models, and both actions leave them mid-flight: the
    /// discard deletes the rows out from under this view, and the finish has the repository actor
    /// saving them while the main actor reads. Both writes that start the actions — `isSaving`,
    /// `isDiscarding` — are read by this body, so a re-render inside that window is guaranteed.
    private var displaySummary: WorkoutSummaryData? {
        if isSaving || isDiscarding { return frozenSummary }
        return viewModel.computeSummary() ?? frozenSummary
    }

    // MARK: - Header

    /// Left-aligned title rather than centred, because "Share workout" needs the right-hand
    /// side and a centred title collides with it on a 390 pt screen.
    private var headerBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.bgInput)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Text("Workout complete")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let summary = displaySummary {
                shareWorkoutButton(hasPR: summary.prsHit > 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
        }
    }

    private func shareWorkoutButton(hasPR: Bool) -> some View {
        Button {
            showSharePreview = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))

                Text("Share workout")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(hasPR ? .gold : .accent)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(hasPR ? Color.goldSoft : Color.accentSoft)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke((hasPR ? Color.gold : Color.accent).opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share workout")
    }

    // MARK: - Recap Hero

    private func recapHero(summary: WorkoutSummaryData) -> some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 14) {
                summaryTitleSection(summary: summary)

                // No tile is promoted. Time carried the only accent before, which pointed the
                // card's single emphasis at how long you were in the gym rather than at
                // anything you did there. PRs now read off the exercise list instead.
                HStack(spacing: 10) {
                    compactSummaryMetric(label: "Time", value: formatDuration(summary.duration))
                    compactSummaryMetric(label: "Sets", value: "\(summary.totalSets)")
                    if let primaryMetric = summary.primaryMetric {
                        compactSummaryMetric(
                            label: primaryMetric.label,
                            value: primaryMetric.formattedValue(
                                style: .detailed,
                                unitPreference: viewModel.unitPreference
                            )
                        )
                    }
                }

                if let estimatedCalories {
                    HStack(spacing: 6) {
                        Text("~\(estimatedCalories) kcal estimated")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.textTertiary)

                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Around \(estimatedCalories) kilocalories, estimated from duration and bodyweight")
                }
            }
        }
    }

    private func compactSummaryMetric(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.horizontal, 8)
        .background(Color.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }

    // MARK: - Title

    private func summaryTitleSection(summary: WorkoutSummaryData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryDateLabel(summary.date))
                .font(.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(1)

            if isEditingTitle {
                TextField("", text: $workoutTitle, prompt: Text(automaticWorkoutTitle).foregroundColor(.textSecondary))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    // Masked while it is being typed. The saved title is content, and
                    // shows up across Home, Calendar and history like any other.
                    .replayMasked()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.border, lineWidth: 1)
                    }
                    .focused($focusedField, equals: .title)
                    .onSubmit {
                        isEditingTitle = false
                        focusedField = nil
                    }
            } else {
                // The title is its own edit affordance. A persistent pencil button held the
                // card's best corner for one of its rarest actions.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditingTitle = true
                    }
                    focusedField = .title
                } label: {
                    HStack(spacing: 8) {
                        Text(resolvedWorkoutTitle)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.leading)

                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Workout title, \(resolvedWorkoutTitle)")
                .accessibilityHint("Double tap to rename")
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
                // The one field on a workout screen whose contents cannot be predicted
                // from its purpose — an injury, a medication, anything.
                .replayMasked()
            }
        }
    }

    // MARK: - Effort

    /// Inline rather than a popover: this is the one input `deloadReadiness` reads, and a
    /// value hidden behind a chevron on a screen people are trying to leave does not get set.
    private var effortSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("How hard did it feel?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Button("Clear") {
                        selectedEffort = nil
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accent)
                    .opacity(selectedEffort == nil ? 0 : 1)
                    .disabled(selectedEffort == nil)
                    .accessibilityHidden(selectedEffort == nil)
                }

                VStack(spacing: 8) {
                    effortRow(1...5)
                    effortRow(6...10)

                    HStack {
                        Text("Easy")
                        Spacer()
                        Text("All out")
                    }
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
                }
            }
        }
    }

    private func effortRow(_ range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(range), id: \.self) { effort in
                let isSelected = selectedEffort == Double(effort)

                Button {
                    selectedEffort = isSelected ? nil : Double(effort)
                } label: {
                    Text("\(effort)")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(isSelected ? .white : .textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isSelected ? Color.accent : Color.bgInput)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? Color.clear : Color.border, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effort \(effort) out of 10")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    // MARK: - Exercise Recap

    private func exerciseRecapSection(summary: WorkoutSummaryData) -> some View {
        return sectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Exercises")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Text(exerciseRecapCaption(summary: summary))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

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
            }
        }
    }

    /// Which lifts set a record, without the amounts. The numbers are the part you have just
    /// spent an hour looking at; which lifts they landed on is the part worth a second look.
    private func exerciseSummaryRow(_ exercise: ExerciseSummary) -> some View {
        HStack(spacing: 10) {
            Text(exercise.exerciseName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            exercisePRTag(isVisible: exercise.hadPR)
        }
        .padding(.vertical, 10)
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

    // MARK: - Details

    /// Notes, effort, suggestion feedback and save-as-template, moved off the recap.
    ///
    /// Notes and effort were unreachable before this: `notesSection` and `effortSection`
    /// existed but were never placed in the body, while `finishWorkout` went on passing both.
    /// `InsightRules+Readiness` is the only reader of `perceivedEffort`, so `deloadReadiness`
    /// had no input from this screen at all.
    private var detailsScreen: some View {
        VStack(spacing: 0) {
            detailsHeaderBar

            ScrollView {
                VStack(spacing: 14) {
                    notesSection

                    effortSection

                    if let summary = displaySummary,
                       !exercisesForFeedback(summary: summary).isEmpty {
                        suggestionFeedbackSection(summary: summary)
                    }

                    saveAsTemplateRow
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            detailsDoneBar
        }
    }

    private var detailsDoneBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)

            Button {
                showDetails = false
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.bg)
    }

    private var detailsHeaderBar: some View {
        ZStack {
            Text("Details")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            HStack {
                Button {
                    showDetails = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.bgInput)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
        }
    }

    private var saveAsTemplateRow: some View {
        Button {
            saveAsTemplateController.begin(defaultName: resolvedWorkoutTitle)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(templateSavedSuccessfully ? "Template saved" : "Save as template")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(templateSavedSuccessfully ? .success : .textPrimary)

                    Text("Reuse this workout later")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                Image(systemName: templateSavedSuccessfully ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(templateSavedSuccessfully ? .success : .textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(templateSavedSuccessfully || saveAsTemplateController.isSaving || isSaving || viewModel.workout?.id == nil)
    }

    // MARK: - Coach

    /// Unbuilt on purpose: no tap target and no destination. A teaser that opens a
    /// "coming soon" screen is worse than one that plainly is not a button.
    private var coachTeaserCard: some View {
        HStack(spacing: 11) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accent.opacity(0.55))

            VStack(alignment: .leading, spacing: 2) {
                Text("Analyse with Coach")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textSecondary)

                Text("What changed, and what's next")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }

            Spacer()

            Text("SOON")
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.bgSubtle)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accent.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyse with Coach, coming soon")
    }

    // MARK: - Details Row

    private var addDetailsRow: some View {
        Button {
            showDetails = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add details")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.textPrimary)

                    Text("Notes, effort, save as template")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isDiscarding)
    }

    // MARK: - Save Bar

    private var saveActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    showDiscardAlert = true
                } label: {
                    Text("Discard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.danger)
                        .frame(width: 96, height: 52)
                        .background(Color.dangerSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.danger.opacity(0.35), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isSaving || isDiscarding)

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
            }
            .padding(.horizontal, 16)
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
        frozenSummary = viewModel.computeSummary()
        frozenTitle = automaticWorkoutTitle

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

        // On success `ActiveWorkoutView` dismisses the whole stack off
        // `isWorkoutFinished`, and dismissing this sheet as well is what made
        // closing a workout play as two separate animations. Only reset the
        // button when the save failed and the sheet is staying put.
        if !viewModel.isWorkoutFinished {
            isSaving = false
        }
    }

    private func discardAndClose() async {
        isDiscarding = true
        frozenSummary = viewModel.computeSummary()
        frozenTitle = automaticWorkoutTitle

        await viewModel.discardWorkout()

        if !viewModel.isWorkoutFinished {
            isDiscarding = false
        }
    }

    // MARK: - Formatting

    private var automaticWorkoutTitle: String {
        viewModel.workout?.displayTitle ?? frozenTitle ?? "Workout"
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

    /// `HealthKitService.estimatedKilocalories` is pure and `static`, so this reuses the
    /// shipped rule rather than restating it. It returns `nil` with no bodyweight logged, and
    /// substituting a population average was considered and rejected there — an absent number
    /// is better than a wrong one, on screen as much as in the Move ring.
    private func loadCalorieEstimate() async {
        guard let summary = viewModel.computeSummary() else { return }

        let start = summary.date
        let end = start.addingTimeInterval(summary.duration)
        let entry = try? await services.bodyweightService.closestBodyweight(to: start)

        guard let kilocalories = HealthKitService.estimatedKilocalories(
            bodyweightKg: entry?.bodyweightKg,
            start: start,
            end: end
        ) else { return }

        estimatedCalories = Int(kilocalories.rounded())
    }

    private func exerciseRecapCaption(summary: WorkoutSummaryData) -> String {
        let logged = "\(summary.exerciseSummaries.count) logged"
        guard summary.prsHit > 0 else { return logged }
        return "\(logged) · \(summary.prsHit) PR\(summary.prsHit == 1 ? "" : "s")"
    }

    /// Builds the pure value the share card draws from. Formatting happens here, in the view
    /// that already knows the unit preference, so the card itself stays free of services.
    private func shareCardData(summary: WorkoutSummaryData) -> WorkoutShareCardData {
        let unit = viewModel.unitPreference

        func lift(_ exercise: ExerciseSummary) -> WorkoutShareCardData.Lift {
            var detail = "\(exercise.setCount) sets"
            if let weight = exercise.bestWeight {
                let weightLabel = UnitConversion.formatWeightLabel(weight, unitPreference: unit)
                detail = exercise.bestReps.map { "\(weightLabel) × \($0)" } ?? weightLabel
            }
            return WorkoutShareCardData.Lift(
                id: exercise.id,
                name: exercise.exerciseName,
                detail: detail,
                setCountLabel: "\(exercise.setCount) sets"
            )
        }

        // The single best record, which is what B3 makes the headline.
        let prExercise = summary.exerciseSummaries.first { $0.hadPR && $0.bestWeight != nil }
            ?? summary.exerciseSummaries.first { $0.hadPR }

        let topLifts = summary.exerciseSummaries
            .sorted { $0.setCount > $1.setCount }
            .prefix(3)
            .map(lift)

        return WorkoutShareCardData(
            title: resolvedWorkoutTitle,
            dateLabel: summaryDateLabel(summary.date),
            durationLabel: formatDuration(summary.duration),
            setCountLabel: "\(summary.totalSets)",
            volumeLabel: summary.primaryMetric?.formattedValue(style: .detailed, unitPreference: unit),
            liftCountLabel: "\(summary.exerciseSummaries.count)",
            prLift: prExercise.map(lift),
            lifts: Array(topLifts),
            extraLiftCount: max(0, summary.exerciseSummaries.count - topLifts.count)
        )
    }

    private func summaryDateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
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
        templateService: any TemplateServiceProtocol,
        analyticsService: any AnalyticsServiceProtocol = NoopAnalyticsService()
    ) async throws -> String {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Workout" : trimmedName
        let templateId = try await templateService.createTemplateFromWorkout(workoutId, name: resolvedName)

        // Second of the three creation paths, previously uncounted.
        let detail = try? await templateService.fetchTemplateDetail(templateId)
        analyticsService.templateCreated(
            exerciseCount: detail?.exercises.count ?? 0,
            source: "save_from_workout"
        )

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
        // An alert's text field is built by `UIAlertController`, so `replayMasked()`
        // never reaches it — see `ReplayPrivacy.swift`.
        content
            .replayPaused(while: controller.showPrompt)
            .alert("Save as Template", isPresented: $controller.showPrompt) {
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
                templateService: services.templateService,
                analyticsService: services.analyticsService
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
