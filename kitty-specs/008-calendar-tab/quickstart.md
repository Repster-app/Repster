# Quickstart: 008 Calendar Tab

**Feature**: Calendar Tab
**Date**: 2026-02-27

## Prerequisites

- Feature 007 (Exercise List & Detail) merged — provides `ExerciseDetailView` for navigation
- Existing services: `WorkoutService`, `SetService`, `ExerciseService`, `StatsService`
- Existing repositories: `WorkoutRepository`, `SetRepository`, `ExerciseRepository`, `ExerciseStatsRepository`

## File Structure

```
Reppo/
├── Features/
│   └── Calendar/
│       ├── Views/
│       │   ├── CalendarView.swift              # Main calendar screen (split view)
│       │   ├── CalendarMonthView.swift          # Single month grid
│       │   ├── CalendarDayCell.swift            # Day cell with number + dots
│       │   ├── CalendarWorkoutDetailView.swift  # Workout detail container
│       │   └── Components/
│       │       ├── MuscleGroupDot.swift         # Colored dot indicator
│       │       ├── CalendarExerciseCard.swift   # Read-only exercise card with sets
│       │       └── SummaryStatsStrip.swift      # Volume/exercises/sets strip
│       └── ViewModels/
│           └── CalendarViewModel.swift          # @Observable, data loading + state
├── Core/
│   └── Extensions/
│       └── MuscleGroupColors.swift             # Muscle group → Color mapping
```

## Key Architecture Decisions

1. **No new SwiftData models** — reads from existing Workout, WorkoutSet, Exercise entities
2. **MVVM with existing services** — CalendarViewModel → WorkoutService/SetService/ExerciseService → Repositories → SwiftData
3. **Split view layout** — Calendar scrolls independently from workout detail
4. **Lazy data loading** — Fetch dot data for visible months + buffer, detail on tap
5. **Exercise cache** — CalendarViewModel caches `[UUID: Exercise]` to avoid repeated fetches

## Quick Verification

After implementation, verify:
- [ ] Calendar displays month grids with correct day layout
- [ ] Colored dots appear on dates with workouts
- [ ] Today has blue fill indicator
- [ ] "Today" button scrolls to current date
- [ ] Tapping a date shows workout detail in bottom section
- [ ] Summary stats show correct volume, exercise count, set count
- [ ] Exercise cards show sets with PR badges
- [ ] Tapping exercise card navigates to ExerciseDetailView
- [ ] Multiple workouts on same date both appear
- [ ] Date with no workout shows empty state
- [ ] Bottom navigation visible
- [ ] Screen transition < 200ms
