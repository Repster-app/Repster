# Replace & reorder exercises in the active workout — design

**Date:** 2026-08-17
**Status:** design only, nothing implemented.
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
// ActiveWorkoutViewModel.swift:343-349
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
after relaunch.

Two consequences that shape the whole design:

- **An exercise with no sets does not exist.** It cannot be ordered, and it will not survive a
  relaunch. `addExercises` handles this by immediately seeding an empty set
  ([ActiveWorkoutViewModel.swift:748-749](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:748)).
  Replace must do the same.
- **New sets go to the global tail.** `addSet` assigns `orderInWorkout: totalSets + 1`
  ([:587](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:587)). A replacement
  exercise seeded this way lands *last* in `orderInWorkout` terms even though it sits at position 3
  in the array. On screen it looks correct; reopen the workout and it has jumped to the end.
  **This is the single easiest way to get replace wrong**, and it is invisible until relaunch —
  exactly the defect class the journey tests were written for.

The correct renumbering already exists and is already batched:

```swift
// ActiveWorkoutViewModel.swift:2142  — walks `exercises` in array order, assigns a
// contiguous global orderInWorkout, returns only what changed
private func reindexOrderInWorkout() -> [SetOrderUpdate]

// ActiveWorkoutViewModel.swift:2164  — one awaited, transactional write
private func persistSetOrdering(_ updates: [SetOrderUpdate]) async
```

---

## 2. Defect A — reorder still uses the fan-out that Stage 2 removed

`reorderExercises` persists like this
([ActiveWorkoutViewModel.swift:818-836](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:818)):

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

From [SetRepository.swift:212-217](Repster/Core/Repositories/SetRepository.swift:212), the doc
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

---

## 3. Defect B — selection tracks the slot, not the exercise

```swift
// ActiveWorkoutViewModel.swift:811-813
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
| [`selectedExerciseIndex.didSet`:113-119](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:113) | `selectedExerciseIndex != oldValue` | `persistSelectedExerciseState()` and `updateLiveActivityState()` never run |
| [`ActiveWorkoutView.onChange`:131-135](Repster/Features/Workout/Views/ActiveWorkoutView.swift:131) | `of: viewModel.selectedExerciseIndex` | sub-tab not reset to Sets, `clearSubTabCache()` not called, `setKeyboardManager.hide()` not called |

Concretely:

- **Live Activity shows the wrong exercise name.** Lock Screen and Dynamic Island keep the old one
  until some other action happens to refresh them.
- **Persisted resume state points at the wrong exercise.** The persistence is stored *by exercise
  ID* ([:1029](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1029)) and restored
  by ID lookup ([:996](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:996)) — that
  part is already correct. But it is never re-written, so UserDefaults still holds B while the screen
  shows C. Force-quit and reopen and you land on B. Screen and store disagree.
- **The keypad stays open, bound to a row that is gone.** `SetEntryKeyboardManager.context` holds an
  `ownerSetID` and closures over the set
  ([SetTableView.swift:1173-1194](Repster/Features/Workout/Views/SetTableView.swift:1173)). The Sets
  table itself is rebuilt — it is keyed `.id(viewModel.currentExercise?.id)`
  ([ActiveWorkoutView.swift:240](Repster/Features/Workout/Views/ActiveWorkoutView.swift:240)) — but
  the keypad lives in `bottomAccessoryArea`, outside that subtree, and nothing hid it. The next
  keypress writes into a set that is no longer on screen. Because the draft buffer *is* the live
  model (`STEP5_DRAFT_STATE_DESIGN.md` §1, 23 write sites in `SetRowWrapper`), that write lands on a
  real, persisted-on-commit object.
- **History/PRs flash stale rows.** `clearSubTabCache()` never runs, so the previous exercise's rows
  stay rendered until the `.task(id:)` refetch lands. Self-corrects, but visibly wrong for a beat.

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

[`EditWorkoutViewModel.swift:343-357`](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift:343)
has the identical selection bug (same shape, slightly more verbose). It does not have Defect A — it
is a draft model that persists on save — so it needs the selection fix only.

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
[`ExerciseTabStripView.swift:102-111`](Repster/Features/Workout/Views/ExerciseTabStripView.swift:102):

- **No completed sets** → replace silently. This is the overwhelmingly common case (you are
  substituting something you haven't started) and a confirmation there is friction for nothing.
- **≥1 completed set** → confirm, naming the count: *"Replace Bench Press? 3 logged sets will be
  removed."* Destructive role on the confirm button.

### 4.3 Flow

1. Long-press the tab → **Replace Exercise…**
2. Sheet presents `ExerciseListView` in `.browse` mode. **No new picker UI is needed** — browse mode
   already single-taps straight to one ID
   ([ExerciseListView.swift:195](Repster/Features/Exercises/Views/ExerciseListView.swift:195)).
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
   (§3, keypad bullet). Needs a hook from the view model to the view — see §6.
4. **Delete the outgoing sets** via `setService.delete`, same loop as `removeExercise`
   ([:776-786](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:776)). Discarding the
   returned `PREvaluationResult` is correct here for the same reason it is correct there: PR badges
   are per-exercise, so no set of any *other* exercise on screen can be affected.
5. **Swap in place**: `exercises[index] = newSnapshot`, and `setsByExercise[old.id] = nil`,
   `setsByExercise[new.id] = []`.
6. **Seed one empty working set**: `await addSet(for: newSnapshot.id)`.
7. **Reindex — mandatory.** `persistSetOrdering(reindexOrderInWorkout())`. Step 6 put the seeded set
   at the global tail (§1); without this the replacement jumps to the end of the strip on relaunch.
8. **Re-anchor selection.** If `index == selectedExerciseIndex`, the selected exercise's ID has
   changed, so the side effects must fire even though the integer has not — the §5 helper handles
   this. If a different index was replaced, selection is untouched.
9. `invalidateSetDerivedSubTabCaches()` and `updateLiveActivityState()`.

Suggestions need no explicit call: the Sets tab is keyed
`.task(id: viewModel.currentExercise?.id)`
([ActiveWorkoutView.swift:241](Repster/Features/Workout/Views/ActiveWorkoutView.swift:241)), so
replacing the *selected* exercise re-fires `loadWeightSuggestions()` on its own, and replacing a
non-selected one correctly does nothing.

### 4.5 Edit-historic-workout parity

`EditWorkoutViewModel` conforms to the same protocol and shares the strip, so adding
`replaceExercise` to `SetTableDataSource` means the menu item appears there too. Its implementation
is simpler (draft model, persists on save, no reindex needed). Building both is cheaper than
conditionally hiding the item, and leaving the two view models divergent is precisely the drift that
`PRBadgeApplier`'s doc comment
([SetTableDataSource.swift:51-67](Repster/Features/Workout/Protocols/SetTableDataSource.swift:51))
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
| **Replacement jumps to the end of the strip after relaunch** | High if step 4.4.7 is skipped | Order is derived from `MIN(orderInWorkout)`; the seeded set lands at the global tail. Invisible in-session. | Relaunch assertion in the journey test (§9), not a ViewModel test. |
| **Migrating reorder off `edit()` changes PR badges** | Low | `edit()` re-evaluates PRs with unchanged values — documented as a no-op ([SetRepository.swift:215](Repster/Core/Repositories/SetRepository.swift:215)). But "documented as a no-op" is what `PRBadgeApplier`'s comment says about a rule that turned out to have never fired. | Journey test asserting PR badges are byte-identical across a reorder. |
| **Replacing the selected exercise leaves the keypad bound to a deleted set** | Medium | Keypad lives outside the `.id()`-keyed subtree; draft state is the live model. | Explicit `hide()` at step 4.4.3, ordered *before* the deletes. Test it. |
| **Two exercises with the same ID in `exercises`** | Low | Strip `ForEach` is keyed by exercise ID; duplicates give undefined selection and animation. | Guard at step 4.4.1. |
| **Reorder during an in-flight suggestion refresh** | Low | `@MainActor` is reentrant. Already mitigated — the refresh carries `expectedExerciseId` and drops stale completions ([:1755](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1755)), and `refreshCurrentExerciseSnapshot` resolves its index *after* the await ([:1726-1733](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1726)) precisely because of this. | Verify replace inherits the same discipline: never hold an index across an await. |
| **Stale entry in `workout.excludedExerciseIdsFromProgressionHistory`** | Very low | Replaced exercise ID could linger. In practice exclusions are only set from the historic-edit screen, and `updateProgressionHistoryExclusions` sanitizes by intersection with the workout's actual exercise IDs ([WorkoutService.swift:202](Repster/Core/Services/WorkoutService.swift:202)). | Note only. No work item. |

---

## 9. Test plan

**The existing reorder test pins the wrong implementation.**
`testReorderExercisesPreservesMovedSelectionAndPersistsContiguousOrder`
([ActiveWorkoutViewModelSuggestionRefreshTests.swift:1194](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift:1194))
asserts `setService.editedSetIds` — the per-set `edit()` calls. Fixing §2 will fail it *by design*.
It should be rewritten against `SetServiceStub.orderingBatches`, which the stub already records
([:4407](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift:4407)). Flagging this now so
the failure is not mistaken for a regression mid-implementation.

Note also that this test only covers the case the current code gets *right* (moving the selected
exercise). The broken case has no test at all — which is why the defect shipped.

### ViewModel tests (stubbed services)

- Reorder a **non-selected** exercise across the selection → `currentExercise` is unchanged. *(fails today)*
- Reorder a non-selected exercise across the selection → the exercise-changed side effect fires exactly once. *(fails today)*
- Reorder the selected exercise → selection follows it. *(passes today; must keep passing)*
- Reorder → exactly one `applyOrdering` batch, no `edit()` calls, contiguous `orderInWorkout` from 1.
- Replace with no completed sets → array position held, one empty set seeded, old sets deleted.
- Replace at the selected index → exercise-changed side effect fires despite an unchanged integer.
- Replace at a non-selected index → selection and `currentExercise` untouched.
- Replace with an ID already in the workout → rejected, no mutation.
- Replace when the snapshot fetch fails → no sets deleted.

### Journey tests (real stack — `WorkoutJourneyTests`)

These are the ones that matter. The harness doc is explicit that ViewModel tests with
`SetServiceStub` "always save" and were blind to both 2026-08-12 defects
([WorkoutJourneyTests.swift:5-28](RepsterTests/WorkoutJourneyTests.swift:5)). **There is currently no
journey test for reorder at all.**

- `testReorderingExercisesSurvivesRelaunch` — reorder, then load a fresh view model over the same
  container, assert strip order. This is the test that would catch a missing reindex.
- `testReplacingAMiddleExerciseKeepsItsPositionAfterRelaunch` — the §8 headline risk, and the reason
  this is a journey test rather than a unit test.
- `testReplacingAnExerciseRemovesItsSetsFromTheStore` — verified through a separate `ModelContext`.
- `testReorderingDoesNotDisturbPRBadges` — the §8 pipeline-migration risk.
- `testReorderingAnEarlierExerciseKeepsTheUserOnTheirCurrentSet` — the user-facing statement of
  Defect B, as a journey.

---

## 10. Decisions I need from you

1. **Replace semantics** — confirm option (b): delete the old sets, seed one empty set. (§4.1)
2. **Confirmation threshold** — silent when nothing is completed, confirm when ≥1 set is logged? Or
   always confirm? (§4.2)
3. **Replacing with an exercise already in the workout** — reject with a message, or allow and merge
   the two into one tab? Reject is safer and simpler; merge raises ordering questions I would rather
   not answer implicitly. (§4.4.1)
4. **Reorder sheet** — build it now, or ship replace first and see whether the tab-walking complaint
   survives? I lean toward the latter. (§7)
5. **Sequencing** — my recommendation below.

---

## 11. Recommended sequencing

Each step is independently shippable and independently testable.

| # | Step | Size | Rationale |
|---|---|---|---|
| 1 | **Defect B — identity-based selection** + the §6 protocol change | Small | Standalone, no new UI, fixes a live mid-workout data hazard. Ships on its own. |
| 2 | **Defect A — reorder onto `applyOrdering`** | Small (a deletion) | Removes the last instance of a pattern already established as a crash cause. Rewrite the pinned test. |
| 3 | **Journey tests for reorder** | Medium | Do this *before* replace. Replace reuses the same ordering machinery, so this net protects step 4. |
| 4 | **Replace exercise** — both view models, menu item, picker sheet | Medium | The actual feature. |
| 5 | **Reorder sheet** | Small | Only if still wanted after 4. |

Steps 1–3 are a strict prerequisite for 4: replace depends on reorder's renumbering being correct
and on selection being identity-based. Building replace on top of the current reorder would inherit
both defects and make them harder to see.

---

## 12. Explicitly out of scope

- Supersets / grouped exercises (`FEATURE_SCOPING_BRIEF.md` §7) — the strip will need rework there,
  but that decision is not blocked by this and this is not blocked by it.
- Changing the underlying storage to give exercises a real order field. It would make all of this
  simpler, but it is a migration on the workout schema and is not justified by this change alone.
  Worth revisiting *if* supersets go ahead, since grouping needs somewhere to live too.
- Undo for replace. Delete has no undo today either; adding it for one operation and not the other
  would be inconsistent.
