// BodyweightServiceProtocol.swift
// Contract for BodyweightEntry CRUD and closest-weight lookup
// Spec: FR-008, FR-009
// Source: specdoc S6.6; AGENT_RULES S6

import Foundation

enum BodyweightServiceError: Error {
    case entryNotFound(UUID)
}

/// BodyweightService owns bodyweight entry lifecycle.
///
/// Responsibilities (per AGENT_RULES S6):
/// - CRUD for bodyweight entries (FR-008)
/// - Closest-weight lookup by date for effectiveWeight calculation (FR-009)
///
/// BodyweightService does NOT:
/// - Calculate effectiveWeight (that's SetService's job, AGENT_RULES S6)
/// - Access ModelContext directly (uses repositories)
///
/// Entries are linked to HealthProfile via healthProfileId.
/// The service handles HealthProfile lookup internally — callers don't need to know the profileId.
protocol BodyweightServiceProtocol: Sendable {

    // MARK: - CRUD (FR-008)

    /// Save a new bodyweight entry.
    ///
    /// Automatically associates with the user's HealthProfile (fetched/created internally).
    ///
    /// - Parameters:
    ///   - bodyweightKg: The bodyweight in kilograms (always stored in kg, converted in UI).
    ///   - date: The date of the measurement.
    /// - Returns: The saved BodyweightEntry.
    func saveEntry(bodyweightKg: Double, date: Date) async throws -> BodyweightEntry

    /// Update an existing bodyweight entry.
    ///
    /// - Parameter entry: The entry with updated values.
    func updateEntry(_ entry: BodyweightEntry) async throws

    /// Delete a bodyweight entry.
    ///
    /// - Parameter entryId: The entry to delete.
    func deleteEntry(_ entryId: UUID) async throws

    // MARK: - Queries

    /// Fetch all bodyweight entries for the current user, ordered by date DESC.
    func fetchAllEntries() async throws -> [BodyweightEntry]

    // MARK: - Closest Lookup (FR-009)

    /// Find the bodyweight entry closest in time to the given date.
    ///
    /// Algorithm: queries entries before and after the target date,
    /// returns whichever has the smallest absolute time distance.
    ///
    /// Used by SetService for effectiveWeight calculation:
    ///   effectiveWeight = weight + (closestBodyweight x exercise.bodyweightFactor)
    ///
    /// - Parameter date: The target date to find the closest entry for.
    /// - Returns: The closest BodyweightEntry, or nil if no entries exist.
    func closestBodyweight(to date: Date) async throws -> BodyweightEntry?
}
