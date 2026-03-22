// PRService.swift
// Core PR evaluation pipeline with suffix-max frontier filtering.
// Spec: FR-001 through FR-012
// Source: specdoc S7.2, S7.3, S7.4, S8.3, AGENT_RULES S4, S6

import Foundation

/// PRService owns all Personal Record evaluation logic.
/// Plain actor (not @ModelActor) — accesses SwiftData only through repository protocols.
actor PRService: PRServiceProtocol {

    // MARK: - Dependencies

    private let performanceRecordRepo: PerformanceRecordRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol

    init(
        performanceRecordRepository: PerformanceRecordRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol
    ) {
        self.performanceRecordRepo = performanceRecordRepository
        self.setRepo = setRepository
        self.healthProfileRepo = healthProfileRepository
        self.exerciseRepo = exerciseRepository
    }

    // MARK: - Core Pipeline (specdoc S7.2)

    /// Evaluate a newly saved set for PR status.
    /// Implements specdoc S7.2 "On New Set Saved" step by step.
    func evaluate(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        effectiveWeight: Double,
        workoutId: UUID,
        setType: SetType,
        hasData: Bool,
        excludeFromPRs: Bool,
        date: Date
    ) async throws -> PREvaluationResult {
        guard try await supportsRepPRs(for: exerciseId) else {
            return emptyResult(for: setId)
        }

        // STEP 1: ELIGIBILITY CHECK (specdoc S7.2 step 1, FR-003)
        guard try await isEligible(
            hasData: hasData,
            excludeFromPRs: excludeFromPRs,
            setType: setType
        ) else {
            return PREvaluationResult(
                setId: setId,
                newStatus: nil,
                affectedSetIds: [:],
                prRecordChanged: false
            )
        }

        // STEP 2: LOOKUP CURRENT PR (O(1) via exerciseId + recordType + reps index)
        let existingPR = try await performanceRecordRepo.fetch(
            exerciseId: exerciseId,
            recordType: .repMax,
            reps: reps
        )

        // STEP 3: NO EXISTING PR — first set for this exercise/reps
        guard let existingPR else {
            let newRecord = PerformanceRecord(
                exerciseId: exerciseId,
                recordType: .repMax,
                reps: reps,
                value: effectiveWeight,
                setId: setId,
                date: date
            )
            try await performanceRecordRepo.save(newRecord)

            // Recompute frontier — new PR may be dominated by existing higher-rep PRs
            let (frontierReps, frontierAffected) = try await recomputeFrontierBadges(
                for: exerciseId,
                skipUpdateForSetId: setId
            )
            let isOnFrontier = frontierReps.contains(reps)

            return PREvaluationResult(
                setId: setId,
                newStatus: isOnFrontier ? .current : .dominated,
                affectedSetIds: frontierAffected,
                prRecordChanged: true
            )
        }

        // STEP 4–6: Compare using integer grams (FR-002, specdoc S8.3)
        // NEVER compare raw floats — always use UnitConversion.toGrams()
        let newGrams = UnitConversion.toGrams(effectiveWeight)
        let existingGrams = UnitConversion.toGrams(existingPR.value)

        // STEP 4: NEW SET BEATS PR
        if newGrams > existingGrams {
            // Demote old PR-owning set to "previous"
            var affectedSets: [UUID: CachedPRStatus?] = [:]
            if let oldSet = try await setRepo.fetch(byId: existingPR.setId) {
                oldSet.cachedPRStatus = .previous
                try await setRepo.save(oldSet)
                affectedSets[existingPR.setId] = .previous
            }

            // Update PerformanceRecord to point to new set (mutate in-place, not delete+insert)
            existingPR.value = effectiveWeight
            existingPR.setId = setId
            existingPR.date = date
            existingPR.updatedAt = Date()
            try await performanceRecordRepo.save(existingPR)

            // Recompute frontier — beating a PR may change the frontier
            let (frontierReps, frontierAffected) = try await recomputeFrontierBadges(
                for: exerciseId,
                skipUpdateForSetId: setId
            )
            let isOnFrontier = frontierReps.contains(reps)

            // Merge frontier-affected sets with the demotion
            for (id, status) in frontierAffected {
                affectedSets[id] = status
            }

            return PREvaluationResult(
                setId: setId,
                newStatus: isOnFrontier ? .current : .dominated,
                affectedSetIds: affectedSets,
                prRecordChanged: true
            )
        }

        // STEP 5: EXACT MATCH
        // specdoc S7.3: ALWAYS store "matched" in DB.
        // UI hides the badge if set is in same workout as PR owner.
        // PRService does not check workoutId for matches.
        if newGrams == existingGrams {
            return PREvaluationResult(
                setId: setId,
                newStatus: .matched,
                affectedSetIds: [:],
                prRecordChanged: false
            )
        }

        // STEP 6: BELOW PR
        return PREvaluationResult(
            setId: setId,
            newStatus: nil,
            affectedSetIds: [:],
            prRecordChanged: false
        )
    }

    // MARK: - Edit Recomputation (specdoc S7.2 "On Set Edited", FR-006)

    /// Re-evaluate PR after a set is edited.
    /// NOTE: This method assumes reps did NOT change. If a user edits reps
    /// (e.g. 5 → 8), the caller (SetService) MUST handle as two operations:
    /// (1) handleDeletion for old reps, then (2) evaluate for new reps.
    func evaluateAfterEdit(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        effectiveWeight: Double,
        workoutId: UUID,
        setType: SetType,
        hasData: Bool,
        excludeFromPRs: Bool,
        previousCachedPRStatus: CachedPRStatus?,
        date: Date
    ) async throws -> PREvaluationResult {
        guard try await supportsRepPRs(for: exerciseId) else {
            return emptyResult(for: setId)
        }

        // CASE 1: Edited set was NOT the PR owner
        // Re-run evaluate() logic with new values — treat as if it's a new set.
        // Uses isPROwner to correctly identify both .current and .dominated owners.
        if previousCachedPRStatus?.isPROwner != true {
            return try await evaluate(
                setId: setId,
                exerciseId: exerciseId,
                reps: reps,
                effectiveWeight: effectiveWeight,
                workoutId: workoutId,
                setType: setType,
                hasData: hasData,
                excludeFromPRs: excludeFromPRs,
                date: date
            )
        }

        // CASE 2: Edited set WAS the PR owner (.current or .dominated)
        // Check if it's still eligible
        guard try await isEligible(hasData: hasData, excludeFromPRs: excludeFromPRs, setType: setType) else {
            // Was PR owner but now ineligible — find new winner
            return try await findNewPROwner(
                exerciseId: exerciseId,
                reps: reps,
                excludingSetId: nil  // don't exclude — set still exists, just ineligible
            )
        }

        // Fetch current PerformanceRecord
        guard let existingPR = try await performanceRecordRepo.fetch(
            exerciseId: exerciseId,
            recordType: .repMax,
            reps: reps
        ) else {
            // PR record missing (shouldn't happen if set was PR owner) — treat as new
            return try await evaluate(
                setId: setId, exerciseId: exerciseId, reps: reps,
                effectiveWeight: effectiveWeight, workoutId: workoutId,
                setType: setType, hasData: hasData, excludeFromPRs: excludeFromPRs, date: date
            )
        }

        let editedGrams = UnitConversion.toGrams(effectiveWeight)
        let prGrams = UnitConversion.toGrams(existingPR.value)

        // CASE 2a: Edited weight still >= PR value — just update the record
        if editedGrams >= prGrams {
            existingPR.value = effectiveWeight
            existingPR.date = date
            existingPR.updatedAt = Date()
            try await performanceRecordRepo.save(existingPR)

            // Recompute frontier — weight change may shift the capability frontier
            let (frontierReps, frontierAffected) = try await recomputeFrontierBadges(
                for: exerciseId,
                skipUpdateForSetId: setId
            )
            let isOnFrontier = frontierReps.contains(reps)

            return PREvaluationResult(
                setId: setId,
                newStatus: isOnFrontier ? .current : .dominated,
                affectedSetIds: frontierAffected,
                prRecordChanged: editedGrams != prGrams  // only changed if value actually differs
            )
        }

        // CASE 2b: Edited weight < PR value — need to find new best
        // Read warmup setting for eligible-set query
        let profile = try await healthProfileRepo.fetchOrCreate()
        let excludeWarmups = !profile.includeWarmupsInPRs

        let bestCandidate = try await setRepo.fetchBestEligibleSet(
            for: exerciseId,
            reps: reps,
            excludeWarmups: excludeWarmups,
            excludingSetId: nil  // don't exclude — all sets are candidates
        )

        guard let winner = bestCandidate else {
            // No eligible sets at all (shouldn't happen since edited set is eligible)
            // Update PR with lower value, keep as owner
            existingPR.value = effectiveWeight
            existingPR.date = date
            existingPR.updatedAt = Date()
            try await performanceRecordRepo.save(existingPR)

            // Recompute frontier
            let (frontierReps, frontierAffected) = try await recomputeFrontierBadges(
                for: exerciseId,
                skipUpdateForSetId: setId
            )
            let isOnFrontier = frontierReps.contains(reps)

            return PREvaluationResult(
                setId: setId,
                newStatus: isOnFrontier ? .current : .dominated,
                affectedSetIds: frontierAffected,
                prRecordChanged: true
            )
        }

        if winner.id == setId {
            // This set still wins (it's the best even at lower weight)
            existingPR.value = effectiveWeight
            existingPR.date = date
            existingPR.updatedAt = Date()
            try await performanceRecordRepo.save(existingPR)

            // Recompute frontier
            let (frontierReps, frontierAffected) = try await recomputeFrontierBadges(
                for: exerciseId,
                skipUpdateForSetId: setId
            )
            let isOnFrontier = frontierReps.contains(reps)

            return PREvaluationResult(
                setId: setId,
                newStatus: isOnFrontier ? .current : .dominated,
                affectedSetIds: frontierAffected,
                prRecordChanged: true
            )
        }

        // Different set wins — promote the winner
        var affectedSets: [UUID: CachedPRStatus?] = [:]

        // Update PR to point to winner
        existingPR.value = winner.effectiveWeight ?? 0
        existingPR.setId = winner.id
        existingPR.date = winner.date
        existingPR.updatedAt = Date()
        try await performanceRecordRepo.save(existingPR)

        // Recompute frontier before assigning statuses
        let (frontierReps, frontierAffected) = try await recomputeFrontierBadges(
            for: exerciseId,
            skipUpdateForSetId: setId  // skip edited set — status returned via newStatus
        )
        let winnerOnFrontier = frontierReps.contains(reps)

        // Winner gets frontier-aware status
        let winnerStatus: CachedPRStatus = winnerOnFrontier ? .current : .dominated
        winner.cachedPRStatus = winnerStatus
        try await setRepo.save(winner)
        affectedSets[winner.id] = winnerStatus

        // Merge frontier-affected sets
        for (id, status) in frontierAffected {
            affectedSets[id] = status
        }

        // Re-evaluate the edited set against the new PR
        let editedGramsVsWinner = UnitConversion.toGrams(effectiveWeight)
        let winnerGrams = UnitConversion.toGrams(winner.effectiveWeight ?? 0)

        var editedNewStatus: CachedPRStatus? = nil
        if editedGramsVsWinner == winnerGrams {
            editedNewStatus = .matched
        }
        // If below winner, editedNewStatus stays nil

        return PREvaluationResult(
            setId: setId,
            newStatus: editedNewStatus,
            affectedSetIds: affectedSets,
            prRecordChanged: true
        )
    }

    // MARK: - Delete Recomputation (specdoc S7.2 "On Set Deleted", FR-007)

    /// Handle PR recomputation after a set is deleted.
    /// Must be called BEFORE the set is removed from the database — the caller (SetService)
    /// must call this first, then delete the set.
    func handleDeletion(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        cachedPRStatus: CachedPRStatus?
    ) async throws -> PREvaluationResult {
        guard try await supportsRepPRs(for: exerciseId) else {
            return emptyResult(for: setId)
        }

        // Non-PR-owner deleted — no PR changes needed.
        // Uses isPROwner to correctly identify both .current and .dominated owners.
        guard cachedPRStatus?.isPROwner == true else {
            return PREvaluationResult(
                setId: setId,
                newStatus: nil,
                affectedSetIds: [:],
                prRecordChanged: false
            )
        }

        // PR owner deleted — find new winner (exclude the deleted set)
        return try await findNewPROwner(
            exerciseId: exerciseId,
            reps: reps,
            excludingSetId: setId
        )
    }

    // MARK: - Display (specdoc S7.4, FR-008)

    /// Fetch the suffix-max filtered PR table for an exercise.
    /// Returns only entries on the capability frontier — entries dominated
    /// by higher-rep PRs are hidden.
    func fetchPRTable(for exerciseId: UUID) async throws -> [PRTableEntry] {
        guard try await supportsRepPRs(for: exerciseId) else {
            return []
        }

        // Fetch all repMax records for this exercise
        let records = try await performanceRecordRepo.fetchAll(
            for: exerciseId,
            recordType: .repMax
        )

        // Sort by reps DESCENDING (highest rep count first)
        let sorted = records.sorted { ($0.reps ?? 0) > ($1.reps ?? 0) }

        // Apply suffix-max filter (specdoc S7.4)
        // Walk from highest reps to lowest, tracking max weight seen.
        // Only include entries that exceed the running max — these form the capability frontier.
        var maxWeightSeenGrams = 0
        var result: [PRTableEntry] = []

        for record in sorted {
            let valueGrams = UnitConversion.toGrams(record.value)
            if valueGrams > maxWeightSeenGrams {
                // This entry is on the capability frontier — include it
                result.append(PRTableEntry(
                    reps: record.reps ?? 0,
                    value: record.value,
                    setId: record.setId,
                    date: record.date
                ))
                maxWeightSeenGrams = valueGrams
            }
            // Else: dominated by a higher-rep entry — skip
        }

        // Return sorted by reps ASCENDING for display
        return result.sorted { $0.reps < $1.reps }
    }

    // MARK: - Bulk Rebuild (FR-011)

    /// Rebuild all PRs across all exercises.
    /// Triggered from Settings when includeWarmupsInPRs changes, or after CSV import.
    /// Iterates all exercises sequentially — acceptable for v1 dataset sizes.
    func rebuildAll() async throws {
        let allExercises = try await exerciseRepo.fetchAll()
        for exercise in allExercises {
            try await rebuild(for: exercise.id)
        }
    }

    /// Rebuild PRs for a single exercise from scratch.
    /// Clean slate approach: delete all PRs, clear cached statuses, then rebuild.
    func rebuild(for exerciseId: UUID) async throws {
        // Step 1: Delete all existing PerformanceRecords for this exercise
        let existingRecords = try await performanceRecordRepo.fetchAll(for: exerciseId)
        for record in existingRecords {
            try await performanceRecordRepo.delete(record)
        }

        // Step 2: Clear cachedPRStatus on ALL sets for this exercise
        let allSets = try await setRepo.fetchSets(for: exerciseId, limit: nil)
        for set in allSets {
            if set.cachedPRStatus != nil {
                set.cachedPRStatus = nil
                try await setRepo.save(set)
            }
        }

        guard try await supportsRepPRs(for: exerciseId) else {
            return
        }

        let profile = try await healthProfileRepo.fetchOrCreate()
        let excludeWarmups = !profile.includeWarmupsInPRs

        // Step 3: Collect unique rep counts from eligible sets
        // Group eligible sets by reps, find best for each rep count
        var repCountsProcessed = Set<Int>()

        for set in allSets {
            guard let reps = set.reps else { continue }
            guard !repCountsProcessed.contains(reps) else { continue }
            repCountsProcessed.insert(reps)

            // Find the best eligible set for this rep count
            let best = try await setRepo.fetchBestEligibleSet(
                for: exerciseId,
                reps: reps,
                excludeWarmups: excludeWarmups,
                excludingSetId: nil
            )

            guard let winner = best, let ew = winner.effectiveWeight else { continue }

            // Create PerformanceRecord for the winner (status set in Step 5)
            let record = PerformanceRecord(
                exerciseId: exerciseId,
                recordType: .repMax,
                reps: reps,
                value: ew,
                setId: winner.id,
                date: winner.date
            )
            try await performanceRecordRepo.save(record)

            // Step 4: Find matching sets (same weight, different workout)
            // and set their status to "matched"
            let eligibleSetsForReps = try await setRepo.fetchSets(
                for: exerciseId,
                reps: reps,
                orderedBy: .effectiveWeightDesc
            )

            let winnerGrams = UnitConversion.toGrams(ew)
            for otherSet in eligibleSetsForReps {
                guard otherSet.id != winner.id else { continue }
                guard let otherEW = otherSet.effectiveWeight else { continue }

                let otherGrams = UnitConversion.toGrams(otherEW)
                if otherGrams == winnerGrams && otherSet.workoutId != winner.workoutId {
                    // Check eligibility before granting "matched"
                    guard otherSet.hasData else { continue }
                    guard otherSet.excludeFromPRs != true else { continue }
                    guard otherSet.setType != .partial else { continue }
                    if excludeWarmups && otherSet.setType == .warmup { continue }

                    otherSet.cachedPRStatus = .matched
                    try await setRepo.save(otherSet)
                }
            }
        }

        // Step 5: Apply suffix-max frontier filtering to all PR owners.
        // Sets on the frontier get .current, others get .dominated.
        // No set to skip — rebuild updates all PR owners directly.
        let (_, _) = try await recomputeFrontierBadges(
            for: exerciseId,
            skipUpdateForSetId: nil
        )
    }

    // MARK: - Private Helpers

    /// Recompute suffix-max frontier badges for all PR owners of an exercise.
    ///
    /// The suffix-max algorithm (specdoc S7.4) walks from highest reps to lowest,
    /// tracking the max weight seen. Only PRs that exceed the running max are on
    /// the "capability frontier" — everything else is dominated.
    ///
    /// PR owners on the frontier get `.current`, off-frontier get `.dominated`.
    ///
    /// - Parameters:
    ///   - exerciseId: The exercise whose PRs to recompute.
    ///   - skipUpdateForSetId: A set ID to skip DB updates for (its status comes
    ///     via PREvaluationResult.newStatus instead). Pass nil to update all sets.
    /// - Returns: The set of rep counts on the frontier, and a dictionary of
    ///   setId → new status for any sets whose badge changed.
    private func recomputeFrontierBadges(
        for exerciseId: UUID,
        skipUpdateForSetId: UUID?
    ) async throws -> (frontierReps: Set<Int>, affectedSets: [UUID: CachedPRStatus?]) {
        // 1. Fetch all repMax records for this exercise
        let records = try await performanceRecordRepo.fetchAll(
            for: exerciseId,
            recordType: .repMax
        )

        guard !records.isEmpty else {
            return (frontierReps: [], affectedSets: [:])
        }

        // 2. Sort by reps DESCENDING (highest rep count first)
        let sorted = records.sorted { ($0.reps ?? 0) > ($1.reps ?? 0) }

        // 3. Suffix-max walk — same algorithm as fetchPRTable (specdoc S7.4)
        var maxWeightSeenGrams = 0
        var frontierReps = Set<Int>()

        for record in sorted {
            let valueGrams = UnitConversion.toGrams(record.value)
            if valueGrams > maxWeightSeenGrams {
                frontierReps.insert(record.reps ?? 0)
                maxWeightSeenGrams = valueGrams
            }
        }

        // 4. Update owning sets: .current if on frontier, .dominated if not
        var affectedSets: [UUID: CachedPRStatus?] = [:]

        for record in records {
            let reps = record.reps ?? 0
            let isOnFrontier = frontierReps.contains(reps)
            let desiredStatus: CachedPRStatus = isOnFrontier ? .current : .dominated

            // Skip the set being evaluated — its status comes via PREvaluationResult.newStatus
            guard record.setId != skipUpdateForSetId else { continue }

            if let owningSet = try await setRepo.fetch(byId: record.setId) {
                if owningSet.cachedPRStatus != desiredStatus {
                    owningSet.cachedPRStatus = desiredStatus
                    try await setRepo.save(owningSet)
                    affectedSets[record.setId] = desiredStatus
                }
            }
        }

        return (frontierReps: frontierReps, affectedSets: affectedSets)
    }

    /// Find a new PR owner when the current owner is removed or made ineligible.
    /// Used by evaluateAfterEdit and handleDeletion.
    private func findNewPROwner(
        exerciseId: UUID,
        reps: Int,
        excludingSetId: UUID?
    ) async throws -> PREvaluationResult {
        let profile = try await healthProfileRepo.fetchOrCreate()
        let excludeWarmups = !profile.includeWarmupsInPRs

        let bestCandidate = try await setRepo.fetchBestEligibleSet(
            for: exerciseId,
            reps: reps,
            excludeWarmups: excludeWarmups,
            excludingSetId: excludingSetId
        )

        guard let winner = bestCandidate else {
            // No eligible sets remain — delete the PerformanceRecord
            if let pr = try await performanceRecordRepo.fetch(
                exerciseId: exerciseId,
                recordType: .repMax,
                reps: reps
            ) {
                try await performanceRecordRepo.delete(pr)
            }

            // Recompute frontier — deleting a PR may un-dominate other rep counts
            let (_, frontierAffected) = try await recomputeFrontierBadges(
                for: exerciseId,
                skipUpdateForSetId: nil
            )

            return PREvaluationResult(
                setId: UUID(), // placeholder — caller handles the original set
                newStatus: nil,
                affectedSetIds: frontierAffected,
                prRecordChanged: true
            )
        }

        // Update PR to point to winner
        if let pr = try await performanceRecordRepo.fetch(
            exerciseId: exerciseId,
            recordType: .repMax,
            reps: reps
        ) {
            pr.value = winner.effectiveWeight ?? 0
            pr.setId = winner.id
            pr.date = winner.date
            pr.updatedAt = Date()
            try await performanceRecordRepo.save(pr)
        }

        // Recompute frontier before assigning winner status
        let (frontierReps, frontierAffected) = try await recomputeFrontierBadges(
            for: exerciseId,
            skipUpdateForSetId: winner.id
        )
        let winnerOnFrontier = frontierReps.contains(reps)
        let winnerStatus: CachedPRStatus = winnerOnFrontier ? .current : .dominated

        winner.cachedPRStatus = winnerStatus
        try await setRepo.save(winner)

        // Merge winner status into affected sets
        var allAffected = frontierAffected
        allAffected[winner.id] = winnerStatus

        return PREvaluationResult(
            setId: winner.id,
            newStatus: winnerStatus,
            affectedSetIds: allAffected,
            prRecordChanged: true
        )
    }

    /// Check if a set is eligible for PR evaluation.
    /// Per specdoc S7.2 step 1 and FR-003.
    private func isEligible(
        hasData: Bool,
        excludeFromPRs: Bool,
        setType: SetType
    ) async throws -> Bool {
        // Rule 1: Must have actual data
        guard hasData else { return false }

        // Rule 2: Must not be explicitly excluded
        guard !excludeFromPRs else { return false }

        // Rule 3: Partial sets ALWAYS excluded (regardless of settings)
        guard setType != .partial else { return false }

        // Rule 4: Warmup sets excluded when setting is off
        if setType == .warmup {
            let profile = try await healthProfileRepo.fetchOrCreate()
            if !profile.includeWarmupsInPRs {
                return false
            }
        }

        return true
    }

    private func supportsRepPRs(for exerciseId: UUID) async throws -> Bool {
        guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else {
            return false
        }
        return exercise.trackingType.supportsRepPRs
    }

    private func emptyResult(for setId: UUID) -> PREvaluationResult {
        PREvaluationResult(
            setId: setId,
            newStatus: nil,
            affectedSetIds: [:],
            prRecordChanged: false
        )
    }
}
