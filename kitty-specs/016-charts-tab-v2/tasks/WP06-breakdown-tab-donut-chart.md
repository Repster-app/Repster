---
work_package_id: "WP06"
subtasks:
  - "T113"
  - "T114"
  - "T115"
  - "T116"
  - "T117"
title: "Breakdown Tab — Donut Chart + Service Method"
phase: "Phase 1 - Breakdown"
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

# Work Package Prompt: WP06 – Breakdown Tab — Donut Chart + Service Method

## Objectives & Success Criteria

- Implement `fetchBreakdownData(metric:timeRange:)` in ChartDataService with all 8 metric permutations.
- Create BreakdownTabViewModel with metric/time range state and data loading.
- Create DonutChartView using Swift Charts SectorMark.
- Create BreakdownTabView composing dropdown + time pills + donut + legend + summary stats.
- Handle edge cases: empty data, > 8 exercises grouped as "Other".
- **Success**: Breakdown tab renders a donut chart for all 8 dropdown options. Time range pills filter data. Legend shows percentages. Summary stats row shows totals. Empty state when no data.

## Context & Constraints

- **Spec**: FR-002, FR-003, FR-004 from `kitty-specs/016-charts-tab-v2/spec.md`.
- **SectorMark**: iOS 17+ Swift Charts. Use `SectorMark(angle: .value(...))` with `.innerRadius(.ratio(0.62))` for donut.
- **Existing patterns**: Reuse `chartEligibleSets()` from ChartDataService. Reuse exercise cache pattern from existing `fetchMuscleGroupDistribution()`.
- **Chart palette**: Define in ChartModels or a shared location. **Note**: Colors 5–8 are raw values not yet in DesignTokens.swift — add `chart5` through `chart8` tokens to `DesignTokens.swift` for consistency, then reference them here:
  ```swift
  static let chartPalette: [Color] = [.accent, .success, .gold, .danger, .chart5, .chart6, .chart7, .chart8]
  // Where chart5–chart8 are added to DesignTokens.swift:
  // static let chart5 = Color(red: 0.659, green: 0.494, blue: 0.902) // purple
  // static let chart6 = Color(red: 0.910, green: 0.608, blue: 0.243) // orange (same as .orange token)
  // static let chart7 = Color(red: 0.306, green: 0.804, blue: 0.769) // teal
  // static let chart8 = Color(red: 1.0, green: 0.420, blue: 0.616)   // pink
  ```
- **Prototype**: See "Tab 1: Breakdown" in `prototype-charts-tab.html`.

**Implementation command**: `spec-kitty implement WP06 --base WP05`

## Subtasks & Detailed Guidance

### Subtask T113 – Implement fetchBreakdownData() in ChartDataService

- **File**: `Reppo/Core/Services/ChartDataService.swift` (edit — add new method)
- **Protocol**: Also add to `ChartDataServiceProtocol` (defined inline at top of `ChartDataService.swift`, NOT in a separate protocol file)

**Algorithm**:
1. Determine date range from `timeRange.startDate` (nil = all time).
2. Fetch sets via `setRepository.fetchSets(from:to:)` (or all sets if `startDate` is nil — may need a new convenience method or pass distant past).
3. Apply `chartEligibleSets()` filter.
4. Build exercise cache: `[UUID: Exercise]` for all exerciseIds in the set.
5. Group by `metric.groupBy`:
   - `.category`: group by `exercise.primaryMuscle` (lowercased)
   - `.exercise`: group by exercise name
6. Aggregate per group by `metric.aggregateType`:
   - `.volume`: sum(effectiveWeight × reps)
   - `.sets`: count of sets
   - `.reps`: sum(reps)
   - `.workouts`: count of distinct workoutIds
7. Sort by value descending.
8. If > 8 groups: keep top 7 by value, sum remainder into "Other" with `Color.textTertiary` color (max 8 total segments).
9. Assign colors from chart palette.
10. Return `[BreakdownDataPoint]`.

```swift
func fetchBreakdownData(metric: BreakdownMetric, timeRange: BreakdownTimeRange) async throws -> [BreakdownDataPoint] {
    let startDate = timeRange.startDate ?? Date.distantPast
    let endDate = Date()
    let allSets = try await setRepository.fetchSets(from: startDate, to: endDate)
    let eligible = chartEligibleSets(allSets)

    // Build exercise cache
    let exerciseIds = Swift.Set(eligible.map { $0.exerciseId })
    var exerciseCache: [UUID: Exercise] = [:]
    for id in exerciseIds {
        if let ex = try await exerciseRepository.fetch(byId: id) {
            exerciseCache[id] = ex
        }
    }

    // Group by category or exercise
    var grouped: [String: [WorkoutSet]] = [:]
    for set in eligible {
        guard let exercise = exerciseCache[set.exerciseId] else { continue }
        let key: String
        switch metric.groupBy {
        case .category:
            key = exercise.primaryMuscle?.lowercased() ?? "other"
        case .exercise:
            key = exercise.name
        }
        grouped[key, default: []].append(set)
    }

    // Aggregate
    var results: [(label: String, value: Double)] = []
    for (label, sets) in grouped {
        let value: Double
        switch metric.aggregateType {
        case .volume:
            value = sets.reduce(0) { $0 + (($1.effectiveWeight ?? 0) * Double($1.reps ?? 0)) }
        case .sets:
            value = Double(sets.count)
        case .reps:
            value = sets.reduce(0) { $0 + Double($1.reps ?? 0) }
        case .workouts:
            value = Double(Swift.Set(sets.map { $0.workoutId }).count)
        }
        if value > 0 {
            results.append((label: label.capitalized, value: value))
        }
    }

    results.sort { $0.value > $1.value }

    // Cap at 8 with "Other" bucket
    let palette = Self.chartPalette
    if results.count > 8 {
        let top7 = results.prefix(7)
        let otherValue = results.dropFirst(7).reduce(0) { $0 + $1.value }
        var points = top7.enumerated().map { i, r in
            BreakdownDataPoint(label: r.label, value: r.value, color: palette[i % palette.count])
        }
        points.append(BreakdownDataPoint(label: "Other", value: otherValue, color: Color.textTertiary))
        return points
    } else {
        return results.enumerated().map { i, r in
            BreakdownDataPoint(label: r.label, value: r.value, color: palette[i % palette.count])
        }
    }
}
```

Add a static palette to ChartDataService or ChartModels.

**Validation**: Returns correct breakdown for each of the 8 metric options. "Other" bucket appears when > 8 groups.

---

### Subtask T114 – Create BreakdownTabViewModel

- **File**: `Reppo/Features/Charts/ViewModels/BreakdownTabViewModel.swift` (new)

```swift
@Observable
final class BreakdownTabViewModel {
    var selectedMetric: BreakdownMetric = .volumeByCategory
    var selectedTimeRange: BreakdownTimeRange = .all
    var chartData: [BreakdownDataPoint]?
    var isLoading = false
    var dateRangeLabel: String = ""
    // Summary stats
    var totalVolume: Double = 0
    var totalSets: Int = 0
    var totalReps: Int = 0
    var totalWorkouts: Int = 0

    private let chartDataService: any ChartDataServiceProtocol

    init(chartDataService: any ChartDataServiceProtocol) {
        self.chartDataService = chartDataService
    }

    func loadData() async {
        isLoading = true
        do {
            chartData = try await chartDataService.fetchBreakdownData(
                metric: selectedMetric, timeRange: selectedTimeRange
            )
            // Compute date range label and summary stats from loaded data
            updateDateRangeLabel()
        } catch {
            print("[BreakdownTab] Error: \(error)")
        }
        isLoading = false
    }

    func changeMetric(_ metric: BreakdownMetric) async {
        selectedMetric = metric
        chartData = nil
        await loadData()
    }

    func changeTimeRange(_ range: BreakdownTimeRange) async {
        selectedTimeRange = range
        chartData = nil
        await loadData()
    }

    private func updateDateRangeLabel() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let start = selectedTimeRange.startDate ?? Date(timeIntervalSince1970: 0)
        dateRangeLabel = "\(formatter.string(from: start)) → \(formatter.string(from: Date()))"
    }
}
```

Also update `ChartsTabViewModel` to create and hold `BreakdownTabViewModel`.

---

### Subtask T115 – Create DonutChartView

- **File**: `Reppo/Features/Charts/Views/Components/DonutChartView.swift` (new)
- **Parallel?**: Yes

```swift
import SwiftUI
import Charts

struct DonutChartView: View {
    let data: [BreakdownDataPoint]

    var body: some View {
        Chart(data) { item in
            SectorMark(
                angle: .value(item.label, item.value),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .foregroundStyle(item.color)
            .cornerRadius(4)
        }
        .frame(height: 240)
        .chartLegend(.hidden) // We use custom ChartLegend
    }
}
```

**Validation**: Donut renders with inner hole. Each segment colored correctly. No built-in legend (using custom).

---

### Subtask T116 – Create BreakdownTabView

- **File**: `Reppo/Features/Charts/Views/BreakdownTabView.swift` (new)

Compose: ChartDropdown (8 options) → ChartTimePills (5 options) → DonutChartView → ChartLegend → date range label → Summary stats row.

Replace placeholder in `ChartsTabView.tabContent` with `BreakdownTabView(viewModel: viewModel.breakdownVM)`.

**Summary stats row**: 4-column card showing Total Volume, Total Sets, Total Reps, Workouts. Same pattern as design system Section 6.2.

---

### Subtask T117 – Edge Cases

- Empty data: Show centered message "No data for this period" inside the chart card.
- "By Exercise" with > 8 items: Already handled by T113 ("Other" bucket).
- Single category: Donut shows single full circle.
- All-zero data: Show empty state.

---

## Definition of Done Checklist

- [ ] `fetchBreakdownData()` added to protocol and implemented with all 8 permutations
- [ ] BreakdownTabViewModel created with metric/timeRange state and loading
- [ ] DonutChartView renders SectorMark donut with custom colors
- [ ] BreakdownTabView composes all components
- [ ] Chart legend shows color + label + percentage
- [ ] Summary stats row shows totals
- [ ] Empty state for no data
- [ ] "Other" bucket for > 8 groups
- [ ] Wired into ChartsTabView (replaces placeholder)
- [ ] App compiles without errors

## Review Guidance

- Verify SectorMark uses `.innerRadius(.ratio(0.62))` for donut effect.
- Verify `chartEligibleSets()` is applied (excludes warmup/partial).
- Verify exercise cache prevents N+1 queries.
- Verify "Other" bucket aggregation is correct.
- Verify chart palette colors match design system accent colors.
- Verify summary stats are computed for the selected time range.

## Activity Log
