// CalendarViewModel.swift
// Central @Observable ViewModel for the Calendar tab.
// Spec: 008-calendar-tab, WP01 T003

import SwiftUI

// MARK: - Supporting Types

/// Snapshot types, not live SwiftData models. Both are parked in main-actor state for the
/// session (`workoutDetails` here and in `WorkoutDetailFromHomeView`), so holding live models
/// meant the UI could fault them through a background context at any later moment.
struct ExerciseGroup: Sendable {
    let exercise: ChartExerciseData
    let sets: [ChartSetData]
    let stats: ChartExerciseStatsData?
}

extension ExerciseGroup {

    /// Group a workout's sets by exercise, in the order the workout ran.
    ///
    /// Extracted because this was written twice — `CalendarViewModel` and
    /// `WorkoutDetailFromHomeView` — and the two copies **had already drifted**: Calendar ordered
    /// by `sets.first?.orderInWorkout`, Home by `sets.map(\.orderInWorkout).min()`. Those are not
    /// the same. `sets` is sorted by `orderInExercise`, and a warm-up added mid-workout is appended
    /// at the global tail, so its `orderInExercise` is 1 while its `orderInWorkout` is the highest
    /// in the workout — enough to order the same session differently on the two screens.
    ///
    /// `min()` is the correct rule and the one kept: it is what `ActiveWorkoutViewModel` uses to
    /// order the tab strip, so all three now agree.
    ///
    /// Async fetching stays with the callers — they resolve exercises differently (a local cache
    /// versus the service) and that was never the part that drifted.
    static func build(
        sets: [ChartSetData],
        exercisesById: [UUID: ChartExerciseData],
        statsById: [UUID: ChartExerciseStatsData?]
    ) -> [ExerciseGroup] {
        var setsByExercise: [UUID: [ChartSetData]] = [:]
        for set in sets {
            setsByExercise[set.exerciseId, default: []].append(set)
        }

        return setsByExercise.compactMap { exerciseId, exerciseSets -> ExerciseGroup? in
            guard let exercise = exercisesById[exerciseId] else { return nil }
            return ExerciseGroup(
                exercise: exercise,
                sets: exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise },
                stats: statsById[exerciseId] ?? nil
            )
        }
        .sorted { lhs, rhs in
            let lhsOrder = lhs.sets.map(\.orderInWorkout).min() ?? Int.max
            let rhsOrder = rhs.sets.map(\.orderInWorkout).min() ?? Int.max
            return lhsOrder < rhsOrder
        }
    }

    /// The superset group this exercise's sets carry, if any.
    ///
    /// Same "any non-nil set decides it" rule as the live screen
    /// (`SupersetGrouping.groupId(for:in:)`), over the read-only snapshot type.
    var supersetGroupId: UUID? {
        sets.lazy.compactMap(\.supersetGroupId).first
    }
}

/// Contiguous runs of exercise groups, for surfaces that draw superset grouping after the fact.
///
/// The workout-detail equivalent of `SupersetGrouping.Run`, and it enforces the same two rules:
/// a run of one is never marked, and non-adjacent members of one group produce separate runs.
struct ExerciseGroupRun: Identifiable {
    var id: UUID { groups[0].exercise.id }
    var supersetGroupId: UUID?
    var groups: [ExerciseGroup]

    var isMarked: Bool { supersetGroupId != nil && groups.count > 1 }

    static func runs(from groups: [ExerciseGroup]) -> [ExerciseGroupRun] {
        var result: [ExerciseGroupRun] = []
        for group in groups {
            let id = group.supersetGroupId
            if let id, var last = result.last, last.supersetGroupId == id {
                last.groups.append(group)
                result[result.count - 1] = last
            } else {
                result.append(ExerciseGroupRun(supersetGroupId: id, groups: [group]))
            }
        }
        return result
    }
}

struct WorkoutDetail: Sendable {
    let workout: WorkoutSnapshot
    let exerciseGroups: [ExerciseGroup]
    let primaryMetric: WorkoutPrimaryMetric?
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
    var workoutsByDate: [Date: [WorkoutSnapshot]] = [:]
    var workoutDetails: [UUID: WorkoutDetail] = [:]
    var isLoadingDots: Bool = false
    var isLoadingDetail: Bool = false
    var scrollToTodayTrigger: Int = 0
    var currentMonth: Date = Calendar.current.startOfMonth(for: Date())
    /// Earliest workout date found in the data — used to extend the calendar range.
    var earliestWorkoutDate: Date?

    // MARK: - Cache

    /// Snapshots — same hazard as `HomeViewModel.exerciseCache`.
    private var exerciseCache: [UUID: ChartExerciseData] = [:]
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
            let workouts = try await workoutService.fetchAllWorkoutSummaries(limit: nil, offset: nil)

            // 1b. Determine earliest workout date to extend the calendar range
            if let earliest = workouts.last?.date {
                earliestWorkoutDate = earliest
            }

            // 2. Group workouts by normalized date
            var dateWorkouts: [Date: [WorkoutSnapshot]] = [:]
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
            dbg("[CalendarViewModel] Failed to load dot data: \(error)")
        }
    }

    /// Force a reload of all calendar dot data (e.g. after a workout is deleted).
    func reloadAllDots() async {
        hasLoadedDots = false
        calendarDotData = [:]
        workoutsByDate = [:]
        await loadAllDots()
    }

    /// Build muscle-group dot data for a subset of date→workout entries.
    private func buildDots(for dateWorkouts: [Date: [WorkoutSnapshot]]) async throws -> [Date: [String]] {
        var dotData: [Date: [String]] = [:]
        for (date, dateWorkoutList) in dateWorkouts {
            var muscleGroups: [String] = []
            for workout in dateWorkoutList {
                // fetchExerciseIds returns a Set built from an unsorted fetch, so dot order
                // shuffled between launches. Snapshots come back sorted by orderInWorkout
                // for the same underlying query.
                let sets = try await setService.fetchSetSnapshots(for: workout.id)
                var seenExerciseIds: Set<UUID> = []
                let exerciseIds = sets.map(\.exerciseId).filter { seenExerciseIds.insert($0).inserted }
                for exerciseId in exerciseIds {
                    let exercise = try await cachedExercise(exerciseId)
                    if let muscle = ExercisePrimaryGroup.normalizedValue(exercise?.primaryMuscle),
                       !muscleGroups.contains(muscle) {
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
                let sets = try await setService.fetchSetSnapshots(for: workout.id)

                // Group sets by exerciseId
                var exerciseSetMap: [UUID: [ChartSetData]] = [:]
                for set in sets {
                    exerciseSetMap[set.exerciseId, default: []].append(set)
                }

                // Resolve exercises and stats here — the grouping and ordering itself is shared
                // with the Home detail screen via `ExerciseGroup.build`.
                var exerciseLookup: [UUID: ChartExerciseData] = [:]
                var statsLookup: [UUID: ChartExerciseStatsData?] = [:]
                for exerciseId in exerciseSetMap.keys {
                    guard let exercise = try await cachedExercise(exerciseId) else { continue }
                    exerciseLookup[exerciseId] = exercise
                    statsLookup[exerciseId] = try? await statsService.fetchStatsSnapshot(for: exerciseId)
                }

                let exerciseGroups = ExerciseGroup.build(
                    sets: sets,
                    exercisesById: exerciseLookup,
                    statsById: statsLookup
                )

                // Compute summary stats using hasData filter
                let completedSets = sets.filter(\.hasData)
                let aggregate = WorkoutAggregateSummary.summarize(
                    sets: completedSets,
                    exercisesById: exerciseLookup
                )
                let uniqueExercises = Set(sets.map(\.exerciseId)).count

                details[workout.id] = WorkoutDetail(
                    workout: workout,
                    exerciseGroups: exerciseGroups,
                    primaryMetric: aggregate.primaryMetric,
                    exerciseCount: uniqueExercises,
                    setCount: completedSets.count
                )
            }

            workoutDetails = details
        } catch {
            dbg("[CalendarViewModel] Failed to load workout detail: \(error)")
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

// MARK: - Calendar Extension

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
