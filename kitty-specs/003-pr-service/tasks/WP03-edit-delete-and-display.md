---
work_package_id: "WP03"
subtasks:
  - "T010"
  - "T011"
  - "T012"
title: "Edit/Delete Recomputation + Suffix-Max Display"
phase: "Phase 2 - Reactive Pipeline + Display"
lane: "planned"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
dependencies: ["WP02"]
history:
  - timestamp: "2026-02-22T20:46:52Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – Edit/Delete Recomputation + Suffix-Max Display

## Implementation Command

Depends on WP02:
```bash
spec-kitty implement WP03 --base WP02
```

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback, update `review_status: acknowledged`.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- Implement `evaluateAfterEdit()` per specdoc S7.2 "On Set Edited"
- Implement `handleDeletion()` per specdoc S7.2 "On Set Deleted"
- Implement `fetchPRTable()` with suffix-max algorithm per specdoc S7.4
- Edit of PR-owning set to lower weight correctly promotes next best candidate
- Delete of only set for a rep count deletes the PerformanceRecord
- Suffix-max filtering on specdoc S7.4 example produces correct output (hides 10-rep at 85kg when 12-rep is 90kg)
- All weight comparisons use `UnitConversion.toGrams()`

## Context & Constraints

- **Specdoc S7.2 "On Set Edited"**: Full pseudocode for edit recomputation
- **Specdoc S7.2 "On Set Deleted"**: Full pseudocode for delete recovery
- **Specdoc S7.4**: Suffix-max algorithm with worked example
- **Plan**: `kitty-specs/003-pr-service/plan.md` — method-by-method pipeline mapping
- **Existing WP02 code**: `PRService.swift` already has `evaluate()`, eligibility check, same-workout matching, and integer grams comparison
- **Repository method**: `SetRepository.fetchBestEligibleSet()` from WP01 is available for recomputation queries

## Subtasks & Detailed Guidance

### Subtask T010 – Implement evaluateAfterEdit()

- **Purpose**: Handle PR recomputation when a set is edited. The logic differs based on whether the edited set was the PR owner. This covers User Story 3 (edit/delete) and FR-006.
- **Steps**:
  1. Replace the `evaluateAfterEdit()` stub in `PRService.swift` with:

     ```swift
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

         // CASE 1: Edited set was NOT the PR owner
         // Re-run evaluate() logic with new values — treat as if it's a new set
         if previousCachedPRStatus != .current {
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

         // CASE 2: Edited set WAS the PR owner
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
             // PR record missing (shouldn't happen if set was "current") — treat as new
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
             return PREvaluationResult(
                 setId: setId,
                 newStatus: .current,
                 affectedSetIds: [:],
                 prRecordChanged: editedGrams != prGrams  // only changed if value actually differs
             )
         }

         // CASE 2c: Edited weight < PR value — need to find new best
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
             return PREvaluationResult(
                 setId: setId,
                 newStatus: .current,
                 affectedSetIds: [:],
                 prRecordChanged: true
             )
         }

         if winner.id == setId {
             // This set still wins (it's the best even at lower weight)
             existingPR.value = effectiveWeight
             existingPR.date = date
             existingPR.updatedAt = Date()
             try await performanceRecordRepo.save(existingPR)
             return PREvaluationResult(
                 setId: setId,
                 newStatus: .current,
                 affectedSetIds: [:],
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

         // Winner gets "current"
         winner.cachedPRStatus = .current
         try await setRepo.save(winner)
         affectedSets[winner.id] = .current

         // Re-evaluate the edited set against the new PR
         let editedGramsVsWinner = UnitConversion.toGrams(effectiveWeight)
         let winnerGrams = UnitConversion.toGrams(winner.effectiveWeight ?? 0)

         var editedNewStatus: CachedPRStatus? = nil
         if editedGramsVsWinner == winnerGrams {
             // Match — check same-workout
             if workoutId == winner.workoutId {
                 editedNewStatus = nil
             } else {
                 editedNewStatus = .matched
             }
         }
         // If below winner, editedNewStatus stays nil

         return PREvaluationResult(
             setId: setId,
             newStatus: editedNewStatus,
             affectedSetIds: affectedSets,
             prRecordChanged: true
         )
     }
     ```

  2. Add a private helper `findNewPROwner()` for the case where the PR owner becomes ineligible:
     ```swift
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
             return PREvaluationResult(
                 setId: UUID(), // placeholder — caller handles the original set
                 newStatus: nil,
                 affectedSetIds: [:],
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

         winner.cachedPRStatus = .current
         try await setRepo.save(winner)

         return PREvaluationResult(
             setId: winner.id,
             newStatus: .current,
             affectedSetIds: [winner.id: .current],
             prRecordChanged: true
         )
     }
     ```

- **Files**: `Reppo/Core/Services/PRService.swift`
- **Parallel?**: Yes — independent of T011 and T012
- **Notes**:
  - The most complex case is "edited set was owner and new weight is lower" — follow the specdoc pseudocode exactly
  - `fetchBestEligibleSet` with `excludingSetId: nil` because the edited set still exists and should be considered as a candidate
  - When the winner is found, re-evaluate the edited set against the new winner to determine its new status
  - **Reps change edge case**: `evaluateAfterEdit` assumes reps did NOT change. If a user edits reps (e.g., 5 → 8), the caller (future SetService) MUST handle this as two operations: (1) `handleDeletion` for the old reps (removes set from old PR race), then (2) `evaluate` for the new reps (enters set in new PR race). This is a caller responsibility, not a PRService concern — document this contract in a code comment on `evaluateAfterEdit`.

### Subtask T011 – Implement handleDeletion()

- **Purpose**: Handle PR recovery when a set that was a PR owner is deleted (specdoc S7.2 "On Set Deleted"). This covers User Story 3 and FR-007.
- **Steps**:
  1. Replace the `handleDeletion()` stub:

     ```swift
     func handleDeletion(
         setId: UUID,
         exerciseId: UUID,
         reps: Int,
         cachedPRStatus: CachedPRStatus?
     ) async throws -> PREvaluationResult {

         // Non-PR-owner deleted — no PR changes needed
         guard cachedPRStatus == .current else {
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
     ```

  2. This is clean because `findNewPROwner()` (from T010) handles all the logic:
     - Finds best eligible set excluding the deleted one
     - If found → updates PerformanceRecord, promotes winner to "current"
     - If no sets remain → deletes PerformanceRecord

- **Files**: `Reppo/Core/Services/PRService.swift`
- **Parallel?**: Yes — independent of T010 and T012
- **Notes**:
  - `handleDeletion` is called BEFORE the set is actually removed from the database — the caller (future SetService) must call this first, then delete the set
  - The `excludingSetId` parameter ensures the deleted set is not selected as its own replacement
  - Acceptance scenarios: delete PR-owning set with alternatives → next best promoted. Delete only set for rep count → PerformanceRecord deleted.

### Subtask T012 – Implement fetchPRTable() with suffix-max filtering

- **Purpose**: Implement the suffix-max display algorithm from specdoc S7.4. This filters the PR table to show only the "capability frontier" — hiding entries dominated by higher-rep PRs.
- **Steps**:
  1. Replace the `fetchPRTable()` stub:

     ```swift
     func fetchPRTable(for exerciseId: UUID) async throws -> [PRTableEntry] {
         // Fetch all repMax records for this exercise
         let records = try await performanceRecordRepo.fetchAll(
             for: exerciseId,
             recordType: .repMax
         )

         // Sort by reps DESCENDING (highest rep count first)
         let sorted = records.sorted { ($0.reps ?? 0) > ($1.reps ?? 0) }

         // Apply suffix-max filter (specdoc S7.4)
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
     ```

  2. **Verify against specdoc S7.4 example**:
     - Input: 12rep=90kg, 10rep=85kg, 8rep=95kg, 5rep=100kg, 3rep=110kg, 1rep=120kg
     - After sorting by reps DESC: 12,10,8,5,3,1
     - Iteration:
       - 12rep 90kg: 90000 > 0 → SHOW, maxSeen=90000
       - 10rep 85kg: 85000 ≤ 90000 → HIDE
       - 8rep 95kg: 95000 > 90000 → SHOW, maxSeen=95000
       - 5rep 100kg: 100000 > 95000 → SHOW, maxSeen=100000
       - 3rep 110kg: 110000 > 100000 → SHOW, maxSeen=110000
       - 1rep 120kg: 120000 > 110000 → SHOW, maxSeen=120000
     - Result: 12,8,5,3,1 shown. 10rep hidden.

  3. Use `UnitConversion.toGrams()` for weight comparison — consistent with the rest of the pipeline

- **Files**: `Reppo/Core/Services/PRService.swift`
- **Parallel?**: Yes — fully independent of T010 and T011
- **Notes**:
  - This is a pure computation — no database writes
  - The algorithm is O(n log n) for the sort + O(n) for the filter. PerformanceRecord rows per exercise are sparse (~50 max), so this is fast.
  - `reps` is `Int?` on PerformanceRecord (nil for e1RM/maxVolume) — use `?? 0` for sorting. The fetchAll filters by `.repMax` so reps should always be non-nil.
  - Return sorted by reps ASC for display — UI shows lowest reps at top (heaviest weights first in a typical PR table)

## Risks & Mitigations

- **evaluateAfterEdit reps change**: If the user edits reps (not just weight), the old-reps PR and new-reps PR are different records. The non-owner case (re-run evaluate) handles this correctly. The owner case needs care: if reps changed, the old PR record for old-reps needs a new owner. Consider this edge case in implementation.
- **handleDeletion timing**: Must be called before set deletion. Document this contract for future SetService.
- **Suffix-max with integer grams**: Using toGrams for comparison ensures consistency. An 85.0001kg PR won't hide an 85.0kg entry — both convert to the same grams value.

## Definition of Done Checklist

- [ ] `evaluateAfterEdit()` handles non-owner case (delegates to evaluate)
- [ ] `evaluateAfterEdit()` handles owner with higher/equal weight (updates PR)
- [ ] `evaluateAfterEdit()` handles owner with lower weight (finds new winner)
- [ ] `handleDeletion()` skips work for non-owners
- [ ] `handleDeletion()` promotes next best for PR-owner deletion
- [ ] `handleDeletion()` deletes PerformanceRecord when no sets remain
- [ ] `fetchPRTable()` produces correct suffix-max output for specdoc example
- [ ] All weight comparisons use `UnitConversion.toGrams()`
- [ ] Project compiles with zero errors
- [ ] `tasks.md` updated with status change

## Review Guidance

- Verify evaluateAfterEdit covers all 3 branches: non-owner, owner-higher, owner-lower
- Verify handleDeletion uses excludingSetId correctly
- Verify suffix-max algorithm against the specdoc S7.4 worked example
- Check that `findNewPROwner` is reused between edit and delete paths
- Verify integer grams comparison is used in suffix-max too

## Activity Log

- 2026-02-22T20:46:52Z – system – lane=planned – Prompt created.
