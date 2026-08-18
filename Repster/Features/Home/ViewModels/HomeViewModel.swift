// HomeViewModel.swift
// Central @Observable ViewModel for the Home tab.
// Spec: 013-home-screen, WP01/WP02

import SwiftUI

// MARK: - Supporting Types

struct WeekDay: Identifiable {
    let id: Int               // 0-6 (Mon=0, Sun=6)
    let abbreviation: String  // "MON", "TUE", etc.
    let dateNumber: Int       // day of month (1-31)
    let date: Date            // full date for this day
    let isToday: Bool
    let hasWorkout: Bool
    let muscleGroups: [String]  // up to 3, for colored dots
}

struct MonthlyStats {
    let totalWorkouts: Int
    let primaryMetric: WorkoutPrimaryMetric?
    let totalSets: Int
}

struct RecentWorkoutSummary: Identifiable {
    let id: UUID              // workout.id
    let displayTitle: String  // workout.displayTitle (user title or time-based default)
    let date: Date
    let exerciseCount: Int
    let setCount: Int         // working sets with hasData
    let durationMinutes: Int
    let primaryMetric: WorkoutPrimaryMetric?
    let muscleGroups: [String]
}

struct CopyPreviousWorkout: Identifiable {
    let id: UUID
    let displayTitle: String
    let date: Date
    let exerciseCount: Int
    let setCount: Int
    let primaryMetric: WorkoutPrimaryMetric?
    let muscleGroups: [String]
}

// MARK: - ViewModel

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - State

    // Week strip
    var weekDays: [WeekDay] = []

    // Active workout detection
    var hasActiveWorkout: Bool = false
    var activeWorkoutStartTime: Date? = nil
    var activeWorkoutExerciseCount: Int = 0
    var activeWorkoutSetCount: Int = 0

    // This Week Activity
    var thisWeekWorkoutCount: Int = 0
    var thisWeekWorkoutDays: Set<Int> = []  // 0=Mon..6=Sun
    let weeklyGoal: Int = 4

    // Recent workouts
    var recentWorkouts: [RecentWorkoutSummary] = []

    // Customizable sections
    var monthlyStats: MonthlyStats? = nil
    var recentPRs: [RecentPR] = []
    var newInsightCount: Int = 0
    var trainingStatus: TrainingStatus? = nil

    // Section customization
    var sectionConfig: HomeSectionConfig = HomeSectionConfig.load()
    var showCustomizeSheet: Bool = false

    // Loading
    var isLoading: Bool = false

    // MARK: - Dependencies

    private let workoutService: WorkoutServiceProtocol
    private let setService: SetServiceProtocol
    private let exerciseService: ExerciseServiceProtocol
    private let chartDataService: ChartDataServiceProtocol
    private let statsService: StatsServiceProtocol
    private let insightsService: (any InsightsServiceProtocol)?

    // MARK: - Cache

    /// Snapshots, not live models: a cached `Exercise` re-arms as a fault whenever a
    /// background `save()` calls `reset()` on its context, so reading it later — mid-render,
    /// long after the fetch — can land on freed memory.
    private var exerciseCache: [UUID: ChartExerciseData] = [:]
    var lastLoadTime: Date?

    init(
        workoutService: WorkoutServiceProtocol,
        setService: SetServiceProtocol,
        exerciseService: ExerciseServiceProtocol,
        chartDataService: ChartDataServiceProtocol,
        statsService: StatsServiceProtocol,
        insightsService: (any InsightsServiceProtocol)? = nil
    ) {
        self.workoutService = workoutService
        self.setService = setService
        self.exerciseService = exerciseService
        self.chartDataService = chartDataService
        self.statsService = statsService
        self.insightsService = insightsService
    }

    // MARK: - Data Loading

    func loadData() async {
        if let last = lastLoadTime, Date().timeIntervalSince(last) < 2 {
            return
        }
        lastLoadTime = Date()

        isLoading = true
        defer { isLoading = false }

        await loadWeekData()
        await checkActiveWorkout()
        await loadRecentWorkouts()
        await loadMonthlyStats()
        await loadRecentPRs()
        await loadInsightsSummary()
    }

    /// Refreshes the analysis if workout data changed, then loads the badge
    /// count and top headline for the teaser card.
    func loadInsightsSummary() async {
        guard let insightsService else { return }
        do {
            try await insightsService.refreshIfNeeded()
            newInsightCount = try await insightsService.newInsightCount()
            trainingStatus = try await insightsService.fetchTrainingStatus()
        } catch {
            dbg("[HomeViewModel] Failed to load insights summary: \(error)")
            newInsightCount = 0
            trainingStatus = nil
        }
    }

    /// Badge only, for coming back from the Insights feed. Reading the feed
    /// marks findings seen but can't change the training status, and re-deriving
    /// the status is the most expensive call the service has.
    func refreshInsightBadge() async {
        guard let insightsService else { return }
        do {
            newInsightCount = try await insightsService.newInsightCount()
        } catch {
            dbg("[HomeViewModel] Failed to refresh insight badge: \(error)")
            newInsightCount = 0
        }
    }

    func checkActiveWorkout() async {
        do {
            let active = try await workoutService.getActiveWorkoutSummary()
            hasActiveWorkout = (active != nil)

            if let workout = active {
                activeWorkoutStartTime = workout.startTime
                let sets = try await setService.fetchSetSnapshots(for: workout.id)
                let exerciseIds = Set(sets.map(\.exerciseId))
                activeWorkoutExerciseCount = exerciseIds.count
                activeWorkoutSetCount = sets.filter { $0.completed && $0.hasData }.count
            } else {
                activeWorkoutStartTime = nil
                activeWorkoutExerciseCount = 0
                activeWorkoutSetCount = 0
            }
        } catch {
            dbg("[HomeViewModel] Failed to check active workout: \(error)")
            hasActiveWorkout = false
            activeWorkoutStartTime = nil
            activeWorkoutExerciseCount = 0
            activeWorkoutSetCount = 0
        }
    }

    // MARK: - Week Data (Strip + Activity)

    private func loadWeekData() async {
        guard let weekRange = currentWeekRange() else { return }

        do {
            let workouts = try await workoutService.fetchWorkoutSummaries(for: weekRange)
            let completed = workouts.filter { $0.status == .completed }

            await buildWeekDays(from: completed, weekRange: weekRange)

            let calendar = Calendar.current
            thisWeekWorkoutCount = completed.count
            thisWeekWorkoutDays = Set(completed.map { workout in
                let weekday = calendar.component(.weekday, from: workout.date)
                return (weekday + 5) % 7
            })
        } catch {
            dbg("[HomeViewModel] Failed to load week data: \(error)")
        }
    }

    private func currentWeekRange() -> ClosedRange<Date>? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        components.weekday = 2 // Monday
        guard let monday = calendar.date(from: components),
              let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else { return nil }
        return calendar.startOfDay(for: monday)...calendar.startOfDay(for: sunday).addingTimeInterval(86399)
    }

    private func buildWeekDays(from completedWorkouts: [WorkoutSnapshot], weekRange: ClosedRange<Date>) async {
        let calendar = Calendar.current
        let monday = calendar.startOfDay(for: weekRange.lowerBound)

        // Group workouts by day index
        var workoutsByDay: [Int: [WorkoutSnapshot]] = [:]
        for workout in completedWorkouts {
            let weekday = calendar.component(.weekday, from: workout.date)
            let index = (weekday + 5) % 7
            workoutsByDay[index, default: []].append(workout)
        }

        let abbreviations = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        var days: [WeekDay] = []
        for i in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: i, to: monday) else { continue }
            let dateNumber = calendar.component(.day, from: dayDate)

            // Get muscle groups for this day's workouts (up to 3)
            var dayMuscleGroups: [String] = []
            if let dayWorkouts = workoutsByDay[i] {
                for workout in dayWorkouts {
                    do {
                        // fetchExerciseIds returns a Set built from an unsorted fetch, so which
                        // three muscles a day settled on changed between launches. Snapshots
                        // come back sorted by orderInWorkout for the same underlying query.
                        let sets = try await setService.fetchSetSnapshots(for: workout.id)
                        var seenExerciseIds: Set<UUID> = []
                        let exerciseIds = sets.map(\.exerciseId).filter { seenExerciseIds.insert($0).inserted }
                        for exerciseId in exerciseIds {
                            if let exercise = try await cachedExercise(exerciseId),
                               let muscle = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle),
                               !dayMuscleGroups.contains(muscle) {
                                dayMuscleGroups.append(muscle)
                                if dayMuscleGroups.count >= 3 { break }
                            }
                        }
                    } catch {
                        // Skip on error
                    }
                    if dayMuscleGroups.count >= 3 { break }
                }
            }

            days.append(WeekDay(
                id: i,
                abbreviation: abbreviations[i],
                dateNumber: dateNumber,
                date: dayDate,
                isToday: calendar.isDateInToday(dayDate),
                hasWorkout: workoutsByDay[i] != nil,
                muscleGroups: dayMuscleGroups
            ))
        }

        weekDays = days
    }

    // MARK: - Monthly Stats

    private func loadMonthlyStats() async {
        do {
            let summary = try await chartDataService.fetchBreakdownSummary(timeRange: .month)
            if summary.totalWorkouts > 0 {
                monthlyStats = MonthlyStats(
                    totalWorkouts: summary.totalWorkouts,
                    primaryMetric: summary.primaryMetric,
                    totalSets: summary.totalSets
                )
            } else {
                monthlyStats = nil
            }
        } catch {
            dbg("[HomeViewModel] Failed to load monthly stats: \(error)")
            monthlyStats = nil
        }
    }

    // MARK: - Recent PRs

    private func loadRecentPRs() async {
        do {
            let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
            let records = try await statsService.fetchRecentPRs(
                since: fourteenDaysAgo,
                limit: sectionConfig.prDisplayMode.fetchLimit,
                scope: sectionConfig.recentPRScope
            )

            var prs: [RecentPR] = []
            for record in records {
                let exerciseName: String
                if let exercise = try await cachedExercise(record.exerciseId) {
                    exerciseName = exercise.name
                    let isPerSide = exercise.unilateral && exercise.supportsUnilateralLogging
                    prs.append(RecentPR(
                        id: record.exerciseId,
                        exerciseName: exerciseName,
                        weight: record.value,
                        reps: record.reps ?? 1,
                        date: record.date,
                        isPerSide: isPerSide
                    ))
                } else {
                    continue
                }
            }

            recentPRs = prs
        } catch {
            dbg("[HomeViewModel] Failed to load recent PRs: \(error)")
            recentPRs = []
        }
    }

    // MARK: - Recent Workouts

    func loadRecentWorkouts() async {
        do {
            let allWorkouts = try await workoutService.fetchAllWorkoutSummaries(limit: nil, offset: nil)
            let completed = allWorkouts
                .filter { $0.status == .completed }
                .sorted { $0.date > $1.date }
                .prefix(sectionConfig.recentWorkoutsCount)

            var summaries: [RecentWorkoutSummary] = []
            for workout in completed {
                let sets = try await setService.fetchSetSnapshots(for: workout.id)
                let workingSetsWithData = sets.filter { $0.setType == .working && $0.hasData }
                // First-appearance order, not Set order. Sets come back sorted by
                // orderInWorkout, so this lists muscles in the order they were trained —
                // and stays put between launches, which Set iteration does not.
                var seenExerciseIds: Set<UUID> = []
                let exerciseIds = sets.map(\.exerciseId).filter { seenExerciseIds.insert($0).inserted }

                var exerciseLookup: [UUID: ChartExerciseData] = [:]
                var muscleGroups: [String] = []
                for exerciseId in exerciseIds {
                    guard let exercise = try await cachedExercise(exerciseId) else { continue }
                    exerciseLookup[exerciseId] = exercise
                    if let muscle = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle),
                       !muscleGroups.contains(muscle) {
                        muscleGroups.append(muscle)
                    }
                }
                let aggregate = WorkoutAggregateSummary.summarize(
                    sets: workingSetsWithData,
                    exercisesById: exerciseLookup
                )

                summaries.append(RecentWorkoutSummary(
                    id: workout.id,
                    displayTitle: workout.displayTitle,
                    date: workout.date,
                    exerciseCount: exerciseIds.count,
                    setCount: workingSetsWithData.count,
                    durationMinutes: (workout.duration ?? 0) / 60,
                    primaryMetric: aggregate.primaryMetric,
                    muscleGroups: muscleGroups
                ))
            }

            recentWorkouts = summaries
        } catch {
            dbg("[HomeViewModel] Failed to load recent workouts: \(error)")
        }
    }

    // MARK: - Section Config

    func toggleSectionVisibility(_ sectionId: HomeSectionId) {
        if let index = sectionConfig.sections.firstIndex(where: { $0.sectionId == sectionId }) {
            sectionConfig.sections[index].visible.toggle()
            sectionConfig.save()
        }
    }


    // MARK: - Cache Helper

    private func cachedExercise(_ id: UUID) async throws -> ChartExerciseData? {
        if let cached = exerciseCache[id] {
            return cached
        }
        let exercise = try await exerciseService.fetchExerciseSnapshot(id)
        if let exercise {
            exerciseCache[id] = exercise
        }
        return exercise
    }
}
