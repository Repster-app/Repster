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

    // MARK: - Snapshot Queries
    //
    // Used by Home, Copy Previous, Calendar and the workout-detail screens to avoid
    // sending live Workout models across actors. The `status` comparison happens in
    // Swift, inside this actor, because #Predicate cannot capture custom enum values
    // (see fetchInProgress above) — so these still read every row, exactly as the
    // live-model fetches they replace do.

    func fetchWorkoutSummary(byId id: UUID) throws -> WorkoutSnapshot? {
        try fetch(byId: id).map(WorkoutSnapshot.init(from:))
    }

    func fetchInProgressSummary() throws -> WorkoutSnapshot? {
        try fetchInProgress().map(WorkoutSnapshot.init(from:))
    }

    func fetchWorkoutSummaries(for dateRange: ClosedRange<Date>) throws -> [WorkoutSnapshot] {
        try fetchWorkouts(for: dateRange).map(WorkoutSnapshot.init(from:))
    }

    func fetchAllWorkoutSummaries(limit: Int? = nil, offset: Int? = nil) throws -> [WorkoutSnapshot] {
        try fetchAllWorkouts(limit: limit, offset: offset).map(WorkoutSnapshot.init(from:))
    }

    /// Persist the mirrored Apple Health sample UUID without handing the live model out.
    func setHealthKitUUID(_ uuid: UUID, forWorkoutId id: UUID) throws {
        guard let workout = try fetch(byId: id) else { return }
        workout.healthKitWorkoutUUID = uuid
        try modelContext.save()
    }

    func fetchEarliestCompletedWorkoutDate() throws -> Date? {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let workouts = try modelContext.fetch(descriptor)
        return workouts.first { $0.status == .completed }?.date
    }
}
