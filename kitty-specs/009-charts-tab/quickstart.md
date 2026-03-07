# Quickstart: 009 Charts Tab

**Feature**: Charts Tab
**Date**: 2026-02-27

## Prerequisites

- Feature 008 (Calendar Tab) merged — provides `MuscleGroupColors` utility for distribution chart
- Feature 007 (Exercise List & Detail) merged — provides `ExerciseChartsView`, `ExerciseChartData`, `ExerciseDetailView`
- Existing services: `WorkoutService`, `SetService`, `ExerciseService`, `StatsService`
- Existing repositories: `WorkoutRepository`, `SetRepository`, `ExerciseRepository`, `ExerciseStatsRepository`, `PerformanceRecordRepository`
- Existing models: `Workout`, `WorkoutSet`, `Exercise`, `ExerciseStats`, `PerformanceRecord`

## File Structure

```
Reppo/
├── Features/
│   └── Charts/
│       ├── Views/
│       │   ├── ChartsDashboardView.swift              # Main tab: overview + exercise list
│       │   ├── ExerciseChartsDetailView.swift         # Drill-down: time range + 4 charts
│       │   └── Components/
│       │       ├── WeeklyVolumeChart.swift            # Bar chart, 12 weeks
│       │       ├── TrainingFrequencyChart.swift       # Sessions per week
│       │       ├── MuscleGroupDistributionChart.swift # Horizontal bars by muscle
│       │       ├── ExerciseChartCard.swift            # Card: e1RM, trend, sparkline
│       │       ├── TimeRangeSelector.swift            # [3M] [6M] [1Y] [All]
│       │       ├── TopWeightChart.swift               # Line: max weight per session
│       │       └── RepPRProgressionChart.swift        # Multi-line: 1RM, 3RM, 5RM
│       ├── ViewModels/
│       │   ├── ChartsDashboardViewModel.swift         # @Observable, overview + cards
│       │   └── ExerciseChartsDetailViewModel.swift    # @Observable, per-exercise detail
│       └── Models/
│           └── ChartModels.swift                      # All chart data types + TimeRange enum
├── Core/
│   ├── Services/
│   │   └── ChartDataService.swift                     # New: aggregation logic
│   └── Repositories/
│       └── SetRepository.swift                        # Add date-range + exercise query methods
├── App/
│   └── ContentView.swift                              # Replace ChartsPlaceholderView
```

## Key Architecture Decisions

1. **No new SwiftData models** — reads from existing Workout, WorkoutSet, Exercise, ExerciseStats, PerformanceRecord
2. **Lazy compute + session cache** — data computed on first Charts tab access, held in memory while displayed, released on navigate away (specdoc S8.10)
3. **New ChartDataService** — encapsulates fetch + aggregate logic, injected into ViewModels via ServiceContainer
4. **Date-range-scoped queries** — overview: 12 weeks / 4 weeks; detail: per TimeRange selector (FR-009)
5. **Reuse chart visual patterns** — same card background, axis styling, colors as ExerciseChartsView
6. **MuscleGroupColors reuse** — from Calendar feature for distribution chart

## Wiring Checklist

- [ ] Add `ChartDataService` to `ServiceContainer`
- [ ] Add new `SetRepository` query methods (date-range, exercise + date-range)
- [ ] Add `WorkoutRepository.fetchWorkouts(from:to:)` if not already present
- [ ] Replace `ChartsPlaceholderView()` with `ChartsDashboardView(...)` in `ContentView.swift`
- [ ] Pass required services to `ChartsDashboardView` via init or environment

## Quick Verification

After implementation, verify:
- [ ] Charts tab shows overview section with 3 charts (volume, frequency, muscle groups)
- [ ] Weekly volume bar chart shows last 12 weeks
- [ ] Training frequency shows sessions per week
- [ ] Muscle group distribution uses correct colors from MuscleGroupColors
- [ ] Per-exercise cards show current e1RM, trend arrow, and sparkline
- [ ] Exercise cards sorted by most recent
- [ ] Tapping exercise card navigates to Exercise Charts Detail
- [ ] Time range selector works: [3M] [6M] [1Y] [All]
- [ ] Detail shows 4 charts: e1RM trend, volume/session, top weight, rep PR progression
- [ ] Rep PR progression shows multi-line (1RM, 3RM, 5RM) where data exists
- [ ] Changing time range re-fetches and updates all charts
- [ ] Empty state shows when no workout history exists
- [ ] Single data point shows point without trendline
- [ ] "No data for this period" shows for time ranges with no data
- [ ] Charts render < 1 second with large dataset (SC-001)
- [ ] Detail loads < 200ms after initial computation (SC-002)
- [ ] No chart data computed at app startup (SC-003)
- [ ] Bottom navigation visible on dashboard
- [ ] Bottom navigation hidden on detail screen
