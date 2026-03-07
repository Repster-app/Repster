---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
title: "Foundation — Service Layer + Protocol Definition"
phase: "Phase 0 - Foundation"
lane: "done"
dependencies: []
assignee: ""
agent: "claude-opus-reviewer"
shell_pid: "23658"
review_status: "approved"
reviewed_by: "Magnus Espensen"
history:
  - timestamp: "2026-03-02T14:27:05Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP01 – Foundation — Service Layer + Protocol Definition

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Implementation Command

```bash
spec-kitty implement WP01
```

No dependencies — this is the starting package.

---

## Objectives & Success Criteria

1. Add `updateWorkoutMetadata(_:notes:perceivedEffort:)` to `WorkoutServiceProtocol` and implement it in `WorkoutService`.
2. Create the `SetTableDataSource` protocol that both `ActiveWorkoutViewModel` and `EditWorkoutViewModel` will conform to.
3. Project compiles after all changes.

**Success**: Both new pieces exist, compile, and the active workout flow is unaffected (no existing callers changed yet).

## Context & Constraints

- **Constitution**: MVVM with Service/Repository layers. ViewModels call Services only. Services call Repositories only. `@Observable` for ViewModels. `async/await` preferred.
- **Spec**: `kitty-specs/015-edit-historic-workout/spec.md` — FR-009 (notes editing), FR-011 (component reuse).
- **Contracts**: `kitty-specs/015-edit-historic-workout/contracts/view-contracts.md` — exact protocol interface.
- **Research**: `kitty-specs/015-edit-historic-workout/research.md` — R1 (protocol design), R3 (notes persistence).

## Subtasks & Detailed Guidance

### Subtask T001 – Add `updateWorkoutMetadata` to WorkoutServiceProtocol

- **Purpose**: The existing protocol has no method to update metadata on a completed workout. `finishWorkout()` resets endTime/duration so it can't be reused.
- **File**: `Reppo/Core/Services/Protocols/WorkoutServiceProtocol.swift`
- **Steps**:
  1. Add a new method declaration in the `// MARK: - CRUD` section (after `fetchAllWorkouts`):
     ```swift
     /// Update metadata (notes, perceived effort) on a completed workout.
     ///
     /// Updates notes, perceivedEffort, and updatedAt. Does not modify status, date,
     /// startTime, endTime, or duration.
     ///
     /// - Parameters:
     ///   - workoutId: The workout to update.
     ///   - notes: Updated free-text notes (nil to clear).
     ///   - perceivedEffort: Updated RPE value (nil to clear).
     func updateWorkoutMetadata(_ workoutId: UUID, notes: String?, perceivedEffort: Double?) async throws
     ```
- **Parallel?**: Yes — can proceed alongside T003.
- **Notes**: Follows the existing naming convention (`deleteWorkout`, `fetchWorkout`, etc.). The method is simple — no cascade effects.

### Subtask T002 – Implement `updateWorkoutMetadata` in WorkoutService

- **Purpose**: Provide the concrete implementation that fetches the workout, updates fields, and persists.
- **File**: `Reppo/Core/Services/WorkoutService.swift`
- **Steps**:
  1. Find the `WorkoutService` actor class.
  2. Add the implementation. Pattern mirrors `finishWorkout()` but only updates metadata:
     ```swift
     func updateWorkoutMetadata(_ workoutId: UUID, notes: String?, perceivedEffort: Double?) async throws {
         guard let workout = try await workoutRepo.fetch(byId: workoutId) else {
             throw WorkoutServiceError.workoutNotFound(workoutId)
         }
         workout.notes = notes
         workout.perceivedEffort = perceivedEffort
         workout.updatedAt = Date()
         try await workoutRepo.save(workout)
     }
     ```
  3. Verify the `workoutRepo` property name by reading the file — it should be `workoutRepo` or `workoutRepository`.
- **Parallel?**: Must follow T001 (protocol declaration needed first).
- **Notes**:
  - `WorkoutService` is an `actor` type, so `async` is required.
  - Error case: `WorkoutServiceError.workoutNotFound` already exists (used by `finishWorkout`).
  - Do NOT modify `status`, `date`, `startTime`, `endTime`, or `duration` — only `notes`, `perceivedEffort`, and `updatedAt`.

### Subtask T003 – Create SetTableDataSource Protocol

- **Purpose**: Enable `SetTableView` and `ExerciseTabStripView` to work with both `ActiveWorkoutViewModel` and `EditWorkoutViewModel`.
- **File**: `Reppo/Features/Workout/Protocols/SetTableDataSource.swift` (NEW — create directory `Protocols/` if it doesn't exist)
- **Steps**:
  1. Create directory: `Reppo/Features/Workout/Protocols/`
  2. Create the protocol file with the exact interface from view-contracts.md:
     ```swift
     // SetTableDataSource.swift
     // Shared protocol enabling SetTableView and ExerciseTabStripView to work with
     // both ActiveWorkoutViewModel and EditWorkoutViewModel.
     // Spec: 015-edit-historic-workout, contracts/view-contracts.md

     import Foundation

     /// Data source protocol for set table and exercise tab strip components.
     ///
     /// Conforming types provide exercise/set state and handle user actions
     /// (complete set, add set, delete set, reorder exercises, etc.).
     /// Both `ActiveWorkoutViewModel` and `EditWorkoutViewModel` conform.
     @MainActor
     protocol SetTableDataSource: AnyObject, Observable {

         // MARK: - State

         /// All exercises in the current workout, ordered by display position.
         var exercises: [Exercise] { get }

         /// Index of the currently selected exercise in the tab strip.
         var selectedExerciseIndex: Int { get set }

         // MARK: - Computed

         /// The currently selected exercise, or nil if no exercises exist.
         var currentExercise: Exercise? { get }

         /// Sets for the currently selected exercise, ordered by orderInExercise.
         var currentSets: [WorkoutSet] { get }

         // MARK: - Set Actions

         /// Complete or update a set with the given values.
         ///
         /// For new sets: persists via SetService.save().
         /// For existing sets: persists via SetService.edit().
         func completeSet(
             _ set: WorkoutSet,
             weight: Double?,
             reps: Int?,
             durationSeconds: Int?,
             distanceMeters: Double?
         ) async

         /// Add a new working set for the given exercise.
         func addSet(for exerciseId: UUID) async

         /// Add a new warmup set for the given exercise.
         func addWarmupSet(for exerciseId: UUID) async

         /// Delete a set from the workout.
         func deleteSet(_ set: WorkoutSet) async

         /// Change a set's type (e.g., warmup → working → dropset).
         func changeSetType(_ set: WorkoutSet, to type: SetType) async

         // MARK: - Exercise Actions

         /// Reorder exercises by moving from source indices to destination.
         func reorderExercises(from source: IndexSet, to destination: Int)

         /// Remove the exercise at the given index and delete all its sets.
         func removeExercise(at index: Int) async
     }
     ```
  3. Verify imports: `Foundation` should suffice since `Exercise`, `WorkoutSet`, `SetType` are SwiftData model types visible project-wide.
- **Parallel?**: Yes — can proceed alongside T001+T002.
- **Notes**:
  - `@MainActor` is required because both ViewModels are `@MainActor`.
  - `AnyObject` is required for `var dataSource` in views (reference semantics).
  - `Observable` is required so SwiftUI views can observe state changes on the conforming type.
  - DO NOT add `Sendable` — `@MainActor` handles thread safety.
  - The `Observable` requirement uses the `Observation` framework's `Observable` protocol (iOS 17+), not `ObservableObject`.

## Risks & Mitigations

- **Protocol compilation**: If `Observable` as a protocol constraint causes issues (it's a macro-based protocol in Swift), try using the `Observation.Observable` protocol directly. Check how `@Observable` is defined in the project.
- **Import issues**: If model types aren't visible, you may need `import SwiftData` or the app's module import.

## Definition of Done Checklist

- [ ] `WorkoutServiceProtocol` has `updateWorkoutMetadata` method declaration
- [ ] `WorkoutService` implements `updateWorkoutMetadata` correctly
- [ ] `SetTableDataSource.swift` exists in `Reppo/Features/Workout/Protocols/`
- [ ] Protocol has all 4 properties and 7 methods per view-contracts.md
- [ ] Project compiles with no errors
- [ ] No existing behavior changed (active workout unaffected)

## Review Guidance

- Verify protocol interface matches view-contracts.md exactly — any mismatch will break WP02.
- Verify `updateWorkoutMetadata` doesn't modify workout status, date, or duration fields.
- Verify the protocol uses `@MainActor`, `AnyObject`, and `Observable` constraints.

## Activity Log

- 2026-03-02T14:27:05Z – system – lane=planned – Prompt created.
- 2026-03-02T16:57:56Z – claude-opus – shell_pid=19938 – lane=doing – Started implementation via workflow command
- 2026-03-02T17:08:08Z – claude-opus – shell_pid=19938 – lane=for_review – Ready for review: Added updateWorkoutMetadata to protocol+service, created SetTableDataSource protocol with 4 properties and 7 methods per view-contracts.md. Build succeeds with no errors.
- 2026-03-02T17:10:07Z – claude-opus-reviewer – shell_pid=23658 – lane=doing – Started review via workflow command
- 2026-03-02T17:11:41Z – claude-opus-reviewer – shell_pid=23658 – lane=done – Review passed: All 3 subtasks verified. Protocol declaration matches view-contracts.md exactly (4 properties, 7 methods, @MainActor/AnyObject/Observable constraints). updateWorkoutMetadata correctly updates only notes/perceivedEffort/updatedAt. Xcode project properly integrated. Build succeeds with zero errors. No existing behavior changed.
