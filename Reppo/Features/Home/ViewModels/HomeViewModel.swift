// HomeViewModel.swift
// Central @Observable ViewModel for the Home tab.
// Spec: 013-home-screen, WP01/WP02

import SwiftUI

// MARK: - Supporting Types

struct WeekDay: Identifiable {
    let id: Int               // 0-6 (Mon=0, Sun=6)
    let abbreviation: String  // "M", "T", "W", "T", "F", "S", "S"
    let dateNumber: Int       // day of month (1-31)
    let date: Date            // full date for this day
    let isToday: Bool
    let hasWorkout: Bool
}

struct RecentWorkoutSummary: Identifiable {
    let id: UUID              // workout.id
    let workout: Workout
    let displayTitle: String  // workout.displayTitle (user title or time-based default)
    let date: Date
    let exerciseCount: Int
    let setCount: Int         // working sets with hasData
    let durationMinutes: Int
    let totalVolume: Double   // sum(effectiveWeight × reps) for working sets with hasData
    let muscleGroups: [String]
}

struct CopyPreviousWorkout: Identifiable {
    let id: UUID
    let workout: Workout
    let displayTitle: String
    let date: Date
    let exerciseCount: Int
    let setCount: Int
    let totalVolume: Double
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

    // Loading
    var isLoading: Bool = false

    // MARK: - Dependencies

    private let workoutService: WorkoutServiceProtocol
    private let setService: SetServiceProtocol
    private let exerciseService: ExerciseServiceProtocol

    // MARK: - Cache

    private var exerciseCache: [UUID: Exercise] = [:]
    var lastLoadTime: Date?

    init(
        workoutService: WorkoutServiceProtocol,
        setService: SetServiceProtocol,
        exerciseService: ExerciseServiceProtocol
    ) {
        self.workoutService = workoutService
        self.setService = setService
        self.exerciseService = exerciseService
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

            buildWeekDays(from: completed, weekRange: weekRange)

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

    private func buildWeekDays(from completedWorkouts: [Workout], weekRange: ClosedRange<Date>) {
        let calendar = Calendar.current
        let monday = calendar.startOfDay(for: weekRange.lowerBound)

        var workoutDayIndices: Set<Int> = []
        for workout in completedWorkouts {
            let weekday = calendar.component(.weekday, from: workout.date)
            let index = (weekday + 5) % 7
            workoutDayIndices.insert(index)
        }

        let abbreviations = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        var days: [WeekDay] = []
        for i in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: i, to: monday) else { continue }
            let dateNumber = calendar.component(.day, from: dayDate)
            days.append(WeekDay(
                id: i,
                abbreviation: abbreviations[i],
                dateNumber: dateNumber,
                date: dayDate,
                isToday: calendar.isDateInToday(dayDate),
                hasWorkout: workoutDayIndices.contains(i)
            ))
        }

        weekDays = days
    }

    // MARK: - Recent Workouts

    func loadRecentWorkouts() async {
        do {
            let allWorkouts = try await workoutService.fetchAllWorkouts(limit: nil, offset: nil)
            let completed = allWorkouts
                .filter { $0.status == .completed }
                .sorted { $0.date > $1.date }
                .prefix(5)

            var summaries: [RecentWorkoutSummary] = []
            for workout in completed {
                let sets = try await setService.fetchSets(for: workout.id)
                let workingSetsWithData = sets.filter { $0.setType == .working && $0.hasData }
                let totalVolume = workingSetsWithData.compactMap(\.volume).reduce(0, +)
                let exerciseIds = try await setService.fetchExerciseIds(for: workout.id)

                var muscleGroups: [String] = []
                for exerciseId in exerciseIds {
                    if let exercise = try await cachedExercise(exerciseId),
                       let muscle = exercise.primaryMuscle?.lowercased(),
                       !muscleGroups.contains(muscle) {
                        muscleGroups.append(muscle)
                    }
                }

                summaries.append(RecentWorkoutSummary(
                    id: workout.id,
                    workout: workout,
                    displayTitle: workout.displayTitle,
                    date: workout.date,
                    exerciseCount: exerciseIds.count,
                    setCount: workingSetsWithData.count,
                    durationMinutes: (workout.duration ?? 0) / 60,
                    totalVolume: totalVolume,
                    muscleGroups: muscleGroups
                ))
            }

            recentWorkouts = summaries
        } catch {
            print("[HomeViewModel] Failed to load recent workouts: \(error)")
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
