# Replace & reorder exercises in the active workout — design

**Date:** 2026-08-17
**Revised:** 2026-08-29 — all five §10 decisions resolved; every claim re-verified against the tree
and line references refreshed (they had drifted ~+42 in `ActiveWorkoutViewModel`). Both defects
confirmed still live. No substantive finding changed.
**Status:** **§11 steps 1–4 implemented 2026-08-29. The feature is built.** Both defects fixed, two
further defects found and fixed, the DEBUG ordering assertion is in, and replace ships on both view
models with the shared menu item, confirmation and picker. Suite green at 650. Only the optional
step 5 (reorder sheet) remains, and it stays deferred by decision 4.
**Touches:** `ActiveWorkoutViewModel`, `EditWorkoutViewModel`, `ExerciseTabStripView`, `SetTableDataSource`.

Two things, deliberately in one document because they share a single root cause:

1. **Replace an exercise in place** — swap Incline DB Press for Cable Fly at position 3, keeping
   position 3, instead of delete-then-add-then-walk-it-left.
2. **Fix reorder** — including a defect that was scoped and fixed everywhere *except* this one
   caller, and a selection bug that can silently move you onto a different exercise mid-set.

This is the highest-frequency write path in the app, and the one that produced both shipped
SwiftData crashes. Section 8 is the risk register; section 10 is what I need decided before code.

---

## 1. How exercise order actually works

This is the load-bearing fact, and everything below depends on it.

**There is no exercise-order field.** Exercises are not stored as a list. The strip's order is
*reconstructed on load* from the sets:

```swift
// ActiveWorkoutViewModel.swift:367-373
// 5. Order exercises by the MIN orderInWorkout across their sets
loadedExercises.sort { lhs, rhs in
    let lhsOrder = setsByExercise[lhs.id]?.map(\.orderInWorkout).min() ?? 0
    let rhsOrder = setsByExercise[rhs.id]?.map(\.orderInWorkout).min() ?? 0
    return lhsOrder < rhsOrder
}
```

So "exercise 3 comes before exercise 4" is expressed as "every set of exercise 3 has a lower
`orderInWorkout` than every set of exercise 4." Any operation that changes exercise order must
renumber `orderInWorkout` across **the whole workout**, or the order is right on screen and wrong
in the store — and the store wins the moment the screen is rebuilt (§1.2).

Two consequences that shape the whole design:

- **An exercise with no sets does not exist.** It cannot be ordered, and it will not survive a
  relaunch. `addExercises` handles this by immediately seeding an empty set
  ([ActiveWorkoutViewModel.swift:789](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:789)).
  Replace must do the same.
- **New sets go to the global tail.** `addSet` assigns `orderInWorkout: totalSets + 1`
  ([:615](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:615)). A replacement
  exercise seeded this way lands *last* in `orderInWorkout` terms even though it sits at position 3
  in the array. On screen it looks correct; rebuild the screen and it has jumped to the end.
  **This is the single easiest way to get replace wrong**, and it is invisible until the rebuild —
  exactly the defect class the journey tests were written for. §1.2 covers when that rebuild
  happens, which is sooner and more often than the original draft of this document assumed.

The correct renumbering already exists and is already batched:

```swift
// ActiveWorkoutViewModel.swift:2274  — walks `exercises` in array order, assigns a
// contiguous global orderInWorkout, returns only what changed
private func reindexOrderInWorkout() -> [SetOrderUpdate]

// ActiveWorkoutViewModel.swift:2296  — one awaited, transactional write
private func persistSetOrdering(_ updates: [SetOrderUpdate]) async
```

---

### 1.1 The ordering invariant

Everything above collapses into one rule. State it once and every mutation site can be checked
against it mechanically:

> **For any two exercises at array positions `i < j`, `MIN(orderInWorkout)` over exercise `i`'s sets
> must be strictly less than `MIN(orderInWorkout)` over exercise `j`'s.**

That is the whole contract. `loadActiveWorkout` sorts on exactly this key, so the invariant holding
in the store *is* "the strip reloads in the order the user left it."

The useful consequence is that most set-level writes cannot break it, and it is worth knowing which,
because it explains why this has survived this long:

- **Adding a set to an existing exercise is always safe.** `addSet` assigns the global tail, which
  can only raise that exercise's MAX. Its MIN is untouched.
- **Deleting a set is safe while ≥1 set remains.** Deleting the exercise's lowest set raises its MIN,
  but only to its own second-lowest, which is still below every successor's — numbering within an
  exercise is contiguous.
- **Appending a new exercise is safe by construction.** `addExercises` appends to the end of the
  array *and* seeds at the global tail. Both are "last", so they agree.

Only two operations can break the invariant:

1. **Moving an exercise within the array** — array order changes, stored numbers don't.
2. **Introducing an exercise at a non-tail array position whose entire set list is at the global
   tail** — array says position 3, numbers say last.

`reorderExercises` is case 1. **Replace is case 2**, and it is the only operation in the app that
has ever been case 2. Both must call `reindexOrderInWorkout()` + `persistSetOrdering()`.

### 1.2 When the store wins — the rebuild boundary

The original draft of this document said the damage was "invisible until relaunch." **That is
wrong, and it understated the severity.** The strip renders the in-memory `exercises` array, so a
broken invariant is invisible only for as long as that array survives. It does not survive as long
as assumed.

`ActiveWorkoutView` is a `fullScreenCover` ([ContentView.swift:262](Repster/App/ContentView.swift:262))
holding its view model in `@State` ([ActiveWorkoutView.swift:50](Repster/Features/Workout/Views/ActiveWorkoutView.swift:50)).
The header's back chevron calls `dismiss()`
([ActiveWorkoutView.swift:386](Repster/Features/Workout/Views/ActiveWorkoutView.swift:386)), which
tears the view down and discards that state. Resuming from the FAB
([ContentView.swift:512](Repster/App/ContentView.swift:512)) constructs a **fresh** view model whose
`.task` re-runs `loadActiveWorkout()` and re-sorts from the store.

So the full list of rebuild moments:

| Trigger | Frequency |
|---|---|
| **Back chevron → resume from FAB** | **Routine, mid-workout.** Ducking out to Home or the calendar and coming back |
| Force-quit and reopen | Occasional |
| A failed set delete ([:740](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:740)), partial exercise-removal failure ([:852](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:852)), failed discard ([:2221](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:2221)) | Rare — all error paths that deliberately re-read |

Backgrounding the app is **not** a rebuild: `scenePhase == .active` only recalculates the rest timer
([ActiveWorkoutView.swift:125](Repster/Features/Workout/Views/ActiveWorkoutView.swift:125)).

**The user-visible statement of the bug is therefore:** replace your 3rd exercise, tap back to check
something on Home, tap the FAB to resume — the replacement is now last in the strip. Two taps, mid
workout, on an ordinary detour. Not a post-relaunch cosmetic nit.

The same boundary is where the §2 reorder race becomes visible: four rapid Move-Lefts spawn four
overlapping renumbering passes and last writer wins, so the screen can show what you did while the
store holds something else. You find out when you come back.

### 1.3 Making it impossible to regress quietly

The invariant in §1.1 is cheap to check and expensive to violate, so assert it rather than trusting
each call site to remember:

```swift
/// Trap in debug if the array order and the stored order disagree. Ordering bugs are invisible
/// on screen by construction (§1.2), so this is the only place they can be caught at the moment
/// they are introduced rather than after the next rebuild.
private func assertOrderingInvariant(_ context: StaticString) {
    #if DEBUG
    let mins = exercises.compactMap { setsByExercise[$0.id]?.map(\.orderInWorkout).min() }
    // Strictly increasing, not merely sorted: two exercises sharing a MIN is also a violation,
    // and `sorted()` would wave it through.
    assert(zip(mins, mins.dropFirst()).allSatisfy(<), "ordering invariant violated at \(context)")
    #endif
}
```

Call it at the end of every mutation named in §1.1 — `reorderExercises`, `replaceExercise`,
`addExercises`, `removeExercise`. It is DEBUG-only, so it costs nothing shipped, and it converts
"invisible until the next rebuild" into "trips in the test suite on the offending line."

---

## 2. Defect A — reorder still uses the fan-out that Stage 2 removed

`reorderExercises` persists like this
([ActiveWorkoutViewModel.swift:860-889](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:860)):

```swift
Task {
    var globalOrder = 1
    for exercise in exercises {
        for set in orderedSets {
            set.orderInWorkout = globalOrder
            set.updatedAt = Date()
            _ = try await setService.edit(set)   // ← full pipeline, per set
            globalOrder += 1
        }
    }
}
```

`setService.edit` ([SetService.swift:222](Repster/Core/Services/SetService.swift:222)) is the full
write pipeline: fetch the exercise, sync derived fields, fetch the old set, recompute
`effectiveWeight`, fetch the health profile, recompute e1RM, persist, then re-evaluate PRs. Running
it once per set to change one integer is not a performance nit — **this is the exact pattern the
crash work removed.**

From [SetRepository.swift:214-218](Repster/Core/Repositories/SetRepository.swift:214), the doc
comment on the replacement API:

> Replaces the previous "one `SetService.edit()` per changed set, each in its own unawaited `Task`"
> reindex. Ordering is not a PR/stats/fatigue concern, so this deliberately does not run that
> pipeline — with identical values it was a no-op that cost N saves and manufactured the overlap
> described in §5.3 of the crash analysis.

And §5.3 of `SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md` names it as the concurrent writer that armed
shipped crash B: *"the overlap is manufactured by the callers, on a routine action."*

`SWIFTDATA_CRASH_WORK_RECORD.md` §2.3 records the migration — but it was scoped as *"reindexing
after a set insert/delete."* `reorderExercises` is not a set insert or delete, so it was never in
scope and was left behind. It is the last caller still doing this.

Severity is worse here than at the sites that were fixed, because reorder touches **every set in the
workout** rather than one exercise's, and because Move Left is tapped repeatedly. Four taps to walk
an exercise four positions left spawn four unawaited, overlapping renumbering tasks, each iterating
all sets, each racing the others' `globalOrder` assignments. Last writer wins, and there is no
guarantee it is the one whose array snapshot matches the screen.

**Fix:** delete the loop, call the helpers that already exist:

```swift
let updates = reindexOrderInWorkout()
Task { await persistSetOrdering(updates) }
```

This is a deletion, not a new mechanism. `reindexOrderInWorkout` walks `exercises` in array order
and produces exactly the numbering the current loop is trying to produce.

### 2.1 A fourth finding — historic-edit reorder never persisted at all

Found while migrating step 2. `EditWorkoutViewModel.reorderExercises` moved the `exercises` array
and **nothing else** — it never touched `orderInWorkout`. That screen reconstructs exercise order the
same way the active screen does (sort by each exercise's first `orderInWorkout`, `loadWorkout` step
5), so reordering there was purely cosmetic: it looked right until the screen was rebuilt, then
reverted.

This is why the original write-up's line that `EditWorkoutViewModel` "does not have Defect A … so it
needs the selection fix only" was right about the fan-out and wrong about the outcome. It has no
fan-out because it has no persistence *at all* on this path.

The fix is one line — call the `reindexOrderInWorkout()` that already exists in that file
([EditWorkoutViewModel.swift:556](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift:556)).
Its sets are live models, so the renumbering persists with the rest of the edit; this is exactly what
`addWarmupSet` already relies on at
[:264](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift:264).

---

## 3. Defect B — selection tracks the slot, not the exercise

```swift
// ActiveWorkoutViewModel.swift:863-866
if let sourceIndex = source.first, sourceIndex == selectedExerciseIndex {
    selectedExerciseIndex = destination > sourceIndex ? destination - 1 : destination
}
```

Selection is only corrected when the exercise you moved *is the one you are on*. Move any other
exercise past your position and the array shifts underneath a fixed integer.

**Repro:** exercises `[A, B, C]`, you are on B (index 1), mid-set. Long-press C → Move Left. Array
becomes `[A, C, B]`. `selectedExerciseIndex` is still 1 — which is now **C**. The set table swaps
to a different exercise while you are logging.

The follow-on damage all comes from the integer not changing, so every side effect keyed to it is
skipped:

| Site | Guarded by | Consequence when the index doesn't change |
|---|---|---|
| [`selectedExerciseIndex.didSet`:113-119](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:126) | `selectedExerciseIndex != oldValue` | `persistSelectedExerciseState()` and `updateLiveActivityState()` never run |
| [`ActiveWorkoutView.onChange`:131-135](Repster/Features/Workout/Views/ActiveWorkoutView.swift:131) | `of: viewModel.selectedExerciseIndex` | sub-tab not reset to Sets, `clearSubTabCache()` not called, `setKeyboardManager.hide()` not called |
| [`ExerciseTabStripView.onChange`:95-101](Repster/Features/Workout/Views/ExerciseTabStripView.swift:95) | `of: dataSource.selectedExerciseIndex` | the strip never auto-scrolls the newly-current tab into view *(found 2026-08-29; not in the original write-up)* |

Concretely:

- **Live Activity shows the wrong exercise name.** Lock Screen and Dynamic Island keep the old one
  until some other action happens to refresh them.
- **Persisted resume state points at the wrong exercise.** The persistence is stored *by exercise
  ID* ([:1029](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1092)) and restored
  by ID lookup ([:996](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1053)) — that
  part is already correct. But it is never re-written, so UserDefaults still holds B while the screen
  shows C. Force-quit and reopen and you land on B. Screen and store disagree.
- **The keypad stays open, bound to a row that is gone.** `SetEntryKeyboardManager.context` holds an
  `ownerSetID` and closures over the set
  ([SetTableView.swift:1007-1028](Repster/Features/Workout/Views/SetTableView.swift:1007)). The Sets
  table itself is rebuilt — it is keyed `.id(viewModel.currentExercise?.id)`
  ([ActiveWorkoutView.swift:263](Repster/Features/Workout/Views/ActiveWorkoutView.swift:263)) — but
  the keypad lives in `bottomAccessoryArea`, outside that subtree, and nothing hid it. The next
  keypress writes into a set that is no longer on screen. Because the draft buffer *is* the live
  model (`STEP5_DRAFT_STATE_DESIGN.md` §1, 23 write sites in `SetRowWrapper`), that write lands on a
  real, persisted-on-commit object.
- **History/PRs flash stale rows.** `clearSubTabCache()` never runs, so the previous exercise's rows
  stay rendered until the `.task(id:)` refetch lands. Self-corrects, but visibly wrong for a beat.

- **The strip doesn't scroll to the tab you are now on.** Same guard, third site. Cosmetic on a
  three-exercise workout, not on a ten-exercise one where the current tab can sit off-screen.

**That mixed behaviour — the set table updates, everything else doesn't — is exactly the "UI not
updating properly" symptom.** It was never written up and never implemented; there is no design doc
and no commit for it. This section is that write-up.

**Fix:** stop deriving selection from an index that survives the move. Capture the selected
exercise's **ID** before mutating the array, re-derive the index after, and route the assignment
through a path that fires the side effects even when the integer is unchanged.

```swift
func reorderExercises(from source: IndexSet, to destination: Int) {
    let anchorId = currentExercise?.id
    exercises.move(fromOffsets: source, toOffset: destination)
    restoreSelection(to: anchorId)          // §5
    let updates = reindexOrderInWorkout()
    Task { await persistSetOrdering(updates) }
}
```

Note this also *simplifies* the semantics: the moved exercise no longer needs special handling.
"Keep the user on the exercise they were on" is one rule that covers both cases, where the current
code has one rule that covers one case and silently gets the other wrong.

[`EditWorkoutViewModel.swift:348-361`](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift:348)
has the identical selection bug (same shape, slightly more verbose). It does not have Defect A — it
is a draft model that persists on save — so it needs the selection fix only.

**A third call site, found while implementing (2026-08-29): `removeExercise`.** Both view models
clamped the index only when it ran off the end of the array. Removing an exercise positioned
*before* the selected one shifts the array left, the index stays in range, and the user silently
lands on the exercise *after* the one they were on. Worse than the reorder case in one respect: the
index does not change either, so the `didSet` never fires and the persisted resume state keeps
pointing at the right exercise while the screen shows the wrong one — screen and store disagree with
no way for the user to tell. Same one-line fix via the §5 helper, covered by
`testRemovingAnExerciseBeforeTheSelectedOneKeepsTheUserOnTheirExercise`.

---

## 4. Feature — replace an exercise in place

### 4.1 The semantics decision: what happens to logged sets

This is the only genuine design question. Three options:

| Option | Behaviour | Verdict |
|---|---|---|
| **(a) Reassign `exerciseId`** on the existing sets | Sets keep their weights/reps, now attributed to the new exercise | **No.** 80 kg × 8 logged for Incline DB Press is not a Cable Fly set. It would write fabricated history into the new exercise's PR table, e1RM series, charts and the fatigue model, and silently delete it from the old one's. Corrupts data the user cannot see is wrong. |
| **(b) Delete the old sets, seed one empty set** | Same as delete + add, but position and flow preserved | **Yes.** Matches what the user is actually doing — substituting a movement they haven't done yet. |
| **(c) Keep old sets alongside new** | Both exercises present | That is just "add an exercise." Not a replace. |

**Recommendation: (b).** It makes replace exactly equivalent in data terms to today's
delete-then-add, which is the operation users already perform — the feature removes the tab-walking,
not the semantics. Nothing new to reason about in PR/stats/fatigue, because the pipeline sees the
same delete and create it sees today.

### 4.2 Confirmation

Reuse the existing pattern from
[`ExerciseTabStripView.swift:104-113`](Repster/Features/Workout/Views/ExerciseTabStripView.swift:104):

- **No completed sets** → replace silently. This is the overwhelmingly common case (you are
  substituting something you haven't started) and a confirmation there is friction for nothing.
- **≥1 completed set** → confirm, naming the count: *"Replace Bench Press? 3 logged sets will be
  removed."* Destructive role on the confirm button.

### 4.3 Flow

1. Long-press the tab → **Replace Exercise…**
2. Sheet presents `ExerciseListView` in `.browse` mode. **No new picker UI is needed** — browse mode
   already single-taps straight to one ID
   ([ExerciseListView.swift:195](Repster/Features/Exercise/Views/ExerciseListView.swift:195)).
3. On selection, `replaceExercise(at: index, with: newExerciseId)`.

### 4.4 `replaceExercise(at:with:)` — the ordered steps

Order matters here; several steps are only correct in this position.

1. **Guard** `index` in range. Guard `newExerciseId` is not already in `exercises` — replacing A with
   B when B is already at position 5 would produce a duplicate the strip cannot disambiguate (the
   `ForEach` is keyed `id: \.element.id`). Reject, or offer to merge; see §10.
2. **Fetch the snapshot first**: `exerciseService.fetchExerciseSnapshot(newExerciseId)`. If it
   returns nil, abort **before** deleting anything. Doing this first means a failed fetch is a no-op
   rather than a workout with a hole in it.
3. **Hide the keypad** if it owns a row of the outgoing exercise, before the sets are deleted
   (§3, keypad bullet). **Resolved for free by step 1**: the view observes `selectedExerciseId`, so
   re-anchoring selection onto the replacement (step 8, hoisted to run before the awaits) fires
   `setKeyboardManager.hide()` on its own. No extra hook was needed.
4. **Swap in place first**: `exercises[index] = newSnapshot`, and `setsByExercise[old.id] = nil`,
   `setsByExercise[new.id] = []`. Then re-anchor selection (step 8) — also before the awaits.

   > **Correction, made while implementing 2026-08-29.** The original draft of this section had the
   > deletes at step 4 and the swap at step 5. That is backwards, and it is the crash pattern:
   > `removeExercise`'s own doc comment records that "the exercise leaves the screen *before* its
   > rows leave the store — the loop awaits once per set, and the set table renders in between.
   > Reading a deleted model traps inside SwiftData." The delete loop suspends, and
   > `ExerciseTabStripView` reads every exercise's sets on every render, so deleting first would put
   > deleted models in front of the main actor. Screen state first, store second.

5. **Delete the outgoing sets** via `setService.delete`, same loop as `removeExercise`
   ([:815-829](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:815)). Discarding the
   returned `PREvaluationResult` is correct here for the same reason it is correct there: PR badges
   are per-exercise, so no set of any *other* exercise on screen can be affected.
6. **Seed one empty working set**: `await addSet(for: newSnapshot.id)`.
7. **Reindex — mandatory.** `persistSetOrdering(reindexOrderInWorkout())`. Step 6 put the seeded set
   at the global tail (§1); without this the replacement jumps to the end of the strip on relaunch.
8. **Re-anchor selection.** If `index == selectedExerciseIndex`, the selected exercise's ID has
   changed, so the side effects must fire even though the integer has not — the §5 helper handles
   this. If a different index was replaced, selection is untouched.
9. `invalidateSetDerivedSubTabCaches()` and `updateLiveActivityState()`.

Suggestions need no explicit call: the Sets tab is keyed
`.task(id: viewModel.currentExercise?.id)`
([ActiveWorkoutView.swift:264](Repster/Features/Workout/Views/ActiveWorkoutView.swift:264)), so
replacing the *selected* exercise re-fires `loadWeightSuggestions()` on its own, and replacing a
non-selected one correctly does nothing.

### 4.5 Edit-historic-workout parity

`EditWorkoutViewModel` conforms to the same protocol and shares the strip, so adding
`replaceExercise` to `SetTableDataSource` means the menu item appears there too. Its implementation
is simpler (draft model, persists on save, no reindex needed). Building both is cheaper than
conditionally hiding the item, and leaving the two view models divergent is precisely the drift that
`PRBadgeApplier`'s doc comment
([SetTableDataSource.swift:58-68](Repster/Features/Workout/Protocols/SetTableDataSource.swift:58))
records as the source of a previous near-miss.

---

## 5. The shared piece: one selection helper

All three changes need the same primitive, and it should exist once:

```swift
/// Re-anchor the selection onto `exerciseId` after `exercises` has been mutated.
///
/// Selection is identity-based, not positional: reordering or replacing must keep the user on
/// the exercise they were looking at, and must fire the switch side effects whenever the
/// *exercise* changes — including when the index lands on the same integer.
private func setSelectedExercise(id exerciseId: UUID?) {
    let previousId = /* exercise selected before the mutation */
    let newIndex = exerciseId.flatMap { id in exercises.firstIndex { $0.id == id } }
                   ?? min(selectedExerciseIndex, max(0, exercises.count - 1))

    selectedExerciseIndex = newIndex          // didSet fires only if the integer moved
    if exercises[safe: newIndex]?.id != previousId {
        persistSelectedExerciseState()        // idempotent
        updateLiveActivityState()             // idempotent
        onSelectedExerciseChanged?()          // view-side: sub-tab, cache, keypad
    }
}
```

Two notes on why it is shaped this way:

- **The `didSet` stays.** Making it fire unconditionally would double-fire on the common
  tap-a-tab path. Both side effects are idempotent, so a redundant call is harmless, but the
  view-side callback is not something to fire twice. Cleaner to leave `didSet` as the "index moved"
  trigger and add an explicit "exercise changed" trigger alongside it.
- **The view-side work has to be reachable from the view model.** Today it lives in
  `.onChange(of: viewModel.selectedExerciseIndex)` in the view
  ([ActiveWorkoutView.swift:131](Repster/Features/Workout/Views/ActiveWorkoutView.swift:131)), which
  by definition cannot fire when the index is unchanged. See §6 for the options.

---

## 6. The one open design question in the implementation

Sub-tab reset, `clearSubTabCache()` and `setKeyboardManager.hide()` are view-owned and currently
driven by an index `onChange`. Three ways to make them fire on identity change:

| Approach | Cost | Notes |
|---|---|---|
| **(i) Expose `selectedExerciseId: UUID?` on the protocol; view observes `onChange(of:)`** | Small | Most SwiftUI-idiomatic; the view keeps owning its own state. `selectedExerciseIndex` stays as the strip's tap target. Both views change identically. **Recommended.** |
| (ii) Callback closure on the view model | Small | Retain-cycle surface, and a view model reaching into view state. |
| (iii) Bump a `selectionGeneration: Int` the view watches | Smallest diff | Opaque; the next reader has to work out what a generation counter means. |

**(i)** is one computed property on `SetTableDataSource`, one changed `onChange` in each of the two
views, and it is self-describing. It also happens to be the more honest model: the screen's identity
*is* the exercise, and the index is an implementation detail of a horizontal strip.

---

## 7. The UX problem — Move Left is O(n) taps

Replace removes most of the need for tab-walking, because walking left is overwhelmingly what you do
*after* being forced to delete-and-re-add. Worth shipping replace first and seeing whether the
reorder UX complaint survives it.

If it does, the cheap correct fix is a **"Reorder Exercises" sheet**: a standard `List` with
`.onMove`, which gives drag handles, autoscroll and accessibility for free, and calls the same
`reorderExercises(from:to:)`. It also collapses the persistence to **one** write when the sheet
dismisses instead of one per tap — which is the right shape once §2 is fixed, and materially better
than four batched writes for a four-position move.

**Not recommended: drag-to-reorder directly on the strip.** It has to arbitrate against the
horizontal `ScrollView` pan and the existing long-press context menu on the same views. That is a
gesture-precedence problem on the most safety-critical screen in the app, for a cosmetic gain.

Keep Move Left / Move Right in the context menu regardless — they are the accessible path and cost
nothing once the underlying call is correct.

---

## 8. Risk register

| Risk | Likelihood | Why it bites | Mitigation |
|---|---|---|---|
| **Replacement jumps to the end of the strip on the next rebuild** | High if step 4.4.7 is skipped | Order is derived from `MIN(orderInWorkout)`; the seeded set lands at the global tail. Invisible on screen until the array is rebuilt — which is a back-tap and a resume away, not a relaunch away (§1.2). | Reindex at 4.4.7 + the §1.3 DEBUG assertion + a resume-boundary journey test (§9). Not a ViewModel test — `SetServiceStub` always "saves". |
| **A future mutation site breaks the invariant again** | Medium over time | Nothing in the type system or the API says `exercises` order and `orderInWorkout` must agree; `reorderExercises` drifted out of scope of the Stage 2 migration for exactly this reason. | The §1.3 `assertOrderingInvariant` call at every mutation site, so a violation trips in the suite instead of surfacing as a user report months later. |
| **Migrating reorder off `edit()` changes PR badges** | Low | `edit()` re-evaluates PRs with unchanged values — documented as a no-op ([SetRepository.swift:216](Repster/Core/Repositories/SetRepository.swift:216)). But "documented as a no-op" is what `PRBadgeApplier`'s comment says about a rule that turned out to have never fired. | Journey test asserting PR badges are byte-identical across a reorder. |
| **Replacing the selected exercise leaves the keypad bound to a deleted set** | Medium | Keypad lives outside the `.id()`-keyed subtree; draft state is the live model. | Explicit `hide()` at step 4.4.3, ordered *before* the deletes. Test it. |
| **Two exercises with the same ID in `exercises`** | Low | Strip `ForEach` is keyed by exercise ID; duplicates give undefined selection and animation. | Guard at step 4.4.1. |
| **Reorder during an in-flight suggestion refresh** | Low | `@MainActor` is reentrant. Already mitigated — the refresh carries `expectedExerciseId` and drops stale completions ([:1861](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1861)), and `refreshCurrentExerciseSnapshot` resolves its index *after* the await ([:1832-1840](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1832)) precisely because of this. | Verify replace inherits the same discipline: never hold an index across an await. |
| **Stale entry in `workout.excludedExerciseIdsFromProgressionHistory`** | Very low | Replaced exercise ID could linger. In practice exclusions are only set from the historic-edit screen, and `updateProgressionHistoryExclusions` sanitizes by intersection with the workout's actual exercise IDs ([WorkoutService.swift:202](Repster/Core/Services/WorkoutService.swift:202)). | Note only. No work item. |

---

## 9. Test plan

**The existing reorder test pins the wrong implementation.**
`testReorderExercisesPreservesMovedSelectionAndPersistsContiguousOrder`
([ActiveWorkoutViewModelSuggestionRefreshTests.swift:1603](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift:1603))
asserts `setService.editedSetIds` — the per-set `edit()` calls. Fixing §2 will fail it *by design*.
It should be rewritten against `SetServiceStub.orderingBatches`, which the stub already records
([:5013](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift:5013)). Flagging this now so
the failure is not mistaken for a regression mid-implementation.

Note also that this test only covers the case the current code gets *right* (moving the selected
exercise). The broken case has no test at all — which is why the defect shipped.

### ViewModel tests (stubbed services)

- ✅ Reorder a **non-selected** exercise across the selection → `currentExercise` is unchanged. *(verified failing against the old logic before the fix landed)*
- ✅ Reorder the selected exercise → selection follows it. *(regression guard; passed before and after)*
- ✅ Remove an exercise **before** the selected one → selection and persisted state both stay on the user's exercise. *(verified failing against the old logic)*
- ✅ Remove the selected exercise → falls back to clamping. *(regression guard)*
- Reorder → exactly one `applyOrdering` batch, no `edit()` calls, contiguous `orderInWorkout` from 1.
- Replace with no completed sets → array position held, one empty set seeded, old sets deleted.
- Replace at the selected index → exercise-changed side effect fires despite an unchanged integer.
- Replace at a non-selected index → selection and `currentExercise` untouched.
- Replace with an ID already in the workout → rejected, no mutation.
- Replace when the snapshot fetch fails → no sets deleted.
- Replace at a middle index → `applyOrdering` is called, and the resulting numbering puts the
  replacement's seeded set *below* every set of the exercise that follows it. This is the unit-level
  proxy for the §8 headline risk; the journey test is what actually proves it.

### Journey tests (real stack — `WorkoutJourneyTests`)

These are the ones that matter. The harness doc is explicit that ViewModel tests with
`SetServiceStub` "always save" and were blind to both 2026-08-12 defects
([WorkoutJourneyTests.swift:9-15](RepsterTests/WorkoutJourneyTests.swift:9)). **There is currently no
journey test for reorder at all.**

Name these for the **resume** boundary, not "relaunch" — building a fresh view model over the same
container is precisely what a back-tap and a FAB resume does (§1.2), and the name should say the
thing a user would do.

**Shipped 2026-08-29** (`WorkoutJourneyTests`), with two shared helpers: `committedExerciseOrder`,
which reproduces `loadActiveWorkout`'s sort key from a separate `ModelContext`, and
`assertStripOrderMatchesStore`, which is the §1.1 invariant in its user-facing form — *what the strip
shows equals what a rebuild would show*.

- ✅ `testReorderingExercisesSurvivesResume` — the test that catches a missing reindex.
- ✅ `testReorderingAnEarlierExerciseKeepsTheUserOnTheirCurrentSet` — Defect B as a journey.
- ✅ `testReorderingDoesNotDisturbPRBadges` — the §8 pipeline-migration risk. Also pins
  `committedRecordCount`, so PR churn shows up as well as badge changes.
- ✅ `testOrderingInvariantHoldsAfterEveryStripMutation` — add → reorder → remove against the real
  stack, asserting screen-equals-store after each.

**All four were verified to fail against the broken implementations before being kept**: with the
reindex removed, all four fail on *"the strip and the store disagree — the order will change on the
next rebuild"*; with slot-based selection restored, the Defect B journey fails with the user's logged
set reading `[]` instead of `[100.0]` — their work gone from the screen. A journey test that passes
against the bug it was written for is worse than no test.

Still to write, with step 4:

- `testReplacingAMiddleExerciseKeepsItsPositionAcrossResume` — the §8 headline risk, and the reason
  it is a journey test rather than a unit test.
- `testReplacingAnExerciseRemovesItsSetsFromTheStore` — verified through a separate `ModelContext`.
- Extend `testOrderingInvariantHoldsAfterEveryStripMutation` to drive replace in the sequence.

---

## 10. Decisions — resolved 2026-08-29

All five taken. Each landed on the recommendation, so nothing in §1–§9 needs rework.

| # | Decision | Resolution |
|---|---|---|
| 1 | **Replace semantics** (§4.1) | **Option (b)** — delete the outgoing sets, seed one empty set. Replace is data-equivalent to today's delete-then-add; it removes the tab-walking, not the semantics. Option (a) rejected on record: it fabricates history in the new exercise's PR table, e1RM series, charts and fatigue model. |
| 2 | **Confirmation threshold** (§4.2) | **Silent when no sets are completed; confirm when ≥1 is logged**, naming the count. Substituting something you haven't started is the common case and shouldn't cost a tap. |
| 3 | **Duplicate exercise** (§4.4.1) | **Reject with a message.** Guard at step 4.4.1. Merge deferred — it raises ordering questions that would get answered implicitly. Greying the row out in the picker was considered and not taken: it pushes workout state into browse mode for a case the guard already covers. |
| 4 | **Reorder sheet** (§7) | **Deferred.** Ship replace first. Tab-walking is overwhelmingly what you do *because* you were forced to delete-and-re-add, so replace may remove the complaint. Move Left / Move Right stay in the context menu regardless. **Unblocked by:** replace shipping and the complaint surviving it. |
| 5 | **Sequencing** (§11) | **Confirmed as written.** Steps 1–3 before step 4, strictly. |

## 11. Recommended sequencing

Each step is independently shippable and independently testable.

| # | Step | Size | Rationale |
|---|---|---|---|
| 1 | ~~**Defect B — identity-based selection** + the §6 protocol change~~ **— DONE 2026-08-29** | Small | Standalone, no new UI, fixes a live mid-workout data hazard. Ships on its own. Landed with a **third** affected call site: `removeExercise` had the same bug (§3). |
| 2 | ~~**Defect A — reorder onto `applyOrdering`**~~ **— DONE 2026-08-29** | Small (a deletion) | Removes the last instance of a pattern already established as a crash cause. Pinned test rewritten against `orderingBatches`. Landed with a **fourth** finding: `EditWorkoutViewModel.reorderExercises` never wrote `orderInWorkout` at all, so reordering on the historic-edit screen was purely cosmetic (§2.1). |
| 2a | ~~**§1.3 `assertOrderingInvariant`**, called from the existing mutation sites~~ **— DONE 2026-08-29** (wired into `reorderExercises`, `removeExercise`, `addExercises`) | XS | Do it with step 2, while the ordering code is already open. It is DEBUG-only and it is what makes step 3 catch a missing reindex on the offending line instead of at the next rebuild. |
| 3 | ~~**Journey tests for reorder**, at the resume boundary~~ **— DONE 2026-08-29** | Medium | Four journeys, all verified failing against both a missing reindex and slot-based selection. This net now protects step 4. |
| 4 | ~~**Replace exercise** — both view models, menu item, picker sheet~~ **— DONE 2026-08-29** | Medium | The actual feature. The 4.4.7 reindex is the load-bearing line, and removing it was verified to fail the journey net. Note the **ordering correction in §4.4** below. |
| 5 | **Reorder sheet** | Small | Only if still wanted after 4. |

Steps 1–3 are a strict prerequisite for 4: replace depends on reorder's renumbering being correct
and on selection being identity-based. Building replace on top of the current reorder would inherit
both defects and make them harder to see.

**On "the order must be maintained" specifically.** That requirement is satisfied by three things
working together, and none of them is sufficient alone: the mandatory reindex at step 4.4.7 (the
mechanism), the §1.3 assertion (catches a call site that forgets it), and the resume-boundary journey
tests at step 3 (prove it against the real store, where the ViewModel stubs cannot). Ship all three.

---

## 12. Explicitly out of scope

- Supersets / grouped exercises (`FEATURE_SCOPING_BRIEF.md` §7) — the strip will need rework there,
  but that decision is not blocked by this and this is not blocked by it.
- Changing the underlying storage to give exercises a real order field. It would make all of this
  simpler, but it is a migration on the workout schema and is not justified by this change alone.
  Worth revisiting *if* supersets go ahead, since grouping needs somewhere to live too.
- Undo for replace. Delete has no undo today either; adding it for one operation and not the other
  would be inconsistent.
