import SwiftData
import Foundation

@ModelActor
actor SetRepository: SetRepositoryProtocol {

    // MARK: - CRUD

    func save(_ set: WorkoutSet) throws {
        modelContext.insert(set)
        try modelContext.save()
    }

    func delete(_ set: WorkoutSet) throws {
        modelContext.delete(set)
        try modelContext.save()
    }

    func fetch(byId id: UUID) throws -> WorkoutSet? {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Workout Queries

    func fetchSets(for workoutId: UUID) throws -> [WorkoutSet] {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == workoutId },
            sortBy: [SortDescriptor(\.orderInWorkout)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Exercise Queries (FR-004)

    func fetchSets(for exerciseId: UUID, limit: Int? = nil) throws -> [WorkoutSet] {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return try modelContext.fetch(descriptor)
    }

    func fetchSets(for exerciseId: UUID, reps: Int, orderedBy order: SetSortOrder) throws -> [WorkoutSet] {
        let sortDescriptors: [SortDescriptor<WorkoutSet>] = switch order {
        case .effectiveWeightDesc:
            [SortDescriptor(\.effectiveWeight, order: .reverse)]
        case .dateAsc:
            [SortDescriptor(\.date, order: .forward)]
        case .dateDesc:
            [SortDescriptor(\.date, order: .reverse)]
        }

        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate {
                $0.exerciseId == exerciseId && $0.reps == reps
            },
            sortBy: sortDescriptors
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Cascade Deletion (FR-010, FR-011)

    func deleteSets(for workoutId: UUID) throws {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )
        let sets = try modelContext.fetch(descriptor)
        for set in sets {
            modelContext.delete(set)
        }
        try modelContext.save()
    }

    func deleteSets(forExercise exerciseId: UUID) throws {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        let sets = try modelContext.fetch(descriptor)
        for set in sets {
            modelContext.delete(set)
        }
        try modelContext.save()
    }

    func fetchExerciseIds(for workoutId: UUID) throws -> Swift.Set<UUID> {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )
        let sets = try modelContext.fetch(descriptor)
        return Swift.Set(sets.map(\.exerciseId))
    }

    // MARK: - Chart Queries (FR-009)

    func fetchSets(from startDate: Date, to endDate: Date) throws -> [WorkoutSet] {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate<WorkoutSet> {
                $0.date >= startDate && $0.date <= endDate
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchChartSets(from startDate: Date, to endDate: Date) throws -> [ChartSetData] {
        try fetchSets(from: startDate, to: endDate).map(ChartSetData.init(from:))
    }

    func fetchSets(exerciseId: UUID, from startDate: Date?, to endDate: Date) throws -> [WorkoutSet] {
        let descriptor: FetchDescriptor<WorkoutSet>
        if let startDate {
            descriptor = FetchDescriptor<WorkoutSet>(
                predicate: #Predicate<WorkoutSet> {
                    $0.exerciseId == exerciseId && $0.date >= startDate && $0.date <= endDate
                },
                sortBy: [SortDescriptor(\.date)]
            )
        } else {
            descriptor = FetchDescriptor<WorkoutSet>(
                predicate: #Predicate<WorkoutSet> {
                    $0.exerciseId == exerciseId && $0.date <= endDate
                },
                sortBy: [SortDescriptor(\.date)]
            )
        }
        return try modelContext.fetch(descriptor)
    }

    func fetchChartSets(exerciseId: UUID, from startDate: Date?, to endDate: Date) throws -> [ChartSetData] {
        try fetchSets(exerciseId: exerciseId, from: startDate, to: endDate).map(ChartSetData.init(from:))
    }

    // MARK: - Aggregation (FR-009)

    func fetchMaxEffectiveWeight(for exerciseId: UUID, reps: Int) throws -> Double? {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate {
                $0.exerciseId == exerciseId && $0.reps == reps
            },
            sortBy: [SortDescriptor(\.effectiveWeight, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.effectiveWeight
    }

    // MARK: - PR Recomputation (FR-006, FR-007)

    func fetchBestEligibleSet(
        for exerciseId: UUID,
        reps: Int,
        excludeWarmups: Bool,
        excludingSetId: UUID?
    ) throws -> WorkoutSet? {
        // Step 1: Database-level filter on exerciseId + reps, sorted for PR priority
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate {
                $0.exerciseId == exerciseId && $0.reps == reps
            },
            sortBy: [
                SortDescriptor(\.effectiveWeight, order: .reverse),
                SortDescriptor(\.date, order: .forward)
            ]
        )
        let sets = try modelContext.fetch(descriptor)

        // Step 2: Filter in Swift for eligibility (SwiftData #Predicate limitations —
        // hasData is computed, excludeFromPRs optional Bool, setType enum comparisons)
        return sets.first { set in
            guard set.hasData else { return false }
            guard set.excludeFromPRs != true else { return false }
            guard set.setType != .partial else { return false }
            if excludeWarmups && set.setType == .warmup { return false }
            if let excludeId = excludingSetId, set.id == excludeId { return false }
            return true
        }
    }

    // SwiftData has no native SUM — fetch and reduce in Swift.
    // For normal reads, callers should prefer ExerciseStats.totalVolume (pre-computed at write-time).
    // This method exists for rebuild scenarios.
    func fetchTotalVolume(for exerciseId: UUID) throws -> Double {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        let sets = try modelContext.fetch(descriptor)
        return sets.reduce(0.0) { total, set in
            total + (set.volume ?? 0.0)
        }
    }

    // MARK: - Aggregation — Database-level (specdoc S8.6)

    /// Aggregate stats for an exercise using SwiftData fetch + Swift reduce.
    ///
    /// Ideally this would use Core Data NSExpression for SQL-level SUM/MAX/COUNT,
    /// but SwiftData's @ModelActor doesn't expose NSManagedObjectContext cleanly,
    /// and NSExpression cannot compute SUM(col1 * col2) for volume.
    ///
    /// This is acceptable because:
    /// - Cold-path only (rebuild from Settings, not hot-path save)
    /// - Per-exercise fetch (bounded dataset, not all sets at once)
    /// - AGENT_RULES S5.2 prohibits loading ALL sets across ALL exercises;
    ///   per-exercise fetches are the documented acceptable pattern for rebuild
    func fetchAggregateStats(
        for exerciseId: UUID,
        excludeWarmups: Bool,
        excludePartial: Bool
    ) throws -> SetAggregateResult {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        let allSets = try modelContext.fetch(descriptor)

        // Apply eligibility filters (hasData + exclusions)
        let sets = allSets.filter { set in
            guard set.hasData else { return false }
            if excludePartial && set.setType == .partial { return false }
            if excludeWarmups && set.setType == .warmup { return false }
            return true
        }

        let totalSets = sets.count
        let totalReps = sets.reduce(0) { $0 + ($1.reps ?? 0) }
        let totalVolume = sets.reduce(0.0) { $0 + ($1.volume ?? 0.0) }
        let maxWeight = sets.reduce(0.0) { max($0, $1.effectiveWeight ?? 0.0) }
        let lastPerformedDate = sets.reduce(nil as Date?) { latest, set in
            guard let current = latest else { return set.date }
            return set.date > current ? set.date : current
        }

        return SetAggregateResult(
            totalSets: totalSets,
            totalReps: totalReps,
            totalVolume: totalVolume,
            maxWeight: maxWeight,
            lastPerformedDate: lastPerformedDate
        )
    }

    func fetchWorkoutCount(for exerciseId: UUID) throws -> Int {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        let sets = try modelContext.fetch(descriptor)
        let uniqueWorkoutIds = Set(sets.map(\.workoutId))
        return uniqueWorkoutIds.count
    }

    func fetchBestE1RM(for exerciseId: UUID) throws -> Double? {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate {
                $0.exerciseId == exerciseId && $0.e1RM != nil
            },
            sortBy: [SortDescriptor(\.e1RM, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.e1RM
    }
}
