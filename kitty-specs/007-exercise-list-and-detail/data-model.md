# Data Model: Exercise List + Detail

**Feature**: 007-exercise-list-and-detail
**Date**: 2026-02-25

## Existing Entities (No Changes Required)

Feature 007 is a **UI-only feature**. All SwiftData models, services, and repositories are already implemented. This document catalogs the existing entities and their relationships relevant to this feature.

### Exercise (existing — `Reppo/Data/Models/Exercise.swift`)

| Field | Type | Nullable | Used By |
|-------|------|----------|---------|
| `id` | UUID | No | All views — primary key |
| `name` | String | No | Exercise card, list search, detail header |
| `equipmentType` | EquipmentType | No | Exercise card display |
| `trackingType` | TrackingType | No | Exercise card, Create/Edit form (locked when sets exist) |
| `primaryMuscle` | String? | Yes | Exercise card, filter pills |
| `secondaryMuscles` | [String] | Yes | Create/Edit form |
| `movementPattern` | MovementPattern? | Yes | Create/Edit form |
| `unilateral` | Bool | No | Create/Edit form |
| `bilateralLoadFactor` | Double? | Yes | Create/Edit form |
| `bodyweightFactor` | Double | No | Create/Edit form |
| `weightIncrement` | Double? | Yes | Create/Edit form |
| `defaultRestTime` | Int? | Yes | Create/Edit form |
| `createdAt` | Date | No | Internal |
| `updatedAt` | Date | No | Internal |

**Relationships**: One-to-many with `WorkoutSet` (via `exerciseId` on WorkoutSet).

### ExerciseStats (existing — `Reppo/Data/Models/ExerciseStats.swift`)

| Field | Type | Used By |
|-------|------|---------|
| `exerciseId` | UUID | Join key to Exercise |
| `totalWorkouts` | Int | Sort by "most used" |
| `totalSets` | Int | Detail stats display |
| `totalReps` | Int | Detail stats display |
| `totalVolume` | Double | Detail stats display |
| `maxWeight` | Double | Exercise card "best lift" |
| `bestE1RM` | Double | Exercise card alternate "best lift" |
| `averageIntensity` | Double | Detail stats display |
| `estimated1RMTrendSlope` | Double | Trend indicator |
| `lastPRDate` | Date? | Detail stats display |
| `lastPerformedDate` | Date? | Exercise card "last performed", sort by "most recent" |
| `maxSessionVolume` | Double | Detail stats display |

**Note**: ExerciseStats is pre-computed at write-time (per constitution). Feature 007 **reads only** — never writes to ExerciseStats.

### PerformanceRecord (existing — `Reppo/Data/Models/PerformanceRecord.swift`)

| Field | Type | Used By |
|-------|------|---------|
| `exerciseId` | UUID | Join key |
| `recordType` | RecordType | Filter for `.repMax` in PR table |
| `reps` | Int? | PR table row |
| `value` | Double | PR table row (weight in kg) |
| `setId` | UUID | Reference to owning set |
| `date` | Date | PR table row |

**Used by**: `ExercisePRsView` via `PRService.fetchPRTable(for:)` which applies suffix-max filtering.

### WorkoutSet (existing — `Reppo/Data/Models/WorkoutSet.swift`)

Relevant fields for Feature 007 views:

| Field | Type | Used By |
|-------|------|---------|
| `exerciseId` | UUID | History tab — group by exercise |
| `workoutId` | UUID | History tab — group by workout |
| `weight` | Double? | History display |
| `effectiveWeight` | Double | Charts (volume calculation) |
| `reps` | Int? | History display |
| `e1RM` | Double? | Charts (e1RM trend) |
| `date` | Date | History display, charts x-axis |
| `setType` | SetType | History display (warmup indicator) |
| `cachedPRStatus` | CachedPRStatus? | History display (PR badges) |
| `completed` | Bool | History display |

### Workout (existing — `Reppo/Data/Models/Workout.swift`)

| Field | Type | Used By |
|-------|------|---------|
| `id` | UUID | History tab — workout header |
| `date` | Date | History tab — session date |
| `status` | WorkoutStatus | Active workout detection |
| `notes` | String? | History tab — session context |

## New Types (View-Layer Only)

These are **not** SwiftData models. They are lightweight enums and structs for the View/ViewModel layer.

### ExerciseListMode (new enum)

```swift
enum ExerciseListMode {
    case browse          // FAB → Exercise List, tap = push detail
    case addToWorkout    // Active Workout → +Exercise, tap = toggle selection
}
```

### ExerciseListSortOrder (new enum)

```swift
enum ExerciseListSortOrder: String, CaseIterable {
    case alphabetical = "A-Z"
    case mostRecent = "Most Recent"
    case mostUsed = "Most Used"
}
```

### ExerciseSubTab (new enum)

```swift
enum ExerciseSubTab: String, CaseIterable {
    case sets = "Sets"
    case history = "History"
    case charts = "Charts"
}
```

### ExerciseDetailTab (new enum)

```swift
enum ExerciseDetailTab: String, CaseIterable {
    case history = "History"
    case prs = "PRs"
    case charts = "Charts"
}
```

### MainTab (new enum — for tab bar)

```swift
enum MainTab: Int, CaseIterable {
    case programs = 0
    case calendar = 1
    case charts = 2
    case settings = 3
}
```

Note: FAB is not a tab — it's an overlay button. The tab bar has 4 real tabs with the FAB centered on top.

## Existing Service APIs Used (Read-Only)

### ExerciseService

| Method | Returns | Used By |
|--------|---------|---------|
| `fetchAllExercises()` | `[Exercise]` | ExerciseListViewModel — initial load |
| `searchExercises(name:)` | `[Exercise]` | ExerciseListViewModel — search |
| `createExercise(_:)` | `void` | CreateEditExerciseViewModel — create |
| `updateExercise(_:originalTrackingType:)` | `void` | CreateEditExerciseViewModel — edit |
| `deleteExercise(_:)` | `void` | ExerciseDetailViewModel — delete action |
| `exerciseHasSets(_:)` | `Bool` | CreateEditExerciseViewModel — lock trackingType |
| `fetchExercise(_:)` | `Exercise?` | ExerciseDetailViewModel — load single exercise |

### PRService

| Method | Returns | Used By |
|--------|---------|---------|
| `fetchPRTable(for:)` | `[PRTableEntry]` | ExercisePRsView — suffix-max filtered PR table |

### StatsService / ExerciseStatsRepository

| Method | Returns | Used By |
|--------|---------|---------|
| `fetchStats(for:)` | `ExerciseStats?` | ExerciseListViewModel — card stats, sort data |

### SetRepository

| Method | Returns | Used By |
|--------|---------|---------|
| `fetchSets(for exerciseId:, limit:)` | `[WorkoutSet]` | ExerciseHistoryView — past sessions |
| `fetchBestE1RM(for:)` | `Double?` | ExerciseChartsView — e1RM trend data |

### WorkoutService

| Method | Returns | Used By |
|--------|---------|---------|
| `getActiveWorkout()` | `Workout?` | ContentView — resume active workout on launch |

## Entity Relationship Diagram

```
┌─────────────┐      1:N      ┌──────────────┐
│  Exercise    │──────────────▶│  WorkoutSet   │
│  (metadata)  │               │  (raw data)   │
└──────┬───────┘               └───────────────┘
       │                              │
       │ 1:1                          │ N:1
       ▼                              ▼
┌──────────────┐               ┌──────────────┐
│ ExerciseStats│               │   Workout    │
│ (pre-computed)│              │  (session)   │
└──────────────┘               └──────────────┘
       │
       │ 1:N
       ▼
┌───────────────────┐
│ PerformanceRecord │
│ (PR cache)        │
└───────────────────┘
```

All relationships are via UUID foreign keys (not SwiftData relationship macros), per existing codebase conventions.
