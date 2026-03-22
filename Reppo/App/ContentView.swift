// ContentView.swift
// Root content view with 4-tab navigation shell, center FAB overlay,
// and active workout resume on launch.
// Spec: AGENT_RULES S7.2 (Navigation Structure), S7.3 (active workout resume)
// Feature: 007-exercise-list-and-detail WP01, WP07 T030/T032

import SwiftUI

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
            print("[ContentView] Startup PR rebuild maintenance failed: \(error)")
        }
    }
}

struct ContentView: View {

    // MARK: - Environment

    @Environment(ServiceContainer.self) private var services

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
                    settingsService: services.settingsService,
                    bodyweightService: services.bodyweightService,
                    importService: services.importService,
                    workoutHistoryBackupService: services.workoutHistoryBackupService,
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
        // Refresh active workout state and HomeView when returning from fullScreenCover
        .onChange(of: showActiveWorkout) { _, isShowing in
            if !isShowing {
                homeRefreshTrigger = UUID()
                Task { await refreshActiveWorkoutState() }
            }
        }
        .onChange(of: showExerciseList) { _, isShowing in
            if !isShowing {
                homeRefreshTrigger = UUID()
                Task { await refreshActiveWorkoutState() }
            }
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
            await refreshActiveWorkoutState()
            if hasActiveWorkout {
                showActiveWorkout = true
            }
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
                onStartEmpty: {
                    Task {
                        do {
                            _ = try await services.workoutService.startWorkout()
                            hasActiveWorkout = true
                            showActiveWorkout = true
                        } catch {
                            print("[ContentView] Start empty workout failed: \(error)")
                        }
                    }
                },
                onCopyPrevious: {
                    Task { await loadCopyPreviousWorkouts() }
                    showCopyPreviousSheet = true
                },
                onTemplates: {
                    pendingTemplateFlow = true
                }
            )
        }
        .sheet(isPresented: $showCopyPreviousSheet) {
            CopyPreviousSheet(
                workouts: copyPreviousWorkouts,
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
            if shouldResumeActiveWorkoutAfterTemplateFlow {
                shouldResumeActiveWorkoutAfterTemplateFlow = false
                hasActiveWorkout = true
                showActiveWorkout = true
            }
        }) {
            TemplateFlowView(
                templateService: services.templateService,
                exerciseService: services.exerciseService,
                onStartWorkout: {
                    shouldResumeActiveWorkoutAfterTemplateFlow = true
                    showTemplateFlow = false
                }
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
    private func refreshActiveWorkoutState() async {
        hasActiveWorkout = (try? await services.workoutService.getActiveWorkout()) != nil
    }

    /// FAB tap handler — if active workout exists, resume it; otherwise show Start Workout sheet.
    private func fabTapped() {
        if hasActiveWorkout {
            showActiveWorkout = true
        } else {
            showStartWorkoutSheet = true
        }
    }

    /// Start a workout with selected exercises from browse mode (T032).
    ///
    /// Creates a new workout via WorkoutService, stores the exercise IDs
    /// to be added by ActiveWorkoutView, dismisses the exercise list,
    /// and presents the active workout fullScreenCover.
    private func startWorkoutWithExercises(_ exerciseIds: [UUID]) {
        Task {
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

                // 3. Dismiss exercise list and show active workout
                showExerciseList = false
                // Small delay to allow navigation to settle before presenting fullScreenCover
                try await Task.sleep(for: .milliseconds(300))
                showActiveWorkout = true
            } catch {
                print("[ContentView] Failed to start workout: \(error)")
            }
        }
    }

    // MARK: - Copy Previous

    /// Load completed workouts for the Copy Previous sheet.
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
            print("[ContentView] Failed to load copy previous workouts: \(error)")
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
            print("[ContentView] Copy failed: \(error)")
        }
    }

    /// Called when user confirms discarding the active workout to proceed with copy.
    private func discardActiveAndCopy() async {
        guard let pendingId = pendingCopyWorkoutId else { return }
        do {
            if let activeWorkout = try await services.workoutService.getActiveWorkout() {
                try await services.workoutService.deleteWorkout(activeWorkout.id)
            }
            showDiscardConfirmation = false
            pendingCopyWorkoutId = nil
            try await performCopy(pendingId)
        } catch {
            print("[ContentView] Discard+copy failed: \(error)")
        }
    }

    /// Perform the actual copy of a source workout, then show active workout.
    private func performCopy(_ sourceWorkoutId: UUID) async throws {
        let sourceSets = try await services.setService.fetchSets(for: sourceWorkoutId)
        let workingSets = sourceSets
            .filter { $0.setType == .working }
            .sorted { ($0.orderInWorkout, $0.orderInExercise) < ($1.orderInWorkout, $1.orderInExercise) }

        let newWorkout = try await services.workoutService.startWorkout()

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

        hasActiveWorkout = true
        showCopyPreviousSheet = false
        showActiveWorkout = true
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
}
