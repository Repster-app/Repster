# Adding an Exercise That's Already in the Workout — Scoping

**Written:** 2026-09-10 · **Status:** BUILT 2026-09-10 for 1.6 · **Size:** small: two view models, no schema change, no UI

**Decisions taken 2026-09-10:** D1 silent jump · D2 tally added (`duplicate_exercise_adds`) · D3 1.6 (1.5 had already shipped).

## 1. The report

On a finished workout, the user added an exercise that was already in it and had logged
sets. The edit screen showed that exercise with a single blank set, as if the logged sets
had been overwritten. The logged sets still appeared in the exercise's history.

Nothing was deleted. The screen stopped showing rows that are still in the store.

## 2. What happens today

A workout has no row for "this exercise, in this workout". A `WorkoutSet` carries
`workoutId` + `exerciseId`, every screen rebuilds the workout by grouping sets on
`exerciseId`, and exercise order is reconstructed from `MIN(orderInWorkout)` per group
([1_5_DECISION_RECORD.md](1_5_DECISION_RECORD.md), "A real exercise-order field"). So an
exercise can appear in a workout **once**. Nothing enforces that on the way in.

Both add paths have the same three lines and no presence check:

| | Edit (finished workout) | Active (live workout) |
|---|---|---|
| Function | [EditWorkoutViewModel.swift:325](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift:325) | [ActiveWorkoutViewModel.swift:981](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:981) |
| `exercises.append(exercise)` | second entry, same id | second entry, same id |
| `setsByExercise[exerciseId] = []` | **forgets the logged sets** | **forgets the logged sets** |
| `await addSet(for:)` | writes one blank set to the store | writes one blank set to the store |

The picker (`ExerciseListView`, `.addToWorkout`) is never told what is in the workout, so it
offers everything. `SetTableDataSource` does not declare `addExercises`, so the two
implementations are separate and both need the change.

`replaceExercise` already refuses duplicates in both view models
([ActiveWorkoutViewModel.swift:1082](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1082)).
Its comment explains why: the strip's `ForEach` is keyed by exercise id. Add never got the same guard.

### 2.1 What the bad state breaks

**Store: nothing is lost.** Stats, PRs, HealthKit, fatigue learning and exercise history all
read the store, and the logged rows are still in it. That is why history still showed them.

**Screen state, on both screens:**
- Two tabs with the same id, so selection and animation are undefined. Both tabs show the
  same one-set list.
- The blank set gets `orderInExercise = 1`, which collides with the first logged set. Its
  `orderInWorkout` is the on-screen count + 1, and that count excludes the forgotten rows,
  so it can collide with another exercise's set. Order can shift on the next reload.
- Removing either duplicate tab deletes the blank set and leaves the other tab empty.

**Active screen only:**
- The summary sheet reads `setsByExercise`
  ([WorkoutSummarySheet.swift:1150](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:1150)),
  so it undercounts that exercise.
- The `workout completed` event computes `completedSetCount`, `totalReps` and `prsHit` from
  screen state, so all three undercount. `exerciseCount` counts the exercise twice
  ([ActiveWorkoutViewModel.swift:2387](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:2387)).
- The Live Activity's counts are wrong.
- **In DEBUG builds, `assertOrderingInvariant("addExercises")` trips**: two entries share a
  `MIN(orderInWorkout)`, and the assert requires strictly increasing values. Nobody hit this
  in development, which suggests it had never been tried on a debug build.

**After a reload,** both screens regroup from the store. The logged sets come back under one
tab, plus the stray blank set (numbered 1, so it may sit first). The blank set carries no
numbers. `WorkoutSet.hasData` only treats never-ticked rows as data when they have numbers
([UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md)), so the blank set should be inert.

## 3. The fix

Guard `addExercises` in both view models. The guard goes in the view model, not the picker,
so it holds whatever the entry point. That includes the unreferenced `ExercisePickerSheet`,
which also calls `addExercises`.

### 3.1 Rules

1. **Skip an id that is already in `exercises`.** No fetch, no append, no blank set. Nothing is written to the store.
2. **Dedupe within the batch.** The picker returns an array. Its `toggleSelection` prevents
   repeats today, but the view model should not depend on that.
3. **Re-check after the fetch's `await`,** then append. This is the same discipline as
   `replaceExercise`: never trust state across a suspension on this screen.
4. **Selection:**
   - If anything new was added, keep each screen's existing rule: Active selects the first
     added, Edit the last added. This fix leaves that inconsistency alone.
   - If nothing new was added but an existing exercise was picked, **jump to that
     exercise's tab**, by identity.
   - If neither, leave the selection alone.
5. **Active only:** make the jump through `setSelectedExercise(id:)`, not by writing the
   index directly. That fires the persisted selection and the Live Activity update.
   `updateLiveActivityState()` and `assertOrderingInvariant` stay where they are.

### 3.2 Shape (Active; Edit is the same, minus the Live Activity and invariant lines)

```swift
func addExercises(_ exerciseIds: [UUID]) async {
    let firstAddedIndex = exercises.count
    var addedExerciseCount = 0
    var firstAlreadyPresentId: UUID?
    var seen = Set<UUID>()

    for exerciseId in exerciseIds where seen.insert(exerciseId).inserted {
        // One exercise, one tab: sets are grouped by exerciseId, so a second entry would
        // reset this exercise's rows on screen while they stay in the store.
        if exercises.contains(where: { $0.id == exerciseId }) {
            firstAlreadyPresentId = firstAlreadyPresentId ?? exerciseId
            continue
        }
        do {
            guard let exercise = try await exerciseService.fetchExerciseSnapshot(exerciseId) else { continue }
            guard !exercises.contains(where: { $0.id == exerciseId }) else { continue }
            exercises.append(exercise)
            setsByExercise[exerciseId] = []
            await addSet(for: exerciseId)
            addedExerciseCount += 1
        } catch { /* unchanged */ }
    }

    if addedExerciseCount > 0 {
        selectedExerciseIndex = firstAddedIndex
    } else if let existingId = firstAlreadyPresentId {
        setSelectedExercise(id: existingId)
    }

    assertOrderingInvariant("addExercises")
    updateLiveActivityState()
}
```

Edit's current fallback, `if !exercises.isEmpty { selectedExerciseIndex = exercises.count - 1 }`,
must become "last added, else the existing one that was picked". Otherwise picking only a
duplicate jumps to the last tab.

## 4. Decisions

**D1: Feedback when a duplicate is skipped.** *Recommend: silent jump.*
- (a) **Silent jump.** Landing on the exercise's own tab, with its sets, is the feedback.
- (b) Alert: "Bench Press is already in this workout." Costs a tap on the logging screen.
- (c) Toast. No toast exists on the workout screens, so this means building one.

In a mixed batch (one new, one already there), the new one is added and the duplicate is
quietly skipped. Note that the Replace design's decision #3 said duplicates are "rejected with
a message" ([EXERCISE_REPLACE_AND_REORDER_DESIGN.md §10](EXERCISE_REPLACE_AND_REORDER_DESIGN.md)).
That message was never built: Replace's guard returns silently and the sheet closes. If you
choose (b) here, Replace should get the same message. With (a), the two stay consistent as
they are.

**D2: Count skipped duplicates in analytics?** *Recommend: yes, if this goes into 1.6; no, if into 1.5.*
A new `WorkoutInteractionTally` case (for example `duplicate_exercise_adds`) would show
whether anyone actually wants the same exercise twice, which is the evidence option 3 would
need. It is Active-only, because `EditWorkoutViewModel` has no analytics service. It touches
`AnalyticsServiceProtocol.swift`, [POSTHOG_ANALYTICS_GUIDE.md](POSTHOG_ANALYTICS_GUIDE.md) and
[WORKOUT_INTERACTION_TALLY_DESIGN.md](WORKOUT_INTERACTION_TALLY_DESIGN.md). That is more
surface than the fix itself, so keep it out of a locked release.

**D3: 1.5 or 1.6.** *Recommend: 1.5, as a bug fix.* Scope was locked on 2026-09-06, but the
version number is still unsettled ([RELEASE_1_5_PLAN.md](RELEASE_1_5_PLAN.md)). The change is
view-model-only with no UI. Today's behaviour looks like data loss to the user and trips an
assert on debug builds.

## 5. Tests

These go in [WorkoutJourneyTests.swift](RepsterTests/WorkoutJourneyTests.swift). It already
has `Stack`, `makeEditViewModel`, `startWorkout`, `completeNextSet`, `committedSets` and
`assertScreenMatchesStore`.

| # | Screen | Setup → action | Asserts |
|---|---|---|---|
| T1 | Edit | Finished workout, X with 2 logged sets → `addExercises([X])` | 1 exercise; `currentSets` is the 2 logged sets; store count unchanged (no blank set); selected = X |
| T2 | Edit | Finished workout with X → `addExercises([X, Z])` | Z added once, X not duplicated; exactly one new stored set (Z's); selected = Z |
| T3 | Active | Live workout, X with 1 logged set → `addExercises([X])` | No duplicate, no new row; `assertScreenMatchesStore` passes; selected = X |
| T4 | Active | Exercises [X, Y], on Y → `addExercises([X, Z])`, then `addExercises([X])` | Z appended and selected; then selection jumps to X |
| T5 | Both | `addExercises([Z, Z])` | Z once, one set |
| T6 | Active | After T3, `makeViewModel()` + `loadActiveWorkout()` | X has exactly its original sets: no stray blank row survives a relaunch |

**Red before green:** on today's code, T3–T6 will **crash the runner** on the DEBUG
invariant assert rather than fail cleanly, and a crashed runner can still print a green
tally. Check the log for the crash, not the count. T1 and T2 fail cleanly. Run the suite
once, into a log.

## 6. Out of scope

- **Labelling "In workout" in the picker** (option 2). This is a follow-up. It touches the
  shared `ExerciseListView`, which four screens use. The Replace doc's objection to greying rows
  was about browse mode; add uses `.addToWorkout`, which is already workout-specific, so that
  objection does not rule option 2 out.
- **The same exercise as two separate blocks** (option 3). Needs a workout-exercise row or a
  stored order, which is a schema migration. Unblocked by D2 data showing demand.
- **Templates holding the same exercise twice.** The template editor allows it (each
  `EditorExercise` has its own id). `startWorkoutFromTemplate`
  ([TemplateService.swift:296](Repster/Core/Services/TemplateService.swift:296)) then writes
  both blocks under one `exerciseId` with overlapping `orderInExercise` (1,2,3 and 1,2). On
  load, they merge into one interleaved tab. It is the same root cause, but a different
  defect with a different fix, and nothing is hidden.
- **Replace's missing "already in workout" message.** See D1.
- **Cleaning up stray blank sets** left by past occurrences. There is no migration. They are
  inert, and a user can delete them.
- **`ExercisePickerSheet`** is unreferenced dead code. The guard covers it anyway.

## 7. Device check (tap steps)

1. History → open a finished workout with logged sets → Edit → **+** → pick an exercise
   already in it → **Add**. You should land on its tab, with the logged sets intact and no second tab.
2. Same screen → pick one exercise already in the workout plus one new one → **Add**. The
   new one is added and selected; the existing tab is unchanged.
3. Live workout → log a set → **+** → pick the same exercise → **Add**. You land on it, and
   the set is still there. Finish, and the summary counts the set.
4. Relaunch mid-workout after step 3 → reopen. No blank row appears.
