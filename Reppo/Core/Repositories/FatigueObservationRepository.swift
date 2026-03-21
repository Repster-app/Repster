import SwiftData
import Foundation

@ModelActor
actor FatigueObservationRepository: FatigueObservationRepositoryProtocol {

    func save(_ observation: FatigueObservation) throws {
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
