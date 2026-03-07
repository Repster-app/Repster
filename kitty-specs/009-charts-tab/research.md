# Research: 009 Charts Tab

**Feature**: Charts Tab
**Date**: 2026-02-27
**Status**: Complete

## Research Questions

### RQ-1: Overview Weekly Volume Aggregation Without GROUP BY

**Question**: SwiftData lacks native GROUP BY / SUM. How to efficiently compute weekly volume for the last 12 weeks?

**Decision**: Fetch all sets in the 12-week date range via `FetchDescriptor` with date predicate, then group and sum in Swift.

**Rationale**:
- Specdoc Section 8.6 explicitly allows: "Building charts with per-set data points (load specific date range)"
- 12 weeks for an active lifter = ~60-80 workouts × 15-20 sets = ~1000-1600 sets. This is a bounded, manageable in-memory operation.
- SwiftData `FetchDescriptor` with `#Predicate { $0.date >= cutoffDate }` leverages the underlying SQLite index on date.
- The constitution's "do not invent" rule prevents adding pre-aggregated tables without evidence of a performance problem.

**Implementation approach**:
```swift
// Repository: fetch sets with date predicate
let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date())!
let predicate = #Predicate<WorkoutSet> { $0.date >= cutoff && $0.hasData }
// Service: group in Swift
let grouped = Dictionary(grouping: sets) { set in
    Calendar.current.startOfWeek(for: set.date) // extension method
}
let weeklyVolume = grouped.map { (week, sets) in
    WeeklyVolumePoint(weekStart: week, volume: sets.reduce(0) { $0 + (($1.effectiveWeight ?? 0) * Double($1.reps ?? 0)) })
}
```

**Alternatives considered**:
- Pre-aggregated `ExerciseWeeklyStats` table: Fast reads but adds write-time complexity. Deferred per planning decision.
- Core Data `NSFetchRequest` with `NSExpression` for SUM/GROUP BY: Bypasses SwiftData, violates constitution's "no Core Data directly" rule.
- Fetch only completed workouts, then fetch sets per workout: N+1 query pattern. Single range fetch is simpler.

---

### RQ-2: Training Frequency Chart Data

**Question**: How to compute sessions per week for the frequency chart?

**Decision**: Fetch workouts in the 12-week range, group by ISO week, count per week.

**Rationale**:
- Workouts are already sparse (3-6 per week for active users × 12 weeks = ~36-72 rows).
- `WorkoutRepository` already has `fetchWorkouts(for dateRange:)` or equivalent.
- Grouping ~50 workouts by week number in Swift is trivial.

**Implementation approach**:
```swift
let workouts = try await workoutRepository.fetchWorkouts(from: cutoff, to: Date())
let grouped = Dictionary(grouping: workouts) { workout in
    Calendar.current.startOfWeek(for: workout.date)
}
let frequency = grouped.map { (week, workouts) in
    WeeklyFrequencyPoint(weekStart: week, sessions: workouts.count)
}
```

**Edge cases**:
- Weeks with 0 sessions: Must fill gaps with zero-value entries so the chart shows continuous weeks.
- Workouts with status `.inProgress`: Include — they represent real training sessions.

---

### RQ-3: Muscle Group Distribution

**Question**: How to compute volume by muscle group for the last 4 weeks?

**Decision**: Fetch sets (4-week range) → look up each set's `Exercise.primaryMuscle` (cached) → sum volume per muscle group.

**Rationale**:
- 4 weeks × ~20 sets/session × ~4 sessions/week ≈ 320 sets max. Lightweight.
- Exercise metadata changes rarely; a `[UUID: Exercise]` cache in the service avoids N+1 queries.
- Primary muscle only (per planning decision). No secondary muscle weighting.

**Implementation approach**:
```swift
let sets = try await setRepository.fetchSets(from: cutoff4w, to: Date(), hasData: true)
let exerciseCache = try await buildExerciseCache(for: sets)
var volumeByMuscle: [String: Double] = [:]
for set in sets {
    guard let exercise = exerciseCache[set.exerciseId],
          let muscle = exercise.primaryMuscle else { continue }
    let volume = (set.effectiveWeight ?? 0) * Double(set.reps ?? 0)
    volumeByMuscle[muscle, default: 0] += volume
}
```

**Chart type**: Horizontal bar chart sorted by volume descending. Shows relative distribution at a glance. Reuses `MuscleGroupColors.color(for:)` from the Calendar feature.

**Alternatives considered**:
- Pie/donut chart: Can be hard to read with 6+ segments. Horizontal bars are clearer.
- Include secondary muscles with weighting: Adds complexity without clear user value for v1.

---

### RQ-4: Exercise Card Sparkline Data

**Question**: What data feeds the sparkline on per-exercise cards, and how to fetch efficiently?

**Decision**: Last 8 sessions' best e1RM per session for each exercise. Sparkline rendered as a minimal `LineMark` chart.

**Rationale**:
- e1RM is the most meaningful single metric for strength progress.
- 8 data points is enough to show a trend without cluttering a small card.
- The trend direction arrow (↑/↓/→) is derived from comparing the last 2 sparkline points.

**Implementation approach**:
- For each exercise with `ExerciseStats.lastPerformedDate != nil`:
  1. Fetch sets WHERE `exerciseId = ? AND hasData = true`, sorted by date DESC, limited to last ~30 sets
  2. Group by `workoutId`, take max `e1RM` per workout
  3. Take last 8 sessions' values
  4. Trend: compare last point vs second-to-last. Up if higher, down if lower, flat if equal.

**Performance consideration**: Loading sparkline data for ~50 exercises × ~30 sets each = ~1500 total set fetches. This can be batched or lazy-loaded as cards scroll into view. For v1, fetch all upfront — the total is bounded.

**Alternatives considered**:
- Use `ExerciseStats.bestE1RM` only (no sparkline): Loses the visual trend, which is the primary value of the card.
- Fetch from `PerformanceRecord` e1RM entries: These are point-in-time records, not a time series. Not ideal for sparklines.

---

### RQ-5: Rep PR Progression Multi-Line Chart

**Question**: How to build the multi-line chart showing 1RM, 3RM, and 5RM progression over time?

**Decision**: Query `PerformanceRecord` (type: `repMax`, reps IN [1, 3, 5]) for the exercise. For each record, use its `date` and `value` fields to build time-series lines.

**Rationale**:
- `PerformanceRecord` stores the date and value of each PR. But it only stores the *current* PR, not historical progression.
- To show progression over time, we need historical PR values. These can be reconstructed from `WorkoutSet` data.

**Revised approach**: Query `WorkoutSet` for the exercise in the selected date range. For each workout session, compute the best weight at 1, 3, and 5 reps. Plot these as three separate line series.

```swift
let sets = try await setRepository.fetchSets(exerciseId: id, from: rangeStart, to: Date())
let grouped = Dictionary(grouping: sets) { $0.workoutId }
var series1RM: [ChartPoint] = []
var series3RM: [ChartPoint] = []
var series5RM: [ChartPoint] = []

for (_, workoutSets) in grouped {
    guard let date = workoutSets.first?.date else { continue }
    for targetReps in [1, 3, 5] {
        let best = workoutSets
            .filter { ($0.reps ?? 0) >= targetReps && $0.hasData }
            .max(by: { ($0.effectiveWeight ?? 0) < ($1.effectiveWeight ?? 0) })
        if let best, let weight = best.effectiveWeight {
            // Append to appropriate series
        }
    }
}
```

**Edge cases**:
- Exercise with no 1-rep sets: That line series is empty, show only available lines.
- Missing sessions: Lines connect available points, gaps are expected.

---

### RQ-6: Time Range Selector Behavior

**Question**: How should the time range selector work? Does it re-fetch or filter cached data?

**Decision**: Re-fetch from the repository with the new date range predicate. Do not cache all-time data and filter client-side.

**Rationale**:
- Specdoc FR-009: "Charts MUST query only the needed date range, not all history."
- For the [All] option on a single exercise, this is still bounded (one exercise's sets only).
- Re-fetching ensures memory is proportional to the displayed range, not all-time data.

**Implementation**:
- `TimeRange` enum: `.threeMonths`, `.sixMonths`, `.oneYear`, `.all`
- Each has a computed `startDate: Date?` (nil for `.all` means no lower bound).
- On selection change, ViewModel calls `ChartDataService.fetchExerciseDetailCharts(exerciseId:, range:)` with new range.
- Previous chart data is replaced (not appended).

---

### RQ-7: Empty States

**Question**: What empty states are needed for the Charts Tab?

**Decision**: Four distinct empty states based on spec edge cases.

| Context | Condition | Message |
|---------|-----------|---------|
| Charts tab, no workouts at all | `ExerciseStats` table empty | Motivational empty state: "Start your first workout to see progress charts" |
| Overview chart, no data in range | No sets in the date range | "No data for this period" |
| Per exercise section, no exercises | No exercises with stats | Motivational empty state |
| Exercise detail, single data point | Only 1 session for exercise | Show point, no trendline. Label: "Need more sessions for trend" |

**Implementation**: Reuse the empty state pattern from `ExerciseChartsView.swift` (chart icon + message text).

---

### RQ-8: Reusing ExerciseChartsView Components

**Question**: How to extend the existing e1RM and volume charts to support time-range filtering in the detail screen?

**Decision**: Extract the chart rendering functions from `ExerciseChartsView` into reusable components that accept data arrays. The detail screen composes these alongside the two new chart types.

**Current state**: `ExerciseChartsView` takes `ExerciseChartData?` and renders e1RM + volume charts. It's used in Exercise Detail sub-tabs (Calendar, Active Workout).

**Extension approach**:
- Keep `ExerciseChartsView` as-is for existing usage (Exercise Detail sub-tabs).
- In `ExerciseChartsDetailView`, compose individual chart components directly:
  - Reuse the chart styling pattern (card background, axis styling, colors).
  - Create `TopWeightChart` and `RepPRProgressionChart` as new components following the same pattern.
- Extract shared chart styling into a `ChartCardModifier` or shared helper if duplication becomes excessive.

This avoids modifying the existing `ExerciseChartsView` API while reusing its visual patterns.
