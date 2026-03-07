# Data Model: Charts Tab v2

**Feature**: 016-charts-tab-v2
**Date**: 2026-03-04

---

## 1. New Enums

### BreakdownMetric

Drives the Breakdown tab dropdown — which value to aggregate.

```swift
enum BreakdownMetric: String, CaseIterable, Identifiable {
    case volumeByCategory = "Volume by Category"
    case setsByCategory = "Sets by Category"
    case repsByCategory = "Reps by Category"
    case workoutsByCategory = "Workouts by Category"
    case volumeByExercise = "Volume by Exercise"
    case setsByExercise = "Sets by Exercise"
    case repsByExercise = "Reps by Exercise"
    case workoutsByExercise = "Workouts by Exercise"

    var id: String { rawValue }

    /// Whether grouping is by muscle category or individual exercise
    var groupBy: BreakdownGroupBy {
        switch self {
        case .volumeByCategory, .setsByCategory, .repsByCategory, .workoutsByCategory:
            return .category
        case .volumeByExercise, .setsByExercise, .repsByExercise, .workoutsByExercise:
            return .exercise
        }
    }

    /// Which aggregate value to compute
    var aggregateType: BreakdownAggregateType {
        switch self {
        case .volumeByCategory, .volumeByExercise: return .volume
        case .setsByCategory, .setsByExercise: return .sets
        case .repsByCategory, .repsByExercise: return .reps
        case .workoutsByCategory, .workoutsByExercise: return .workouts
        }
    }
}

enum BreakdownGroupBy {
    case category
    case exercise
}

enum BreakdownAggregateType {
    case volume   // effectiveWeight × reps
    case sets     // count of sets
    case reps     // sum of reps
    case workouts // count of distinct workouts
}
```

### BreakdownTimeRange

Time ranges specific to the Breakdown tab.

```swift
enum BreakdownTimeRange: String, CaseIterable, Identifiable {
    case all = "All"
    case year = "Year"
    case month = "Month"
    case week = "Week"
    case day = "Day"

    var id: String { rawValue }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .year: return cal.date(byAdding: .year, value: -1, to: Date())
        case .month: return cal.date(byAdding: .month, value: -1, to: Date())
        case .week: return cal.date(byAdding: .weekOfYear, value: -1, to: Date())
        case .day: return cal.startOfDay(for: Date())
        }
    }
}
```

### WorkoutsMetric

Metric selection for the Workouts tab.

```swift
enum WorkoutsMetric: String, CaseIterable, Identifiable {
    case reps = "Reps"
    case sets = "Sets"
    case volume = "Volume"
    case workouts = "Workouts"
    case distance = "Distance"
    case time = "Time"

    var id: String { rawValue }
}
```

### WorkoutsAggregation

Aggregation period for the Workouts tab.

```swift
enum WorkoutsAggregation: String, CaseIterable, Identifiable {
    case perWorkout = "Per Workout"
    case perWeek = "Per Week"
    case perMonth = "Per Month"
    case perYear = "Per Year"

    var id: String { rawValue }
}
```

### WorkoutsFilter

Filter scope for the Workouts tab.

```swift
enum WorkoutsFilter: Identifiable, Equatable, Hashable {
    case all
    case category(String)
    case exercise(UUID, name: String)

    var id: String {
        switch self {
        case .all: return "all"
        case .category(let name): return "cat:\(name)"
        case .exercise(let id, _): return "ex:\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .category(let name): return name
        case .exercise(_, let name): return name
        }
    }

    // Explicit Hashable conformance required for enums with associated values.
    // Needed by ChartDropdown<T: Hashable>.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

### WorkoutsTimeRange

Time ranges for the Workouts and Exercises tabs.

```swift
enum WorkoutsTimeRange: String, CaseIterable, Identifiable {
    case all = "All"
    case oneYear = "1y"
    case sixMonths = "6mo"
    case threeMonths = "3mo"
    case oneMonth = "1mo"

    var id: String { rawValue }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .oneYear: return cal.date(byAdding: .year, value: -1, to: Date())
        case .sixMonths: return cal.date(byAdding: .month, value: -6, to: Date())
        case .threeMonths: return cal.date(byAdding: .month, value: -3, to: Date())
        case .oneMonth: return cal.date(byAdding: .month, value: -1, to: Date())
        }
    }
}
```

### ExerciseMetric

Metric selection for the Exercises tab (11 options).

```swift
enum ExerciseMetric: String, CaseIterable, Identifiable {
    case estimatedOneRM = "Estimated 1RM"
    case maxWeight = "Max Weight"
    case maxReps = "Max Reps"
    case maxVolume = "Max Volume"
    case maxWeightForReps = "Max Weight for Reps"
    case workoutVolume = "Workout Volume"
    case workoutReps = "Workout Reps"
    case personalRecords = "Personal Records"
    case maxDistance = "Max Distance"
    case maxTime = "Max Time"
    case minPace = "Min Pace"

    var id: String { rawValue }

    /// Whether this metric applies to weight-based exercises
    var isWeightBased: Bool {
        switch self {
        case .maxDistance, .maxTime, .minPace: return false
        default: return true
        }
    }
}
```

---

## 2. New Data Structures

### BreakdownDataPoint

Result type for breakdown/donut chart segments.

```swift
struct BreakdownDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}
```

### WorkoutsTimeSeriesPoint

Result type for workouts bar chart.

```swift
struct WorkoutsTimeSeriesPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String?  // Optional label for display (e.g., workout title)
}
```

### ExerciseProgressSeries

Result type for the Exercises tab multi-line chart.

```swift
struct ExerciseProgressSeries: Identifiable {
    let id: UUID          // exerciseId
    let name: String
    let color: Color
    let points: [ExerciseProgressPoint]
}

struct ExerciseProgressPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
```

### TrendLineData

Linear regression result for trend lines.

```swift
struct TrendLineData {
    let slope: Double
    let intercept: Double
    let startPoint: (x: Double, y: Double)
    let endPoint: (x: Double, y: Double)

    var isPositive: Bool { slope > 0 }
    var isNegative: Bool { slope < 0 }
    var formattedSlope: String {
        String(format: "%.2f", slope)
    }
}

// Note: startPoint/endPoint use index-based x values (0...N-1).
// The view layer maps x indices back to dates from the original data array
// when rendering trend lines on date-axis charts.
```

### ChartPreset

For persisting saved exercise selections. Stored as JSON in UserDefaults.

```swift
struct ChartPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var exerciseIds: [UUID]

    init(id: UUID = UUID(), name: String, exerciseIds: [UUID]) {
        self.id = id
        self.name = name
        self.exerciseIds = exerciseIds
    }
}
```

---

## 3. Extended TimeRange

The existing `TimeRange` enum (3M/6M/1Y/All) is kept for backward compatibility but the new tabs use `BreakdownTimeRange` and `WorkoutsTimeRange` which have different options. The old `TimeRange` can remain for any existing code that references it.

---

## 4. New ChartDataService Protocol Methods

These methods will be added to `ChartDataServiceProtocol`:

```swift
// Breakdown tab
func fetchBreakdownData(
    metric: BreakdownMetric,
    timeRange: BreakdownTimeRange
) async throws -> [BreakdownDataPoint]

// Workouts tab
func fetchWorkoutsTimeSeries(
    metric: WorkoutsMetric,
    aggregation: WorkoutsAggregation,
    filter: WorkoutsFilter,
    timeRange: WorkoutsTimeRange
) async throws -> [WorkoutsTimeSeriesPoint]

// Exercises tab
func fetchExerciseProgress(
    metric: ExerciseMetric,
    exerciseIds: [UUID],
    timeRange: WorkoutsTimeRange
) async throws -> [ExerciseProgressSeries]
```

---

## 5. Summary of Changes to Existing Models

| Action | Type                                        | Notes                                   |
| ------ | ------------------------------------------- | --------------------------------------- |
| Keep   | `WeeklyVolumePoint`                         | May still be used internally by service |
| Keep   | `WeeklyFrequencyPoint`                      | May still be used internally by service |
| Keep   | `MuscleGroupVolume`                         | Used in breakdown service logic         |
| Keep   | `TrendDirection`                            | Used for slope indicator                |
| Keep   | `TopWeightPoint`, `RepPRPoint`, `RepSeries` | Internal building blocks                |
| Remove | `OverviewChartData`                         | No overview section in v2               |
| Remove | `ExerciseCardData`                          | No per-exercise card list in v2         |
| Remove | `ExerciseDetailChartData`                   | Replaced by `ExerciseProgressSeries`    |
| Add    | All new enums and structs above             | New for v2                              |

**Note**: "Remove" means the types can be deleted once all references are migrated. Do this in the final cleanup WP.
