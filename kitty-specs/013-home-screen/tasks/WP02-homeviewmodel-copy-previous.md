---
work_package_id: "WP02"
subtasks:
  - "T008"
  - "T009"
  - "T010"
  - "T011"
title: "HomeViewModel — Copy Previous & Workout Actions"
phase: "Phase 1 - Foundation"
lane: "done"
assignee: "claude-opus"
agent: "claude-opus-reviewer"
shell_pid: "65596"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01"]
history:
  - timestamp: "2026-03-01T17:56:08Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-03-01T18:25:31Z"
    lane: "doing"
    agent: "claude-opus"
    shell_pid: "62091"
    action: "Started implementation"
  - timestamp: "2026-03-01T18:30:29Z"
    lane: "for_review"
    agent: "claude-opus"
    shell_pid: "62091"
    action: "Ready for review"
  - timestamp: "2026-03-01T18:31:03Z"
    lane: "done"
    agent: "claude-opus-reviewer"
    shell_pid: "65596"
    action: "Review passed"
---

# Work Package Prompt: WP02 – HomeViewModel — Copy Previous & Workout Actions

## Implementation Command

```bash
spec-kitty implement WP02 --base WP01
```

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- Add workout action methods to HomeViewModel: start empty workout, load copy candidates, copy a past workout.
- Copy Previous correctly duplicates working sets with pre-filled weight and reps from the source workout.
- Active workout conflict is detected and handled via confirmation dialog state.
- `discardActiveAndCopy()` deletes the active workout before creating the copied one.

## Context & Constraints

- **Spec**: `kitty-specs/013-home-screen/spec.md` — User Story 4, FR-007, FR-008, clarifications.
- **Plan**: `kitty-specs/013-home-screen/plan.md` — Copy Previous section.
- **Research**: `kitty-specs/013-home-screen/research.md` — R1 (service composition for copy flow).
- **FR-016**: No new service/repository methods. Compose existing calls.
- **Clarifications**: Working sets only (no warmup). Pre-fill weight/reps from source. Confirmation dialog if active workout exists.
- **Constitution**: All data access via services. Weight stored in kg. Sets persist immediately via `setService.save()`.

### Key Service Methods

```swift
// WorkoutServiceProtocol
func startWorkout() async throws -> Workout
func getActiveWorkout() async throws -> Workout?
func deleteWorkout(_ workoutId: UUID) async throws

// SetServiceProtocol
func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]
func save(_ set: WorkoutSet) async throws -> SetSaveResult
```

### State Properties (from WP01)

These are already declared in HomeViewModel:
```swift
var showCopyPreviousSheet: Bool = false
var copyPreviousWorkouts: [CopyPreviousWorkout] = []
var showDiscardConfirmation: Bool = false
var pendingCopyWorkoutId: UUID? = nil
```

---

## Subtasks & Detailed Guidance

### Subtask T008 – Implement startEmptyWorkout()

**Purpose**: Create a new empty workout for the [+] button on the Start Workout card.

**Steps**:
1. Add method to HomeViewModel:

```swift
/// Start an empty workout. Returns the workout for the caller to trigger navigation.
func startEmptyWorkout() async throws -> Workout {
    // startWorkout() returns existing active workout if one exists (FR-004)
    let workout = try await workoutService.startWorkout()
    hasActiveWorkout = true
    return workout
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add method)

**Notes**:
- `workoutService.startWorkout()` already handles the "return existing if active" logic (per its protocol doc). So this is safe to call even if an active workout exists — it will return the existing one.
- After calling this, the View should trigger `onStartWorkout()` to present the fullScreenCover.

### Subtask T009 – Implement loadCopyPreviousWorkouts()

**Purpose**: Fetch all completed workouts for display in the Copy Previous sheet.

**Steps**:
1. Add method to HomeViewModel:

```swift
func loadCopyPreviousWorkouts() async {
    do {
        let allWorkouts = try await workoutService.fetchAllWorkouts(limit: nil, offset: nil)
        let completed = allWorkouts
            .filter { $0.status == .completed }
            .sorted { $0.date > $1.date }

        var items: [CopyPreviousWorkout] = []
        for workout in completed {
            let sets = try await setService.fetchSets(for: workout.id)
            let workingSetsWithData = sets.filter { $0.setType == .working && $0.hasData }
            let totalVolume = workingSetsWithData.compactMap(\.volume).reduce(0, +)
            let exerciseIds = try await setService.fetchExerciseIds(for: workout.id)

            var muscleGroups: [String] = []
            for exerciseId in exerciseIds {
                if let exercise = try await cachedExercise(exerciseId),
                   let muscle = exercise.primaryMuscle,
                   !muscleGroups.contains(muscle) {
                    muscleGroups.append(muscle)
                }
            }

            items.append(CopyPreviousWorkout(
                id: workout.id,
                workout: workout,
                date: workout.date,
                exerciseCount: exerciseIds.count,
                setCount: workingSetsWithData.count,
                totalVolume: totalVolume,
                muscleGroups: muscleGroups
            ))
        }

        copyPreviousWorkouts = items
    } catch {
        print("[HomeViewModel] Failed to load copy previous workouts: \(error)")
    }
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add method)

**Notes**:
- No limit on number of workouts shown in the sheet (unlike Recent which caps at 5).
- Uses the same exercise cache and muscle group derivation pattern as `loadRecentWorkouts()`.
- Called when user taps "Copy Previous" card, before showing the sheet.

### Subtask T010 – Implement copyWorkout()

**Purpose**: Copy a past workout's exercises and working sets into a new workout, handling active workout conflicts.

**Steps**:
1. Add method to HomeViewModel:

```swift
/// Copy a past workout. If an active workout exists, triggers confirmation dialog.
/// - Parameter workoutId: The source workout to copy.
/// - Returns: The new workout if copy succeeded, nil if blocked by confirmation dialog.
func copyWorkout(_ workoutId: UUID) async throws -> Workout? {
    // 1. Check for active workout conflict
    let activeWorkout = try await workoutService.getActiveWorkout()
    if activeWorkout != nil {
        // Store pending copy and show confirmation
        pendingCopyWorkoutId = workoutId
        showDiscardConfirmation = true
        return nil
    }

    // 2. No conflict — proceed with copy
    return try await performCopy(workoutId)
}

/// Internal copy implementation.
private func performCopy(_ sourceWorkoutId: UUID) async throws -> Workout {
    // 1. Fetch source sets
    let sourceSets = try await setService.fetchSets(for: sourceWorkoutId)
    let workingSets = sourceSets
        .filter { $0.setType == .working }
        .sorted { ($0.orderInWorkout, $0.orderInExercise) < ($1.orderInWorkout, $1.orderInExercise) }

    // 2. Create new workout
    let newWorkout = try await workoutService.startWorkout()

    // 3. Duplicate each working set
    for sourceSet in workingSets {
        let newSet = WorkoutSet(
            workoutId: newWorkout.id,
            exerciseId: sourceSet.exerciseId,
            date: Date(),
            setType: .working,
            orderInWorkout: sourceSet.orderInWorkout,
            orderInExercise: sourceSet.orderInExercise,
            completed: false,
            weight: sourceSet.weight,
            reps: sourceSet.reps
        )
        _ = try await setService.save(newSet)
    }

    // 4. Update state
    hasActiveWorkout = true
    showCopyPreviousSheet = false

    return newWorkout
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add methods)

**Notes**:
- Only `setType == .working` sets are copied (no warmup, dropset, etc.).
- Each copied set gets a new UUID (from `WorkoutSet` init default), new `workoutId`, same `exerciseId`, `weight`, `reps`, `orderInWorkout`, `orderInExercise`.
- `completed` is set to `false` — user needs to complete each set in the new workout.
- `setService.save()` triggers the full PR pipeline (effectiveWeight calculation, PR evaluation, stats update) — this is correct behavior.
- Sorting by `(orderInWorkout, orderInExercise)` preserves exercise order and set order within each exercise.
- Check the `WorkoutSet` initializer in `Reppo/Data/Models/WorkoutSet.swift` for exact parameter names and defaults.

### Subtask T011 – Implement discardActiveAndCopy()

**Purpose**: Handle the "discard active workout" confirmation action — delete the active workout and then copy the pending workout.

**Steps**:
1. Add method to HomeViewModel:

```swift
/// Called when user confirms discarding the active workout to proceed with copy.
/// - Returns: The new copied workout.
func discardActiveAndCopy() async throws -> Workout? {
    guard let pendingId = pendingCopyWorkoutId else { return nil }

    // 1. Delete the active workout
    if let activeWorkout = try await workoutService.getActiveWorkout() {
        try await workoutService.deleteWorkout(activeWorkout.id)
    }

    // 2. Clear confirmation state
    showDiscardConfirmation = false
    pendingCopyWorkoutId = nil

    // 3. Perform the copy
    return try await performCopy(pendingId)
}

/// Called when user cancels the discard confirmation.
func cancelDiscard() {
    showDiscardConfirmation = false
    pendingCopyWorkoutId = nil
}
```

**Files**:
- `Reppo/Features/Home/ViewModels/HomeViewModel.swift` (add methods)

**Notes**:
- `deleteWorkout()` cascades: deletes all sets, rebuilds PRs/stats for affected exercises. This is the correct behavior for discarding a workout.
- `cancelDiscard()` clears state and returns user to the Copy Previous sheet.
- After discard + copy, `performCopy()` sets `hasActiveWorkout = true` and dismisses the sheet.

---

## Risks & Mitigations

- **Race condition**: User starts workout via FAB while Copy Previous is open. Mitigation: `copyWorkout()` always checks `getActiveWorkout()` immediately before copying.
- **Large workout copy**: Sequentially saving 30+ sets could take noticeable time. Mitigation: Typical workouts have 15–30 working sets; save pipeline is <100ms per set. Total ~1.5-3s is acceptable.
- **Delete cascade timing**: `deleteWorkout()` triggers PR/stats rebuild for all affected exercises. This should complete before `startWorkout()` is called. Sequential execution guarantees this.
- **WorkoutSet initializer**: Verify exact parameter names against the model file. The init may have additional parameters with defaults.

## Definition of Done Checklist

- [ ] `startEmptyWorkout()` creates a workout and updates `hasActiveWorkout`
- [ ] `loadCopyPreviousWorkouts()` populates `copyPreviousWorkouts` with all completed workouts
- [ ] `copyWorkout()` detects active workout conflict and shows confirmation
- [ ] `copyWorkout()` creates new workout with duplicated working sets (weight/reps pre-filled)
- [ ] `discardActiveAndCopy()` deletes active workout then copies
- [ ] `cancelDiscard()` clears confirmation state
- [ ] Only `.working` sets are copied (no warmup)
- [ ] Set order preserved (`orderInWorkout`, `orderInExercise`)
- [ ] Copied sets have `completed = false`

## Review Guidance

- Verify only working sets are duplicated (check `.setType == .working` filter).
- Verify `copyWorkout()` checks for active workout before creating the copy.
- Verify `discardActiveAndCopy()` deletes BEFORE creating the new workout.
- Check that `WorkoutSet` constructor parameters match the actual model init.
- Ensure `showCopyPreviousSheet` is set to `false` after successful copy.

## Activity Log

- 2026-03-01T17:56:08Z – system – lane=planned – Prompt created.
- 2026-03-01T18:25:27Z – claude-opus – shell_pid=64845 – lane=doing – Started implementation via workflow command
- 2026-03-01T18:28:30Z – claude-opus – shell_pid=64845 – lane=for_review – Ready for review: All workout action methods added — startEmptyWorkout, loadCopyPreviousWorkouts, copyWorkout with conflict detection, discardActiveAndCopy, cancelDiscard. Only working sets copied with weight/reps pre-filled. Build succeeds.
- 2026-03-01T18:28:57Z – claude-opus-reviewer – shell_pid=65596 – lane=doing – Started review via workflow command
- 2026-03-01T18:30:02Z – claude-opus-reviewer – shell_pid=65596 – lane=done – Review passed: All 4 subtasks verified. WorkoutSet init params match model exactly. Only working sets copied with weight/reps pre-filled, completed=false, order preserved. Active workout conflict detection correct (check → dialog → discard+copy). Delete before copy order verified. FR-016 respected (no new service methods). Build succeeds.
- 2026-03-01T18:50:43Z – claude-opus-reviewer – shell_pid=65596 – lane=done – Review approved, moved to done
