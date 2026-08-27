// ContentView.swift
// Root content view with 4-tab navigation shell, center FAB overlay,
// and active workout resume on launch.
// Spec: AGENT_RULES S7.2 (Navigation Structure), S7.3 (active workout resume)
// Feature: 007-exercise-list-and-detail WP01, WP07 T030/T032

import SwiftUI
import RevenueCatUI
import StoreKit

/// One-time, versioned rebuild of derived data on first launch after an update.
///
/// Version 2 also rebuilds stats. Until it shipped, `SetService.create` ran the full save
/// pipeline on rows it had just created, so every Copy Previous set was PR-evaluated and
/// counted in stats before being performed — and counted a second time when the user
/// completed it. Stored PRs and aggregates on existing installs carry that inflation, and
/// arithmetic-delta stats can't self-heal, so both are recomputed from the logged sets.
///
/// The UserDefaults key predates the stats rebuild and is left alone: it's persisted on
/// device, and the version number is what gates the work.
enum StartupPRRebuildMaintenance {
    static let currentVersion = 2
    static let userDefaultsKey = "startupPRRebuildMaintenanceVersion"

    static func runIfNeeded(
        settingsService: any SettingsServiceProtocol,
        userDefaults: UserDefaults = .standard
    ) async {
        guard userDefaults.integer(forKey: userDefaultsKey) < currentVersion else { return }

        do {
            try await settingsService.rebuildPRs()
            try await settingsService.rebuildStats()
            userDefaults.set(currentVersion, forKey: userDefaultsKey)
        } catch {
            // Version stays unstamped, so this retries on the next launch.
            dbg("[ContentView] Startup rebuild maintenance failed: \(error)")
        }
    }
}

/// Clears the learned fatigue rates once, on the first launch after the suggestion model changes.
///
/// The rates are calibrated *around* the engine's constants, so a model change makes them answers
/// to a question the engine no longer asks — keeping them would apply a correction tuned for the
/// old model to the new one. Every behaviour change in the epoch trips this, which is precisely why
/// they ship as one release: done separately, the calibration is burned once per change and no
/// regression can be attributed to anything.
///
/// It calls the *preserving* reset. The prediction record — what the model said next to what
/// actually happened — is kept and stamped with its epoch. Rates rebuild themselves from future
/// sessions; that record cannot be recomputed from anything once deleted.
enum StartupSuggestionModelMaintenance {
    static let userDefaultsKey = "suggestionModelEpochApplied"

    static func runIfNeeded(
        fatigueLearningService: FatigueLearningService,
        userDefaults: UserDefaults = .standard
    ) async {
        guard userDefaults.integer(forKey: userDefaultsKey) < SuggestionModelEpoch.current else { return }

        do {
            try await fatigueLearningService.resetLearnedRatesPreservingHistory()
            userDefaults.set(SuggestionModelEpoch.current, forKey: userDefaultsKey)
        } catch {
            // Epoch stays unstamped, so this retries on the next launch. Retrying is harmless:
            // clearing already-cleared rates is a no-op.
            dbg("[ContentView] Suggestion model maintenance failed: \(error)")
        }
    }
}

struct ContentView: View {

    // MARK: - Environment

    @Environment(ServiceContainer.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    /// Decides when an App Store rating prompt is appropriate. Held here rather
    /// than in ServiceContainer because the prompt is inherently a view-layer
    /// concern — it needs the SwiftUI `requestReview` environment action.
    @State private var reviewPrompt: any ReviewPromptServiceProtocol = ReviewPromptService()

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

    /// Whether the discard confirmation is shown in copy previous flow.
    @State private var showDiscardConfirmation = false

    /// Pending workout ID for copy when discard confirmation is needed.
    @State private var pendingCopyWorkoutId: UUID? = nil

    /// Start options selected from the Start Workout sheet for downstream flows.
    @State private var pendingWorkoutStartOptions: WorkoutStartOptions? = nil

    /// Whether the templates flow should open after StartWorkoutSheet dismisses.
    @State private var pendingTemplateFlow = false

    /// Whether the Copy Previous sheet should open after StartWorkoutSheet dismisses.
    @State private var pendingCopyPreviousFlow = false

    /// Whether StartWorkoutSheet has finished animating out. The copy-previous handoff is
    /// queued behind an async access check that can outlive the dismissal, so whichever of
    /// the two finishes last is the one that presents.
    @State private var startWorkoutSheetDidDismiss = false

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

    /// Whether the What's New sheet is presented.
    @State private var showWhatsNew = false

    /// Repster's own Apple Health offer, raised on the first return to Home after a
    /// workout has been completed. Held rather than built inline so a connect that is
    /// still in flight survives the view re-rendering underneath it.
    @State private var healthOffer: AppleHealthConnectionModel?

    @State private var showAppleHealthOffer = false

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
                    insightsService: services.insightsService,
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
                    // Asking for five stars moments after asking for money is a
                    // reliable way to earn one star instead.
                    reviewPrompt.suppressForThisSession()
                }
        }
        // Refresh active workout state and HomeView when returning from fullScreenCover
        .onChange(of: showActiveWorkout) { _, isShowing in
            if !isShowing {
                homeRefreshTrigger = UUID()
                Task {
                    await refreshActiveWorkoutState()
                    await refreshMonetizationState(forceSubscriptionRefresh: true)
                    // Both want the same moment, so only one may have it. Health goes
                    // first because it can only ever be claimed once, while the review
                    // prompt has two more milestones behind it.
                    guard !offerAppleHealthIfEarned() else { return }
                    await requestReviewIfEarned()
                }
            }
        }
        .onChange(of: showStartWorkoutSheet) { _, isShowing in
            if isShowing { startWorkoutSheetDidDismiss = false }
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
                let fatigueLearningService = services.fatigueLearningService
                Task(priority: .utility) {
                    await StartupPRRebuildMaintenance.runIfNeeded(settingsService: settingsService)
                    await StartupSuggestionModelMaintenance.runIfNeeded(
                        fatigueLearningService: fatigueLearningService
                    )
                }
            }

            // Check for active workout on launch (AGENT_RULES S7.3)
            guard !hasCheckedForActive else { return }
            hasCheckedForActive = true
            await services.refreshUnitPreference()
            await refreshActiveWorkoutState()
            await refreshMonetizationState(forceSubscriptionRefresh: true)
            // Read before reporting abandonment, which clears the marker.
            let inFlightSetCount = ActiveWorkoutSessionMarker.setCount()
            reportAbandonedWorkoutIfNeeded()
            if hasActiveWorkout {
                services.analyticsService.workoutResumed(setCount: inFlightSetCount)
                showActiveWorkout = true
            } else if WhatsNewPreferences.shouldPresent(), let release = WhatsNewRelease.current {
                // Only when nothing else is claiming the screen. A resumed workout takes
                // the fullScreenCover, and two modals racing on launch is how one of them
                // gets dismissed unread.
                services.analyticsService.whatsNewShown()
                // Same reasoning as the paywall: a sheet asking for attention followed by
                // a rating request in one session is how you earn one star.
                reviewPrompt.suppressForThisSession()
                showWhatsNew = true
            }
            trackScreen(for: selectedTab)
        }
        .onAppear {
            configureTabBarAppearance()
        }
        // Marked seen on any dismissal, swipe included: a sheet that returns every launch
        // until it's formally acknowledged is worse than one that was ignored once.
        .sheet(isPresented: $showWhatsNew, onDismiss: { WhatsNewPreferences.markSeen() }) {
            if let release = WhatsNewRelease.current {
                WhatsNewSheet(
                    release: release,
                    healthKitService: services.healthKitService,
                    analyticsService: services.analyticsService
                )
            }
        }
        // Marked offered on any dismissal, swipe included. `decline()` and `connect()`
        // already spend the offer, so this only catches the user who swipes the sheet away
        // without answering — and an unanswered offer that returns after every workout is
        // worse than one that was ignored once.
        .sheet(isPresented: $showAppleHealthOffer, onDismiss: {
            HealthKitPreferences.markOffered()
            healthOffer = nil
        }) {
            if let healthOffer {
                AppleHealthPromptView(
                    model: healthOffer,
                    onConnected: { showAppleHealthOffer = false },
                    onDecline: { showAppleHealthOffer = false }
                )
                // Fixed copy, and the decline rate here is the thing being watched.
                .replayVisible()
                .onAppear { healthOffer.promptShown() }
            }
        }
        // Both follow-on flows wait for this sheet to finish dismissing. Presenting while
        // another sheet is still animating out is dropped by UIKit and re-presented from a
        // stale snapshot.
        .sheet(isPresented: $showStartWorkoutSheet, onDismiss: {
            if pendingTemplateFlow {
                pendingTemplateFlow = false
                showTemplateFlow = true
            }
            startWorkoutSheetDidDismiss = true
            presentCopyPreviousIfReady()
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
                services: services,
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
        hasActiveWorkout = (try? await services.workoutService.getActiveWorkoutSummary()) != nil
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
        // The sheet loads its own list once it's on screen; this only queues the handoff.
        pendingCopyPreviousFlow = true
        presentCopyPreviousIfReady()
    }

    /// Present the Copy Previous sheet once the flow is queued *and* StartWorkoutSheet has
    /// finished dismissing. Called from both sides so the later one wins; presenting into a
    /// sheet that is still animating out is what left the list empty on first open.
    @MainActor
    private func presentCopyPreviousIfReady() {
        guard pendingCopyPreviousFlow, startWorkoutSheetDidDismiss else { return }
        pendingCopyPreviousFlow = false
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
                    _ = try await services.setService.create(
                        workoutId: workout.id,
                        exerciseId: exerciseId,
                        date: Date(),
                        setType: .working,
                        orderInWorkout: index + 1,
                        orderInExercise: 1,
                        weight: nil,
                        reps: nil
                    )
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

    /// Copy a past workout. If an active workout exists, triggers confirmation dialog.
    @MainActor
    private func copyWorkout(_ workoutId: UUID) async {
        do {
            let activeWorkout = try await services.workoutService.getActiveWorkoutSummary()
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
    @MainActor
    private func discardActiveAndCopy() async {
        guard let pendingId = pendingCopyWorkoutId else { return }
        do {
            if let activeWorkout = try await services.workoutService.getActiveWorkoutSummary() {
                let activeSets = try await services.setService.fetchSetSnapshots(for: activeWorkout.id)
                let priorContext = WorkoutStartContextStore.recall()
                services.analyticsService.workoutDiscarded(
                    durationSeconds: Date().timeIntervalSince(activeWorkout.startTime ?? activeWorkout.date),
                    setCount: activeSets.count,
                    date: activeWorkout.date,
                    source: priorContext.source,
                    templateUsed: priorContext.templateUsed,
                    interactions: WorkoutInteractionTally.snapshot()
                )
                WorkoutStartContextStore.clear()
                try await services.workoutService.deleteWorkout(activeWorkout.id)

                // This discard runs without ever building `ActiveWorkoutViewModel`, so none of
                // its teardown fires. Left alone, a rest timer running at the moment of discard
                // would still announce itself minutes later.
                ActiveWorkoutSessionDefaultsKeys.clearRestTimerState()
                RestTimerAlarmCoordinator.cancel()
            }
            showDiscardConfirmation = false
            pendingCopyWorkoutId = nil
            try await performCopy(pendingId)
        } catch {
            dbg("[ContentView] Discard+copy failed: \(error)")
        }
    }

    /// Perform the actual copy of a source workout, then show active workout.
    ///
    /// `@MainActor` because this mutates presentation state. It used to be nonisolated, and
    /// the main app target doesn't set `SWIFT_APPROACHABLE_CONCURRENCY`, so a nonisolated
    /// async function here did *not* inherit the caller's executor — the `@State` writes below
    /// happened off the main actor and the cover could come up before they landed.
    @MainActor
    private func performCopy(_ sourceWorkoutId: UUID) async throws {
        // Warmups are part of the workout being copied. Filtering to `.working` here dropped
        // them silently — the set type is carried through instead.
        let sourceSets = try await services.setService.fetchSetSnapshots(for: sourceWorkoutId)
            .sorted { ($0.orderInWorkout, $0.orderInExercise) < ($1.orderInWorkout, $1.orderInExercise) }

        let startOptions = pendingWorkoutStartOptions ?? .default
        let newWorkout = try await services.workoutService.startWorkout(options: startOptions)

        for sourceSet in sourceSets {
            // Per-side reps and RIR have to be carried explicitly. `reps` on a unilateral row is
            // only a derived mirror of `max(left, right)` (`syncDerivedPerformanceFields`), so
            // copying it alone produced a row the Sets tab read as 0/0 while History and the PR
            // badge read the mirror — the two disagreed on the same set.
            _ = try await services.setService.create(
                workoutId: newWorkout.id,
                exerciseId: sourceSet.exerciseId,
                date: Date(),
                setType: sourceSet.setType,
                orderInWorkout: sourceSet.orderInWorkout,
                orderInExercise: sourceSet.orderInExercise,
                weight: sourceSet.weight,
                reps: sourceSet.reps,
                leftReps: sourceSet.leftReps,
                rightReps: sourceSet.rightReps,
                rir: sourceSet.rir,
                leftRIR: sourceSet.leftRIR,
                rightRIR: sourceSet.rightRIR
            )
        }

        trackWorkoutStarted(
            source: .copyPrevious,
            templateUsed: false,
            copiedPrevious: true,
            options: startOptions
        )

        hasActiveWorkout = true
        pendingWorkoutStartOptions = nil

        // Let the sheet finish dismissing before presenting the cover, matching
        // `startWorkoutWithExercises`. Presenting in the same tick gave a cover whose
        // `.task` ran against a view tree built before the copy landed — the screen came
        // up empty and only filled in when reopened.
        showCopyPreviousSheet = false
        try await Task.sleep(for: .milliseconds(300))
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

    /// Asks for an App Store rating after the active workout screen closes, which
    /// is the best moment Repster has: the user just finished training and the
    /// summary is behind them.
    ///
    /// Raise Repster's own Apple Health explainer once, on the first return to Home after
    /// a workout has been completed.
    ///
    /// Deliberately not in onboarding. 1.4 asked there and converted 2 of 9, while the
    /// same prompt raised from the What's New sheet converted both times it appeared —
    /// an offer to send *finished workouts* somewhere lands once there is a finished
    /// workout to send. Same treatment notification permission already got, for the same
    /// reason: see the `RestTimerAlarmCoordinator` note in `RepsterApp.init`.
    ///
    /// `shouldOfferConnection` is the one-shot gate — false once the user has connected,
    /// answered either way, or is on hardware without HealthKit — so this can never ask a
    /// second time. The completed-workout floor is what keeps a first-ever *discard* from
    /// spending it, since backing out of a workout lands here too.
    ///
    /// - Returns: whether the offer took this moment, so the caller can stand down.
    @MainActor
    private func offerAppleHealthIfEarned() -> Bool {
        guard services.healthKitService.shouldOfferConnection,
              reviewPrompt.completedWorkoutCount >= 1,
              !hasActiveWorkout else { return false }

        healthOffer = AppleHealthConnectionModel(
            healthKitService: services.healthKitService,
            analyticsService: services.analyticsService,
            source: .workoutFinish
        )
        // Milestone 3 is the earliest the rating request can fire, so the two normally
        // can't meet — but a device that only becomes eligible later could land both in
        // one session, and asking for five stars right after asking for permission is how
        // you earn one.
        reviewPrompt.suppressForThisSession()
        showAppleHealthOffer = true
        return true
    }

    /// `ReviewPromptService` owns the "is this earned" decision — milestone,
    /// once-per-version, and a 60-day floor on top of StoreKit's own 3-per-year
    /// throttle. The short delay lets the fullScreenCover finish dismissing so the
    /// system alert doesn't fight the transition.
    private func requestReviewIfEarned() async {
        guard reviewPrompt.shouldRequestReview() else { return }

        try? await Task.sleep(for: .seconds(1.5))
        guard !showActiveWorkout else { return }

        services.analyticsService.reviewPromptRequested(
            trigger: "workout_completed",
            completedWorkoutCount: reviewPrompt.completedWorkoutCount
        )
        reviewPrompt.markReviewRequested()
        requestReview()
    }

    /// Reports a workout that was started but never finished or discarded.
    ///
    /// This is the population the event stream used to lose entirely: `workout
    /// started` with no terminal event, indistinguishable from a user who is
    /// mid-session. Only fires once the session is stale enough that resuming is
    /// implausible, and only clears the analytics marker — the workout itself is
    /// left untouched so the user can still resume or discard it themselves.
    private func reportAbandonedWorkoutIfNeeded() {
        guard ActiveWorkoutSessionMarker.isAbandoned() else { return }

        let context = WorkoutStartContextStore.recall()
        services.analyticsService.workoutAbandoned(
            setCount: ActiveWorkoutSessionMarker.setCount(),
            source: context.source,
            templateUsed: context.templateUsed,
            // Survives the app being killed, which is the whole reason the tally
            // lives in UserDefaults: this is the population whose behaviour matters
            // most and the only one with no live ViewModel to ask.
            interactions: WorkoutInteractionTally.snapshot()
        )
        ActiveWorkoutSessionMarker.clear()
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
