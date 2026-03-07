// BodyweightService.swift
// Bodyweight entry CRUD and closest-weight lookup
// Spec: FR-008, FR-009
// Source: specdoc S6.6; AGENT_RULES S6

import Foundation

actor BodyweightService: BodyweightServiceProtocol {

    // MARK: - Dependencies

    private let bodyweightEntryRepo: BodyweightEntryRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol

    init(
        bodyweightEntryRepository: BodyweightEntryRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol
    ) {
        self.bodyweightEntryRepo = bodyweightEntryRepository
        self.healthProfileRepo = healthProfileRepository
    }

    // MARK: - CRUD (FR-008)

    func saveEntry(bodyweightKg: Double, date: Date) async throws -> BodyweightEntry {
        let profile = try await healthProfileRepo.fetchOrCreate()
        let entry = BodyweightEntry(
            healthProfileId: profile.id,
            date: date,
            bodyweightKg: bodyweightKg
        )
        try await bodyweightEntryRepo.save(entry)
        return entry
    }

    func updateEntry(_ entry: BodyweightEntry) async throws {
        entry.updatedAt = Date()
        try await bodyweightEntryRepo.save(entry)
    }

    func deleteEntry(_ entryId: UUID) async throws {
        guard let entry = try await bodyweightEntryRepo.fetch(byId: entryId) else {
            throw BodyweightServiceError.entryNotFound(entryId)
        }
        try await bodyweightEntryRepo.delete(entry)
    }

    func fetchAllEntries() async throws -> [BodyweightEntry] {
        let profile = try await healthProfileRepo.fetchOrCreate()
        return try await bodyweightEntryRepo.fetchAll(for: profile.id)
    }

    // MARK: - Closest Lookup (FR-009)

    func closestBodyweight(to date: Date) async throws -> BodyweightEntry? {
        let profile = try await healthProfileRepo.fetchOrCreate()
        return try await bodyweightEntryRepo.fetchClosest(to: date, healthProfileId: profile.id)
    }
}
