// BodyweightEntryRepositoryProtocol.swift
// Contract for BodyweightEntry data access
// Spec: FR-001, FR-002, FR-003, FR-008
// Source entity: BodyweightEntry (specdoc S6.6)

import Foundation

/// Repository protocol for BodyweightEntry entity.
/// Used for bodyweight tracking and effectiveWeight calculation
/// when Exercise.bodyweightFactor > 0.
protocol BodyweightEntryRepositoryProtocol: Sendable {

    // MARK: - CRUD

    func save(_ entry: BodyweightEntry) async throws
    func delete(_ entry: BodyweightEntry) async throws

    // MARK: - Queries

    /// Fetch all bodyweight entries for a health profile, ordered by date DESC.
    func fetchAll(for healthProfileId: UUID) async throws -> [BodyweightEntry]

    // MARK: - Lookups

    /// Fetch a bodyweight entry by ID.
    func fetch(byId id: UUID) async throws -> BodyweightEntry?

    // MARK: - Closest Weight Lookup (FR-008)

    /// Find the bodyweight entry closest in time to the given date.
    /// Algorithm: query entries <= date (nearest before) and entries >= date (nearest after),
    /// return whichever has the smallest absolute time distance.
    /// Used for effectiveWeight calculation: weight + (closestBodyweight x bodyweightFactor).
    func fetchClosest(to date: Date, healthProfileId: UUID) async throws -> BodyweightEntry?
}
