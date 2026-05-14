// PRServiceProtocol.swift
// Contract for PR evaluation, recomputation, and display
// Spec: FR-001 through FR-012
// Source: specdoc S7 (all subsections), AGENT_RULES S4, S6

import Foundation

/// Result of evaluating a set for PR status.
/// Returned to callers so they can update UI optimistically.
struct PREvaluationResult: Sendable {
    /// The set that was evaluated.
    let setId: UUID
    /// The new PR status to assign to this set (nil means no badge).
    let newStatus: CachedPRStatus?
    /// Other sets whose PR status changed as a side effect.
    /// Key: setId, Value: new PR status (nil means cleared).
    /// Example: old PR owner's status changes to "previous".
    let affectedSetIds: [UUID: CachedPRStatus?]
    /// Whether a PerformanceRecord was created, updated, or deleted.
    let prRecordChanged: Bool
}

/// A single entry in the suffix-max filtered PR table for display.
/// Only includes entries on the capability frontier (specdoc S7.4).
struct PRTableEntry: Sendable {
    let reps: Int
    let value: Double
    let setId: UUID
    let date: Date
}

/// PRService owns all Personal Record evaluation logic.
///
/// Responsibilities (per AGENT_RULES S6):
/// - Evaluate PR eligibility for sets
/// - Update PerformanceRecord table
/// - Update PR status on WorkoutSet
/// - Suffix-max filtering for display
/// - Bulk rebuild after import or settings changes
///
/// PRService does NOT:
/// - Modify any WorkoutSet field other than PR status
/// - Handle set creation/deletion (that's SetService)
/// - Compute stats (that's StatsService)
/// - Access ModelContext directly (uses repositories)
protocol PRServiceProtocol: Sendable {

    // MARK: - Core Pipeline (FR-001, specdoc S7.2)

    /// Evaluate a newly saved set for PR status.
    /// Called at write-time after every set save.
    ///
    /// All weight comparisons use integer grams via UnitConversion.toGrams() (FR-002).
    /// Eligibility: hasData, excludeFromPRs, setType, warmup setting (FR-003).
    /// Earliest occurrence wins for ties (FR-004).
    ///
    /// - Parameters:
    ///   - setId: The saved set's ID.
    ///   - exerciseId: The exercise this set belongs to.
    ///   - reps: Number of reps performed.
    ///   - effectiveWeight: The set's effective weight (includes bodyweight factor).
    ///   - workoutId: The workout this set belongs to (for same-workout matching, S7.3).
    ///   - setType: The set's type (warmup, working, partial, etc.).
    ///   - hasData: Whether the set has actual recorded values.
    ///   - excludeFromPRs: User-level PR exclusion flag.
    ///   - date: The set's date.
    /// - Returns: Evaluation result with new status and side effects.
    func evaluate(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        effectiveWeight: Double,
        workoutId: UUID,
        setType: SetType,
        hasData: Bool,
        excludeFromPRs: Bool,
        date: Date
    ) async throws -> PREvaluationResult

    /// Re-evaluate PR after a set is edited (specdoc S7.2 "On Set Edited").
    ///
    /// If the edited set was the PR owner and new weight is lower,
    /// queries for a new best candidate (FR-006).
    ///
    /// - Parameters:
    ///   - setId: The edited set's ID.
    ///   - exerciseId: The exercise this set belongs to.
    ///   - reps: Number of reps (may have changed).
    ///   - effectiveWeight: New effective weight after edit.
    ///   - workoutId: The workout this set belongs to.
    ///   - setType: The set's type after edit.
    ///   - hasData: Whether the set has data after edit.
    ///   - excludeFromPRs: PR exclusion flag after edit.
    ///   - previousCachedPRStatus: The set's PR status before the edit.
    ///   - date: The set's date.
    /// - Returns: Evaluation result with new status and side effects.
    func evaluateAfterEdit(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        effectiveWeight: Double,
        workoutId: UUID,
        setType: SetType,
        hasData: Bool,
        excludeFromPRs: Bool,
        previousCachedPRStatus: CachedPRStatus?,
        date: Date
    ) async throws -> PREvaluationResult

    /// Handle PR recomputation after a set is deleted (specdoc S7.2 "On Set Deleted").
    ///
    /// Only does meaningful work if the deleted set was the PR owner (FR-007).
    /// Finds next best candidate or deletes the PerformanceRecord.
    ///
    /// - Parameters:
    ///   - setId: The deleted set's ID (used to exclude from candidate search).
    ///   - exerciseId: The exercise this set belonged to.
    ///   - reps: Number of reps on the deleted set.
    ///   - cachedPRStatus: The deleted set's PR status before deletion.
    /// - Returns: Evaluation result with any promoted sets.
    func handleDeletion(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        cachedPRStatus: CachedPRStatus?
    ) async throws -> PREvaluationResult

    // MARK: - Display (FR-008, specdoc S7.4)

    /// Fetch the suffix-max filtered PR table for an exercise.
    ///
    /// Returns only entries on the capability frontier — entries where
    /// a higher-rep PR has equal or greater weight are hidden.
    ///
    /// - Parameter exerciseId: The exercise to display PRs for.
    /// - Returns: Filtered PR entries sorted by reps ascending.
    func fetchPRTable(for exerciseId: UUID) async throws -> [PRTableEntry]

    // MARK: - Bulk Operations (FR-011)

    /// Rebuild all PRs from scratch across all exercises.
    ///
    /// Used after CSV import or when includeWarmupsInPRs setting changes.
    /// Deletes all PerformanceRecords and re-evaluates from raw sets.
    func rebuildAll() async throws

    /// Rebuild PRs for a single exercise.
    ///
    /// - Parameter exerciseId: The exercise to rebuild PRs for.
    func rebuild(for exerciseId: UUID) async throws
}
