---
work_package_id: "WP07"
subtasks:
  - "T118"
  - "T119"
  - "T120"
  - "T121"
  - "T122"
  - "T123"
title: "Workouts Tab — Bar Chart + Time Series Service"
phase: "Phase 1 - Workouts"
lane: "planned"
dependencies: ["WP05"]
agent: ""
assignee: ""
shell_pid: ""
reviewed_by: ""
review_status: ""
history:
  - timestamp: "2026-03-04T14:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated manually (spec-kitty format)"
---

# Work Package Prompt: WP07 – Workouts Tab — Bar Chart + Time Series Service

## Objectives & Success Criteria

- Implement `fetchWorkoutsTimeSeries(metric:aggregation:filter:timeRange:)` in ChartDataService — the most complex service method with 6 metrics × 4 aggregations × category/exercise filtering.
- Create WorkoutsTabViewModel with 3 dropdowns, time range, trend line, data point navigation.
- Create TimeSeriesBarChart using Swift Charts BarMark with dashed trend line overlay.
- Create WorkoutsTabView composing 3 dropdowns + time pills + bar chart + slope badge + data navigator.
- Build filter dropdown data source (available categories and exercises).
- **Success**: Workouts tab renders bar chart for "Volume / Per Month / All". All metric/aggregation/filter combos work. Trend line shows with slope badge. ← → navigation works. Empty state for no data.

## Context & Constraints

- **Spec**: FR-005, FR-006, FR-007, FR-008 from `kitty-specs/016-charts-tab-v2/spec.md`.
- **Existing patterns**: Reuse `chartEligibleSets()`. Reuse ISO week grouping pattern from existing `fetchWeeklyVolume()`.
- **Unit display**: Volume Y-axis shows "kg" (or user's unit preference). Sets/Reps/Workouts show integer counts. Distance shows "m"/"km". Time shows "min".
- **Trend line**: Use `TrendLineCalculator.compute(values:)` from WP05. Render as dashed `LineMark` overlay on the bar chart, or as `RuleMark` from start to end.
- **Zero-fill**: For week/month/year aggregation, fill gaps with zero-value entries. For perWorkout, no zero-fill (discrete events).
- **Prototype**: See "Tab 2: Workouts" in `prototype-charts-tab.html`.

**Implementation command**: `spec-kitty implement WP07 --base WP05`

## Subtasks & Detailed Guidance

### Subtask T118 – Implement fetchWorkoutsTimeSeries() in ChartDataService

- **File**: `Reppo/Core/Services/ChartDataService.swift` (edit)
- **Protocol**: Also add to `ChartDataServiceProtocol` (defined inline at top of `ChartDataService.swift`, NOT in a separate protocol file)

**Algorithm**:
1. Determine date range from `timeRange.startDate`.
2. Fetch sets with optional filter:
   - `.all`: fetch all sets in date range
   - `.category(name)`: fetch all sets, build exercise cache, filter where `exercise.primaryMuscle?.lowercased() == name.lowercased()`
   - `.exercise(id, _)`: fetch sets for that exerciseId in date range
3. Apply `chartEligibleSets()`.
4. Bucket by aggregation:
   - `perWorkout`: group by workoutId. Date = workout date (look up via set.date or fetch workout).
   - `perWeek`: group by ISO week start (same as existing `fetchWeeklyVolume` pattern).
   - `perMonth`: group by `Calendar.current.dateComponents([.year, .month], from: set.date)`.
   - `perYear`: group by `Calendar.current.component(.year, from: set.date)`.
5. Compute metric per bucket:
   - `volume`: sum(effectiveWeight × reps)
   - `sets`: count of sets
   - `reps`: sum(reps)
   - `workouts`: count of distinct workoutIds in bucket
   - `distance`: sum(distanceMeters)
   - `time`: sum(durationSeconds) converted to minutes for display
6. Zero-fill for week/month/year (not perWorkout).
7. Sort chronologically.
8. Return `[WorkoutsTimeSeriesPoint]`.

```swift
func fetchWorkoutsTimeSeries(
    metric: WorkoutsMetric,
    aggregation: WorkoutsAggregation,
    filter: WorkoutsFilter,
    timeRange: WorkoutsTimeRange
) async throws -> [WorkoutsTimeSeriesPoint] {
    let startDate = timeRange.startDate ?? Date.distantPast
    let endDate = Date()

    // Fetch and filter sets
    var allSets: [WorkoutSet]
    switch filter {
    case .all:
        allSets = try await setRepository.fetchSets(from: startDate, to: endDate)
    case .exercise(let id, _):
        allSets = try await setRepository.fetchSets(exerciseId: id, from: startDate, to: endDate)
    case .category(let categoryName):
        allSets = try await setRepository.fetchSets(from: startDate, to: endDate)
        let exerciseIds = Swift.Set(allSets.map { $0.exerciseId })
        var cache: [UUID: Exercise] = [:]
        for id in exerciseIds {
            if let ex = try await exerciseRepository.fetch(byId: id) { cache[id] = ex }
        }
        allSets = allSets.filter { set in
            guard let ex = cache[set.exerciseId] else { return false }
            return ex.primaryMuscle?.lowercased() == categoryName.lowercased()
        }
    }

    let eligible = chartEligibleSets(allSets)
    guard !eligible.isEmpty else { return [] }

    let calendar = Calendar.current

    // Bucket sets
    // ... (group by aggregation period, compute metric, zero-fill, sort)
    // Return WorkoutsTimeSeriesPoint array
}
```

The internal bucketing logic is complex — implement helper methods for each aggregation type. Follow the existing `fetchWeeklyVolume()` pattern for ISO week grouping.

**Validation**: Returns correct values for each metric × aggregation combo. Zero-filled gaps for periodic aggregation. Empty array when no data.

---

### Subtask T119 – Create WorkoutsTabViewModel

- **File**: `Reppo/Features/Charts/ViewModels/WorkoutsTabViewModel.swift` (new)

State: `selectedMetric: WorkoutsMetric`, `selectedAggregation: WorkoutsAggregation`, `selectedFilter: WorkoutsFilter`, `selectedTimeRange: WorkoutsTimeRange`, `chartData: [WorkoutsTimeSeriesPoint]?`, `trendLine: TrendLineData?`, `selectedDataIndex: Int?`, `availableCategories: [String]`, `availableExercises: [(id: UUID, name: String)]`.

Methods: `loadData()`, `changeMetric()`, `changeAggregation()`, `changeFilter()`, `changeTimeRange()`, `navigateDataPoint(direction:)`.

On data load: compute trend line via `TrendLineCalculator.compute(values: chartData.map { $0.value })`. Set `selectedDataIndex` to last point.

Also update `ChartsTabViewModel` to hold `WorkoutsTabViewModel`.

---

### Subtask T120 – Create TimeSeriesBarChart

- **File**: `Reppo/Features/Charts/Views/Components/TimeSeriesBarChart.swift` (new)
- **Parallel?**: Yes

```swift
import SwiftUI
import Charts

struct TimeSeriesBarChart: View {
    let data: [WorkoutsTimeSeriesPoint]
    let trendLine: TrendLineData?
    let yAxisLabel: String // e.g., "kg", "reps"
    var selectedIndex: Int?

    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                BarMark(
                    x: .value("Date", point.date, unit: .month),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(index == selectedIndex ? Color.accent : Color.accent.opacity(0.6))
                .cornerRadius(4)
            }

            // Trend line as LineMark overlay
            if let trend = trendLine, data.count >= 2 {
                // Render dashed line from first to last point
                // Using RuleMark or computed LineMark points
            }
        }
        .frame(height: 220)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.border)
                AxisValueLabel()
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}
```

Y-axis formatting varies by metric. Pass `yAxisLabel` for suffix.

---

### Subtask T121 – Create WorkoutsTabView

- **File**: `Reppo/Features/Charts/Views/WorkoutsTabView.swift` (new)

Compose: 2 dropdowns side by side (Metric + Aggregation) → 1 full-width dropdown (Filter) → ChartTimePills → chart card containing TimeSeriesBarChart + SlopeBadge + DataPointNavigator.

Replace placeholder in `ChartsTabView.tabContent` for `.workouts` case.

---

### Subtask T122 – Build Filter Dropdown Data Source

Need to populate the Filter dropdown with available categories and exercises. Fetch from ExerciseService:
- Categories: distinct `primaryMuscle` values from all exercises
- Exercises: exercises that have been performed (have ExerciseStats with lastPerformedDate)

May need a convenience method on ExerciseService or use existing `fetchExercise` methods.

---

### Subtask T123 – Edge Cases

- Empty data: Show empty state inside chart card.
- Single data point: Show bar, no trend line.
- Distance/Time metrics with no matching data: Empty chart.
- Zero-fill: Only for periodic aggregation (week/month/year), not perWorkout.
- Very long date range with perWorkout: Many bars — chart should handle scroll or auto-adjust bar width.

---

## Definition of Done Checklist

- [ ] `fetchWorkoutsTimeSeries()` added to protocol and implemented
- [ ] WorkoutsTabViewModel created with all 3 dropdown states + navigation
- [ ] TimeSeriesBarChart renders bars with dashed trend line
- [ ] WorkoutsTabView composes dropdowns + pills + chart + slope + navigator
- [ ] Filter dropdown populates with real categories and exercises
- [ ] Trend line computed via TrendLineCalculator
- [ ] Data point navigation with ← → works
- [ ] Empty state and edge cases handled
- [ ] Wired into ChartsTabView
- [ ] App compiles without errors

## Review Guidance

- Verify all 6 metric × 4 aggregation combinations produce correct data.
- Verify category filter correctly filters by primaryMuscle.
- Verify exercise filter uses exerciseId (not name matching).
- Verify zero-fill only applies to periodic aggregation.
- Verify trend line uses TrendLineCalculator (not re-implementing regression).
- Verify Y-axis units change with metric (kg for volume, count for sets/reps).

## Activity Log
