import SwiftData
import Foundation

@ModelActor
actor SetRepository: SetRepositoryProtocol {

    // MARK: - CRUD

    func save(_ set: WorkoutSet) throws {
        modelContext.insert(set)
        try modelContext.save()
    }

    // MARK: - Mutation
    //
    // Fetch, mutate and save inside the actor that owns the context. `SetService` is
    // `@MainActor`, so every one of these assignments used to happen on the main thread
    // against a model this context owns — the non-main cross-context write in §5.5 of
    // SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md.

    /// Clear a set's completion and PR status. Used by the uncomplete pipeline.
    func applyUncomplete(setId: UUID) throws {
        guard let set = try fetch(byId: setId) else { return }
        set.completed = false
        set.completedAt = nil
        set.prStatus = nil
        set.updatedAt = Date()
        try modelContext.save()
    }

    /// Apply the unilateral derivation and return the resulting snapshot.
    ///
    /// Deliberately does **not** insert or save. `save()` calls this on sets that are not in
    /// the store yet, and both pipelines commit exactly once — in `persist(_:applying:)` —
    /// which is the same single transaction the previous `setRepo.save(set)` produced.
    func syncDerivedFields(on set: WorkoutSet, exercise: ChartExerciseData?) throws -> ChartSetData {
        set.syncDerivedPerformanceFields(for: exercise)
        return ChartSetData(from: set)
    }

    /// Insert if new, apply the pipeline's computed values, save, and return the snapshot.
    func persist(
        _ set: WorkoutSet,
        effectiveWeight: Double?,
        e1RM: E1RMUpdate,
        clearPRStatus: Bool,
        touchUpdatedAt: Bool
    ) throws -> ChartSetData {
        set.effectiveWeight = effectiveWeight

        switch e1RM {
        case .leaveAlone:
            break
        case .clear:
            set.e1RM = nil
        case let .set(value, formulaVersion):
            set.e1RM = value
            set.e1RMFormulaVersion = formulaVersion
        }

        if clearPRStatus {
            set.prStatus = nil
        }
        if touchUpdatedAt {
            set.updatedAt = Date()
        }

        // Inserting an object the context already owns is a no-op, so this covers both a
        // brand-new set from `addSet` and an existing one being re-saved.
        modelContext.insert(set)
        try modelContext.save()
        return ChartSetData(from: set)
    }

    /// Write the PR status the PR pipeline returned for a set.
    func applyPRStatus(setId: UUID, status: CachedPRStatus?) throws {
        guard let set = try fetch(byId: setId), set.prStatus != status else { return }
        set.prStatus = status
        try modelContext.save()
    }

    /// Persist rep-target override guidance without touching any other field.
    func applyTargetRepOverride(setId: UUID, min: Int?, max: Int?) throws {
        guard let set = try fetch(byId: setId) else {
            throw SetServiceError.setNotFound(setId)
        }
        set.overrideTargetRepMin = min
        set.overrideTargetRepMax = max
        set.updatedAt = Date()
        try modelContext.save()
    }

    /// Apply set ordering changes inside this actor, in a single transaction.
    ///
    /// Replaces the previous "one `SetService.edit()` per changed set, each in its own
    /// unawaited `Task`" reindex. Ordering is not a PR/stats/fatigue concern, so this
    /// deliberately does not run that pipeline — with identical values it was a no-op that
    /// cost N saves and manufactured the overlap described in §5.3 of the crash analysis.
    func applyOrdering(_ updates: [SetOrderUpdate]) throws {
        guard !updates.isEmpty else { return }

        for update in updates {
            guard let set = try fetch(byId: update.setId) else { continue }

            var didChangeThisSet = false
            if let orderInExercise = update.orderInExercise, set.orderInExercise != orderInExercise {
                set.orderInExercise = orderInExercise
                didChangeThisSet = true
            }
            if let orderInWorkout = update.orderInWorkout, set.orderInWorkout != orderInWorkout {
                set.orderInWorkout = orderInWorkout
                didChangeThisSet = true
            }

            if didChangeThisSet {
                set.updatedAt = Date()
            }
        }

        // Commit unconditionally. The comparisons above decide whether to bump `updatedAt`
        // — they cannot decide whether a save is needed. `ActiveWorkoutViewModel` holds this
        // context's own models and reindexes them on the main actor *before* calling here,
        // so `fetch(byId:)` returns the very instance it already mutated and every
        // comparison reads as "unchanged". Short-circuiting on that left the reindex sitting
        // uncommitted until some unrelated later write on this context happened to flush it.
        // Saving with no pending changes is a no-op, so the guard bought nothing.
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
        let sets = try modelContext.fetch(descriptor)
        sets.forEach { $0.markFatigueLearningSnapshotPersisted() }
        return sets
    }

    // MARK: - Exercise Queries (FR-004)

    func fetchSets(for exerciseId: UUID, limit: Int? = nil) throws -> [WorkoutSet] {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        let sets = try modelContext.fetch(descriptor)
        sets.forEach { $0.markFatigueLearningSnapshotPersisted() }
        return sets
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

    /// Snapshot equivalent of `fetchSets(for workoutId:)`, ordered by orderInWorkout.
    /// Used by Home, Calendar and the workout-detail screens.
    func fetchChartSets(for workoutId: UUID) throws -> [ChartSetData] {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == workoutId },
            sortBy: [SortDescriptor(\.orderInWorkout)]
        )
        return try modelContext.fetch(descriptor).map(ChartSetData.init(from:))
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
        excludingSetId: UUID?,
        excludedWorkoutIds: Set<UUID>
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
            if excludedWorkoutIds.contains(set.workoutId) { return false }
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
        let totalReps = sets.reduce(0) { $0 + $1.statsReps }
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

    func fetchWorkoutCount(for exerciseId: UUID, excludeWarmups: Bool) throws -> Int {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        let sets = try modelContext.fetch(descriptor)
        let performedIn = sets.lazy
            .filter { set in
                guard set.completed, set.hasData else { return false }
                if set.setType == .partial { return false }
                if excludeWarmups && set.setType == .warmup { return false }
                return true
            }
            .map(\.workoutId)
        return Set(performedIn).count
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
