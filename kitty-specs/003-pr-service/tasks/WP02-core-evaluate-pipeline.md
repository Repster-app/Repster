---
work_package_id: "WP02"
subtasks:
  - "T005"
  - "T006"
  - "T007"
  - "T008"
  - "T009"
title: "Core PR Pipeline — evaluate()"
phase: "Phase 1 - Core Pipeline"
lane: "planned"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-22T20:46:52Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP02 – Core PR Pipeline — evaluate()

## Implementation Command

Depends on WP01:
```bash
spec-kitty implement WP02 --base WP01
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

- Create `PRService` actor with repository dependencies via initializer injection
- Implement the full `evaluate()` pipeline from specdoc S7.2 "On New Set Saved"
- All 5 acceptance scenarios from User Story 1 must be handled correctly:
  1. First PR creation (no existing PR) → PerformanceRecord created, status="current"
  2. Beats existing PR → PerformanceRecord updated, old set="previous", new set="current"
  3. Exact match (any workout) → status="matched" stored in DB, PerformanceRecord unchanged (specdoc S7.3)
  5. Below PR → status=nil
- Eligibility filtering excludes: hasData=false, excludeFromPRs=true, warmup (when setting off), partial (always)
- ALL weight comparisons use `UnitConversion.toGrams()` — NEVER raw float comparison
- Integer grams comparison verified (FR-002, SC-002)

## Context & Constraints

- **Constitution**: `.kittify/memory/constitution.md` — write-time PR updates, integer grams comparison, services call repositories only
- **Specdoc S7.2**: Complete PR pipeline pseudocode — follow step by step
- **Specdoc S7.3**: Same-workout matching rule — store "matched" in DB, UI handles display hiding
- **Specdoc S8.3**: Float comparison policy — integer grams via `toGrams()`, NEVER epsilon
- **Plan**: `kitty-specs/003-pr-service/plan.md` — PRService is a plain actor, not @ModelActor
- **Research**: `kitty-specs/003-pr-service/research.md` — cross-actor data flow uses UUIDs/primitives
- **Existing code**:
  - `Reppo/Core/Extensions/UnitConversion.swift` — `toGrams(_ kg: Double) -> Int` already implemented
  - `Reppo/Data/Models/PerformanceRecord.swift` — the PR table model
  - `Reppo/Data/Models/WorkoutSet.swift` — has `cachedPRStatus`, `hasData`, `workoutId`
  - `Reppo/Data/Enums/CachedPRStatus.swift` — `.current`, `.matched`, `.previous`
  - `Reppo/Data/Enums/RecordType.swift` — `.repMax`, `.e1RM`, `.maxVolume`
  - `Reppo/Data/Enums/SetType.swift` — `.warmup`, `.partial`, `.working`, etc.

## Subtasks & Detailed Guidance

### Subtask T005 – Create PRService actor skeleton

- **Purpose**: Establish the PRService actor with all repository dependencies injected via initializer. This is the foundation for all subsequent subtasks.
- **Steps**:
  1. Create `Reppo/Core/Services/PRService.swift`
  2. Define the actor:
     ```swift
     import Foundation

     actor PRService: PRServiceProtocol {
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

         // Protocol methods — stub with fatalError for now, implement in T006-T009
     }
     ```
  3. Add stub implementations for all protocol methods (they'll be filled in subsequent subtasks)
  4. Verify it compiles — the stubs should satisfy protocol conformance
- **Files**: `Reppo/Core/Services/PRService.swift` (new file)
- **Parallel?**: No — must come first, other subtasks build on this
- **Notes**: Do NOT import SwiftData. PRService uses repository protocols only. The `exerciseRepo` dependency is needed for `rebuildAll()` (WP04) — include it now to avoid init signature changes later.

### Subtask T006 – Implement eligibility check

- **Purpose**: The eligibility check is the first step of every PR evaluation (specdoc S7.2 step 1). It determines whether a set should even be considered for PR status.
- **Steps**:
  1. Add a private method to PRService:
     ```swift
     /// Check if a set is eligible for PR evaluation.
     /// Returns true if the set should be evaluated, false if it should be skipped.
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
     ```
  2. The warmup check reads `HealthProfile.includeWarmupsInPRs` — this is the only DB read in the eligibility check
  3. Partial sets are ALWAYS excluded regardless of any setting (per spec FR-003)
- **Files**: `Reppo/Core/Services/PRService.swift`
- **Parallel?**: Yes — independent utility method
- **Notes**: The HealthProfile read happens on every warmup set evaluation. For non-warmup sets, no DB read is needed. This is acceptable — HealthProfile is a single-row table.

### Subtask T007 – Implement evaluate() full pipeline

- **Purpose**: This is the core method — called at write-time after every set save. Implements specdoc S7.2 "On New Set Saved" step by step.
- **Steps**:
  1. Replace the evaluate() stub with the full implementation
  2. Follow this exact flow (matches specdoc S7.2):

     ```swift
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

         // STEP 1: ELIGIBILITY CHECK
         guard try await isEligible(hasData: hasData, excludeFromPRs: excludeFromPRs, setType: setType) else {
             return PREvaluationResult(
                 setId: setId,
                 newStatus: nil,
                 affectedSetIds: [:],
                 prRecordChanged: false
             )
         }

         // STEP 2: LOOKUP CURRENT PR
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
             return PREvaluationResult(
                 setId: setId,
                 newStatus: .current,
                 affectedSetIds: [:],
                 prRecordChanged: true
             )
         }

         let newGrams = UnitConversion.toGrams(effectiveWeight)
         let existingGrams = UnitConversion.toGrams(existingPR.value)

         // STEP 4: NEW SET BEATS PR
         if newGrams > existingGrams {
             // Fetch old PR-owning set to demote it
             var affectedSets: [UUID: CachedPRStatus?] = [:]
             if let oldSet = try await setRepo.fetch(byId: existingPR.setId) {
                 oldSet.cachedPRStatus = .previous
                 try await setRepo.save(oldSet)
                 affectedSets[existingPR.setId] = .previous
             }

             // Update PerformanceRecord to point to new set
             existingPR.value = effectiveWeight
             existingPR.setId = setId
             existingPR.date = date
             existingPR.updatedAt = Date()
             try await performanceRecordRepo.save(existingPR)

             return PREvaluationResult(
                 setId: setId,
                 newStatus: .current,
                 affectedSetIds: affectedSets,
                 prRecordChanged: true
             )
         }

         // STEP 5: EXACT MATCH
         // Per specdoc S7.3: ALWAYS store "matched" in DB.
         // UI layer decides whether to show the badge (hides for same-workout).
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
     ```

  3. **CRITICAL**: All comparisons use `UnitConversion.toGrams()` — lines with `newGrams > existingGrams` and `newGrams == existingGrams`. NEVER compare `effectiveWeight` directly.

  4. **CRITICAL**: When updating PerformanceRecord (step 4), mutate the existing object's properties and save — do NOT delete and re-create. Per specdoc S7.2: "UPDATE PerformanceRecord SET value = ?, setId = ?, date = ?"

  5. **CRITICAL**: When demoting old PR-owning set (step 4), set `cachedPRStatus = .previous` and save via setRepo. The old set may not exist (was deleted in a previous operation) — handle the nil case gracefully.

- **Files**: `Reppo/Core/Services/PRService.swift`
- **Parallel?**: No — this is the main method, depends on T005, T006, T008, T009
- **Notes**:
  - The `handleMatch` helper is implemented in T008
  - PerformanceRecord objects fetched from the repo are in the repo's ModelContext — mutations and saves go through the repo correctly
  - The method accepts primitives (UUIDs, Doubles) not @Model objects — per research.md cross-actor data flow pattern

### Subtask T008 – Verify same-workout matching follows specdoc S7.3

- **Purpose**: Verify that exact-match handling correctly stores `cachedPRStatus = "matched"` in the database for ALL matches, regardless of workout context. Per specdoc S7.3 (highest authority), the database always stores "matched" — the UI layer hides the badge for same-workout sets.
- **Steps**:
  1. Confirm the `evaluate()` step 5 (exact match) in T007 returns `.matched` unconditionally — no workoutId check in PRService
  2. No `handleMatch` helper is needed — the logic is a simple return statement
  3. Add a code comment in the exact-match branch:
     ```swift
     // specdoc S7.3: ALWAYS store "matched" in DB.
     // UI hides the badge if set is in same workout as PR owner.
     // PRService does not check workoutId for matches.
     ```
  4. Verify PerformanceRecord is NOT updated for matches (earliest occurrence wins, specdoc S4.2)
- **Files**: `Reppo/Core/Services/PRService.swift`
- **Parallel?**: Yes — verification/audit task
- **Notes**: This simplifies the evaluate() method — no need to fetch the PR-owning set for the match case. The `workoutId` parameter is still needed in the method signature for future use (evaluateAfterEdit may need it), but evaluate() itself does not use it for the match branch.

### Subtask T009 – Verify integer grams comparison usage

- **Purpose**: Ensure all weight comparisons in PRService use `UnitConversion.toGrams()` and never compare raw floats. This is a verification/cleanup subtask.
- **Steps**:
  1. After T007 is complete, audit all weight comparisons in `PRService.swift`
  2. Every comparison must use `toGrams()`:
     - `UnitConversion.toGrams(effectiveWeight) > UnitConversion.toGrams(existingPR.value)` for beats-PR
     - `UnitConversion.toGrams(effectiveWeight) == UnitConversion.toGrams(existingPR.value)` for exact match
  3. Search for any raw float comparisons (`effectiveWeight >`, `effectiveWeight ==`, `.value >`, `.value ==`) and fix them
  4. Verify the `UnitConversion.toGrams()` implementation in `Reppo/Core/Extensions/UnitConversion.swift`:
     ```swift
     static func toGrams(_ kg: Double) -> Int {
         Int(round(kg * 1000))
     }
     ```
     This must match specdoc S8.3 exactly.
- **Files**: `Reppo/Core/Services/PRService.swift`, `Reppo/Core/Extensions/UnitConversion.swift` (verify only)
- **Parallel?**: Yes — verification task, can run alongside other subtasks
- **Notes**: This is a safety check. The evaluate() implementation in T007 should already use toGrams() everywhere. This subtask catches any missed cases.

## Risks & Mitigations

- **Cross-actor model passing**: PRService receives UUIDs/primitives and fetches models via repos. SwiftData @Model objects are NOT Sendable. The `evaluate()` method signature accepts only primitive types — this is by design.
- **PerformanceRecord mutation across actors**: When PRService fetches a PerformanceRecord via `performanceRecordRepo.fetch()`, the object lives in the repo's ModelContext. Mutating it and calling `save()` on the same repo is safe — both happen within the repo actor's context.
- **Old PR-owning set may be nil**: The set referenced by `existingPR.setId` could have been deleted (e.g., by a concurrent operation). Handle the nil case — skip the demotion if the set no longer exists.
- **HealthProfile fetch per evaluation**: Adds one DB read for warmup sets. Acceptable for single-row table. If profiling shows issues, add caching in the actor later.

## Definition of Done Checklist

- [ ] `Reppo/Core/Services/PRService.swift` exists as a plain actor (no `@ModelActor`)
- [ ] PRService accepts 4 repository protocols via init
- [ ] `evaluate()` implements all 6 steps from specdoc S7.2
- [ ] Eligibility check handles hasData, excludeFromPRs, partial (always), warmup (configurable)
- [ ] All weight comparisons use `UnitConversion.toGrams()` — zero raw float comparisons
- [ ] Exact matches always store "matched" in DB (specdoc S7.3 — UI hides badge for same-workout)
- [ ] PerformanceRecord is mutated in-place, not delete+insert
- [ ] Old PR-owning set gets `cachedPRStatus = .previous` when demoted
- [ ] Project compiles with zero errors
- [ ] `tasks.md` updated with status change

## Review Guidance

- **Most critical**: Verify all weight comparisons use `toGrams()` — search for `effectiveWeight` comparisons, they should all go through `UnitConversion.toGrams()`
- Verify the 5 acceptance scenarios from User Story 1 are all covered by the evaluate() flow
- Verify eligibility check order matches specdoc S7.2 step 1
- Verify PerformanceRecord is mutated, not recreated
- Verify exact matches always store "matched" (no workoutId check in evaluate — specdoc S7.3)
- Verify PRService has no SwiftData import

## Activity Log

- 2026-02-22T20:46:52Z – system – lane=planned – Prompt created.
