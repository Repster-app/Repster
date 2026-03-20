// SetRepositoryProtocol.swift
// Contract for WorkoutSet data access
// Spec: FR-002, FR-003, FR-004, FR-009
// Source entity: WorkoutSet (specdoc S6.1)

import Foundation

/// Repository protocol for WorkoutSet entity.
/// Only the implementation imports SwiftData and touches ModelContext.
protocol SetRepositoryProtocol: Sendable {

    // MARK: - CRUD

    func save(_ set: WorkoutSet) async throws
    func delete(_ set: WorkoutSet) async throws
    func fetch(byId id: UUID) async throws -> WorkoutSet?

    // MARK: - Workout Queries

    /// Fetch all sets belonging to a workout, ordered by orderInWorkout.
    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]

    // MARK: - Exercise Queries (FR-004)

    /// Fetch sets for an exercise with optional limit, ordered by date DESC.
    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet]

    /// Fetch sets for an exercise filtered by rep count, with specified sort order.
    /// Used by PRService for PR recomputation.
    func fetchSets(for exerciseId: UUID, reps: Int, orderedBy: SetSortOrder) async throws -> [WorkoutSet]

    // MARK: - Chart Queries (FR-009)

    /// Fetch sets within a date range.
    /// Used by overview charts (weekly volume, muscle group distribution).
    func fetchSets(from startDate: Date, to endDate: Date) async throws -> [WorkoutSet]

    /// Fetch chart-safe set snapshots within a date range.
    /// Used by Charts to avoid crossing live SwiftData models between actors.
    func fetchChartSets(from startDate: Date, to endDate: Date) async throws -> [ChartSetData]

    /// Fetch sets for a specific exercise within an optional date range.
    /// Used by exercise detail charts and sparkline data.
    /// If startDate is nil, fetches all history for the exercise.
    func fetchSets(exerciseId: UUID, from startDate: Date?, to endDate: Date) async throws -> [WorkoutSet]

    /// Fetch chart-safe set snapshots for a specific exercise within an optional date range.
    func fetchChartSets(exerciseId: UUID, from startDate: Date?, to endDate: Date) async throws -> [ChartSetData]

    // MARK: - Aggregation (FR-009)

    /// Returns total volume for an exercise by fetching sets and reducing.
    /// For normal use, prefer ExerciseStats.totalVolume (pre-computed at write-time).
    /// This method exists for rebuild scenarios.
    func fetchTotalVolume(for exerciseId: UUID) async throws -> Double

    /// Returns the maximum effectiveWeight for a given exercise and rep count.
    /// Uses sort DESC + fetchLimit(1) — database-level MAX equivalent.
    func fetchMaxEffectiveWeight(for exerciseId: UUID, reps: Int) async throws -> Double?

    // MARK: - Aggregation — Database-level (specdoc S8.6)

    /// Aggregate stats for an exercise using database-level SUM/MAX/COUNT.
    /// Used by StatsService.rebuildAll() only (cold path).
    func fetchAggregateStats(
        for exerciseId: UUID,
        excludeWarmups: Bool,
        excludePartial: Bool
    ) async throws -> SetAggregateResult

    /// Count distinct workouts containing sets for a given exercise.
    func fetchWorkoutCount(for exerciseId: UUID) async throws -> Int

    /// Fetch the best e1RM value for an exercise.
    /// Uses sort DESC + fetchLimit(1) — database-level MAX equivalent.
    func fetchBestE1RM(for exerciseId: UUID) async throws -> Double?

    // MARK: - Cascade Deletion (FR-010, FR-011)

    /// Bulk delete all sets for a workout. Used by WorkoutService cascade deletion.
    func deleteSets(for workoutId: UUID) async throws

    /// Bulk delete all sets for an exercise. Used by ExerciseService cascade deletion.
    func deleteSets(forExercise exerciseId: UUID) async throws

    /// Fetch unique exerciseIds for sets in a workout.
    /// Used before cascade deletion to know which exercises need PR/stats rebuild.
    func fetchExerciseIds(for workoutId: UUID) async throws -> Swift.Set<UUID>

    // MARK: - PR Recomputation (FR-006, FR-007)

    /// Fetch the best eligible set for PR candidacy.
    /// Used by PRService during recomputation after edit/delete (specdoc S7.2).
    ///
    /// Filters: hasData = true, excludeFromPRs = false, eligible setTypes.
    /// Sorted by effectiveWeight DESC, date ASC (earliest-highest wins).
    /// Optional excludingSetId to skip the deleted/edited set.
    ///
    /// - Parameters:
    ///   - exerciseId: The exercise to search sets for.
    ///   - reps: The rep count to match.
    ///   - excludeWarmups: Whether warmup sets should be excluded (based on user setting).
    ///   - excludingSetId: Optional set ID to exclude from results (the deleted/edited set).
    /// - Returns: The best eligible set, or nil if no eligible sets exist.
    func fetchBestEligibleSet(
        for exerciseId: UUID,
        reps: Int,
        excludeWarmups: Bool,
        excludingSetId: UUID?
    ) async throws -> WorkoutSet?
}
