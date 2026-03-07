// StatsServiceProtocol.swift
// Contract for ExerciseStats incremental updates and full rebuild
// Spec: FR-007, FR-008, FR-009
// Source: specdoc S6.4, S8.4, S8.6; AGENT_RULES S5.2, S6

import Foundation

/// Describes what triggered a stats update, carrying the data needed
/// for incremental arithmetic adjustments.
enum StatsUpdateEvent: Sendable {
    /// A new set was saved.
    case save(
        reps: Int,
        effectiveWeight: Double,
        setType: SetType,
        hasData: Bool,
        date: Date,
        workoutId: UUID
    )

    /// A set was edited. Carries old and new values for delta computation.
    case edit(
        oldReps: Int, oldEffectiveWeight: Double, oldSetType: SetType, oldHasData: Bool,
        newReps: Int, newEffectiveWeight: Double, newSetType: SetType, newHasData: Bool,
        date: Date, workoutId: UUID
    )

    /// A set was deleted.
    case delete(
        reps: Int,
        effectiveWeight: Double,
        setType: SetType,
        hasData: Bool,
        date: Date,
        workoutId: UUID
    )
}

/// Result of Core Data NSExpression aggregation for rebuildAll().
/// All values computed at the database level — no Swift iteration (specdoc S8.6).
struct SetAggregateResult: Sendable {
    let totalSets: Int
    let totalReps: Int
    let totalVolume: Double   // SUM(effectiveWeight * reps)
    let maxWeight: Double     // MAX(effectiveWeight)
    let lastPerformedDate: Date?  // MAX(date)
}

/// StatsService owns ExerciseStats updates — both incremental and full rebuild.
///
/// Responsibilities (per AGENT_RULES S6):
/// - Update ExerciseStats incrementally at write-time (FR-007)
/// - Recompute all ExerciseStats via database aggregation (FR-008)
/// - Volume = effectiveWeight x reps, excluding partial sets and warmups per settings (FR-009)
///
/// StatsService does NOT:
/// - Own PR logic (that's PRService)
/// - Modify WorkoutSet (read-only access for aggregation)
/// - Access ModelContext directly (uses repositories)
///
/// Incremental path (hot): Pure arithmetic on cached ExerciseStats. O(1).
/// Rebuild path (cold): Core Data NSExpression for real SQL SUM/MAX/COUNT (specdoc S8.6).
protocol StatsServiceProtocol: Sendable {

    // MARK: - Incremental Update (FR-007, specdoc S8.4)

    /// Update ExerciseStats incrementally after a set save/edit/delete.
    ///
    /// Hot path — must be fast (part of 100ms save budget).
    /// Uses pure arithmetic to adjust existing ExerciseStats values.
    /// Creates ExerciseStats if none exists for this exercise.
    ///
    /// Volume calculation (FR-009):
    /// - volume = effectiveWeight x reps
    /// - Partial sets excluded from volume (always)
    /// - Warmup sets excluded from volume when HealthProfile.includeWarmupsInVolume == false
    ///
    /// - Parameters:
    ///   - exerciseId: The exercise whose stats to update.
    ///   - event: What happened (save/edit/delete) with the relevant data.
    func updateStats(for exerciseId: UUID, event: StatsUpdateEvent) async throws

    // MARK: - Full Rebuild (FR-008, specdoc S8.6)

    /// Rebuild all ExerciseStats from raw sets using database aggregation.
    ///
    /// Cold path — rare maintenance operation (import, settings change, corruption).
    /// Uses Core Data NSFetchRequest + NSExpression for SQL-level SUM/MAX/COUNT.
    /// Must handle 12,000+ sets without loading them into memory (specdoc S8.6).
    ///
    /// NOT called at startup (AGENT_RULES S5.1). Triggered from Settings only.
    func rebuildAll() async throws

    /// Rebuild stats for a single exercise.
    ///
    /// - Parameter exerciseId: The exercise to rebuild stats for.
    func rebuild(for exerciseId: UUID) async throws

    // MARK: - Read (007: Exercise List + Detail)

    /// Fetch pre-computed stats for a single exercise.
    ///
    /// Used by ExerciseDetailViewModel to display stats without skipping layers.
    /// Thin pass-through to ExerciseStatsRepository.
    ///
    /// - Parameter exerciseId: The exercise whose stats to fetch.
    /// - Returns: The ExerciseStats, or nil if no stats exist yet.
    func fetchStats(for exerciseId: UUID) async throws -> ExerciseStats?

    /// Fetch all ExerciseStats for display in exercise lists.
    /// Returns stats keyed by exerciseId for O(1) lookup.
    ///
    /// Used by ExerciseListViewModel to display card metadata (last performed, best lift).
    func fetchAllStats() async throws -> [UUID: ExerciseStats]
}
