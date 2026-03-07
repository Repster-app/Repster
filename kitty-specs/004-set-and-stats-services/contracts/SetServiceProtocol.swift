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
/// - Modify cachedPRStatus directly (PRService returns it via PREvaluationResult)
///
/// Pipeline order (specdoc S4.5, FR-002, FR-003):
///   persist → effectiveWeight → PRService.evaluate → StatsService.updateStats
///
/// Performance: Entire pipeline must complete within 100ms (AGENT_RULES S5.5, SC-005).
protocol SetServiceProtocol: Sendable {

    // MARK: - Save (FR-001, FR-002, FR-003, FR-012)

    /// Save a new set with full pipeline orchestration.
    ///
    /// 1. Compute effectiveWeight (S5.4): weight + (closestBodyweight × bodyweightFactor)
    /// 2. Persist set with effectiveWeight stored (FR-012: immediate persistence)
    /// 3. PRService.evaluate() → cachedPRStatus (FR-002)
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
    func edit(_ set: WorkoutSet) async throws -> SetSaveResult

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
}
