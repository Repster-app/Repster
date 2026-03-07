---
work_package_id: "WP02"
subtasks:
  - "T004"
  - "T005"
  - "T006"
  - "T007"
  - "T008"
  - "T009"
title: "Protocol Refactor — Existing Views"
phase: "Phase 0 - Foundation"
lane: "done"
dependencies: ["WP01"]
assignee: ""
agent: "claude-opus-reviewer"
shell_pid: "47497"
review_status: "approved"
reviewed_by: "Magnus Espensen"
history:
  - timestamp: "2026-03-02T14:27:05Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP02 – Protocol Refactor — Existing Views

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
spec-kitty implement WP02 --base WP01
```

Depends on WP01 (SetTableDataSource protocol must exist).

---

## Objectives & Success Criteria

1. Refactor `SetTableView`, `SetRowWrapper`, and `ExerciseTabStripView` to accept `any SetTableDataSource` instead of `ActiveWorkoutViewModel`.
2. Conform `ActiveWorkoutViewModel` to `SetTableDataSource`.
3. Update `ActiveWorkoutView` call sites.
4. **Active workout flow works identically** — no regressions.

**Success**: Build passes. Active workout: start → add exercise → log set → change set type → delete set → reorder exercises → finish — all unchanged.

## Context & Constraints

- **Key files to modify** (read these before starting):
  - `Reppo/Features/Workout/Views/SetTableView.swift` — contains both `SetTableView` and `SetRowWrapper` (private struct)
  - `Reppo/Features/Workout/Views/ExerciseTabStripView.swift` — exercise tab navigation
  - `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` — must conform to protocol
  - `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` — update call sites
- **Protocol**: `Reppo/Features/Workout/Protocols/SetTableDataSource.swift` (created in WP01)
- **Constitution**: Views call ViewModels only. No business logic in Views.

## Subtasks & Detailed Guidance

### Subtask T004 – Refactor SetTableView to accept protocol

- **Purpose**: SetTableView currently depends on concrete `ActiveWorkoutViewModel`. Change to protocol for reuse.
- **File**: `Reppo/Features/Workout/Views/SetTableView.swift`
- **Steps**:
  1. Read the current file to understand the structure.
  2. In `struct SetTableView`, change:
     ```swift
     // BEFORE
     var viewModel: ActiveWorkoutViewModel

     // AFTER
     var dataSource: any SetTableDataSource
     ```
  3. Update all references in the body:
     - `viewModel.currentExercise` → `dataSource.currentExercise`
     - `viewModel.currentSets` → `dataSource.currentSets`
  4. In `addButtons(for:)`, update:
     - `viewModel.addSet(for: exerciseId)` → `dataSource.addSet(for: exerciseId)`
     - `viewModel.addWarmupSet(for: exerciseId)` → `dataSource.addWarmupSet(for: exerciseId)`
  5. Update the `SetRowWrapper` init call:
     - `SetRowWrapper(set:, exercise:, setNumber:, viewModel:)` → `SetRowWrapper(set:, exercise:, setNumber:, dataSource:)`
- **Notes**: The rename is mechanical — search-and-replace `viewModel` → `dataSource` within the SetTableView struct only. Do NOT touch the Preview section at the bottom (it uses inline mock data, not the ViewModel).

### Subtask T005 – Refactor SetRowWrapper to accept protocol

- **Purpose**: SetRowWrapper also holds a reference to the ViewModel for action closures.
- **File**: `Reppo/Features/Workout/Views/SetTableView.swift` (same file, private struct)
- **Steps**:
  1. In `private struct SetRowWrapper`, change:
     ```swift
     // BEFORE
     var viewModel: ActiveWorkoutViewModel

     // AFTER
     var dataSource: any SetTableDataSource
     ```
  2. Update the init:
     ```swift
     // BEFORE
     init(set:, exercise:, setNumber:, viewModel: ActiveWorkoutViewModel)

     // AFTER
     init(set:, exercise:, setNumber:, dataSource: any SetTableDataSource)
     ```
  3. Update all closures in the body:
     - `viewModel.completeSet(...)` → `dataSource.completeSet(...)`
     - `viewModel.deleteSet(set)` → `dataSource.deleteSet(set)`
     - `viewModel.changeSetType(set, to: newType)` → `dataSource.changeSetType(set, to: newType)`
- **Notes**: The closure parameters (weight, reps, etc.) and text-to-numeric conversions remain unchanged — only the target object changes.

### Subtask T006 – Refactor ExerciseTabStripView to accept protocol

- **Purpose**: ExerciseTabStripView also depends on concrete ActiveWorkoutViewModel.
- **File**: `Reppo/Features/Workout/Views/ExerciseTabStripView.swift`
- **Steps**:
  1. Read the file to understand usage patterns.
  2. Change:
     ```swift
     // BEFORE
     var viewModel: ActiveWorkoutViewModel

     // AFTER
     var dataSource: any SetTableDataSource
     ```
  3. Update all references:
     - `viewModel.exercises` → `dataSource.exercises`
     - `viewModel.selectedExerciseIndex` → `dataSource.selectedExerciseIndex`
     - `viewModel.exercises.count` → `dataSource.exercises.count`
     - `viewModel.reorderExercises(from:to:)` → `dataSource.reorderExercises(from:to:)`
     - `viewModel.removeExercise(at:)` → `dataSource.removeExercise(at:)`
- **Parallel?**: Yes — different file from T004/T005.
- **Notes**: The `ExerciseTab` private struct does NOT reference the ViewModel — leave it unchanged.

### Subtask T007 – Conform ActiveWorkoutViewModel to SetTableDataSource

- **Purpose**: The existing ViewModel must conform so the refactored views continue working.
- **File**: `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift`
- **Steps**:
  1. Add conformance extension at the bottom of the file (before any `#Preview` blocks):
     ```swift
     // MARK: - SetTableDataSource Conformance

     extension ActiveWorkoutViewModel: SetTableDataSource { }
     ```
  2. The extension body should be empty — all required methods and properties already exist with matching signatures.
  3. If the compiler reports missing members, check the exact signatures. The protocol requires:
     - `var exercises: [Exercise]` ✓ (exists)
     - `var selectedExerciseIndex: Int` ✓ (exists)
     - `var currentExercise: Exercise?` ✓ (exists as computed)
     - `var currentSets: [WorkoutSet]` ✓ (exists as computed)
     - `func completeSet(_:weight:reps:durationSeconds:distanceMeters:) async` ✓ (exists)
     - `func addSet(for:) async` ✓ (exists)
     - `func addWarmupSet(for:) async` ✓ (exists)
     - `func deleteSet(_:) async` ✓ (exists)
     - `func changeSetType(_:to:) async` ✓ (exists)
     - `func reorderExercises(from:to:)` ✓ (exists, synchronous)
     - `func removeExercise(at:) async` ✓ (exists)
- **Parallel?**: Yes — can proceed once WP01 is done.
- **Notes**: If there's a minor signature mismatch (e.g., `throws` on a method that the protocol doesn't require), you may need to adjust. But based on research, all signatures should match exactly.

### Subtask T008 – Update ActiveWorkoutView call sites

- **Purpose**: Pass `dataSource:` instead of `viewModel:` to the refactored components.
- **File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift`
- **Steps**:
  1. Find where `SetTableView` is instantiated (approximately line 140 area, in the sub-tab content):
     ```swift
     // BEFORE
     SetTableView(viewModel: viewModel)

     // AFTER
     SetTableView(dataSource: viewModel)
     ```
  2. Find where `ExerciseTabStripView` is instantiated (approximately line 64):
     ```swift
     // BEFORE
     ExerciseTabStripView(viewModel: viewModel)

     // AFTER
     ExerciseTabStripView(dataSource: viewModel)
     ```
  3. Search for any other references to ensure none are missed.
- **Notes**: Only TWO call sites need changing. The `viewModel` local variable in `ActiveWorkoutView` is still `ActiveWorkoutViewModel` — it's just passed as `any SetTableDataSource` to the sub-views.

### Subtask T009 – Build verification

- **Purpose**: Confirm no regressions in the active workout flow.
- **Steps**:
  1. Build the project (Cmd+B in Xcode or `xcodebuild`).
  2. Fix any compilation errors (should be none if steps above were followed correctly).
  3. Manual verification checklist:
     - Start a new workout
     - Add an exercise via the exercise picker
     - Log a working set (enter weight/reps, tap checkbox)
     - Verify PR badge appears if applicable
     - Add a warmup set
     - Change a set type via context menu
     - Delete a set via context menu
     - Add a second exercise
     - Reorder exercises via "Move Left"/"Move Right"
     - Delete an exercise
     - Finish the workout
  4. If anything behaves differently, the refactor introduced a bug — investigate.
- **Notes**: This is the critical checkpoint. ALL active workout functionality must be identical.

## Risks & Mitigations

- **`any` existential performance**: Using `any SetTableDataSource` introduces protocol existential overhead. For UI state management this is negligible. If profiling shows issues, can switch to generics `<T: SetTableDataSource>` later.
- **SwiftUI observation through existential**: `@Observable` observation may not propagate through `any` existential types in some Swift versions. If views don't update, try using `@Bindable var dataSource` or wrapping in a generic container. Test carefully.
- **Preview breakage**: The `#Preview` blocks at the bottom of SetTableView use inline mock data, not the ViewModel. They should be unaffected. If they break, update or remove them.

## Definition of Done Checklist

- [ ] `SetTableView` accepts `any SetTableDataSource` (not ActiveWorkoutViewModel)
- [ ] `SetRowWrapper` accepts `any SetTableDataSource`
- [ ] `ExerciseTabStripView` accepts `any SetTableDataSource`
- [ ] `ActiveWorkoutViewModel` conforms to `SetTableDataSource`
- [ ] `ActiveWorkoutView` passes `dataSource: viewModel` to both components
- [ ] Project builds without errors
- [ ] Active workout flow manually verified — no regressions

## Review Guidance

- **Critical**: Run the active workout flow end-to-end. Any regression here blocks the entire feature.
- Verify no references to `ActiveWorkoutViewModel` remain in SetTableView or ExerciseTabStripView (except in Previews if they use mock data).
- Check that `any SetTableDataSource` is used consistently (not `some SetTableDataSource` — we need existential, not opaque type).

## Activity Log

- 2026-03-02T14:27:05Z – system – lane=planned – Prompt created.
- 2026-03-02T17:12:04Z – claude-opus – shell_pid=24285 – lane=doing – Started implementation via workflow command
- 2026-03-02T19:16:24Z – claude-opus – shell_pid=24285 – lane=for_review – Ready for review: Refactored SetTableView, SetRowWrapper, ExerciseTabStripView to accept any SetTableDataSource. ActiveWorkoutViewModel conforms via empty extension. ActiveWorkoutView call sites updated. Zero ActiveWorkoutViewModel refs remain in shared views. Build succeeds.
- 2026-03-02T19:17:12Z – claude-opus-reviewer – shell_pid=47497 – lane=doing – Started review via workflow command
- 2026-03-02T19:18:41Z – claude-opus-reviewer – shell_pid=47497 – lane=done – Review passed: All 6 subtasks verified. SetTableView, SetRowWrapper, ExerciseTabStripView all accept any SetTableDataSource. Zero ActiveWorkoutViewModel refs remain in shared views. ActiveWorkoutViewModel conforms via empty extension. 2 call sites in ActiveWorkoutView updated. any (not some) used consistently. Previews unaffected. Build succeeds.
