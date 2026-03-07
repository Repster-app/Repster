# View Contracts: Edit Historic Workout

**Feature**: 015-edit-historic-workout
**Date**: 2026-03-02

## Protocol: SetTableDataSource

**File**: `Reppo/Features/Workout/Protocols/SetTableDataSource.swift`

The shared protocol that both `ActiveWorkoutViewModel` and `EditWorkoutViewModel` must conform to. Consumed by `SetTableView`, `SetRowWrapper`, and `ExerciseTabStripView`.

### Properties

| Property | Type | Access | Used By |
|----------|------|--------|---------|
| `exercises` | `[Exercise]` | get | ExerciseTabStripView |
| `selectedExerciseIndex` | `Int` | get/set | ExerciseTabStripView, SetTableView (indirectly) |
| `currentExercise` | `Exercise?` | get (computed) | SetTableView |
| `currentSets` | `[WorkoutSet]` | get (computed) | SetTableView |

### Methods

| Method | Signature | Async | Used By |
|--------|-----------|-------|---------|
| `completeSet` | `(_ set: WorkoutSet, weight: Double?, reps: Int?, durationSeconds: Int?, distanceMeters: Double?)` | Yes | SetRowWrapper |
| `addSet` | `(for exerciseId: UUID)` | Yes | SetTableView |
| `addWarmupSet` | `(for exerciseId: UUID)` | Yes | SetTableView |
| `deleteSet` | `(_ set: WorkoutSet)` | Yes | SetRowWrapper |
| `changeSetType` | `(_ set: WorkoutSet, to type: SetType)` | Yes | SetRowWrapper |
| `reorderExercises` | `(from source: IndexSet, to destination: Int)` | No | ExerciseTabStripView |
| `removeExercise` | `(at index: Int)` | Yes | ExerciseTabStripView |

### Conformance Notes

- Protocol must be `@MainActor` (both ViewModels are `@MainActor`)
- Protocol must require `AnyObject` (reference types only, for `var dataSource` in views)
- Protocol must require `Observable` (views need to observe changes)
- `currentExercise` and `currentSets` are computed from `exercises`, `selectedExerciseIndex`, and `setsByExercise` — the protocol exposes them as read-only getters

## View: EditWorkoutView

**File**: `Reppo/Features/Workout/Views/EditWorkoutView.swift`

### Init Parameters

| Parameter | Type | Source |
|-----------|------|--------|
| `workoutId` | `UUID` | From WorkoutDetailFromHomeView |
| `services` | `ServiceContainer` | From SwiftUI environment |

### Layout Contract

```
┌──────────────────────────────────┐
│  [←Done]   Edit Workout   [+Ex] │  ← Header bar
├──────────────────────────────────┤
│  [Bench Press] [Squat] [Row]    │  ← ExerciseTabStripView(dataSource:)
├──────────────────────────────────┤
│  SET  KG      REPS    PR   ✓    │  ← SetTableView(dataSource:)
│  1    80      6       ⭐PR  ☑   │
│  2    80      6       =    ☑   │
│  3    60      8            ☑   │
│  [+ Add Set] [+ Add Warmup]    │
├──────────────────────────────────┤
│  Notes                          │  ← TextEditor
│  [workout notes text...]        │
└──────────────────────────────────┘
```

### State Properties

| Property | Type | Purpose |
|----------|------|---------|
| `viewModel` | `EditWorkoutViewModel` | @State, created in init |
| `dismiss` | `DismissAction` | @Environment, for back button |

### Lifecycle

| Event | Action |
|-------|--------|
| `.task` | `viewModel.loadWorkout()` |
| Back/Done tap | `viewModel.saveNotes()` then `dismiss()` |
| `showAddExerciseSheet` | Present ExerciseListView in `.addToWorkout` mode |

## View: EditWorkoutViewModel

**File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift`

### Dependencies (injected via init)

| Dependency | Protocol | Used For |
|------------|----------|----------|
| `workoutService` | `WorkoutServiceProtocol` | Fetch workout, update notes |
| `setService` | `SetServiceProtocol` | Save, edit, delete sets |
| `exerciseService` | `ExerciseServiceProtocol` | Fetch exercises |
| `statsService` | `StatsServiceProtocol` | Fetch exercise stats (for PR badge context) |

### Published State

| Property | Type | Default |
|----------|------|---------|
| `workout` | `Workout?` | nil |
| `exercises` | `[Exercise]` | [] |
| `selectedExerciseIndex` | `Int` | 0 |
| `setsByExercise` | `[UUID: [WorkoutSet]]` | [:] |
| `notesText` | `String` | "" |
| `isLoading` | `Bool` | true |
| `showAddExerciseSheet` | `Bool` | false |
| `editCompleted` | `Bool` | false |

### Internal Tracking

| Property | Type | Purpose |
|----------|------|---------|
| `newSetIds` | `Set<UUID>` | IDs of sets added during this edit session. Used to choose `save()` vs `edit()` in `completeSet`. |

## Modified View: WorkoutDetailFromHomeView

**File**: `Reppo/Features/Home/Views/WorkoutDetailFromHomeView.swift`

### New State

| Property | Type | Purpose |
|----------|------|---------|
| `showEditWorkout` | `Bool` | Controls fullScreenCover presentation |

### New Environment

| Property | Type | Purpose |
|----------|------|---------|
| `services` | `ServiceContainer` | Passed to EditWorkoutView |

### Changes

1. Remove `.disabled(true)` from "Edit Workout" button
2. Button action: `showEditWorkout = true`
3. Add `.fullScreenCover(isPresented: $showEditWorkout)` presenting `EditWorkoutView`
4. Add `.onChange(of: showEditWorkout)` to reload data when edit dismisses

## Modified Service: WorkoutServiceProtocol

**File**: `Reppo/Core/Services/Protocols/WorkoutServiceProtocol.swift`

### New Method

```
func updateWorkoutMetadata(_ workoutId: UUID, notes: String?, perceivedEffort: Double?) async throws
```

Fetches workout by ID, updates notes/perceivedEffort/updatedAt, saves via repository. Throws `WorkoutServiceError.workoutNotFound` if workout doesn't exist.
