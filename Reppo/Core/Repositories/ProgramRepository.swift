import SwiftData
import Foundation

@ModelActor
actor ProgramRepository: ProgramRepositoryProtocol {

    // MARK: - CRUD

    func save(_ program: Program) throws {
        modelContext.insert(program)
        try modelContext.save()
    }

    func delete(_ program: Program) throws {
        modelContext.delete(program)
        try modelContext.save()
    }

    func fetch(byId id: UUID) throws -> Program? {
        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Queries

    func fetchAll() throws -> [Program] {
        let descriptor = FetchDescriptor<Program>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
}
