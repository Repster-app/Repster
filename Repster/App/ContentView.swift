// ContentView.swift
// Root content view with 4-tab navigation shell, center FAB overlay,
// and active workout resume on launch.
// Spec: AGENT_RULES S7.2 (Navigation Structure), S7.3 (active workout resume)
// Feature: 007-exercise-list-and-detail WP01, WP07 T030/T032

import SwiftUI
import RevenueCatUI

enum StartupPRRebuildMaintenance {
    static let currentVersion = 1
    static let userDefaultsKey = "startupPRRebuildMaintenanceVersion"

    static func runIfNeeded(
        settingsService: any SettingsServiceProtocol,
        userDefaults: UserDefaults = .standard
    ) async {
        guard userDefaults.integer(forKey: userDefaultsKey) < currentVersion else { return }

        do {
            try await settingsService.rebuildPRs()
            userDefaults.set(currentVersion, forKey: userDefaultsKey)
        } catch {
            dbg("[ContentView] Startup PR rebuild maintenance failed: \(error)")
        }
    }
}

struct ContentView: View {

    // MARK: - Environment

    @Environment(ServiceContainer.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    /// Currently selected tab.
    @State private var selectedTab: MainTab = .home

    /// Date to navigate to when switching to Calendar tab from week strip tap.
    @State private var calendarInitialDate: Date? = nil

    /// Trigger to pop HomeView NavigationStack to root when home tab is re-tapped.
    @State private var homePopToRootTrigger = UUID()

    /// Whether the active workout fullScreenCover is presented.
    @State private var showActiveWorkout = false

    /// Whether the initial check for an active workout has been performed.
    @State private var hasCheckedForActive = false

    /// Whether one-time startup PR maintenance has been scheduled for this app session.
    @State private var hasScheduledStartupPRMaintenance = false

    /// Whether the Exercise List (browse mode) is shown via FAB (T030).
    @State private var showExerciseList = false

    /// Whether the Start Workout sheet is shown (from FAB or Home).
    @State private var showStartWorkoutSheet = false

    /// Whether the Copy Previous sheet is shown (from StartWorkoutSheet).
    @State private var showCopyPreviousSheet = false

    /// Loaded copy previous workouts for the sheet.
    @State private var copyPreviousWorkouts: [CopyPreviousWorkout] = []

    /// Whether the discard confirmation is shown in copy previous flow.
    @State private var showDiscardConfirmation = false

    /// Pending workout ID for copy when discard confirmation is needed.
    @State private var pendingCopyWorkoutId: UUID? = nil

    /// Start options selected from the Start Workout sheet for downstream flows.
    @State private var pendingWorkoutStartOptions: WorkoutStartOptions? = nil

    /// Whether the templates flow should open after StartWorkoutSheet dismisses.
    @State private var pendingTemplateFlow = false

    /// Whether the full-screen templates flow is presented.
    @State private var showTemplateFlow = false

    /// Whether starting a template workout should resume into the active workout after flow dismissal.
    @State private var shouldResumeActiveWorkoutAfterTemplateFlow = false

    /// Whether an active workout currently exists (drives FAB behavior).
    @State private var hasActiveWorkout = false

    /// Incremented when a fullScreenCover dismisses to trigger HomeView refresh.
    @State private var homeRefreshTrigger = UUID()

    /// Exercise IDs to pre-add when starting a workout from browse mode (T032).
    @State private var pendingWorkoutExerciseIds: [UUID] = []

    /// Cached monetization state used to drive messaging and gating.
    @State private var accessSnapshot = AccessSnapshot.placeholder(limit: RevenueCatConfiguration.freeWorkoutLimit)

    /// Whether the RevenueCat paywall is presented.
    @State private var showPaywall = false

    // MARK: - Tab Selection

    /// Custom binding that detects re-selecting the home tab to pop its navigation to root.
    private var tabSelection: Binding<MainTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == selectedTab && newTab == .home {
                    homePopToRootTrigger = UUID()
                }
                selectedTab = newTab
            }
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: tabSelection) {
                HomeView(
                    workoutService: services.workoutService,
                    setService: services.setService,
                    exerciseService: services.exerciseService,
                    chartDataService: services.chartDataService,
                    statsService: services.statsService,
                    refreshTrigger: homeRefreshTrigger,
                    popToRootTrigger: homePopToRootTrigger,
                    workoutAccessMessage: workoutAccessMessage,
                    onStartWorkout: { showActiveWorkout = true },
                    onShowStartWorkoutSheet: { showStartWorkoutSheet = true },
                    onShowExerciseList: { showExerciseList = true },
                    onDayTapped: { date in
                        calendarInitialDate = date
                        selectedTab = .calendar
                    }
                )
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(MainTab.home)

                CalendarView(
                    workoutService: services.workoutService,
                    setService: services.setService,
                    exerciseService: services.exerciseService,
                    statsService: services.statsService,
                    initialDate: $calendarInitialDate
                )
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .tag(MainTab.calendar)

                ChartsTabView(
                    chartDataService: services.chartDataService,
                    exerciseService: services.exerciseService
                )
                    .tabItem {
                        Label("Charts", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tag(MainTab.charts)

                SettingsView(
                    accessSnapshot: $accessSnapshot,
                    settingsService: services.settingsService,
                    bodyweightService: services.bodyweightService,
                    importService: services.importService,
                    workoutHistoryBackupService: services.workoutHistoryBackupService,
                    subscriptionService: services.subscriptionService,
                    accessControlService: services.accessControlService,
                    analyticsService: services.analyticsService,
                    fatigueLearningService: services.fatigueLearningService
                )
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(MainTab.settings)
            }

            // FAB overlay centered on the tab bar
            fabButton
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showExerciseList) {
            NavigationStack {
                ExerciseListView(
                    mode: .browse,
                    onExercisesSelected: { exerciseIds in
                        startWorkoutWithExercises(exerciseIds)
                    },
                    services: services
                )
            }
        }
        .fullScreenCover(isPresented: $showActiveWorkout) {
            ActiveWorkoutView(services: services)
        }
        .sheet(isPresented: $showPaywall, onDismiss: {
            services.analyticsService.paywallDismissed(source: .paywall)
            Task { await refreshMonetizationState(forceSubscriptionRefresh: true) }
        }) {
            PaywallView()
                .onPurchaseStarted { _ in
                    services.analyticsService.purchaseStarted(source: .paywall)
                }
                .onPurchaseCompleted { _ in
                    services.analyticsService.purchaseCompleted(source: .paywall)
                }
                .onPurchaseCancelled {
                    services.analyticsService.purchaseCancelled(source: .paywall)
                }
                .onRestoreStarted {
                    services.analyticsService.restorePurchasesTapped(source: .paywall)
                }
                .onAppear {
                    services.analyticsService.paywallShown(source: .paywall)
                }
        }
        // Refresh active workout state and HomeView when returning from fullScreenCover
        .onChange(of: showActiveWorkout) { _, isShowing in
            if !isShowing {
                homeRefreshTrigger = UUID()
                Task {
                    await refreshActiveWorkoutState()
                    await refreshMonetizationState(forceSubscriptionRefresh: true)
                }
            }
        }
        .onChange(of: showExerciseList) { _, isShowing in
            if !isShowing {
                homeRefreshTrigger = UUID()
                Task {
                    await refreshActiveWorkoutState()
                    await refreshMonetizationState(forceSubscriptionRefresh: false)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await services.refreshUnitPreference()
                await refreshMonetizationState(forceSubscriptionRefresh: true)
            }
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            trackScreen(for: newTab)
            guard oldTab == .settings, newTab == .home else { return }
            Task { await refreshMonetizationState(forceSubscriptionRefresh: true) }
        }
        .task {
            if !hasScheduledStartupPRMaintenance {
                hasScheduledStartupPRMaintenance = true
                let settingsService = services.settingsService
                Task(priority: .utility) {
                    await StartupPRRebuildMaintenance.runIfNeeded(settingsService: settingsService)
                }
            }

            // Check for active workout on launch (AGENT_RULES S7.3)
            guard !hasCheckedForActive else { return }
            hasCheckedForActive = true
            await services.refreshUnitPreference()
            await refreshActiveWorkoutState()
            await refreshMonetizationState(forceSubscriptionRefresh: true)
            if hasActiveWorkout {
                showActiveWorkout = true
            }
            trackScreen(for: selectedTab)
        }
        .onAppear {
            configureTabBarAppearance()
        }
        .sheet(isPresented: $showStartWorkoutSheet, onDismiss: {
            if pendingTemplateFlow {
                pendingTemplateFlow = false
                showTemplateFlow = true
            }
        }) {
            StartWorkoutSheet(
                accessMessage: workoutAccessMessage,
                onStartEmpty: { options in
                    Task { await startEmptyWorkout(options: options) }
                },
                onCopyPrevious: { options in
                    Task { await beginCopyPreviousFlow(options: options) }
                },
                onTemplates: { options in
                    Task { await beginTemplateFlow(options: options) }
                }
            )
        }
        .sheet(isPresented: $showCopyPreviousSheet, onDismiss: {
            pendingWorkoutStartOptions = nil
        }) {
            CopyPreviousSheet(
                workouts: copyPreviousWorkouts,
                unitPreference: services.unitPreference,
                showDiscardConfirmation: $showDiscardConfirmation,
                onWorkoutSelected: { workoutId in
                    Task { await copyWorkout(workoutId) }
                },
                onDiscardAndCopy: {
                    Task { await discardActiveAndCopy() }
                },
                onCancelDiscard: {
                    showDiscardConfirmation = false
                    pendingCopyWorkoutId = nil
                }
            )
        }
        .fullScreenCover(isPresented: $showTemplateFlow, onDismiss: {
            pendingWorkoutStartOptions = nil
            if shouldResumeActiveWorkoutAfterTemplateFlow {
                shouldResumeActiveWorkoutAfterTemplateFlow = false
                hasActiveWorkout = true
                showActiveWorkout = true
            }
        }) {
            TemplateFlowView(
                templateService: services.templateService,
                exerciseService: services.exerciseService,
                beforeStartWorkout: {
                    await ensureWorkoutCreationAccess {
                        showTemplateFlow = false
                    }
                },
                onStartWorkout: {
                    shouldResumeActiveWorkoutAfterTemplateFlow = true
                    showTemplateFlow = false
                },
                workoutStartOptions: pendingWorkoutStartOptions ?? .default,
                analyticsService: services.analyticsService
            )
        }
    }

    // MARK: - FAB Button

    /// Center FAB overlay positioned on the tab bar.
    /// Navigates to ExerciseListView(mode: .browse) (T030).
    private var fabButton: some View {
        Button {
            fabTapped()
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accent)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .offset(y: -24)
    }

    // MARK: - Actions

    /// Refresh whether an active workout exists. Called on launch and when covers dismiss.
    @MainActor
    private func refreshActiveWorkoutState() async {
        hasActiveWorkout = (try? await services.workoutService.getActiveWorkout()) != nil
    }

    @MainActor
    private func refreshMonetizationState(forceSubscriptionRefresh: Bool) async {
        if forceSubscriptionRefresh {
            _ = await services.subscriptionService.refreshSubscriptionStatus()
        }
        accessSnapshot = await services.accessControlService.currentAccessSnapshot()
    }

    private var workoutAccessMessage: String? {
        switch accessSnapshot.state {
        case .subscribed:
            return nil
        case .free(let remaining):
            return remaining == 1 ? "1 free workout left" : "\(remaining) free workouts left"
        case .paywallRequired:
            return "Unlock Repster to start a new workout"
        }
    }

    /// FAB tap handler — if active workout exists, resume it; otherwise show Start Workout sheet.
    private func fabTapped() {
        if hasActiveWorkout {
            showActiveWorkout = true
        } else {
            showStartWorkoutSheet = true
        }
    }

    @MainActor
    private func ensureWorkoutCreationAccess(dismissBeforePaywall: (() -> Void)? = nil) async -> Bool {
        let canStart = await services.accessControlService.canStartNewWorkout()
        await refreshMonetizationState(forceSubscriptionRefresh: false)

        guard canStart else {
            dismissBeforePaywall?()
            showPaywall = true
            return false
        }

        return true
    }

    @MainActor
    private func startEmptyWorkout(options: WorkoutStartOptions) async {
        guard await ensureWorkoutCreationAccess() else { return }

        do {
            _ = try await services.workoutService.startWorkout(options: options)
            trackWorkoutStarted(
                source: .empty,
                templateUsed: false,
                copiedPrevious: false,
                options: options
            )
            hasActiveWorkout = true
            showActiveWorkout = true
        } catch {
            dbg("[ContentView] Start empty workout failed: \(error)")
        }
    }

    @MainActor
    private func beginCopyPreviousFlow(options: WorkoutStartOptions) async {
        guard await ensureWorkoutCreationAccess() else { return }
        pendingWorkoutStartOptions = options
        await loadCopyPreviousWorkouts()
        showCopyPreviousSheet = true
    }

    @MainActor
    private func beginTemplateFlow(options: WorkoutStartOptions) async {
        guard await ensureWorkoutCreationAccess() else { return }
        pendingWorkoutStartOptions = options
        pendingTemplateFlow = true
    }

    /// Start a workout with selected exercises from browse mode (T032).
    ///
    /// Creates a new workout via WorkoutService, stores the exercise IDs
    /// to be added by ActiveWorkoutView, dismisses the exercise list,
    /// and presents the active workout fullScreenCover.
    @MainActor
    private func startWorkoutWithExercises(_ exerciseIds: [UUID]) {
        Task {
            guard await ensureWorkoutCreationAccess(dismissBeforePaywall: {
                showExerciseList = false
            }) else { return }

            do {
                // 1. Create a new workout
                let workout = try await services.workoutService.startWorkout()
                _ = workout // workout is persisted; ActiveWorkoutView will load it

                // 2. Add exercises to the workout before showing it
                // We use SetService to create initial sets for each exercise
                for (index, exerciseId) in exerciseIds.enumerated() {
                    let set = WorkoutSet(
                        workoutId: workout.id,
                        exerciseId: exerciseId,
                        date: Date(),
                        setType: .working,
                        orderInWorkout: index + 1,
                        orderInExercise: 1,
                        completed: false
                    )
                    _ = try await services.setService.save(set)
                }

                trackWorkoutStarted(
                    source: .exerciseList,
                    templateUsed: false,
                    copiedPrevious: false,
                    options: .default
                )

                // 3. Dismiss exercise list and show active workout
                showExerciseList = false
                // Small delay to allow navigation to settle before presenting fullScreenCover
                try await Task.sleep(for: .milliseconds(300))
                showActiveWorkout = true
            } catch {
                dbg("[ContentView] Failed to start workout: \(error)")
            }
        }
    }

    // MARK: - Copy Previous

    /// Load completed workouts for the Copy Previous sheet.
    @MainActor
    private func loadCopyPreviousWorkouts() async {
        do {
            let allWorkouts = try await services.workoutService.fetchAllWorkouts(limit: nil, offset: nil)
            let completed = allWorkouts
                .filter { $0.status == .completed }
                .sorted { $0.date > $1.date }

            var items: [CopyPreviousWorkout] = []
            for workout in completed {
                let sets = try await services.setService.fetchSets(for: workout.id)
                let workingSetsWithData = sets.filter { $0.setType == .working && $0.hasData }
                let exerciseIds = Set(sets.map(\.exerciseId))

                var exerciseLookup: [UUID: Exercise] = [:]
                var muscleGroups: [String] = []
                for exerciseId in exerciseIds {
                    if let exercise = try await services.exerciseService.fetchExercise(exerciseId) {
                        exerciseLookup[exerciseId] = exercise
                        if let muscle = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle),
                           !muscleGroups.contains(muscle) {
                            muscleGroups.append(muscle)
                        }
                    }
                }
                let aggregate = WorkoutAggregateSummary.summarize(
                    sets: workingSetsWithData,
                    exercisesById: exerciseLookup
                )

                items.append(CopyPreviousWorkout(
                    id: workout.id,
                    workout: workout,
                    displayTitle: workout.displayTitle,
                    date: workout.date,
                    exerciseCount: exerciseIds.count,
                    setCount: workingSetsWithData.count,
                    primaryMetric: aggregate.primaryMetric,
                    muscleGroups: muscleGroups
                ))
            }

            copyPreviousWorkouts = items
        } catch {
            dbg("[ContentView] Failed to load copy previous workouts: \(error)")
        }
    }

    /// Copy a past workout. If an active workout exists, triggers confirmation dialog.
    private func copyWorkout(_ workoutId: UUID) async {
        do {
            let activeWorkout = try await services.workoutService.getActiveWorkout()
            if activeWorkout != nil {
                pendingCopyWorkoutId = workoutId
                showDiscardConfirmation = true
                return
            }
            try await performCopy(workoutId)
        } catch {
            dbg("[ContentView] Copy failed: \(error)")
        }
    }

    /// Called when user confirms discarding the active workout to proceed with copy.
    private func discardActiveAndCopy() async {
        guard let pendingId = pendingCopyWorkoutId else { return }
        do {
            if let activeWorkout = try await services.workoutService.getActiveWorkout() {
                let activeSets = try await services.setService.fetchSets(for: activeWorkout.id)
                let priorContext = WorkoutStartContextStore.recall()
                services.analyticsService.workoutDiscarded(
                    durationSeconds: Date().timeIntervalSince(activeWorkout.startTime ?? activeWorkout.date),
                    setCount: activeSets.count,
                    date: activeWorkout.date,
                    source: priorContext.source,
                    templateUsed: priorContext.templateUsed
                )
                WorkoutStartContextStore.clear()
                try await services.workoutService.deleteWorkout(activeWorkout.id)
            }
            showDiscardConfirmation = false
            pendingCopyWorkoutId = nil
            try await performCopy(pendingId)
        } catch {
            dbg("[ContentView] Discard+copy failed: \(error)")
        }
    }

    /// Perform the actual copy of a source workout, then show active workout.
    private func performCopy(_ sourceWorkoutId: UUID) async throws {
        let sourceSets = try await services.setService.fetchSets(for: sourceWorkoutId)
        let workingSets = sourceSets
            .filter { $0.setType == .working }
            .sorted { ($0.orderInWorkout, $0.orderInExercise) < ($1.orderInWorkout, $1.orderInExercise) }

        let startOptions = pendingWorkoutStartOptions ?? .default
        let newWorkout = try await services.workoutService.startWorkout(options: startOptions)

        for sourceSet in workingSets {
            let newSet = WorkoutSet(
                workoutId: newWorkout.id,
                exerciseId: sourceSet.exerciseId,
                weight: sourceSet.weight,
                reps: sourceSet.reps,
                setType: .working,
                orderInWorkout: sourceSet.orderInWorkout,
                orderInExercise: sourceSet.orderInExercise,
                completed: false
            )
            _ = try await services.setService.save(newSet)
        }

        trackWorkoutStarted(
            source: .copyPrevious,
            templateUsed: false,
            copiedPrevious: true,
            options: startOptions
        )

        hasActiveWorkout = true
        showCopyPreviousSheet = false
        showActiveWorkout = true
        pendingWorkoutStartOptions = nil
    }

    // MARK: - Tab Bar Appearance

    /// Configure UIKit tab bar appearance for dark mode styling.
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.bgCard)

        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color.textTertiary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color.textTertiary)
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.accent)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.accent)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private func trackScreen(for tab: MainTab) {
        switch tab {
        case .home:
            services.analyticsService.screen(.home)
        case .calendar:
            services.analyticsService.screen(.calendar)
        case .charts:
            services.analyticsService.screen(.charts)
        case .settings:
            services.analyticsService.screen(.settings)
        }
    }

    private func trackWorkoutStarted(
        source: WorkoutStartSource,
        templateUsed: Bool,
        copiedPrevious: Bool,
        options: WorkoutStartOptions
    ) {
        WorkoutStartContextStore.remember(source: source, templateUsed: templateUsed)
        services.analyticsService.workoutStarted(
            source: source,
            templateUsed: templateUsed,
            copiedPrevious: copiedPrevious,
            countTowardProgression: options.countTowardProgressionHistory
        )
    }
}
