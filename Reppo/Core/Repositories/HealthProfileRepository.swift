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
            var didBackfill = false
            if existing.prescriptionDefaultTargetReps == nil {
                existing.prescriptionDefaultTargetReps = 8
                didBackfill = true
            }
            if existing.prescriptionDefaultTargetRIR == nil {
                existing.prescriptionDefaultTargetRIR = 2
                didBackfill = true
            }
            if existing.prescriptionAdminModeEnabled == nil {
                existing.prescriptionAdminModeEnabled = false
                didBackfill = true
            }
            if didBackfill {
                existing.updatedAt = Date()
                try modelContext.save()
            }
            return existing
        }
        let profile = HealthProfile(
            unitPreference: .metric,
            includeWarmupsInVolume: false,
            includeWarmupsInPRs: false,
            e1RMFormula: "epley",
            defaultRestTimeSeconds: 150
        )
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }
}
