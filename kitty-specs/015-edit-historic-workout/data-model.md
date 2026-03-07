# Data Model: Edit Historic Workout

**Feature**: 015-edit-historic-workout
**Date**: 2026-03-02

## Existing Entities (No Schema Changes)

This feature does **not** add, remove, or modify any SwiftData `@Model` classes. All data operations use existing entities and their existing fields.

### Workout (`Reppo/Data/Models/Workout.swift`)

Fields used by this feature:
- `id: UUID` — identifies the workout to edit
- `notes: String?` — editable metadata (FR-009)
- `perceivedEffort: Double?` — not editable in this version (see Assumptions in spec)
- `status: WorkoutStatus` — always `.completed` for historic workouts; not modified by editing
- `updatedAt: Date` — updated when notes are saved via `updateWorkoutMetadata()`

### WorkoutSet (`Reppo/Data/Models/WorkoutSet.swift`)

Fields used by this feature:
- `id: UUID` — identity
- `workoutId: UUID` — links set to the workout being edited
- `exerciseId: UUID` — links set to its exercise
- `weight: Double?` — editable (FR-004)
- `effectiveWeight: Double?` — recomputed by SetService on edit
- `reps: Int?` — editable (FR-004)
- `durationSeconds: Int?` — editable (for duration-tracked exercises)
- `distanceMeters: Double?` — editable (for distance-tracked exercises)
- `setType: SetType` — changeable via context menu (warmup, working, dropset, etc.)
- `completed: Bool` — set to true when user confirms via checkbox
- `cachedPRStatus: CachedPRStatus?` — updated by PRService after edit
- `orderInWorkout: Int` — maintained when adding/deleting sets
- `orderInExercise: Int` — reindexed when sets are added/deleted/reordered
- `updatedAt: Date` — updated on edit

### Exercise (`Reppo/Data/Models/Exercise.swift`)

Fields used by this feature:
- `id: UUID` — used to add/remove exercises from workout
- `name: String` — displayed in exercise tab strip
- `trackingType: TrackingType` — determines which columns show in set table (weight+reps, duration, etc.)
- `equipmentType: EquipmentType` — displayed in exercise cards

## Service Layer Changes

### WorkoutServiceProtocol — New Method

```
updateWorkoutMetadata(workoutId: UUID, notes: String?, perceivedEffort: Double?) → void
```

Fetches workout by ID, updates `notes`, `perceivedEffort`, and `updatedAt` fields, saves via WorkoutRepository. No cascade effects (sets are unaffected).

## State Transitions

### Workout Lifecycle During Edit

```
[completed] → Edit View opens → [completed, content being edited]
           → Sets modified (immediate persist)
           → Edit View dismisses → [completed, updatedAt refreshed]
```

The workout status never changes during editing. It remains `.completed` throughout.

### WorkoutSet Lifecycle During Edit

```
Existing set:
[completed, has values] → user changes values → taps checkbox
  → SetService.edit() → [completed, new values, PR re-evaluated]

New set added:
[not created yet] → "+ Add Set" → SetService.save(empty) → [persisted, incomplete]
  → user fills values → taps checkbox
  → SetService.save(with values) → [completed, values, PR evaluated]

Deleted set:
[completed] → context menu "Delete" → SetService.delete() → [hard deleted]
```
