# Implementation Plan: Charts Tab

**Branch**: `009-charts-tab` | **Date**: 2026-02-27 | **Spec**: `kitty-specs/009-charts-tab/spec.md`
**Input**: Feature specification from `kitty-specs/009-charts-tab/spec.md`

## Summary

Build the Charts Tab — an overview dashboard with weekly volume, training frequency, and muscle group distribution charts, plus a per-exercise card list with sparklines. Tapping an exercise card pushes an Exercise Charts Detail screen with time-range filtering ([3M] [6M] [1Y] [All]) and 4 chart types: e1RM trend, volume per session, top weight per session, and rep PR progression (multi-line). All charts use Swift Charts. Data is lazy-computed via date-range-scoped queries with session-scoped in-memory caching. No new SwiftData entities; no pre-aggregated tables for v1.

## Technical Context

**Language/Version**: Swift (latest stable), iOS 17.0+
**Primary Dependencies**: SwiftUI, SwiftData, Swift Charts (existing)
**Storage**: SwiftData — reads from existing Workout, WorkoutSet, Exercise, ExerciseStats, PerformanceRecord models
**Testing**: Manual testing for v1 (per constitution)
**Target Platform**: iOS 17.0+, iPhone only
**Project Type**: Mobile (single platform)
**Performance Goals**: Charts render < 1 second with 12,000+ sets (SC-001), detail loads < 200ms after initial computation (SC-002), no chart data computed at startup (SC-003), chart data released on navigate away (SC-004)
**Constraints**: Dark mode only, no third-party chart libs, MVVM architecture, lazy compute + session cache (specdoc S8.10), date-range-scoped queries, no pre-aggregated tables for v1
**Scale/Scope**: ~12,000 sets, ~200 exercises, overview bounded to 12/4 weeks, detail per-exercise (bounded by exercise frequency)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| SwiftUI primary, UIKit only if needed | PASS | All views in SwiftUI |
| MVVM: View → ViewModel → Service → Repository → SwiftData | PASS | ChartsDashboardViewModel/ExerciseChartsDetailViewModel → Services → Repositories |
| @Observable for ViewModels (not ObservableObject) | PASS | Both ViewModels use @Observable |
| No third-party UI libraries | PASS | Swift Charts only (approved dependency) |
| No ModelContext in ViewModel | PASS | All data via service/repository layer |
| NavigationStack (not NavigationView) | PASS | Exercise Charts Detail pushed via NavigationStack |
| Dark mode only | PASS | All colors from DesignTokens.swift |
| No startup rebuild | PASS | Lazy-loads on tab appear, not at launch (FR-007, SC-003) |
| Database aggregation over Swift iteration | CONDITIONAL | SwiftData lacks GROUP BY — bounded date-range fetches aggregated in Swift are acceptable per specdoc S8.6: "Building charts with per-set data points (load specific date range)" |
| Do not invent schema | PASS | 0 new SwiftData models, 0 new fields |
| SF Symbols for icons | PASS | Trend arrows, chart icons use SF Symbols |
| Minimum 44x44pt tap targets | PASS | Exercise cards, time range buttons sized accordingly |
| Store metric, convert in UI | PASS | Reads effectiveWeight (kg), converts to user's unit preference for display |
| Chart data in memory only when displayed (S8.8) | PASS | ViewModel releases data on navigate away |
| Lazy compute + session cache (S8.10) | PASS | Computed on first access, cached while screen is active |
| Query only needed date range (FR-009) | PASS | Overview: 12/4 weeks. Detail: per time range selector. |

**Post-Phase 1 re-check**: No violations. The in-memory aggregation is bounded by date range (overview: max 12 weeks of sets) or by exercise (detail: one exercise at a time). This follows specdoc Section 8.6's explicit allowance for "building charts with per-set data points (load specific date range)."

## Project Structure

### Documentation (this feature)

```
kitty-specs/009-charts-tab/
├── plan.md              # This file
├── research.md          # Phase 0 output — chart patterns, data loading, sparklines
├── data-model.md        # Phase 1 output — entity usage, derived structures
├── quickstart.md        # Phase 1 output — file structure, verification checklist
└── tasks.md             # Phase 2 output (NOT created by /spec-kitty.plan)
```

### Source Code (repository root)

```
Reppo/
├── Features/
│   ├── Charts/
│   │   ├── Views/
│   │   │   ├── ChartsDashboardView.swift              # Main tab screen: overview + exercise list
│   │   │   ├── ExerciseChartsDetailView.swift         # Drill-down: time range + 4 charts
│   │   │   └── Components/
│   │   │       ├── WeeklyVolumeChart.swift            # Bar chart, 12 weeks (overview)
│   │   │       ├── TrainingFrequencyChart.swift       # Sessions per week (overview)
│   │   │       ├── MuscleGroupDistributionChart.swift # Pie/bar, 4 weeks (overview)
│   │   │       ├── ExerciseChartCard.swift            # Card: e1RM, trend arrow, sparkline
│   │   │       ├── TimeRangeSelector.swift            # [3M] [6M] [1Y] [All] picker
│   │   │       ├── TopWeightChart.swift               # Line chart: top weight per session
│   │   │       └── RepPRProgressionChart.swift        # Multi-line: 1RM, 3RM, 5RM over time
│   │   ├── ViewModels/
│   │   │   ├── ChartsDashboardViewModel.swift         # @Observable, overview + exercise cards
│   │   │   └── ExerciseChartsDetailViewModel.swift    # @Observable, per-exercise detail data
│   │   └── Models/
│   │       └── ChartModels.swift                      # Data types for chart points
│   └── Exercise/
│       └── Views/
│           └── ExerciseChartsView.swift               # Existing — styling pattern reused (not modified)
├── Core/
│   ├── Repositories/
│   │   └── SetRepository.swift                        # Add chart query methods
│   └── Services/
│       └── ChartDataService.swift                     # New: chart aggregation logic
└── App/
    └── ContentView.swift                              # Wire Charts tab (replace placeholder)
```

**Structure Decision**: New `Reppo/Features/Charts/` follows the established feature folder pattern. A new `ChartDataService` in `Core/Services/` encapsulates chart-specific aggregation logic (fetching + in-memory grouping), keeping ViewModels thin. Existing `ExerciseChartsView` is extended in-place.

## Engineering Alignment (Planning Decisions)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Aggregation strategy | Lazy compute from raw sets, no pre-aggregated tables | Specdoc S8.10: lazy compute for v1. Bounded queries are fast enough. |
| 2 | Chart framework | Swift Charts | Constitution mandate, approved dependency |
| 3 | Existing code reuse | Extend `ExerciseChartsView` and `ExerciseChartData` | screen_tree S8 reused components; avoid duplication |
| 4 | Muscle group distribution | Primary muscle only, no secondary weighting | Simpler, matches how lifters think about splits |
| 5 | Memory model | Chart data in-memory only while displayed | Specdoc S8.8, S8.10: session-scoped cache, released on navigate away |
| 6 | Chart aggregation | New `ChartDataService` actor for fetch + aggregate | Keeps ViewModels thin, aggregation logic testable, follows service layer pattern |
| 7 | Sparkline data | Last 8 sessions' best e1RM per exercise | Compact, shows recent trend direction |
| 8 | Overview query scope | Weekly volume: 12 weeks, frequency: 12 weeks, muscle groups: 4 weeks | Per spec FR-001, FR-002, FR-003 |

## Component Architecture

### ChartsDashboardViewModel (@Observable)

```
Responsibilities:
├── overviewData: OverviewChartData?         # Weekly volume, frequency, muscle groups
├── exerciseCards: [ExerciseCardData]         # Sorted by lastPerformedDate
├── isLoading: Bool                          # Loading state
├── isEmpty: Bool                            # No workout history at all
│
├── loadOverview()                           # Fetches overview chart data (lazy, once)
├── loadExerciseCards()                      # Fetches exercise list with sparkline data
│
└── Dependencies (injected):
    ├── ChartDataService                     # Chart aggregation
    ├── ExerciseService                      # Exercise metadata
    └── StatsService                         # ExerciseStats for e1RM values
```

### ExerciseChartsDetailViewModel (@Observable)

```
Responsibilities:
├── exerciseId: UUID                         # Target exercise
├── exerciseName: String                     # Display name
├── selectedTimeRange: TimeRange = .sixMonths # Default to 6M
├── chartData: ExerciseDetailChartData?      # All 4 chart datasets
├── isLoading: Bool
│
├── loadCharts()                             # Fetches all 4 chart types for current time range
├── changeTimeRange(_:)                      # Recomputes charts for new range
│
└── Dependencies (injected):
    ├── ChartDataService
    └── ExerciseService
```

### ChartDataService (actor)

```
Responsibilities:
├── fetchWeeklyVolume(weeks: Int) async → [WeeklyVolumePoint]
├── fetchTrainingFrequency(weeks: Int) async → [WeeklyFrequencyPoint]
├── fetchMuscleGroupDistribution(weeks: Int) async → [MuscleGroupVolume]
├── fetchExerciseCardData() async → [ExerciseCardData]
├── fetchExerciseDetailCharts(exerciseId:, range:) async → ExerciseDetailChartData
│
└── Dependencies (injected):
    ├── SetRepository           # Raw set queries with date predicates
    ├── WorkoutRepository       # Workout queries for frequency
    ├── ExerciseRepository      # Exercise metadata
    ├── ExerciseStatsRepository # Pre-computed stats (e1RM, lastPerformed)
    └── PerformanceRecordRepository  # Rep PR records
```

### View Hierarchy

```
ChartsDashboardView (NavigationStack, bottom nav visible)
├── ScrollView
│   ├── OVERVIEW section header
│   │   ├── WeeklyVolumeChart (BarMark, 12 weeks)
│   │   ├── TrainingFrequencyChart (sessions/week, 12 weeks)
│   │   └── MuscleGroupDistributionChart (4 weeks, primary muscle)
│   │
│   ├── PER EXERCISE section header
│   │   └── LazyVStack
│   │       └── ForEach(exerciseCards) → ExerciseChartCard
│   │           ├── Exercise name
│   │           ├── Current e1RM value
│   │           ├── Trend direction arrow (↑/↓/→)
│   │           ├── Sparkline (last 8 sessions, LineMark)
│   │           └── NavigationLink → ExerciseChartsDetailView
│   │
│   └── Empty state (no workouts at all)
│
└── Bottom nav visible (TabView handles this)

ExerciseChartsDetailView (pushed, bottom nav hidden)
├── ScrollView
│   ├── TimeRangeSelector: [3M] [6M] [1Y] [All]
│   ├── e1RM Trend (LineMark + PointMark) — reused from ExerciseChartsView
│   ├── Volume Per Session (BarMark) — reused from ExerciseChartsView
│   ├── Top Weight Per Session (LineMark)
│   └── Rep PR Progression (multi-LineMark: 1RM, 3RM, 5RM series)
│
└── Empty states per chart section
```

### Data Flow

```
Charts Tab appears (first time)
  → ChartsDashboardView.onAppear
  → ChartsDashboardViewModel.loadOverview()
    → ChartDataService.fetchWeeklyVolume(weeks: 12)
      → SetRepository: fetch sets WHERE date >= 12 weeks ago, hasData = true
      → Group by ISO week in Swift, sum effectiveWeight × reps per week
    → ChartDataService.fetchTrainingFrequency(weeks: 12)
      → WorkoutRepository: fetch workouts WHERE date >= 12 weeks ago
      → Group by ISO week, count per week
    → ChartDataService.fetchMuscleGroupDistribution(weeks: 4)
      → SetRepository: fetch sets WHERE date >= 4 weeks ago, hasData = true
      → Join with Exercise.primaryMuscle (cached)
      → Group by muscle, sum volume per muscle
  → ChartsDashboardViewModel.loadExerciseCards()
    → ChartDataService.fetchExerciseCardData()
      → ExerciseStatsRepository: fetch all ExerciseStats (sparse, ~200 rows)
      → For each exercise with stats: get bestE1RM, lastPerformedDate
      → For top exercises: fetch last 8 sessions' best e1RM for sparkline
      → Sort by lastPerformedDate descending

User taps exercise card
  → NavigationStack pushes ExerciseChartsDetailView(exerciseId:)
  → ExerciseChartsDetailViewModel.loadCharts()
    → ChartDataService.fetchExerciseDetailCharts(exerciseId:, range: .sixMonths)
      → SetRepository: fetch sets WHERE exerciseId = ? AND date >= 6 months ago
      → Group by workoutId:
        - e1RM: max(set.e1RM) per workout
        - Volume: sum(effectiveWeight × reps) per workout
        - Top weight: max(effectiveWeight) per workout
      → Rep PR progression (from same sets, not PerformanceRecord):
        - For each target rep count [1, 3, 5]:
          - Filter sets where reps >= targetReps
          - Take max effectiveWeight per session
          - Build time series as separate line series

User changes time range [3M] → [1Y]
  → ExerciseChartsDetailViewModel.changeTimeRange(.oneYear)
  → Re-fetches with new date range
  → View updates with new chart data

User navigates away from Charts tab
  → ViewModel data released (not persisted, per S8.8/SC-004)
```

## Complexity Tracking

| Decision | Justification |
|----------|---------------|
| In-memory aggregation for overview | Bounded to 12 weeks. Max ~2000 sets for a heavy user. Acceptable per specdoc S8.6 chart exception. |
| Sparkline fetch per exercise card | Bounded: top ~50 exercises × 8 sessions each. Can be lazy-loaded on scroll if needed. |
| Rep PR progression from PerformanceRecord + Set dates | PerformanceRecord is sparse (~50 rows/exercise). Set date lookup is by setId (indexed). |

## Parallel Work Analysis

This feature has a clear dependency chain suitable for sequential work packages.

### Dependency Graph

```
WP01: Foundation (ChartModels, ChartDataService, ChartsDashboardViewModel skeleton, tab wiring)
  → WP02: Overview Dashboard (3 overview charts, empty states)
  → WP03: Per-Exercise Cards (ExerciseChartCard with sparkline, card list)
  → WP04: Exercise Charts Detail (TimeRangeSelector, 4 chart types, navigation)
```

Sequential: WP01 must complete before WP02-04. WP02 and WP03 share the dashboard view but can be split cleanly (overview section vs. exercise section). WP04 depends on WP01 for ChartDataService but is otherwise independent.
