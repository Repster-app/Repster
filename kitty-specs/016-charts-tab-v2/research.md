# Research: Charts Tab v2 — Current State Analysis

**Feature**: 016-charts-tab-v2
**Date**: 2026-03-04

---

## 1. Current Implementation (009-charts-tab)

The existing charts tab was built across 4 work packages (WP01–WP04) and consists of:

### Architecture: Single-Scroll Dashboard + Drill-Down

```
ChartsDashboardView (ScrollView)
├── OVERVIEW section
│   ├── WeeklyVolumeChart (BarMark, last 12 weeks)
│   ├── TrainingFrequencyChart (sessions/week)
│   └── MuscleGroupDistributionChart (horizontal bars by muscle)
├── PER EXERCISE section
│   └── LazyVStack of ExerciseChartCards
│       └── NavigationLink → ExerciseChartsDetailView
│           ├── TimeRangeSelector (3M/6M/1Y/All)
│           ├── e1RM Trend (LineMark)
│           ├── Volume Per Session (BarMark)
│           ├── Top Weight (LineMark)
│           └── Rep PR Progression (multi-line 1RM/3RM/5RM)
```

### Existing Files

| File                                  | Purpose                          | Reuse in v2?                                                                                                      |
| ------------------------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `ChartModels.swift`                   | All data types                   | **Extend** — keep existing, add new types                                                                         |
| `ChartDataService.swift`              | Actor with 5 aggregation methods | **Extend** — add new query methods                                                                                |
| `ChartDataServiceProtocol`            | Protocol for DI                  | **Extend** — add new method signatures                                                                            |
| `ChartsDashboardViewModel.swift`      | Dashboard VM                     | **Replace** — new 3-tab architecture                                                                              |
| `ChartsDashboardView.swift`           | Dashboard view                   | **Replace** — new 3-tab layout                                                                                    |
| `ExerciseChartsDetailViewModel.swift` | Detail VM                        | **Keep or adapt** — may serve Exercises tab                                                                       |
| `ExerciseChartsDetailView.swift`      | Detail view                      | **Remove** — functionality absorbed into Exercises tab                                                            |
| `WeeklyVolumeChart.swift`             | Bar chart component              | **Remove** — replaced by flexible bar chart                                                                       |
| `TrainingFrequencyChart.swift`        | Frequency chart                  | **Remove** — replaced by Workouts tab                                                                             |
| `MuscleGroupDistributionChart.swift`  | Distribution chart               | **Remove** — replaced by Breakdown tab donut                                                                      |
| `ExerciseChartCard.swift`             | Sparkline card                   | **Remove** — no per-exercise card list in v2                                                                      |
| `TimeRangeSelector.swift`             | Segmented picker                 | **Remove** — replaced by new `ChartTimePills` component (different range options per tab, generic implementation) |
| `TopWeightChart.swift`                | Line chart                       | **Remove** — absorbed into Exercises tab metrics                                                                  |
| `RepPRProgressionChart.swift`         | Multi-line chart                 | **Remove** — absorbed into Exercises tab metrics                                                                  |

### Existing ChartDataService Methods

| Method                                         | Current Use                  | v2 Relevance                                                                              |
| ---------------------------------------------- | ---------------------------- | ----------------------------------------------------------------------------------------- |
| `fetchWeeklyVolume(weeks:)`                    | Overview bar chart           | Partially reusable for Workouts tab (but needs flexibility for metric/aggregation/filter) |
| `fetchTrainingFrequency(weeks:)`               | Overview frequency           | Can be adapted for Workouts tab "Workouts" metric                                         |
| `fetchMuscleGroupDistribution(weeks:)`         | Overview horizontal bars     | Partially reusable for Breakdown tab "Volume by Category"                                 |
| `fetchExerciseCardData()`                      | Per-exercise sparkline cards | **Not needed** — no card list in v2                                                       |
| `fetchExerciseDetailCharts(exerciseId:range:)` | Detail drill-down            | Partially reusable for Exercises tab single-exercise data                                 |

### Existing ChartModels Types

| Type                                                | v2 Relevance                                      |
| --------------------------------------------------- | ------------------------------------------------- |
| `OverviewChartData`                                 | **Remove** — no overview section                  |
| `WeeklyVolumePoint`                                 | Keep — useful building block                      |
| `WeeklyFrequencyPoint`                              | Keep — useful building block                      |
| `MuscleGroupVolume`                                 | Keep — useful for Breakdown tab                   |
| `ExerciseCardData`                                  | **Remove** — no card list                         |
| `TrendDirection`                                    | Keep                                              |
| `ExerciseDetailChartData`                           | **Restructure** — Exercises tab is multi-exercise |
| `TopWeightPoint`                                    | Keep as building block                            |
| `RepPRProgressionData` / `RepSeries` / `RepPRPoint` | Keep for PR metric in Exercises tab               |
| `TimeRange`                                         | **Extend** — need more range options              |
| `ExerciseChartData.ChartPoint` / `VolumePoint`      | Keep as building blocks                           |

---

## 2. What the v2 Design Introduces

Based on `prototype-charts-tab.html`:

### Structural Change: 3-Tab Layout

The single-scroll dashboard is replaced by 3 sub-tabs with distinct purposes:

1. **Breakdown** — Distribution analysis (donut chart)
2. **Workouts** — Time-series metrics (bar chart)
3. **Exercises** — Exercise-specific progress (multi-line chart)

### New Capabilities Not in v1

| Capability                                                                 | Complexity | Notes                                                                             |
| -------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------- |
| Donut/Pie chart (SectorMark)                                               | Medium     | iOS 17+ Swift Charts `SectorMark`                                                 |
| 8 breakdown chart type permutations                                        | Medium     | Need flexible groupBy (category vs exercise) × metric (volume/sets/reps/workouts) |
| Flexible bar chart (6 metrics × 4 aggregations × category/exercise filter) | High       | Needs a generalized query engine in ChartDataService                              |
| Linear regression trend line                                               | Low        | Pure math utility, ~20 lines                                                      |
| Slope indicator badge                                                      | Low        | Simple view component                                                             |
| Interactive data point navigation (← →)                                    | Medium     | State management for selected index + display                                     |
| Multi-exercise line chart (up to 10)                                       | High       | Multiple data series on one Swift Chart                                           |
| Exercise Selection Modal with Current/Presets                              | High       | New UI, new persistence for presets                                               |
| 11 exercise metric options                                                 | Medium     | Some exist (e1RM, max weight), others new (max distance, min pace)                |
| Different time range options per tab                                       | Low        | Extend TimeRange enum                                                             |

### New Data Queries Required

| Query                 | Parameters                                                                                   | Returns                                       |
| --------------------- | -------------------------------------------------------------------------------------------- | --------------------------------------------- |
| Breakdown aggregation | metric (volume/sets/reps/workouts), groupBy (category/exercise), timeRange                   | `[(label: String, value: Double)]`            |
| Workouts time series  | metric, aggregation (per workout/week/month/year), filter (all/category/exercise), timeRange | `[(date: Date, value: Double)]`               |
| Exercise progress     | metric (11 options), exerciseIds (up to 10), timeRange                                       | `[exerciseId: [(date: Date, value: Double)]]` |

---

## 3. Technical Considerations

### SectorMark Availability
- `SectorMark` is available in iOS 17+ via Swift Charts — confirmed compatible with our minimum deployment target.

### Performance
- Breakdown tab: Single aggregation query, bounded by time range. Fast.
- Workouts tab: Single time-series query with grouping. Needs efficient date bucketing. Fast for ≤5 years of data.
- Exercises tab: Up to 10 separate exercise queries. Could be slow if done sequentially — should use TaskGroup for parallel fetching.
- **Memory**: All chart data released when switching tabs (session-scoped per existing AGENT_RULES 5.3).

### Preset Persistence
- Exercise chart presets (saved exercise selections) need persistent storage.
- Options: (a) New SwiftData model `ChartPreset`, (b) UserDefaults/JSON file for simplicity.
- Recommendation: Simple JSON file or UserDefaults since presets are just `[{name: String, exerciseIds: [UUID]}]` — doesn't warrant a SwiftData model.

### Unit Conversion
- All chart y-axis labels showing weight values must respect user's unit preference (kg/lbs).
- Conversion at the view layer per AGENT_RULES 3.2 and 7.5.
