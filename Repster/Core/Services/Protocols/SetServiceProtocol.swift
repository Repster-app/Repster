// SetServiceProtocol.swift
// Contract for set save/edit/delete orchestration
// Spec: FR-001 through FR-006, FR-010, FR-011, FR-012
// Source: specdoc S4, S5.4, S8; AGENT_RULES S3.3, S6

import Foundation

/// Result of a set save operation.
/// Contains the computed effectiveWeight and PR evaluation result
/// so the caller can update UI optimistically.
struct SetSaveResult: Sendable {
    /// The saved set's ID.
    let setId: UUID
    /// The computed effectiveWeight (specdoc S5.4).
    let effectiveWeight: Double
    /// PR evaluation result from PRService.
    let prResult: PREvaluationResult
}

/// Snapshot of a set's completed contribution before UI or caller-side mutation.
///
/// Some UI paths mutate the live `WorkoutSet` object before asking `SetService`
/// to remove or edit its prior contribution. This value preserves the original
/// PR/stat bucket so recomputation does not read already-mutated fields.
struct SetContributionSnapshot: Sendable {
    let setId: UUID
    let exerciseId: UUID
    let workoutId: UUID
    let statsReps: Int
    let prReps: Int
    let effectiveWeight: Double
    let setType: SetType
    let hasData: Bool
    let excludeFromPRs: Bool
    let cachedPRStatus: CachedPRStatus?
    let date: Date

    init(set: WorkoutSet) {
        self.setId = set.id
        self.exerciseId = set.exerciseId
        self.workoutId = set.workoutId
        self.statsReps = set.statsReps
        self.prReps = set.prReps
        self.effectiveWeight = set.effectiveWeight ?? 0
        self.setType = set.setType
        self.hasData = set.hasData
        self.excludeFromPRs = set.excludeFromPRs ?? false
        self.cachedPRStatus = set.prStatus
        self.date = set.date
    }
}

/// SetService orchestrates the complete set lifecycle.
///
/// Responsibilities (per AGENT_RULES S6):
/// - Save/edit/delete sets
/// - Compute effectiveWeight at save time (specdoc S5.4)
/// - Trigger PR pipeline (PRService.evaluate) after persist
/// - Trigger stats pipeline (StatsService.updateStats) after PR evaluation
///
/// SetService does NOT:
/// - Access ModelContext directly (uses SetRepository)
/// - Own PR logic (that's PRService)
/// - Own stats logic (that's StatsService)
/// - Modify PR status directly (PRService returns it via PREvaluationResult)
///
/// Pipeline order (specdoc S4.5, FR-002, FR-003):
///   persist -> effectiveWeight -> PRService.evaluate -> StatsService.updateStats
///
/// Performance: Entire pipeline must complete within 100ms (AGENT_RULES S5.5, SC-005).
protocol SetServiceProtocol: Sendable {

    // MARK: - Save (FR-001, FR-002, FR-003, FR-012)

    /// Save a new set with full pipeline orchestration.
    ///
    /// 1. Compute effectiveWeight (S5.4): weight + (closestBodyweight x bodyweightFactor)
    /// 2. Persist set with effectiveWeight stored (FR-012: immediate persistence)
    /// 3. PRService.evaluate() -> PR status (FR-002)
    /// 4. StatsService.updateStats() (FR-003)
    ///
    /// - Parameter set: The WorkoutSet to save. effectiveWeight will be computed and set.
    /// - Returns: SetSaveResult with computed effectiveWeight and PR result.
    func save(_ set: WorkoutSet) async throws -> SetSaveResult

    // MARK: - Edit (FR-004)

    /// Edit an existing set with full pipeline re-orchestration.
    ///
    /// 1. Capture old values for stats delta
    /// 2. Recompute effectiveWeight with new values
    /// 3. Persist updated set
    /// 4. PRService.evaluateAfterEdit() (FR-004)
    /// 5. StatsService.updateStats() with edit delta
    ///
    /// effectiveWeight is never recalculated retroactively (FR-010) —
    /// this recalculates because the set itself is being edited (new values).
    ///
    /// - Parameter set: The WorkoutSet with updated values.
    /// - Returns: SetSaveResult with new effectiveWeight and PR result.
    func edit(
        _ set: WorkoutSet,
        previousContribution: SetContributionSnapshot?
    ) async throws -> SetSaveResult

    // MARK: - Uncomplete

    /// Uncomplete a set that was previously completed.
    ///
    /// Conceptually "removes a set's contribution" to PRs and stats without deleting it.
    /// Modeled after delete() pipeline:
    /// 1. Capture old values (reps, effectiveWeight, PR status, etc.)
    /// 2. Mutate set: completed = false, completedAt = nil, PR status = nil
    /// 3. Persist set (flat save — no PR/stats pipeline)
    /// 4. PRService.handleDeletion() — demotes PR if this set owned one
    /// 5. StatsService.updateStats(.delete) — decrements totals
    ///
    /// - Parameter set: The WorkoutSet to uncomplete.
    /// - Returns: SetSaveResult with effectiveWeight and PR demotion result.
    func uncomplete(
        _ set: WorkoutSet,
        previousContribution: SetContributionSnapshot?
    ) async throws -> SetSaveResult

    // MARK: - Delete (FR-005)

    /// Delete a set with PR recomputation and stats decrement.
    ///
    /// 1. Capture set values before deletion
    /// 2. Delete set via repository
    /// 3. PRService.handleDeletion() — recomputes if this set owned a PR
    /// 4. StatsService.updateStats() — decrements totals
    ///
    /// - Parameter set: The WorkoutSet to delete (hard delete, no soft delete).
    func delete(_ set: WorkoutSet) async throws

    // MARK: - Lightweight In-Progress Updates

    /// Persist rep-target overrides for an in-progress set without invoking the
    /// PR, stats, fatigue, or effective-weight pipelines.
    func updateInProgressTargetRepOverride(
        setId: UUID,
        min: Int?,
        max: Int?
    ) async throws

    // MARK: - Fetch (006: Active Workout Screen)

    /// Fetch all sets belonging to a workout, ordered by orderInWorkout.
    ///
    /// Used by ActiveWorkoutViewModel to populate set table on workout load/resume.
    /// Returns sets in orderInWorkout order, allowing the caller to group by exerciseId.
    ///
    /// - Parameter workoutId: The workout whose sets to fetch.
    /// - Returns: All WorkoutSets for this workout, ordered by orderInWorkout.
    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]

    /// Fetch the unique exerciseIds for all sets in a workout.
    ///
    /// Used by ActiveWorkoutViewModel to discover which exercises are in a workout,
    /// so it can then fetch each Exercise via ExerciseService.
    ///
    /// - Parameter workoutId: The workout to inspect.
    /// - Returns: Set of unique exerciseIds referenced by this workout's sets.
    func fetchExerciseIds(for workoutId: UUID) async throws -> Swift.Set<UUID>

    // MARK: - Fetch by Exercise (007: Exercise List + Detail)

    /// Fetch sets for an exercise, optionally limited.
    ///
    /// Used by ExerciseDetailViewModel to build workout history for the History tab.
    /// Thin pass-through to SetRepository.
    ///
    /// - Parameters:
    ///   - exerciseId: The exercise whose sets to fetch.
    ///   - limit: Maximum number of sets to return, or nil for all.
    /// - Returns: WorkoutSets for this exercise, ordered by date descending.
    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet]
}

extension SetServiceProtocol {
    func edit(_ set: WorkoutSet) async throws -> SetSaveResult {
        try await edit(set, previousContribution: nil)
    }

    func uncomplete(_ set: WorkoutSet) async throws -> SetSaveResult {
        try await uncomplete(set, previousContribution: nil)
    }
}
