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
    let workout: Workout
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
    let workout: Workout
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

    // MARK: - Cache

    private var exerciseCache: [UUID: Exercise] = [:]
    var lastLoadTime: Date?

    init(
        workoutService: WorkoutServiceProtocol,
        setService: SetServiceProtocol,
        exerciseService: ExerciseServiceProtocol,
        chartDataService: ChartDataServiceProtocol,
        statsService: StatsServiceProtocol
    ) {
        self.workoutService = workoutService
        self.setService = setService
        self.exerciseService = exerciseService
        self.chartDataService = chartDataService
        self.statsService = statsService
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
    }

    func checkActiveWorkout() async {
        do {
            let active = try await workoutService.getActiveWorkout()
            hasActiveWorkout = (active != nil)

            if let workout = active {
                activeWorkoutStartTime = workout.startTime
                let sets = try await setService.fetchSets(for: workout.id)
                let exerciseIds = Set(sets.map(\.exerciseId))
                activeWorkoutExerciseCount = exerciseIds.count
                activeWorkoutSetCount = sets.filter { $0.completed && $0.hasData }.count
            } else {
                activeWorkoutStartTime = nil
                activeWorkoutExerciseCount = 0
                activeWorkoutSetCount = 0
            }
        } catch {
            print("[HomeViewModel] Failed to check active workout: \(error)")
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
            let workouts = try await workoutService.fetchWorkouts(for: weekRange)
            let completed = workouts.filter { $0.status == .completed }

            await buildWeekDays(from: completed, weekRange: weekRange)

            let calendar = Calendar.current
            thisWeekWorkoutCount = completed.count
            thisWeekWorkoutDays = Set(completed.map { workout in
                let weekday = calendar.component(.weekday, from: workout.date)
                return (weekday + 5) % 7
            })
        } catch {
            print("[HomeViewModel] Failed to load week data: \(error)")
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

    private func buildWeekDays(from completedWorkouts: [Workout], weekRange: ClosedRange<Date>) async {
        let calendar = Calendar.current
        let monday = calendar.startOfDay(for: weekRange.lowerBound)

        // Group workouts by day index
        var workoutsByDay: [Int: [Workout]] = [:]
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
                        let exerciseIds = try await setService.fetchExerciseIds(for: workout.id)
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
            print("[HomeViewModel] Failed to load monthly stats: \(error)")
            monthlyStats = nil
        }
    }

    // MARK: - Recent PRs

    private func loadRecentPRs() async {
        do {
            let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
            let records = try await statsService.fetchRecentPRs(since: fourteenDaysAgo, limit: sectionConfig.prDisplayMode.fetchLimit)

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
            print("[HomeViewModel] Failed to load recent PRs: \(error)")
            recentPRs = []
        }
    }

    // MARK: - Recent Workouts

    func loadRecentWorkouts() async {
        do {
            let allWorkouts = try await workoutService.fetchAllWorkouts(limit: nil, offset: nil)
            let completed = allWorkouts
                .filter { $0.status == .completed }
                .sorted { $0.date > $1.date }
                .prefix(sectionConfig.recentWorkoutsCount)

            var summaries: [RecentWorkoutSummary] = []
            for workout in completed {
                let sets = try await setService.fetchSets(for: workout.id)
                let workingSetsWithData = sets.filter { $0.setType == .working && $0.hasData }
                let exerciseIds = Set(sets.map(\.exerciseId))

                var exerciseLookup: [UUID: Exercise] = [:]
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
                    workout: workout,
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
            print("[HomeViewModel] Failed to load recent workouts: \(error)")
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

    private func cachedExercise(_ id: UUID) async throws -> Exercise? {
        if let cached = exerciseCache[id] {
            return cached
        }
        let exercise = try await exerciseService.fetchExercise(id)
        if let exercise {
            exerciseCache[id] = exercise
        }
        return exercise
    }
}
