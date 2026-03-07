---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
  - "T005"
  - "T006"
  - "T007"
title: "HomeViewModel — Foundation & Data Loading"
phase: "Phase 1 - Foundation"
lane: "done"
assignee: "claude-opus"
agent: "claude-opus-reviewer"
shell_pid: "64485"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: []
history:
  - timestamp: "2026-03-01T17:56:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-03-01T18:16:02Z"
    lane: "doing"
    agent: "claude-opus"
    shell_pid: "62091"
    action: "Started implementation"
  - timestamp: "2026-03-01T18:22:53Z"
    lane: "for_review"
    agent: "claude-opus"
    shell_pid: "62091"
    action: "Ready for review"
  - timestamp: "2026-03-01T18:24:48Z"
    lane: "done"
    agent: "claude-opus-reviewer"
    shell_pid: "64485"
    action: "Review passed"
---

# Work Package Prompt: WP01 – HomeViewModel — Foundation & Data Loading

## Implementation Command

```bash
spec-kitty implement WP01
```

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- Rename `MainTab.programs` to `.home` across the codebase.
- Create `HomeViewModel` with all state properties, data structures, and data loading methods for the Home screen's read-only sections.
- After calling `loadData()`, all state properties are populated: `weekDays`, `hasActiveWorkout`, `thisWeekWorkoutCount`, `thisWeekWorkoutDays`, `recentWorkouts`.
- Exercise cache prevents redundant service calls when multiple workouts share exercises.

## Context & Constraints

- **Architecture**: `@Observable` + `@MainActor` pattern (same as `CalendarViewModel`).
- **Constitution**: Views → ViewModels → Services → Repositories. No layer skipping.
- **FR-016**: No new service or repository methods. Compose existing calls only.
- **Spec**: `kitty-specs/013-home-screen/spec.md`
- **Plan**: `kitty-specs/013-home-screen/plan.md`
- **Data Model**: `kitty-specs/013-home-screen/data-model.md`
- **Reference ViewModel**: `Reppo/Features/Calendar/ViewModels/CalendarViewModel.swift` — follow the same patterns for caching, error handling, and data aggregation.

### Key Service Methods Available

```swift
// WorkoutServiceProtocol
func getActiveWorkout() async throws -> Workout?
func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout]
func fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout]

// SetServiceProtocol
func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]
func fetchExerciseIds(for workoutId: UUID) async throws -> Swift.Set<UUID>

// ExerciseServiceProtocol
func fetchExercise(_ exerciseId: UUID) async throws -> Exercise?
```

---

## Subtasks & Detailed Guidance

### Subtask T001 – Rename MainTab.programs → .home

**Purpose**: Update the tab enum to reflect the new Home tab identity.

**Steps**:
1. Open `Reppo/Features/Exercise/Models/ExerciseEnums.swift`.
2. Change `case programs = 0` to `case home = 0`.
3. No other cases change (calendar = 1, charts = 2, settings = 3).

**Files**:
- `Reppo/Features/Exercise/Models/ExerciseEnums.swift` (modify line ~9)

**Notes**: ContentView.swift references `MainTab.programs` in multiple places — those will be updated in WP04. For now, just rename the enum case. The compiler will flag all usages, but they'll be fixed in WP04. If the project doesn't compile after this change alone, that's expected — WP04 handles ContentView updates.

### Subtask T002 – Create HomeViewModel class structure

**Purpose**: Establish the ViewModel class with all state properties, data structures, and service dependencies.

**Steps**:
1. Create directory `Reppo/Features/Home/ViewModels/` (and `Reppo/Features/Home/Views/` for later WPs).
2. Create `Reppo/Features/Home/ViewModels/HomeViewModel.swift`.
3. Define three data structs at the top of the file (module-level, not nested):

```swift
struct WeekDay: Identifiable {
    let id: Int               // 0-6 (Mon=0, Sun=6)
    let abbreviation: String  // "M", "T", "W", "T", "F", "S", "S"
    let dateNumber: Int       // day of month (1-31)
    let date: Date            // full date for this day
    let isToday: Bool
    let hasWorkout: Bool
}

struct RecentWorkoutSummary: Identifiable {
    let id: UUID              // workout.id
    let workout: Workout
    let date: Date
    let exerciseCount: Int
    let setCount: Int         // working sets with hasData
    let durationMinutes: Int
    let totalVolume: Double   // sum(effectiveWeight × reps) for working sets with hasData
    let muscleGroups: [String]
}

struct CopyPreviousWorkout: Identifiable {
    let id: UUID
    let workout: Workout
    let date: Date
    let exerciseCount: Int
    let setCount: Int
    let totalVolume: Double
    let muscleGroups: [String]
}
```

4. Define the ViewModel class:

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
    var thisWeekWorkoutDays: Set<Int> = []  // 0=Mon..6=Sun
    let weeklyGoal: Int = 4

    // Recent workouts
    var recentWorkouts: [RecentWorkoutSummary] = []

    // Copy Previous (state managed here, logic in WP02)
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

    init(
        workoutService: any WorkoutServiceProtocol,
        setService: any SetServiceProtocol,
        exerciseService: any ExerciseServiceProtocol
    ) {
        self.workoutService = workoutService
        self.setService = setService
        self.exerciseService = exerciseService
    }

    // MARK: - Cache Helper

    private func cachedExercise(_ id: UUID) async throws -> Exercise? {
        if let cached = exerciseCache[id] {
            return cached
        }
        let exercise = try await exerciseService.fetchExercise(id)
        if let exercise {
            exerciseCache[id] = exercise
        }
        return exercise
    }
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (new file, ~120 lines)

**Notes**:
- Use `any WorkoutServiceProtocol` (existential) for property types — matches CalendarViewModel pattern.
- The `cachedExercise()` helper is identical to CalendarViewModel's — follow the same pattern.
- Copy Previous state properties (`showCopyPreviousSheet`, `showDiscardConfirmation`, `pendingCopyWorkoutId`) are declared here but their logic is implemented in WP02.

### Subtask T003 – Implement checkActiveWorkout()

**Purpose**: Check if an active workout exists so the Start Workout card can show the correct behavior (start new vs. resume).

**Steps**:
1. Add method to HomeViewModel:

```swift
func checkActiveWorkout() async {
    do {
        let active = try await workoutService.getActiveWorkout()
        hasActiveWorkout = (active != nil)
    } catch {
        print("[HomeViewModel] Failed to check active workout: \(error)")
        hasActiveWorkout = false
    }
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add method)

### Subtask T004 – Implement loadWeekStrip()

**Purpose**: Fetch workouts for the current week (Mon–Sun) and build the `[WeekDay]` array with today highlighting and workout dots.

**Steps**:
1. Add method to HomeViewModel:

```swift
func loadWeekStrip() async {
    let calendar = Calendar.current

    // 1. Find Monday of current week (weekday 2 in gregorian, but use .monday)
    let today = Date()
    var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
    components.weekday = 2 // Monday
    guard let monday = calendar.date(from: components) else { return }

    // 2. Build date range Mon–Sun
    guard let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else { return }
    let weekRange = calendar.startOfDay(for: monday)...calendar.startOfDay(for: sunday).addingTimeInterval(86399)

    // 3. Fetch completed workouts in range
    do {
        let workouts = try await workoutService.fetchWorkouts(for: weekRange)
        let completedWorkouts = workouts.filter { $0.status == .completed }

        // 4. Derive which days have workouts
        var workoutDayIndices: Set<Int> = []
        for workout in completedWorkouts {
            let weekday = calendar.component(.weekday, from: workout.date)
            // Convert: Sun=1..Sat=7 → Mon=0..Sun=6
            let index = (weekday + 5) % 7
            workoutDayIndices.insert(index)
        }

        // 5. Build WeekDay array
        let abbreviations = ["M", "T", "W", "T", "F", "S", "S"]
        var days: [WeekDay] = []
        for i in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: i, to: monday) else { continue }
            let dateNumber = calendar.component(.day, from: dayDate)
            days.append(WeekDay(
                id: i,
                abbreviation: abbreviations[i],
                dateNumber: dateNumber,
                date: dayDate,
                isToday: calendar.isDateInToday(dayDate),
                hasWorkout: workoutDayIndices.contains(i)
            ))
        }

        weekDays = days
    } catch {
        print("[HomeViewModel] Failed to load week strip: \(error)")
    }
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add method)

**Notes**:
- The weekday conversion (`(weekday + 5) % 7`) maps Sunday=1 to index 6, Monday=2 to index 0, etc.
- `calendar.startOfDay(for:)` normalizes dates for comparison.
- The date range includes the full Sunday by adding 86399 seconds (23:59:59).

### Subtask T005 – Implement loadThisWeekActivity()

**Purpose**: Count completed workouts this week and identify which days had workouts for the activity bar chart.

**Steps**:
1. Add method to HomeViewModel. This reuses the same week range as `loadWeekStrip()`, so refactor to share the range computation. One approach: compute the week range once in `loadData()` and pass it, or extract a helper:

```swift
private func currentWeekRange() -> ClosedRange<Date>? {
    let calendar = Calendar.current
    var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
    components.weekday = 2
    guard let monday = calendar.date(from: components),
          let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else { return nil }
    return calendar.startOfDay(for: monday)...calendar.startOfDay(for: sunday).addingTimeInterval(86399)
}
```

2. Then `loadThisWeekActivity()` can share the fetched workouts with `loadWeekStrip()`. Alternatively, pass the already-fetched workouts from `loadData()`:

```swift
private func loadWeekData() async {
    guard let weekRange = currentWeekRange() else { return }
    do {
        let workouts = try await workoutService.fetchWorkouts(for: weekRange)
        let completed = workouts.filter { $0.status == .completed }

        // Week strip (T004 logic)
        buildWeekDays(from: completed, weekRange: weekRange)

        // Activity (T005 logic)
        let calendar = Calendar.current
        thisWeekWorkoutCount = completed.count
        thisWeekWorkoutDays = Set(completed.map { workout in
            let weekday = calendar.component(.weekday, from: workout.date)
            return (weekday + 5) % 7
        })
    } catch {
        print("[HomeViewModel] Failed to load week data: \(error)")
    }
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add method or refactor T004)

**Notes**:
- Session counting: each completed workout counts individually, even multiple on the same day (per clarification).
- `thisWeekWorkoutDays` is used for the bar chart (binary filled/empty per day).
- `thisWeekWorkoutCount` is the total count for the "X / 4 sessions" display.

### Subtask T006 – Implement loadRecentWorkouts()

**Purpose**: Fetch the 5 most recent completed workouts and build summary data for the Recent section cards.

**Steps**:
1. Add method to HomeViewModel:

```swift
func loadRecentWorkouts() async {
    do {
        // 1. Fetch workouts (may include in-progress — filter)
        let allWorkouts = try await workoutService.fetchAllWorkouts(limit: nil, offset: nil)
        let completed = allWorkouts
            .filter { $0.status == .completed }
            .sorted { $0.date > $1.date }  // reverse chronological
            .prefix(5)

        // 2. Build summaries
        var summaries: [RecentWorkoutSummary] = []
        for workout in completed {
            let sets = try await setService.fetchSets(for: workout.id)
            let workingSetsWithData = sets.filter { $0.setType == .working && $0.hasData }
            let totalVolume = workingSetsWithData.compactMap(\.volume).reduce(0, +)
            let exerciseIds = try await setService.fetchExerciseIds(for: workout.id)

            // Derive muscle groups (deduplicated)
            var muscleGroups: [String] = []
            for exerciseId in exerciseIds {
                if let exercise = try await cachedExercise(exerciseId),
                   let muscle = exercise.primaryMuscle,
                   !muscleGroups.contains(muscle) {
                    muscleGroups.append(muscle)
                }
            }

            summaries.append(RecentWorkoutSummary(
                id: workout.id,
                workout: workout,
                date: workout.date,
                exerciseCount: exerciseIds.count,
                setCount: workingSetsWithData.count,
                durationMinutes: (workout.duration ?? 0) / 60,
                totalVolume: totalVolume,
                muscleGroups: muscleGroups
            ))
        }

        recentWorkouts = summaries
    } catch {
        print("[HomeViewModel] Failed to load recent workouts: \(error)")
    }
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add method)

**Notes**:
- `fetchAllWorkouts(limit: nil, offset: nil)` fetches all workouts. Filter to `.completed` and take first 5 after sorting.
- Volume = sum of `effectiveWeight × reps` (i.e., `WorkoutSet.volume`) for working sets with `hasData == true`.
- Muscle groups are deduplicated strings from `exercise.primaryMuscle`.
- Exercise cache (`cachedExercise()`) prevents redundant fetches across workouts.

### Subtask T007 – Implement loadData() orchestration

**Purpose**: Single entry point that loads all Home screen data, called from `.task` and `.onAppear`.

**Steps**:
1. Add method to HomeViewModel:

```swift
func loadData() async {
    isLoading = true
    defer { isLoading = false }

    // Load week data (strip + activity) — shares one fetch
    await loadWeekData()

    // Check active workout
    await checkActiveWorkout()

    // Load recent workouts
    await loadRecentWorkouts()
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add method)

**Notes**:
- Methods are called sequentially for simplicity. The total should stay well under 1 second (SC-001) given the bounded data sizes.
- `isLoading` can be used by the View for a loading indicator if desired, but the Home screen should feel instant for typical data sizes.
- `loadData()` is safe to call multiple times (idempotent — overwrites state).

---

## Risks & Mitigations

- **`fetchAllWorkouts` returns in-progress workouts**: Always filter to `.completed` before displaying.
- **Week boundary**: `currentWeekRange()` helper ensures Mon–Sun alignment regardless of device locale's `firstWeekday` setting. Use explicit weekday = 2 (Monday).
- **Exercise not found**: `cachedExercise()` returns `nil` if exercise was deleted — skip gracefully (don't crash).
- **Empty state**: If no workouts exist, all arrays will be empty and counts will be 0. Views handle this in WP03/WP04.

## Definition of Done Checklist

- [ ] `MainTab.programs` renamed to `.home` in ExerciseEnums.swift
- [ ] `HomeViewModel.swift` created in `Reppo/Features/Home/ViewModels/`
- [ ] All three data structs defined (`WeekDay`, `RecentWorkoutSummary`, `CopyPreviousWorkout`)
- [ ] `checkActiveWorkout()` correctly sets `hasActiveWorkout`
- [ ] `loadWeekStrip()` builds 7 `WeekDay` entries with correct today/dots
- [ ] `loadThisWeekActivity()` counts sessions and identifies workout days
- [ ] `loadRecentWorkouts()` builds up to 5 summaries with correct stats
- [ ] `loadData()` orchestrates all methods
- [ ] Exercise cache prevents redundant fetches
- [ ] Error handling via print statements (no crashes)

## Review Guidance

- Verify `@Observable` and `@MainActor` annotations are present.
- Verify service protocols use `any` keyword (existential types).
- Check weekday conversion math: Monday must be index 0, Sunday index 6.
- Check volume calculation uses `setType == .working && hasData` filter.
- Verify muscle group deduplication.
- Ensure `fetchAllWorkouts` result is filtered to `.completed` status.

## Activity Log

- 2026-03-01T17:56:08Z – system – lane=planned – Prompt created.
- 2026-03-01T18:16:02Z – claude-opus – shell_pid=62091 – lane=doing – Started implementation via workflow command
- 2026-03-01T18:22:53Z – claude-opus – shell_pid=62091 – lane=for_review – Ready for review: HomeViewModel foundation with all data loading methods, MainTab rename, and Xcode project integration. Build succeeds.
- 2026-03-01T18:23:24Z – claude-opus-reviewer – shell_pid=64485 – lane=doing – Started review via workflow command
- 2026-03-01T18:24:48Z – claude-opus-reviewer – shell_pid=64485 – lane=done – Review passed: All 7 subtasks verified. Architecture (@Observable/@MainActor, bare protocols) matches CalendarViewModel pattern. Weekday math correct (Mon=0..Sun=6). Volume filter (working+hasData), muscle dedup, exercise cache, .completed filter all correct. Build succeeds. Xcode project properly updated. No issues.
- 2026-03-01T18:50:42Z – claude-opus-reviewer – shell_pid=64485 – lane=done – Review approved, moved to done
