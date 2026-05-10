// HomeView.swift
// Main Home screen assembling all sub-views in NavigationStack + ScrollView.
// Supports customizable section ordering, long-press edit mode, and calendar day navigation.
// Spec: 013-home-screen, WP04 T017

import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var navigationPath = NavigationPath()
    @Environment(ServiceContainer.self) private var services

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
            statsService: statsService
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
        }
        .task(id: refreshTrigger) {
            viewModel.lastLoadTime = nil
            await viewModel.loadData()
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
