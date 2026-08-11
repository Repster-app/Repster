// HomeView.swift
// Main Home screen assembling all sub-views in NavigationStack + ScrollView.
// Supports customizable section ordering, long-press edit mode, and calendar day navigation.
// Spec: 013-home-screen, WP04 T017

import SwiftUI

/// Navigation token for pushing the Insights feed from Home.
struct InsightsRoute: Hashable {}

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var navigationPath = NavigationPath()
    @Environment(ServiceContainer.self) private var services

    /// Home is reported once per view lifetime — see `reportHomeContentIfNeeded`.
    @State private var hasReportedHomeContent = false

    let refreshTrigger: UUID
    let popToRootTrigger: UUID
    let workoutAccessMessage: String?
    let onStartWorkout: () -> Void
    let onShowStartWorkoutSheet: () -> Void
    let onShowExerciseList: () -> Void
    var onDayTapped: ((Date) -> Void)? = nil

    init(
        workoutService: any WorkoutServiceProtocol,
        setService: any SetServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        chartDataService: any ChartDataServiceProtocol,
        statsService: any StatsServiceProtocol,
        insightsService: (any InsightsServiceProtocol)? = nil,
        refreshTrigger: UUID,
        popToRootTrigger: UUID = UUID(),
        workoutAccessMessage: String? = nil,
        onStartWorkout: @escaping () -> Void,
        onShowStartWorkoutSheet: @escaping () -> Void,
        onShowExerciseList: @escaping () -> Void,
        onDayTapped: ((Date) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: HomeViewModel(
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService,
            chartDataService: chartDataService,
            statsService: statsService,
            insightsService: insightsService
        ))
        self.refreshTrigger = refreshTrigger
        self.popToRootTrigger = popToRootTrigger
        self.workoutAccessMessage = workoutAccessMessage
        self.onStartWorkout = onStartWorkout
        self.onShowStartWorkoutSheet = onShowStartWorkoutSheet
        self.onShowExerciseList = onShowExerciseList
        self.onDayTapped = onDayTapped
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    WeekStripView(weekDays: viewModel.weekDays, onDayTap: onDayTapped)
                    startWorkoutSection

                    // Customizable sections (ordered by user preference)
                    ForEach(viewModel.sectionConfig.visibleSections) { section in
                        customizableSection(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color.bg)
            .navigationDestination(for: UUID.self) { workoutId in
                WorkoutDetailFromHomeView(
                    workoutId: workoutId,
                    workoutService: services.workoutService,
                    setService: services.setService,
                    exerciseService: services.exerciseService,
                    statsService: services.statsService,
                    onWorkoutDeleted: {
                        refreshAfterWorkoutDeletion()
                    }
                )
            }
            .navigationDestination(for: InsightsRoute.self) { _ in
                // Home already derived this status for the hook card, and
                // re-deriving it is the slowest call on the service — hand it
                // over so the destination opens drawn rather than empty.
                InsightsView(
                    insightsService: services.insightsService,
                    initialStatus: viewModel.trainingStatus
                )
                    .onDisappear {
                        // Reading the feed clears the badge; reload it so the
                        // hook card reflects that. Only the badge — nothing on
                        // the Insights screen can move the training status.
                        Task { await viewModel.refreshInsightBadge() }
                    }
            }
        }
        .task(id: refreshTrigger) {
            viewModel.lastLoadTime = nil
            await viewModel.loadData()
            reportHomeContentIfNeeded()
        }
        .onChange(of: popToRootTrigger) {
            navigationPath = NavigationPath()
        }
        .sheet(isPresented: $viewModel.showCustomizeSheet) {
            CustomizeHomeSheet(config: $viewModel.sectionConfig)
        }
        .onChange(of: viewModel.sectionConfig) {
            viewModel.lastLoadTime = nil
            Task { await viewModel.loadData() }
        }
    }

    private func refreshAfterWorkoutDeletion() {
        viewModel.lastLoadTime = nil
        Task { await viewModel.loadData() }
    }

    // MARK: - Customizable Section Router

    @ViewBuilder
    private func customizableSection(_ section: HomeSectionEntry) -> some View {
        switch section.sectionId {
        case .monthlyStats:
            if let stats = viewModel.monthlyStats {
                MonthlyStatsCardView(
                    totalWorkouts: stats.totalWorkouts,
                    primaryMetric: stats.primaryMetric,
                    totalSets: stats.totalSets,
                    unitPreference: services.unitPreference
                )
            }
        case .recentPRs:
            if !viewModel.recentPRs.isEmpty {
                RecentPRsView(
                    prs: viewModel.recentPRs,
                    unitPreference: services.unitPreference,
                    displayMode: viewModel.sectionConfig.prDisplayMode
                )
            }
        case .insights:
            NavigationLink(value: InsightsRoute()) {
                TrainingInsightsHookView(
                    status: viewModel.trainingStatus,
                    newCount: viewModel.newInsightCount
                )
            }
            .buttonStyle(.plain)
        case .recentWorkouts:
            recentWorkoutsSection
        case .legacyTrendingUp:
            EmptyView()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                Text("Workout")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()

            Button {
                viewModel.showCustomizeSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }

    // MARK: - Start Workout

    @ViewBuilder
    private var startWorkoutSection: some View {
        StartWorkoutCardView(
            hasActiveWorkout: viewModel.hasActiveWorkout,
            activeWorkoutStartTime: viewModel.activeWorkoutStartTime,
            activeExerciseCount: viewModel.activeWorkoutExerciseCount,
            activeSetCount: viewModel.activeWorkoutSetCount,
            accessMessage: workoutAccessMessage,
            onCardTapped: {
                if viewModel.hasActiveWorkout {
                    onStartWorkout()
                } else {
                    onShowStartWorkoutSheet()
                }
            },
            onPlusTapped: {
                onShowStartWorkoutSheet()
            }
        )
    }

    // MARK: - Recent Workouts

    @ViewBuilder
    /// Reports an empty Home — the single most common shape of a first session
    /// that never turns into a second one, and previously indistinguishable in
    /// analytics from a returning user opening the app.
    ///
    /// Only the empty case is reported. `ContentView` is the sole emitter of
    /// `$screen` for the tabs, so a screen call here would double-count Home
    /// against Calendar and Settings.
    ///
    /// Fires once per view lifetime; Home reloads on every cover dismissal and
    /// repeat reports would swamp the signal.
    private func reportHomeContentIfNeeded() {
        guard !hasReportedHomeContent else { return }
        hasReportedHomeContent = true
        guard viewModel.recentWorkouts.isEmpty else { return }
        services.analyticsService.emptyStateShown(screen: .home)
    }

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            if viewModel.recentWorkouts.isEmpty {
                Text("Complete your first workout to see it here")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(viewModel.recentWorkouts) { summary in
                    NavigationLink(value: summary.id) {
                        RecentWorkoutCardView(summary: summary, unitPreference: services.unitPreference)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
