# Quickstart: Exercise Info in Active Workout

**Feature**: 014-exercise-info-active-workout
**Date**: 2026-03-01

## What This Feature Does

Adds a contextual data section below the set table in the active workout view, showing three information cards:
1. **Estimated 1RM** (hero card) — Current session's best e1RM with historical comparison
2. **Last Workout** (compact card) — Top sets from the most recent previous session
3. **Est. for N reps** (compact card) — Suggested weight for the current rep target

## Prerequisites

- Active workout with at least one exercise
- Existing data layer: `WorkoutSet.e1RM` is pre-computed at save-time
- Existing services: `SetService`, `StatsService`, `HealthProfileRepository`
- Existing enum: `E1RMFormula` (needs `reverseCalculate` method added)

## Files to Create

| File | Type | Purpose |
|------|------|---------|
| `Reppo/Features/Workout/Models/ExerciseInfoData.swift` | Data model | Value types for Exercise Info display |
| `Reppo/Features/Workout/ViewModels/ExerciseInfoProvider.swift` | Helper | Computation logic for all 3 cards |
| `Reppo/Features/Workout/Views/Components/ExerciseInfoSectionView.swift` | View | Container with section header + cards |
| `Reppo/Features/Workout/Views/Components/E1RMCardView.swift` | View | Hero e1RM card |
| `Reppo/Features/Workout/Views/Components/LastWorkoutCardView.swift` | View | Compact last workout card |
| `Reppo/Features/Workout/Views/Components/EstimatedRepsCardView.swift` | View | Compact estimated reps card |

## Files to Modify

| File | Change |
|------|--------|
| `Reppo/Data/Enums/E1RMFormula.swift` | Add `reverseCalculate(e1RM:reps:)` method |
| `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift` | Add `exerciseInfoData` property, `loadExerciseInfo()` method, cache tracking |
| `Reppo/Features/Workout/Views/ActiveWorkoutView.swift` | Insert `ExerciseInfoSectionView` in `.sets` sub-tab ScrollView |

## Implementation Order

```
1. ExerciseInfoData.swift          ← Data model structs (no dependencies)
2. E1RMFormula.swift               ← Add reverseCalculate (no dependencies)
3. ExerciseInfoProvider.swift      ← Computation logic (depends on #1, #2)
4. E1RMCardView.swift              ← Hero card view (depends on #1)
5. LastWorkoutCardView.swift       ← Compact card view (depends on #1)
6. EstimatedRepsCardView.swift     ← Compact card view (depends on #1)
7. ExerciseInfoSectionView.swift   ← Container view (depends on #4, #5, #6)
8. ActiveWorkoutViewModel.swift    ← Integration (depends on #3)
9. ActiveWorkoutView.swift         ← Final wiring (depends on #7, #8)
```

## Key Design Decisions

1. **ExerciseInfoProvider** encapsulates all computation — keeps ViewModel clean
2. **Single data fetch** for all 3 cards — one `fetchSets` call, derive everything
3. **Cached by exerciseId** — cleared on exercise switch, matching existing pattern
4. **Visible in `.sets` sub-tab only** — not in History or Charts
5. **Inserted after SetTableView** in ScrollView — separate visual section, not inside set table
6. **Duration exercises** hide e1RM and Est. Reps cards — Last Workout adapts to show duration

## Verification Checklist

- [ ] e1RM card shows correct value based on today's best working set
- [ ] "Best today" shows weight × reps of the set that produced the best e1RM
- [ ] Historical comparison shows correct delta with green/red color coding
- [ ] Last Workout shows top 2 working sets from most recent previous session
- [ ] Relative time label shows correct "N days ago"
- [ ] Est. for N reps shows weight matching the user's most recent rep count
- [ ] Exercise Info updates when switching exercises via tab strip
- [ ] Empty states display gracefully for new exercises
- [ ] Duration-based exercises hide irrelevant cards
- [ ] Cards follow design-system.md: bgCard, 14pt radius, correct typography
- [ ] Loads within 500ms of exercise selection
- [ ] 60 FPS maintained while scrolling through section
- [ ] Weights display in correct unit (kg/lbs) based on HealthProfile
