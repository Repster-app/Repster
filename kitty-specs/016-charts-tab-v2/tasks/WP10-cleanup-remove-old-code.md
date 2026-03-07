---
work_package_id: "WP10"
subtasks:
  - "T135"
  - "T136"
  - "T137"
  - "T138"
  - "T139"
  - "T140"
  - "T141"
title: "Cleanup — Remove Old Code, Dead Types"
phase: "Phase 2 - Cleanup"
lane: "planned"
dependencies: ["WP05", "WP06", "WP07", "WP08", "WP09"]
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

# Work Package Prompt: WP10 – Cleanup — Remove Old Code, Dead Types

## Objectives & Success Criteria

- Audit all cross-feature references to old Charts v1 code (especially Exercise detail "Charts" sub-tab).
- Migrate or update any external references to old chart components.
- Remove all unreferenced Charts v1 files (views, viewmodels, chart components).
- Remove unused model types from ChartModels.swift.
- Remove unused service methods from ChartDataService (if no longer called).
- Update project.pbxproj to remove deleted file references.
- **Success**: App compiles and runs. Charts tab v2 works fully. No dead chart code remains. Exercise detail view (if it referenced old charts) still works. Zero compiler warnings from removed code.

## Context & Constraints

- **Critical check**: The Exercise feature has `ExerciseDetailTab.charts` which may use `ExerciseChartsDetailView` and its dependencies. Must audit before deleting.
- **Existing files to potentially remove** (per research.md):
  - `ChartsDashboardViewModel.swift` — replaced by `ChartsTabViewModel`
  - `ChartsDashboardView.swift` — replaced by `ChartsTabView`
  - `ExerciseChartsDetailViewModel.swift` — may be referenced by Exercise detail
  - `ExerciseChartsDetailView.swift` — may be referenced by Exercise detail
  - `ExerciseChartCard.swift` — no longer needed (no card list)
  - `WeeklyVolumeChart.swift` — replaced by TimeSeriesBarChart
  - `TrainingFrequencyChart.swift` — replaced by Workouts tab
  - `MuscleGroupDistributionChart.swift` — replaced by Breakdown donut
  - `TopWeightChart.swift` — absorbed into Exercises tab
  - `RepPRProgressionChart.swift` — absorbed into Exercises tab
  - `TimeRangeSelector.swift` — replaced by ChartTimePills
- **Old model types**: `OverviewChartData`, `ExerciseCardData`, `ExerciseDetailChartData`
- **Old service methods**: `fetchExerciseCardData()`, potentially `fetchWeeklyVolume()`, `fetchTrainingFrequency()`, `fetchMuscleGroupDistribution()`
- **DO NOT remove**: Types and methods still used internally by new service methods or by other features.

**Implementation command**: `spec-kitty implement WP10 --base WP09`

## Subtasks & Detailed Guidance

### Subtask T135 – Audit Cross-Feature References

- **Purpose**: Before deleting anything, find all references to old chart files across the entire codebase.
- **Method**: Use Xcode "Find in Project" (Cmd+Shift+F) or grep for each file/type name.

**Check these specifically**:
1. `ExerciseChartsDetailView` — is it referenced in `ExerciseDetailView` or `ExerciseHistoryView` or any exercise feature file?
2. `ExerciseChartsDetailViewModel` — any references outside Charts feature?
3. `ExerciseChartCard` — any references outside Charts feature?
4. `TimeRangeSelector` — used anywhere outside old Charts views? (Research.md said "adapt" but plan.md creates new `ChartTimePills` instead — this file can be unconditionally removed if no external references exist.)
5. `TopWeightChart`, `RepPRProgressionChart` — used in Exercise detail charts sub-tab?
6. Old service methods — are any called from outside Charts ViewModels?
7. **CRITICAL — `ExerciseChartData`** (in `Reppo/Features/Exercise/Models/ExerciseModels.swift`, NOT in ChartModels.swift): This type and its nested `ChartPoint`/`VolumePoint` types are used by `ActiveWorkoutViewModel`, `ExerciseDetailViewModel`, `ExerciseChartsView`, AND `ChartDataService.fetchExerciseDetailCharts()`. These are cross-feature dependencies and MUST NOT be removed. The `ExerciseDetailChartData` in `ChartModels.swift` references `ExerciseChartData.ChartPoint` — only remove `ExerciseDetailChartData` if `fetchExerciseDetailCharts()` is also being removed.

**Output**: List of files with external references that need migration before deletion.

```bash
# Quick reference check
grep -r "ExerciseChartsDetailView" Reppo/ --include="*.swift" -l
grep -r "ChartsDashboardView" Reppo/ --include="*.swift" -l
grep -r "ExerciseChartCard" Reppo/ --include="*.swift" -l
grep -r "WeeklyVolumeChart" Reppo/ --include="*.swift" -l
grep -r "TimeRangeSelector" Reppo/ --include="*.swift" -l
grep -r "fetchExerciseCardData" Reppo/ --include="*.swift" -l
grep -r "fetchWeeklyVolume" Reppo/ --include="*.swift" -l
grep -r "OverviewChartData" Reppo/ --include="*.swift" -l
grep -r "ExerciseCardData" Reppo/ --include="*.swift" -l
grep -r "ExerciseDetailChartData" Reppo/ --include="*.swift" -l
```

---

### Subtask T136 – Migrate Exercise Detail References (if needed)

- **Purpose**: If Exercise detail's "Charts" sub-tab uses old chart components, decide:
  - **Option A**: Keep `ExerciseChartsDetailView` and its dependencies as-is (they serve a different UX — single-exercise detail, not the main Charts tab).
  - **Option B**: Replace with simplified version using new `MultiLineChart` component.
  - **Option C**: Remove the "Charts" sub-tab from Exercise detail entirely (simplify).

**Recommendation**: Option A is safest — keep the Exercise detail charts as-is if they work. They serve a different purpose (drill-down from exercise list, not the main Charts tab). Only remove files that are truly unreferenced.

If keeping: do NOT delete `ExerciseChartsDetailView`, `ExerciseChartsDetailViewModel`, `TopWeightChart`, `RepPRProgressionChart`, or any model types they use. Update the "Files to Remove" list accordingly.

---

### Subtask T137 – Remove Unreferenced View/ViewModel Files

Based on T135 audit results, delete files with ZERO external references:

**Definitely safe to remove** (replaced by v2, only referenced by each other):
- `ChartsDashboardViewModel.swift`
- `ChartsDashboardView.swift`
- `ExerciseChartCard.swift`
- `WeeklyVolumeChart.swift`
- `TrainingFrequencyChart.swift`
- `MuscleGroupDistributionChart.swift`

**Conditionally remove** (only if T135 confirms no external references):
- `ExerciseChartsDetailViewModel.swift`
- `ExerciseChartsDetailView.swift`
- `TopWeightChart.swift`
- `RepPRProgressionChart.swift`
- `TimeRangeSelector.swift`

---

### Subtask T138 – Remove Unused Model Types from ChartModels.swift

Remove types that are no longer referenced anywhere:
- `OverviewChartData` — only used by old `ChartsDashboardViewModel`
- `ExerciseCardData` — only used by old card list
- `ExerciseDetailChartData` — check if used by `ExerciseChartsDetailViewModel`

**Important**: Keep `WeeklyVolumePoint`, `WeeklyFrequencyPoint`, `MuscleGroupVolume`, `TopWeightPoint`, `RepSeries`, `RepPRPoint`, `RepPRProgressionData`, `TimeRange`, `TrendDirection` — these may still be used by remaining code or the new service methods internally.

---

### Subtask T139 – Remove Unused Service Methods

From `ChartDataService.swift`, remove methods no longer called:
- `fetchExerciseCardData()` — no longer needed (no card list in v2)

**Check before removing**:
- `fetchWeeklyVolume()` — is it called by new `fetchWorkoutsTimeSeries()` internally? If yes, keep as private helper.
- `fetchTrainingFrequency()` — same check.
- `fetchMuscleGroupDistribution()` — same check. Likely replaced by `fetchBreakdownData()`.
- `fetchExerciseDetailCharts()` — is it used by `ExerciseChartsDetailViewModel` (if kept)?

Also remove corresponding protocol method signatures for deleted methods.

---

### Subtask T140 – Update project.pbxproj

- **Purpose**: Remove deleted files from the Xcode project file. If files are deleted from disk but not from pbxproj, the project won't build.
- **Method**: The simplest approach is to remove the files via Xcode (which auto-updates pbxproj), or manually edit pbxproj to remove file reference lines.

**Important**: After removing files, do a clean build to verify no missing references.

---

### Subtask T141 – Final Compile + Run Verification

1. Clean build folder (Cmd+Shift+K in Xcode).
2. Build the project (Cmd+B). Must succeed with 0 errors.
3. Run the app on simulator.
4. Verify:
   - Charts tab shows 3-tab picker and all tabs work.
   - Breakdown: donut chart renders, all 8 options work.
   - Workouts: bar chart renders, dropdowns work, navigation works.
   - Exercises: line chart renders, exercise selection modal works, presets work.
   - Exercise detail view (if it has charts sub-tab): still works.
   - No crashes or runtime errors.
5. Check for compiler warnings related to removed code — should be zero.

---

## Definition of Done Checklist

- [ ] Cross-feature reference audit completed (T135)
- [ ] Exercise detail migrations handled if needed (T136)
- [ ] Unreferenced view/viewmodel files deleted (T137)
- [ ] Unused model types removed from ChartModels.swift (T138)
- [ ] Unused service methods removed from ChartDataService (T139)
- [ ] project.pbxproj updated — no dangling file references (T140)
- [ ] Clean build succeeds with 0 errors (T141)
- [ ] All Charts v2 tabs work correctly
- [ ] Exercise detail view (if applicable) still works
- [ ] No compiler warnings from cleanup

## Review Guidance

- Verify T135 audit was thorough — no external references missed.
- Verify no files were deleted that are still referenced.
- Verify project.pbxproj has no orphaned file references.
- Verify ChartDataServiceProtocol matches the remaining methods in ChartDataService.
- Verify a clean build succeeds.
- Verify the old `TimeRange` enum is kept if `ExerciseChartsDetailViewModel` (if retained) uses it.

## Activity Log
