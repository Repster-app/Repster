// SetRepositoryProtocol.swift
// Contract for WorkoutSet data access
// Spec: FR-002, FR-003, FR-004, FR-009
// Source entity: WorkoutSet (specdoc S6.1)

import Foundation

/// Sort order options for set queries
enum SetSortOrder: Sendable {
    case effectiveWeightDesc
    case dateAsc
    case dateDesc
}

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

    // MARK: - Aggregation (FR-009)

    /// Returns the maximum effectiveWeight for a given exercise and rep count.
    /// Uses sort DESC + fetchLimit(1) — database-level MAX equivalent.
    func fetchMaxEffectiveWeight(for exerciseId: UUID, reps: Int) async throws -> Double?

    // Note: No fetchTotalVolume — SwiftData has no native SUM.
    // Callers read ExerciseStats.totalVolume (pre-computed at write-time by StatsService).
}
