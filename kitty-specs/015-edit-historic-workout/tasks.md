# Work Packages: Edit Historic Workout

**Inputs**: Design documents from `/kitty-specs/015-edit-historic-workout/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/view-contracts.md, quickstart.md

**Tests**: Manual testing only (per constitution — no automated tests for v1).

**Organization**: 26 subtasks roll up into 5 work packages. Each WP is independently deliverable.

---

## Work Package WP01: Foundation — Service Layer + Protocol Definition (Priority: P0)

**Goal**: Add `updateWorkoutMetadata()` to WorkoutService and define the `SetTableDataSource` protocol. These are the two foundational pieces all other WPs depend on.
**Independent Test**: Project compiles. `updateWorkoutMetadata()` can be called from a ViewModel. Protocol file exists with correct interface.
**Prompt**: `tasks/WP01-foundation-service-and-protocol.md`
**Estimated size**: ~300 lines

### Included Subtasks
- [x] T001 Add `updateWorkoutMetadata()` to `WorkoutServiceProtocol` in `Reppo/Core/Services/Protocols/WorkoutServiceProtocol.swift`
- [x] T002 Implement `updateWorkoutMetadata()` in `WorkoutService` in `Reppo/Core/Services/WorkoutService.swift`
- [x] T003 Create `SetTableDataSource` protocol in `Reppo/Features/Workout/Protocols/SetTableDataSource.swift` (NEW)

### Implementation Notes
- T001-T002: Minimal service addition. Pattern: fetch by ID, update fields, save via repo. Mirror `finishWorkout()` pattern but without status/endTime changes.
- T003: Protocol requires `@MainActor`, `AnyObject`, `Observable` constraints. 4 properties + 7 methods per view-contracts.md.

### Parallel Opportunities
- T001+T002 (service) and T003 (protocol) touch different files and can proceed in parallel.

### Dependencies
- None (starting package).

### Risks & Mitigations
- Protocol design must exactly match what SetTableView and ExerciseTabStripView consume. view-contracts.md has the verified interface.

---

## Work Package WP02: Protocol Refactor — Existing Views (Priority: P0)

**Goal**: Refactor `SetTableView`, `SetRowWrapper`, and `ExerciseTabStripView` to accept `any SetTableDataSource` instead of `ActiveWorkoutViewModel`. Conform `ActiveWorkoutViewModel` and update call sites. Verify active workout is unchanged.
**Independent Test**: Active workout flow works identically — start workout, add exercise, log sets, change set type, delete set, reorder exercises, finish. No regressions.
**Prompt**: `tasks/WP02-protocol-refactor-existing-views.md`
**Estimated size**: ~450 lines

### Included Subtasks
- [x] T004 Refactor `SetTableView` to accept `var dataSource: any SetTableDataSource` in `Reppo/Features/Workout/Views/SetTableView.swift`
- [x] T005 Refactor `SetRowWrapper` to accept `var dataSource: any SetTableDataSource` in `Reppo/Features/Workout/Views/SetTableView.swift`
- [x] T006 Refactor `ExerciseTabStripView` to accept `var dataSource: any SetTableDataSource` in `Reppo/Features/Workout/Views/ExerciseTabStripView.swift`
- [x] T007 [P] Add `SetTableDataSource` conformance to `ActiveWorkoutViewModel` in `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift`
- [x] T008 Update `ActiveWorkoutView` call sites in `Reppo/Features/Workout/Views/ActiveWorkoutView.swift`
- [x] T009 Build verification — confirm active workout flow unchanged

### Implementation Notes
- T004-T005: Change `var viewModel: ActiveWorkoutViewModel` → `var dataSource: any SetTableDataSource` in both structs. Update all `viewModel.xxx` calls to `dataSource.xxx`. The method names are identical.
- T006: Same pattern for ExerciseTabStripView.
- T007: Add `extension ActiveWorkoutViewModel: SetTableDataSource {}` — all methods already exist with matching signatures. This may be an empty extension body if all signatures match.
- T008: Two call sites: `SetTableView(viewModel: viewModel)` → `SetTableView(dataSource: viewModel)` and `ExerciseTabStripView(viewModel: viewModel)` → `ExerciseTabStripView(dataSource: viewModel)`.
- T009: Build the project. Manually test: start workout → add exercise → log a set → verify PR badge → change set type → delete set → reorder exercises → finish workout.

### Parallel Opportunities
- T004+T005 (SetTableView) and T006 (ExerciseTabStripView) touch different files — parallel.
- T007 can proceed after protocol is defined (WP01).

### Dependencies
- Depends on WP01 (protocol must exist).

### Risks & Mitigations
- **Breaking active workout**: The refactor is mechanical (rename parameter, change type). All method names stay the same. Build verification (T009) catches regressions.
- **Swift existential type limitations**: `any SetTableDataSource` may have protocol witness issues if the protocol has associated types or Self requirements. Our protocol has neither — it uses concrete types (Exercise, WorkoutSet, etc.) so existentials work cleanly.

---

## Work Package WP03: EditWorkoutViewModel — Core Set Operations (Priority: P1) 🎯 MVP

**Goal**: Create `EditWorkoutViewModel` with workout loading and core set CRUD (edit values, add sets, delete sets). This is the P1 user story — editing set values on a completed workout.
**Independent Test**: Create ViewModel with a workout ID, call `loadWorkout()`, verify exercises/sets populate. Call `completeSet()` on an existing set with new values, verify `setService.edit()` is called. Add a set, verify it persists. Delete a set.
**Prompt**: `tasks/WP03-edit-viewmodel-core.md`
**Estimated size**: ~450 lines

### Included Subtasks
- [x] T010 Create `EditWorkoutViewModel` class skeleton with state properties and init in `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift` (NEW)
- [x] T011 Implement `loadWorkout(workoutId:)` — fetch workout, sets, exercises, populate state
- [x] T012 Implement `completeSet()` — distinguish existing vs new sets via `newSetIds`, call `edit()` or `save()`
- [x] T013 Implement `addSet(for:)` and `addWarmupSet(for:)` — create set, persist immediately, track in `newSetIds`
- [x] T014 Implement `deleteSet()` — call `setService.delete()`, remove from local state, reindex orders

### Implementation Notes
- T010: Follow `ActiveWorkoutViewModel` pattern: `@Observable @MainActor`, service dependencies via init. State: `workout`, `exercises`, `setsByExercise`, `selectedExerciseIndex`, `notesText`, `isLoading`, `showAddExerciseSheet`, `newSetIds`.
- T011: Same pattern as `WorkoutDetailFromHomeView.loadDetail()` — fetch workout, fetch sets, group by exerciseId, fetch each exercise, sort by orderInWorkout.
- T012: Critical distinction — if `newSetIds.contains(set.id)`: call `setService.save(set)`. Otherwise: update set properties in-place, call `setService.edit(set)`. Apply `SetSaveResult` to local state (effectiveWeight, cachedPRStatus).
- T013: Create `WorkoutSet(workoutId:, exerciseId:, setType: .working/.warmup, completed: false, orderInWorkout:, orderInExercise:)`. Call `setService.save()` immediately. Add to `newSetIds`. For warmups, insert before first working set and reindex.
- T014: Call `setService.delete(set)`. Remove from `setsByExercise`. Reindex `orderInExercise`. If set was in `newSetIds`, also remove from there.

### Parallel Opportunities
- None within this WP — all subtasks modify the same file sequentially.

### Dependencies
- Depends on WP01 (protocol definition + service method).

### Risks & Mitigations
- **save vs edit confusion**: If `completeSet()` calls `edit()` on a new set (not yet in DB with values), `edit()` will try to fetch old values and may fail. The `newSetIds` tracking prevents this.
- **Set ordering**: Must maintain correct `orderInWorkout` and `orderInExercise` when adding/deleting. Reuse the same indexing logic from `ActiveWorkoutViewModel`.

---

## Work Package WP04: EditWorkoutViewModel — Exercise Management + Notes (Priority: P2)

**Goal**: Complete the EditWorkoutViewModel with exercise add/remove, reordering, notes persistence, and full protocol conformance.
**Independent Test**: Add an exercise via `addExercises()`, verify it appears with an initial empty set. Remove an exercise, verify all its sets are deleted. Edit notes text, call `saveNotes()`, verify persistence.
**Prompt**: `tasks/WP04-edit-viewmodel-exercises-notes.md`
**Estimated size**: ~350 lines

### Included Subtasks
- [x] T015 Implement `addExercises(_ exerciseIds:)` — fetch exercises, create initial sets
- [x] T016 Implement `removeExercise(at:)` — delete all sets for exercise, remove from local state
- [x] T017 Implement `reorderExercises(from:to:)` — local reorder of exercises array
- [x] T018 Implement `saveNotes()` — call `workoutService.updateWorkoutMetadata()`
- [x] T019 Add computed properties `currentExercise` and `currentSets`, verify `SetTableDataSource` conformance

### Implementation Notes
- T015: Pattern from `ActiveWorkoutViewModel.addExercises()` — fetch Exercise objects, append to `exercises`, create initial empty set per exercise via `addSet(for:)`, switch selectedExerciseIndex to new exercise.
- T016: Get all sets for the exercise from `setsByExercise`, delete each via `setService.delete()`, remove exercise from `exercises`, adjust `selectedExerciseIndex`.
- T017: Simple array reorder. Same implementation as `ActiveWorkoutViewModel.reorderExercises()`.
- T018: Call `workoutService.updateWorkoutMetadata(workout.id, notes: notesText, perceivedEffort: workout.perceivedEffort)`. Called from EditWorkoutView when dismissing. Preserves existing RPE value.
- T019: Computed properties mirror ActiveWorkoutViewModel. Protocol conformance should compile with all methods now in place.

### Parallel Opportunities
- None — all subtasks modify the same file.

### Dependencies
- Depends on WP03 (EditWorkoutViewModel must exist with core set operations).

### Risks & Mitigations
- **Exercise removal cascade**: Must delete ALL sets for the exercise before removing it from local state. Order matters to avoid stale references.

---

## Work Package WP05: EditWorkoutView + Integration (Priority: P1)

**Goal**: Create the EditWorkoutView UI and wire it up from WorkoutDetailFromHomeView. This completes the feature end-to-end.
**Independent Test**: Navigate to a completed workout in the Home tab, tap menu → Edit Workout. Full-screen edit opens with pre-populated data. Edit a set value, add a set, add an exercise, modify notes. Dismiss. Verify workout detail refreshes with all changes.
**Prompt**: `tasks/WP05-edit-view-and-integration.md`
**Estimated size**: ~500 lines

### Included Subtasks
- [x] T020 Create `EditWorkoutView` with header bar (Done button, "Edit Workout" title, +Exercise button) in `Reppo/Features/Workout/Views/EditWorkoutView.swift` (NEW)
- [x] T021 Integrate `ExerciseTabStripView(dataSource:)` and `SetTableView(dataSource:)` in the view body
- [x] T022 Add notes `TextEditor` section below the set table
- [x] T023 Add exercise picker sheet integration using `ExerciseListView` in `.addToWorkout` mode
- [x] T024 Add loading state (ProgressView) and empty state handling
- [x] T025 Wire up `WorkoutDetailFromHomeView` — enable edit button, add `@State showEditWorkout`, add `.fullScreenCover`, add `@Environment(ServiceContainer.self)`
- [x] T026 Add `.onChange(of: showEditWorkout)` to reload workout detail data when edit screen dismisses

### Implementation Notes
- T020: Follow `ActiveWorkoutView` header pattern but simplified. No timer, no Finish button. Header: `HStack { Button("Done") { saveNotes(); dismiss() } | Spacer | Text("Edit Workout") | Spacer | Button("+Exercise") }`.
- T021: Compose in `VStack(spacing: 0) { headerBar; ExerciseTabStripView(dataSource: viewModel); ScrollView { SetTableView(dataSource: viewModel); notesSection } }`.
- T022: `TextEditor(text: $viewModel.notesText)` with placeholder overlay when empty. Style per design-system.md tokens (bgCard background, textPrimary foreground).
- T023: `.sheet(isPresented: $viewModel.showAddExerciseSheet) { ExerciseListView(mode: .addToWorkout, ...) }`. On selection: `viewModel.addExercises(selectedIds)`.
- T024: `if viewModel.isLoading { ProgressView() }` overlay.
- T025: In `WorkoutDetailFromHomeView`: remove `.disabled(true)` from edit button, set action to `showEditWorkout = true`, add `@State private var showEditWorkout = false`, add `@Environment(ServiceContainer.self) private var services`, add `.fullScreenCover(isPresented: $showEditWorkout) { EditWorkoutView(workoutId: workoutId, services: services) }`.
- T026: `.onChange(of: showEditWorkout) { _, isShowing in if !isShowing { Task { await loadDetail() } } }`.

### Parallel Opportunities
- T020-T024 (EditWorkoutView) and T025-T026 (WorkoutDetailFromHomeView wiring) touch different files — parallel.

### Dependencies
- Depends on WP02 (views accept protocol) and WP04 (ViewModel complete).

### Risks & Mitigations
- **ServiceContainer access**: `WorkoutDetailFromHomeView` currently receives individual services. Must also read `ServiceContainer` from `@Environment` to pass to `EditWorkoutView`. The container is already in the SwiftUI environment (set in `ReppoApp.swift`).
- **ExerciseListView mode**: Confirm `.addToWorkout` mode exists and the selection callback interface matches. Active workout already uses this mode.

---

## Dependency & Execution Summary

```
WP01 (Foundation) ─┬── WP02 (Refactor views) ──────┐
                   │                                 │
                   └── WP03 (VM Core) ── WP04 (VM Exercises) ── WP05 (View + Integration)
                                                     │
                        WP02 ────────────────────────┘
```

- **Sequence**: WP01 → (WP02 ∥ WP03) → WP04 → WP05
- **Parallelization**: WP02 and WP03 can run in parallel after WP01 completes (different files).
- **Full Scope**: All 5 WPs required. WP05 depends on WP04 (SetTableDataSource conformance), so no WP can be skipped.

---

## Subtask Index (Reference)

| Subtask | Summary | WP | Priority | Parallel? |
|---------|---------|-----|----------|-----------|
| T001 | Add updateWorkoutMetadata to protocol | WP01 | P0 | Yes |
| T002 | Implement updateWorkoutMetadata | WP01 | P0 | Yes |
| T003 | Create SetTableDataSource protocol | WP01 | P0 | Yes |
| T004 | Refactor SetTableView to protocol | WP02 | P0 | Yes |
| T005 | Refactor SetRowWrapper to protocol | WP02 | P0 | No |
| T006 | Refactor ExerciseTabStripView to protocol | WP02 | P0 | Yes |
| T007 | Conform ActiveWorkoutViewModel | WP02 | P0 | Yes |
| T008 | Update ActiveWorkoutView call sites | WP02 | P0 | No |
| T009 | Build verification | WP02 | P0 | No |
| T010 | Create EditWorkoutViewModel skeleton | WP03 | P1 | No |
| T011 | Implement loadWorkout | WP03 | P1 | No |
| T012 | Implement completeSet (edit vs save) | WP03 | P1 | No |
| T013 | Implement addSet/addWarmupSet | WP03 | P1 | No |
| T014 | Implement deleteSet | WP03 | P1 | No |
| T015 | Implement addExercises | WP04 | P2 | No |
| T016 | Implement removeExercise | WP04 | P2 | No |
| T017 | Implement reorderExercises | WP04 | P2 | No |
| T018 | Implement saveNotes | WP04 | P2 | No |
| T019 | Verify SetTableDataSource conformance | WP04 | P2 | No |
| T020 | Create EditWorkoutView header bar | WP05 | P1 | Yes |
| T021 | Integrate tab strip + set table | WP05 | P1 | No |
| T022 | Add notes TextEditor section | WP05 | P1 | No |
| T023 | Add exercise picker sheet | WP05 | P1 | No |
| T024 | Add loading/empty states | WP05 | P1 | No |
| T025 | Wire up WorkoutDetailFromHomeView | WP05 | P1 | Yes |
| T026 | Add data reload on edit dismiss | WP05 | P1 | No |
