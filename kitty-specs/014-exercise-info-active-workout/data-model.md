# Data Model: Exercise Info in Active Workout

**Feature**: 014-exercise-info-active-workout
**Date**: 2026-03-01

> No new SwiftData `@Model` classes are introduced. All models below are transient Swift structs used for view display only. Data is sourced from existing `WorkoutSet`, `ExerciseStats`, `Exercise`, and `HealthProfile` models.

## New Entities

### ExerciseInfoData

**Type**: `struct` (value type, `Sendable`)
**Purpose**: Holds all computed data for the Exercise Info section, ready for view consumption.
**Lifecycle**: Computed on exercise selection, cached in ViewModel, cleared on exercise switch.

| Property | Type | Description |
|----------|------|-------------|
| `e1RMInfo` | `E1RMInfo?` | Estimated 1RM card data. `nil` when trackingType doesn't support weight/reps. |
| `lastWorkoutInfo` | `LastWorkoutInfo?` | Last workout card data. `nil` when no previous session exists. |
| `estimatedRepsInfo` | `EstimatedRepsInfo?` | Estimated weight for N reps card data. `nil` when insufficient history or non-weight tracking. |
| `trackingType` | `TrackingType` | Determines which cards are visible. |

### E1RMInfo

**Type**: `struct` (value type)
**Purpose**: Data for the hero e1RM card.

| Property | Type | Description |
|----------|------|-------------|
| `currentE1RM` | `Double` | Today's best estimated 1RM (kg). From best working set's `e1RM` in current session. |
| `bestSetWeight` | `Double` | Weight of today's best set (kg, `effectiveWeight`). |
| `bestSetReps` | `Int` | Reps of today's best set. |
| `historicalE1RM` | `Double?` | e1RM from ~4 weeks ago for comparison. `nil` if no history. |
| `historicalWeeksAgo` | `Int?` | Actual weeks ago the comparison point is from (e.g., 4). |
| `delta` | `Double?` | `currentE1RM - historicalE1RM` in kg. Positive = improvement. `nil` if no history. |
| `trend` | `Trend?` | `.positive`, `.negative`, or `.neutral` based on delta. |

### LastWorkoutInfo

**Type**: `struct` (value type)
**Purpose**: Data for the compact Last Workout card.

| Property | Type | Description |
|----------|------|-------------|
| `topSets` | `[TopSet]` | Top 2 working sets from last session, sorted by effectiveWeight desc. |
| `daysAgo` | `Int` | How many days since the last session. |
| `relativeTimeLabel` | `String` | Formatted string (e.g., "9 days ago"). |

### TopSet

**Type**: `struct` (value type)
**Purpose**: A single set summary for display.

| Property | Type | Description |
|----------|------|-------------|
| `weight` | `Double` | `effectiveWeight` in kg. |
| `reps` | `Int?` | Rep count (nil for duration-based). |
| `durationSeconds` | `Int?` | Duration in seconds (for duration-based exercises). |
| `formattedLabel` | `String` | Pre-formatted display string (e.g., "85×8" or "2:30"). |

### EstimatedRepsInfo

**Type**: `struct` (value type)
**Purpose**: Data for the compact Est. for N reps card.

| Property | Type | Description |
|----------|------|-------------|
| `targetReps` | `Int` | The rep count being estimated for (from user's most recent working set). |
| `estimatedWeight` | `Double` | Reverse-calculated weight in kg for the target reps. |
| `sourceLabel` | `String` | Always "Based on recent data". |

### Trend (enum)

**Type**: `enum` (String-backed)
**Purpose**: Direction of e1RM change for color coding.

| Case | Color Token | Display |
|------|------------|---------|
| `.positive` | `Color.success` | "+X.X kg" (green) |
| `.negative` | `Color.danger` | "−X.X kg" (red) |
| `.neutral` | `Color.textSecondary` | "0.0 kg" (gray) |

## Existing Entities Referenced (Read-Only)

### WorkoutSet (existing `@Model`)

| Property Used | Type | How Used |
|---------------|------|----------|
| `e1RM` | `Double?` | Pre-computed e1RM value — read directly for today's best and historical comparison |
| `effectiveWeight` | `Double?` | Used for "Best today" display and top set ranking |
| `reps` | `Int?` | Used for "Best today" display and determining target rep count |
| `durationSeconds` | `Int?` | Used for duration-based exercise display |
| `workoutId` | `UUID` | Used to group sets by workout session and exclude current workout |
| `exerciseId` | `UUID` | Used to filter sets for the current exercise |
| `date` | `Date` | Used for historical comparison window and relative time labels |
| `setType` | `SetType` | Used to filter to working sets only (exclude warmups) |
| `hasData` | `Bool` (computed) | Used to exclude empty/unfinished sets from calculations |

### ExerciseStats (existing `@Model`)

| Property Used | Type | How Used |
|---------------|------|----------|
| `bestE1RM` | `Double` | Fallback source for e1RM when no sets completed in current session |

### Exercise (existing `@Model`)

| Property Used | Type | How Used |
|---------------|------|----------|
| `trackingType` | `TrackingType` | Determines which cards are shown/hidden |
| `weightIncrement` | `Double?` | Used to snap estimated weight to practical plate values |

### HealthProfile (existing `@Model`)

| Property Used | Type | How Used |
|---------------|------|----------|
| `e1RMFormula` | `String` | Converted to `E1RMFormula` enum for reverse calculation |
| `unitPreference` | `UnitPreference` | Determines kg vs lbs display in card values |

## Data Flow

```
┌─────────────────────────────┐
│   ActiveWorkoutViewModel    │
│                             │
│  currentSets (in memory)    │──┐
│  workout.id                 │  │
│  currentExercise            │  │
└─────────────────────────────┘  │
                                 │
         ┌───────────────────────┘
         ▼
┌─────────────────────────────┐     ┌─────────────────┐
│   ExerciseInfoProvider      │────▶│  SetService      │
│                             │     │  .fetchSets()    │
│  compute(                   │     └─────────────────┘
│    currentSets,             │
│    exerciseId,              │     ┌─────────────────┐
│    currentWorkoutId,        │────▶│  StatsService    │
│    setService,              │     │  .fetchStats()   │
│    healthProfileRepo        │     └─────────────────┘
│  )                          │
│                             │     ┌─────────────────┐
│  Returns: ExerciseInfoData  │────▶│ HealthProfileRepo│
└─────────────────────────────┘     │  .fetchOrCreate()│
         │                          └─────────────────┘
         ▼
┌─────────────────────────────┐
│   ExerciseInfoSectionView   │
│                             │
│  ├── E1RMCardView           │
│  ├── LastWorkoutCardView    │
│  └── EstimatedRepsCardView  │
└─────────────────────────────┘
```

## Validation Rules

| Rule | Source | Enforcement |
|------|--------|-------------|
| Only working sets with `hasData` count for e1RM "best today" | Constitution: `hasData` for analytics | Filter: `setType == .working && hasData` |
| Historical comparison uses integer grams precision | Constitution: float comparison | `toGrams(current) - toGrams(historical)` then convert back to kg for display |
| Unit conversion at UI boundary only | Constitution: store metric | All `ExerciseInfoData` values in kg; views apply `UnitConversion` |
| e1RM uses user's selected formula | Spec FR-010 | Read `HealthProfile.e1RMFormula` → `E1RMFormula` enum |
| Top sets exclude warmups | Spec: "only working sets shown" | Filter: `setType == .working` |

## State Transitions

```
Exercise Info Loading States:

  ┌─────────┐     loadExerciseInfo()    ┌─────────┐
  │  idle   │ ─────────────────────────▶│ loading │
  └─────────┘                           └────┬────┘
       ▲                                     │
       │          exercise switch             ▼
       │         (clearSubTabCache)    ┌─────────────┐
       └──────────────────────────────│   loaded    │
                                       │ (cached)    │
                                       └─────────────┘

  Cards Visibility by TrackingType:

  weightReps/weightRepsDuration:
    [E1RM Card - full width]
    [Last Workout] [Est. for N reps]

  duration/weightDistance/custom:
    [Last Workout Card - full width]
```
