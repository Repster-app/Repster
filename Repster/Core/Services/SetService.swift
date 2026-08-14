// SetService.swift
// Set save/edit/delete orchestration with full pipeline
// Spec: FR-001 through FR-006, FR-010, FR-012
// Source: specdoc S4, S5.4, S8; AGENT_RULES S3.3, S6

import Foundation

enum SetServiceError: Error {
    case setNotFound(UUID)
    case exerciseNotFound(UUID)
}

@MainActor
final class SetService: SetServiceProtocol {
    private let setRepo: SetRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol
    private let bodyweightEntryRepo: BodyweightEntryRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol
    private let prService: PRServiceProtocol
    private let statsService: StatsServiceProtocol
    private let fatigueLearningService: FatigueLearningService

    nonisolated init(
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol,
        bodyweightEntryRepository: BodyweightEntryRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol,
        prService: PRServiceProtocol,
        statsService: StatsServiceProtocol,
        fatigueLearningService: FatigueLearningService
    ) {
        self.setRepo = setRepository
        self.exerciseRepo = exerciseRepository
        self.bodyweightEntryRepo = bodyweightEntryRepository
        self.healthProfileRepo = healthProfileRepository
        self.prService = prService
        self.statsService = statsService
        self.fatigueLearningService = fatigueLearningService
    }

    // MARK: - SetServiceProtocol

    func create(
        workoutId: UUID,
        exerciseId: UUID,
        date: Date,
        setType: SetType,
        orderInWorkout: Int,
        orderInExercise: Int,
        weight: Double?,
        reps: Int?,
        leftReps: Int?,
        rightReps: Int?,
        rir: Double?,
        leftRIR: Double?,
        rightRIR: Double?
    ) async throws -> WorkoutSet {
        let set = try await setRepo.create(
            workoutId: workoutId,
            exerciseId: exerciseId,
            date: date,
            setType: setType,
            orderInWorkout: orderInWorkout,
            orderInExercise: orderInExercise,
            weight: weight,
            reps: reps,
            leftReps: leftReps,
            rightReps: rightReps,
            rir: rir,
            leftRIR: leftRIR,
            rightRIR: rightRIR
        )
        // A created row is `completed: false` and has not been performed, so it must not
        // contribute to PRs or stats. Every caller already assumes a fresh row is uncounted
        // (`EditWorkoutViewModel.uncountedSetIds`), and the contribution is added by the
        // completion path in `save(setId:input:)`.
        //
        // This used to call `save(set)` unconditionally, which was harmless only while every
        // creator passed `weight: nil, reps: nil` — no data, so no contribution. Copy Previous
        // creates prefilled rows: they were PR-evaluated before being lifted, counted in stats
        // immediately, and then counted a *second* time when the user ticked them off.
        try await persistWithoutContribution(set)
        return set
    }

    /// Commit a newly created row with the derivation and weight resolution it needs for
    /// display, deliberately stopping short of `save()`'s PR evaluation and stats update.
    ///
    /// e1RM is left unwritten: an unperformed row must not reach charts or feed any estimate.
    /// `save()` computes it at completion time.
    private func persistWithoutContribution(_ set: WorkoutSet) async throws {
        let exercise = try await exerciseRepo.fetchChartExercise(byId: set.exerciseId)
        let synced = try await setRepo.syncDerivedFields(on: set, exercise: exercise)
        let effectiveWeight = try await computeEffectiveWeight(
            weight: synced.weight,
            exerciseId: synced.exerciseId,
            date: synced.date
        )
        _ = try await setRepo.persist(
            set,
            effectiveWeight: effectiveWeight,
            e1RM: .leaveAlone,
            clearPRStatus: false,
            touchUpdatedAt: false
        )
    }

    func updateNote(setId: UUID, note: String?) async throws -> SetSaveResult {
        guard let set = try await setRepo.fetch(byId: setId) else {
            throw SetServiceError.setNotFound(setId)
        }
        try await setRepo.applyNote(setId: setId, note: note)
        return try await edit(set)
    }

    func changeSetType(setId: UUID, to type: SetType) async throws -> SetSaveResult {
        guard let set = try await setRepo.fetch(byId: setId) else {
            throw SetServiceError.setNotFound(setId)
        }
        try await setRepo.applySetType(setId: setId, type: type)
        return try await edit(set)
    }

    func save(setId: UUID, input: SetCompletionInput) async throws -> SetSaveResult {
        guard let set = try await setRepo.fetch(byId: setId) else {
            throw SetServiceError.setNotFound(setId)
        }
        let exercise = try await exerciseRepo.fetchChartExercise(byId: set.exerciseId)

        // The typed values and completion stamps are written inside the repository actor.
        // `ActiveWorkoutViewModel.completeSet` used to do this on the main actor, immediately
        // before handing the mutated model over.
        try await setRepo.applyCompletion(setId: setId, input: input, exercise: exercise)

        return try await save(set)
    }

    func save(_ set: WorkoutSet) async throws -> SetSaveResult {
        let exercise = try await exerciseRepo.fetchChartExercise(byId: set.exerciseId)

        // Unilateral derivation, applied inside the repository actor. No insert or save yet —
        // the single commit is `persist` below, matching the original `setRepo.save(set)`.
        let synced = try await setRepo.syncDerivedFields(on: set, exercise: exercise)

        // 1. Compute effectiveWeight (specdoc S5.4)
        let effectiveWeight = try await computeEffectiveWeight(
            weight: synced.weight,
            exerciseId: synced.exerciseId,
            date: synced.date
        )

        // 1b. Compute e1RM so charts reflect this set immediately. Reps come from the
        // post-derivation snapshot, since the derivation can rewrite them for per-side sets.
        // `.leaveAlone` when it doesn't qualify — save() has no else branch and never cleared
        // a previously stored estimate.
        var e1RMUpdate: E1RMUpdate = .leaveAlone
        if let ew = effectiveWeight, ew > 0, let reps = synced.reps, reps > 0 {
            let profile = try await healthProfileRepo.fetch()
            let formula = E1RMFormula(rawValue: profile?.e1RMFormula ?? "") ?? .epley
            e1RMUpdate = .set(
                value: formula.calculate(weight: ew, reps: reps),
                formulaVersion: formula.rawValue
            )
        }

        // 2. Persist immediately (FR-012)
        let persisted = try await setRepo.persist(
            set,
            effectiveWeight: effectiveWeight,
            e1RM: e1RMUpdate,
            clearPRStatus: !supportsRepPRs(for: exercise),
            touchUpdatedAt: false
        )
        set.markFatigueLearningSnapshotPersisted(effectiveWeightOverride: effectiveWeight)

        // 3. PR evaluation (FR-002)
        let prResult: PREvaluationResult
        if supportsRepPRs(for: exercise) {
            prResult = try await prService.evaluate(
                setId: persisted.id,
                exerciseId: persisted.exerciseId,
                reps: persisted.prReps,
                effectiveWeight: effectiveWeight ?? 0,
                workoutId: persisted.workoutId,
                setType: persisted.setType,
                hasData: persisted.hasData,
                excludeFromPRs: persisted.excludeFromPRs,
                date: persisted.date
            )
        } else {
            prResult = emptyPRResult(for: persisted.id)
        }

        // PRService skips writing PR status on the evaluated set itself
        // (it's returned via prResult.newStatus) — write it here, inside the repository
        // actor rather than on this @MainActor service.
        if supportsRepPRs(for: exercise) {
            try await setRepo.applyPRStatus(setId: persisted.id, status: prResult.newStatus)
        }

        // 4. Stats update (FR-003)
        try await statsService.updateStats(
            for: persisted.exerciseId,
            event: .save(
                setId: persisted.id,
                reps: persisted.statsReps,
                effectiveWeight: effectiveWeight ?? 0,
                setType: persisted.setType,
                hasData: persisted.hasData,
                date: persisted.date,
                workoutId: persisted.workoutId
            )
        )

        return SetSaveResult(
            setId: persisted.id,
            effectiveWeight: effectiveWeight ?? 0,
            prResult: prResult
        )
    }

    func edit(
        _ set: WorkoutSet,
        previousContribution: SetContributionSnapshot? = nil
    ) async throws -> SetSaveResult {
        let exercise = try await exerciseRepo.fetchChartExercise(byId: set.exerciseId)

        // Kept ahead of the old-contribution capture, where `set.syncDerivedPerformanceFields`
        // used to sit.
        //
        // As it happens the order cannot change `SetContributionSnapshot` today: the derivation
        // only writes `reps`/`rir`/`side`, while the snapshot's `statsReps` and `prReps` read
        // `leftReps`/`rightReps` whenever both are set, and fall back to `reps` only in the case
        // where the derivation writes it back unchanged. The original order is preserved anyway,
        // so this stays correct if that snapshot ever grows a field that does depend on it.
        let synced = try await setRepo.syncDerivedFields(on: set, exercise: exercise)

        // 1. Capture old values BEFORE changes (for stats delta)
        guard let oldSet = try await setRepo.fetch(byId: set.id) else {
            throw SetServiceError.setNotFound(set.id)
        }
        let oldContribution = previousContribution ?? SetContributionSnapshot(set: oldSet)
        let previousFatigueSnapshot = set.persistedFatigueSnapshot ?? oldSet.fatigueLearningSnapshot()

        // 2. Recompute effectiveWeight with new values (specdoc S5.4)
        let newEffectiveWeight = try await computeEffectiveWeight(
            weight: set.weight,
            exerciseId: set.exerciseId,
            date: set.date
        )

        // 2b. Recompute e1RM with updated values. Reps come from the post-derivation snapshot,
        // since the derivation above can rewrite them for per-side sets.
        // `.clear` rather than `.leaveAlone` when it no longer qualifies: edit() has an else
        // branch that nils the estimate while keeping the formula version that produced it.
        var e1RMUpdate: E1RMUpdate = .clear
        if let ew = newEffectiveWeight, ew > 0, let reps = synced.reps, reps > 0 {
            let profile = try await healthProfileRepo.fetch()
            let formula = E1RMFormula(rawValue: profile?.e1RMFormula ?? "") ?? .epley
            e1RMUpdate = .set(
                value: formula.calculate(weight: ew, reps: reps),
                formulaVersion: formula.rawValue
            )
        }

        // 3. Persist — mutation happens inside the repository actor, which owns the context.
        let updated = try await setRepo.persist(
            set,
            effectiveWeight: newEffectiveWeight,
            e1RM: e1RMUpdate,
            clearPRStatus: !supportsRepPRs(for: exercise),
            touchUpdatedAt: true
        )

        // 4. PR re-evaluation (FR-004)
        let prResult: PREvaluationResult
        if supportsRepPRs(for: exercise) {
            if oldContribution.prReps != updated.prReps {
                let deletionResult = try await prService.handleDeletion(
                    setId: oldContribution.setId,
                    exerciseId: oldContribution.exerciseId,
                    reps: oldContribution.prReps,
                    cachedPRStatus: oldContribution.cachedPRStatus
                )
                let evaluationResult = try await prService.evaluate(
                    setId: updated.id,
                    exerciseId: updated.exerciseId,
                    reps: updated.prReps,
                    effectiveWeight: newEffectiveWeight ?? 0,
                    workoutId: updated.workoutId,
                    setType: updated.setType,
                    hasData: updated.hasData,
                    excludeFromPRs: updated.excludeFromPRs,
                    date: updated.date
                )
                prResult = mergedPRResult(
                    setId: updated.id,
                    deletionResult: deletionResult,
                    evaluationResult: evaluationResult
                )
            } else {
                prResult = try await prService.evaluateAfterEdit(
                    setId: updated.id,
                    exerciseId: updated.exerciseId,
                    reps: updated.prReps,
                    effectiveWeight: newEffectiveWeight ?? 0,
                    workoutId: updated.workoutId,
                    setType: updated.setType,
                    hasData: updated.hasData,
                    excludeFromPRs: updated.excludeFromPRs,
                    previousCachedPRStatus: oldContribution.cachedPRStatus,
                    date: updated.date
                )
            }
        } else {
            prResult = emptyPRResult(for: set.id)
        }

        // PRService skips writing PR status on the evaluated set itself
        // (it's returned via prResult.newStatus) — write it here, inside the repository
        // actor rather than on this @MainActor service.
        if supportsRepPRs(for: exercise) {
            try await setRepo.applyPRStatus(setId: updated.id, status: prResult.newStatus)
        }

        // 5. Stats update with edit delta
        try await statsService.updateStats(
            for: updated.exerciseId,
            event: .edit(
                setId: updated.id,
                oldReps: oldContribution.statsReps,
                oldEffectiveWeight: oldContribution.effectiveWeight,
                oldSetType: oldContribution.setType,
                oldHasData: oldContribution.hasData,
                newReps: updated.statsReps,
                newEffectiveWeight: newEffectiveWeight ?? 0,
                newSetType: updated.setType,
                newHasData: updated.hasData,
                date: updated.date,
                workoutId: updated.workoutId
            )
        )

        let currentFatigueSnapshot = set.fatigueLearningSnapshot(effectiveWeightOverride: newEffectiveWeight)
        if try await fatigueLearningService.capturedSetDataNeedsInvalidation(
            setId: updated.id,
            workoutId: updated.workoutId,
            exerciseId: updated.exerciseId,
            previous: previousFatigueSnapshot,
            current: currentFatigueSnapshot
        ) {
            try await fatigueLearningService.removeCapturedSetData(setId: set.id)
        }
        set.persistedFatigueSnapshot = currentFatigueSnapshot

        return SetSaveResult(
            setId: updated.id,
            effectiveWeight: newEffectiveWeight ?? 0,
            prResult: prResult
        )
    }

    func uncomplete(
        _ set: WorkoutSet,
        previousContribution: SetContributionSnapshot? = nil
    ) async throws -> SetSaveResult {
        // 1. Capture old values BEFORE mutation (same pattern as delete)
        let oldContribution = previousContribution ?? SetContributionSnapshot(set: set)

        // 2/3. Mutate and persist inside the repository actor (flat write — no PR/stats
        // pipeline). The ViewModel holds the same @Model reference, so the cleared
        // completion and PR status are still visible to it immediately.
        try await setRepo.applyUncomplete(setId: set.id)
        set.markFatigueLearningSnapshotPersisted(effectiveWeightOverride: oldContribution.effectiveWeight)

        // 4. PR demotion — same as delete path
        // handleDeletion is a no-op if this set wasn't the PR owner
        let exercise = try await exerciseRepo.fetch(byId: oldContribution.exerciseId)
        let prResult: PREvaluationResult
        if supportsRepPRs(for: exercise) {
            prResult = try await prService.handleDeletion(
                setId: oldContribution.setId,
                exerciseId: oldContribution.exerciseId,
                reps: oldContribution.prReps,
                cachedPRStatus: oldContribution.cachedPRStatus
            )
        } else {
            prResult = emptyPRResult(for: oldContribution.setId)
        }

        // 5. Stats decrement — same as delete path
        try await statsService.updateStats(
            for: oldContribution.exerciseId,
            event: .delete(
                setId: oldContribution.setId,
                reps: oldContribution.statsReps,
                effectiveWeight: oldContribution.effectiveWeight,
                setType: oldContribution.setType,
                hasData: oldContribution.hasData,
                date: oldContribution.date,
                workoutId: oldContribution.workoutId
            )
        )

        try await fatigueLearningService.removeCapturedSetData(setId: oldContribution.setId)

        return SetSaveResult(
            setId: oldContribution.setId,
            effectiveWeight: oldContribution.effectiveWeight,
            prResult: prResult
        )
    }

    /// Delete a set and report the PR changes that fell out of it.
    ///
    /// The result used to be discarded here (`_ = try await prService.handleDeletion(...)`) and
    /// the method returned `Void`, so no caller could apply it. Deleting a PR owner promotes
    /// another set — `PRService` writes `winner.prStatus` directly (`:720`) — and that reached the
    /// screen *only* because the ViewModel happened to hold the same `@Model` instance the
    /// service mutated. Once `setsByExercise` holds value types that channel disappears and the
    /// badge would silently stay wrong until relaunch, so the result has to come back.
    ///
    /// Pinned by `AffectedSetsPreconditionTests.testDeletingAPROwnerPromotesAnotherSetThroughIdentityAlone`.
    func delete(_ set: WorkoutSet) async throws -> PREvaluationResult {
        // 1. Capture values before deletion
        let setId = set.id
        let exerciseId = set.exerciseId
        let reps = set.statsReps
        let prReps = set.prReps
        let effectiveWeight = set.effectiveWeight ?? 0
        let setType = set.setType
        let hasData = set.hasData
        let cachedPRStatus = set.prStatus
        let date = set.date
        let workoutId = set.workoutId

        // 2. Delete set (hard delete — specdoc S4.4)
        try await setRepo.delete(set)

        // 3. PR recomputation (FR-005)
        let exercise = try await exerciseRepo.fetch(byId: exerciseId)
        let prResult: PREvaluationResult
        if supportsRepPRs(for: exercise) {
            prResult = try await prService.handleDeletion(
                setId: setId,
                exerciseId: exerciseId,
                reps: prReps,
                cachedPRStatus: cachedPRStatus
            )
        } else {
            prResult = PREvaluationResult(
                setId: setId,
                newStatus: nil,
                affectedSetIds: [:],
                prRecordChanged: false
            )
        }

        // 4. Stats decrement
        try await statsService.updateStats(
            for: exerciseId,
            event: .delete(
                setId: setId,
                reps: reps,
                effectiveWeight: effectiveWeight,
                setType: setType,
                hasData: hasData,
                date: date,
                workoutId: workoutId
            )
        )

        try await fatigueLearningService.removeCapturedSetData(setId: setId)

        return prResult
    }

    func updateInProgressTargetRepOverride(
        setId: UUID,
        min: Int?,
        max: Int?
    ) async throws {
        try await setRepo.applyTargetRepOverride(setId: setId, min: min, max: max)
    }

    // MARK: - Fetch (006: Active Workout Screen)

    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet] {
        try await setRepo.fetchSets(for: workoutId)
    }

    func fetchSetSnapshots(for workoutId: UUID) async throws -> [ChartSetData] {
        try await setRepo.fetchChartSets(for: workoutId)
    }

    func applyOrdering(_ updates: [SetOrderUpdate]) async throws {
        try await setRepo.applyOrdering(updates)
    }

    func fetchExerciseIds(for workoutId: UUID) async throws -> Swift.Set<UUID> {
        return try await setRepo.fetchExerciseIds(for: workoutId)
    }

    // MARK: - Fetch by Exercise (007: Exercise List + Detail)

    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet] {
        try await setRepo.fetchSets(for: exerciseId, limit: limit)
    }

    func fetchSetSnapshots(for exerciseId: UUID, limit: Int?) async throws -> [ChartSetData] {
        try await setRepo.fetchChartSets(for: exerciseId, limit: limit)
    }

    // MARK: - Helpers

    /// Compute effectiveWeight per specdoc S5.4.
    /// effectiveWeight = weight + (closestBodyweight x exercise.bodyweightFactor)
    /// If bodyweightFactor == 0 -> effectiveWeight = weight
    /// If no bodyweight entry -> effectiveWeight = weight
    private func computeEffectiveWeight(
        weight: Double?,
        exerciseId: UUID,
        date: Date
    ) async throws -> Double? {
        guard let weight else { return nil }

        guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else {
            return weight
        }

        guard exercise.bodyweightFactor > 0 else {
            return weight
        }

        let profile = try await healthProfileRepo.fetchOrCreate()
        let closestEntry = try await bodyweightEntryRepo.fetchClosest(
            to: date,
            healthProfileId: profile.id
        )

        guard let bodyweight = closestEntry?.bodyweightKg else {
            return weight
        }

        return weight + (bodyweight * exercise.bodyweightFactor)
    }

    private func supportsRepPRs(for exercise: Exercise?) -> Bool {
        exercise?.trackingType.supportsRepPRs == true
    }

    private func supportsRepPRs(for exercise: ChartExerciseData?) -> Bool {
        exercise?.trackingType.supportsRepPRs == true
    }

    private func emptyPRResult(for setId: UUID) -> PREvaluationResult {
        PREvaluationResult(
            setId: setId,
            newStatus: nil,
            affectedSetIds: [:],
            prRecordChanged: false
        )
    }

    private func mergedPRResult(
        setId: UUID,
        deletionResult: PREvaluationResult,
        evaluationResult: PREvaluationResult
    ) -> PREvaluationResult {
        var affectedSetIds = deletionResult.affectedSetIds
        for (affectedSetId, status) in evaluationResult.affectedSetIds {
            affectedSetIds[affectedSetId] = status
        }
        affectedSetIds.removeValue(forKey: setId)

        return PREvaluationResult(
            setId: setId,
            newStatus: evaluationResult.newStatus,
            affectedSetIds: affectedSetIds,
            prRecordChanged: deletionResult.prRecordChanged || evaluationResult.prRecordChanged
        )
    }
}
