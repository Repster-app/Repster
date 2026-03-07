# Quickstart: Edit Historic Workout

**Feature**: 015-edit-historic-workout
**Date**: 2026-03-02

## Overview

This feature adds the ability to edit completed workouts. It introduces 3 new files and modifies 7 existing files. The core architectural change is a `SetTableDataSource` protocol that decouples SetTableView/ExerciseTabStripView from ActiveWorkoutViewModel, enabling reuse with the new EditWorkoutViewModel.

## Implementation Order

Build in this sequence to maintain a compilable project at each step:

### Step 1: Service Layer Addition

**Files**: `WorkoutServiceProtocol.swift`, `WorkoutService.swift`

Add `updateWorkoutMetadata(_:notes:perceivedEffort:)` to the protocol and implement it. This is isolated — no other code depends on it yet.

### Step 2: Define SetTableDataSource Protocol

**File**: `Reppo/Features/Workout/Protocols/SetTableDataSource.swift` (NEW)

Create the protocol with all properties and methods that SetTableView and ExerciseTabStripView need. This compiles independently.

### Step 3: Refactor SetTableView

**File**: `Reppo/Features/Workout/Views/SetTableView.swift`

Change `var viewModel: ActiveWorkoutViewModel` → `var dataSource: any SetTableDataSource` in both `SetTableView` and `SetRowWrapper`. Update method calls from `viewModel.xxx` to `dataSource.xxx`.

### Step 4: Refactor ExerciseTabStripView

**File**: `Reppo/Features/Workout/Views/ExerciseTabStripView.swift`

Same pattern: change `var viewModel: ActiveWorkoutViewModel` → `var dataSource: any SetTableDataSource`.

### Step 5: Conform ActiveWorkoutViewModel

**File**: `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift`

Add `extension ActiveWorkoutViewModel: SetTableDataSource {}` — all methods already exist with matching signatures.

### Step 6: Update ActiveWorkoutView Call Sites

**File**: `Reppo/Features/Workout/Views/ActiveWorkoutView.swift`

Change `SetTableView(viewModel: viewModel)` → `SetTableView(dataSource: viewModel)` and `ExerciseTabStripView(viewModel: viewModel)` → `ExerciseTabStripView(dataSource: viewModel)`.

**CHECKPOINT**: Build and verify the active workout flow still works identically.

### Step 7: Create EditWorkoutViewModel

**File**: `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift` (NEW)

Implement the `SetTableDataSource` protocol. Key differences from ActiveWorkoutViewModel:
- `loadWorkout(workoutId:)` loads a completed workout (not an in-progress one)
- `completeSet()` uses `setService.edit()` for existing sets, `setService.save()` for new sets (tracked via `newSetIds`)
- `saveNotes()` calls `workoutService.updateWorkoutMetadata()`
- No timer logic, no finish flow, no sub-tabs

### Step 8: Create EditWorkoutView

**File**: `Reppo/Features/Workout/Views/EditWorkoutView.swift` (NEW)

Full-screen cover layout: header bar + ExerciseTabStripView + SetTableView + notes TextEditor. Simplified version of ActiveWorkoutView without timers or sub-tabs.

### Step 9: Wire Up WorkoutDetailFromHomeView

**File**: `Reppo/Features/Home/Views/WorkoutDetailFromHomeView.swift`

Enable the "Edit Workout" button, add `@State showEditWorkout`, present `EditWorkoutView` as `.fullScreenCover`, reload data on dismiss.

## Key Files Reference

| File | Role | Action |
|------|------|--------|
| `Reppo/Features/Workout/Protocols/SetTableDataSource.swift` | Shared protocol | NEW |
| `Reppo/Features/Workout/ViewModels/EditWorkoutViewModel.swift` | Edit state + logic | NEW |
| `Reppo/Features/Workout/Views/EditWorkoutView.swift` | Edit UI | NEW |
| `Reppo/Features/Workout/Views/SetTableView.swift` | Set entry table | MODIFY |
| `Reppo/Features/Workout/Views/ExerciseTabStripView.swift` | Exercise tabs | MODIFY |
| `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` | Conform to protocol | MODIFY |
| `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` | Update call sites | MODIFY |
| `Reppo/Core/Services/Protocols/WorkoutServiceProtocol.swift` | Add method | MODIFY |
| `Reppo/Core/Services/WorkoutService.swift` | Implement method | MODIFY |
| `Reppo/Features/Home/Views/WorkoutDetailFromHomeView.swift` | Wire up entry point | MODIFY |

## Verification Checklist

1. Active workout flow unchanged after protocol refactor (Steps 3-6)
2. Edit screen opens from workout detail toolbar menu
3. Set values pre-populated with existing data
4. Editing a set updates values and PR badges
5. Adding a set creates a new row, persists on checkbox tap
6. Deleting a set removes it, PRs/stats recalculate
7. Adding an exercise via picker works
8. Removing an exercise deletes all its sets
9. Notes save on dismiss
10. Workout detail refreshes after edit dismiss
