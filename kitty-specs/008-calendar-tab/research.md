# Research: 008 Calendar Tab

**Feature**: Calendar Tab
**Date**: 2026-02-27
**Status**: Complete

## Research Questions

### RQ-1: Calendar Grid Implementation in SwiftUI

**Question**: How to build a vertically scrollable calendar with month grids in SwiftUI without third-party libraries?

**Decision**: Custom `LazyVGrid` (7-column) inside `ScrollView`/`LazyVStack`

**Rationale**: SwiftUI has no built-in calendar grid component. `UICalendarView` (UIKit, iOS 16+) exists but provides limited customization for dot indicators and inline detail below the calendar. A custom grid gives full control over:
- Muscle group dot placement and styling
- Selection behavior
- Today highlighting
- Split-view layout with detail below

**Implementation approach**:
- `LazyVStack` with a `ForEach` over months for vertical scrolling
- Each month renders a `LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 7))` for the 7-day week
- `Calendar.current.dateComponents` for date math (first weekday offset, days in month)
- `ScrollViewReader` + `scrollTo(id:)` for "Today" button

**Alternatives considered**:
- `UICalendarView` via `UIViewRepresentable`: Native look but poor customization for dots and inline detail. Bridging complexity.
- Third-party libraries (e.g., FSCalendar): Violates constitution "no third-party UI component libraries" rule.

---

### RQ-2: Muscle Group Color Mapping

**Question**: The design system defines no per-muscle-group colors. How should calendar dots be colored?

**Decision**: Define a static color mapping in a new `MuscleGroupColors` utility using the existing design token palette extended with additional hues.

**Rationale**: The current codebase stores muscle groups as `String` values on `Exercise.primaryMuscle`. The design system has only 4 accent colors (blue, green, gold, red). A workout can hit 6+ distinct muscle groups, so we need more colors while staying visually consistent with the dark theme.

**Proposed muscle group color palette** (8 colors to cover common groups):

| Muscle Group | Color | Hex | Reasoning |
|-------------|-------|-----|-----------|
| Chest | Blue | #5B8DEF | Uses existing accent |
| Back | Green | #5EC269 | Uses existing success |
| Shoulders | Gold/Yellow | #D4A23A | Uses existing gold |
| Legs/Quads | Red/Coral | #E05555 | Uses existing danger |
| Arms/Biceps | Purple | #9B7FE6 | New — distinct from existing |
| Triceps | Teal | #4ECDC4 | New — distinct from existing |
| Core/Abs | Orange | #E08850 | New — warm, distinct |
| Glutes/Hamstrings | Pink | #D46B9E | New — distinct from existing |

**Fallback**: Any unmatched muscle group string gets `Color.textTertiary` as a neutral dot.

**Implementation**: A static function `MuscleGroupColors.color(for: String) -> Color` with a switch on lowercased muscle group strings. Fuzzy matching for variations (e.g., "chest", "pectorals" → blue).

**Alternatives considered**:
- Single color for all dots: Loses the "which muscle groups were worked" information.
- Hash-based color generation: Unpredictable, could produce ugly/low-contrast colors on dark backgrounds.

---

### RQ-3: Data Loading for Calendar Dots

**Question**: How to efficiently load muscle group data for calendar dot indicators across months?

**Decision**: Fetch visible range + 1-month buffer. Derive muscle groups in-memory from the fetched data.

**Rationale**:
- The specdoc's guidance (Section 8.8, 8.10) says "query Workouts by date range, don't load all" and "lazy compute first, add pre-aggregation only if needed."
- The constitution's "do not invent" rule prevents adding a new pre-computed table.
- For v1 dataset sizes (< 1000 workouts), the query chain is fast:
  1. `WorkoutRepository.fetchWorkouts(for: dateRange)` — returns workouts for ~3 months
  2. `SetRepository.fetchExerciseIds(for: workoutId)` — returns unique exercise IDs per workout
  3. `ExerciseService.fetchExercise(_:)` — gets `primaryMuscle` per exercise
- The exercises can be cached in a local dictionary during the calendar session since exercise data rarely changes.

**Data flow**:
```
Visible months change
  → WorkoutService.fetchWorkouts(for: expandedDateRange)
  → For each workout: SetService.fetchExerciseIds(for: workout.id)
  → For each exerciseId: ExerciseService.fetchExercise(exerciseId)  [cached]
  → Build [Date: [String]] mapping (date → unique muscle groups)
  → CalendarDayCell reads muscle groups for its date
```

**Performance considerations**:
- Exercise objects are cached in `CalendarViewModel` (`[UUID: Exercise]`) to avoid redundant fetches
- Date range expanded by 1 month in each direction as buffer
- On scroll, only fetch new months not already cached
- Keep a `[Date: [String]]` dictionary for dot data; update incrementally

**Alternatives considered**:
- Fetch all workout dates upfront: Simple but scales poorly over years.
- Add `WorkoutSummary` cache table: Fast reads but violates "do not invent" rule. Could be added later if performance testing shows need.

---

### RQ-4: Split View Layout Pattern

**Question**: How to implement the split-view layout with independently scrollable calendar and workout detail?

**Decision**: `VStack` with `GeometryReader` for proportional sizing. Calendar in upper `ScrollView`, detail in lower `ScrollView`. Divider between them.

**Implementation**:
- Use `GeometryReader` to split the screen (e.g., 55% calendar, 45% detail — adjustable)
- Upper section: `ScrollView` containing `LazyVStack` of month grids
- Lower section: `ScrollView` with workout detail (summary stats + exercise cards)
- When no date is selected or date has no workout, show empty state in lower section
- Smooth animation when detail appears/disappears

**Alternatives considered**:
- Single ScrollView with everything: Detail at the bottom can be far from the tapped date. User loses calendar context when scrolling to detail.
- Calendar collapses on tap: Adds animation complexity. User may want to tap adjacent dates without re-expanding.

---

### RQ-5: Workout Detail Component Design

**Question**: What components are needed for the inline workout detail, and which can be reused from existing features?

**Decision**: Reuse where possible, create new `CalendarWorkoutDetailView` as the container.

**Reusable from existing codebase** (per screen_tree Section 8):
- `ExerciseDetailView` — full screen push navigation on exercise card tap (from feature 007)
- `PRBadgeView` — gold/blue badge on set rows (from Workout feature)
- Set row display pattern — from `SetRowView` (make read-only variant)

**New components needed**:
- `CalendarWorkoutDetailView` — Container for summary stats + exercise cards for a selected date
- `WorkoutSummaryStatsStrip` — Horizontal strip showing volume, exercise count, set count (may already exist as pattern in `WorkoutSummarySheet`)
- `CalendarExerciseCard` — Exercise card showing sets/weights/reps/PR badges (similar to day-view Exercise Card pattern from design-system Section 6.2, but read-only)
- `CalendarView` — Main calendar screen
- `CalendarMonthView` — Single month grid
- `CalendarDayCell` — Individual day cell with dots
- `MuscleGroupDot` — Colored dot indicator

**Navigation**: Tapping an exercise card pushes `ExerciseDetailView` via NavigationStack.

---

### RQ-6: Multiple Workouts per Date

**Question**: How to handle multiple workouts on the same date (User Story 3)?

**Decision**: When a date has multiple workouts, show all of them stacked in the detail area with clear separation.

**Implementation**:
- `WorkoutService.fetchWorkouts(for: dateRange)` already returns all workouts for a date
- Group workouts by date in the ViewModel: `[Date: [Workout]]`
- In the detail view, `ForEach` over workouts for the selected date
- Each workout gets its own summary stats strip and exercise card section
- Visual separator between workouts (e.g., subtle divider + optional timestamp label like "Morning Session" / "Evening Session" using `startTime`)
- Muscle group dots on the calendar merge all muscle groups from all workouts on that date
