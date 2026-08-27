// StatsService.swift
// Incremental ExerciseStats updates at write-time
// Spec: FR-007, FR-008, FR-009
// Source: specdoc S8.4, S8.6; AGENT_RULES S5.2, S5.5, S6

import Foundation

actor StatsService: StatsServiceProtocol {
    private let exerciseStatsRepo: ExerciseStatsRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol
    private let performanceRecordRepo: PerformanceRecordRepositoryProtocol

    init(
        exerciseStatsRepository: ExerciseStatsRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol,
        performanceRecordRepository: PerformanceRecordRepositoryProtocol
    ) {
        self.exerciseStatsRepo = exerciseStatsRepository
        self.setRepo = setRepository
        self.exerciseRepo = exerciseRepository
        self.healthProfileRepo = healthProfileRepository
        self.performanceRecordRepo = performanceRecordRepository
    }

    // MARK: - StatsServiceProtocol

    func updateStats(for exerciseId: UUID, event: StatsUpdateEvent) async throws {
        let profile = try await healthProfileRepo.fetchOrCreate()
        let includeWarmups = profile.includeWarmupsInVolume

        switch event {
        case .save(let setId, let reps, let effectiveWeight, let setType, let hasData, let date, let workoutId):
            try await handleSave(
                exerciseId: exerciseId, setId: setId, reps: reps, effectiveWeight: effectiveWeight,
                setType: setType, hasData: hasData, date: date, workoutId: workoutId,
                includeWarmups: includeWarmups
            )

        case .edit(let setId,
                   let oldReps, let oldEW, let oldSetType, let oldHasData,
                   let newReps, let newEW, let newSetType, let newHasData,
                   let date, let workoutId):
            try await handleEdit(
                exerciseId: exerciseId, setId: setId,
                oldReps: oldReps, oldEffectiveWeight: oldEW, oldSetType: oldSetType, oldHasData: oldHasData,
                newReps: newReps, newEffectiveWeight: newEW, newSetType: newSetType, newHasData: newHasData,
                date: date, workoutId: workoutId, includeWarmups: includeWarmups
            )

        case .delete(let setId, let reps, let effectiveWeight, let setType, let hasData, let date, let workoutId):
            try await handleDelete(
                exerciseId: exerciseId, setId: setId, reps: reps, effectiveWeight: effectiveWeight,
                setType: setType, hasData: hasData, date: date, workoutId: workoutId,
                includeWarmups: includeWarmups
            )
        }
    }

    func rebuildAll() async throws {
        let exercises = try await exerciseRepo.fetchAll()
        for exercise in exercises {
            try await rebuild(for: exercise.id)
        }
    }

    func rebuild(for exerciseId: UUID) async throws {
        let profile = try await healthProfileRepo.fetchOrCreate()
        let excludeWarmups = !profile.includeWarmupsInVolume

        // 1. Delete existing stats
        if let existingStats = try await exerciseStatsRepo.fetch(for: exerciseId) {
            try await exerciseStatsRepo.delete(existingStats)
        }

        // 2. Aggregate from raw sets (specdoc S8.6)
        let aggregate = try await setRepo.fetchAggregateStats(
            for: exerciseId,
            excludeWarmups: excludeWarmups,
            excludePartial: true
        )

        // 3. Get additional stats not covered by basic aggregation
        let workoutCount = try await setRepo.fetchWorkoutCount(
            for: exerciseId,
            excludeWarmups: excludeWarmups
        )
        let bestE1RM = try await setRepo.fetchBestE1RM(for: exerciseId)

        // 4. Get most recent PR date from PerformanceRecords
        let allPRs = try await performanceRecordRepo.fetchAll(for: exerciseId)
        let lastPRDate = allPRs.map(\.date).max()

        // 5. Compute e1RM trend slope from recent sets
        let trendSlope = try await computeE1RMTrendSlope(for: exerciseId)

        // 6. Create new ExerciseStats and persist
        let newStats = ExerciseStats(
            exerciseId: exerciseId,
            totalWorkouts: workoutCount,
            totalSets: aggregate.totalSets,
            totalReps: aggregate.totalReps,
            totalVolume: aggregate.totalVolume,
            maxWeight: aggregate.maxWeight,
            bestE1RM: bestE1RM ?? 0,
            estimated1RMTrendSlope: trendSlope,
            lastPRDate: lastPRDate,
            lastPerformedDate: aggregate.lastPerformedDate
        )
        try await exerciseStatsRepo.save(newStats)
    }

    // MARK: - Read (007: Exercise List + Detail)

    func fetchStats(for exerciseId: UUID) async throws -> ExerciseStats? {
        try await exerciseStatsRepo.fetch(for: exerciseId)
    }

    func fetchStatsSnapshot(for exerciseId: UUID) async throws -> ChartExerciseStatsData? {
        try await exerciseStatsRepo.fetchChartExerciseStats(for: exerciseId)
    }

    func fetchAllStats() async throws -> [UUID: ExerciseStats] {
        let allStats = try await exerciseStatsRepo.fetchAll()
        return Dictionary(uniqueKeysWithValues: allStats.map { ($0.exerciseId, $0) })
    }

    // MARK: - Recent PRs (Home Screen)

    func fetchRecentPRs(since: Date, limit: Int, scope: RecentPRScope) async throws -> [PerformanceRecordSummaryData] {
        let records = try await performanceRecordRepo.fetchRecentRepMaxRecordSummaries(since: since)

        // Resolve the user's e1RM formula once (only used for .e1RMOnly scope)
        let profile = try await healthProfileRepo.fetchOrCreate()
        let formula = E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley

        var seen = Set<UUID>()
        var repMaxesByExercise: [UUID: [PerformanceRecordSummaryData]] = [:]
        var result: [PerformanceRecordSummaryData] = []
        for record in records {
            guard let exercise = try await exerciseRepo.fetchChartExercise(byId: record.exerciseId),
                  exercise.trackingType.supportsRepPRs,
                  let recordReps = record.reps,
                  recordReps > 0 else {
                continue
            }
            // One card per exercise — an exercise only counts as seen once a
            // record of its own actually made the list, so a dominated newest
            // record falls through to the last PR that still stands.
            guard !seen.contains(record.exerciseId) else { continue }

            let validRepMaxes: [PerformanceRecordSummaryData]
            if let cached = repMaxesByExercise[record.exerciseId] {
                validRepMaxes = cached
            } else {
                let allRepMaxes = try await performanceRecordRepo.fetchAllSummaries(
                    for: record.exerciseId,
                    recordType: .repMax
                )
                validRepMaxes = allRepMaxes.filter { ($0.reps ?? 0) > 0 }
                repMaxesByExercise[record.exerciseId] = validRepMaxes
            }
            guard !validRepMaxes.isEmpty else { continue }

            // A rep-bucket record dominated by a higher-rep record at the same or
            // greater weight is not a PR anywhere else in the app — its own set
            // carries no badge (CachedPRStatus.dominated), so Home must not claim
            // one either. 60 kg x 7 says nothing new once 60 kg x 8 is on the board.
            let frontierReps = PRFrontier.frontierReps(
                validRepMaxes.map { (reps: $0.reps ?? 0, value: $0.value) }
            )
            guard frontierReps.contains(recordReps) else { continue }

            if scope == .e1RMOnly {
                // Only include the record if its e1RM is the best across all rep buckets
                let recordE1RM = formula.calculate(weight: record.value, reps: recordReps)
                let bestE1RM = validRepMaxes.map {
                    formula.calculate(weight: $0.value, reps: $0.reps ?? 1)
                }.max() ?? 0

                guard recordE1RM >= bestE1RM else { continue }
            }

            seen.insert(record.exerciseId)
            result.append(record)
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - Eligibility

    /// Determines if a set should be counted for stats calculations.
    /// Partial sets are always excluded. Warmup sets excluded when setting is off.
    /// Sets without data (hasData = false) are always excluded.
    private func shouldCountForStats(
        setType: SetType,
        hasData: Bool,
        includeWarmupsInVolume: Bool
    ) -> Bool {
        guard hasData else { return false }
        if setType == .partial { return false }
        if setType == .warmup && !includeWarmupsInVolume { return false }
        return true
    }

    // MARK: - Workout membership (totalWorkouts)

    /// Whether a persisted set makes its workout count toward `totalWorkouts`.
    ///
    /// Same eligibility rule as the running totals, plus `completed`: uncompleting a set
    /// removes its contribution (SetService.uncomplete emits a `.delete` event), so an
    /// uncompleted row must not keep the workout counted either.
    private func establishesWorkoutMembership(_ set: WorkoutSet, includeWarmups: Bool) -> Bool {
        guard set.completed else { return false }
        return shouldCountForStats(
            setType: set.setType,
            hasData: set.hasData,
            includeWarmupsInVolume: includeWarmups
        )
    }

    /// Membership state of one workout for one exercise, split by the set being written.
    ///
    /// Reads the persisted rows of a single workout — bounded by the sets in that session,
    /// so this stays cheap on the save path. `subject` reflects the row as it stands after
    /// the write; `others` is what the workout's remaining rows say on their own.
    private func workoutMembership(
        exerciseId: UUID,
        workoutId: UUID,
        subjectSetId: UUID,
        includeWarmups: Bool
    ) async throws -> (subject: Bool, others: Bool) {
        let workoutSets = try await setRepo.fetchSets(for: workoutId)
        var subject = false
        var others = false
        for set in workoutSets where set.exerciseId == exerciseId {
            guard establishesWorkoutMembership(set, includeWarmups: includeWarmups) else { continue }
            if set.id == subjectSetId {
                subject = true
            } else {
                others = true
            }
        }
        return (subject, others)
    }

    // MARK: - Save (T013)

    private func handleSave(
        exerciseId: UUID, setId: UUID, reps: Int, effectiveWeight: Double,
        setType: SetType, hasData: Bool, date: Date, workoutId: UUID,
        includeWarmups: Bool
    ) async throws {
        // 1. Get or create ExerciseStats
        var stats = try await exerciseStatsRepo.fetch(for: exerciseId)
        let isNew = (stats == nil)

        if isNew {
            stats = ExerciseStats(exerciseId: exerciseId)
        }
        guard let stats else { return }

        // 2. Check eligibility
        guard shouldCountForStats(setType: setType, hasData: hasData, includeWarmupsInVolume: includeWarmups) else {
            if isNew {
                try await exerciseStatsRepo.save(stats)
            }
            return
        }

        // 3. Increment totals (pure arithmetic — O(1))
        stats.totalSets += 1
        stats.totalReps += reps
        stats.totalVolume += effectiveWeight * Double(reps)

        // 4. Update maxWeight if this set is heavier
        if effectiveWeight > stats.maxWeight {
            stats.maxWeight = effectiveWeight
        }

        // 5. Update lastPerformedDate
        if let lastDate = stats.lastPerformedDate {
            if date > lastDate {
                stats.lastPerformedDate = date
            }
        } else {
            stats.lastPerformedDate = date
        }

        // 6. Update totalWorkouts — a workout counts once, from the first set that
        //    contributes to stats. Rows that contribute nothing (the empty placeholder
        //    row added with the exercise, warmups while they're excluded, partials) must
        //    neither establish membership nor block the first real set from doing so —
        //    hence an eligibility check rather than a row count.
        let membership = try await workoutMembership(
            exerciseId: exerciseId,
            workoutId: workoutId,
            subjectSetId: setId,
            includeWarmups: includeWarmups
        )
        if membership.subject && !membership.others {
            stats.totalWorkouts += 1
        }

        // 7. Persist
        stats.updatedAt = Date()
        try await exerciseStatsRepo.save(stats)
    }

    // MARK: - Edit (T014)

    private func handleEdit(
        exerciseId: UUID, setId: UUID,
        oldReps: Int, oldEffectiveWeight: Double, oldSetType: SetType, oldHasData: Bool,
        newReps: Int, newEffectiveWeight: Double, newSetType: SetType, newHasData: Bool,
        date: Date, workoutId: UUID, includeWarmups: Bool
    ) async throws {
        guard let stats = try await exerciseStatsRepo.fetch(for: exerciseId) else { return }

        let oldCounted = shouldCountForStats(setType: oldSetType, hasData: oldHasData, includeWarmupsInVolume: includeWarmups)
        let newCounted = shouldCountForStats(setType: newSetType, hasData: newHasData, includeWarmupsInVolume: includeWarmups)

        if oldCounted && newCounted {
            // Both counted — adjust by delta
            stats.totalReps += (newReps - oldReps)
            let oldVolume = oldEffectiveWeight * Double(oldReps)
            let newVolume = newEffectiveWeight * Double(newReps)
            stats.totalVolume += (newVolume - oldVolume)

            if newEffectiveWeight > stats.maxWeight {
                stats.maxWeight = newEffectiveWeight
            } else if oldEffectiveWeight >= stats.maxWeight && newEffectiveWeight < oldEffectiveWeight {
                stats.maxWeight = try await recomputeMaxWeight(for: exerciseId)
            }
        } else if oldCounted && !newCounted {
            // Was counted, no longer — decrement
            stats.totalSets -= 1
            stats.totalReps -= oldReps
            stats.totalVolume -= oldEffectiveWeight * Double(oldReps)
            if oldEffectiveWeight >= stats.maxWeight {
                stats.maxWeight = try await recomputeMaxWeight(for: exerciseId)
            }
        } else if !oldCounted && newCounted {
            // Was not counted, now is — increment
            stats.totalSets += 1
            stats.totalReps += newReps
            stats.totalVolume += newEffectiveWeight * Double(newReps)
            if newEffectiveWeight > stats.maxWeight {
                stats.maxWeight = newEffectiveWeight
            }
        }
        // Neither counted — no change

        // An edit that flips eligibility can also flip whether this workout counts —
        // e.g. clearing the only working set's reps, or turning a warmup into a working
        // set. Only the workout's own rows are read, so this stays off the slow path.
        if oldCounted != newCounted {
            let membership = try await workoutMembership(
                exerciseId: exerciseId,
                workoutId: workoutId,
                subjectSetId: setId,
                includeWarmups: includeWarmups
            )
            if !membership.others {
                if membership.subject && !oldCounted {
                    stats.totalWorkouts += 1
                } else if !membership.subject && oldCounted {
                    stats.totalWorkouts = max(0, stats.totalWorkouts - 1)
                }
            }
        }

        stats.updatedAt = Date()
        try await exerciseStatsRepo.save(stats)
    }

    // MARK: - Delete (T015)

    private func handleDelete(
        exerciseId: UUID, setId: UUID, reps: Int, effectiveWeight: Double,
        setType: SetType, hasData: Bool, date: Date, workoutId: UUID,
        includeWarmups: Bool
    ) async throws {
        guard let stats = try await exerciseStatsRepo.fetch(for: exerciseId) else { return }

        let wasCounted = shouldCountForStats(setType: setType, hasData: hasData, includeWarmupsInVolume: includeWarmups)

        if wasCounted {
            stats.totalSets = max(0, stats.totalSets - 1)
            stats.totalReps = max(0, stats.totalReps - reps)
            stats.totalVolume = max(0, stats.totalVolume - effectiveWeight * Double(reps))

            if effectiveWeight >= stats.maxWeight {
                stats.maxWeight = try await recomputeMaxWeight(for: exerciseId)
            }
        }

        // Drop the workout from totalWorkouts once nothing in it contributes to stats
        // any more. Leftover rows that never counted (placeholders, excluded warmups)
        // must not keep the workout on the books; this also covers `uncomplete`, where
        // the row survives but stops contributing.
        if wasCounted {
            let membership = try await workoutMembership(
                exerciseId: exerciseId,
                workoutId: workoutId,
                subjectSetId: setId,
                includeWarmups: includeWarmups
            )
            if !membership.subject && !membership.others {
                stats.totalWorkouts = max(0, stats.totalWorkouts - 1)
            }
        }

        stats.updatedAt = Date()
        try await exerciseStatsRepo.save(stats)
    }

    // MARK: - Helpers

    /// Re-query maxWeight across all reps for an exercise.
    /// Only called when the previous max might have been reduced (edit down / delete).
    /// Loads sets for one exercise — acceptable for this rare operation.
    private func recomputeMaxWeight(for exerciseId: UUID) async throws -> Double {
        let allSets = try await setRepo.fetchSets(for: exerciseId, limit: nil)
        return allSets
            .filter { $0.hasData }
            .compactMap(\.effectiveWeight)
            .max() ?? 0
    }

    /// Compute the e1RM trend slope over the last 60 days using linear regression.
    /// Returns slope in units of kg/day. Positive = improving.
    private func computeE1RMTrendSlope(for exerciseId: UUID) async throws -> Double {
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let recentSets = try await setRepo.fetchSets(exerciseId: exerciseId, from: sixtyDaysAgo, to: Date())

        // Filter to sets that have e1RM computed
        let setsWithE1RM = recentSets.filter { $0.e1RM != nil && $0.e1RM! > 0 }
        guard !setsWithE1RM.isEmpty else { return 0 }

        // Group by day, take max e1RM per day
        let calendar = Calendar.current
        var bestByDay: [Date: Double] = [:]
        for set in setsWithE1RM {
            let day = calendar.startOfDay(for: set.date)
            let e1rm = set.e1RM!
            if let existing = bestByDay[day] {
                bestByDay[day] = max(existing, e1rm)
            } else {
                bestByDay[day] = e1rm
            }
        }

        let sortedDays = bestByDay.sorted { $0.key < $1.key }
        guard sortedDays.count >= 3 else { return 0 }

        // Linear regression: x = days since first data point, y = e1RM
        let referenceDate = sortedDays[0].key
        let n = Double(sortedDays.count)
        var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0
        for (day, e1rm) in sortedDays {
            let x = day.timeIntervalSince(referenceDate) / 86400.0
            sumX += x
            sumY += e1rm
            sumXY += x * e1rm
            sumX2 += x * x
        }

        let denominator = n * sumX2 - sumX * sumX
        guard denominator > 0 else { return 0 }

        return (n * sumXY - sumX * sumY) / denominator
    }
}
