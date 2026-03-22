import SwiftData
import Foundation

@ModelActor
actor FatigueObservationRepository: FatigueObservationRepositoryProtocol {

    func upsert(_ observation: FatigueObservation) throws {
        try deleteObservation(for: observation.setId)
        modelContext.insert(observation)
        try modelContext.save()
    }

    func fetchObservations(for workoutId: UUID) throws -> [FatigueObservation] {
        let descriptor = FetchDescriptor<FatigueObservation>(
            predicate: #Predicate { $0.workoutId == workoutId },
            sortBy: [SortDescriptor(\.setIndex)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchObservations(exerciseId: UUID, limit: Int?) throws -> [FatigueObservation] {
        var descriptor = FetchDescriptor<FatigueObservation>(
            predicate: #Predicate { $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }

    func distinctWorkoutCount(exerciseId: UUID) throws -> Int {
        let observations = try fetchObservations(exerciseId: exerciseId, limit: nil)
        let uniqueWorkouts = Set(observations.map(\.workoutId))
        return uniqueWorkouts.count
    }

    func deleteObservation(for setId: UUID) throws {
        let descriptor = FetchDescriptor<FatigueObservation>(
            predicate: #Predicate { $0.storedSetId == setId || ($0.storedSetId == nil && $0.id == setId) }
        )
        let observations = try modelContext.fetch(descriptor)
        for observation in observations {
            modelContext.delete(observation)
        }
        if !observations.isEmpty {
            try modelContext.save()
        }
    }

    @discardableResult
    func pruneObservations(exerciseId: UUID, keepRecentSessions: Int) throws -> Int {
        let allObservations = try fetchObservations(exerciseId: exerciseId, limit: nil)

        // Group by workoutId, sorted by most recent first
        let workoutGroups = Dictionary(grouping: allObservations, by: \.workoutId)
        let sortedWorkoutIds = workoutGroups.keys.sorted { a, b in
            let dateA = workoutGroups[a]?.first?.createdAt ?? .distantPast
            let dateB = workoutGroups[b]?.first?.createdAt ?? .distantPast
            return dateA > dateB
        }

        guard sortedWorkoutIds.count > keepRecentSessions else { return 0 }

        let workoutsToRemove = sortedWorkoutIds.dropFirst(keepRecentSessions)
        var deletedCount = 0

        for workoutId in workoutsToRemove {
            if let observations = workoutGroups[workoutId] {
                for observation in observations {
                    modelContext.delete(observation)
                    deletedCount += 1
                }
            }
        }

        try modelContext.save()
        return deletedCount
    }
}

@ModelActor
actor FatigueLearningSetAuditRepository: FatigueLearningSetAuditRepositoryProtocol {

    func upsert(_ audit: FatigueLearningSetAudit) throws {
        try deleteExistingAudit(for: audit.setId)
        modelContext.insert(audit)
        try modelContext.save()
    }

    func fetchAudits(for workoutId: UUID) throws -> [FatigueLearningSetAudit] {
        let descriptor = FetchDescriptor<FatigueLearningSetAudit>(
            predicate: #Predicate { $0.workoutId == workoutId },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.visibleSetNumber)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAudits(workoutId: UUID, exerciseId: UUID) throws -> [FatigueLearningSetAudit] {
        let descriptor = FetchDescriptor<FatigueLearningSetAudit>(
            predicate: #Predicate { $0.workoutId == workoutId && $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.visibleSetNumber), SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAudits(exerciseId: UUID, limit: Int?) throws -> [FatigueLearningSetAudit] {
        var descriptor = FetchDescriptor<FatigueLearningSetAudit>(
            predicate: #Predicate { $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.visibleSetNumber)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }

    func exerciseIdsWithAudits() throws -> [UUID] {
        let audits = try modelContext.fetch(FetchDescriptor<FatigueLearningSetAudit>())
        return Array(Set(audits.map(\.exerciseId))).sorted { $0.uuidString < $1.uuidString }
    }

    func deleteAudit(for setId: UUID) throws {
        let descriptor = FetchDescriptor<FatigueLearningSetAudit>(
            predicate: #Predicate { $0.setId == setId }
        )
        let audits = try modelContext.fetch(descriptor)
        for audit in audits {
            modelContext.delete(audit)
        }
        if !audits.isEmpty {
            try modelContext.save()
        }
    }

    func deleteAudits(workoutId: UUID) throws {
        let audits = try fetchAudits(for: workoutId)
        for audit in audits {
            modelContext.delete(audit)
        }
        if !audits.isEmpty {
            try modelContext.save()
        }
    }

    func deleteAudits(exerciseId: UUID) throws {
        let audits = try fetchAudits(exerciseId: exerciseId, limit: nil)
        for audit in audits {
            modelContext.delete(audit)
        }
        if !audits.isEmpty {
            try modelContext.save()
        }
    }

    func deleteAll() throws {
        let audits = try modelContext.fetch(FetchDescriptor<FatigueLearningSetAudit>())
        for audit in audits {
            modelContext.delete(audit)
        }
        if !audits.isEmpty {
            try modelContext.save()
        }
    }

    private func deleteExistingAudit(for setId: UUID) throws {
        let descriptor = FetchDescriptor<FatigueLearningSetAudit>(
            predicate: #Predicate { $0.setId == setId }
        )
        let audits = try modelContext.fetch(descriptor)
        for audit in audits {
            modelContext.delete(audit)
        }
    }
}
