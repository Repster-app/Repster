# Data Model: 009 Charts Tab

**Feature**: Charts Tab
**Date**: 2026-02-27

## Overview

The Charts Tab introduces **no new SwiftData entities**. It reads from existing entities (`Workout`, `WorkoutSet`, `Exercise`, `ExerciseStats`, `PerformanceRecord`) and computes chart data in-memory via bounded date-range queries. This complies with the constitution's "do not invent" rule and specdoc S8.10 (lazy compute for v1).

## Entities Used (Read-Only)

### WorkoutSet (specdoc S6.1)

| Field | Type | Charts Usage |
|-------|------|-------------|
| `exerciseId` | UUID | Group by exercise for detail charts |
| `workoutId` | UUID | Group by session for per-session aggregation |
| `date` | Date | Date-range filtering, chart x-axis |
| `effectiveWeight` | Double? | Volume calculation (`effectiveWeight × reps`) |
| `reps` | Int? | Volume calculation, rep-based filtering |
| `e1RM` | Double? | e1RM trend charts, sparkline |
| `setType` | SetType | Exclude warmup/partial per settings |
| `completed` | Bool | Not used — charts use `hasData` |

**Query patterns**:
- Overview weekly volume: `date >= 12 weeks ago AND hasData`
- Overview muscle groups: `date >= 4 weeks ago AND hasData`
- Exercise detail: `exerciseId = ? AND date >= range start AND hasData`
- Sparkline: `exerciseId = ? AND hasData`, sorted by date DESC, limited

### Workout (specdoc S6.2)

| Field | Type | Charts Usage |
|-------|------|-------------|
| `id` | UUID | Key for grouping sets by session |
| `date` | Date | Training frequency chart, date-range filtering |

**Query pattern**: `WorkoutRepository.fetchWorkouts(from: cutoff, to: Date())` — for frequency (sessions per week).

### Exercise (specdoc S6.3)

| Field | Type | Charts Usage |
|-------|------|-------------|
| `id` | UUID | Lookup key |
| `name` | String | Exercise card display, detail screen title |
| `primaryMuscle` | String? | Muscle group distribution chart |

**Query pattern**: Fetched once and cached in `[UUID: Exercise]` dictionary within `ChartDataService`. Exercises change rarely.

### ExerciseStats (specdoc S6.4)

| Field | Type | Charts Usage |
|-------|------|-------------|
| `exerciseId` | UUID | Lookup key |
| `bestE1RM` | Double | Current e1RM value on exercise cards |
| `lastPerformedDate` | Date? | Sort exercise cards by most recent |
| `totalVolume` | Double | Not directly used (overview computes from sets) |

**Query pattern**: `ExerciseStatsRepository.fetchAll()` — sparse table (~200 rows), safe to load entirely for building card list.

### PerformanceRecord (specdoc S6.5)

| Field | Type | Charts Usage |
|-------|------|-------------|
| `exerciseId` | UUID | Filter for exercise detail |
| `recordType` | RecordType | Filter to `repMax` |
| `reps` | Int? | Filter to [1, 3, 5] for PR progression |
| `value` | Double | PR weight values |
| `date` | Date | Time series x-axis |
| `setId` | UUID | Not used for charts |

**Query pattern**: `PerformanceRecordRepository.fetch(exerciseId:, recordType: .repMax)` — sparse, ~50 rows per exercise max.

## Derived Data Structures (In-Memory Only)

All chart data types are plain structs, created in `ChartDataService`, consumed by ViewModels, rendered by Views. Released when navigating away from the chart screen.

### Overview Chart Data

```swift
/// Container for all overview section chart data.
struct OverviewChartData {
    let weeklyVolume: [WeeklyVolumePoint]
    let trainingFrequency: [WeeklyFrequencyPoint]
    let muscleGroupDistribution: [MuscleGroupVolume]
}

/// One bar in the weekly volume chart.
struct WeeklyVolumePoint: Identifiable {
    let id = UUID()
    let weekStart: Date      // Monday of the week
    let volume: Double        // Sum of effectiveWeight × reps
}

/// One bar in the training frequency chart.
struct WeeklyFrequencyPoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let sessions: Int         // Count of workouts in that week
}

/// One segment in the muscle group distribution chart.
struct MuscleGroupVolume: Identifiable {
    let id = UUID()
    let muscleGroup: String   // Exercise.primaryMuscle
    let volume: Double        // Sum of effectiveWeight × reps for that muscle
    let color: Color          // From MuscleGroupColors.color(for:)
}
```

### Exercise Card Data

```swift
/// Data for one exercise card in the PER EXERCISE section.
struct ExerciseCardData: Identifiable {
    let id: UUID              // Exercise ID
    let name: String
    let currentE1RM: Double?  // From ExerciseStats.bestE1RM
    let trendDirection: TrendDirection  // Up, down, or flat
    let sparklinePoints: [Double]       // Last 8 sessions' best e1RM
    let lastPerformed: Date?
}

enum TrendDirection {
    case up, down, flat
}
```

### Exercise Detail Chart Data

```swift
/// Container for all 4 chart types in the detail screen.
struct ExerciseDetailChartData {
    let e1RMTrend: [ExerciseChartData.ChartPoint]       // Reuse existing type
    let volumePerSession: [ExerciseChartData.VolumePoint] // Reuse existing type
    let topWeightPerSession: [TopWeightPoint]
    let repPRProgression: RepPRProgressionData
}

/// One point in the top weight per session chart.
struct TopWeightPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double        // Max effectiveWeight in that session
}

/// Multi-line data for rep PR progression.
struct RepPRProgressionData {
    let series: [RepSeries]   // One per tracked rep count (1, 3, 5)
}

struct RepSeries: Identifiable {
    let id = UUID()
    let reps: Int             // 1, 3, or 5
    let label: String         // "1RM", "3RM", "5RM"
    let points: [RepPRPoint]
}

struct RepPRPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double        // Best effectiveWeight at this rep count in session
}
```

### Time Range

```swift
/// Time range options for the detail screen filter.
enum TimeRange: String, CaseIterable {
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "All"

    /// Start date for the range, nil means no lower bound.
    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: Date())
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: Date())
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: Date())
        case .all: return nil
        }
    }
}
```

## Relationships (UUID-Based, No SwiftData @Relationship)

```
Workout.id ←── WorkoutSet.workoutId (1:many)
Exercise.id ←── WorkoutSet.exerciseId (many:1)
Exercise.id ←── ExerciseStats.exerciseId (1:1)
Exercise.id ←── PerformanceRecord.exerciseId (1:many)
PerformanceRecord.setId ──→ WorkoutSet.id (reference only, not used for charts)
```

All relationships are manual UUID lookups, consistent with the existing codebase pattern.

## New Repository Methods Required

### SetRepository (additions)

```swift
/// Fetch sets within a date range. Filter hasData in Swift (computed property, not predicable).
/// Used by: overview weekly volume, overview muscle groups
func fetchSets(from startDate: Date, to endDate: Date) throws -> [WorkoutSet]

/// Fetch sets for a specific exercise within a date range.
/// Used by: exercise detail charts, sparkline data
func fetchSets(exerciseId: UUID, from startDate: Date?, to endDate: Date) throws -> [WorkoutSet]
```

> **Note**: `hasData` is a computed property and cannot be used in `#Predicate`. Filter in Swift via `ChartDataService.chartEligibleSets(_:)` after fetching.

### Existing Methods Used (no additions needed)

- `WorkoutRepository.fetchWorkouts(for dateRange: ClosedRange<Date>)` — already exists, used for training frequency.
- `ExerciseStatsRepository.fetchAll()` — already exists, used for exercise card list. Filter `lastPerformedDate != nil` in Swift.

## No Schema Changes Required

This feature adds:
- **0 new SwiftData @Model classes**
- **0 new database fields**
- **0 new indexes**

All data is read from existing entities. New repository methods use existing indexes and add only new predicate combinations.
