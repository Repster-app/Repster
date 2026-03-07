# Data Model: Workout + Exercise + Bodyweight Services

**Feature**: 005-workout-exercise-bodyweight-services
**Date**: 2026-02-24

## Entity Interaction Map

```
┌──────────────┐     ┌──────────────────┐     ┌───────────────────┐
│WorkoutService│     │ ExerciseService  │     │BodyweightService  │
└──────┬───────┘     └────────┬─────────┘     └─────────┬─────────┘
       │                      │                         │
       │ uses                 │ uses                    │ uses
       ▼                      ▼                         ▼
┌──────────────┐     ┌──────────────────┐     ┌───────────────────┐
│WorkoutRepo   │     │ ExerciseRepo     │     │BodyweightEntryRepo│
│SetRepo       │     │ SetRepo          │     │HealthProfileRepo  │
│PRService     │     │ PRService        │     └───────────────────┘
│StatsService  │     │ StatsService     │
└──────────────┘     └──────────────────┘
```

## Services — No New Models

Feature 005 introduces **zero new SwiftData models**. All entities already exist from features 001-002:

| Entity | Created In | Used By (005) |
|--------|-----------|--------------|
| `Workout` | 001 | WorkoutService (CRUD, status management) |
| `WorkoutSet` | 001 | WorkoutService (cascade delete), ExerciseService (cascade delete) |
| `Exercise` | 001 | ExerciseService (CRUD, mutability enforcement) |
| `BodyweightEntry` | 001 | BodyweightService (CRUD, closest lookup) |
| `HealthProfile` | 001 | BodyweightService (healthProfileId for entries) |
| `ExerciseStats` | 001 | ExerciseService (rebuild trigger), WorkoutService (rebuild trigger) |
| `PerformanceRecord` | 001 | ExerciseService (rebuild trigger), WorkoutService (rebuild trigger) |

## New Value Types

### WorkoutServiceError

```swift
enum WorkoutServiceError: Error {
    case workoutNotFound(UUID)
    case workoutAlreadyCompleted(UUID)
}
```

### ExerciseServiceError

```swift
enum ExerciseServiceError: Error {
    case exerciseNotFound(UUID)
    case trackingTypeImmutable(exerciseId: UUID)
}
```

### BodyweightServiceError

```swift
enum BodyweightServiceError: Error {
    case entryNotFound(UUID)
}
```

## Workflow: Workout Lifecycle

```
startWorkout()
  │
  ├─ fetchInProgress() → exists? → return existing (no duplicate)
  │
  └─ create Workout(status: .inProgress, startTime: now, date: today)
     │
     ├─ [User adds sets via SetService — outside WorkoutService scope]
     │
     └─ finishWorkout(workoutId)
        │
        ├─ workout.status = .completed
        ├─ workout.endTime = now
        └─ workout.duration = endTime - startTime (seconds)
```

## Workflow: Workout Deletion (Cascade)

```
deleteWorkout(workoutId)
  │
  ├─ 1. Fetch affected exerciseIds from sets in this workout
  │     setRepo.fetchExerciseIds(for: workoutId) → Set<UUID>
  │
  ├─ 2. Bulk delete all sets for this workout
  │     setRepo.deleteSets(for: workoutId)
  │
  ├─ 3. Delete the workout itself
  │     workoutRepo.delete(workout)
  │
  └─ 4. Rebuild PRs + stats for each affected exercise
        for exerciseId in affectedExerciseIds:
          prService.rebuild(for: exerciseId)
          statsService.rebuild(for: exerciseId)
```

## Workflow: Exercise Edit (Mutability Enforcement)

```
updateExercise(exercise, changes)
  │
  ├─ hasSets = exerciseRepo.hasAssociatedSets(exerciseId)
  │
  ├─ if hasSets AND trackingType changed:
  │     throw ExerciseServiceError.trackingTypeImmutable
  │
  ├─ Apply allowed changes
  │
  ├─ if hasSets AND rebuild-required field changed:
  │     (bodyweightFactor, unilateral, bilateralLoadFactor, equipmentType)
  │     prService.rebuild(for: exerciseId)
  │     statsService.rebuild(for: exerciseId)
  │
  └─ exerciseRepo.save(exercise)
```

## Workflow: Exercise Deletion (Cascade)

```
deleteExercise(exerciseId)
  │
  ├─ 1. Bulk delete all sets for this exercise
  │     setRepo.deleteSets(forExercise: exerciseId)
  │
  ├─ 2. Delete ExerciseStats
  │     exerciseStatsRepo.delete(stats) [if exists]
  │
  ├─ 3. Delete all PerformanceRecords
  │     performanceRecordRepo.deleteAll(for: exerciseId)
  │
  └─ 4. Delete the exercise itself
        exerciseRepo.delete(exercise)
```

Note: No rebuild needed on exercise deletion — we're deleting everything. The stats/PRs for other exercises are unaffected.

## Workflow: Bodyweight Service

```
saveEntry(bodyweightKg, date)
  │
  ├─ profile = healthProfileRepo.fetchOrCreate()
  └─ entry = BodyweightEntry(healthProfileId: profile.id, date, bodyweightKg)
     bodyweightEntryRepo.save(entry)

closestBodyweight(to date)
  │
  ├─ profile = healthProfileRepo.fetchOrCreate()
  └─ bodyweightEntryRepo.fetchClosest(to: date, healthProfileId: profile.id)
```

## Repository Additions Needed

### SetRepositoryProtocol (3 new methods)

```swift
/// Bulk delete all sets for a workout. Used by WorkoutService cascade deletion.
func deleteSets(for workoutId: UUID) async throws

/// Bulk delete all sets for an exercise. Used by ExerciseService cascade deletion.
func deleteSets(forExercise exerciseId: UUID) async throws

/// Fetch unique exerciseIds for sets in a workout. Used before cascade deletion
/// to know which exercises need PRService/StatsService rebuild.
func fetchExerciseIds(for workoutId: UUID) async throws -> Swift.Set<UUID>
```

### PerformanceRecordRepositoryProtocol (1 new method)

```swift
/// Delete all PerformanceRecords for an exercise. Used by ExerciseService cascade deletion.
func deleteAll(for exerciseId: UUID) async throws
```

### BodyweightEntryRepositoryProtocol (1 new method)

```swift
/// Fetch a single bodyweight entry by ID. Used by BodyweightService for update/delete.
func fetch(byId id: UUID) async throws -> BodyweightEntry?
```
