// ActiveWorkoutView.swift
// Main focused screen for the active workout, assembling all sub-views.
// Spec: FR-001 (focused workout), FR-013 (elapsed timer), FR-007 (add exercises), FR-006 (rest timer), FR-008 (finish)
// Contract: WP05 T022 (main layout), T023 (header bar), WP06 T025-T029 (sub-tabs + picker), T030 (rest timer), WP07 T035 (finish flow)
//
// Composes: header bar + ExerciseTabStripView (WP04) + sub-tab picker (WP06) + content area
// Presented as fullScreenCover — no bottom navigation visible.
// ViewModel created from injected service protocols.

import SwiftUI

enum ActiveWorkoutBottomAccessoryLayout {
    /// Whether the rest timer belongs on screen for this state.
    ///
    /// The timer used to have a full and a compact height, and this picked between them
    /// based on the keyboard. It is one height now, so only the `.finished` rule survives:
    /// a completed rest is suppressed while the set keypad is open, because the message is
    /// redundant mid-entry — you are already logging the next set — and a bar appearing
    /// underneath would shift the keypad while a thumb is on it.
    static func shouldShowRestTimer(
        for state: RestTimerState,
        isKeyboardVisible: Bool
    ) -> Bool {
        switch state {
        case .idle:
            return false
        case .running, .paused:
            return true
        case .finished:
            return !isKeyboardVisible
        }
    }

    /// Whether the superset prompt belongs on screen.
    ///
    /// Same keypad rule as `.finished`, for the same reason: mid-entry the message is redundant —
    /// you are already logging — and a bar appearing underneath would shift the keypad while a
    /// thumb is on it. The rest timer wins the slot outright if one is somehow running, which it
    /// should not be: the branch that raises a prompt is the branch that starts no timer.
    static func shouldShowSupersetPrompt(
        hasPrompt: Bool,
        restTimerState: RestTimerState,
        isKeyboardVisible: Bool
    ) -> Bool {
        guard hasPrompt, !isKeyboardVisible else { return false }
        if case .idle = restTimerState { return true }
        return false
    }
}

/// The active workout screen — a focused full-screen experience for logging sets.
///
/// Layout (top to bottom):
/// 1. Header bar: back button, elapsed timer, +Exercise, Finish
/// 2. Exercise tab strip (WP04)
/// 3. Sub-tab picker: [Sets | History | Charts] (WP06 T025)
/// 4. Sub-tab content: SetTableView / ExerciseHistoryView / ExerciseChartsView (WP06 T026/T027)
/// 5. Rest timer overlay (WP06 T030)
///
/// Presented as `.fullScreenCover` to hide bottom navigation (FR-001).
struct ActiveWorkoutView: View {

    // MARK: - State

    /// The ViewModel managing workout data and actions.
    @State private var viewModel: ActiveWorkoutViewModel

    /// Currently selected sub-tab for the per-exercise content area (WP06 T025).
    @State private var selectedSubTab: ExerciseSubTab = .sets

    /// Controls the exercise settings sheet presentation.
    @State private var showExerciseSettingsSheet: Bool = false

    /// Shared custom keyboard state for set input.
    @StateObject private var setKeyboardManager = SetEntryKeyboardManager()

    // MARK: - Dependencies

    /// Service container reference for ExerciseListView picker (WP06 T029).
    private let services: ServiceContainer

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Init

    init(services: ServiceContainer) {
        _viewModel = State(initialValue: ActiveWorkoutViewModel(
            workoutService: services.workoutService,
            setService: services.setService,
            exerciseService: services.exerciseService,
            statsService: services.statsService,
            prService: services.prService,
            healthProfileRepo: services.healthProfileRepo,
            settingsService: services.settingsService,
            loadPrescriptionService: services.loadPrescriptionService,
            accessControlService: services.accessControlService,
            analyticsService: services.analyticsService,
            fatigueLearningService: services.fatigueLearningService
        ))
        self.services = services
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header bar (T023)
            headerBar

            // Exercise tab strip (WP04)
            ExerciseTabStripView(dataSource: viewModel, services: services)

            if viewModel.currentExercise != nil {
                // Sub-tab picker: [Sets | History | Charts] (T025)
                subTabPicker

                // Sub-tab content (T025/T026/T027)
                subTabContent
            } else if !viewModel.isLoading && !viewModel.isWorkoutFinished {
                // Finishing clears the exercise list a beat before this screen
                // dismisses. Prompting for exercises behind the closing summary
                // reads as the workout having been thrown away.
                emptyExerciseState
            }

            Spacer(minLength: 0)
        }
        .background(Color.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomAccessoryArea
        }
        .animation(.easeInOut(duration: 0.2), value: bottomAccessoryAnimationKey)
        .task {
            services.analyticsService.screen(.activeWorkout)
            await viewModel.loadActiveWorkout()
        }
        // Recalculate rest timer when returning from background (WP06 T030)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.recalculateTimerAfterBackground()
            }
        }
        // Reset sub-tab to .sets when switching exercises (T028).
        // Keyed on identity, not index: reordering past the selection or replacing in place changes
        // the exercise while the integer stays put, and this must still run — the keypad especially,
        // which lives outside the `.id()`-keyed set table and would otherwise stay bound to a row
        // that is no longer on screen.
        .onChange(of: viewModel.selectedExerciseId) { _, _ in
            selectedSubTab = .sets
            viewModel.clearSubTabCache()
            setKeyboardManager.hide()
        }
        .onChange(of: selectedSubTab) { _, newTab in
            if newTab != .sets {
                setKeyboardManager.hide()
            }
            // Whether people consult their own training data while training is the
            // question this app's premise rests on, and nothing measured it.
            if let interaction = newTab.analyticsInteraction {
                services.analyticsService.recordWorkoutInteraction(interaction)
            }
        }
        .onChange(of: services.unitPreference) { _, _ in
            Task {
                await viewModel.refreshDisplaySettings()
                await viewModel.refreshWeightSuggestions(
                    invalidateCache: true,
                    presentation: .preserveExisting
                )
            }
        }
        // Exercise picker sheet — replaced with ExerciseListView (T029)
        .sheet(isPresented: $viewModel.showAddExerciseSheet) {
            exercisePickerSheet
        }
        // Repster's own notification explainer, raised by the first rest timer (§D2).
        .sheet(isPresented: $viewModel.showRestAlarmPrompt) {
            RestAlarmPromptView(
                onEnable: { Task { await viewModel.enableRestAlarmAuthorization() } },
                onDecline: { viewModel.declineRestAlarmAuthorization() },
                isRequesting: viewModel.isRequestingRestAlarmAuthorization
            )
            .presentationDetents([.medium, .large])
        }
        // Finish workout summary sheet (WP07 T032)
        .sheet(isPresented: $viewModel.showFinishSheet) {
            WorkoutSummarySheet(viewModel: viewModel)
                .onAppear {
                    services.analyticsService.screen(.workoutSummary)
                }
        }
        // Dismiss active workout screen after finish (WP07 T035)
        .onChange(of: viewModel.isWorkoutFinished) { _, finished in
            if finished {
                dismiss()
            }
        }
    }

    // MARK: - Sub-Tab Picker (T025)

    /// Segmented picker for [Sets | History | Charts] with exercise settings gear icon.
    private var subTabPicker: some View {
        HStack(spacing: 8) {
            WorkoutSubTabBar(selectedTab: $selectedSubTab)
                .frame(maxWidth: .infinity)

            // Exercise settings gear icon
            Button {
                services.analyticsService.recordWorkoutInteraction(.exerciseSettingsOpens)
                showExerciseSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showExerciseSettingsSheet) {
                if let exercise = viewModel.currentExercise {
                    ExerciseSettingsSheet(
                        exercise: exercise,
                        services: services,
                        onSave: {
                            Task {
                                await viewModel.refreshCurrentExerciseConfigurationData()
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    // MARK: - Sub-Tab Content (T025/T026/T027)

    /// Content area that switches based on selected sub-tab.
    @ViewBuilder
    private var subTabContent: some View {
        switch selectedSubTab {
        case .sets:
            ScrollView {
                SetTableView(
                    dataSource: viewModel,
                    keyboardManager: setKeyboardManager
                )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                // Smart Suggestions module (opt-in, read-only suggestions)
                WeightSuggestionModuleView(
                    data: viewModel.weightSuggestionData,
                    unitPreference: viewModel.unitPreference,
                    isAdminModeEnabled: viewModel.suggestionAdminModeEnabled,
                    isLoading: viewModel.isLoadingWeightSuggestions,
                    isRefreshing: viewModel.isRefreshingWeightSuggestions,
                    onRefresh: {
                        services.analyticsService.recordWorkoutInteraction(.suggestionRefreshes)
                        Task {
                            await viewModel.refreshWeightSuggestions(
                                invalidateCache: true,
                                presentation: .preserveExisting
                            )
                        }
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .id(viewModel.currentExercise?.id)
            .task(id: viewModel.currentExercise?.id) {
                await viewModel.loadWeightSuggestions()
            }

        case .history:
            // Exercise history from past workouts (T026)
            ExerciseHistoryView(
                historyWorkouts: viewModel.subTabHistory,
                exercise: viewModel.currentExercise,
                unitPreference: viewModel.unitPreference
            )
                .task(id: viewModel.currentExercise?.id) {
                    await viewModel.loadHistoryForCurrentExercise()
                }

        case .prs:
            // Exercise PR table — reuses ExercisePRsView from ExerciseDetailView
            ExercisePRsView(
                prTable: viewModel.subTabPRTable,
                unitPreference: viewModel.unitPreference,
                isPerSide: viewModel.currentExercise?.unilateral == true
                    && viewModel.currentExercise?.supportsUnilateralLogging == true
            )
                .task(id: viewModel.currentExercise?.id) {
                    await viewModel.loadPRsForCurrentExercise()
                }

        case .charts:
            // Exercise charts: full-featured chart from Charts tab (replaces old ExerciseChartsView)
            if let exercise = viewModel.currentExercise {
                EmbeddedExerciseChartView(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCategory: exercise.primaryMuscle ?? "",
                    chartDataService: services.chartDataService,
                    exerciseService: services.exerciseService
                )
                .id(exercise.id) // Recreate when exercise changes
            }
        }
    }

    private var isSetKeyboardVisible: Bool {
        selectedSubTab == .sets && setKeyboardManager.context?.trackedField != nil
    }

    private var isRestTimerVisible: Bool {
        ActiveWorkoutBottomAccessoryLayout.shouldShowRestTimer(
            for: viewModel.restTimer,
            isKeyboardVisible: isSetKeyboardVisible
        )
    }

    private var isSupersetPromptVisible: Bool {
        ActiveWorkoutBottomAccessoryLayout.shouldShowSupersetPrompt(
            hasPrompt: viewModel.supersetPrompt != nil,
            restTimerState: viewModel.restTimer,
            isKeyboardVisible: isSetKeyboardVisible
        )
    }

    private var bottomAccessoryAnimationKey: String {
        "\(selectedSubTab)-\(isSetKeyboardVisible)-\(isRestTimerVisible)-\(isSupersetPromptVisible)"
    }

    @ViewBuilder
    private var bottomAccessoryArea: some View {
        VStack(spacing: 0) {
            if isRestTimerVisible {
                RestTimerView(
                    state: viewModel.restTimer,
                    onAddTime: {
                        services.analyticsService.recordWorkoutInteraction(.restTimerAdjusts)
                        viewModel.addTime($0)
                    },
                    onSubtractTime: {
                        services.analyticsService.recordWorkoutInteraction(.restTimerAdjusts)
                        viewModel.subtractTime($0)
                    },
                    onSetDuration: {
                        services.analyticsService.recordWorkoutInteraction(.restTimerAdjusts)
                        viewModel.setTimerDuration($0)
                    },
                    onTogglePause: { viewModel.toggleRestTimerPause() },
                    // Counted here rather than in `dismissTimer()`, which is also the
                    // internal cleanup path for finish, discard and set completion —
                    // that would add a phantom skip to every workout.
                    onDismiss: {
                        services.analyticsService.recordWorkoutInteraction(.restTimerSkips)
                        viewModel.dismissTimer()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Same slot, same height as the timer above — inside a superset there is no rest to
            // count, so the slot names the partner instead and nothing on screen moves.
            if isSupersetPromptVisible, let prompt = viewModel.supersetPrompt {
                SupersetPromptView(
                    nextExerciseName: prompt.nextExerciseName,
                    onTap: {
                        services.analyticsService.recordWorkoutInteraction(.supersetPromptTaps)
                        viewModel.goToSupersetPartner()
                    },
                    onDismiss: { viewModel.dismissSupersetPrompt() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if selectedSubTab == .sets {
                SetEntryKeyboardOverlay(manager: setKeyboardManager)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Exercise Picker Sheet (T029)

    /// Full exercise browser replacing the stub ExercisePickerSheet.
    ///
    /// Uses ExerciseListView in `.addToWorkout` mode inside a NavigationStack.
    /// When exercises are selected, adds them to the workout via the ViewModel.
    private var exercisePickerSheet: some View {
        NavigationStack {
            ExerciseListView(
                mode: .addToWorkout,
                onExercisesSelected: { selectedIds in
                    Task {
                        await viewModel.addExercises(selectedIds)
                        viewModel.showAddExerciseSheet = false
                    }
                },
                services: services
            )
        }
    }

    // MARK: - Header Bar (T023)

    /// Top bar with back button, elapsed timer, +Exercise button, and Finish button.
    private var headerBar: some View {
        HStack(spacing: 8) {
            // Back / dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .frame(width: 44, height: 36)
            }

            Spacer()

            // Elapsed timer (T024)
            ElapsedTimerView(
                elapsedTime: viewModel.workout == nil ? nil : viewModel.elapsedTime,
                isPaused: viewModel.isWorkoutPaused,
                onTap: { viewModel.toggleWorkoutPause() }
            )

            Spacer()

            // +Exercise button
            Button {
                viewModel.presentAddExerciseSheet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accent)
                    .frame(width: 44, height: 36)
            }

            // Finish Workout button
            Button {
                viewModel.showFinishSheet = true
            } label: {
                Text("Finish")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.accent)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    /// Shown when there are no exercises in the workout yet.
    private var emptyExerciseState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "dumbbell")
                .font(.system(size: 48))
                .foregroundColor(.textTertiary)

            Text("No exercises yet")
                .font(.headline)
                .foregroundColor(.textSecondary)

            Text("Add exercises to start logging sets")
                .font(.subheadline)
                .foregroundColor(.textTertiary)

            Button {
                viewModel.presentAddExerciseSheet()
            } label: {
                Text("Add Exercises")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Color.accent)
                    .cornerRadius(10)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

}

private struct WorkoutSubTabBar: View {
    @Binding var selectedTab: ExerciseSubTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ExerciseSubTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? Color.textPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 32)
                        .background(selectedTab == tab ? Color.bgSubtle : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.bgCard.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}
