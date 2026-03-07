---
work_package_id: "WP08"
subtasks:
  - "T124"
  - "T125"
  - "T126"
  - "T127"
  - "T128"
title: "Exercises Tab — Multi-Line Chart + Progress Service"
phase: "Phase 1 - Exercises"
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

# Work Package Prompt: WP08 – Exercises Tab — Multi-Line Chart + Progress Service

## Objectives & Success Criteria

- Implement `fetchExerciseProgress(metric:exerciseIds:timeRange:)` in ChartDataService using TaskGroup for parallel loading of up to 10 exercises.
- Create ExercisesTabViewModel with metric dropdown, exercise selection state, time range, trend line, data point navigation.
- Create MultiLineChart using Swift Charts LineMark with multiple colored series.
- Create ExercisesTabView composing metric dropdown + exercise trigger button + time pills + line chart + slope badge + navigator + exercise legend.
- **Success**: Exercises tab renders multi-line chart for "Estimated 1RM" with pre-selected exercises. Metric switching works. Trend line shows. ← → navigation works. Exercise color legend below chart.

## Context & Constraints

- **Spec**: FR-009, FR-010, FR-013, FR-014 from `kitty-specs/016-charts-tab-v2/spec.md`.
- **TaskGroup**: Use `withTaskGroup(of:returning:body:)` for parallel exercise data fetching. Each child task fetches one exercise's data.
- **Actor serialization caveat**: `ChartDataService` is an `actor`. Repository calls from within TaskGroup child tasks will hop back to the actor's serial executor, partially serializing the "parallel" work. For true parallelism, consider extracting `chartEligibleSets()` as a `static` function (it's pure — no actor state needed) and pre-fetching all exercise data in a `nonisolated` helper. See plan.md Risk Mitigation table for details.
- **11 metrics**: See `ExerciseMetric` enum in `data-model.md`. Each metric computes differently per session.
- **Chart palette**: Reuse same palette as Breakdown tab for line colors.
- **Exercise selection**: Initially hardcoded or empty. Full modal built in WP09 and wired in.
- **Prototype**: See "Tab 3: Exercises" in `prototype-charts-tab.html`.

**Implementation command**: `spec-kitty implement WP08 --base WP05`

## Subtasks & Detailed Guidance

### Subtask T124 – Implement fetchExerciseProgress() in ChartDataService

- **File**: `Reppo/Core/Services/ChartDataService.swift` (edit)
- **Protocol**: Also add to `ChartDataServiceProtocol` (defined inline at top of `ChartDataService.swift`, NOT in a separate protocol file)

**Algorithm**:
1. Use `withTaskGroup` to fetch data for each exerciseId in parallel.
2. Per exercise child task:
   a. Look up exercise name via `exerciseRepository.fetch(byId:)`.
   b. Fetch sets via `setRepository.fetchSets(exerciseId:from:to:)`.
   c. Apply `chartEligibleSets()`.
   d. Group by workoutId.
   e. Compute metric per session:
      - `estimatedOneRM`: `max(set.e1RM)` where e1RM > 0
      - `maxWeight`: `max(effectiveWeight)`
      - `maxReps`: `max(reps)`
      - `maxVolume`: `max(effectiveWeight × reps)` per set
      - `maxWeightForReps`: `max(effectiveWeight)` — treat as same as maxWeight for now
      - `workoutVolume`: `sum(effectiveWeight × reps)`
      - `workoutReps`: `sum(reps)`
      - `personalRecords`: filter to sets where `cachedPRStatus == .current` (typed enum, NOT string), use effectiveWeight
      - `maxDistance`: `max(distanceMeters)`
      - `maxTime`: `max(durationSeconds)`
      - `minPace`: `min(distanceMeters / durationSeconds)` where both > 0
   f. Return sorted chronologically.
3. Assign colors from chart palette (index-based).
4. Return `[ExerciseProgressSeries]`.

```swift
func fetchExerciseProgress(
    metric: ExerciseMetric,
    exerciseIds: [UUID],
    timeRange: WorkoutsTimeRange
) async throws -> [ExerciseProgressSeries] {
    let startDate = timeRange.startDate
    let endDate = Date()
    let palette = Self.chartPalette

    return try await withThrowingTaskGroup(
        of: (Int, ExerciseProgressSeries?).self
    ) { group in
        for (index, exerciseId) in exerciseIds.enumerated() {
            group.addTask { [self] in
                guard let exercise = try await self.exerciseRepository.fetch(byId: exerciseId) else {
                    return (index, nil)
                }

                let sets = try await self.setRepository.fetchSets(
                    exerciseId: exerciseId, from: startDate, to: endDate
                )
                let eligible = self.chartEligibleSets(sets)
                guard !eligible.isEmpty else { return (index, nil) }

                let grouped = Dictionary(grouping: eligible) { $0.workoutId }
                var points: [ExerciseProgressPoint] = []

                for (_, workoutSets) in grouped {
                    guard let date = workoutSets.first?.date else { continue }
                    let value = self.computeMetric(metric, for: workoutSets)
                    if let value, value > 0 {
                        points.append(ExerciseProgressPoint(date: date, value: value))
                    }
                }

                points.sort { $0.date < $1.date }
                guard !points.isEmpty else { return (index, nil) }

                let color = palette[index % palette.count]
                return (index, ExerciseProgressSeries(
                    id: exerciseId, name: exercise.name,
                    color: color, points: points
                ))
            }
        }

        var results: [(Int, ExerciseProgressSeries)] = []
        for try await (index, series) in group {
            if let series { results.append((index, series)) }
        }
        return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}

private func computeMetric(_ metric: ExerciseMetric, for sets: [WorkoutSet]) -> Double? {
    switch metric {
    case .estimatedOneRM:
        return sets.compactMap { $0.e1RM }.filter { $0 > 0 }.max()
    case .maxWeight:
        return sets.compactMap { $0.effectiveWeight }.filter { $0 > 0 }.max()
    case .maxReps:
        return sets.compactMap { $0.reps }.map { Double($0) }.max()
    case .maxVolume:
        return sets.map { ($0.effectiveWeight ?? 0) * Double($0.reps ?? 0) }.max()
    case .maxWeightForReps:
        // Note: This metric is identical to maxWeight for v1 since there's no rep-target
        // parameter in the current ExerciseMetric enum. In a future iteration, this could
        // be extended with a user-selected rep target (e.g., "Max Weight for 5+ Reps").
        // For now, treat as max(effectiveWeight) — same as maxWeight.
        return sets.compactMap { $0.effectiveWeight }.filter { $0 > 0 }.max()
    case .workoutVolume:
        return sets.reduce(0) { $0 + (($1.effectiveWeight ?? 0) * Double($1.reps ?? 0)) }
    case .workoutReps:
        return sets.reduce(0) { $0 + Double($1.reps ?? 0) }
    case .personalRecords:
        // CachedPRStatus is an enum (see Reppo/Data/Enums/CachedPRStatus.swift).
        // .current = PR owner on the suffix-max frontier (shows ★ badge).
        // Do NOT compare as string — use the typed enum value.
        return sets.filter { $0.cachedPRStatus == .current }.compactMap { $0.effectiveWeight }.max()
    case .maxDistance:
        return sets.compactMap { $0.distanceMeters }.filter { $0 > 0 }.max()
    case .maxTime:
        return sets.compactMap { $0.durationSeconds }.map { Double($0) }.max()
    case .minPace:
        let paces = sets.compactMap { set -> Double? in
            guard let dist = set.distanceMeters, dist > 0,
                  let dur = set.durationSeconds, dur > 0 else { return nil }
            return dist / Double(dur)
        }
        return paces.min()
    }
}
```

**Validation**: Returns correct series for each exercise. Parallel loading completes. Colors assigned by index. Empty exercises omitted.

---

### Subtask T125 – Create ExercisesTabViewModel

- **File**: `Reppo/Features/Charts/ViewModels/ExercisesTabViewModel.swift` (new)

State: `selectedMetric: ExerciseMetric`, `selectedExercises: [(id: UUID, name: String)]`, `selectedTimeRange: WorkoutsTimeRange`, `chartData: [ExerciseProgressSeries]?`, `trendLine: TrendLineData?`, `selectedDataIndex: Int?`, `showExerciseSelector: Bool`.

Methods: `loadData()`, `changeMetric()`, `updateExercises(newSelection:)`, `changeTimeRange()`, `navigateDataPoint(direction:)`.

On data load: compute trend line for first series via `TrendLineCalculator.compute(values: series[0].points.map { $0.value })`.

Default: empty selection → prompt state "Select exercises to view progress".

Also update `ChartsTabViewModel` to hold `ExercisesTabViewModel`.

---

### Subtask T126 – Create MultiLineChart

- **File**: `Reppo/Features/Charts/Views/Components/MultiLineChart.swift` (new)
- **Parallel?**: Yes

```swift
import SwiftUI
import Charts

struct MultiLineChart: View {
    let series: [ExerciseProgressSeries]
    let trendLine: TrendLineData?
    let yAxisLabel: String

    var body: some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(s.color)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(s.color)
                    .symbolSize(20)
                }
            }

            // Trend line for first series (dashed)
            // Render via computed LineMark points with .lineStyle(StrokeStyle(dash: [6, 4]))
        }
        .frame(height: 220)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
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

Use `foregroundStyle(by: .value("Exercise", s.name))` with `.chartForegroundStyleScale` for explicit color mapping if needed.

---

### Subtask T127 – Create ExercisesTabView

- **File**: `Reppo/Features/Charts/Views/ExercisesTabView.swift` (new)

Compose: Metric dropdown → Exercise selection button (accent color, shows names) → ChartTimePills → chart card with MultiLineChart + SlopeBadge + DataPointNavigator → Exercise legend card (color + name + latest value).

Exercise selection button: tapping sets `viewModel.showExerciseSelector = true` which presents the modal from WP09. Initially, before WP09: show prompt or hardcoded test exercises.

Replace placeholder in `ChartsTabView.tabContent` for `.exercises` case.

---

### Subtask T128 – Edge Cases

- No exercises selected: Show centered prompt "Select exercises to view progress".
- Exercise with incompatible metric (weight metric on distance-only exercise): line simply doesn't appear (no data points).
- Single data point per exercise: Show point, no trend line.
- All exercises empty for chosen metric: Show "No data for this period".
- 10 exercises: All render with cycling colors.

---

## Definition of Done Checklist

- [ ] `fetchExerciseProgress()` added to protocol and implemented with TaskGroup
- [ ] `computeMetric()` handles all 11 ExerciseMetric cases
- [ ] ExercisesTabViewModel created with all state + methods
- [ ] MultiLineChart renders multiple colored line series
- [ ] ExercisesTabView composes all components
- [ ] Trend line for first exercise computed and displayed
- [ ] Data point navigation works
- [ ] Exercise color legend shows below chart
- [ ] Empty/prompt states handled
- [ ] Wired into ChartsTabView
- [ ] App compiles without errors

## Review Guidance

- Verify TaskGroup is used for parallel loading (not sequential loop).
- Verify `computeMetric()` correctly handles all 11 cases.
- Verify colors are assigned by stable index (not random).
- Verify trend line is computed for first series only.
- Verify empty exercises are filtered out (no empty series returned).
- Verify cachedPRStatus check for personalRecords metric.

## Activity Log
