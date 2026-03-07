---
work_package_id: "WP04"
subtasks:
  - "T015"
  - "T016"
  - "T017"
  - "T018"
  - "T019"
title: "EditWorkoutViewModel — Exercise Management + Notes"
phase: "Phase 2 - User Stories 2-4 (P2-P3)"
lane: "done"
dependencies: ["WP03"]
assignee: ""
agent: "claude-opus-reviewer"
shell_pid: "52394"
review_status: "approved"
reviewed_by: "Magnus Espensen"
history:
  - timestamp: "2026-03-02T14:27:05Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP04 – EditWorkoutViewModel — Exercise Management + Notes

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
spec-kitty implement WP04 --base WP03
```

Depends on WP03 (EditWorkoutViewModel core must exist).

---

## Objectives & Success Criteria

1. Add exercise management (add, remove, reorder) to `EditWorkoutViewModel`.
2. Add notes persistence via `saveNotes()`.
3. Add computed properties (`currentExercise`, `currentSets`) and full `SetTableDataSource` conformance.
4. ViewModel is complete and ready to be consumed by `EditWorkoutView` (WP05).

**Success**: All `SetTableDataSource` protocol requirements are satisfied. Adding, removing, reordering exercises works. Notes save via `updateWorkoutMetadata()`.

## Context & Constraints

- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift` (created in WP03)
- **Reference**: `ActiveWorkoutViewModel` methods: `addExercises()`, `removeExercise(at:)`, `reorderExercises(from:to:)` — follow same patterns.
- **Protocol**: `SetTableDataSource` from `Reppo/Features/Workout/Protocols/SetTableDataSource.swift` (WP01).

## Subtasks & Detailed Guidance

### Subtask T015 – Implement addExercises

- **Purpose**: Allow adding new exercises to the workout via the exercise picker.
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`
- **Steps**:
  1. Add method:
     ```swift
     // MARK: - Exercise Actions

     func addExercises(_ exerciseIds: [UUID]) async {
         for exerciseId in exerciseIds {
             do {
                 guard let exercise = try await exerciseService.fetchExercise(exerciseId) else {
                     continue
                 }
                 exercises.append(exercise)
                 setsByExercise[exerciseId] = []

                 // Create initial empty working set
                 await addSet(for: exerciseId)

             } catch {
                 print("[EditWorkoutViewModel] addExercise failed: \(error)")
             }
         }

         // Switch to the last added exercise
         if !exercises.isEmpty {
             selectedExerciseIndex = exercises.count - 1
         }
     }
     ```
- **Notes**: This follows `ActiveWorkoutViewModel.addExercises()` exactly. Each new exercise gets one initial empty set so the set table isn't empty.

### Subtask T016 – Implement removeExercise

- **Purpose**: Remove an exercise and cascade-delete all its sets.
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`
- **Steps**:
  1. Add method:
     ```swift
     func removeExercise(at index: Int) async {
         guard index >= 0, index < exercises.count else { return }

         let exercise = exercises[index]
         let exerciseSets = setsByExercise[exercise.id] ?? []

         // Delete all sets for this exercise
         for set in exerciseSets {
             do {
                 try await setService.delete(set)
                 newSetIds.remove(set.id)
             } catch {
                 print("[EditWorkoutViewModel] delete set during removeExercise failed: \(error)")
             }
         }

         // Remove from local state
         exercises.remove(at: index)
         setsByExercise.removeValue(forKey: exercise.id)

         // Clamp selectedExerciseIndex
         if selectedExerciseIndex >= exercises.count {
             selectedExerciseIndex = max(0, exercises.count - 1)
         }
     }
     ```
- **Notes**: Must delete ALL sets before removing the exercise from local state. Each `setService.delete()` handles PR recomputation and stats decrement.

### Subtask T017 – Implement reorderExercises

- **Purpose**: Allow reordering exercises via "Move Left"/"Move Right" in the tab strip context menu.
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`
- **Steps**:
  1. Add method:
     ```swift
     func reorderExercises(from source: IndexSet, to destination: Int) {
         exercises.move(fromOffsets: source, toOffset: destination)

         // Update selectedExerciseIndex to follow the moved exercise
         if let sourceIndex = source.first {
             if sourceIndex == selectedExerciseIndex {
                 // The selected exercise was moved
                 if destination > sourceIndex {
                     selectedExerciseIndex = destination - 1
                 } else {
                     selectedExerciseIndex = destination
                 }
             }
         }
     }
     ```
- **Notes**: This is local-only reordering (same as `ActiveWorkoutViewModel`). No persistence needed — the order is determined by the `exercises` array.

### Subtask T018 – Implement saveNotes

- **Purpose**: Persist updated notes when the user dismisses the edit view.
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`
- **Steps**:
  1. Add method:
     ```swift
     // MARK: - Notes

     func saveNotes() async {
         guard let workout else { return }

         // Only save if notes actually changed
         let currentNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
         let originalNotes = (workout.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

         guard currentNotes != originalNotes else { return }

         do {
             try await workoutService.updateWorkoutMetadata(
                 workout.id,
                 notes: currentNotes.isEmpty ? nil : currentNotes,
                 perceivedEffort: workout.perceivedEffort  // preserve existing RPE
             )
         } catch {
             print("[EditWorkoutViewModel] saveNotes failed: \(error)")
         }
     }
     ```
- **Notes**: Notes save on dismiss, not on every keystroke. Pass existing `perceivedEffort` to avoid clearing it.

### Subtask T019 – Add computed properties and SetTableDataSource conformance

- **Purpose**: Add `currentExercise` and `currentSets` computed properties, then declare protocol conformance.
- **File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`
- **Steps**:
  1. Add computed properties (in the State section or as a separate MARK):
     ```swift
     // MARK: - Computed

     var currentExercise: Exercise? {
         guard selectedExerciseIndex >= 0,
               selectedExerciseIndex < exercises.count else { return nil }
         return exercises[selectedExerciseIndex]
     }

     var currentSets: [WorkoutSet] {
         guard let exercise = currentExercise else { return [] }
         return setsByExercise[exercise.id] ?? []
     }
     ```
  2. Add protocol conformance:
     ```swift
     // MARK: - SetTableDataSource Conformance

     extension EditWorkoutViewModel: SetTableDataSource { }
     ```
  3. Build the project. If the compiler reports missing protocol requirements, verify all method signatures match exactly.
  4. Add `changeSetType` if not already present:
     ```swift
     func changeSetType(_ set: WorkoutSet, to type: SetType) async {
         set.setType = type
         set.updatedAt = Date()
         do {
             _ = try await setService.edit(set)
         } catch {
             print("[EditWorkoutViewModel] changeSetType failed: \(error)")
         }
     }
     ```
- **Notes**: `changeSetType` is required by the protocol. It calls `setService.edit()` to persist the type change. The `ActiveWorkoutViewModel` implementation is the reference.

## Risks & Mitigations

- **Missing protocol methods**: If any `SetTableDataSource` method is missing, the compiler will report it clearly. Add the missing method following the `ActiveWorkoutViewModel` pattern.
- **Notes trimming**: Empty notes should be stored as `nil`, not empty string. The trimming and nil-coalescing in T018 handles this.

## Definition of Done Checklist

- [ ] `addExercises()` fetches exercises, creates initial sets, updates state
- [ ] `removeExercise(at:)` cascade-deletes sets, removes exercise, clamps index
- [ ] `reorderExercises(from:to:)` reorders array and updates selectedExerciseIndex
- [ ] `saveNotes()` persists notes via `updateWorkoutMetadata()` only when changed
- [ ] `currentExercise` and `currentSets` computed properties work correctly
- [ ] `changeSetType()` persists type change via `setService.edit()`
- [ ] `EditWorkoutViewModel` conforms to `SetTableDataSource` — compiles cleanly
- [ ] Project builds without errors

## Review Guidance

- Verify `removeExercise` deletes ALL sets before removing from local state.
- Verify `saveNotes` preserves existing `perceivedEffort` value.
- Verify all `SetTableDataSource` methods compile — try instantiating `EditWorkoutViewModel` and assigning to `any SetTableDataSource` variable.

## Activity Log

- 2026-03-02T14:27:05Z – system – lane=planned – Prompt created.
- 2026-03-02T19:31:09Z – claude-opus – shell_pid=51269 – lane=doing – Started implementation via workflow command
- 2026-03-02T19:33:35Z – claude-opus – shell_pid=51269 – lane=for_review – Ready for review: addExercises() with initial empty set creation, removeExercise() with newSetIds cleanup per deleted set, reorderExercises() with selectedExerciseIndex tracking, saveNotes() with change detection/trimming preserving perceivedEffort, currentExercise/currentSets computed properties, SetTableDataSource conformance extension. Build succeeds.
- 2026-03-02T19:34:06Z – claude-opus-reviewer – shell_pid=52394 – lane=doing – Started review via workflow command
- 2026-03-02T19:34:55Z – claude-opus-reviewer – shell_pid=52394 – lane=done – Review passed: All 5 subtasks verified. T015 addExercises fetches exercises and creates initial empty sets. T016 removeExercise cascade-deletes all sets with newSetIds cleanup before removing from local state. T017 reorderExercises tracks selectedExerciseIndex. T018 saveNotes has change detection with trimming and preserves perceivedEffort. T019 currentExercise/currentSets computed properties correct, SetTableDataSource conformance compiles cleanly. Build succeeds independently. Note: WP05 depends on this — rebase: cd .worktrees/015-edit-historic-workout-WP05 && git rebase 015-edit-historic-workout-WP04
