import SwiftData
import Foundation

@ModelActor
actor WorkoutRepository: WorkoutRepositoryProtocol {

    // MARK: - CRUD

    func save(_ workout: Workout) throws {
        modelContext.insert(workout)
        try modelContext.save()
    }

    func delete(_ workout: Workout) throws {
        modelContext.delete(workout)
        try modelContext.save()
    }

    func fetch(byId id: UUID) throws -> Workout? {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetch(byIds ids: Set<UUID>) throws -> [Workout] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Workout>()
        return try modelContext.fetch(descriptor).filter { ids.contains($0.id) }
    }

    // MARK: - Specialized Queries

    func fetchInProgress() throws -> Workout? {
        // SwiftData #Predicate does not support captured custom enum values.
        // Fetch all workouts and filter in Swift — this is called infrequently
        // (app launch + start workout) and the workout count is bounded.
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let workouts = try modelContext.fetch(descriptor)
        return workouts.first { $0.status == .inProgress }
    }

    func fetchWorkouts(for dateRange: ClosedRange<Date>) throws -> [Workout] {
        let start = dateRange.lowerBound
        let end = dateRange.upperBound
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate {
                $0.date >= start && $0.date <= end
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAllWorkouts(limit: Int? = nil, offset: Int? = nil) throws -> [Workout] {
        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        if let offset { descriptor.fetchOffset = offset }
        return try modelContext.fetch(descriptor)
    }

    func fetchEarliestCompletedWorkoutDate() throws -> Date? {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let workouts = try modelContext.fetch(descriptor)
        return workouts.first { $0.status == .completed }?.date
    }
}
