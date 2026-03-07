---
work_package_id: "WP02"
subtasks:
  - "T008"
  - "T009"
  - "T010"
  - "T011"
  - "T012"
  - "T013"
  - "T014"
title: "Overview Dashboard — Weekly Volume, Training Frequency, Muscle Group Distribution"
phase: "Phase 1 - User Story 1"
lane: "done"
dependencies: ["WP01"]
agent: "claude"
assignee: "Magnus Espensen"
shell_pid: "93884"
reviewed_by: "Magnus Espensen"
review_status: "approved"
history:
  - timestamp: "2026-02-27T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-02-28T08:24:20Z"
    lane: "doing"
    agent: "claude"
    shell_pid: "91411"
    action: "Started implementation via workflow command"
  - timestamp: "2026-02-28T08:33:00Z"
    lane: "for_review"
    agent: "claude"
    shell_pid: "91411"
    action: "Ready for review: Overview dashboard charts — all 3 service methods, 3 chart views, ViewModel wiring, and empty state implemented. Build succeeds with 0 errors."
  - timestamp: "2026-02-28T08:37:59Z"
    lane: "doing"
    agent: "claude"
    shell_pid: "93884"
    action: "Started review via workflow command"
  - timestamp: "2026-02-28T13:25:49Z"
    lane: "done"
    agent: "claude"
    shell_pid: "93884"
    action: "Review passed: All 3 overview chart service methods correctly implemented with hasData filtering, ISO week zero-fill, exercise cache. Chart views match ExerciseChartsView styling. Build succeeds."
---

# Work Package Prompt: WP02 – Overview Dashboard — Weekly Volume, Training Frequency, Muscle Group Distribution

## Objectives & Success Criteria

- Implement the 3 overview chart data aggregation methods in ChartDataService.
- Create 3 chart view components using Swift Charts (BarMark, LineMark).
- Wire overview data loading into ChartsDashboardViewModel and render charts in ChartsDashboardView.
- Handle empty state when no workout history exists.
- **Success**: Charts tab OVERVIEW section shows 3 charts with real data. Weekly volume shows 12 bars (one per week). Frequency shows sessions per week. Muscle group shows distribution. Empty state displays when no data. Charts render < 1 second (SC-001).

## Context & Constraints

- **Spec references**: FR-001 (weekly volume, 12 weeks), FR-002 (training frequency), FR-003 (muscle groups, 4 weeks), FR-007 (lazy compute), FR-009 (date-range only), FR-010 (Swift Charts).
- **Performance**: specdoc S8.10 — lazy compute, session cache. S8.6 — in-memory aggregation acceptable for bounded date ranges.
- **Existing chart styling**: Follow the card-based pattern from `Reppo/Features/Exercise/Views/ExerciseChartsView.swift` — `bgCard` background, `padding(14)`, `cornerRadius(14)`, axis styling with `Color.border` grid lines and `Color.textTertiary` labels.
- **MuscleGroupColors**: Reuse `Reppo/Core/Extensions/MuscleGroupColors.swift` from Calendar feature for muscle group chart colors.
- **WorkoutRepository**: Already has `fetchWorkouts(for: ClosedRange<Date>)`.
- **SetRepository**: WP01 added `fetchSets(from:to:)`.
- **ExerciseRepository**: Has `fetch(byId:)` for exercise lookup.

**Implementation command**: `spec-kitty implement WP02 --base WP01`

## Subtasks & Detailed Guidance

### Subtask T008 – Implement ChartDataService.fetchWeeklyVolume(weeks:)

- **Purpose**: Compute total training volume per week for the last N weeks. Returns one data point per week.
- **File**: `Reppo/Core/Services/ChartDataService.swift` (edit — replace stub)
- **Spec**: FR-001 — weekly volume bar chart, last 12 weeks.

**Steps**:
1. Calculate the cutoff date: `N weeks ago from today`.
2. Fetch sets via `setRepository.fetchSets(from: cutoffDate, to: Date())`.
3. Filter in Swift: only sets where `hasData` is true (computed property — can't be in predicate).
4. Also filter out warmup sets if `setType == .warmup` (volume typically excludes warmups per constitution). Filter out `.partial` sets (always excluded from volume per specdoc S1.3).
5. Group sets by ISO week using `Calendar.current`:
   ```swift
   let calendar = Calendar.current
   let grouped = Dictionary(grouping: filteredSets) { set in
       calendar.startOfDay(for: calendar.dateInterval(of: .weekOfYear, for: set.date)!.start)
   }
   ```
6. For each week group, sum volume: `effectiveWeight × reps` for each set.
7. **Fill zero-value weeks**: Iterate from the earliest week to the current week. For any week with no data, insert a `WeeklyVolumePoint(weekStart:, volume: 0)`. This ensures the bar chart has a continuous x-axis.
8. Sort by `weekStart` ascending and return.

**Edge cases**:
- No sets in range → return array of 12 zero-value weeks.
- Sets with `effectiveWeight == nil` or `reps == nil` → skip (already filtered by hasData).

**Validation**:
- Returns exactly N weekly data points (including zero-filled weeks).
- Volume sums are correct per week.

---

### Subtask T009 – Implement ChartDataService.fetchTrainingFrequency(weeks:)

- **Purpose**: Count workout sessions per week for the last N weeks.
- **File**: `Reppo/Core/Services/ChartDataService.swift` (edit — replace stub)
- **Spec**: FR-002 — training frequency, sessions per week.

**Steps**:
1. Calculate cutoff date: N weeks ago.
2. Fetch workouts via `workoutRepository.fetchWorkouts(for: cutoffDate...Date())`.
3. Group workouts by ISO week (same approach as T008):
   ```swift
   let grouped = Dictionary(grouping: workouts) { workout in
       calendar.startOfDay(for: calendar.dateInterval(of: .weekOfYear, for: workout.date)!.start)
   }
   ```
4. Count workouts per week.
5. Fill zero-value weeks (weeks with 0 sessions).
6. Sort by `weekStart` ascending and return.

**Edge cases**:
- Weeks with no workouts → `sessions: 0`.
- Multiple workouts on the same day → each counts as a separate session.

**Validation**:
- Returns exactly N weekly data points.
- Session counts match actual workout count per week.

---

### Subtask T010 – Implement ChartDataService.fetchMuscleGroupDistribution(weeks:)

- **Purpose**: Compute total volume per primary muscle group for the last N weeks.
- **File**: `Reppo/Core/Services/ChartDataService.swift` (edit — replace stub)
- **Spec**: FR-003 — muscle group distribution, last 4 weeks. Primary muscle only (per planning decision).

**Steps**:
1. Calculate cutoff date: N weeks ago.
2. Fetch sets via `setRepository.fetchSets(from: cutoffDate, to: Date())`.
3. Filter: `hasData == true`, exclude `.warmup` and `.partial` sets.
4. Build exercise cache to avoid N+1 queries:
   ```swift
   let exerciseIds = Set(filteredSets.map { $0.exerciseId })
   var exerciseCache: [UUID: Exercise] = [:]
   for id in exerciseIds {
       if let exercise = try await exerciseRepository.fetch(byId: id) {
           exerciseCache[id] = exercise
       }
   }
   ```
5. Group volume by `Exercise.primaryMuscle`:
   ```swift
   var volumeByMuscle: [String: Double] = [:]
   for set in filteredSets {
       guard let exercise = exerciseCache[set.exerciseId],
             let muscle = exercise.primaryMuscle else { continue }
       let volume = (set.effectiveWeight ?? 0) * Double(set.reps ?? 0)
       volumeByMuscle[muscle, default: 0] += volume
   }
   ```
6. Map to `MuscleGroupVolume` with colors from `MuscleGroupColors.color(for:)`.
7. Sort by volume descending and return.

**Edge cases**:
- Exercises with no `primaryMuscle` → skip (excluded from distribution).
- Duration-only exercises (no weight) → volume is 0, effectively excluded.

**Validation**:
- Returns muscle groups sorted by volume descending.
- Colors match MuscleGroupColors mapping.
- Sum of all muscle volumes approximately equals total training volume for the period.

---

### Subtask T011 – Create WeeklyVolumeChart.swift

- **Purpose**: Bar chart showing weekly training volume for the last 12 weeks.
- **File**: `Reppo/Features/Charts/Views/Components/WeeklyVolumeChart.swift` (new file)
- **Parallel?**: Yes — pure view component.

**Steps**:
1. Create the component:
```swift
import SwiftUI
import Charts

struct WeeklyVolumeChart: View {
    let data: [WeeklyVolumePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WEEKLY VOLUME")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            Chart(data) { point in
                BarMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Volume", point.volume)
                )
                .foregroundStyle(Color.accent.opacity(0.7))
            }
            .frame(height: 200)
            .chartYAxis { /* standard axis styling */ }
            .chartXAxis { /* week labels */ }
        }
        .padding(14)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}
```
2. Follow the exact axis styling from `ExerciseChartsView.swift`: `AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))` with `Color.border`, `AxisValueLabel()` with `Color.textTertiary`.
3. X-axis: Show abbreviated week dates (e.g., "Jan 6", "Jan 13"). Use `.chartXAxis` with date formatting.
4. Y-axis: Volume in the user's preferred unit. Position on leading side.

**Validation**:
- Renders 12 bars (one per week).
- Zero-volume weeks show no bar (or tiny bar).
- Chart fits within the card.

---

### Subtask T012 – Create TrainingFrequencyChart.swift

- **Purpose**: Chart showing training sessions per week.
- **File**: `Reppo/Features/Charts/Views/Components/TrainingFrequencyChart.swift` (new file)
- **Parallel?**: Yes — pure view component.

**Steps**:
1. Create a bar or line chart showing sessions/week:
```swift
import SwiftUI
import Charts

struct TrainingFrequencyChart: View {
    let data: [WeeklyFrequencyPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRAINING FREQUENCY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            Chart(data) { point in
                BarMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Sessions", point.sessions)
                )
                .foregroundStyle(Color.success.opacity(0.7))
            }
            .frame(height: 160)
            .chartYAxis { /* axis: integer scale */ }
            .chartXAxis { /* week labels */ }
        }
        .padding(14)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}
```
2. Use `Color.success` (green) to differentiate from volume chart (blue).
3. Y-axis should use integer scale (sessions are whole numbers). Use `.chartYScale(domain:)` if needed.
4. Same axis styling pattern as WeeklyVolumeChart.

**Validation**:
- Renders bars with integer session counts.
- Green color distinguishes it from volume chart.

---

### Subtask T013 – Create MuscleGroupDistributionChart.swift

- **Purpose**: Horizontal bar chart showing volume by muscle group for the last 4 weeks.
- **File**: `Reppo/Features/Charts/Views/Components/MuscleGroupDistributionChart.swift` (new file)
- **Parallel?**: Yes — pure view component.

**Steps**:
1. Create a horizontal bar chart sorted by volume:
```swift
import SwiftUI
import Charts

struct MuscleGroupDistributionChart: View {
    let data: [MuscleGroupVolume]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MUSCLE GROUPS (4 WEEKS)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            Chart(data) { item in
                BarMark(
                    x: .value("Volume", item.volume),
                    y: .value("Muscle", item.muscleGroup)
                )
                .foregroundStyle(item.color)
            }
            .frame(height: max(CGFloat(data.count) * 36, 120))
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel()
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
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
2. Horizontal bars: x = volume, y = muscle group name. Each bar colored by `MuscleGroupColors`.
3. Height scales with number of muscle groups (36pt per row, minimum 120pt).
4. Y-axis shows muscle group names. X-axis shows volume values.

**Validation**:
- Bars are colored per muscle group.
- Sorted by volume descending (highest volume muscle group at top).
- Renders cleanly with 4-8 muscle groups.

---

### Subtask T014 – Implement ViewModel.loadOverview() + Wire Overview Section

- **Purpose**: Connect ChartDataService to the ViewModel and render overview charts in ChartsDashboardView.
- **Files**: `Reppo/Features/Charts/ViewModels/ChartsDashboardViewModel.swift` (edit), `Reppo/Features/Charts/Views/ChartsDashboardView.swift` (edit)

**Steps**:
1. In `ChartsDashboardViewModel`, implement `loadOverview()`:
   ```swift
   func loadOverview() async {
       guard !overviewLoaded else { return }
       do {
           let volume = try await chartDataService.fetchWeeklyVolume(weeks: 12)
           let frequency = try await chartDataService.fetchTrainingFrequency(weeks: 12)
           let muscles = try await chartDataService.fetchMuscleGroupDistribution(weeks: 4)
           overviewData = OverviewChartData(
               weeklyVolume: volume,
               trainingFrequency: frequency,
               muscleGroupDistribution: muscles
           )
           overviewLoaded = true
       } catch {
           print("[ChartsDashboard] Failed to load overview: \(error)")
       }
   }
   ```

2. In `ChartsDashboardView`, replace the overview placeholder with the 3 chart components:
   ```swift
   @ViewBuilder
   private var overviewSection: some View {
       Text("OVERVIEW")
           .font(.system(size: 11, weight: .semibold))
           .foregroundStyle(Color.textTertiary)
           .kerning(0.8)

       if let data = viewModel.overviewData {
           WeeklyVolumeChart(data: data.weeklyVolume)
           TrainingFrequencyChart(data: data.trainingFrequency)
           if !data.muscleGroupDistribution.isEmpty {
               MuscleGroupDistributionChart(data: data.muscleGroupDistribution)
           }
       } else if viewModel.isLoading {
           ProgressView()
               .frame(maxWidth: .infinity, minHeight: 200)
       } else {
           // Empty state — no workout history
           emptyOverviewState
       }
   }
   ```

3. Add the motivational empty state view:
   ```swift
   private var emptyOverviewState: some View {
       VStack(spacing: 12) {
           Image(systemName: "chart.bar.fill")
               .font(.system(size: 36))
               .foregroundStyle(Color.textTertiary)
           Text("Start your first workout to see progress charts")
               .font(.subheadline)
               .foregroundStyle(Color.textTertiary)
               .multilineTextAlignment(.center)
       }
       .frame(maxWidth: .infinity)
       .padding(.vertical, 40)
   }
   ```

**Validation**:
- Overview section shows 3 charts with real data from workouts.
- Empty state shows when no workout history exists.
- Loading indicator shows during data fetch.
- Charts render within 1 second (SC-001).

---

## Risks & Mitigations

- **ISO week edge cases**: The first/last week of a year may span two years. Use `Calendar.current.dateInterval(of: .weekOfYear, for:)` which handles this correctly.
- **Zero-fill week generation**: Generate all weeks from cutoff to current date, then merge with actual data. Don't rely on data alone to determine the week list.
- **Exercise cache memory**: Building `[UUID: Exercise]` for all exercises in the 4-week range is bounded (typically 20-50 exercises). Acceptable.
- **Unit conversion**: Charts display raw metric values (kg). For user-facing labels, apply unit conversion in the view layer if needed.

## Definition of Done Checklist

- [ ] `fetchWeeklyVolume()` returns 12 weekly data points with zero-filling
- [ ] `fetchTrainingFrequency()` returns 12 weekly session counts with zero-filling
- [ ] `fetchMuscleGroupDistribution()` returns muscle groups sorted by volume, colored correctly
- [ ] `WeeklyVolumeChart` renders 12-week bar chart with accent color
- [ ] `TrainingFrequencyChart` renders session count bars with success color
- [ ] `MuscleGroupDistributionChart` renders horizontal bars with per-muscle colors
- [ ] Overview section shows all 3 charts in ChartsDashboardView
- [ ] Empty state displays when no workout data exists
- [ ] App compiles without errors
- [ ] Charts render within 1 second on test data

## Review Guidance

- Verify `hasData` filtering happens in Swift (not in predicate) since it's a computed property.
- Verify warmup and partial sets are excluded from volume calculations.
- Verify zero-week filling produces exactly N weeks of data.
- Verify chart styling matches existing ExerciseChartsView pattern (bgCard, cornerRadius 14, axis styling).
- Verify MuscleGroupColors is reused (not duplicated).
- Verify `loadOverview()` has a guard against re-loading (`overviewLoaded`).

## Activity Log

- 2026-02-28T08:24:20Z – claude – shell_pid=91411 – lane=doing – Started implementation via workflow command
- 2026-02-28T08:33:00Z – claude – shell_pid=91411 – lane=for_review – Ready for review: Overview dashboard charts — weekly volume, training frequency, muscle group distribution. All 3 service methods, 3 chart views, ViewModel wiring, and empty state implemented. Build succeeds with 0 errors.
- 2026-02-28T08:37:59Z – claude – shell_pid=93884 – lane=doing – Started review via workflow command
- 2026-02-28T13:25:49Z – claude – shell_pid=93884 – lane=done – Review passed: All 3 overview chart service methods correctly implemented with hasData + warmup/partial filtering in Swift, ISO week grouping with zero-fill, exercise cache for N+1 prevention. Chart views match ExerciseChartsView styling (bgCard, padding 14, cornerRadius 14). MuscleGroupColors reused. ViewModel loadOverview guard present. Empty state implemented. Build succeeds.
