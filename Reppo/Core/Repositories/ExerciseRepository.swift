import SwiftData
import Foundation

@ModelActor
actor ExerciseRepository: ExerciseRepositoryProtocol {

    // MARK: - CRUD

    func save(_ exercise: Exercise) throws {
        modelContext.insert(exercise)
        try modelContext.save()
    }

    func delete(_ exercise: Exercise) throws {
        modelContext.delete(exercise)
        try modelContext.save()
    }

    func fetch(byId id: UUID) throws -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Queries

    func fetchAll() throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAllChartExercises() throws -> [ChartExerciseData] {
        try fetchAll().map(ChartExerciseData.init(from:))
    }

    func search(name: String) throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate {
                $0.name.localizedStandardContains(name)
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func hasAssociatedSets(_ exerciseId: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }
}
