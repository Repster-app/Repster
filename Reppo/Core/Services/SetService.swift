// SetService.swift
// Set save/edit/delete orchestration with full pipeline
// Spec: FR-001 through FR-006, FR-010, FR-012
// Source: specdoc S4, S5.4, S8; AGENT_RULES S3.3, S6

import Foundation

enum SetServiceError: Error {
    case setNotFound(UUID)
    case exerciseNotFound(UUID)
}

actor SetService: SetServiceProtocol {
    private let setRepo: SetRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol
    private let bodyweightEntryRepo: BodyweightEntryRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol
    private let prService: PRServiceProtocol
    private let statsService: StatsServiceProtocol

    init(
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol,
        bodyweightEntryRepository: BodyweightEntryRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol,
        prService: PRServiceProtocol,
        statsService: StatsServiceProtocol
    ) {
        self.setRepo = setRepository
        self.exerciseRepo = exerciseRepository
        self.bodyweightEntryRepo = bodyweightEntryRepository
        self.healthProfileRepo = healthProfileRepository
        self.prService = prService
        self.statsService = statsService
    }

    // MARK: - SetServiceProtocol

    func save(_ set: WorkoutSet) async throws -> SetSaveResult {
        // 1. Compute effectiveWeight (specdoc S5.4)
        let effectiveWeight = try await computeEffectiveWeight(
            weight: set.weight,
            exerciseId: set.exerciseId,
            date: set.date
        )
        set.effectiveWeight = effectiveWeight

        // 1b. Compute e1RM so charts reflect this set immediately
        if let ew = effectiveWeight, ew > 0, let reps = set.reps, reps > 0 {
            let profile = try await healthProfileRepo.fetch()
            let formula = E1RMFormula(rawValue: profile?.e1RMFormula ?? "") ?? .epley
            set.e1RM = formula.calculate(weight: ew, reps: reps)
            set.e1RMFormulaVersion = formula.rawValue
        }

        // 2. Persist immediately (FR-012)
        try await setRepo.save(set)

        // 3. PR evaluation (FR-002)
        let prResult = try await prService.evaluate(
            setId: set.id,
            exerciseId: set.exerciseId,
            reps: set.reps ?? 0,
            effectiveWeight: effectiveWeight ?? 0,
            workoutId: set.workoutId,
            setType: set.setType,
            hasData: set.hasData,
            excludeFromPRs: set.excludeFromPRs ?? false,
            date: set.date
        )

        // 4. Stats update (FR-003)
        try await statsService.updateStats(
            for: set.exerciseId,
            event: .save(
                reps: set.reps ?? 0,
                effectiveWeight: effectiveWeight ?? 0,
                setType: set.setType,
                hasData: set.hasData,
                date: set.date,
                workoutId: set.workoutId
            )
        )

        return SetSaveResult(
            setId: set.id,
            effectiveWeight: effectiveWeight ?? 0,
            prResult: prResult
        )
    }

    func edit(_ set: WorkoutSet) async throws -> SetSaveResult {
        // 1. Capture old values BEFORE changes (for stats delta)
        guard let oldSet = try await setRepo.fetch(byId: set.id) else {
            throw SetServiceError.setNotFound(set.id)
        }
        let oldReps = oldSet.reps ?? 0
        let oldEffectiveWeight = oldSet.effectiveWeight ?? 0
        let oldSetType = oldSet.setType
        let oldHasData = oldSet.hasData
        let oldCachedPRStatus = oldSet.cachedPRStatus

        // 2. Recompute effectiveWeight with new values (specdoc S5.4)
        let newEffectiveWeight = try await computeEffectiveWeight(
            weight: set.weight,
            exerciseId: set.exerciseId,
            date: set.date
        )
        set.effectiveWeight = newEffectiveWeight
        set.updatedAt = Date()

        // 2b. Recompute e1RM with updated values
        if let ew = newEffectiveWeight, ew > 0, let reps = set.reps, reps > 0 {
            let profile = try await healthProfileRepo.fetch()
            let formula = E1RMFormula(rawValue: profile?.e1RMFormula ?? "") ?? .epley
            set.e1RM = formula.calculate(weight: ew, reps: reps)
            set.e1RMFormulaVersion = formula.rawValue
        } else {
            set.e1RM = nil
        }

        // 3. Persist updated set
        try await setRepo.save(set)

        // 4. PR re-evaluation (FR-004)
        let prResult = try await prService.evaluateAfterEdit(
            setId: set.id,
            exerciseId: set.exerciseId,
            reps: set.reps ?? 0,
            effectiveWeight: newEffectiveWeight ?? 0,
            workoutId: set.workoutId,
            setType: set.setType,
            hasData: set.hasData,
            excludeFromPRs: set.excludeFromPRs ?? false,
            previousCachedPRStatus: oldCachedPRStatus,
            date: set.date
        )

        // 5. Stats update with edit delta
        try await statsService.updateStats(
            for: set.exerciseId,
            event: .edit(
                oldReps: oldReps,
                oldEffectiveWeight: oldEffectiveWeight,
                oldSetType: oldSetType,
                oldHasData: oldHasData,
                newReps: set.reps ?? 0,
                newEffectiveWeight: newEffectiveWeight ?? 0,
                newSetType: set.setType,
                newHasData: set.hasData,
                date: set.date,
                workoutId: set.workoutId
            )
        )

        return SetSaveResult(
            setId: set.id,
            effectiveWeight: newEffectiveWeight ?? 0,
            prResult: prResult
        )
    }

    func uncomplete(_ set: WorkoutSet) async throws -> SetSaveResult {
        // 1. Capture old values BEFORE mutation (same pattern as delete)
        let setId = set.id
        let exerciseId = set.exerciseId
        let reps = set.reps ?? 0
        let effectiveWeight = set.effectiveWeight ?? 0
        let setType = set.setType
        let hasData = set.hasData
        let cachedPRStatus = set.cachedPRStatus
        let date = set.date
        let workoutId = set.workoutId

        // 2. Mutate the set — mark as uncompleted, clear PR status
        set.completed = false
        set.completedAt = nil
        set.cachedPRStatus = nil
        set.updatedAt = Date()

        // 3. Persist (flat save — no PR/stats pipeline)
        try await setRepo.save(set)

        // 4. PR demotion — same as delete path
        // handleDeletion is a no-op if this set wasn't the PR owner
        let prResult = try await prService.handleDeletion(
            setId: setId,
            exerciseId: exerciseId,
            reps: reps,
            cachedPRStatus: cachedPRStatus
        )

        // 5. Stats decrement — same as delete path
        try await statsService.updateStats(
            for: exerciseId,
            event: .delete(
                reps: reps,
                effectiveWeight: effectiveWeight,
                setType: setType,
                hasData: hasData,
                date: date,
                workoutId: workoutId
            )
        )

        return SetSaveResult(
            setId: setId,
            effectiveWeight: effectiveWeight,
            prResult: prResult
        )
    }

    func delete(_ set: WorkoutSet) async throws {
        // 1. Capture values before deletion
        let setId = set.id
        let exerciseId = set.exerciseId
        let reps = set.reps ?? 0
        let effectiveWeight = set.effectiveWeight ?? 0
        let setType = set.setType
        let hasData = set.hasData
        let cachedPRStatus = set.cachedPRStatus
        let date = set.date
        let workoutId = set.workoutId

        // 2. Delete set (hard delete — specdoc S4.4)
        try await setRepo.delete(set)

        // 3. PR recomputation (FR-005)
        _ = try await prService.handleDeletion(
            setId: setId,
            exerciseId: exerciseId,
            reps: reps,
            cachedPRStatus: cachedPRStatus
        )

        // 4. Stats decrement
        try await statsService.updateStats(
            for: exerciseId,
            event: .delete(
                reps: reps,
                effectiveWeight: effectiveWeight,
                setType: setType,
                hasData: hasData,
                date: date,
                workoutId: workoutId
            )
        )
    }

    // MARK: - Fetch (006: Active Workout Screen)

    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet] {
        return try await setRepo.fetchSets(for: workoutId)
    }

    func fetchExerciseIds(for workoutId: UUID) async throws -> Swift.Set<UUID> {
        return try await setRepo.fetchExerciseIds(for: workoutId)
    }

    // MARK: - Fetch by Exercise (007: Exercise List + Detail)

    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet] {
        try await setRepo.fetchSets(for: exerciseId, limit: limit)
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
}
