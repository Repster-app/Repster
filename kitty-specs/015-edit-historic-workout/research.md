# Research: Edit Historic Workout

**Feature**: 015-edit-historic-workout
**Date**: 2026-03-02

## Research Questions & Findings

### R1: How to decouple SetTableView and ExerciseTabStripView from ActiveWorkoutViewModel?

**Decision**: Define a `SetTableDataSource` protocol containing the shared interface.

**Rationale**: Both views currently take `var viewModel: ActiveWorkoutViewModel` directly. The exact interface used by these views has been mapped:

SetTableView uses:
- `currentExercise: Exercise?` (read)
- `currentSets: [WorkoutSet]` (read)
- `addSet(for: UUID) async`
- `addWarmupSet(for: UUID) async`
- `completeSet(_:weight:reps:durationSeconds:distanceMeters:) async`
- `deleteSet(_:) async`
- `changeSetType(_:to:) async`

ExerciseTabStripView uses:
- `exercises: [Exercise]` (read)
- `selectedExerciseIndex: Int` (read/write)
- `reorderExercises(from:to:)` (sync)
- `removeExercise(at:) async`

All of these can be expressed as a single protocol. Both ViewModels already implement (or will implement) these methods.

**Alternatives considered**:
- Closure-based: More flexible but verbose (7+ closures to pass through SetTableView + SetRowWrapper). Rejected for readability.
- View duplication: Zero risk to existing code but doubles maintenance. Rejected for maintainability.

### R2: How should EditWorkoutViewModel distinguish existing sets from newly added sets?

**Decision**: Maintain a `Set<UUID>` called `newSetIds` in the ViewModel.

**Rationale**: When the user taps the checkbox on a set:
- If `newSetIds.contains(set.id)` → call `setService.save(set)` (new set pipeline)
- Otherwise → call `setService.edit(set)` (edit pipeline with old-value delta)

This distinction matters because `SetService.edit()` fetches old values from the database for delta computation, while `SetService.save()` creates fresh records. A newly added set has no old values in the database yet (it was just persisted as an empty shell).

**Alternatives considered**:
- Check `set.completed` flag: Unreliable since existing sets are already completed.
- Always use `save()`: Would break stats delta tracking for existing set edits.

### R3: How to persist workout notes?

**Decision**: Add `updateWorkoutMetadata(_:notes:perceivedEffort:)` to `WorkoutServiceProtocol`.

**Rationale**: The current protocol has no method to update a completed workout's metadata. `finishWorkout()` sets notes/perceivedEffort but also changes status to .completed and sets endTime — inappropriate for editing.

Implementation is minimal: fetch workout by ID, update notes + updatedAt, save via repository. Notes are saved when the edit view dismisses (not on every keystroke).

**Alternatives considered**:
- Reuse `finishWorkout()`: Would reset endTime and duration. Rejected.
- Direct repository access from ViewModel: Violates constitution (layer skipping). Rejected.

### R4: What happens to existing SetRowView and SetRowWrapper during the protocol refactor?

**Decision**: SetRowView needs zero changes. SetRowWrapper changes only its ViewModel parameter type.

**Rationale**:
- `SetRowView` already accepts bindings and closures (`onComplete`, `onDelete`, `onChangeSetType`). It has no ViewModel dependency.
- `SetRowWrapper` owns `@State` text bindings and delegates to the ViewModel via closures. It needs to change from `var viewModel: ActiveWorkoutViewModel` to `var dataSource: any SetTableDataSource`. The closure bodies (`viewModel.completeSet(...)` → `dataSource.completeSet(...)`) are identical.

### R5: How should the edit view header differ from the active workout header?

**Decision**: Simplified header with back/done button, "Edit Workout" title, and +Exercise button. No elapsed timer, no rest timer, no Finish button.

**Rationale**: The active workout header has features irrelevant to editing (elapsed timer, rest timer, finish flow). The edit view is a focused editing experience. The header should provide:
- Dismiss mechanism (back/done button)
- Title for context
- Ability to add exercises (+Exercise button)

No summary sheet needed on dismiss since changes are already persisted.
