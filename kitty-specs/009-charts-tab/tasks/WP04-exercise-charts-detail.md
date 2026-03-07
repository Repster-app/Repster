---
work_package_id: "WP04"
subtasks:
  - "T020"
  - "T021"
  - "T022"
  - "T023"
  - "T024"
  - "T025"
  - "T026"
title: "Exercise Charts Detail — Time Range Selector + 4 Chart Types"
phase: "Phase 1 - User Story 3"
lane: "done"
dependencies: ["WP01", "WP03"]
agent: "claude"
assignee: "Magnus Espensen"
shell_pid: "13174"
reviewed_by: "Magnus Espensen"
review_status: "approved"
history:
  - timestamp: "2026-02-27T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-02-28T13:27:10Z"
    lane: "doing"
    agent: "claude"
    shell_pid: "10694"
    action: "Started implementation via workflow command"
  - timestamp: "2026-02-28T13:33:01Z"
    lane: "for_review"
    agent: "claude"
    shell_pid: "10694"
    action: "Ready for review: Exercise charts detail — fetchExerciseDetailCharts with 4 chart datasets, TimeRangeSelector, ExerciseChartsDetailViewModel, TopWeightChart, RepPRProgressionChart, ExerciseChartsDetailView, NavigationLink wiring. Build succeeds with 0 errors."
  - timestamp: "2026-02-28T13:35:03Z"
    lane: "doing"
    agent: "claude"
    shell_pid: "13174"
    action: "Started review via workflow command"
  - timestamp: "2026-02-28T13:35:51Z"
    lane: "done"
    agent: "claude"
    shell_pid: "13174"
    action: "Review passed: fetchExerciseDetailCharts correctly computes 4 datasets. Rep PR uses reps >= targetReps. e1RM/volume charts match ExerciseChartsView styling. changeTimeRange clears data before re-fetch. hasNoData checks all 4 datasets. Build succeeds."
---

# Work Package Prompt: WP04 – Exercise Charts Detail — Time Range Selector + 4 Chart Types

## Objectives & Success Criteria

- Implement exercise detail chart data aggregation in ChartDataService (4 chart datasets from WorkoutSet data).
- Create TimeRangeSelector component ([3M] [6M] [1Y] [All]).
- Create ExerciseChartsDetailViewModel with time range switching and chart data loading.
- Create TopWeightChart and RepPRProgressionChart components.
- Create ExerciseChartsDetailView composing all chart components.
- Wire navigation from exercise cards (WP03) to the detail screen.
- Handle edge cases: empty exercise history, single data point, no data for selected time range.
- **Success**: Tapping an exercise card navigates to detail screen. Time range selector works. 4 charts display. Charts update on range change. Edge cases handled. Detail loads < 200ms after initial compute (SC-002).

## Context & Constraints

- **Spec references**: FR-005 (time range selector), FR-006 (4 chart types), FR-007 (lazy compute), FR-008 (session cache), FR-009 (date-range queries), User Story 3 acceptance scenarios.
- **Existing chart types to reuse**: `ExerciseChartData.ChartPoint` (for e1RM trend) and `ExerciseChartData.VolumePoint` (for volume) from `Reppo/Features/Exercise/Models/ExerciseModels.swift`.
- **Existing chart styling**: Follow `Reppo/Features/Exercise/Views/ExerciseChartsView.swift` — same card layout, axis styling, colors.
- **SetRepository**: WP01 added `fetchSets(exerciseId:from:to:)`.
- **PerformanceRecordRepository**: Has `fetchAll(for exerciseId: UUID, recordType: RecordType)` — use for rep PR records.
- **Rep PR progression**: Build from `WorkoutSet` data, not `PerformanceRecord` (PR records only store current best, not historical progression). See research.md RQ-5.
- **Memory**: Chart data released on navigate away (SC-004). ViewModel is @State-owned by view.

**Implementation command**: `spec-kitty implement WP04 --base WP03`

## Subtasks & Detailed Guidance

### Subtask T020 – Implement ChartDataService.fetchExerciseDetailCharts(exerciseId:range:)

- **Purpose**: Compute all 4 chart datasets for a single exercise within a time range.
- **File**: `Reppo/Core/Services/ChartDataService.swift` (edit — replace stub)
- **Spec**: FR-006, FR-009

**Steps**:
1. Calculate the date range from `TimeRange`:
   ```swift
   let startDate = range.startDate  // nil for .all
   let endDate = Date()
   ```

2. Fetch sets: `let sets = try await setRepository.fetchSets(exerciseId: exerciseId, from: startDate, to: endDate)`.

3. Filter: `hasData == true`, exclude `.partial` sets. Optionally exclude `.warmup` (check user settings if accessible, or exclude by default for chart accuracy).

4. Group by `workoutId`:
   ```swift
   let grouped = Dictionary(grouping: filteredSets) { $0.workoutId }
   ```

5. Build each dataset by iterating over workout groups:

   **a. e1RM Trend** (reuses `ExerciseChartData.ChartPoint`):
   ```swift
   var e1rmPoints: [ExerciseChartData.ChartPoint] = []
   for (_, workoutSets) in grouped {
       guard let date = workoutSets.first?.date else { continue }
       if let bestE1RM = workoutSets.compactMap({ $0.e1RM }).filter({ $0 > 0 }).max() {
           e1rmPoints.append(.init(date: date, value: bestE1RM))
       }
   }
   e1rmPoints.sort { $0.date < $1.date }
   ```

   **b. Volume Per Session** (reuses `ExerciseChartData.VolumePoint`):
   ```swift
   var volumePoints: [ExerciseChartData.VolumePoint] = []
   for (_, workoutSets) in grouped {
       guard let date = workoutSets.first?.date else { continue }
       let volume = workoutSets.reduce(0.0) { total, set in
           total + ((set.effectiveWeight ?? 0) * Double(set.reps ?? 0))
       }
       if volume > 0 {
           volumePoints.append(.init(date: date, volume: volume))
       }
   }
   volumePoints.sort { $0.date < $1.date }
   ```

   **c. Top Weight Per Session**:
   ```swift
   var topWeightPoints: [TopWeightPoint] = []
   for (_, workoutSets) in grouped {
       guard let date = workoutSets.first?.date else { continue }
       if let maxWeight = workoutSets.compactMap({ $0.effectiveWeight }).filter({ $0 > 0 }).max() {
           topWeightPoints.append(.init(date: date, weight: maxWeight))
       }
   }
   topWeightPoints.sort { $0.date < $1.date }
   ```

   **d. Rep PR Progression** (multi-line: 1RM, 3RM, 5RM):
   ```swift
   let targetRepCounts = [1, 3, 5]
   var series: [RepSeries] = []

   for targetReps in targetRepCounts {
       var points: [RepPRPoint] = []
       for (_, workoutSets) in grouped {
           guard let date = workoutSets.first?.date else { continue }
           // Find best weight among sets with reps >= targetReps
           let eligible = workoutSets.filter { ($0.reps ?? 0) >= targetReps && ($0.effectiveWeight ?? 0) > 0 }
           if let best = eligible.max(by: { ($0.effectiveWeight ?? 0) < ($1.effectiveWeight ?? 0) }) {
               points.append(.init(date: date, weight: best.effectiveWeight ?? 0))
           }
       }
       points.sort { $0.date < $1.date }
       if !points.isEmpty {
           series.append(RepSeries(
               reps: targetReps,
               label: "\(targetReps)RM",
               points: points
           ))
       }
   }
   ```

6. Assemble and return:
   ```swift
   return ExerciseDetailChartData(
       e1RMTrend: e1rmPoints,
       volumePerSession: volumePoints,
       topWeightPerSession: topWeightPoints,
       repPRProgression: RepPRProgressionData(series: series)
   )
   ```

**Edge cases**:
- Exercise with no sets in range → all arrays empty.
- Exercise with only duration tracking → e1RM, volume, top weight all empty. Only rep PR might have data if the exercise has reps.
- Sessions where exercise wasn't done at 1 rep → 1RM series has no point for that session (gap in line is OK).

**Validation**:
- e1RM points match max e1RM per session.
- Volume sums are correct per session.
- Top weight matches max effectiveWeight per session.
- Rep PR series only include sessions where the exercise was actually done at that rep count or higher.

---

### Subtask T021 – Create TimeRangeSelector.swift

- **Purpose**: Horizontal segmented picker for time range selection.
- **File**: `Reppo/Features/Charts/Views/Components/TimeRangeSelector.swift` (new file)
- **Parallel?**: Yes — pure view component.

**Steps**:
1. Create a horizontal button row:
```swift
import SwiftUI

struct TimeRangeSelector: View {
    @Binding var selectedRange: TimeRange

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedRange == range ? Color.white : Color.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedRange == range ? Color.accent : Color.bgCard)
                        .cornerRadius(10)
                }
            }
        }
    }
}
```

2. Selected state: accent background with white text. Unselected: bgCard background with textSecondary.
3. Corner radius matches design system `rSm` (10pt).
4. Minimum tap target: 44pt height (8pt padding + 13pt font + 8pt padding = ~29pt — add more vertical padding or set `.frame(minHeight: 44)`).

**Validation**:
- Shows 4 buttons: 3M, 6M, 1Y, All.
- Selected button is visually highlighted.
- Tapping changes the binding.
- Meets 44pt minimum tap target.

---

### Subtask T022 – Create ExerciseChartsDetailViewModel.swift

- **Purpose**: @Observable ViewModel for the exercise detail screen. Manages time range selection and chart data loading.
- **File**: `Reppo/Features/Charts/ViewModels/ExerciseChartsDetailViewModel.swift` (new file)

**Steps**:
1. Create the ViewModel:
```swift
import SwiftUI

@Observable
final class ExerciseChartsDetailViewModel {

    // MARK: - State
    let exerciseId: UUID
    var exerciseName: String = ""
    var selectedTimeRange: TimeRange = .sixMonths
    var chartData: ExerciseDetailChartData?
    var isLoading: Bool = false

    var hasNoData: Bool {
        guard let data = chartData else { return false }
        return data.e1RMTrend.isEmpty &&
               data.volumePerSession.isEmpty &&
               data.topWeightPerSession.isEmpty &&
               data.repPRProgression.series.isEmpty
    }

    // MARK: - Dependencies
    private let chartDataService: any ChartDataServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol

    init(exerciseId: UUID,
         chartDataService: any ChartDataServiceProtocol,
         exerciseService: any ExerciseServiceProtocol) {
        self.exerciseId = exerciseId
        self.chartDataService = chartDataService
        self.exerciseService = exerciseService
    }

    // MARK: - Data Loading

    func loadCharts() async {
        isLoading = true
        do {
            // Load exercise name
            if exerciseName.isEmpty {
                if let exercise = try await exerciseService.fetchExercise(exerciseId) {
                    exerciseName = exercise.name
                }
            }

            // Load chart data
            chartData = try await chartDataService.fetchExerciseDetailCharts(
                exerciseId: exerciseId,
                range: selectedTimeRange
            )
        } catch {
            print("[ExerciseChartsDetail] Failed to load charts: \(error)")
        }
        isLoading = false
    }

    func changeTimeRange(_ range: TimeRange) async {
        guard range != selectedTimeRange else { return }
        selectedTimeRange = range
        chartData = nil  // Clear previous data
        await loadCharts()
    }
}
```

2. Default time range is `.sixMonths` (per plan.md).
3. `changeTimeRange()` clears existing data before re-fetching — ensures the view shows loading state.
4. `hasNoData` computed property checks if all chart datasets are empty (for the "no data for this period" state).

**Validation**:
- ViewModel loads chart data on `loadCharts()`.
- Time range change triggers re-fetch with new range.
- Exercise name is loaded once and cached.

---

### Subtask T023 – Create TopWeightChart.swift

- **Purpose**: Line chart showing the maximum weight (effectiveWeight) lifted per session over time.
- **File**: `Reppo/Features/Charts/Views/Components/TopWeightChart.swift` (new file)
- **Parallel?**: Yes — pure view component.

**Steps**:
1. Create the component following the same card styling as ExerciseChartsView:
```swift
import SwiftUI
import Charts

struct TopWeightChart: View {
    let data: [TopWeightPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP WEIGHT PER SESSION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            Chart(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Weight", point.weight)
                )
                .foregroundStyle(Color.gold)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Weight", point.weight)
                )
                .foregroundStyle(Color.gold)
                .symbolSize(20)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.border)
                    AxisValueLabel()
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.border)
                    AxisValueLabel()
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(14)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}
```

2. Uses `Color.gold` to differentiate from e1RM chart (blue/accent) and volume chart (blue bars).
3. LineMark + PointMark pattern matches existing ExerciseChartsView e1RM chart.
4. Same axis styling and card dimensions.

**Validation**:
- Line chart renders with gold color.
- Points show at each data value.
- Axis labels are readable on dark background.

---

### Subtask T024 – Create RepPRProgressionChart.swift

- **Purpose**: Multi-line chart showing weight progression for 1RM, 3RM, and 5RM over time.
- **File**: `Reppo/Features/Charts/Views/Components/RepPRProgressionChart.swift` (new file)
- **Parallel?**: Yes — pure view component.

**Steps**:
1. Create a multi-series line chart:
```swift
import SwiftUI
import Charts

struct RepPRProgressionChart: View {
    let data: RepPRProgressionData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REP PR PROGRESSION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            if data.series.isEmpty {
                emptyState
            } else {
                Chart {
                    ForEach(data.series) { series in
                        ForEach(series.points) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Weight", point.weight)
                            )
                            .foregroundStyle(by: .value("Series", series.label))

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Weight", point.weight)
                            )
                            .foregroundStyle(by: .value("Series", series.label))
                            .symbolSize(16)
                        }
                    }
                }
                .frame(height: 200)
                .chartForegroundStyleScale([
                    "1RM": Color.danger,
                    "3RM": Color.accent,
                    "5RM": Color.success
                ])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.border)
                        AxisValueLabel()
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.border)
                        AxisValueLabel()
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    private var emptyState: some View {
        Text("Not enough data for rep progression")
            .font(.caption)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}
```

2. **Color coding**: 1RM = red (danger), 3RM = blue (accent), 5RM = green (success). Uses `.chartForegroundStyleScale()` for consistent mapping.
3. **Legend**: Positioned at bottom, shows series labels with colors.
4. Each series may have different numbers of points (not every session has 1-rep or 5-rep sets). Lines connect available points — gaps are expected.
5. If no series have data, show an inline empty state message.

**Validation**:
- Up to 3 colored lines render correctly.
- Legend shows at bottom with correct labels and colors.
- Series with no data are omitted (not shown in legend).
- Single-point series shows as a dot.

---

### Subtask T025 – Create ExerciseChartsDetailView.swift

- **Purpose**: Main detail screen composing TimeRangeSelector + 4 chart types in a ScrollView.
- **File**: `Reppo/Features/Charts/Views/ExerciseChartsDetailView.swift` (new file)

**Steps**:
1. Create the view:
```swift
import SwiftUI
import Charts

struct ExerciseChartsDetailView: View {

    @State private var viewModel: ExerciseChartsDetailViewModel

    init(exerciseId: UUID,
         chartDataService: any ChartDataServiceProtocol,
         exerciseService: any ExerciseServiceProtocol) {
        _viewModel = State(initialValue: ExerciseChartsDetailViewModel(
            exerciseId: exerciseId,
            chartDataService: chartDataService,
            exerciseService: exerciseService
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Time Range Selector
                TimeRangeSelector(selectedRange: Binding(
                    get: { viewModel.selectedTimeRange },
                    set: { newRange in
                        Task { await viewModel.changeTimeRange(newRange) }
                    }
                ))
                .padding(.horizontal, 20)

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if viewModel.hasNoData {
                    noDataState
                } else if let data = viewModel.chartData {
                    chartContent(data)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color.bg)
        .navigationTitle(viewModel.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadCharts()
        }
    }

    // MARK: - Chart Content

    @ViewBuilder
    private func chartContent(_ data: ExerciseDetailChartData) -> some View {
        VStack(spacing: 16) {
            // e1RM Trend (reuse styling from ExerciseChartsView)
            if !data.e1RMTrend.isEmpty {
                e1rmChart(data.e1RMTrend)
            }

            // Volume Per Session
            if !data.volumePerSession.isEmpty {
                volumeChart(data.volumePerSession)
            }

            // Top Weight Per Session
            if !data.topWeightPerSession.isEmpty {
                TopWeightChart(data: data.topWeightPerSession)
            }

            // Rep PR Progression
            RepPRProgressionChart(data: data.repPRProgression)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Inline Charts (reuse pattern from ExerciseChartsView)

    // ... e1rmChart and volumeChart follow same pattern as ExerciseChartsView
    // Copy the chart rendering logic from ExerciseChartsView for consistency

    // MARK: - Empty State

    private var noDataState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("No data for this period")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
```

2. **e1RM and volume charts**: Replicate the chart rendering from `ExerciseChartsView.swift` (same LineMark/BarMark pattern, same styling). Copy the private chart functions directly — they render the same way but with time-range-filtered data.
3. **Layout**: ScrollView → VStack → TimeRangeSelector → charts (conditionally shown based on data availability).
4. **Navigation title**: Shows exercise name. `.navigationBarTitleDisplayMode(.inline)`.
5. **Loading state**: ProgressView while fetching.
6. **Empty state**: "No data for this period" when `hasNoData` is true.
7. Each chart section is conditionally rendered — if e1RM data is empty, that chart is hidden. RepPRProgressionChart handles its own empty state internally.

**Validation**:
- All 4 charts render with data.
- Empty charts are hidden (not shown as empty cards).
- Time range selector is at the top.
- Exercise name shows in navigation title.
- Loading state shows during fetch.

---

### Subtask T026 – Wire Navigation + Edge Cases

- **Purpose**: Connect ExerciseChartCard navigation to the detail screen. Handle all edge cases from the spec.
- **Files**: `Reppo/Features/Charts/Views/ChartsDashboardView.swift` (edit)

**Steps**:
1. Update the NavigationLink in ChartsDashboardView (from WP03's T018) to push `ExerciseChartsDetailView`:
   ```swift
   NavigationLink {
       ExerciseChartsDetailView(
           exerciseId: card.id,
           chartDataService: viewModel.chartDataService,
           exerciseService: viewModel.exerciseService
       )
   } label: {
       ExerciseChartCard(data: card)
   }
   .buttonStyle(.plain)
   ```

2. **Problem**: The ViewModel currently only has `chartDataService` as a dependency. To pass `exerciseService` to the detail view, either:
   - a. Add `exerciseService` as a dependency on `ChartsDashboardViewModel` (recommended — matches existing pattern).
   - b. Or pass it via init of ChartsDashboardView from ContentView.

   Choose option (a): Add `exerciseService: any ExerciseServiceProtocol` to `ChartsDashboardViewModel` init, pass from `ServiceContainer` in `ChartsDashboardView` init, and expose for the NavigationLink.

3. Update `ChartsDashboardView` init to accept both services:
   ```swift
   init(chartDataService: any ChartDataServiceProtocol,
        exerciseService: any ExerciseServiceProtocol) {
       _viewModel = State(initialValue: ChartsDashboardViewModel(
           chartDataService: chartDataService,
           exerciseService: exerciseService
       ))
   }
   ```

4. Update `ContentView.swift` to pass both services:
   ```swift
   ChartsDashboardView(
       chartDataService: services.chartDataService,
       exerciseService: services.exerciseService
   )
   ```

5. **Edge cases** (from spec):
   - Exercise with no history → detail shows "No data for this period" empty state.
   - Single data point → chart shows the point, no trendline. LineMark with a single point renders as just a dot.
   - Time range with no data (e.g., [3M] but exercise not performed in 3 months) → "No data for this period".
   - Charts tab with no workouts at all → handled in WP02 (motivational empty state on dashboard).

**Validation**:
- Tapping exercise card navigates to ExerciseChartsDetailView.
- Exercise name shows in navigation title.
- Changing time range re-fetches and updates charts.
- All edge cases handled per spec.
- Back navigation returns to dashboard.
- Bottom navigation is hidden on detail screen (NavigationStack push handles this automatically when within TabView).

---

## Risks & Mitigations

- **Rep PR progression sparse data**: Not every session has 1-rep, 3-rep, and 5-rep sets. Lines will have gaps — this is expected and OK. The legend still shows all available series.
- **Time range [All] performance**: For a heavily used exercise (~300+ sessions), fetching all sets is still bounded per exercise. Should be fast.
- **Service dependency threading**: `ChartsDashboardViewModel` needs both `chartDataService` and `exerciseService`. Update both init and ContentView wiring. This is a small but critical change.
- **Chart y-axis auto-scaling**: Swift Charts auto-scales axes. For the multi-line rep PR chart, all series share the same y-axis, which is correct (they represent the same metric: weight).

## Definition of Done Checklist

- [ ] `fetchExerciseDetailCharts()` computes 4 chart datasets correctly
- [ ] `TimeRangeSelector` renders 4 buttons with selection state
- [ ] `ExerciseChartsDetailViewModel` loads charts and handles time range changes
- [ ] `TopWeightChart` renders line chart with gold color
- [ ] `RepPRProgressionChart` renders multi-line with legend and color coding
- [ ] `ExerciseChartsDetailView` composes all components correctly
- [ ] Navigation from exercise card to detail screen works
- [ ] Time range change re-fetches and updates all charts
- [ ] Empty state: "No data for this period" when no data in range
- [ ] Single data point shows as dot without trend line
- [ ] Exercise with no history shows empty state
- [ ] ContentView passes both services to ChartsDashboardView
- [ ] Bottom navigation hidden on detail screen
- [ ] Detail loads < 200ms after initial computation (SC-002)
- [ ] App compiles without errors

## Review Guidance

- Verify rep PR progression uses `reps >= targetReps` (not strict equality) — a 5-rep set also qualifies for the "5RM" line.
- Verify e1RM and volume chart rendering matches the style of existing `ExerciseChartsView.swift`.
- Verify `changeTimeRange()` clears previous data before re-fetch (shows loading state, not stale data).
- Verify NavigationLink uses `.buttonStyle(.plain)` to prevent default styling.
- Verify time range "All" passes `nil` as start date to the repository method.
- Verify `hasNoData` checks all 4 datasets, not just one.
- Check that warmup and partial sets are excluded from chart calculations.
- Verify ServiceContainer wiring change doesn't break other views.

## Activity Log

- 2026-02-28T13:27:10Z – claude – shell_pid=10694 – lane=doing – Started implementation via workflow command
- 2026-02-28T13:33:01Z – claude – shell_pid=10694 – lane=for_review – Ready for review: Exercise charts detail — fetchExerciseDetailCharts with 4 chart datasets (e1RM, volume, top weight, rep PR progression), TimeRangeSelector [3M/6M/1Y/All], ExerciseChartsDetailViewModel with range switching, TopWeightChart + RepPRProgressionChart components, ExerciseChartsDetailView, and NavigationLink wiring from exercise cards to detail. exerciseService added to ViewModel/View/ContentView chain. Build succeeds with 0 errors.
- 2026-02-28T13:35:03Z – claude – shell_pid=13174 – lane=doing – Started review via workflow command
- 2026-02-28T13:35:51Z – claude – shell_pid=13174 – lane=done – Review passed: fetchExerciseDetailCharts correctly computes 4 datasets with chartEligibleSets filtering. Rep PR uses reps >= targetReps (not strict equality). e1RM/volume charts match ExerciseChartsView styling exactly. changeTimeRange clears data before re-fetch. hasNoData checks all 4 datasets. TimeRange.all passes nil startDate. NavigationLink uses .buttonStyle(.plain). ContentView wiring clean. Build succeeds.
