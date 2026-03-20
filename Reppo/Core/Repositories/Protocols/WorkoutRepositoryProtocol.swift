// WorkoutRepositoryProtocol.swift
// Contract for Workout data access
// Spec: FR-001, FR-002, FR-003
// Source entity: Workout (specdoc S6.2 + AGENT_RULES S7.3)

import Foundation

/// Repository protocol for Workout entity.
protocol WorkoutRepositoryProtocol: Sendable {

    // MARK: - CRUD

    func save(_ workout: Workout) async throws
    func delete(_ workout: Workout) async throws
    func fetch(byId id: UUID) async throws -> Workout?

    // MARK: - Specialized Queries

    /// Fetch the currently active workout (status == .inProgress).
    /// Returns nil if no workout is in progress.
    /// Used at app launch to resume active workout (AGENT_RULES S7.3).
    func fetchInProgress() async throws -> Workout?

    /// Fetch workouts within a date range, ordered by date DESC.
    /// Used by Calendar tab for date-based history.
    func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout]

    /// Fetch all workouts with optional pagination.
    func fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout]

    /// Fetch the earliest completed workout date.
    /// Used by Charts to avoid sending live Workout models across actors.
    func fetchEarliestCompletedWorkoutDate() async throws -> Date?
}
