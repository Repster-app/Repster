# Quickstart: Feature 013 — Home Screen

## Prerequisites

- Xcode 15+ with iOS 17.0+ SDK
- Existing project builds and runs (all prior features merged)
- Familiarity with: `@Observable` ViewModel pattern, `ServiceContainer` DI, design tokens

## Key Reference Files

| Purpose | Path |
|---------|------|
| Tab bar + FAB + active workout | `Reppo/App/ContentView.swift` |
| MainTab enum to rename | `Reppo/Features/Exercise/Models/ExerciseEnums.swift` |
| Programs placeholder to replace | `Reppo/Features/Exercise/Views/TabPlaceholderViews.swift` |
| ViewModel pattern reference | `Reppo/Features/Calendar/ViewModels/CalendarViewModel.swift` |
| Workout detail view to reuse | `Reppo/Features/Calendar/Views/CalendarWorkoutDetailView.swift` |
| WorkoutDetail / ExerciseGroup structs | `Reppo/Features/Calendar/ViewModels/CalendarViewModel.swift` |
| Design tokens (colors, spacing) | `Reppo/Core/Extensions/DesignTokens.swift` |
| Service protocols | `Reppo/Core/Services/Protocols/` |

## Implementation Order

1. Rename `MainTab.programs` → `.home` in `ExerciseEnums.swift`
2. Create `HomeViewModel.swift` with all data loading logic
3. Create sub-views: `WeekStripView`, `StartWorkoutCardView`, `QuickActionCardsView`, `ThisWeekActivityView`, `RecentWorkoutCardView`
4. Create `HomeView.swift` assembling all sub-views in a ScrollView
5. Create `CopyPreviousSheet.swift` for the copy previous modal
6. Update `ContentView.swift` — swap placeholder for HomeView, update tab item

## Service Methods You'll Use

```swift
// Active workout check
workoutService.getActiveWorkout() async throws -> Workout?

// Week data + activity
workoutService.fetchWorkouts(for: ClosedRange<Date>) async throws -> [Workout]

// Recent workouts
workoutService.fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout]

// Sets for stats + copy
setService.fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]
setService.fetchExerciseIds(for workoutId: UUID) async throws -> Set<UUID>
setService.save(_ set: WorkoutSet) async throws -> SetSaveResult

// Exercise lookup (cache these)
exerciseService.fetchExercise(_ id: UUID) async throws -> Exercise?

// Create / delete workouts
workoutService.startWorkout() async throws -> Workout
workoutService.deleteWorkout(_ id: UUID) async throws
```

## Verification Checklist

- [ ] Home tab is first tab, labeled "Home" with house icon
- [ ] Week strip shows Mon–Sun, today highlighted, dots on workout days
- [ ] Start Workout card body opens ExerciseListView in browse mode
- [ ] Start Workout [+] creates empty workout and opens ActiveWorkoutView
- [ ] Copy Previous sheet lists completed workouts with stats
- [ ] Copying duplicates working sets with pre-filled weight/reps
- [ ] Copy with active workout shows confirmation dialog
- [ ] Templates card shows "Coming soon"
- [ ] Activity section shows correct session count and bar chart
- [ ] Recent section shows last 5 completed workouts
- [ ] Tapping recent card navigates to workout detail
- [ ] Empty states display correctly for fresh app
- [ ] Data refreshes after returning from completed workout
- [ ] All touch targets ≥ 44pt, all colors match design system
