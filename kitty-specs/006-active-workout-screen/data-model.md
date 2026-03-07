# Data Model: Active Workout Screen (006)

**Date**: 2026-02-24
**Feature**: 006-active-workout-screen

## Overview

This feature creates NO new SwiftData models. All entities exist from features 001–005. This document maps how existing models are consumed by the active workout screen's View and ViewModel layers.

## Entity Usage Map

### Workout (read + write via WorkoutService)

| Field | UI Usage | Write Trigger |
|-------|----------|---------------|
| `id` | Internal reference | `startWorkout()` |
| `date` | Summary sheet header | `startWorkout()` |
| `startTime` | Elapsed timer calculation | `startWorkout()` |
| `endTime` | Summary sheet duration calc | `finishWorkout()` |
| `duration` | Summary sheet display | `finishWorkout()` |
| `perceivedEffort` | RPE selector on summary sheet | `finishWorkout()` |
| `notes` | Notes field on summary sheet | `finishWorkout()` |
| `status` | Resume detection (`.inProgress`) | `startWorkout()` / `finishWorkout()` |

### WorkoutSet (read + write via SetService)

| Field | UI Usage | Write Trigger |
|-------|----------|---------------|
| `id` | Internal reference | `save()` |
| `workoutId` | Filter sets for this workout | `save()` |
| `exerciseId` | Group sets by exercise tab | `save()` |
| `weight` | Weight input field | User input → `completeSet()` |
| `effectiveWeight` | Returned in SetSaveResult | Computed by SetService |
| `reps` | Reps input field | User input → `completeSet()` |
| `durationSeconds` | Duration input (DURATION trackingType) | User input → `completeSet()` |
| `distanceMeters` | Distance input (WEIGHT_DISTANCE) | User input → `completeSet()` |
| `setType` | Set number badge ("W" for warmup) | `addWarmupSet()` / `changeSetType()` |
| `orderInWorkout` | Global ordering | Auto-assigned on creation |
| `orderInExercise` | Order within exercise tab | Auto-assigned, updated on reorder |
| `completed` | Green row tint + green check | Checkbox tap → `completeSet()` |
| `cachedPRStatus` | PR badge (gold) / match badge (blue) | Set by PRService via SetService pipeline |
| `notes` | Set-level notes (long-press → edit) | Future: set edit sheet |

### Exercise (read-only via ExerciseService)

| Field | UI Usage |
|-------|----------|
| `id` | Tab strip key, set grouping key |
| `name` | Tab label, exercise title |
| `trackingType` | Column adaptation (AGENT_RULES S7.5) |
| `defaultRestTime` | Rest timer initial countdown value |
| `equipmentType` | Display context (future) |
| `bodyweightFactor` | Display info (effectiveWeight computed by SetService) |

### ExerciseStats (read-only via StatsService — for summary sheet)

| Field | UI Usage |
|-------|----------|
| `totalSets` | Summary sheet exercise detail |
| `totalVolume` | Summary sheet total volume |
| `maxWeight` | Summary sheet "best lift" per exercise |
| `bestE1RM` | Summary sheet e1RM display |

### PerformanceRecord (not directly accessed)

PR data flows through `cachedPRStatus` on WorkoutSet. The active workout screen never queries PerformanceRecord directly. PRService handles all PR logic at write-time.

## View-Model State Mapping

```
ActiveWorkoutViewModel
│
├── workout: Workout?
│   └── Source: WorkoutService.getActiveWorkout() or startWorkout()
│
├── exercises: [Exercise]
│   └── Source: ExerciseService.fetchExercise() for each exercise in workout
│   └── Order: Maintained locally, persisted via orderInExercise on sets
│
├── setsByExercise: [UUID: [WorkoutSet]]
│   └── Source: SetService (fetched by workoutId, grouped by exerciseId)
│   └── Updated: After every save/delete/edit operation
│
├── selectedExerciseIndex: Int
│   └── Source: User tab selection
│
├── restTimer: RestTimerState
│   └── Source: Auto-started after completeSet(), driven by Timer.publish
│   └── Initial value: exercise.defaultRestTime
│
└── elapsedTime: TimeInterval
    └── Source: Date().timeIntervalSince(workout.startTime), updated every second
```

## Data Flow Sequences

### Set Completion Flow

```
1. User enters weight + reps in input fields
2. User taps completion checkbox
3. VM creates/updates WorkoutSet with input values
4. VM calls SetService.save(set)
5. SetService:
   a. Computes effectiveWeight (weight + bodyweight × bodyweightFactor)
   b. Persists set to SwiftData
   c. Calls PRService.evaluate() → returns PREvaluationResult
   d. Calls StatsService.updateStats() → incremental update
   e. Returns SetSaveResult { setId, effectiveWeight, prResult }
6. VM updates local set with:
   - effectiveWeight from result
   - cachedPRStatus from prResult.newStatus
   - completed = true
7. VM starts rest timer from exercise.defaultRestTime
8. View re-renders:
   - Row turns green (completed tint)
   - Set badge shows green checkmark
   - PR badge appears if prResult.newStatus == .current
   - Match badge appears if prResult.newStatus == .matched
   - Rest timer countdown begins
```

### Finish Workout Flow

```
1. User taps "Finish Workout"
2. VM sets showFinishSheet = true
3. WorkoutSummarySheet computes from local state:
   - Total sets: count all sets where hasData == true
   - Total volume: sum (effectiveWeight × reps) for all completed sets
   - Per-exercise: set count + best weight
   - PRs hit: count sets where cachedPRStatus == .current
4. User enters optional notes + selects RPE (1–10)
5. User taps "Save & Close"
6. VM calls WorkoutService.finishWorkout(workoutId):
   - Sets status = .completed
   - Sets endTime = Date()
   - Computes duration = endTime - startTime
   - Saves notes + perceivedEffort if provided
7. VM dismisses sheet
8. Navigation returns to Calendar tab
```
