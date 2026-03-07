# Architecture Plan: Charts Tab v2

**Feature**: 016-charts-tab-v2
**Date**: 2026-03-04

---

## 1. Strategy: Incremental Migration

The v2 charts tab replaces the existing dashboard layout while reusing the ChartDataService actor and extending it with new methods. We do NOT delete old code until the final cleanup step — this allows incremental delivery where each work package produces a working state.

### Phase Sequence

```
WP05: Foundation — New models, enums, 3-tab shell, TrendLine utility
  ↓
WP06: Breakdown Tab — Donut chart + service method          ← can ship standalone
  ↓
WP07: Workouts Tab — Bar chart + service method + navigation  ← can ship standalone
  ↓
WP08: Exercises Tab — Multi-line chart + service method       ← depends on WP09 for modal
  ↓  (parallel ↕)
WP09: Exercise Selection Modal + Presets                      ← can be built in parallel with WP08 chart
  ↓
WP10: Cleanup — Remove old code, dead model types
```

---

## 2. New File Plan

### New Files to Create

```
Reppo/Features/Charts/
├── Models/
│   ├── ChartModels.swift          ← EXTEND (add new enums + structs)
│   └── ChartPreset.swift          ← NEW (preset persistence)
├── ViewModels/
│   ├── ChartsTabViewModel.swift        ← NEW (replaces ChartsDashboardViewModel)
│   ├── BreakdownTabViewModel.swift     ← NEW
│   ├── WorkoutsTabViewModel.swift      ← NEW
│   └── ExercisesTabViewModel.swift     ← NEW
├── Views/
│   ├── ChartsTabView.swift             ← NEW (replaces ChartsDashboardView, 3-tab container)
│   ├── BreakdownTabView.swift          ← NEW
│   ├── WorkoutsTabView.swift           ← NEW
│   ├── ExercisesTabView.swift          ← NEW
│   └── Components/
│       ├── ChartSubTabPicker.swift     ← NEW (Breakdown/Workouts/Exercises pill bar)
│       ├── ChartDropdown.swift         ← NEW (reusable dropdown picker)
│       ├── ChartTimePills.swift        ← NEW (reusable time range pill bar)
│       ├── DonutChartView.swift        ← NEW (SectorMark donut)
│       ├── TimeSeriesBarChart.swift    ← NEW (flexible BarMark chart)
│       ├── MultiLineChart.swift        ← NEW (multi-exercise LineMark chart)
│       ├── TrendLineOverlay.swift      ← NEW (dotted trend line + slope badge)
│       ├── DataPointNavigator.swift    ← NEW (← → arrows + value/date display)
│       ├── ExerciseSelectionSheet.swift ← NEW (modal with Current/Presets)
│       └── ChartLegend.swift           ← NEW (color-coded legend for donut/lines)

Reppo/Core/Utilities/
│   └── TrendLineCalculator.swift       ← NEW (linear regression utility)
```

### Files to Modify

```
Reppo/Features/Charts/Models/ChartModels.swift           ← Add new enums and structs
Reppo/Core/Services/ChartDataService.swift                ← Add 3 new methods + protocol signatures
                                                            (protocol is defined inline at top of this file,
                                                             NOT in a separate Protocols/ file)
Reppo/App/ContentView.swift                               ← Update Charts tab to use ChartsTabView
```

> **Note**: `ChartDataServiceProtocol` is defined inline at the top of `ChartDataService.swift`, not in a separate protocol file. All new method signatures are added there.

### Files to Remove (WP10 cleanup only)

```
Reppo/Features/Charts/ViewModels/ChartsDashboardViewModel.swift
Reppo/Features/Charts/ViewModels/ExerciseChartsDetailViewModel.swift
Reppo/Features/Charts/Views/ChartsDashboardView.swift
Reppo/Features/Charts/Views/ExerciseChartsDetailView.swift
Reppo/Features/Charts/Views/Components/ExerciseChartCard.swift
Reppo/Features/Charts/Views/Components/WeeklyVolumeChart.swift
Reppo/Features/Charts/Views/Components/TrainingFrequencyChart.swift
Reppo/Features/Charts/Views/Components/MuscleGroupDistributionChart.swift
Reppo/Features/Charts/Views/Components/TopWeightChart.swift
Reppo/Features/Charts/Views/Components/RepPRProgressionChart.swift
```

---

## 3. ViewModel Architecture

### ChartsTabViewModel (Coordinator)

Owns the 3 sub-tab ViewModels and manages which tab is active. Handles session-scoped caching by holding references.

```swift
@Observable
final class ChartsTabViewModel {
    enum SubTab: Int, CaseIterable { case breakdown, workouts, exercises }

    var activeTab: SubTab = .breakdown

    // Child VMs — created once, hold cached data
    let breakdownVM: BreakdownTabViewModel
    let workoutsVM: WorkoutsTabViewModel
    let exercisesVM: ExercisesTabViewModel
}
```

### Each Sub-Tab ViewModel

Each owns its own state (dropdown selections, time range, chart data, selected data point index):

```swift
// Example: BreakdownTabViewModel
@Observable
final class BreakdownTabViewModel {
    var selectedMetric: BreakdownMetric = .volumeByCategory
    var selectedTimeRange: BreakdownTimeRange = .all
    var chartData: [BreakdownDataPoint]?
    var summaryStats: BreakdownSummary?
    var isLoading = false
    var dateRangeLabel: String = ""

    func loadData() async { ... }
    func changeMetric(_ metric: BreakdownMetric) async { ... }
    func changeTimeRange(_ range: BreakdownTimeRange) async { ... }
}
```

---

## 4. ChartDataService Extension Strategy

We add 3 new methods to the existing actor without removing old ones (old methods may still be used by other features or the Exercise detail sub-tab in the exercise list view):

### `fetchBreakdownData(metric:timeRange:)`

- Fetches sets in time range
- Applies `chartEligibleSets()` filter
- Groups by category (via exercise lookup cache) or by exercise name
- Aggregates: volume (effectiveWeight × reps), sets (count), reps (sum), workouts (distinct workoutIds)
- Returns sorted by value descending, with "Other" bucket if > 8 items

### `fetchWorkoutsTimeSeries(metric:aggregation:filter:timeRange:)`

- Fetches sets (optionally filtered by category/exerciseId) in time range
- Applies `chartEligibleSets()` filter
- Buckets by aggregation period (per workout: group by workoutId, per week/month/year: calendar bucketing)
- Computes metric per bucket (volume, sets count, reps sum, workout count, distance sum, time sum)
- Zero-fills empty buckets (for week/month/year aggregation)
- Returns chronologically sorted

### `fetchExerciseProgress(metric:exerciseIds:timeRange:)`

- Uses TaskGroup to fetch data for up to 10 exercises in parallel
- Per exercise: fetches sets, groups by workoutId, computes metric per session
- Metric computation varies:
  - `estimatedOneRM`: max(set.e1RM) per session
  - `maxWeight`: max(effectiveWeight) per session
  - `maxReps`: max(reps) per session
  - `maxVolume`: max(effectiveWeight × reps) per set per session
  - `workoutVolume`: sum(effectiveWeight × reps) per session
  - `workoutReps`: sum(reps) per session
  - `personalRecords`: filtered to PR-eligible sets only
  - `maxDistance`: max(distanceMeters) per session
  - `maxTime`: max(durationSeconds) per session
  - `minPace`: min(distanceMeters / durationSeconds) per session
  - `maxWeightForReps`: max(effectiveWeight) where reps ≥ target per session
- Returns ExerciseProgressSeries with assigned colors

---

## 5. Shared Components Design

### TrendLineCalculator

Pure utility, no dependencies:

```swift
struct TrendLineCalculator {
    /// Computes linear regression on date-value pairs.
    /// Returns nil if fewer than 2 points.
    static func compute(points: [(date: Date, value: Double)]) -> TrendLineData?
}
```

### DataPointNavigator

Reusable view component used by both Workouts and Exercises tabs:

```swift
struct DataPointNavigator<T> {
    let dataPoints: [T]
    @Binding var selectedIndex: Int?
    let valueFormatter: (T) -> String
    let dateFormatter: (T) -> String
}
```

### ChartDropdown

Reusable dropdown used across all tabs:

```swift
struct ChartDropdown<T: Identifiable & CustomStringConvertible> {
    let options: [T]
    @Binding var selected: T
    let label: String?
}
```

---

## 6. Preset Persistence

Simple UserDefaults-based storage using `ChartPresetStore`:

```swift
final class ChartPresetStore {
    private let key = "chartExercisePresets"

    func loadPresets() -> [ChartPreset] { ... }
    func savePreset(_ preset: ChartPreset) { ... }
    func deletePreset(_ id: UUID) { ... }
    func updatePreset(_ preset: ChartPreset) { ... }
}
```

Encoded/decoded as JSON array in UserDefaults. No SwiftData model needed — these are lightweight user preferences.

---

## 7. Risk Mitigation

| Risk                                               | Mitigation                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SectorMark API surface area unknown                | Research in WP05 — confirm SectorMark supports inner radius (donut), custom colors, and chart styling                                                                                                                                                                                                                                                                                                                                                       |
| Workouts tab query complexity (6×4×N permutations) | Single flexible service method with switch/case internal dispatch. Test with edge cases in each WP                                                                                                                                                                                                                                                                                                                                                          |
| 10-exercise parallel loading could be slow         | TaskGroup with structured concurrency. **Important**: `ChartDataService` is an actor — repository calls from TaskGroup child tasks will serialize on the actor's executor. To achieve true parallelism, extract `chartEligibleSets()` as a `static` (non-isolated) function and fetch all exercise data in a `nonisolated` helper that collects raw sets first, then processes on a shared executor. Fallback: limit to 5 exercises if performance degrades |
| Old code removal breaking other features           | Defer removal to WP10. Check for any cross-feature references (Exercise detail sub-tab uses some chart components)                                                                                                                                                                                                                                                                                                                                          |
| Exercise selection modal complexity                | Isolate in its own WP09. Build and test independently before integrating with Exercises tab                                                                                                                                                                                                                                                                                                                                                                 |
| Tab switching cancellation                         | Use Task cancellation pattern: store Task reference per tab, cancel on tab switch                                                                                                                                                                                                                                                                                                                                                                           |
