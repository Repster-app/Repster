// ExerciseStatsRepositoryProtocol.swift
// Contract for ExerciseStats data access
// Spec: FR-001, FR-002, FR-003
// Source entity: ExerciseStats (specdoc S6.4)

import Foundation

/// Repository protocol for ExerciseStats entity.
/// ExerciseStats is a rebuildable cache of per-exercise aggregates,
/// updated at write-time by StatsService.
protocol ExerciseStatsRepositoryProtocol: Sendable {

    // MARK: - CRUD

    func save(_ stats: ExerciseStats) async throws
    func delete(_ stats: ExerciseStats) async throws

    // MARK: - Queries

    /// Fetch stats for a specific exercise.
    func fetch(for exerciseId: UUID) async throws -> ExerciseStats?

    /// Fetch all exercise stats (used for rebuild, charts overview).
    func fetchAll() async throws -> [ExerciseStats]

    /// Fetch chart-safe exercise stats snapshots.
    func fetchAllChartExerciseStats() async throws -> [ChartExerciseStatsData]
}
