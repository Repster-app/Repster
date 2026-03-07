# Data Model: 008 Calendar Tab

**Feature**: Calendar Tab
**Date**: 2026-02-27

## Overview

The Calendar Tab introduces **no new SwiftData entities**. It reads from existing entities (`Workout`, `WorkoutSet`, `Exercise`, `ExerciseStats`, `PerformanceRecord`) and derives muscle group data in-memory. This complies with the constitution's "do not invent" rule.

## Entities Used (Read-Only)

### Workout (specdoc S6.2)

| Field | Type | Calendar Usage |
|-------|------|---------------|
| `id` | UUID | Key for fetching sets |
| `date` | Date | Calendar date placement |
| `startTime` | Date? | Display in multi-workout label ("Morning"/"Evening") |
| `status` | WorkoutStatus | Filter: show `.completed` and `.inProgress` |
| `duration` | Int? | Summary stats display |

**Query pattern**: `WorkoutRepository.fetchWorkouts(for: dateRange)` — fetches by visible month range + buffer.

### WorkoutSet (specdoc S6.3)

| Field | Type | Calendar Usage |
|-------|------|---------------|
| `workoutId` | UUID | Link sets to their workout |
| `exerciseId` | UUID | Link to exercise for muscle group + name |
| `weight` | Double? | Display in set rows |
| `effectiveWeight` | Double? | Volume calculation |
| `reps` | Int? | Display in set rows |
| `setType` | SetType | Warmup opacity |
| `cachedPRStatus` | CachedPRStatus? | PR badge display |
| `orderInWorkout` | Int | Ordering |
| `orderInExercise` | Int | Ordering within exercise group |
| `completed` | Bool | Display state |

**Query pattern**: `SetRepository.fetchSets(for: workoutId)` — gets all sets for a workout.

### Exercise (specdoc S6.1)

| Field | Type | Calendar Usage |
|-------|------|---------------|
| `id` | UUID | Lookup key |
| `name` | String | Display in exercise cards |
| `primaryMuscle` | String? | Muscle group dot color derivation |
| `equipmentType` | EquipmentType | Display in exercise cards |

**Query pattern**: `ExerciseService.fetchExercise(_:)` — cached in ViewModel dictionary to avoid redundant fetches.

### ExerciseStats (specdoc S6.4)

| Field | Type | Calendar Usage |
|-------|------|---------------|
| `exerciseId` | UUID | Lookup key |
| `totalVolume` | Double | Summary stats |
| `maxWeight` | Double | Exercise card "best" display |

**Query pattern**: `StatsService.fetchStats(for: exerciseId)` — per exercise in workout detail.

## Derived Data Structures (In-Memory Only)

### CalendarDotData

```swift
/// Maps each date to its muscle group strings for dot rendering.
/// Built from Workout → WorkoutSet → Exercise.primaryMuscle chain.
typealias CalendarDotData = [Date: [String]]
```

**Derivation**:
1. Fetch workouts for visible date range
2. For each workout, fetch exercise IDs via `SetRepository.fetchExerciseIds(for:)`
3. For each exercise ID, look up `Exercise.primaryMuscle` (cached)
4. Collect unique muscle groups per date (merge across multiple workouts on same date)
5. Order by frequency (most sets per muscle group first)

### WorkoutDetailData

```swift
/// Grouped set data for workout detail display.
struct ExerciseGroup {
    let exercise: Exercise
    let sets: [WorkoutSet]     // Ordered by orderInExercise
    let stats: ExerciseStats?  // For "best" display
}

struct WorkoutDetail {
    let workout: Workout
    let exerciseGroups: [ExerciseGroup]  // Ordered by first set's orderInWorkout
    let totalVolume: Double              // Sum of set volumes
    let exerciseCount: Int               // Unique exercises
    let setCount: Int                    // Total completed sets
}
```

**Derivation**: Fetched on-demand when user taps a date. Not pre-loaded.

## Relationships (UUID-Based, No SwiftData @Relationship)

```
Workout.id ←── WorkoutSet.workoutId (1:many)
Exercise.id ←── WorkoutSet.exerciseId (many:1)
Exercise.id ←── ExerciseStats.exerciseId (1:1)
```

All relationships are manual UUID lookups, consistent with the existing codebase pattern.

## Muscle Group Color Mapping

No new model. Static utility function `MuscleGroupColors.color(for:)` maps `Exercise.primaryMuscle` strings to `Color` values. See `research.md` RQ-2 for the full color table.

## No Schema Changes Required

This feature adds:
- **0 new SwiftData @Model classes**
- **0 new database fields**
- **0 new indexes**

All data is read from existing entities using existing repository methods.
