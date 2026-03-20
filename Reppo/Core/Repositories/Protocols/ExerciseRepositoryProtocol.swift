// ExerciseRepositoryProtocol.swift
// Contract for Exercise data access
// Spec: FR-001, FR-002, FR-003
// Source entity: Exercise (specdoc S6.3)

import Foundation

/// Repository protocol for Exercise entity.
protocol ExerciseRepositoryProtocol: Sendable {

    // MARK: - CRUD

    func save(_ exercise: Exercise) async throws
    func delete(_ exercise: Exercise) async throws
    func fetch(byId id: UUID) async throws -> Exercise?

    // MARK: - Queries

    /// Fetch all exercises, ordered by name ASC.
    func fetchAll() async throws -> [Exercise]

    /// Fetch chart-safe exercise snapshots ordered by name ASC.
    func fetchAllChartExercises() async throws -> [ChartExerciseData]

    /// Search exercises by name (case-insensitive, contains).
    /// Used by exercise list autocomplete (~200 exercises).
    func search(name: String) async throws -> [Exercise]

    /// Check if an exercise has any associated WorkoutSets.
    /// Used to enforce trackingType immutability (AGENT_RULES S3.5).
    func hasAssociatedSets(_ exerciseId: UUID) async throws -> Bool
}
