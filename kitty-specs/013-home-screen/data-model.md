# Data Model: Feature 013 — Home Screen

**Date**: 2026-03-01

---

## Overview

No new SwiftData `@Model` classes are required. The Home screen reads from existing `Workout`, `WorkoutSet`, and `Exercise` models via existing services. This document defines the **view-layer data structures** used by `HomeViewModel` to shape data for the UI.

---

## New View-Layer Structs

### RecentWorkoutSummary

Lightweight struct for displaying recent workout cards on the Home screen. Avoids loading full set arrays just for card display.

```swift
struct RecentWorkoutSummary: Identifiable {
    let id: UUID              // workout.id
    let workout: Workout      // reference to full model (for detail navigation)
    let date: Date            // workout.date
    let exerciseCount: Int    // count of unique exerciseIds
    let setCount: Int         // count of working sets with hasData
    let durationMinutes: Int  // workout.duration / 60 (or 0 if nil)
    let totalVolume: Double   // sum(effectiveWeight × reps) for working sets with hasData
    let muscleGroups: [String] // deduplicated exercise.primaryMuscle values
}
```

**Derivation**:
- `exerciseCount`: `setService.fetchExerciseIds(for: workoutId).count`
- `setCount`: `setService.fetchSets(for: workoutId)` → filter `.working` + `hasData` → `.count`
- `totalVolume`: same filtered sets → `reduce(0) { $0 + ($1.volume ?? 0) }`
- `muscleGroups`: exercise IDs → `exerciseService.fetchExercise()` → collect unique `primaryMuscle.displayName`
- `durationMinutes`: `(workout.duration ?? 0) / 60`

### WeekDay

Represents a single day cell in the week strip.

```swift
struct WeekDay: Identifiable {
    let id: Int               // weekday index 0-6 (Mon=0, Sun=6)
    let abbreviation: String  // "M", "T", "W", "T", "F", "S", "S"
    let dateNumber: Int       // day of month (1-31)
    let date: Date            // full date for this day
    let isToday: Bool         // Calendar.current.isDateInToday(date)
    let hasWorkout: Bool      // at least one completed workout on this date
}
```

### CopyPreviousWorkout

Struct for displaying a workout in the Copy Previous sheet.

```swift
struct CopyPreviousWorkout: Identifiable {
    let id: UUID              // workout.id
    let workout: Workout      // reference for copying sets
    let date: Date            // workout.date
    let exerciseCount: Int    // count of unique exerciseIds
    let setCount: Int         // working sets with hasData
    let totalVolume: Double   // volume calculation
    let muscleGroups: [String] // primary muscle groups
}
```

---

## Existing Models Referenced (No Changes)

### Workout (`Reppo/Data/Models/Workout.swift`)

| Property | Type | Used By Home Screen |
|----------|------|-------------------|
| `id` | `UUID` | Identification, navigation |
| `date` | `Date` | Display date, week strip dots |
| `startTime` | `Date?` | — |
| `endTime` | `Date?` | — |
| `duration` | `Int?` | Duration display (seconds → minutes) |
| `status` | `WorkoutStatus` | Filter: `.completed` only |

### WorkoutSet (`Reppo/Data/Models/WorkoutSet.swift`)

| Property | Type | Used By Home Screen |
|----------|------|-------------------|
| `id` | `UUID` | Set identification |
| `workoutId` | `UUID` | Join to workout |
| `exerciseId` | `UUID` | Join to exercise, muscle group lookup |
| `setType` | `SetType` | Filter: `.working` for stats, copy |
| `weight` | `Double?` | Pre-fill in copied sets |
| `reps` | `Int?` | Pre-fill in copied sets |
| `effectiveWeight` | `Double?` | Volume calculation |
| `orderInWorkout` | `Int` | Preserve order in copy |
| `orderInExercise` | `Int` | Preserve order in copy |
| `completed` | `Bool` | — |
| `hasData` | `Bool` (computed) | Filter sets with actual values |
| `volume` | `Double?` (computed) | Per-set volume |

### Exercise (`Reppo/Data/Models/Exercise.swift`)

| Property | Type | Used By Home Screen |
|----------|------|-------------------|
| `id` | `UUID` | Cache key, lookup |
| `name` | `String` | — (not displayed on cards) |
| `primaryMuscle` | `MuscleGroup` | Muscle group tags on cards |

---

## HomeViewModel State Properties

```swift
@Observable
@MainActor
final class HomeViewModel {
    // MARK: - State

    // Week strip
    var weekDays: [WeekDay] = []

    // Active workout detection
    var hasActiveWorkout: Bool = false

    // This Week Activity
    var thisWeekWorkoutCount: Int = 0
    var thisWeekWorkoutDays: Set<Int> = []  // weekday indices with workouts (0=Mon)
    let weeklyGoal: Int = 4                 // hardcoded for v1

    // Recent workouts
    var recentWorkouts: [RecentWorkoutSummary] = []

    // Copy Previous
    var showCopyPreviousSheet: Bool = false
    var copyPreviousWorkouts: [CopyPreviousWorkout] = []
    var showDiscardConfirmation: Bool = false
    var pendingCopyWorkoutId: UUID? = nil

    // Loading
    var isLoading: Bool = false

    // MARK: - Dependencies

    private let workoutService: any WorkoutServiceProtocol
    private let setService: any SetServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol

    // MARK: - Cache

    private var exerciseCache: [UUID: Exercise] = [:]
}
```

---

## Data Flow Diagram

```
App Launch / Tab Selection
         │
         ▼
   HomeViewModel.loadData()
         │
         ├──► workoutService.getActiveWorkout()
         │         └──► hasActiveWorkout = (result != nil)
         │
         ├──► workoutService.fetchWorkouts(for: weekRange)
         │         ├──► weekDays (dots for completed workouts)
         │         ├──► thisWeekWorkoutCount (total completed)
         │         └──► thisWeekWorkoutDays (days with workouts)
         │
         └──► workoutService.fetchAllWorkouts(limit: 5, offset: 0)
                   │   filter: .completed, sorted by date DESC
                   │
                   └──► For each workout:
                            ├── setService.fetchSets(for: workoutId)
                            ├── setService.fetchExerciseIds(for: workoutId)
                            ├── exerciseService.fetchExercise(id) [cached]
                            └──► RecentWorkoutSummary

Copy Previous Flow:
   User taps "Copy Previous"
         │
         ▼
   showCopyPreviousSheet = true
   workoutService.fetchAllWorkouts() → filter .completed
         │
         ▼
   User selects workout
         │
         ├── workoutService.getActiveWorkout()
         │         ├── nil → proceed to copy
         │         └── exists → showDiscardConfirmation = true
         │                        ├── Cancel → dismiss
         │                        └── Discard → deleteWorkout() → proceed
         │
         ▼
   setService.fetchSets(for: sourceWorkoutId)
   filter: setType == .working
   workoutService.startWorkout() → newWorkout
   For each source set:
       create WorkoutSet(workoutId: newWorkout.id, ...)
       setService.save(newSet)
         │
         ▼
   ContentView.showActiveWorkout = true
```

---

## Relationships

```
HomeView ──uses──► HomeViewModel
   │
   ├── WeekStripView ◄── weekDays: [WeekDay]
   ├── StartWorkoutCardView ◄── hasActiveWorkout: Bool
   ├── QuickActionCardsView ◄── triggers copyPrevious / templates
   ├── ThisWeekActivityView ◄── thisWeekWorkoutCount, thisWeekWorkoutDays
   ├── RecentWorkoutCardView ◄── recentWorkouts: [RecentWorkoutSummary]
   └── CopyPreviousSheet ◄── copyPreviousWorkouts: [CopyPreviousWorkout]

HomeViewModel ──calls──► WorkoutServiceProtocol (existing)
HomeViewModel ──calls──► SetServiceProtocol (existing)
HomeViewModel ──calls──► ExerciseServiceProtocol (existing)
```
