// PerformanceRecordRepositoryProtocol.swift
// Contract for PerformanceRecord data access
// Spec: FR-001, FR-002, FR-003, FR-005
// Source entity: PerformanceRecord (specdoc S6.5)

import Foundation

/// Repository protocol for PerformanceRecord entity.
/// PerformanceRecord is the consolidated PR table with uniqueness on
/// (exerciseId, recordType, reps) — enforced in PRService.
protocol PerformanceRecordRepositoryProtocol: Sendable {

    // MARK: - CRUD

    func save(_ record: PerformanceRecord) async throws
    func delete(_ record: PerformanceRecord) async throws

    // MARK: - Lookups (FR-005)

    /// Lookup a specific PR by (exerciseId, recordType, reps).
    /// This is the O(1) PR lookup used on every set save.
    /// reps is nil for e1RM and maxVolume record types.
    func fetch(exerciseId: UUID, recordType: RecordType, reps: Int?) async throws -> PerformanceRecord?

    // MARK: - Bulk Fetch (FR-005)

    /// Fetch all performance records for an exercise (all record types).
    /// Used for PR table display and suffix-max filtering.
    func fetchAll(for exerciseId: UUID) async throws -> [PerformanceRecord]

    /// Fetch performance records for an exercise filtered by record type.
    /// Used for displaying rep-max table or e1RM history.
    func fetchAll(for exerciseId: UUID, recordType: RecordType) async throws -> [PerformanceRecord]

    // MARK: - Recent PRs

    /// Fetch recent repMax PerformanceRecords across all exercises since a given date,
    /// sorted by date descending. Used by Home screen Recent PRs card.
    func fetchRecentRepMaxRecords(since: Date) async throws -> [PerformanceRecord]

    // MARK: - Cascade Deletion (FR-011)

    /// Delete all PerformanceRecords for an exercise.
    /// Used by ExerciseService cascade deletion.
    func deleteAll(for exerciseId: UUID) async throws
}
