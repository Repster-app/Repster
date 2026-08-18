# Discard Crash — Use-After-Delete Scoping

**Date:** 2026-08-17
**Branch:** NewMain (`2066de7` + uncommitted)
**Trigger:** simulator crash, Repster 1.4 (4), `EXC_BREAKPOINT (SIGTRAP)` on the main thread while
discarding a workout from the summary sheet.
**Status:** **implemented 2026-08-17; reproduced and controlled 2026-08-18** — see §9.
Suite 464 → **471, 0 failures, 4 skipped** (the new control is gated).

This is a **different failure mode from the cross-context crash work**, not a regression of it.
`SWIFTDATA_CRASH_WORK_RECORD.md` and `STEP5_SCOPE_AND_TEST_STRATEGY.md` cover reads racing a
`save()` — `EXC_BAD_ACCESS` at `0x8000000000000010`, non-deterministic. This one is a read of a row
that has been **deleted and committed**: SwiftData detects it and calls `_assertionFailure`
deliberately. Same root cause one level up — the UI holds live `@Model` objects — with a different
symptom.

> **Corrected twice.** This section first claimed the failure is *deterministic rather than racy*;
> then, when no harness could reproduce it, that the mechanism was unknown. Both are now settled by
> §9.2: it is deterministic, but only for an attribute that was **never resolved**. A committed
> delete alone is harmless — reading an *unresolved* attribute off detached backing data is fatal.

---

## 0. Conclusions — read this first

1. **The reported crash is one of four fault sites in one view, in a window that lasts seconds and
   has two independent guarantees of a re-render inside it.** It is not a narrow race. §1, §2.
2. **A guard in `WorkoutSummarySheet.displaySummary` is not sufficient.** The same window exposes
   `SetTableView`, `ExerciseTabStripView` and three more reads in the sheet itself. §3.
3. **The fix belongs in the ViewModel: clear/remove state *before* awaiting a delete, restore by
   re-loading on failure.** That makes every downstream read short-circuit instead of needing its own
   guard. §5, §6.
4. **The sheet guard is still needed — for the *finish* path**, where nothing is deleted but the
   workout is being saved under the reader. That is Stage 2 step 7, and this change closes it. §3.4.
5. **Five call sites carry the pattern**, in two ViewModels. Three are reachable today, one is
   reachable but narrow, one is currently unreachable. §3.
6. **Nothing in the suite covers discard, `removeExercise`, or delete-during-render at all.** §7.
7. This is **compatible with step 5** and creates nothing step 5 would delete. The ordering rule
   ("don't show rows that no longer exist") stays correct once sets become value types — it just
   changes from a crash to staleness. §8.

8. **Reproduced on the sixth configuration**, after five failed. The trap needs an attribute that
   was never resolved, not merely a deleted row — which is why fast harnesses never saw it. There is
   now a real paired control. §9.2.

---

## 1. What actually happened

### 1.1 The stack, in order of causation

Thread 7 is the user's action; thread 0 is the crash. Reading them together:

| Step | Where |
|---|---|
| User taps **Discard** in the confirmation alert | `WorkoutSummarySheet.swift:134` |
| `discardAndClose()` sets `isDiscarding = true`, freezes the summary, awaits | `:765-770` |
| `discardWorkout()` awaits the service; **local state is untouched** | `ActiveWorkoutViewModel.swift:2105` |
| `deleteWorkout` step 4: **every set deleted and `save()`d** | `WorkoutService.swift:251` → `SetRepository.swift:326-335` |
| step 5: workout deleted | `WorkoutService.swift:254` |
| step 6: `prService.rebuild` + `statsService.rebuild`, **per affected exercise** | `:257-260` |
| ← thread 7 is parked here, inside `recomputeFrontierBadges` → `setRepo.fetch(byId:)` | `PRService.swift:644` |
| Meanwhile SwiftUI runs a layout pass on the sheet | thread 0, `_UIHostingView.layoutSubviews` |
| body → `displaySummary` → `computeSummary()` | `WorkoutSummarySheet.swift:155` |
| maps the still-held, now-deleted sets | `ActiveWorkoutViewModel.swift:1960` |
| reads `set.setType` on a deleted row → SwiftData traps | `ChartSetData.swift:96` |

`SetRepository.deleteSets(for:)` deletes **and saves** (`:334`), so by the time the render runs, the
rows behind the instances the ViewModel holds are gone. *Why* that read is fatal here and not in a
test harness is unresolved — see §9.2.

### 1.2 Why the ViewModel still held them

`discardWorkout()` clears `workout`, `exercises` and `setsByExercise` at
`ActiveWorkoutViewModel.swift:2122-2125` — **after** `try await workoutService.deleteWorkout(...)`
returns, i.e. after the entire pipeline including the per-exercise PR and stats rebuild. The whole
pipeline is the exposure window.

---

## 2. The window is seconds long, and a re-render inside it is guaranteed twice over

This is the part that makes it worth fixing properly rather than patching the one frame in the report.

**Length.** Step 6 runs `prService.rebuild(for:)` **per affected exercise**, and `rebuild` →
`recomputeFrontierBadges` does one awaited `setRepo.fetch(byId:)` **per PR record**, plus a save per
changed set (`PRService.swift:636-651`), followed by `statsService.rebuild`. For a six-exercise
workout on a real history that is hundreds of sequential store round trips. The crash report caught
it still running.

**Trigger 1 — the sheet's own state write.** `discardAndClose()` sets `isDiscarding = true`
(`:766`) immediately before the await, and `isDiscarding` is read by the body (`:658`, `:697`). The
invalidation is therefore queued before the delete starts and renders on the next display tick —
inside the window, every time.

**Trigger 2 — the 1 Hz workout clock.** `startWorkoutClockTicker` publishes every second and writes
`elapsedTime` on the `@Observable` ViewModel (`ActiveWorkoutViewModel.swift:965-971, 979-981`).
`stopWorkoutClockTicker()` is not called until `:2117` — after the delete. So for the whole window
the ViewModel invalidates its observers once per second, and `ActiveWorkoutView` (which renders the
elapsed time) is one of them.

That second trigger matters beyond the sheet: `WorkoutSummarySheet` is presented with `.sheet` from
`ActiveWorkoutView` (`:160-161`), so the presenter stays in the hierarchy and keeps re-rendering
behind it.

**Why it does not crash every time.** The first display tick can land before the pipeline reaches
step 4 — there are three awaited hops ahead of it (`workoutRepo.fetch`, `fetchExerciseIds`,
`fatigueLearningService.removeCapturedWorkoutData`). Win that race and the render reads live rows and
succeeds. Lose it and it reads rows that are gone. So: intermittent in practice, structural in
cause, and more likely the bigger the workout and the slower the device.

---

## 3. Blast radius

### 3.1 Fault sites in `WorkoutSummarySheet` during the discard window

Four, not one. A `displaySummary` guard fixes the first only.

| Line | Read | Faults on |
|---|---|---|
| `:155` | `viewModel.computeSummary()` | deleted `WorkoutSet` rows ← **the reported crash** |
| `:780` | `viewModel.workout?.displayTitle` (via `automaticWorkoutTitle`) | deleted `Workout` row |
| `:141` | `viewModel.workout?.id` (template prompt modifier) | deleted `Workout` row |
| `:641` | `viewModel.workout?.id == nil` (button disabled state) | deleted `Workout` row |

`:119`'s `viewModel.workout != nil` is **safe** — an optional nil-check does not fault a property.

Each of `:780`, `:141`, `:641` already has a frozen or nil fallback, but all three only take effect
once `viewModel.workout` is `nil`, which is exactly what does not happen until the pipeline ends.

### 3.2 Fault sites outside the sheet, same window

| Reader | Line | Read |
|---|---|---|
| `SetTableView` | `:128` → `SetRowView` (37 direct `set.` reads) | `dataSource.currentSets` |
| `ExerciseTabStripView.isExerciseCompleted` | `:118` | `sets.allSatisfy { $0.completed }` for **every** exercise tab |

Both are in `ActiveWorkoutView`'s body, kept alive behind the sheet, and re-rendered by trigger 2.

### 3.3 Every call site with the same shape

| # | Site | Window | Reachable |
|---|---|---|---|
| W1 | `ActiveWorkoutViewModel.discardWorkout` `:2095` | whole delete + per-exercise rebuild — **seconds** | yes — **observed** |
| W2 | `ActiveWorkoutViewModel.removeExercise` `:781` | the whole per-set delete loop; state cleared at `:801-802` | yes — tab strip → Delete Exercise |
| W3 | `EditWorkoutViewModel.removeExercise` `:359` | identical shape, state cleared at `:378-379` | yes — edit a finished workout |
| W4 | `ActiveWorkoutViewModel.deleteSet` `:678` / `EditWorkoutViewModel.deleteSet` `:274` | one `setService.delete` await; state updated synchronously on return | yes, but narrow |
| W5 | `ExerciseService.deleteExercise` → `setRepo.deleteSets(forExercise:)` `:246` | deletes that exercise's sets **across all workouts**, including an active one | **no** today — the in-workout picker runs in `.addToWorkout` mode, which offers no delete. One mode flag away from reachable |

W2/W3 are worth noting for a reason beyond the shape: the loop awaits **per set**, and
`ExerciseTabStripView` reads *every* exercise's sets on every render, so the exposure is not limited
to the exercise being deleted.

### 3.4 The finish path — no delete, same reader problem

`finishWorkout` clears state at `:2066-2074`, again **after** `workoutService.finishWorkout` and
`fatigueLearningService.processSessionEnd`. Nothing is deleted, so this cannot trap — but the sheet's
four reads run on live models *while the repository actor is saving them*, which is precisely the
`0x8000000000000010` shape from the shipped crashes. `saveAndClose` sets `isSaving = true` at `:727`,
so trigger 1 applies identically.

This is Stage 2 **step 7** ("`WorkoutSummarySheet` — reads live workout fields during `finishWorkout`'s
save", work record §6.2). The sheet-side half of this fix closes it.

### 3.5 Already safe — checked, not assumed

- **Home** (`WorkoutDetailFromHomeView:171`) and **Calendar** (`CalendarView:220`) delete by
  `workoutId` / `WorkoutSnapshot` and re-fetch afterwards. Stage 1 converted these; they hold no live
  models.
- **`ContentView.discardActiveAndCopy`** (`:622`) deletes the active workout, but it runs from Home
  with `showActiveWorkout == false`, so `ActiveWorkoutView` and its `@State` ViewModel are not in the
  hierarchy. It also already works from `getActiveWorkoutSummary()` + `fetchSetSnapshots` — value
  types throughout.

---

## 4. Non-goals

- **Making the delete faster.** Moving the per-exercise rebuild off the awaited path would shrink the
  window, not close it. Worth doing on its own merits later; it is not this fix and must not be
  mistaken for it.
- **Defensive `isDeleted` / `modelContext == nil` guards at the read sites.** Stage 1 deliberately
  *deleted* one of these (`CalendarExerciseCard`, work record §2.1) on the grounds that it swallowed
  the failure instead of removing it. Same verdict here, plus: it would need adding at six sites and
  would have to be re-removed at step 5.
- **Step 5 itself.** Value-typed `setsByExercise` is the real end state and is gated on
  `STEP5_DRAFT_STATE_DESIGN.md`. This crash needs fixing before that lands.

---

## 5. Options

### A. Clear-then-delete (recommended)

The ViewModel drops the state *before* awaiting the service, so nothing downstream can read a deleted
row. Every existing fallback (`frozenSummary`, `frozenTitle`, the `?? nil` guards) then does the job
it was written for.

- **Covers:** W1–W4, and every reader at once — sheet, set table, tab strip, anything added later.
- **Cost:** on failure the state is gone and must be restored by re-loading (§6.3).
- **Visible change:** during the delete, `ActiveWorkoutView` behind the sheet shows an empty workout.
  See §5.1 — this is the one open question.

### B. Freeze at the view (the one-liner)

`displaySummary` returns `frozenSummary` whenever `isSaving || isDiscarding`.

- **Covers:** `:155` only. Leaves the other three reads in the same view, plus `SetTableView` and the
  tab strip. Does nothing for W2–W4.
- **Verdict:** necessary but not sufficient. Keep it as part of A — it is what covers the *finish*
  path (§3.4), where clearing state early is not available.

### C. Dismiss-then-delete

Set `isWorkoutFinished = true` first, let the stack dismiss, run the delete detached.

- **Best perceived UX** — the screen goes away instantly instead of showing an empty workout.
- **Rejected for now:** the delete would outlive the view that owns its error handling, and a
  failure would leave a workout the user believes is gone. Revisit only with a real failure story.

**Recommendation: A + B.** A is the fix; B is one line and covers the finish path A cannot reach.

### 5.1 The open decision

Under A, for the duration of the delete the user sees the frozen summary sheet over an **empty**
workout screen. Today they see the frozen summary over the intact one. Options:

1. Accept it — it is behind a sheet, and the sheet is opaque (`Color.bg`).
2. Have `ActiveWorkoutView` render a "Discarding…" state when `viewModel.workout == nil &&
   !isWorkoutFinished`, so nothing flashes empty.

I lean 1 (nothing is actually visible), but 2 is cheap and removes the question. **Worth your call
before I write it**, because it decides whether `ActiveWorkoutView` is in the diff at all.

---

## 6. The change, concretely

### 6.1 `ActiveWorkoutViewModel.discardWorkout()` — reorder

```
1. hoist everything read off the model: workout.id, workout.date, set count
2. stopWorkoutClockTicker() + clearPersistedWorkoutClockState() + clearPersistedSelectedExerciseState()
3. clear workout / exercises / setsByExercise / clock fields   ← moved up from :2122-2125
4. await workoutService.deleteWorkout(id)
5. success: analytics (from the hoisted values), endActivity(), isWorkoutFinished = true
6. failure: await loadActiveWorkout() to put the screen back
```

Step 1 is load-bearing: `analyticsService.workoutDiscarded` reads `workout.date` at `:2110`, after
the point where the model is gone.

### 6.2 `removeExercise` (both ViewModels) — remove from state first

Take the sets out of `setsByExercise` and drop the exercise from `exercises` **before** the delete
loop, keeping a local copy to iterate. On failure, re-load rather than splicing back.

### 6.3 The failure path

`loadActiveWorkout()` (`:296`) already re-fetches from the store and handles "no active workout", so
it is the honest restore: after a partial failure some sets may genuinely be gone, and re-reading is
the only way to show what is actually there. Today's catch blocks only `dbg(...)`; that stays, but
the user now needs the screen back, so the reload is not optional.

### 6.4 `WorkoutSummarySheet.displaySummary`

```swift
private var displaySummary: WorkoutSummaryData? {
    if isSaving || isDiscarding { return frozenSummary }
    return viewModel.computeSummary() ?? frozenSummary
}
```

`frozenSummary` and `frozenTitle` are already captured before both awaits (`:727-728`, `:767-768`),
and `WorkoutSummaryData` is a pure value type — no live references survive the freeze.

---

## 7. Test strategy

Per method note 1 in the work record: a clean run is worth nothing without a control that still
catches the bug.

### 7.1 The paired control — attempted, and it does not reproduce

**This section's original plan was wrong, and the correction is in §9.2.** The expectation was that
the crash needs neither concurrency nor timing — delete a set through the real repository, read a
persisted property off the instance the ViewModel still holds, watch it trap. Three configurations
were tried and **none trapped.** No control ships, and the fix therefore rests on the crash report
plus the traced code path rather than on a reproduced-then-fixed pair. Read §9.2 before treating
the delete-ordering tests as proof of a crash fix.

### 7.2 Invariant tests that do not crash — the actual net

The fix's invariant is *"no deleted model is reachable from ViewModel state"*, and it is observable
mid-flight with a stub whose `deleteWorkout` suspends on a continuation the test controls:

1. start `Task { await vm.discardWorkout() }`
2. wait until the stub is entered
3. assert `vm.workout == nil` **and** `vm.setsByExercise.isEmpty` — i.e. state was cleared *before*
   the delete, not after
4. resume; assert `isWorkoutFinished`, and that the analytics event carried the right date and set
   count from the hoisted values

Four of these: discard success, discard failure (state restored by re-load), `removeExercise`,
`deleteSet`. Each fails against today's code — which is the point.

### 7.3 Journeys to add

There are **none** for discard or `removeExercise` today (`WorkoutJourneyTests` has 16 tests; neither
path appears). Two worth pinning against the real stack:

- discard a workout with two exercises → no sets, no workout, no PR records left; Home shows nothing;
  a fresh ViewModel loads no active workout;
- delete an exercise mid-workout → its sets are gone, the other exercise's sets and badges are intact,
  ordering is contiguous, and it survives a relaunch.

### 7.4 Mutations to run

Per §4.4's discipline, break each and confirm a test fails: re-order the clear back after the await;
drop the `date` hoist (analytics gets the wrong date); make the failure path skip `loadActiveWorkout`;
make `displaySummary` ignore `isDiscarding`.

### 7.5 Device pass

The simulator's timing is not the phone's, and the window scales with store size. On device: discard a
6+ exercise workout on the real history, and delete an exercise mid-workout, watching for both the
crash and any visible flash from §5.1.

New test files need four `project.pbxproj` entries by hand (work record §4) — not file-system
synchronized.

---

## 8. Relationship to step 5

Step 5 makes `setsByExercise` hold `ChartSetData`, at which point reading a deleted set is
**deterministically stale instead of fatal**. That removes the crash but not the bug: the summary
would still count sets that no longer exist.

So this change is not throwaway. The ordering rule it introduces — *state comes out before the row
does* — is the behaviour step 5 needs anyway, and §6.4's guard is unaffected by the type change. The
one thing to avoid is adding read-site guards (§4), which step 5 would have to unpick.

Worth recording in `STEP5_SCOPE_AND_TEST_STRATEGY.md` §0.5 as a known gap the conversion inherits:
`removeExercise` in both ViewModels still deletes in a loop and clears state afterwards.

---

## 9. Implementation record — 2026-08-17

Option A + B as scoped, with §5.1 answered "leave it" — `ActiveWorkoutView` is not in the diff.

### 9.1 What landed

| Change | File |
|---|---|
| `discardWorkout` hoists `workout.id`/`date`, stops the ticker and calls the new `clearScreenState()` **before** awaiting the delete; clears *persisted* clock/selection only on success; `loadActiveWorkout()` on failure | `ActiveWorkoutViewModel:2090` |
| `clearScreenState()` extracted, shared with `finishWorkout` so the two orderings cannot drift | `ActiveWorkoutViewModel` |
| `removeExercise` drops the exercise, its sets and the index clamp before the delete loop; reloads if any delete failed | `ActiveWorkoutViewModel:781`, `EditWorkoutViewModel:359` |
| `deleteSet` removes and reindexes before the service call; reloads on failure | `ActiveWorkoutViewModel:678`, `EditWorkoutViewModel:274` |
| `displaySummary` returns `frozenSummary` outright once `isSaving \|\| isDiscarding` | `WorkoutSummarySheet:155` |
| Gates on `SetServiceStub.delete` / `WorkoutServiceStub.deleteWorkout` that run **on the main actor inside** the call, plus `deleteError` / `deleteWorkoutError` | `ActiveWorkoutViewModelSuggestionRefreshTests` |
| `DeleteOrderingTests` — 4 tests | same file (the stubs are file-private, so a new file would have meant duplicating ~400 lines of conformance) |
| 2 journeys: discard leaves nothing behind; removing an exercise leaves the other intact | `WorkoutJourneyTests` |

The hoist turned out to be load-bearing rather than tidy: `guard let workout` binds the model, so a
reverted hoist would read `workout.date` off a deleted row in the analytics call — a trap, not a
wrong value.

Suite 464 → **470, 0 failures, 3 skipped.** No new files, so no `project.pbxproj` work.

### 9.2 The control — reproduced on the sixth configuration

`CrossContextRaceTests.testUnmaterialisedSetTypeGoesFatalOnceTheRowIsDeleted`, gated behind
`Fixtures/Local/RUN_DELETED_READ_REPRO`, **crashes the runner** — the passing result for a control:

```
SwiftData/BackingData.swift:249: Fatal error: This backing data was detached from a context
without resolving attribute faults: PersistentIdentifier(…) - \WorkoutSet.setType
```

Same property as the TestFlight report, and a Swift `fatalError`, which is the report's
`EXC_BREAKPOINT (SIGTRAP)` with `_assertionFailure` on top.

**The five failures are the finding, not noise.** Deleting a row and reading it back is *not* fatal
on its own:

| # | Configuration | Result |
|---|---|---|
| 1 | 1 set, in-memory, delete, read `setType` | no trap |
| 2 | 400 sets, in-memory, nothing read first, 2,000 concurrent repo fetches vs 2,000 main-actor reads | no trap |
| 3 | as #2, **on-disk** | no trap |
| 4 | real `deleteWorkout` pipeline, sets **dirtied on the main actor** first, reads *during* the delete | no trap |
| 5 | as #4 plus a forced memory warning either side of the delete | no trap |
| 6 | **on-disk + `propertiesToFetch` leaving `setType` unresolved** | **traps** |

**The mechanism.** SwiftData is fatal when an attribute that is still an **unresolved fault** is read
after its backing data has been detached. If the value was already materialised, the read answers
from memory and nothing happens — which is what every fast harness produced, and why five attempts
found nothing. Attempts 1, 2, 4 and 5 also used an in-memory store, where the object graph *is* the
store and no row can go missing.

**This explains the report's asymmetry.** `ChartSetData.init(from:)` reads 21 properties before line
96 and every one is a plain scalar; line 96 is `setType`, and `SetType` is `enum SetType: String,
Codable` — the first non-scalar attribute the initialiser touches. The scalars were resolved. It was
not.

**Credit where due:** the app owner's question — *did it crash because the workout had been idling?*
— is what produced this. The process had been up **2h58m** (launch 19:40:51, crash 22:38:45; the Mac
did not sleep, last wake 18:23, before launch). Hours of memory pressure are exactly what returns a
resolved attribute to fault state. The harness reaches the same state with `propertiesToFetch`
instead of waiting.

**What it changes.** The fix now has a genuine paired control, to the standard the earlier crash work
set: the control crashes on demand, and the four `DeleteOrderingTests` — each verified by mutation —
prove the read no longer happens. The manual discard check is still worth doing, but it is
confirmation rather than the only evidence.

**Single `ModelContext` throughout the control**, because `ServiceContainer` wires one shared
`setRepository` into every service (checked, not assumed) — so a cross-context harness would not be
modelling the shipped code.

---

## 10. What I have not verified

Stated plainly so nothing here reads as more settled than it is.

- ~~That SwiftData traps deterministically on any persisted-property read after a committed
  delete.~~ **Answered 2026-08-18 (§9.2): it does not.** It traps only on an attribute that is still
  an unresolved fault. The per-property suspicion was right; the "any read" half was wrong.
- **That `ActiveWorkoutView` re-renders inside the window.** Reasoned from `.sheet` semantics plus the
  1 Hz `elapsedTime` write, not observed in a stack. The sheet's own re-render *is* observed.
- **The window's real duration.** Inferred from the pipeline's shape and the fact that the report
  caught it mid-rebuild. Measurable with the existing `PipelinePerformanceTests` harness if the number
  turns out to matter.
- **W5's unreachability.** Based on the in-workout picker using `.addToWorkout` mode; I did not
  exhaustively trace every route into `ExerciseListViewModel.deleteExercise`.
