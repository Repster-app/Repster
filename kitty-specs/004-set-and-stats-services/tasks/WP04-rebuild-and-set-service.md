---
work_package_id: "WP04"
subtasks:
  - "T016"
  - "T017"
  - "T018"
  - "T019"
  - "T020"
  - "T021"
  - "T022"
title: "StatsService Rebuild + SetService"
phase: "Phase 1 - Core Implementation"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "68965"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP02", "WP03"]
history:
  - timestamp: "2026-02-23T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP04 – StatsService Rebuild + SetService

## Implementation Command

Depends on WP02 and WP03:
```bash
spec-kitty implement WP04 --base WP03
```
Note: WP02 must also be merged/available. If WP02 and WP03 were done in parallel branches, merge both before starting WP04.

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

- Implement `StatsService.rebuild(for:)` using Core Data aggregation from WP02
- Implement `StatsService.rebuildAll()` iterating all exercises
- Create `SetService` actor with 6 dependencies (repos + PRService + StatsService)
- Implement `computeEffectiveWeight()` per specdoc S5.4 formula
- Implement `save()` with full sequential pipeline: effectiveWeight → persist → PR → stats
- Implement `edit()` with old value capture, recompute, and re-trigger
- Implement `delete()` with capture, delete, PR recompute, stats decrement
- `rebuildAll()` produces identical results to incremental updates (SC-004)
- effectiveWeight correctly computed for bodyweightFactor values 0.0, 0.65, 0.80 (SC-001)
- Full save pipeline completes within 100ms (SC-005)

## Context & Constraints

- **Specdoc S5.4**: `effectiveWeight = weight + (closestBodyweight × exercise.bodyweightFactor)`
- **Specdoc S4.5**: "PR/stat computation runs as a bounded, cheap work unit after set save. Synchronous execution acceptable initially."
- **Spec FR-002**: "SetService.save(set) MUST call PRService.evaluate(set) after persisting"
- **Spec FR-003**: "SetService.save(set) MUST call StatsService.updateStats(for: exerciseId) after PR evaluation"
- **Spec FR-010**: "effectiveWeight MUST never be recalculated retroactively"
- **Spec FR-012**: "Sets MUST persist immediately on entry"
- **AGENT_RULES S6**: SetService orchestrates pipeline. Does NOT access ModelContext directly.
- **Existing code**:
  - `StatsService.swift` from WP03 — actor with updateStats implemented
  - `SetRepository` from WP02 — has aggregation methods
  - `PRServiceProtocol` — evaluate, evaluateAfterEdit, handleDeletion
  - `BodyweightEntryRepository.fetchClosest(to:healthProfileId:)` — returns closest bodyweight entry
  - `ExerciseRepository.fetch(byId:)` — returns exercise with bodyweightFactor
  - `HealthProfileRepository.fetchOrCreate()` — returns user settings
- **Architecture**: SetService is a plain `actor` with 6 dependencies. PRService dependency via protocol only.

## Subtasks & Detailed Guidance

### Subtask T016 – Implement rebuild(for:) in StatsService

- **Purpose**: Recompute ExerciseStats for a single exercise from raw data using Core Data aggregation. Used by `rebuildAll()` and potentially as a standalone repair operation.
- **Steps**:
  1. Replace the `fatalError` stub in `rebuild(for:)`:
     ```swift
     func rebuild(for exerciseId: UUID) async throws {
         let profile = try await healthProfileRepo.fetchOrCreate()
         let excludeWarmups = !profile.includeWarmupsInVolume

         // 1. Delete existing stats
         if let existingStats = try await exerciseStatsRepo.fetch(for: exerciseId) {
             try await exerciseStatsRepo.delete(existingStats)
         }

         // 2. Aggregate from raw sets using Core Data (specdoc S8.6)
         let aggregate = try await setRepo.fetchAggregateStats(
             for: exerciseId,
             excludeWarmups: excludeWarmups,
             excludePartial: true  // Partial always excluded
         )

         // 3. Get additional stats not covered by basic aggregation
         let workoutCount = try await setRepo.fetchWorkoutCount(for: exerciseId)
         let bestE1RM = try await setRepo.fetchBestE1RM(for: exerciseId)

         // 4. Create new ExerciseStats
         let newStats = ExerciseStats(
             exerciseId: exerciseId,
             totalWorkouts: workoutCount,
             totalSets: aggregate.totalSets,
             totalReps: aggregate.totalReps,
             totalVolume: aggregate.totalVolume,
             maxWeight: aggregate.maxWeight,
             bestE1RM: bestE1RM ?? 0,
             averageIntensity: 0,  // TODO: compute in future if needed
             estimated1RMTrendSlope: 0,  // TODO: compute in future if needed
             lastPerformedDate: aggregate.lastPerformedDate
         )

         // 5. Persist
         try await exerciseStatsRepo.save(newStats)
     }
     ```
  2. **Note**: `averageIntensity` and `estimated1RMTrendSlope` require more complex computation (RPE averages, linear regression). Set to 0 for v1 — these are display-nice-to-haves, not critical.
  3. **maxSessionVolume**: Not covered by the simple aggregation query. Would require GROUP BY workoutId, then MAX of those sums. Set to 0 for v1 or compute separately if needed.
- **Files**: `Reppo/Core/Services/StatsService.swift` (replace fatalError stub)
- **Parallel?**: Yes — independent of T018-T022 (different file)
- **Notes**: This is the cold path. It calls the Core Data aggregation methods from WP02. It's OK if this takes hundreds of milliseconds — it's a maintenance operation.

### Subtask T017 – Implement rebuildAll() in StatsService

- **Purpose**: Rebuild all ExerciseStats across all exercises. Called from Settings after import or settings changes. NOT called at startup (AGENT_RULES S5.1).
- **Steps**:
  1. Replace the `fatalError` stub in `rebuildAll()`:
     ```swift
     func rebuildAll() async throws {
         // 1. Get all exercises
         let exercises = try await exerciseRepo.fetchAll()

         // 2. Rebuild each exercise's stats
         for exercise in exercises {
             try await rebuild(for: exercise.id)
         }
     }
     ```
  2. That's it. Simple iteration over exercises, delegating to `rebuild(for:)`.
  3. **Performance**: For 200 exercises, this may take several seconds. Acceptable for a rare manual operation.
- **Files**: `Reppo/Core/Services/StatsService.swift` (replace fatalError stub)
- **Parallel?**: No — calls T016
- **Notes**: Future optimization: add progress reporting callback for UI progress bar. Not needed for v1.

### Subtask T018 – Create SetService actor skeleton

- **Purpose**: Establish the SetService actor with all 6 dependencies. SetService is the central orchestrator — it computes effectiveWeight, persists sets, triggers PRService, and triggers StatsService.
- **Steps**:
  1. Create file `Reppo/Core/Services/SetService.swift`
  2. Define the actor:
     ```swift
     import Foundation

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
             fatalError("TODO: Implement in T020")
         }

         func edit(_ set: WorkoutSet) async throws -> SetSaveResult {
             fatalError("TODO: Implement in T021")
         }

         func delete(_ set: WorkoutSet) async throws {
             fatalError("TODO: Implement in T022")
         }
     }
     ```
  3. **Important**: Do NOT import SwiftData. SetService is a plain actor.
  4. **6 dependencies**: 4 repositories + 2 services. PRService is `PRServiceProtocol` (coded against protocol only — doesn't require 003 to be merged).
- **Files**: `Reppo/Core/Services/SetService.swift` (new file)
- **Parallel?**: Yes — can proceed alongside T016/T017
- **Notes**: The 6-dependency count is high but each has a clear role. SetService is the hub that connects data access (repos) with business logic (PRService, StatsService).

### Subtask T019 – Implement computeEffectiveWeight() helper

- **Purpose**: Compute effectiveWeight per specdoc S5.4: `effectiveWeight = weight + (closestBodyweight × exercise.bodyweightFactor)`. This is called before every save and edit.
- **Steps**:
  1. Add private method to SetService:
     ```swift
     /// Compute effectiveWeight per specdoc S5.4.
     /// effectiveWeight = weight + (closestBodyweight × exercise.bodyweightFactor)
     /// If bodyweightFactor == 0 → effectiveWeight = weight
     /// If no bodyweight entry → effectiveWeight = weight (user warned)
     private func computeEffectiveWeight(
         weight: Double?,
         exerciseId: UUID,
         date: Date
     ) async throws -> Double? {
         guard let weight = weight else { return nil }

         // 1. Get exercise for bodyweightFactor
         guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else {
             return weight
         }

         // 2. If bodyweightFactor is 0, effectiveWeight = weight
         guard exercise.bodyweightFactor > 0 else {
             return weight
         }

         // 3. Find closest bodyweight entry
         let profile = try await healthProfileRepo.fetchOrCreate()
         let closestEntry = try await bodyweightEntryRepo.fetchClosest(
             to: date,
             healthProfileId: profile.id
         )

         guard let bodyweight = closestEntry?.bodyweightKg else {
             // No bodyweight entry — effectiveWeight = weight (warn user)
             // TODO: Add warning mechanism in future (e.g., return tuple with warning flag)
             return weight
         }

         // 4. Compute: weight + (closestBodyweight × bodyweightFactor)
         return weight + (bodyweight * exercise.bodyweightFactor)
     }
     ```
  2. **Acceptance scenarios from spec**:
     - bodyweightFactor=0.65, bodyweight=80kg, weight=20kg → 20 + (80 × 0.65) = 72kg ✓
     - bodyweightFactor=0.0, weight=100kg → 100kg ✓
     - bodyweightFactor=0.65, no bodyweight entry → weight only ✓
  3. **FR-010**: This method is called at save/edit time. Historical sets keep their original effectiveWeight — we never call this retroactively.
- **Files**: `Reppo/Core/Services/SetService.swift` (add to actor)
- **Parallel?**: Yes — independent utility method
- **Notes**: The method returns `Double?` to handle nil weight. If weight is nil, effectiveWeight is nil (set doesn't have weight data).

### Subtask T020 – Implement SetService.save() — full pipeline

- **Purpose**: The core write path. Every set flows through this: compute effectiveWeight → persist → PR evaluate → stats update. Sequential pipeline per specdoc S4.5.
- **Steps**:
  1. Replace the `fatalError` in `save()`:
     ```swift
     func save(_ set: WorkoutSet) async throws -> SetSaveResult {
         // 1. Compute effectiveWeight (specdoc S5.4)
         let effectiveWeight = try await computeEffectiveWeight(
             weight: set.weight,
             exerciseId: set.exerciseId,
             date: set.date
         )
         set.effectiveWeight = effectiveWeight

         // 2. Persist immediately (FR-012)
         try await setRepo.save(set)

         // 3. PR evaluation (FR-002) — after persisting
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

         // 4. Stats update (FR-003) — after PR evaluation
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

         // 5. Return result for UI
         return SetSaveResult(
             setId: set.id,
             effectiveWeight: effectiveWeight ?? 0,
             prResult: prResult
         )
     }
     ```
  2. **Pipeline order**: persist → effectiveWeight computed before persist → PR → stats. This is the EXACT order from the plan.
  3. **Cross-actor data**: SetService receives a `WorkoutSet` from the caller. It mutates `effectiveWeight` on it, then passes it to `setRepo.save()`. Since SetService is a plain actor (not @ModelActor), there's a subtlety: the WorkoutSet is created in a different ModelContext. **IMPORTANT**: The set must be created within the repository's ModelContext for the save to work. Options:
     a. SetService extracts primitives and creates a new WorkoutSet inside setRepo.save()
     b. SetService passes the @Model object hoping it works across contexts
     c. Add a `saveNew(...)` method to SetRepository that takes primitives

     For v1, option (b) should work if the set hasn't been inserted into any ModelContext yet (it's a new, unmanaged object). If it's already managed, option (a) is needed.
  4. **PR service parameters**: All primitives — UUIDs, Double, Int, Date, enum values. Safe to pass across actor boundaries.
- **Files**: `Reppo/Core/Services/SetService.swift` (replace save fatalError)
- **Parallel?**: No — depends on T019 (computeEffectiveWeight)
- **Edge Cases**:
  - Weight is nil (duration-only exercise): effectiveWeight = nil, volume = nil, PR evaluation skipped (hasData checks)
  - reps is nil: passed as 0 to PR/stats. PR evaluation will see reps=0.
  - excludeFromPRs is nil: passed as false (default to not excluding)

### Subtask T021 – Implement SetService.edit()

- **Purpose**: Edit an existing set. Capture old values for delta computation, recompute effectiveWeight with new values, re-trigger PR and stats pipelines.
- **Steps**:
  1. Replace the `fatalError` in `edit()`:
     ```swift
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
     ```
  2. **Define error type** (add to SetService or a separate file):
     ```swift
     enum SetServiceError: Error {
         case setNotFound(UUID)
         case exerciseNotFound(UUID)
     }
     ```
  3. **FR-010**: effectiveWeight IS recalculated here because the set is being actively edited (new values). This is NOT retroactive — it's a current edit operation.
  4. **Cross-actor concern**: `oldSet` is fetched via `setRepo.fetch(byId:)` which runs in the repository's ModelContext. The returned `WorkoutSet` may be in a different context than `set`. We only read primitive values from `oldSet` — this is safe.
- **Files**: `Reppo/Core/Services/SetService.swift` (replace edit fatalError)
- **Parallel?**: No — depends on T019
- **Notes**: The `previousCachedPRStatus` is critical for PRService to know if this set was a PR owner before the edit.

### Subtask T022 – Implement SetService.delete()

- **Purpose**: Delete a set with proper cascade to PR and stats. Capture values before deletion since the set won't exist afterward.
- **Steps**:
  1. Replace the `fatalError` in `delete()`:
     ```swift
     func delete(_ set: WorkoutSet) async throws {
         // 1. Capture values before deletion (can't read after delete)
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
         // Only does work if this set was the PR owner
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
     ```
  2. **Hard delete**: No soft delete. The set is removed from the database.
  3. **Order**: Delete first, THEN recompute PRs and stats. PRService.handleDeletion needs the set to already be gone so it doesn't find it as a candidate.
     **Wait — actually**: PRService.handleDeletion uses `excludingSetId` parameter to skip the deleted set. It doesn't matter if the set is deleted before or after the call. But deleting first is cleaner — the set is gone, and PRService's `fetchBestEligibleSet(excludingSetId:)` won't find it.
  4. **`_ = try await`**: We discard the PREvaluationResult for delete. The caller doesn't need it — the set is gone.
- **Files**: `Reppo/Core/Services/SetService.swift` (replace delete fatalError)
- **Parallel?**: No — depends on T018/T019
- **Notes**: Capture ALL needed values as local variables before calling delete. After setRepo.delete(), the WorkoutSet object may be invalid.

## Risks & Mitigations

- **Cross-actor WorkoutSet passing**: SetService receives WorkoutSet from caller. If the set is already managed by a different ModelContext, mutations (setting effectiveWeight) may not propagate to the repository's context. Mitigation: for save(), the set should be a new unmanaged object. For edit(), we fetch the set inside the repository's context and apply changes there.
- **Core Data aggregation in rebuild**: If WP02's NSExpression approach had to fall back to SwiftData, rebuild will be slower but still correct.
- **PRServiceProtocol not available**: If feature 003 hasn't been merged, the project won't compile (SetService references PRServiceProtocol). This is expected and documented.
- **100ms budget**: All operations are local. Estimated: ~5ms effectiveWeight + ~5ms persist + ~10ms PR + ~5ms stats = ~25ms. Well within 100ms.
- **SetServiceError**: Simple error enum. May need expansion in future for other error cases.

## Definition of Done Checklist

- [ ] StatsService.rebuild(for:) recomputes stats from raw data using Core Data aggregation
- [ ] StatsService.rebuildAll() iterates all exercises and rebuilds each
- [ ] SetService.swift exists as plain actor with 6 dependencies
- [ ] computeEffectiveWeight() handles all bodyweightFactor cases (0.0, 0.65, 0.80)
- [ ] SetService.save() runs full pipeline: effectiveWeight → persist → PR → stats
- [ ] SetService.edit() captures old values, recomputes, re-triggers pipeline
- [ ] SetService.delete() captures values, deletes, recomputes PRs and stats
- [ ] SetServiceError enum defined
- [ ] No SwiftData import in SetService.swift
- [ ] Project compiles with zero errors (assuming PRServiceProtocol exists)

## Review Guidance

- Verify effectiveWeight formula matches specdoc S5.4 exactly
- Verify pipeline order: persist → PR → stats (sequential, not parallel)
- Verify old values captured BEFORE mutations in edit()
- Verify values captured BEFORE deletion in delete()
- Verify rebuild(for:) calls the Core Data aggregation methods, not Swift iteration
- Verify no SwiftData import in service files
- Verify SetService does NOT modify cachedPRStatus directly (that's PRService's job via PREvaluationResult)

## Activity Log

- 2026-02-23T12:00:00Z – system – lane=planned – Prompt created.
- 2026-02-24T10:37:17Z – claude – lane=for_review – Moved to for_review
- 2026-02-24T10:37:21Z – claude – shell_pid=68965 – lane=doing – Started review via workflow command
- 2026-02-24T10:37:56Z – claude – shell_pid=68965 – lane=done – Review passed: SetService actor with 6 DI deps, correct sequential save/edit/delete pipelines, computeEffectiveWeight follows S5.4 formula. StatsService rebuild uses WP02 aggregation correctly. Old-value capture in edit() before mutations. Values captured before hard delete.
