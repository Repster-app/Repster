# Work Packages: Charts Tab v2 — 3-Tab Redesign

**Inputs**: `kitty-specs/016-charts-tab-v2/` — spec.md, plan.md, data-model.md, research.md
**Prerequisites**: 009-charts-tab (completed — existing ChartDataService and models)
**Tests**: Manual testing only (per AGENT_RULES — no automated tests for v1).
**Prototype**: `prototype-charts-tab.html`

**Organization**: Fine-grained subtasks (`Txxx`) roll up into work packages (`WPxx`). Each work package must be independently deliverable and testable.

## Subtask Format: `[Txxx] [P?] Description`
- **[P]** indicates the subtask can proceed in parallel (different files/components).

---

## Work Package WP05: Foundation — New Models, Enums, 3-Tab Shell, Shared Components (Priority: P0)

**Goal**: Add all new enum/struct types to ChartModels, create the 3-tab container view and coordinator ViewModel, create shared reusable components (dropdown, time pills, trend line calculator, data point navigator), and wire into ContentView.
**Independent Test**: Charts tab now shows a 3-tab picker (Breakdown/Workouts/Exercises). Each tab shows a placeholder "Coming soon" message. Shared components render in isolation. All new types compile.
**Estimated prompt size**: ~500 lines

### Included Subtasks

- [ ] T101 [P] Add new enums to `ChartModels.swift` — `BreakdownMetric`, `BreakdownGroupBy`, `BreakdownAggregateType`, `BreakdownTimeRange`, `WorkoutsMetric`, `WorkoutsAggregation`, `WorkoutsFilter`, `WorkoutsTimeRange`, `ExerciseMetric`
- [ ] T102 [P] Add new structs to `ChartModels.swift` — `BreakdownDataPoint`, `WorkoutsTimeSeriesPoint`, `ExerciseProgressSeries`, `ExerciseProgressPoint`, `TrendLineData`
- [ ] T103 [P] Create `Reppo/Core/Utilities/TrendLineCalculator.swift` — static linear regression function returning `TrendLineData?`
- [ ] T104 Create `Reppo/Features/Charts/ViewModels/ChartsTabViewModel.swift` — coordinator VM with SubTab enum, 3 child VM stubs
- [ ] T105 Create `Reppo/Features/Charts/Views/ChartsTabView.swift` — NavigationStack + sub-tab picker + tab content switching
- [ ] T106 [P] Create `Reppo/Features/Charts/Views/Components/ChartSubTabPicker.swift` — horizontal pill bar (Breakdown/Workouts/Exercises)
- [ ] T107 [P] Create `Reppo/Features/Charts/Views/Components/ChartDropdown.swift` — generic reusable dropdown picker
- [ ] T108 [P] Create `Reppo/Features/Charts/Views/Components/ChartTimePills.swift` — generic time range pill bar
- [ ] T109 [P] Create `Reppo/Features/Charts/Views/Components/DataPointNavigator.swift` — ← → arrows with value/date display
- [ ] T110 [P] Create `Reppo/Features/Charts/Views/Components/TrendLineOverlay.swift` — dotted line + slope badge component
- [ ] T111 [P] Create `Reppo/Features/Charts/Views/Components/ChartLegend.swift` — color-coded legend (donut segments, line series)
- [ ] T112 Update `ContentView.swift` — replace `ChartsDashboardView` with `ChartsTabView` in the Charts tab

### Implementation Notes
- T101 and T102 are pure model additions to the existing file — append below existing types, don't modify existing types yet.
- T103 is a standalone utility with no dependencies.
- T104 depends on T101 (uses new enum types for state).
- T105 depends on T104 + T106.
- T106–T111 are independent pure view components — all parallel.
- T112 is a small edit to swap the Charts tab view.
- All placeholder views in tabs should show "Select options above" or similar — not an empty/error state.

### Parallel Opportunities
- T101, T102, T103, T106, T107, T108, T109, T110, T111 are all independent files.
- T104 → T105 → T112 are sequential.

### Dependencies
- None (first WP in this spec).

---

## Work Package WP06: Breakdown Tab — Donut Chart + Service Method (Priority: P1)

**Goal**: Implement the Breakdown tab end-to-end: service method for breakdown aggregation, ViewModel with dropdown and time range state, donut chart view (SectorMark), legend, date range label, and summary stats row.
**Independent Test**: Breakdown tab renders a donut chart for "Volume by Category". Switching between all 8 chart type options updates the chart. Time range pills filter data. Legend shows color-coded segments with percentages. Summary stats row shows totals.
**Estimated prompt size**: ~450 lines

### Included Subtasks

- [ ] T113 Add `fetchBreakdownData(metric:timeRange:)` to `ChartDataServiceProtocol` and implement in `ChartDataService`
- [ ] T114 Create `Reppo/Features/Charts/ViewModels/BreakdownTabViewModel.swift` — state for metric, timeRange, chartData, summaryStats, dateRangeLabel; methods: loadData, changeMetric, changeTimeRange
- [ ] T115 [P] Create `Reppo/Features/Charts/Views/Components/DonutChartView.swift` — SectorMark donut chart with inner radius, color per segment, tap interaction
- [ ] T116 Create `Reppo/Features/Charts/Views/BreakdownTabView.swift` — compose dropdown + time pills + donut chart + legend + date range + summary stats
- [ ] T117 Handle edge cases — empty state (no data), "By Exercise" grouping with > 8 items ("Other" bucket), time range with no data

### Implementation Notes
- T113: The service method handles all 8 permutations via `metric.groupBy` and `metric.aggregateType`. For category grouping, use exercise cache pattern from existing `fetchMuscleGroupDistribution()`. For exercise grouping, group by exercise name. Limit to top 8 by value, group remainder as "Other" with gray color.
- T113: Use existing `chartEligibleSets()` filter.
- T114: `dateRangeLabel` is computed from the actual min/max dates in the returned data (e.g., "May 20, 2021 → Mar 4, 2026").
- T114: `summaryStats` includes: total volume, total sets, total reps, total workouts for the selected time range.
- T115: Use `Chart { ForEach(data) { SectorMark(angle:) } }` with `.innerRadius(.ratio(0.62))` for donut effect.
- T115: Colors assigned from a predefined palette (chart-1 through chart-8 matching design tokens).
- T116: Summary stats row uses the same 4-column pattern from existing design system (Section 6.2 Summary Stat Card).
- T117: "By Exercise" with > 8 exercises: sum remaining into "Other" segment.

### Parallel Opportunities
- T115 is a pure view component — can be developed while T113 is in progress.

### Dependencies
- Depends on WP05 (new enums, ChartsTabView shell, shared components).

---

## Work Package WP07: Workouts Tab — Bar Chart + Time Series Service (Priority: P1)

**Goal**: Implement the Workouts tab end-to-end: flexible time-series service method, ViewModel with 3 dropdowns + time range + data point navigation, bar chart with trend line overlay, interactive data point navigator.
**Independent Test**: Workouts tab renders a bar chart for "Volume / Per Month / All". Changing metric/aggregation/filter updates the chart. Trend line with slope badge overlays the bars. ← → arrows navigate data points with value/date display.
**Estimated prompt size**: ~550 lines

### Included Subtasks

- [ ] T118 Add `fetchWorkoutsTimeSeries(metric:aggregation:filter:timeRange:)` to `ChartDataServiceProtocol` and implement in `ChartDataService`
- [ ] T119 Create `Reppo/Features/Charts/ViewModels/WorkoutsTabViewModel.swift` — state for 3 dropdowns, timeRange, chartData, trendLine, selectedDataIndex; methods: loadData, changeMetric, changeAggregation, changeFilter, changeTimeRange, navigateDataPoint
- [ ] T120 [P] Create `Reppo/Features/Charts/Views/Components/TimeSeriesBarChart.swift` — BarMark chart with configurable Y-axis units, RuleMark for trend line, tap-to-select interaction
- [ ] T121 Create `Reppo/Features/Charts/Views/WorkoutsTabView.swift` — compose 3 dropdowns + time pills + bar chart + trend overlay + data point navigator
- [ ] T122 Build filter dropdown data source — fetch available categories (from exercises) and exercise list for the filter dropdown options
- [ ] T123 Handle edge cases — empty state, zero-fill for missing periods, Distance/Time metrics (different Y-axis units), single data point (no trend)

### Implementation Notes
- T118: This is the most complex service method. Internal structure:
  1. Determine date range from `timeRange.startDate`
  2. Fetch sets with optional filter (all sets, or filtered by category/exerciseId)
  3. For category filter: build exercise cache, filter sets where exercise.primaryMuscle matches
  4. Apply `chartEligibleSets()` filter
  5. Bucket by aggregation period:
     - `perWorkout`: group by workoutId, each workout is one bar
     - `perWeek`: group by ISO week start
     - `perMonth`: group by year-month
     - `perYear`: group by year
  6. Compute metric per bucket:
     - `volume`: sum(effectiveWeight × reps)
     - `sets`: count
     - `reps`: sum(reps)
     - `workouts`: count of distinct workoutIds (meaningful for week/month/year)
     - `distance`: sum(distanceMeters)
     - `time`: sum(durationSeconds)
  7. Zero-fill empty periods (for week/month/year aggregation)
  8. Sort chronologically
- T119: `trendLine` computed via `TrendLineCalculator.compute()` from the loaded data points.
- T119: `selectedDataIndex` starts at the latest data point. ← decrements, → increments with bounds checking.
- T120: Y-axis formatting varies by metric: "kg" for volume, count for sets/reps/workouts, "m"/"km" for distance, "min" for time.
- T120: Trend line rendered as `RuleMark` or overlay `LineMark` with dashed stroke.
- T122: Categories come from distinct `exercise.primaryMuscle` values across all exercises. Exercise list comes from exercises that have been performed (have sets).
- T123: For `perWorkout` aggregation, don't zero-fill (workouts are discrete events).

### Parallel Opportunities
- T120 is a pure view component — can be developed in parallel with T118.
- T122 may need a new convenience method on ExerciseService/Repository.

### Dependencies
- Depends on WP05 (shared components, ChartsTabView shell).
- Independent of WP06 (Breakdown tab).

---

## Work Package WP08: Exercises Tab — Multi-Line Chart + Progress Service (Priority: P1)

**Goal**: Implement the Exercises tab chart: multi-exercise progress service method (with TaskGroup parallel loading), ViewModel with metric dropdown + exercise selection state + time range + data navigation, multi-line chart with trend line, exercise color legend.
**Independent Test**: Exercises tab renders a multi-line chart for "Estimated 1RM" with 3 pre-selected exercises. Switching metrics updates chart. Trend line shows for first exercise. ← → navigation works. Selected exercises legend shows below chart.
**Estimated prompt size**: ~500 lines

### Included Subtasks

- [ ] T124 Add `fetchExerciseProgress(metric:exerciseIds:timeRange:)` to `ChartDataServiceProtocol` and implement in `ChartDataService` with TaskGroup parallel loading
- [ ] T125 Create `Reppo/Features/Charts/ViewModels/ExercisesTabViewModel.swift` — state for metric, selectedExercises, timeRange, chartData, trendLine, selectedDataIndex; methods: loadData, changeMetric, updateExercises, changeTimeRange, navigateDataPoint
- [ ] T126 [P] Create `Reppo/Features/Charts/Views/Components/MultiLineChart.swift` — multi-series LineMark chart with color per series, PointMark, tap interaction, Y-axis units
- [ ] T127 Create `Reppo/Features/Charts/Views/ExercisesTabView.swift` — compose metric dropdown + exercise selection trigger + time pills + multi-line chart + trend overlay + data navigator + exercise legend
- [ ] T128 Handle edge cases — no exercises selected (prompt state), exercises with incompatible metrics (e.g., weight metric on distance exercise), single data point, empty result

### Implementation Notes
- T124: Uses `withTaskGroup` to fetch data for up to 10 exercises in parallel. Each child task:
  1. Fetch sets for exerciseId in date range
  2. Apply `chartEligibleSets()` filter
  3. Group by workoutId
  4. Compute metric per session (varies by ExerciseMetric — see plan.md Section 4)
  5. Return `ExerciseProgressSeries`
- T124: Assign colors from the chart palette (chart-1 through chart-8, cycling for > 8).
- T124: Look up exercise names via exerciseRepository.
- T125: `selectedExercises` is `[(id: UUID, name: String)]` — populated from the exercise selection modal (WP09).
- T125: Default state: empty selection with prompt. Once exercises are selected, loads data immediately.
- T125: `trendLine` computed for the first exercise in the list only.
- T126: Use `foregroundStyle(by: .value("Exercise", series.name))` for color differentiation. Custom `chartForegroundStyleScale` for explicit color mapping.
- T126: Y-axis units depend on metric: kg for weight metrics, count for reps, meters for distance, seconds for time.
- T127: Exercise selection trigger button shows selected exercise names (truncated) in accent color.
- T128: If a selected exercise has no data for the chosen metric, its line simply doesn't appear (no error).

### Parallel Opportunities
- T126 is a pure view component — parallel with T124.
- T125 and T127 depend on T124 and T126.

### Dependencies
- Depends on WP05 (shared components, ChartsTabView shell).
- Depends on WP09 for the exercise selection modal (but can be initially built with hardcoded test exercises, then wired to modal in WP09).
- Independent of WP06 and WP07.

---

## Work Package WP09: Exercise Selection Modal + Preset Persistence (Priority: P1)

**Goal**: Build the exercise selection sheet with Current/Presets tabs, add/remove/reorder exercises, preset persistence via UserDefaults, and wire into ExercisesTabView.
**Independent Test**: Tapping exercise selection button in Exercises tab opens modal. Can add exercises (up to 10), remove them, reorder via drag. Can save selection as named preset. Presets tab shows saved presets. Applying a preset loads exercises. Clearing removes all. Presets survive app restart.
**Estimated prompt size**: ~450 lines

### Included Subtasks

- [ ] T129 [P] Create `Reppo/Features/Charts/Models/ChartPreset.swift` — `ChartPreset` struct + `ChartPresetStore` (UserDefaults persistence)
- [ ] T130 Create `Reppo/Features/Charts/Views/Components/ExerciseSelectionSheet.swift` — modal sheet view with:
  - Sheet handle, title "Select Exercises", subtitle "Choose up to 10 exercises"
  - Current / Presets toggle tabs
  - Current tab: list of selected exercises with drag handle (≡), category badge, remove (−) button, "Add Exercise" row
  - Presets tab: list of saved presets with name, exercise summary, "Apply" button
  - Footer: "Apply to Graph" (primary), "Save as Preset" + "Clear Selection" (secondary row)
- [ ] T131 Wire "Add Exercise" action — present the existing exercise list picker (from ExerciseListView in `.addToWorkout` mode or a simplified picker) to select an exercise
- [ ] T132 Implement preset CRUD — save current selection as preset (prompt for name), load preset into current selection, delete preset (swipe-to-delete in Presets tab)
- [ ] T133 Wire ExerciseSelectionSheet into ExercisesTabView — exercise selection button opens sheet, Apply closes sheet and triggers `ExercisesTabViewModel.updateExercises()`
- [ ] T134 Handle edge cases — max 10 exercises limit (disable Add when at 10), duplicate exercise prevention, preset with deleted exercise (filter + warn), empty presets tab state

### Implementation Notes
- T129: `ChartPresetStore` uses `UserDefaults.standard` with JSON encoding/decoding. Key: `"chartExercisePresets"`.
- T130: Use `.sheet` presentation on the ExercisesTabView. Drag-reorder via `ForEach` with `.onMove` modifier.
- T130: Design follows the prototype: `bgCard` sheet background, rounded top corners, handle bar.
- T131: Two options for "Add Exercise":
  - Option A: Reuse `ExerciseListView(mode: .addToWorkout)` in a nested sheet
  - Option B: Simple inline search + list within the modal
  - **Recommendation**: Option A — reuses existing code.
- T132: "Save as Preset" should show a text field alert for the preset name.
- T133: On "Apply to Graph", close sheet and call `exercisesVM.updateExercises(newSelection)` which triggers data reload.
- T134: When loading a preset, check each exerciseId still exists (exercise may have been deleted). Filter out missing ones. If preset becomes empty, show a brief alert.

### Parallel Opportunities
- T129 is independent (model + persistence).
- T130 is the main UI work.
- T131–T134 build on T130 sequentially.

### Dependencies
- Depends on WP05 (ChartsTabView is live).
- Depends on WP08 (ExercisesTabViewModel exists to wire into).
- Can be built in parallel with WP08 if the VM interface is agreed upon first.

---

## Work Package WP10: Cleanup — Remove Old Code, Dead Types (Priority: P2)

**Goal**: Remove all old Charts v1 code that is no longer referenced: old ViewModels, old Views, old model types. Ensure no regressions in the Exercise detail view (which had its own chart sub-tab).
**Independent Test**: App compiles and runs. Charts tab works as v2. Exercise detail view (if it had chart components) still works or has been updated. No dead code remains.
**Estimated prompt size**: ~200 lines

### Included Subtasks

- [ ] T135 Audit cross-feature references — check if Exercise detail's "Charts" sub-tab uses any of the old chart components (ExerciseChartsDetailView, etc.)
- [ ] T136 If Exercise detail references exist: either migrate them to use new components or keep the specific files they need
- [ ] T137 Remove unused files: `ChartsDashboardViewModel.swift`, `ChartsDashboardView.swift`, `ExerciseChartsDetailViewModel.swift` (if unreferenced), `ExerciseChartsDetailView.swift` (if unreferenced), `ExerciseChartCard.swift`, `WeeklyVolumeChart.swift`, `TrainingFrequencyChart.swift`, `MuscleGroupDistributionChart.swift`, `TopWeightChart.swift`, `RepPRProgressionChart.swift`
- [ ] T138 Remove unused model types from `ChartModels.swift`: `OverviewChartData`, `ExerciseCardData`, `ExerciseDetailChartData` (if unreferenced)
- [ ] T139 Remove old service methods from `ChartDataService` if no longer called: `fetchExerciseCardData()`, potentially `fetchWeeklyVolume()`, `fetchTrainingFrequency()`, `fetchMuscleGroupDistribution()`
- [ ] T140 Update `project.pbxproj` — remove deleted files from Xcode project
- [ ] T141 Final compile + run verification

### Implementation Notes
- T135 is critical — the Exercise feature has a "Charts" sub-tab (`ExerciseDetailTab.charts`) that may use `ExerciseChartsDetailView`. If so, we need to decide: (a) keep it as-is, (b) replace with a simplified version using new components, (c) remove the sub-tab.
- T139: The old overview methods (`fetchWeeklyVolume`, `fetchTrainingFrequency`, `fetchMuscleGroupDistribution`) may have logic reusable internally by the new methods. Keep them as private helpers if the new methods call into them, or remove if fully replaced.
- T140: Must update `project.pbxproj` to remove file references, or the project won't build.

### Dependencies
- Depends on ALL previous WPs being complete and verified (WP05–WP09).

---

## Dependency & Execution Summary

```
WP05 (Foundation) ────────────────────────────────────────────────────
    │
    ├── WP06 (Breakdown) ─────────────────────────────────────────────
    │
    ├── WP07 (Workouts) ──────────────────────────────────────────────
    │
    ├── WP08 (Exercises Chart) ────┐
    │                              ├── Wire together ──── WP10 (Cleanup)
    └── WP09 (Selection Modal) ───┘
```

- **WP05** must complete first (foundation for everything).
- **WP06, WP07, WP08** can run in any order or in parallel after WP05.
- **WP09** can be built in parallel with WP08, but wiring requires both.
- **WP10** runs last after all tabs are verified working.

### Recommended Execution Order (sequential)

1. WP05 — Foundation
2. WP06 — Breakdown (simplest chart, good first win)
3. WP07 — Workouts (most complex service method)
4. WP08 + WP09 — Exercises + Modal (build chart and modal in parallel, wire together)
5. WP10 — Cleanup

---

## Subtask Index (Reference)

| ID   | Summary                                    | WP   | Parallel? |
| ---- | ------------------------------------------ | ---- | --------- |
| T101 | Add new enums to ChartModels               | WP05 | Yes       |
| T102 | Add new structs to ChartModels             | WP05 | Yes       |
| T103 | TrendLineCalculator utility                | WP05 | Yes       |
| T104 | ChartsTabViewModel coordinator             | WP05 | No        |
| T105 | ChartsTabView (3-tab container)            | WP05 | No        |
| T106 | ChartSubTabPicker component                | WP05 | Yes       |
| T107 | ChartDropdown component                    | WP05 | Yes       |
| T108 | ChartTimePills component                   | WP05 | Yes       |
| T109 | DataPointNavigator component               | WP05 | Yes       |
| T110 | TrendLineOverlay component                 | WP05 | Yes       |
| T111 | ChartLegend component                      | WP05 | Yes       |
| T112 | Wire ChartsTabView into ContentView        | WP05 | No        |
| T113 | ChartDataService.fetchBreakdownData()      | WP06 | No        |
| T114 | BreakdownTabViewModel                      | WP06 | No        |
| T115 | DonutChartView (SectorMark)                | WP06 | Yes       |
| T116 | BreakdownTabView                           | WP06 | No        |
| T117 | Breakdown edge cases                       | WP06 | No        |
| T118 | ChartDataService.fetchWorkoutsTimeSeries() | WP07 | No        |
| T119 | WorkoutsTabViewModel                       | WP07 | No        |
| T120 | TimeSeriesBarChart component               | WP07 | Yes       |
| T121 | WorkoutsTabView                            | WP07 | No        |
| T122 | Filter dropdown data source                | WP07 | No        |
| T123 | Workouts edge cases                        | WP07 | No        |
| T124 | ChartDataService.fetchExerciseProgress()   | WP08 | No        |
| T125 | ExercisesTabViewModel                      | WP08 | No        |
| T126 | MultiLineChart component                   | WP08 | Yes       |
| T127 | ExercisesTabView                           | WP08 | No        |
| T128 | Exercises edge cases                       | WP08 | No        |
| T129 | ChartPreset model + ChartPresetStore       | WP09 | Yes       |
| T130 | ExerciseSelectionSheet view                | WP09 | No        |
| T131 | Add Exercise picker wiring                 | WP09 | No        |
| T132 | Preset CRUD operations                     | WP09 | No        |
| T133 | Wire modal into ExercisesTabView           | WP09 | No        |
| T134 | Modal edge cases                           | WP09 | No        |
| T135 | Audit cross-feature references             | WP10 | No        |
| T136 | Migrate Exercise detail if needed          | WP10 | No        |
| T137 | Remove unused view/VM files                | WP10 | No        |
| T138 | Remove unused model types                  | WP10 | No        |
| T139 | Remove unused service methods              | WP10 | No        |
| T140 | Update project.pbxproj                     | WP10 | No        |
| T141 | Final compile + run verification           | WP10 | No        |
