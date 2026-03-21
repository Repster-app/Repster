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

                    recentWorkoutsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color.bg)
            .onAppear {
                viewModel.lastLoadTime = nil
                Task { await viewModel.loadData() }
            }
            .navigationDestination(for: UUID.self) { workoutId in
                WorkoutDetailFromHomeView(
                    workoutId: workoutId,
                    workoutService: services.workoutService,
                    setService: services.setService,
                    exerciseService: services.exerciseService,
                    statsService: services.statsService
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
        .onAppear {
            viewModel.lastLoadTime = nil
            Task { await viewModel.loadData() }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.isEditMode = true
            }
        }
        .sheet(isPresented: $viewModel.showCustomizeSheet) {
            CustomizeHomeSheet(config: $viewModel.sectionConfig)
        }
        .overlay {
            if viewModel.isEditMode {
                editModeOverlay
            }
        }
    }

    // MARK: - Customizable Section Router

    @ViewBuilder
    private func customizableSection(_ section: HomeSectionEntry) -> some View {
        switch section.sectionId {
        case .monthlyStats:
            if let stats = viewModel.monthlyStats {
                MonthlyStatsCardView(
                    totalWorkouts: stats.totalWorkouts,
                    totalVolume: stats.totalVolume,
                    totalSets: stats.totalSets
                )
            }
        case .recentPRs:
            if !viewModel.recentPRs.isEmpty {
                RecentPRsView(prs: viewModel.recentPRs)
            }
        case .legacyTrendingUp:
            EmptyView()
        }
    }

    // MARK: - Edit Mode Overlay

    private var editModeOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.exitEditMode()
                    }
                }

            VStack(spacing: 16) {
                Text("Edit Home Screen")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                // Show each section with toggle
                ForEach(viewModel.sectionConfig.sections.indices, id: \.self) { index in
                    let section = viewModel.sectionConfig.sections[index]
                    HStack {
                        Text(section.sectionId.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Button {
                            viewModel.toggleSectionVisibility(section.sectionId)
                        } label: {
                            Image(systemName: section.visible ? "eye.fill" : "eye.slash.fill")
                                .foregroundStyle(section.visible ? Color.accent : Color.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .foregroundStyle(Color.border)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.bgCard)
                    )
                }

                HStack(spacing: 12) {
                    Button("Customize") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isEditMode = false
                        }
                        viewModel.showCustomizeSheet = true
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentSoft)
                    .cornerRadius(10)

                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.exitEditMode()
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accent)
                    .cornerRadius(10)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.bgCard)
            )
            .padding(.horizontal, 32)
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
                        RecentWorkoutCardView(summary: summary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
