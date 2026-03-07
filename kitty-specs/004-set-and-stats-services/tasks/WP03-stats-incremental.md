---
work_package_id: "WP03"
subtasks:
  - "T011"
  - "T012"
  - "T013"
  - "T014"
  - "T015"
title: "StatsService — Incremental Updates"
phase: "Phase 1 - Core Implementation"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "68793"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-23T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – StatsService — Incremental Updates

## Implementation Command

Depends on WP01:
```bash
spec-kitty implement WP03 --base WP01
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

- Create `StatsService` actor with repository dependencies via initializer injection
- Implement `updateStats(for:event:)` handling all three cases: `.save`, `.edit`, `.delete`
- Incremental updates use pure arithmetic on ExerciseStats — no database aggregation queries on hot path
- Partial sets always excluded from stats. Warmup sets excluded when `includeWarmupsInVolume == false`
- ExerciseStats created automatically when first set for an exercise is saved
- All acceptance scenarios from User Story 4 pass

## Context & Constraints

- **Specdoc S8.4**: "Stats aggregates — Write-time — Avoid scanning history"
- **AGENT_RULES S5.5**: Set save pipeline (including stats) must complete within 100ms
- **Spec FR-007**: "StatsService.updateStats(for:) MUST update ExerciseStats incrementally when possible"
- **Spec FR-009**: "Volume calculation MUST use effectiveWeight × reps, excluding partial sets and warmups (per settings)"
- **Plan**: `kitty-specs/004-set-and-stats-services/plan.md` — StatsService is a plain actor with 4 dependencies
- **Existing code**:
  - `Reppo/Core/Repositories/Protocols/ExerciseStatsRepositoryProtocol.swift` — save, fetch, fetchAll, delete
  - `Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift` — fetchMaxEffectiveWeight for re-query
  - `Reppo/Core/Repositories/Protocols/HealthProfileRepositoryProtocol.swift` — fetchOrCreate for warmup setting
  - `Reppo/Data/Models/ExerciseStats.swift` — all aggregate fields
- **Architecture**: StatsService is a plain `actor` (NOT `@ModelActor`). Only accesses SwiftData through repositories.

## Subtasks & Detailed Guidance

### Subtask T011 – Create StatsService actor skeleton

- **Purpose**: Establish the StatsService actor with all 4 repository dependencies injected via init. Stub all protocol methods.
- **Steps**:
  1. Create file `Reppo/Core/Services/StatsService.swift`
  2. Define the actor:
     ```swift
     import Foundation

     actor StatsService: StatsServiceProtocol {
         private let exerciseStatsRepo: ExerciseStatsRepositoryProtocol
         private let setRepo: SetRepositoryProtocol
         private let exerciseRepo: ExerciseRepositoryProtocol
         private let healthProfileRepo: HealthProfileRepositoryProtocol

         init(
             exerciseStatsRepository: ExerciseStatsRepositoryProtocol,
             setRepository: SetRepositoryProtocol,
             exerciseRepository: ExerciseRepositoryProtocol,
             healthProfileRepository: HealthProfileRepositoryProtocol
         ) {
             self.exerciseStatsRepo = exerciseStatsRepository
             self.setRepo = setRepository
             self.exerciseRepo = exerciseRepository
             self.healthProfileRepo = healthProfileRepository
         }

         // MARK: - StatsServiceProtocol

         func updateStats(for exerciseId: UUID, event: StatsUpdateEvent) async throws {
             fatalError("TODO: Implement in T013-T015")
         }

         func rebuildAll() async throws {
             fatalError("TODO: Implement in WP04")
         }

         func rebuild(for exerciseId: UUID) async throws {
             fatalError("TODO: Implement in WP04")
         }
     }
     ```
  3. **Important**: Do NOT import SwiftData. StatsService is a plain actor.
  4. The `fatalError` stubs will be replaced in subsequent subtasks
- **Files**: `Reppo/Core/Services/StatsService.swift` (new file)
- **Parallel?**: No — must come first (other subtasks add to this actor)
- **Notes**: 4 dependencies: exerciseStatsRepo, setRepo (for maxWeight re-query on delete), exerciseRepo (for rebuildAll in WP04), healthProfileRepo (for warmup setting).

### Subtask T012 – Implement stats eligibility helper

- **Purpose**: Determine whether a set should be counted in stats (volume, totals). Centralizes the partial/warmup exclusion logic.
- **Steps**:
  1. Add private method to StatsService:
     ```swift
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
     ```
  2. This is a pure function — no async, no throws, no repository calls
- **Files**: `Reppo/Core/Services/StatsService.swift` (add to existing actor)
- **Parallel?**: Yes — independent utility method
- **Notes**: Mirrors the eligibility logic in PRService but for stats (uses `includeWarmupsInVolume` instead of `includeWarmupsInPRs`).

### Subtask T013 – Implement updateStats — .save case

- **Purpose**: When a new set is saved, increment ExerciseStats totals. Create ExerciseStats if none exists. This is the hot path — must be pure arithmetic with no aggregation queries.
- **Steps**:
  1. Replace the `fatalError` in `updateStats` with a switch on event
  2. Implement the `.save` case:
     ```swift
     func updateStats(for exerciseId: UUID, event: StatsUpdateEvent) async throws {
         let profile = try await healthProfileRepo.fetchOrCreate()
         let includeWarmups = profile.includeWarmupsInVolume

         switch event {
         case .save(let reps, let effectiveWeight, let setType, let hasData, let date, let workoutId):
             try await handleSave(
                 exerciseId: exerciseId, reps: reps, effectiveWeight: effectiveWeight,
                 setType: setType, hasData: hasData, date: date, workoutId: workoutId,
                 includeWarmups: includeWarmups
             )
         case .edit(...):
             // T014
             break
         case .delete(...):
             // T015
             break
         }
     }

     private func handleSave(
         exerciseId: UUID, reps: Int, effectiveWeight: Double,
         setType: SetType, hasData: Bool, date: Date, workoutId: UUID,
         includeWarmups: Bool
     ) async throws {
         // 1. Get or create ExerciseStats
         var stats = try await exerciseStatsRepo.fetch(for: exerciseId)
         let isNew = (stats == nil)

         if isNew {
             stats = ExerciseStats(exerciseId: exerciseId)
         }
         guard var stats = stats else { return }

         // 2. Check eligibility
         guard shouldCountForStats(setType: setType, hasData: hasData, includeWarmupsInVolume: includeWarmups) else {
             // Save the new (empty) stats if just created
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

         // 6. Update totalWorkouts — check if first set for this exercise in this workout
         let workoutSets = try await setRepo.fetchSets(for: workoutId)
         let exerciseSetsInWorkout = workoutSets.filter { $0.exerciseId == exerciseId }
         if exerciseSetsInWorkout.count <= 1 {
             // This is the first (or only) set for this exercise in this workout
             stats.totalWorkouts += 1
         }

         // 7. Update timestamp
         stats.updatedAt = Date()

         // 8. Persist
         try await exerciseStatsRepo.save(stats)
     }
     ```
  3. **totalWorkouts logic**: We check if there are other sets for this exercise in this workout. If count <= 1 (just the newly saved set), it's a new workout for this exercise.
  4. **ExerciseStats creation**: Use the default init which sets all numeric fields to 0.
- **Files**: `Reppo/Core/Services/StatsService.swift` (modify updateStats method)
- **Parallel?**: Yes — independent of T014/T015
- **Edge Cases**:
  - First ever set for an exercise: creates new ExerciseStats with this set's values
  - Set with hasData=false: saved but not counted (stats unchanged)
  - Warmup set when excluded: not counted
  - effectiveWeight is 0 (e.g., bodyweight exercise with no bodyweight logged): counted but doesn't affect maxWeight

### Subtask T014 – Implement updateStats — .edit case

- **Purpose**: When a set is edited, compute the delta between old and new values and adjust ExerciseStats accordingly. Handle eligibility changes (e.g., set changed from working to partial).
- **Steps**:
  1. Add the `.edit` case handler:
     ```swift
     case .edit(let oldReps, let oldEW, let oldSetType, let oldHasData,
                let newReps, let newEW, let newSetType, let newHasData,
                let date, let workoutId):
         try await handleEdit(
             exerciseId: exerciseId,
             oldReps: oldReps, oldEffectiveWeight: oldEW, oldSetType: oldSetType, oldHasData: oldHasData,
             newReps: newReps, newEffectiveWeight: newEW, newSetType: newSetType, newHasData: newHasData,
             date: date, workoutId: workoutId, includeWarmups: includeWarmups
         )
     ```
  2. Implement `handleEdit()`:
     ```swift
     private func handleEdit(
         exerciseId: UUID,
         oldReps: Int, oldEffectiveWeight: Double, oldSetType: SetType, oldHasData: Bool,
         newReps: Int, newEffectiveWeight: Double, newSetType: SetType, newHasData: Bool,
         date: Date, workoutId: UUID, includeWarmups: Bool
     ) async throws {
         guard var stats = try await exerciseStatsRepo.fetch(for: exerciseId) else { return }

         let oldCounted = shouldCountForStats(setType: oldSetType, hasData: oldHasData, includeWarmupsInVolume: includeWarmups)
         let newCounted = shouldCountForStats(setType: newSetType, hasData: newHasData, includeWarmupsInVolume: includeWarmups)

         // Case 1: Was counted, still counted — adjust by delta
         if oldCounted && newCounted {
             stats.totalReps += (newReps - oldReps)
             let oldVolume = oldEffectiveWeight * Double(oldReps)
             let newVolume = newEffectiveWeight * Double(newReps)
             stats.totalVolume += (newVolume - oldVolume)

             // maxWeight might have changed
             if newEffectiveWeight > stats.maxWeight {
                 stats.maxWeight = newEffectiveWeight
             } else if oldEffectiveWeight >= stats.maxWeight && newEffectiveWeight < oldEffectiveWeight {
                 // Old value was the max and new is lower — re-query
                 // fetchMaxEffectiveWeight needs reps=0 to mean "all reps" but current API requires reps
                 // Workaround: use a broad fetch
                 stats.maxWeight = try await recomputeMaxWeight(for: exerciseId)
             }
         }
         // Case 2: Was counted, no longer counted — decrement
         else if oldCounted && !newCounted {
             stats.totalSets -= 1
             stats.totalReps -= oldReps
             stats.totalVolume -= oldEffectiveWeight * Double(oldReps)
             if oldEffectiveWeight >= stats.maxWeight {
                 stats.maxWeight = try await recomputeMaxWeight(for: exerciseId)
             }
         }
         // Case 3: Was not counted, now counted — increment
         else if !oldCounted && newCounted {
             stats.totalSets += 1
             stats.totalReps += newReps
             stats.totalVolume += newEffectiveWeight * Double(newReps)
             if newEffectiveWeight > stats.maxWeight {
                 stats.maxWeight = newEffectiveWeight
             }
         }
         // Case 4: Neither counted — no change

         stats.updatedAt = Date()
         try await exerciseStatsRepo.save(stats)
     }
     ```
  3. Add helper for maxWeight re-query:
     ```swift
     /// Re-query maxWeight across all reps for an exercise.
     /// Used when the previous max might have been reduced by an edit or delete.
     private func recomputeMaxWeight(for exerciseId: UUID) async throws -> Double {
         // Fetch sets sorted by effectiveWeight DESC, take first
         let sets = try await setRepo.fetchSets(for: exerciseId, limit: 1)
         // Note: fetchSets sorts by date DESC, not effectiveWeight
         // We need effectiveWeight DESC — may need a different approach
         // Use fetchSets with no limit and take max, or add a new repo method
         let allSets = try await setRepo.fetchSets(for: exerciseId, limit: nil)
         return allSets.compactMap { $0.effectiveWeight }.max() ?? 0
     }
     ```
     **Note**: This `recomputeMaxWeight` is a rare-path operation (only when the max set is edited down or deleted). Loading all sets for one exercise is acceptable here. The existing `fetchMaxEffectiveWeight(for:reps:)` requires a specific rep count — for overall max we need all reps. Consider adding a repo method `fetchMaxEffectiveWeight(for exerciseId: UUID) -> Double?` (no reps filter) in future.
- **Files**: `Reppo/Core/Services/StatsService.swift` (add to updateStats)
- **Parallel?**: Yes — independent of T013/T015
- **Edge Cases**:
  - Set type changes from working to partial: decrement stats (was counted, no longer)
  - reps changes but weight doesn't: delta adjusts reps and volume
  - effectiveWeight changes because bodyweightFactor changed on exercise: this shouldn't happen (effectiveWeight is computed at save time and historical values are kept)

### Subtask T015 – Implement updateStats — .delete case

- **Purpose**: When a set is deleted, decrement ExerciseStats totals. Re-query maxWeight if the deleted set held the max. Handle totalWorkouts decrement if this was the last set for the exercise in the workout.
- **Steps**:
  1. Add the `.delete` case handler:
     ```swift
     case .delete(let reps, let effectiveWeight, let setType, let hasData, let date, let workoutId):
         try await handleDelete(
             exerciseId: exerciseId, reps: reps, effectiveWeight: effectiveWeight,
             setType: setType, hasData: hasData, date: date, workoutId: workoutId,
             includeWarmups: includeWarmups
         )
     ```
  2. Implement `handleDelete()`:
     ```swift
     private func handleDelete(
         exerciseId: UUID, reps: Int, effectiveWeight: Double,
         setType: SetType, hasData: Bool, date: Date, workoutId: UUID,
         includeWarmups: Bool
     ) async throws {
         guard var stats = try await exerciseStatsRepo.fetch(for: exerciseId) else { return }

         let wasCounted = shouldCountForStats(setType: setType, hasData: hasData, includeWarmupsInVolume: includeWarmups)

         if wasCounted {
             stats.totalSets = max(0, stats.totalSets - 1)
             stats.totalReps = max(0, stats.totalReps - reps)
             stats.totalVolume = max(0, stats.totalVolume - effectiveWeight * Double(reps))

             // Re-query maxWeight if deleted set might have been the max
             if effectiveWeight >= stats.maxWeight {
                 stats.maxWeight = try await recomputeMaxWeight(for: exerciseId)
             }
         }

         // Check if this was the last set for the exercise in this workout
         let workoutSets = try await setRepo.fetchSets(for: workoutId)
         let remainingExerciseSets = workoutSets.filter { $0.exerciseId == exerciseId }
         if remainingExerciseSets.isEmpty {
             stats.totalWorkouts = max(0, stats.totalWorkouts - 1)
         }

         stats.updatedAt = Date()
         try await exerciseStatsRepo.save(stats)
     }
     ```
  3. **max(0, ...)**: Defensive clamping to prevent negative values from rounding errors or edge cases
  4. **totalWorkouts**: After deletion, check if any sets remain for this exercise in the workout. If none, decrement totalWorkouts.
- **Files**: `Reppo/Core/Services/StatsService.swift` (add to updateStats)
- **Parallel?**: Yes — independent of T013/T014
- **Edge Cases**:
  - Last set for an exercise deleted: stats go to zero but ExerciseStats record remains (for UI to show "0 sets")
  - Delete a set that wasn't counted (partial/warmup): no stats change
  - Delete when ExerciseStats doesn't exist: guard returns early (shouldn't happen in practice)

## Risks & Mitigations

- **recomputeMaxWeight loading all sets**: Only triggered on rare cases (editing max set downward, deleting max set). Per-exercise set count is typically <500, acceptable for rare operation. Future optimization: add `fetchMaxEffectiveWeight(for exerciseId: UUID) async throws -> Double?` to SetRepositoryProtocol (no reps filter).
- **totalWorkouts race**: If two sets are saved concurrently for the same exercise in the same workout, both might see count=0 and both increment totalWorkouts. The actor provides serialization, preventing this.
- **ExerciseStats save semantics**: SwiftData tracks property mutations. When we mutate `stats.totalSets` etc. and call `save()`, SwiftData should update the existing record, not insert a duplicate. Verify this behavior — if duplicates occur, use fetch+mutate pattern instead of insert.
- **HealthProfile read on every call**: O(1) single-row read. Acceptable. If profiling shows concern, cache in actor state with manual invalidation.

## Definition of Done Checklist

- [ ] `Reppo/Core/Services/StatsService.swift` exists as plain `actor` with 4 dependencies
- [ ] `updateStats(for:event:)` handles `.save` case: creates or increments ExerciseStats
- [ ] `updateStats(for:event:)` handles `.edit` case: computes delta, adjusts stats
- [ ] `updateStats(for:event:)` handles `.delete` case: decrements stats, re-queries max if needed
- [ ] `shouldCountForStats()` correctly excludes partials (always) and warmups (per setting)
- [ ] totalWorkouts incremented/decremented based on per-workout set count
- [ ] No SwiftData import in StatsService.swift
- [ ] Project compiles with zero errors

## Review Guidance

- Verify incremental updates use pure arithmetic — no database aggregation on hot path
- Verify eligibility: partial always excluded, warmup excluded per `includeWarmupsInVolume`
- Verify volume = effectiveWeight × reps (not raw weight × reps)
- Verify maxWeight re-query only fires when the edited/deleted set was the max
- Verify totalWorkouts logic: increment when first set for exercise in workout, decrement when last set removed
- Verify defensive clamping: `max(0, ...)` prevents negatives
- Verify ExerciseStats is created on first save for an exercise

## Activity Log

- 2026-02-23T12:00:00Z – system – lane=planned – Prompt created.
- 2026-02-24T10:36:43Z – claude – lane=for_review – Moved to for_review
- 2026-02-24T10:36:47Z – claude – shell_pid=68793 – lane=doing – Started review via workflow command
- 2026-02-24T10:37:10Z – claude – shell_pid=68793 – lane=done – Review passed: StatsService actor with correct DI, 4-case edit delta logic, eligibility helper, totalWorkouts tracking, maxWeight re-query on potential max change, safe max(0,...) guards. rebuild stubs deferred to WP04 correctly.
