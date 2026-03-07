---
work_package_id: "WP03"
subtasks:
  - "T010"
  - "T011"
  - "T012"
  - "T013"
  - "T014"
title: "EditWorkoutViewModel — Core Set Operations"
phase: "Phase 1 - User Story 1 (P1)"
lane: "done"
dependencies: ["WP01"]
assignee: ""
agent: "claude-opus-reviewer"
shell_pid: "49867"
review_status: "approved"
reviewed_by: "Magnus Espensen"
history:
  - timestamp: "2026-03-02T14:27:05Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – EditWorkoutViewModel — Core Set Operations

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP03 --base WP01
```

Depends on WP01 (SetTableDataSource protocol + updateWorkoutMetadata service method).

---

## Objectives & Success Criteria

1. Create `EditWorkoutViewModel` with full workout loading and core set CRUD.
2. Loading a completed workout populates exercises and sets correctly.
3. Editing an existing set calls `setService.edit()` and updates PR status.
4. Adding a new set calls `setService.save()` with immediate persistence.
5. Deleting a set calls `setService.delete()` with PR/stats cascade.

**Success**: ViewModel can load a completed workout, and all set operations work with correct service calls. Does NOT need to conform to `SetTableDataSource` yet (that happens in WP04 with computed properties).

## Context & Constraints

- **Architecture**: `@Observable @MainActor` ViewModel, calls Services via protocols (never Repositories).
- **Reference**: `ActiveWorkoutViewModel` at `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` — follow the same patterns.
- **Services used**: `SetServiceProtocol`, `WorkoutServiceProtocol`, `ExerciseServiceProtocol`, `StatsServiceProtocol`.
- **Key design decision** (from research.md R2): Use `newSetIds: Set<UUID>` to distinguish new vs existing sets in `completeSet()`.
- **Constitution**: Sets persist immediately (FR-012). Write-time PR computation. effectiveWeight computed at save time.

## Subtasks & Detailed Guidance

### Subtask T010 – Create EditWorkoutViewModel skeleton

- **Purpose**: Establish the class structure, state properties, and dependency injection.
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift` (NEW)
- **Steps**:
  1. Create the file with this skeleton:
     ```swift
     // EditWorkoutViewModel.swift
     // ViewModel for editing completed workouts.
     // Mirrors ActiveWorkoutViewModel pattern but without timer, finish flow, or sub-tabs.
     // Spec: 015-edit-historic-workout, FR-001 through FR-012

     import SwiftUI

     @Observable
     @MainActor
     final class EditWorkoutViewModel {

         // MARK: - Dependencies

         private let workoutId: UUID
         private let workoutService: any WorkoutServiceProtocol
         private let setService: any SetServiceProtocol
         private let exerciseService: any ExerciseServiceProtocol
         private let statsService: any StatsServiceProtocol

         // MARK: - State

         var workout: Workout?
         var exercises: [Exercise] = []
         var selectedExerciseIndex: Int = 0
         var setsByExercise: [UUID: [WorkoutSet]] = [:]
         var notesText: String = ""
         var isLoading: Bool = true
         var showAddExerciseSheet: Bool = false

         // MARK: - Internal Tracking

         /// IDs of sets added during this edit session.
         /// Used by completeSet() to choose save() vs edit().
         private var newSetIds: Set<UUID> = []

         // MARK: - Init

         init(
             workoutId: UUID,
             workoutService: any WorkoutServiceProtocol,
             setService: any SetServiceProtocol,
             exerciseService: any ExerciseServiceProtocol,
             statsService: any StatsServiceProtocol
         ) {
             self.workoutId = workoutId
             self.workoutService = workoutService
             self.setService = setService
             self.exerciseService = exerciseService
             self.statsService = statsService
         }
     }
     ```
  2. Verify it compiles.
- **Notes**: The `statsService` is included for potential future use (PR badge context). It's injected but may not be called directly in v1 — `setService.edit()` handles stats internally.

### Subtask T011 – Implement loadWorkout

- **Purpose**: Fetch the completed workout, its sets, and the associated exercises. Populate all state.
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`
- **Steps**:
  1. Add a `loadWorkout()` method. Follow the same pattern as `WorkoutDetailFromHomeView.loadDetail()`:
     ```swift
     // MARK: - Load

     func loadWorkout() async {
         isLoading = true
         do {
             // 1. Fetch workout
             guard let workout = try await workoutService.fetchWorkout(workoutId) else {
                 isLoading = false
                 return
             }
             self.workout = workout
             self.notesText = workout.notes ?? ""

             // 2. Fetch all sets for this workout
             let sets = try await setService.fetchSets(for: workout.id)

             // 3. Group sets by exerciseId
             var exerciseSetMap: [UUID: [WorkoutSet]] = [:]
             for set in sets {
                 exerciseSetMap[set.exerciseId, default: []].append(set)
             }

             // 4. Fetch each unique exercise
             var loadedExercises: [(exercise: Exercise, firstOrder: Int)] = []
             for (exerciseId, exerciseSets) in exerciseSetMap {
                 guard let exercise = try await exerciseService.fetchExercise(exerciseId) else {
                     continue
                 }
                 let sorted = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }
                 exerciseSetMap[exerciseId] = sorted
                 let firstOrder = sorted.first?.orderInWorkout ?? Int.max
                 loadedExercises.append((exercise, firstOrder))
             }

             // 5. Sort exercises by their first set's orderInWorkout
             loadedExercises.sort { $0.firstOrder < $1.firstOrder }

             // 6. Populate state
             self.exercises = loadedExercises.map(\.exercise)
             self.setsByExercise = exerciseSetMap
             self.selectedExerciseIndex = 0
             self.isLoading = false
         } catch {
             print("[EditWorkoutViewModel] Load failed: \(error)")
             isLoading = false
         }
     }
     ```
- **Notes**: This is very similar to `WorkoutDetailFromHomeView.loadDetail()` but stores into ViewModel properties instead of `WorkoutDetail` structs.

### Subtask T012 – Implement completeSet

- **Purpose**: Handle the checkbox tap on a set row. Must distinguish existing sets (call `edit()`) from newly added sets (call `save()`).
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`
- **Steps**:
  1. Add the method:
     ```swift
     // MARK: - Set Actions

     func completeSet(
         _ set: WorkoutSet,
         weight: Double?,
         reps: Int?,
         durationSeconds: Int?,
         distanceMeters: Double?
     ) async {
         // Update set values
         set.weight = weight
         set.reps = reps
         set.durationSeconds = durationSeconds
         set.distanceMeters = distanceMeters
         set.completed = true
         set.completedAt = Date()
         set.updatedAt = Date()

         do {
             let result: SetSaveResult

             if newSetIds.contains(set.id) {
                 // New set added during this edit session → save()
                 result = try await setService.save(set)
             } else {
                 // Existing set being edited → edit()
                 result = try await setService.edit(set)
             }

             // Apply pipeline results to local state
             set.effectiveWeight = result.effectiveWeight
             set.cachedPRStatus = result.prResult.newStatus

             // Apply affected sets (PR status changes on other sets)
             applyAffectedSets(result.prResult.affectedSetIds)

         } catch {
             print("[EditWorkoutViewModel] completeSet failed: \(error)")
         }
     }
     ```
  2. Add the helper for cascading PR changes:
     ```swift
     /// Apply PR status changes to other sets affected by a save/edit/delete.
     private func applyAffectedSets(_ affectedSetIds: [UUID: CachedPRStatus]) {
         for (setId, newStatus) in affectedSetIds {
             for exerciseId in setsByExercise.keys {
                 if let index = setsByExercise[exerciseId]?.firstIndex(where: { $0.id == setId }) {
                     setsByExercise[exerciseId]?[index].cachedPRStatus = newStatus
                 }
             }
         }
     }
     ```
- **Notes**:
  - Check `PREvaluationResult` structure by reading `Reppo/Core/Services/PRService.swift` or its protocol. Verify `prResult.newStatus` and `prResult.affectedSetIds` property names.
  - The `applyAffectedSets` pattern is from `ActiveWorkoutViewModel` — follow the same approach.

### Subtask T013 – Implement addSet and addWarmupSet

- **Purpose**: Allow users to add new sets to existing exercises during editing.
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`
- **Steps**:
  1. Add working set method:
     ```swift
     func addSet(for exerciseId: UUID) async {
         guard workout != nil else { return }

         let totalSets = setsByExercise.values.flatMap { $0 }.count
         let exerciseSets = setsByExercise[exerciseId] ?? []

         let newSet = WorkoutSet(
             workoutId: workoutId,
             exerciseId: exerciseId,
             date: workout?.date ?? Date(),
             setType: .working,
             orderInWorkout: totalSets + 1,
             orderInExercise: exerciseSets.count + 1,
             completed: false
         )

         do {
             _ = try await setService.save(newSet)
             newSetIds.insert(newSet.id)
             setsByExercise[exerciseId, default: []].append(newSet)
         } catch {
             print("[EditWorkoutViewModel] addSet failed: \(error)")
         }
     }
     ```
  2. Add warmup set method:
     ```swift
     func addWarmupSet(for exerciseId: UUID) async {
         guard workout != nil else { return }

         let totalSets = setsByExercise.values.flatMap { $0 }.count

         let newSet = WorkoutSet(
             workoutId: workoutId,
             exerciseId: exerciseId,
             date: workout?.date ?? Date(),
             setType: .warmup,
             orderInWorkout: totalSets + 1,
             orderInExercise: 1,
             completed: false
         )

         do {
             _ = try await setService.save(newSet)
             newSetIds.insert(newSet.id)

             // Insert at beginning and reindex
             var sets = setsByExercise[exerciseId] ?? []
             // Find first non-warmup set index
             let insertIndex = sets.firstIndex(where: { $0.setType != .warmup }) ?? sets.count
             sets.insert(newSet, at: insertIndex)
             reindexOrderInExercise(&sets)
             setsByExercise[exerciseId] = sets
         } catch {
             print("[EditWorkoutViewModel] addWarmupSet failed: \(error)")
         }
     }

     private func reindexOrderInExercise(_ sets: inout [WorkoutSet]) {
         for (index, set) in sets.enumerated() {
             set.orderInExercise = index + 1
         }
     }
     ```
- **Notes**:
  - Use `workout?.date ?? Date()` for the new set's date — sets in a historic workout should match the workout date.
  - The set is persisted immediately via `setService.save()` but with `completed: false` — the user fills in values and taps the checkbox to complete it.
  - `WorkoutSet` init: Check the actual initializer by reading the model file. It may have different parameter names.

### Subtask T014 – Implement deleteSet

- **Purpose**: Remove a set from the workout with immediate persistence and PR/stats cascade.
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`
- **Steps**:
  1. Add the method:
     ```swift
     func deleteSet(_ set: WorkoutSet) async {
         let exerciseId = set.exerciseId

         do {
             try await setService.delete(set)

             // Remove from local state
             setsByExercise[exerciseId]?.removeAll { $0.id == set.id }

             // Reindex remaining sets
             if var sets = setsByExercise[exerciseId] {
                 reindexOrderInExercise(&sets)
                 setsByExercise[exerciseId] = sets
             }

             // Remove from newSetIds if it was added during this session
             newSetIds.remove(set.id)

         } catch {
             print("[EditWorkoutViewModel] deleteSet failed: \(error)")
         }
     }
     ```
- **Notes**: `setService.delete()` handles the full cascade: PR recomputation + stats decrement. The ViewModel just needs to clean up local state.

## Risks & Mitigations

- **`SetSaveResult` / `PREvaluationResult` property names**: Verify exact property names by reading the protocol files. If `prResult.newStatus` doesn't exist, find the correct property.
- **WorkoutSet initializer**: The `WorkoutSet` init may differ from the code shown. Read `Reppo/Data/Models/WorkoutSet.swift` to get the exact init signature.
- **SwiftData thread safety**: Services are `actor` types returning values to `@MainActor`. The `async/await` pattern handles this correctly.

## Definition of Done Checklist

- [ ] `EditWorkoutViewModel.swift` exists in `Reppo/Features/Workout/ViewModels/`
- [ ] `loadWorkout()` fetches and populates workout, exercises, sets, and notes
- [ ] `completeSet()` calls `edit()` for existing sets and `save()` for new sets
- [ ] `addSet()` creates and persists a new working set, tracked in `newSetIds`
- [ ] `addWarmupSet()` inserts before first working set, reindexes
- [ ] `deleteSet()` removes set, reindexes, handles `newSetIds` cleanup
- [ ] `applyAffectedSets()` propagates PR status changes
- [ ] Project compiles

## Review Guidance

- Verify `newSetIds` tracking is correct — `completeSet` must check this to choose `save()` vs `edit()`.
- Verify `applyAffectedSets` iterates all exercises, not just the current one — a PR change could affect sets in the same exercise.
- Verify new sets use the workout's date, not `Date()` (current date), for the set's `date` property.

## Activity Log

- 2026-03-02T14:27:05Z – system – lane=planned – Prompt created.
- 2026-03-02T19:19:12Z – claude-opus – shell_pid=48149 – lane=doing – Started implementation via workflow command
- 2026-03-02T19:22:43Z – claude-opus – shell_pid=48149 – lane=for_review – Ready for review: EditWorkoutViewModel created with loadWorkout, completeSet (save/edit via newSetIds), addSet, addWarmupSet, deleteSet, changeSetType, reorderExercises, removeExercise, saveNotes, applyAffectedSets. All service calls match exact protocol signatures. Build succeeds.
- 2026-03-02T19:26:42Z – claude-opus-reviewer – shell_pid=49867 – lane=doing – Started review via workflow command
- 2026-03-02T19:30:33Z – claude-opus-reviewer – shell_pid=49867 – lane=done – Review passed: EditWorkoutViewModel correctly implements all core set operations. T010 skeleton verified (@Observable @MainActor, proper DI). T011 loadWorkout fetches/groups/sorts correctly. T012 completeSet uses newSetIds to route save() vs edit() with proper PR cascade. T013 addSet/addWarmupSet use workout date, track newSetIds, warmup reindexes correctly. T014 deleteSet cleans all state including newSetIds. applyAffectedSets iterates ALL exercises. All types match exact protocol signatures (SetSaveResult, PREvaluationResult). Build succeeds independently. Note: WP04 depends on this — rebase needed: cd .worktrees/015-edit-historic-workout-WP04 && git rebase 015-edit-historic-workout-WP03
