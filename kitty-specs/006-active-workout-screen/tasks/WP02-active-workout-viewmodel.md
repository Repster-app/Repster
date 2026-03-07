---
work_package_id: "WP02"
subtasks:
  - "T006"
  - "T007"
  - "T008"
  - "T009"
  - "T010"
  - "T011"
title: "ActiveWorkoutViewModel — Core + Set Operations"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "17329"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-24T14:26:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP02 – ActiveWorkoutViewModel — Core + Set Operations

## Implementation Command

Depends on WP01:
```bash
spec-kitty implement WP02 --base WP01
```

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- `ActiveWorkoutViewModel` created as `@Observable @MainActor final class` with correct dependency injection
- Lifecycle: `loadActiveWorkout()` fetches or detects active workout, loads exercises and sets
- Set operations: `completeSet()` calls SetService.save() and updates local state with PR results
- Set CRUD: `addSet()`, `addWarmupSet()`, `deleteSet()`, `changeSetType()` all functional
- Exercise operations: `addExercises()`, `removeExercise()`, `reorderExercises()` all functional
- All service calls use `async/await` via `Task {}` — no main thread blocking
- Project compiles with zero errors

## Context & Constraints

**Feature**: 006-active-workout-screen
**Architecture**: MVVM — ViewModel calls Services (actors). Never access repositories or ModelContext.
**Constitution**: `.kittify/memory/constitution.md` — `@Observable` (not ObservableObject), `async/await`, no layer skipping.
**Plan**: `kitty-specs/006-active-workout-screen/plan.md` — ViewModel contract in Phase 1.
**Contract**: `kitty-specs/006-active-workout-screen/contracts/ActiveWorkoutViewModelContract.swift`
**Data Model**: `kitty-specs/006-active-workout-screen/data-model.md` — entity usage map and data flows.

**Existing service protocols** (read these to understand exact method signatures):
- `Reppo/Core/Services/Protocols/WorkoutServiceProtocol.swift`
- `Reppo/Core/Services/Protocols/SetServiceProtocol.swift`
- `Reppo/Core/Services/Protocols/ExerciseServiceProtocol.swift`

**Key constraint**: The ViewModel must construct `WorkoutSet` objects correctly for SetService. Read the `WorkoutSet` model (`Reppo/Data/Models/WorkoutSet.swift`) to understand all required fields and their types.

## Subtasks & Detailed Guidance

### Subtask T006 – Create ActiveWorkoutViewModel Skeleton

- **Purpose**: Establish the ViewModel class with all properties, dependencies, and initializer. This is the foundation all methods build on.
- **File**: `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` (new file)
- **Parallel?**: No — all other subtasks build on this.

**Steps**:
1. Create the file at `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift`
2. Define the class:
   ```swift
   @Observable
   @MainActor
   final class ActiveWorkoutViewModel {
       // Dependencies
       private let workoutService: any WorkoutServiceProtocol
       private let setService: any SetServiceProtocol
       private let exerciseService: any ExerciseServiceProtocol

       // Workout state
       var workout: Workout?
       var exercises: [Exercise] = []
       var selectedExerciseIndex: Int = 0
       var setsByExercise: [UUID: [WorkoutSet]] = [:]

       // UI state
       var isLoading: Bool = false
       var showFinishSheet: Bool = false
       var showAddExerciseSheet: Bool = false
       var restTimer: RestTimerState = .idle
       var elapsedTime: TimeInterval = 0

       // Computed
       var currentExercise: Exercise? {
           guard selectedExerciseIndex >= 0, selectedExerciseIndex < exercises.count else { return nil }
           return exercises[selectedExerciseIndex]
       }
       var currentSets: [WorkoutSet] {
           guard let exercise = currentExercise else { return [] }
           return setsByExercise[exercise.id] ?? []
       }

       init(workoutService: any WorkoutServiceProtocol,
            setService: any SetServiceProtocol,
            exerciseService: any ExerciseServiceProtocol) {
           self.workoutService = workoutService
           self.setService = setService
           self.exerciseService = exerciseService
       }
   }
   ```
3. Define `RestTimerState` enum (in the same file or a separate helper):
   ```swift
   enum RestTimerState: Equatable {
       case idle
       case running(remaining: Int, total: Int)
       case finished
   }
   ```

**Validation**:
- [ ] Class compiles with `@Observable @MainActor`
- [ ] All three services injected via init
- [ ] Computed properties `currentExercise` and `currentSets` work correctly

### Subtask T007 – Implement loadActiveWorkout()

- **Purpose**: Load or detect an active workout on screen appear. Fetches the workout, its exercises (from set data), and all sets grouped by exercise.
- **Parallel?**: No — builds on T006.

**Steps**:
1. Implement `loadActiveWorkout()`:
   ```swift
   func loadActiveWorkout() async {
       isLoading = true
       defer { isLoading = false }

       do {
           // Check for existing active workout
           let active = try await workoutService.getActiveWorkout()
           guard let active else { return }  // No active workout — screen shouldn't be shown

           self.workout = active

           // Fetch sets for this workout
           // Need to get sets grouped by exerciseId
           // Check SetServiceProtocol for available fetch methods

           // Fetch exercise details for each unique exerciseId
           // Build exercises array and setsByExercise dict

       } catch {
           // Handle error — log and show error state
           print("Failed to load active workout: \(error)")
       }
   }
   ```
2. **Critical**: Read `SetServiceProtocol` and `SetRepositoryProtocol` to find the correct method for fetching sets by workoutId. The VM may need to call a repository method indirectly through the service, or there may be a service method for fetching sets.
3. If no direct "fetch sets for workout" method exists on SetService, consider if there's a WorkoutService method that returns sets, or if you need to fetch sets via a different path. **Do not invent new service methods** — use what exists.
4. Group fetched sets by `exerciseId` into the `setsByExercise` dictionary.
5. For each unique `exerciseId`, fetch the `Exercise` object via `exerciseService.fetchExercise(exerciseId)`.
6. Order exercises by their `orderInExercise` (take the first set's orderInExercise for each exercise group).

**Validation**:
- [ ] After calling `loadActiveWorkout()`, `workout` is populated
- [ ] `exercises` array is populated with Exercise objects
- [ ] `setsByExercise` dictionary maps exerciseId → [WorkoutSet]
- [ ] `isLoading` correctly toggles

### Subtask T008 – Implement completeSet()

- **Purpose**: The critical hot path — user taps the checkbox to complete a set. Persists via SetService, updates local state with PR results, triggers rest timer.
- **Parallel?**: No — builds on T006/T007.

**Steps**:
1. Read `SetServiceProtocol` to understand the exact `save()` / `edit()` method signature and `SetSaveResult` shape.
2. Implement `completeSet()`:
   ```swift
   func completeSet(_ set: WorkoutSet, weight: Double?, reps: Int?,
                    durationSeconds: Int?, distanceMeters: Double?) async {
       // 1. Update the set object with input values
       //    set.weight = weight
       //    set.reps = reps
       //    set.durationSeconds = durationSeconds
       //    set.distanceMeters = distanceMeters
       //    set.completed = true
       //    set.completedAt = Date()

       // 2. Call SetService.save() or edit()
       //    let result = try await setService.save(set)  // or edit() for existing sets

       // 3. Update local state with result
       //    - set.effectiveWeight = result.effectiveWeight
       //    - set.cachedPRStatus from result.prResult.newStatus
       //    - Update any affectedSetIds from result.prResult.affectedSetIds

       // 4. Start rest timer
       //    if let exercise = currentExercise {
       //        startRestTimer(duration: exercise.defaultRestTime ?? 90)
       //    }
   }
   ```
3. **Handle `affectedSetIds`**: The `PREvaluationResult` may contain other sets whose `cachedPRStatus` changed (e.g., a previous PR was demoted). Iterate through `affectedSetIds` and update those sets in `setsByExercise`.
4. Wrap in `do/catch` — log errors but don't crash.

**Validation**:
- [ ] Set is saved via SetService (not directly to repo)
- [ ] Local set state updated with effectiveWeight and cachedPRStatus
- [ ] Affected sets (from PR pipeline) updated in local state
- [ ] Rest timer starts after completion
- [ ] Errors are caught and handled gracefully

### Subtask T009 – Implement addSet() and addWarmupSet()

- **Purpose**: Add new empty rows to the set table for the current exercise.
- **Parallel?**: No — builds on T006.

**Steps**:
1. Implement `addSet(for exerciseId: UUID)`:
   - Create a new `WorkoutSet` with:
     - `workoutId` = current workout id
     - `exerciseId` = the given exerciseId
     - `setType` = `.working`
     - `completed` = false
     - `orderInWorkout` = next order (count all sets across exercises + 1)
     - `orderInExercise` = next order for this exercise (count sets for this exerciseId + 1)
     - `date` = Date()
   - Persist via SetService (save the empty set so it survives app kill)
   - Append to `setsByExercise[exerciseId]`
2. Implement `addWarmupSet(for exerciseId: UUID)`:
   - Same as above but `setType` = `.warmup`
   - Insert BEFORE working sets in the exercise's set list (warmups conventionally come first)

**Validation**:
- [ ] New set appears in `setsByExercise` for the correct exercise
- [ ] Set is persisted (survives app kill per FR-003)
- [ ] Warmup set has `.warmup` type
- [ ] Order fields are correct

### Subtask T010 – Implement deleteSet() and changeSetType()

- **Purpose**: Handle set deletion (with PR/stats cascade) and set type changes (e.g., working → warmup).
- **Parallel?**: No — builds on T006.

**Steps**:
1. Implement `deleteSet(_ set: WorkoutSet)`:
   - Call `setService.delete(set)` — this handles PR/stats cascade
   - Remove set from `setsByExercise[set.exerciseId]`
   - Handle `PREvaluationResult.affectedSetIds` — other sets may have changed badges
   - Reindex `orderInExercise` for remaining sets in this exercise
2. Implement `changeSetType(_ set: WorkoutSet, to type: SetType)`:
   - Update set's `setType`
   - Call `setService.edit(set)` — type change may affect PR eligibility
   - Update local state with result

**Validation**:
- [ ] Deleted set removed from local state
- [ ] SetService.delete() called (not direct repo access)
- [ ] Affected sets updated after deletion
- [ ] Set type change persisted and PR pipeline re-evaluated

### Subtask T011 – Implement Exercise Operations

- **Purpose**: Add, remove, and reorder exercises in the active workout.
- **Parallel?**: Can run alongside T008-T010 (different concerns).

**Steps**:
1. Implement `addExercises(_ exerciseIds: [UUID])`:
   - For each exerciseId:
     - Fetch Exercise via `exerciseService.fetchExercise(exerciseId)`
     - Append to `exercises` array
     - Create an initial empty working set (via `addSet()`)
     - Initialize `setsByExercise[exerciseId]` with the new set
   - Switch to the newly added exercise tab (set `selectedExerciseIndex`)
2. Implement `removeExercise(at index: Int)`:
   - Get the exercise at the index
   - Delete all sets for this exercise in this workout (loop through `setsByExercise[exerciseId]` and call `deleteSet()` for each, or find a bulk approach)
   - Remove from `exercises` array
   - Remove from `setsByExercise` dictionary
   - Adjust `selectedExerciseIndex` if needed (clamp to valid range)
3. Implement `reorderExercises(from source: IndexSet, to destination: Int)`:
   - Rearrange `exercises` array using `exercises.move(fromOffsets: source, toOffset: destination)`
   - No immediate persistence needed — order is maintained in the ViewModel array

**Validation**:
- [ ] Added exercises appear in tab strip
- [ ] Each added exercise gets an initial empty set
- [ ] Removed exercise and all its sets are deleted
- [ ] Reorder updates exercises array correctly
- [ ] selectedExerciseIndex stays valid after remove/reorder

## Risks & Mitigations

- **SetService.save() signature**: The exact method signature may differ from what's shown here. Read the protocol file carefully. The save method likely takes specific parameters (not a full WorkoutSet object) — adapt accordingly.
- **Fetching sets for a workout**: There may not be a direct "fetch sets by workoutId" on SetService. Check WorkoutService and SetService protocols. If needed, the sets may need to be fetched through a repository method exposed via a service.
- **SwiftData object lifecycle**: WorkoutSet and Exercise are `@Model` objects. They may need to be on the same ModelContext. Since the VM doesn't access ModelContext, work with UUIDs and let services handle object lifecycle.

## Definition of Done Checklist

- [ ] All subtasks completed and validated
- [ ] ActiveWorkoutViewModel compiles with all methods
- [ ] All service calls use async/await (no synchronous blocking)
- [ ] No direct ModelContext or Repository access from ViewModel
- [ ] RestTimerState enum defined
- [ ] Project builds with zero errors

## Review Guidance

- Verify ViewModel is `@Observable @MainActor` (not `ObservableObject`)
- Verify all service interactions go through protocols (not concrete types)
- Verify `completeSet()` handles `affectedSetIds` from PR pipeline
- Check that set creation includes all required fields (workoutId, exerciseId, date, order fields)
- Verify no layer violations (ViewModel → Services only, never Repositories)

## Activity Log

- 2026-02-24T14:26:08Z – system – lane=planned – Prompt created.
- 2026-02-24T19:02:19Z – claude – shell_pid=16406 – lane=doing – Started implementation via workflow command
- 2026-02-24T19:06:25Z – claude – shell_pid=16406 – lane=for_review – Ready for review: ActiveWorkoutViewModel (431 lines) — full lifecycle, set CRUD, exercise ops, rest timer, finish workout. @Observable @MainActor, services-only, handles affectedSetIds from PR pipeline. Build succeeds zero errors.
- 2026-02-24T19:07:30Z – claude – shell_pid=17329 – lane=doing – Started review via workflow command
- 2026-02-24T19:11:26Z – claude – shell_pid=17329 – lane=done – Review passed: @Observable @MainActor ViewModel with correct DI, service-only access, all lifecycle/CRUD/exercise ops, affectedSetIds handled, build succeeds.
