# Implementation Plan: Calendar Tab

**Branch**: `008-calendar-tab` | **Date**: 2026-02-27 | **Spec**: `kitty-specs/008-calendar-tab/spec.md`
**Input**: Feature specification from `kitty-specs/008-calendar-tab/spec.md`

## Summary

Build the Calendar Tab — a vertically scrollable calendar with muscle group dot indicators and inline workout detail. The calendar uses a custom `LazyVGrid`-based month grid (no third-party libs). Tapping a date reveals workout detail in a split-view layout (calendar top, detail bottom, independently scrollable). Muscle group colors are derived at read-time from `Workout → WorkoutSet → Exercise.primaryMuscle`. No new SwiftData entities required.

## Technical Context

**Language/Version**: Swift (latest stable), iOS 17.0+
**Primary Dependencies**: SwiftUI, SwiftData (existing)
**Storage**: SwiftData — reads from existing Workout, WorkoutSet, Exercise, ExerciseStats models
**Testing**: Manual testing for v1 (per constitution)
**Target Platform**: iOS 17.0+, iPhone only
**Project Type**: Mobile (single platform)
**Performance Goals**: Screen transition < 200ms, 60 FPS scrolling, < 100MB idle memory
**Constraints**: Dark mode only, no third-party UI libs, MVVM architecture, no new schema entities
**Scale/Scope**: < 1000 workouts for v1 dataset, calendar scrolls across all months with workout data

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| SwiftUI primary, UIKit only if needed | PASS | Fully custom SwiftUI calendar grid |
| MVVM: View → ViewModel → Service → Repository → SwiftData | PASS | CalendarViewModel → WorkoutService/SetService/ExerciseService |
| @Observable for ViewModels (not ObservableObject) | PASS | CalendarViewModel uses @Observable |
| No third-party UI libraries | PASS | Custom LazyVGrid-based calendar |
| No ModelContext in ViewModel | PASS | All data via service/repository layer |
| NavigationStack (not NavigationView) | PASS | ExerciseDetail push via NavigationStack |
| Dark mode only | PASS | All colors from DesignTokens.swift |
| No startup rebuild | PASS | Lazy-loads data on calendar appear |
| Database aggregation over Swift iteration | PASS | Uses existing pre-computed ExerciseStats where possible; in-memory derivation only for muscle group dots (bounded by visible month range) |
| Do not invent schema | PASS | 0 new SwiftData models, 0 new fields |
| SF Symbols for icons | PASS | "Today" button uses SF Symbol |
| Minimum 44x44pt tap targets | PASS | Day cells sized for comfortable tapping |
| Store metric, convert in UI | PASS | Reads existing effectiveWeight (kg), converts to user's unit preference for display |

**Post-Phase 1 re-check**: No violations. The in-memory muscle group derivation is bounded (max ~90 workouts for 3-month visible range) and follows the specdoc's "lazy compute first" guidance (Section 8.10).

## Project Structure

### Documentation (this feature)

```
kitty-specs/008-calendar-tab/
├── plan.md              # This file
├── research.md          # Phase 0 output — calendar grid, colors, data loading
├── data-model.md        # Phase 1 output — entity usage, derived structures
├── quickstart.md        # Phase 1 output — file structure, verification checklist
└── tasks.md             # Phase 2 output (NOT created by /spec-kitty.plan)
```

### Source Code (repository root)

```
Reppo/
├── Features/
│   └── Calendar/
│       ├── Views/
│       │   ├── CalendarView.swift              # Main screen: split-view container
│       │   ├── CalendarMonthView.swift          # Single month: header + 7-col grid
│       │   ├── CalendarDayCell.swift            # Day number + muscle group dots
│       │   ├── CalendarWorkoutDetailView.swift  # Workout detail: stats + exercise cards
│       │   └── Components/
│       │       ├── MuscleGroupDot.swift         # Colored circle indicator
│       │       ├── CalendarExerciseCard.swift   # Read-only exercise card with set rows
│       │       └── SummaryStatsStrip.swift      # Horizontal volume/exercises/sets strip
│       └── ViewModels/
│           └── CalendarViewModel.swift          # @Observable ViewModel
├── Core/
│   └── Extensions/
│       └── MuscleGroupColors.swift             # Muscle group string → Color mapping
└── App/
    └── ContentView.swift                        # Wire Calendar tab (may already be wired)
```

**Structure Decision**: Follows existing `Reppo/Features/{FeatureName}/Views/` and `Reppo/Features/{FeatureName}/ViewModels/` pattern established by Exercise and Workout features. New utility `MuscleGroupColors.swift` goes in `Core/Extensions/` alongside `DesignTokens.swift`.

## Engineering Alignment (Planning Decisions)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Calendar grid | Custom `LazyVGrid` (7-column) in `ScrollView`/`LazyVStack` | Full control, no dependencies, constitution compliance |
| 2 | Dot overflow | Max 3 dots + gray overflow indicator (+N) | Balance of information and visual cleanliness |
| 3 | Layout | Split view: scrollable calendar top, scrollable detail bottom | Keeps calendar accessible while viewing detail |
| 4 | Data loading | Fetch visible months + 1-month buffer, lazy compute muscle groups | Follows specdoc "lazy compute first" (S8.10), no new schema |
| 5 | Muscle group colors | 8-color static mapping + fallback for unknown groups | Design system has only 4 accents; extend with 4 new dark-theme-safe hues |
| 6 | Exercise caching | In-memory `[UUID: Exercise]` dictionary in ViewModel | Exercises rarely change; avoids N+1 queries |
| 7 | Multi-workout dates | Stack all workouts in detail area with separator | Simple, handles two-a-day sessions |
| 8 | Component reuse | ExerciseDetailView (push nav), PRBadgeView (badges) | From feature 007 and Workout feature |

## Component Architecture

### CalendarViewModel (@Observable)

```
Responsibilities:
├── selectedDate: Date?                    # Currently tapped date
├── calendarDotData: [Date: [String]]      # Date → muscle group names for dots
├── workoutsByDate: [Date: [Workout]]      # Date → workouts (for detail)
├── exerciseCache: [UUID: Exercise]        # Cached exercises
├── workoutDetails: [UUID: WorkoutDetail]  # Fetched workout details (on-demand)
│
├── loadDotsForVisibleRange(months:)       # Fetches dot data for visible + buffer
├── selectDate(_:)                         # Sets selected date, loads detail
├── scrollToToday()                        # Triggers scroll via ScrollViewReader
│
└── Dependencies (injected):
    ├── WorkoutService
    ├── SetService
    ├── ExerciseService
    └── StatsService
```

### View Hierarchy

```
CalendarView (NavigationStack)
├── VStack
│   ├── Header: "Calendar" title + "Today" button
│   ├── Upper ScrollView (calendar grid)
│   │   └── LazyVStack
│   │       └── ForEach(months) → CalendarMonthView
│   │           ├── Month/Year header label
│   │           ├── Weekday headers (S M T W T F S)
│   │           └── LazyVGrid(7-col) → CalendarDayCell
│   │               ├── Day number (blue fill if today, blue outline if scheduled)
│   │               ├── MuscleGroupDot × 3 + overflow
│   │               └── Selection highlight
│   │
│   └── Lower ScrollView (workout detail)
│       └── CalendarWorkoutDetailView
│           ├── Empty state ("No workout") if no workout
│           └── ForEach(workouts for selected date)
│               ├── Session label (if multiple workouts)
│               ├── SummaryStatsStrip (volume, exercises, sets)
│               └── ForEach(exercise groups)
│                   └── CalendarExerciseCard
│                       ├── Exercise header (name, set count)
│                       ├── Set rows (weight, reps, PR badge) — read-only
│                       └── Tap → NavigationLink to ExerciseDetailView
│
└── Bottom nav visible (TabView handles this)
```

### Data Flow

```
App Launch
  → CalendarView.onAppear
  → CalendarViewModel.loadDotsForVisibleRange(currentMonth ± 1)
    → WorkoutService.fetchWorkouts(for: expandedDateRange)
    → For each workout: SetService.fetchExerciseIds(for: workout.id)
    → For each exerciseId: ExerciseService.fetchExercise(id)  [→ cache]
    → Build calendarDotData: [Date: [String]]
    → Build workoutsByDate: [Date: [Workout]]

User taps a date
  → CalendarViewModel.selectDate(date)
  → If workouts exist for date:
    → For each workout: SetService.fetchSets(for: workout.id)
    → Group sets by exerciseId, ordered by orderInWorkout
    → Compute summary stats (volume, exercise count, set count)
    → Build WorkoutDetail objects
  → View updates: detail section shows workout data

User scrolls calendar to new months
  → Detect new visible range
  → CalendarViewModel.loadDotsForVisibleRange(newMonths)
  → Merge new dot data into existing dictionary

User taps exercise card
  → NavigationStack pushes ExerciseDetailView(exerciseId:)
  → Reused component from feature 007
```

## Complexity Tracking

No constitution violations. No complexity justifications needed.

## Parallel Work Analysis

This feature is small enough for a single implementer. No parallel work needed.

### Dependency Graph

```
WP01: Foundation (MuscleGroupColors, CalendarViewModel, CalendarView skeleton)
  → WP02: Calendar Grid (MonthView, DayCell, dots, today button)
  → WP03: Workout Detail (detail view, exercise cards, navigation, multi-workout)
```

Sequential: WP01 must complete before WP02/WP03. WP02 and WP03 can potentially run in parallel if the ViewModel API is stable, but sequential is simpler for a single implementer.
