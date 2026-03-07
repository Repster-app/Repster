import SwiftData
import Foundation

@ModelActor
actor ExerciseStatsRepository: ExerciseStatsRepositoryProtocol {

    // MARK: - CRUD

    func save(_ stats: ExerciseStats) throws {
        modelContext.insert(stats)
        try modelContext.save()
    }

    func delete(_ stats: ExerciseStats) throws {
        modelContext.delete(stats)
        try modelContext.save()
    }

    // MARK: - Queries

    func fetch(for exerciseId: UUID) throws -> ExerciseStats? {
        let descriptor = FetchDescriptor<ExerciseStats>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchAll() throws -> [ExerciseStats] {
        let descriptor = FetchDescriptor<ExerciseStats>()
        return try modelContext.fetch(descriptor)
    }
}
