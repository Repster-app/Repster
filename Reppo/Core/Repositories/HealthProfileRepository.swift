import SwiftData
import Foundation

@ModelActor
actor HealthProfileRepository: HealthProfileRepositoryProtocol {

    // MARK: - CRUD

    func save(_ profile: HealthProfile) throws {
        modelContext.insert(profile)
        try modelContext.save()
    }

    // MARK: - Queries

    func fetch() throws -> HealthProfile? {
        var descriptor = FetchDescriptor<HealthProfile>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchOrCreate() throws -> HealthProfile {
        if let existing = try fetch() {
            return existing
        }
        let profile = HealthProfile(
            unitPreference: .metric,
            includeWarmupsInVolume: false,
            includeWarmupsInPRs: false,
            e1RMFormula: "epley"
        )
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }
}
