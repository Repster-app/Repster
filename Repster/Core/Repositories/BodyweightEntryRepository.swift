import SwiftData
import Foundation

@ModelActor
actor BodyweightEntryRepository: BodyweightEntryRepositoryProtocol {

    // MARK: - CRUD

    func save(_ entry: BodyweightEntry) throws {
        modelContext.insert(entry)
        try modelContext.save()
    }

    func delete(_ entry: BodyweightEntry) throws {
        modelContext.delete(entry)
        try modelContext.save()
    }

    // MARK: - Lookups

    func fetch(byId id: UUID) throws -> BodyweightEntry? {
        let descriptor = FetchDescriptor<BodyweightEntry>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Queries

    func fetchAll(for healthProfileId: UUID) throws -> [BodyweightEntry] {
        let descriptor = FetchDescriptor<BodyweightEntry>(
            predicate: #Predicate { $0.healthProfileId == healthProfileId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Closest Weight Lookup (FR-008)

    func fetchClosest(to date: Date, healthProfileId: UUID) throws -> BodyweightEntry? {
        // Query 1: Nearest entry BEFORE or ON the target date
        var beforeDescriptor = FetchDescriptor<BodyweightEntry>(
            predicate: #Predicate {
                $0.healthProfileId == healthProfileId && $0.date <= date
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        beforeDescriptor.fetchLimit = 1
        let before = try modelContext.fetch(beforeDescriptor).first

        // Query 2: Nearest entry AFTER the target date
        var afterDescriptor = FetchDescriptor<BodyweightEntry>(
            predicate: #Predicate {
                $0.healthProfileId == healthProfileId && $0.date > date
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        afterDescriptor.fetchLimit = 1
        let after = try modelContext.fetch(afterDescriptor).first

        // Return whichever is closer by absolute time distance
        switch (before, after) {
        case let (b?, a?):
            let beforeDistance = date.timeIntervalSince(b.date)
            let afterDistance = a.date.timeIntervalSince(date)
            return beforeDistance <= afterDistance ? b : a
        case let (b?, nil):
            return b
        case let (nil, a?):
            return a
        case (nil, nil):
            return nil
        }
    }
}
