// CalendarViewModel.swift
// Central @Observable ViewModel for the Calendar tab.
// Spec: 008-calendar-tab, WP01 T003

import SwiftUI

// MARK: - Supporting Types

struct ExerciseGroup {
    let exercise: Exercise
    let sets: [WorkoutSet]
    let stats: ExerciseStats?
}

struct WorkoutDetail {
    let workout: Workout
    let exerciseGroups: [ExerciseGroup]
    let totalVolume: Double
    let exerciseCount: Int
    let setCount: Int
}

// MARK: - ViewModel

@Observable
@MainActor
final class CalendarViewModel {

    // MARK: - State

    var selectedDate: Date?
    var calendarDotData: [Date: [String]] = [:]
    var workoutsByDate: [Date: [Workout]] = [:]
    var workoutDetails: [UUID: WorkoutDetail] = [:]
    var isLoadingDots: Bool = false
    var isLoadingDetail: Bool = false
    var scrollToTodayTrigger: Int = 0
    var currentMonth: Date = Calendar.current.startOfMonth(for: Date())
    /// Earliest workout date found in the data — used to extend the calendar range.
    var earliestWorkoutDate: Date?

    // MARK: - Cache

    private var exerciseCache: [UUID: Exercise] = [:]
    private var hasLoadedDots: Bool = false

    // MARK: - Dependencies

    private let workoutService: WorkoutServiceProtocol
    private let setService: SetServiceProtocol
    private let exerciseService: ExerciseServiceProtocol
    private let statsService: StatsServiceProtocol

    init(
        workoutService: WorkoutServiceProtocol,
        setService: SetServiceProtocol,
        exerciseService: ExerciseServiceProtocol,
        statsService: StatsServiceProtocol
    ) {
        self.workoutService = workoutService
        self.setService = setService
        self.exerciseService = exerciseService
        self.statsService = statsService
    }

    // MARK: - Data Loading

    /// Two-phase dot loading for fast initial render.
    /// Phase 1: Fetch all workouts (single cheap query), populate workoutsByDate,
    ///          then build dots only for the current month (~8-12 workouts → near-instant).
    /// Phase 2: Background-load dots for all remaining months; dots merge in
    ///          reactively via @Observable so the user sees them appear seamlessly.
    func loadAllDots() async {
        guard !hasLoadedDots else { return }

        isLoadingDots = true

        do {
            // 1. Fetch all workouts (single DB query, returns Workout objects only — not sets)
            let workouts = try await workoutService.fetchAllWorkouts(limit: nil, offset: nil)

            // 1b. Determine earliest workout date to extend the calendar range
            if let earliest = workouts.last?.date {
                earliestWorkoutDate = earliest
            }

            // 2. Group workouts by normalized date
            var dateWorkouts: [Date: [Workout]] = [:]
            for workout in workouts {
                let key = Self.normalizeDate(workout.date)
                dateWorkouts[key, default: []].append(workout)
            }
            workoutsByDate = dateWorkouts

            // 3. Phase 1 — build dots for the current month only (fast)
            let currentMonthDates = dateWorkouts.keys.filter {
                Calendar.current.isDate($0, equalTo: currentMonth, toGranularity: .month)
            }
            let currentMonthEntries = dateWorkouts.filter { currentMonthDates.contains($0.key) }
            let currentMonthDots = try await buildDots(for: currentMonthEntries)
            calendarDotData.merge(currentMonthDots) { _, new in new }

            // Current month is now visible — stop showing loading state
            isLoadingDots = false

            // 4. Phase 2 — background-load remaining months
            let remainingEntries = dateWorkouts.filter { !currentMonthDates.contains($0.key) }
            let remainingDots = try await buildDots(for: remainingEntries)
            calendarDotData.merge(remainingDots) { _, new in new }

            hasLoadedDots = true
        } catch {
            isLoadingDots = false
            print("[CalendarViewModel] Failed to load dot data: \(error)")
        }
    }

    /// Build muscle-group dot data for a subset of date→workout entries.
    private func buildDots(for dateWorkouts: [Date: [Workout]]) async throws -> [Date: [String]] {
        var dotData: [Date: [String]] = [:]
        for (date, dateWorkoutList) in dateWorkouts {
            var muscleGroups: [String] = []
            for workout in dateWorkoutList {
                let exerciseIds = try await setService.fetchExerciseIds(for: workout.id)
                for exerciseId in exerciseIds {
                    let exercise = try await cachedExercise(exerciseId)
                    if let muscle = exercise?.primaryMuscle?.lowercased(), !muscleGroups.contains(muscle) {
                        muscleGroups.append(muscle)
                    }
                }
            }
            dotData[date] = muscleGroups
        }
        return dotData
    }

    func scrollToToday() {
        currentMonth = Calendar.current.startOfMonth(for: Date())
        scrollToTodayTrigger += 1
    }

    func goToPreviousMonth() {
        if let prev = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = prev
        }
    }

    func goToNextMonth() {
        if let next = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = next
        }
    }

    // MARK: - Date Selection

    func selectDate(_ date: Date) async {
        let normalizedDate = Self.normalizeDate(date)
        selectedDate = normalizedDate

        guard let workouts = workoutsByDate[normalizedDate], !workouts.isEmpty else {
            workoutDetails = [:]
            return
        }

        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            var details: [UUID: WorkoutDetail] = [:]

            for workout in workouts {
                let sets = try await setService.fetchSets(for: workout.id)

                // Group sets by exerciseId
                var exerciseSetMap: [UUID: [WorkoutSet]] = [:]
                for set in sets {
                    exerciseSetMap[set.exerciseId, default: []].append(set)
                }

                // Build exercise groups ordered by position in workout
                var exerciseGroups: [ExerciseGroup] = []
                for (exerciseId, exerciseSets) in exerciseSetMap {
                    let exercise = try await cachedExercise(exerciseId)
                    guard let exercise else { continue }

                    let sortedSets = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }
                    let stats = try? await statsService.fetchStats(for: exerciseId)

                    exerciseGroups.append(ExerciseGroup(
                        exercise: exercise,
                        sets: sortedSets,
                        stats: stats
                    ))
                }

                exerciseGroups.sort { lhs, rhs in
                    let lhsOrder = lhs.sets.first?.orderInWorkout ?? Int.max
                    let rhsOrder = rhs.sets.first?.orderInWorkout ?? Int.max
                    return lhsOrder < rhsOrder
                }

                // Compute summary stats using hasData filter
                let completedSets = sets.filter(\.hasData)
                let totalVolume = completedSets.compactMap(\.volume).reduce(0, +)
                let uniqueExercises = Set(sets.map(\.exerciseId)).count

                details[workout.id] = WorkoutDetail(
                    workout: workout,
                    exerciseGroups: exerciseGroups,
                    totalVolume: totalVolume,
                    exerciseCount: uniqueExercises,
                    setCount: completedSets.count
                )
            }

            workoutDetails = details
        } catch {
            print("[CalendarViewModel] Failed to load workout detail: \(error)")
        }
    }

    /// Sorted workout details for the currently selected date.
    var selectedDateWorkoutDetails: [WorkoutDetail] {
        guard let date = selectedDate,
              let workouts = workoutsByDate[date] else { return [] }
        return workouts
            .compactMap { workoutDetails[$0.id] }
            .sorted { ($0.workout.startTime ?? $0.workout.createdAt) < ($1.workout.startTime ?? $1.workout.createdAt) }
    }

    // MARK: - Helpers

    static func normalizeDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

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

// MARK: - Calendar Extension

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
