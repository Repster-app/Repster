# Research: Feature 013 — Home Screen

**Date**: 2026-03-01
**Status**: Complete — all unknowns resolved

---

## R1: Service Composition for Copy Previous Flow

**Decision**: Compose existing `WorkoutService` and `SetService` calls in `HomeViewModel`. No new service methods (per FR-016).

**Rationale**: The existing service protocols already expose all necessary operations. Adding a convenience method would violate the spec constraint and create coupling between features. The ViewModel can orchestrate the sequence clearly.

**Composition sequence**:
1. `workoutService.fetchAllWorkouts(limit: nil, offset: nil)` → filter `.completed`, display in sheet
2. User selects a workout → `setService.fetchSets(for: selectedWorkoutId)` → get source sets
3. `workoutService.getActiveWorkout()` → check if active workout exists
4. If active exists → show confirmation dialog (discard or cancel)
5. If discard → `workoutService.deleteWorkout(activeWorkoutId)`
6. `workoutService.startWorkout()` → create new workout
7. For each source set where `setType == .working`:
   - Create new `WorkoutSet` with same `exerciseId`, `weight`, `reps`, `setType`, `orderInWorkout`, `orderInExercise`
   - `setService.save(newSet)` → persist with PR pipeline

**Alternatives considered**:
- New `WorkoutService.copyWorkout()` method — rejected per FR-016
- Repository-level batch insert — rejected, skips PR pipeline

---

## R2: WorkoutDetail Struct Reuse

**Decision**: Reuse existing `WorkoutDetail` and `ExerciseGroup` structs from `CalendarViewModel.swift` for workout detail navigation.

**Rationale**: The structs are module-level (not nested in the class) and already contain exactly the data needed for the workout detail view. CalendarWorkoutDetailView accepts `[WorkoutDetail]`, so passing this from HomeViewModel is straightforward.

**Alternatives considered**:
- Define new structs in HomeViewModel — rejected, would duplicate identical definitions
- Move structs to shared Models folder — nice refactoring but out of scope for this feature

---

## R3: Recent Workout Card Data Shape

**Decision**: Create a lightweight `RecentWorkoutSummary` struct in HomeViewModel for card display. Only use full `WorkoutDetail` when navigating to the detail view (lazy load).

**Rationale**: The recent workout card only needs: date, exercise count, set count, duration, total volume, and muscle group tags. Loading full `ExerciseGroup` arrays (with all sets and stats) for 5 cards on the Home screen is wasteful. Compute summary stats during the initial fetch and defer full detail loading to tap.

**Data shape**:
```swift
struct RecentWorkoutSummary {
    let workout: Workout
    let exerciseCount: Int
    let setCount: Int       // working sets only
    let totalVolume: Double // sum of effectiveWeight × reps for working sets with hasData
    let muscleGroups: [String] // deduplicated primaryMuscle values
}
```

---

## R4: Week Strip Data Requirements

**Decision**: Fetch workouts for the current week's Mon–Sun range and derive workout dots from their dates.

**Method**: `workoutService.fetchWorkouts(for: mondayOfWeek...sundayOfWeek)` filtered to `.completed` status. Map to a `Set<Int>` of weekday indices (1=Mon...7=Sun) for dot display.

**Today highlighting**: Use `Calendar.current.isDateInToday()` for the current day cell.

---

## R5: This Week Activity Session Counting

**Decision**: Count each completed workout individually (confirmed in clarification session). Multiple workouts on the same day each count as separate sessions.

**Method**: `workoutService.fetchWorkouts(for: weekRange)` filtered to `.completed`. Count = array length. Bar chart: binary filled/empty per day (group by calendar day, mark days with ≥1 workout).

---

## R6: Navigation Pattern — Home Tab

**Decision**: Wrap the Home tab content in its own `NavigationStack` to support push navigation to workout detail views.

**Rationale**: CalendarView follows this same pattern — each tab manages its own NavigationStack. The outer NavigationStack in ContentView handles the FAB → ExerciseListView navigation. Home tab needs its own stack for Recent card → workout detail push.

**Implementation**: HomeView wraps its ScrollView content in a NavigationStack. Recent workout cards use `.navigationDestination` to push a detail view.

---

## R7: Data Refresh Strategy

**Decision**: Use `.task` for initial load. Use `.onAppear` or `onChange(of: showActiveWorkout)` to refresh after returning from active workout.

**Rationale**: The `.task` modifier runs once when the view appears. To refresh after finishing a workout (dismissing fullScreenCover), we need to detect when the Home screen reappears. Options:
- `.onAppear` fires when tab is reselected or fullScreenCover dismisses
- `onChange(of:)` on a binding from ContentView

The simplest approach: HomeViewModel exposes a `loadData()` async method called from both `.task` (initial) and `.onAppear` (refresh). Guard against redundant loads with a timestamp check.

---

## R8: Exercise Cache Strategy

**Decision**: Use an in-memory dictionary `[UUID: Exercise]` within HomeViewModel to cache exercises fetched during the session. Follows CalendarViewModel's established pattern.

**Rationale**: Multiple recent workouts may share exercises. Caching avoids redundant `exerciseService.fetchExercise()` calls. Cache lives for the ViewModel's lifetime — invalidated naturally when HomeView is recreated or data is reloaded.
