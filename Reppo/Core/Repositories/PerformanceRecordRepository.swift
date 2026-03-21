import SwiftData
import Foundation

@ModelActor
actor PerformanceRecordRepository: PerformanceRecordRepositoryProtocol {

    // MARK: - CRUD

    func save(_ record: PerformanceRecord) throws {
        modelContext.insert(record)
        try modelContext.save()
    }

    func delete(_ record: PerformanceRecord) throws {
        modelContext.delete(record)
        try modelContext.save()
    }

    // MARK: - Lookups (FR-005)

    func fetch(exerciseId: UUID, recordType: RecordType, reps: Int?) throws -> PerformanceRecord? {
        // SwiftData #Predicate doesn't support custom enum types as captured values
        // or .rawValue keypaths. Fetch by exerciseId and filter in Swift.
        // This is fine — PerformanceRecords per exercise are tiny (one per rep count).
        let descriptor = FetchDescriptor<PerformanceRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        let records = try modelContext.fetch(descriptor)
        return records.first { record in
            record.recordType == recordType && record.reps == reps
        }
    }

    // MARK: - Bulk Fetch (FR-005)

    func fetchAll(for exerciseId: UUID) throws -> [PerformanceRecord] {
        let descriptor = FetchDescriptor<PerformanceRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAll(for exerciseId: UUID, recordType: RecordType) throws -> [PerformanceRecord] {
        // SwiftData #Predicate doesn't support custom enum types as captured values
        // or .rawValue keypaths. Fetch by exerciseId and filter in Swift.
        let descriptor = FetchDescriptor<PerformanceRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.reps)]
        )
        return try modelContext.fetch(descriptor).filter { $0.recordType == recordType }
    }

    // MARK: - Recent PRs

    func fetchRecentRepMaxRecords(since: Date) throws -> [PerformanceRecord] {
        let descriptor = FetchDescriptor<PerformanceRecord>(
            predicate: #Predicate { $0.date >= since },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).filter { $0.recordType == .repMax }
    }

    // MARK: - Cascade Deletion (FR-011)

    func deleteAll(for exerciseId: UUID) throws {
        let descriptor = FetchDescriptor<PerformanceRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        let records = try modelContext.fetch(descriptor)
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}
