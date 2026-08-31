// SetRepositoryProtocol.swift
// Contract for WorkoutSet data access
// Spec: FR-002, FR-003, FR-004, FR-009
// Source entity: WorkoutSet (specdoc S6.1)

import Foundation

/// A single set's new position, as plain values.
///
/// Reindexing after an insert or delete changes only ordering, but the old code routed each
/// changed set through `SetService.edit()` — the full effectiveWeight → PR → stats → fatigue
/// pipeline — in **one unawaited `Task` per set**. That is what manufactured the concurrent
/// writer behind the crash class (see SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md §5.3): N
/// main-actor tasks interleaving against a serialised stream of background saves, while the
/// set table re-rendered off the same models.
///
/// A reindex is now one batched, awaited call applied inside the repository actor.
/// `nil` means "leave this field alone".
struct SetOrderUpdate: Sendable, Equatable {
    let setId: UUID
    let orderInExercise: Int?
    let orderInWorkout: Int?

    init(setId: UUID, orderInExercise: Int? = nil, orderInWorkout: Int? = nil) {
        self.setId = setId
        self.orderInExercise = orderInExercise
        self.orderInWorkout = orderInWorkout
    }
}

/// How a persist call should treat a set's stored e1RM estimate.
///
/// This used to be expressed as `e1RM: Double?` plus `e1RMFormulaVersion: String?` where a nil
/// version meant "leave alone" — a convention nothing enforced and no test covered, which a
/// mutation test caught on 2026-08-12. The three cases are now explicit:
enum E1RMUpdate: Sendable, Equatable {
    /// Leave both the estimate and the stored formula version untouched.
    /// `save()` does this when a set doesn't qualify — it has no `else` branch.
    case leaveAlone
    /// Clear the estimate but keep the formula version that produced the last one.
    /// `edit()` does this when a set stops qualifying.
    case clear
    /// Store a freshly computed estimate and the formula that produced it.
    case set(value: Double, formulaVersion: String)
}

/// Repository protocol for WorkoutSet entity.
/// Only the implementation imports SwiftData and touches ModelContext.
protocol SetRepositoryProtocol: Sendable {

    // MARK: - CRUD

    /// Construct and insert a new set inside the repository actor.
    /// Does not commit — `persist(_:…)` remains the single save.
    func create(
        workoutId: UUID,
        exerciseId: UUID,
        date: Date,
        setType: SetType,
        orderInWorkout: Int,
        orderInExercise: Int,
        weight: Double?,
        reps: Int?,
        leftReps: Int?,
        rightReps: Int?,
        rir: Double?,
        leftRIR: Double?,
        rightRIR: Double?,
        supersetGroupId: UUID?
    ) async throws -> WorkoutSet

    func save(_ set: WorkoutSet) async throws
    func delete(_ set: WorkoutSet) async throws
    func fetch(byId id: UUID) async throws -> WorkoutSet?

    /// Record the rest actually taken after a set, without touching any other field.
    func applyRestDuration(setId: UUID, seconds: Int) async throws

    /// Stamp or clear a superset group across many sets, in one transaction.
    func applySupersetGroup(setIds: [UUID], groupId: UUID?) async throws

    /// Apply set ordering changes inside the owning actor, in one transaction.
    /// Unknown ids are skipped. No-op for an empty batch.
    func applyOrdering(_ updates: [SetOrderUpdate]) async throws

    // MARK: - Mutation
    //
    // These exist so `SetService` — which is `@MainActor` — never mutates a model this
    // context owns from the main thread (§5.5 of the crash analysis).

    /// Apply a completion's typed values and completion stamps inside the owning actor.
    /// Replaces twelve main-actor writes in `ActiveWorkoutViewModel.completeSet`.
    func applyCompletion(
        setId: UUID,
        input: SetCompletionInput,
        exercise: ChartExerciseData?
    ) async throws

    /// Apply the unilateral derivation (`reps`/`rir`/`side` from the per-side values) and
    /// return the resulting snapshot.
    ///
    /// Takes the model rather than an id because `save()` runs this on sets that are not in
    /// the store yet. Does not insert and does not save — both pipelines commit once, in
    /// `persist(_:applying:)`.
    func syncDerivedFields(on set: WorkoutSet, exercise: ChartExerciseData?) async throws -> ChartSetData

    /// Insert the set if it is new, apply the values the pipeline computed, and save —
    /// the single commit point for both `save()` and `edit()`.
    ///
    /// - Parameter touchUpdatedAt: `edit()` stamps `updatedAt`; `save()` never did, and
    ///   still doesn't.
    func persist(
        _ set: WorkoutSet,
        effectiveWeight: Double?,
        e1RM: E1RMUpdate,
        clearPRStatus: Bool,
        touchUpdatedAt: Bool
    ) async throws -> ChartSetData

    /// Set a set's note inside the owning actor. Does not commit.
    func applyNote(setId: UUID, note: String?) async throws

    /// Change a set's type inside the owning actor. Does not commit.
    func applySetType(setId: UUID, type: SetType) async throws

    /// Clear a set's completion and PR status. Used by the uncomplete pipeline.
    func applyUncomplete(setId: UUID) async throws

    /// Write the PR status the PR pipeline returned for a set. No-op if unchanged.
    func applyPRStatus(setId: UUID, status: CachedPRStatus?) async throws

    /// Persist rep-target override guidance without touching any other field.
    func applyTargetRepOverride(setId: UUID, min: Int?, max: Int?) async throws

    // MARK: - Workout Queries

    /// Fetch all sets belonging to a workout, ordered by orderInWorkout.
    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]

    // MARK: - Exercise Queries (FR-004)

    /// Fetch sets for an exercise with optional limit, ordered by date DESC.
    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet]

    /// Snapshot equivalent of `fetchSets(for exerciseId:limit:)`, ordered by date DESC.
    /// Used by the exercise-history screens, which render on the main actor.
    func fetchChartSets(for exerciseId: UUID, limit: Int?) async throws -> [ChartSetData]

    /// Fetch sets for an exercise filtered by rep count, with specified sort order.
    /// Used by PRService for PR recomputation.
    func fetchSets(for exerciseId: UUID, reps: Int, orderedBy: SetSortOrder) async throws -> [WorkoutSet]

    // MARK: - Chart Queries (FR-009)

    /// Fetch sets within a date range.
    /// Used by overview charts (weekly volume, muscle group distribution).
    func fetchSets(from startDate: Date, to endDate: Date) async throws -> [WorkoutSet]

    /// Fetch chart-safe set snapshots for a workout, ordered by orderInWorkout.
    /// Used by Home, Calendar and the workout-detail screens.
    func fetchChartSets(for workoutId: UUID) async throws -> [ChartSetData]

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

    /// Count distinct workouts in which the exercise was actually performed —
    /// i.e. workouts holding at least one completed set that contributes to stats.
    /// Placeholder rows, partials and (unless included) warmups don't count.
    func fetchWorkoutCount(for exerciseId: UUID, excludeWarmups: Bool) async throws -> Int

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
    ///   - excludedWorkoutIds: Workouts to exclude entirely for this PR search.
    /// - Returns: The best eligible set, or nil if no eligible sets exist.
    func fetchBestEligibleSet(
        for exerciseId: UUID,
        reps: Int,
        excludeWarmups: Bool,
        excludingSetId: UUID?,
        excludedWorkoutIds: Set<UUID>
    ) async throws -> WorkoutSet?
}
