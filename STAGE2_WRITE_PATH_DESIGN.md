# Stage 2 — Active-Workout Write Path Design

**Status:** §3's design agreed. **Steps 1, 3 and 4 complete — see §10, §11, §13, §14.**
Step 2 partly done; steps 5–8 outstanding; §9's open questions still need answers before step 5.
**Date:** 2026-08-12
**Prerequisite:** Stage 1, implemented and verified (see `SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md` §14)
**Fixes:** crash B — `EXC_BAD_ACCESS` faulting `Exercise.trackingType` in `SetTableView.inputHeaders`
while `ExerciseRepository.save` runs

§9 of the crash analysis decided *what* Stage 2 does — "snapshot the active-workout surface" — but not
*how writes work* once the UI holds value types. That is the gap this document closes. It is the
decision that matters, because a mistake here loses a user's logged session rather than crashing.

---

## 1. Why Stage 2 is not just "Stage 1 again"

Stage 1 converted read-only screens. Nothing wrote back, so swapping live models for snapshots was a
substitution with no design content.

The active-workout surface is different, and the reason is specific:

**The live `WorkoutSet` is doing double duty — it is both the persistence handle and the observable UI
state.** The ViewModel mutates the object in place and relies on that same reference being the one
inside `setsByExercise` for the table to re-render:

```swift
applyCompletionInput(input, to: set)          // ActiveWorkoutViewModel:431
set.completed = true
let result = try await setService.save(set)
set.effectiveWeight = result.effectiveWeight  // pipeline result written back onto the model

if let sets = setsByExercise[set.exerciseId] {
    setsByExercise[set.exerciseId] = sets     // self-assignment, purely to poke @Observable
}
```

That self-assignment is the tell. The array never changed — only the shared object did — so the code
has to fake a mutation to get SwiftUI to notice. Every write path in the file has this shape.

So snapshotting doesn't just change a type. It removes the mechanism the UI currently uses to update
itself, and that mechanism has to be replaced deliberately rather than discovered halfway through a
2,235-line file.

## 2. What is already in our favour

The audit turned up more good news than §9 suggests. **`SetTableDataSource` is already mostly
intent-based.** Its action methods take value types for the *data* and use the `WorkoutSet` only to
say *which* set:

| Existing signature | What the `WorkoutSet` is used for |
|---|---|
| `completeSet(_ set:input: SetCompletionInput)` | identity — `SetCompletionInput` is already `Sendable` |
| `uncompleteSet(_ set:previousContribution: SetContributionSnapshot?)` | identity — the snapshot is already a `Sendable` value type with `init(set:)` |
| `changeSetType(_ set:to: SetType)` | identity |
| `updateSetNote(_ set:note: String?)` | identity |
| `persistTargetRepOverride(_ set:min:max:)` | identity |
| `markSetDirty(_ set:field:)` | identity |
| `deleteSet(_ set:)` | identity |

Only one place in the view layer mutates a live model directly:
`CustomRepRangeCommitter.commit(min:max:to set:)` (`SetTableView.swift:69`), which is pure logic and
becomes a function returning values.

So the protocol conversion is mostly *changing the first parameter from a handle to an id*, not
inventing a new command architecture. That materially lowers the risk of this change.

## 3. The design

### 3.1 Rejected alternatives

| Option | Why not |
|---|---|
| **Everything `@MainActor`** | Already dropped outright in §9 — drags ten services, including `LoadPrescriptionService`, onto the main thread. Trading a crash for a hang. |
| **UI models re-fetched into `container.mainContext`** | For writes this is worse than for reads: two contexts would write the same rows, and the write pipeline (PR → stats → fatigue) runs in background actors that would need the other context's objects. Merge-conflict territory for no benefit. |
| **Generic sparse `SetPatch` with per-field optionals** | Nullable fields need `Optional<Optional<T>>` to distinguish "leave alone" from "set to nil". Awkward to write, easy to get wrong, and unnecessary given §2 — the protocol already enumerates the operations. |

### 3.2 Chosen: keep the operation list, change handles to ids, move mutation into the owning actor

Three rules. Everything else follows from them.

**Rule 1 — the UI's source of truth becomes a value type.**
`setsByExercise: [UUID: [WorkoutSet]]` becomes `[UUID: [ActiveSetSnapshot]]`; `exercises: [Exercise]`
becomes `[ChartExerciseData]`; `workout: Workout?` becomes `WorkoutSnapshot?`. Value semantics mean
replacing an element in the array *is* a real mutation, so `@Observable` fires on its own and the
self-assignment hack disappears.

**Rule 2 — actions are addressed by id and carry values.**
`completeSet(_ set: WorkoutSet, input:)` becomes `completeSet(setId: UUID, input:)`. The method list
on `SetTableDataSource` is unchanged; only the first parameter's type changes. Each action returns
(or publishes) the updated snapshot, which the ViewModel splices into the array.

**Rule 3 — the mutation itself happens inside the actor that owns the model.**
This is the load-bearing rule, and it is the one that is *not* satisfied merely by snapshotting the
UI. Today `SetService` is `@MainActor` and mutates `SetRepository`-owned models on the main thread
(`SetService.swift:53, 65, 91, 136-137, 151, 202, 251-254, 351-353`) — that is the §5.5
non-main-cross-context category, and it stays a bug even after the UI holds snapshots.

So the mutations move down into `SetRepository`, which owns the context:

```swift
// SetRepository (@ModelActor) — fetch, mutate and save without the model ever leaving
func applyCompletion(setId: UUID, values: SetFieldValues) throws -> ChartSetData
func applyEffectiveWeightAndPR(setId: UUID, effectiveWeight: Double, prStatus: CachedPRStatus?) throws
func applyUncomplete(setId: UUID) throws -> ChartSetData
func applySetType(setId: UUID, type: SetType) throws -> ChartSetData
func applyNote(setId: UUID, note: String?) throws -> ChartSetData
func applyTargetRepOverride(setId: UUID, min: Int?, max: Int?) throws -> ChartSetData
func applyOrdering(_ ordering: [(setId: UUID, orderInExercise: Int, orderInWorkout: Int)]) throws
```

`SetService` then orchestrates the pipeline (effectiveWeight → PR → stats → fatigue) purely in
values. It never holds a model, so it no longer matters which executor it runs on.

### 3.3 Why this is safer than what exists today, not just different

Three things get *better*, not merely relocated:

- **`SetContributionSnapshot` gets captured inside the actor.** Today the UI captures pre-edit values
  from a live set before mutating it, and `SetServiceProtocol`'s own doc comment admits the hazard:
  *"Some UI paths mutate the live `WorkoutSet` before asking `SetService` to remove its prior
  contribution."* Capturing it in the repository, after the fetch and before the mutation, removes
  that whole class of ordering bug.
- **Failure handling becomes real.** Today `uncompleteSet`'s catch reverts exactly one field
  (`set.completed = oldCompleted`) and leaves everything else the pipeline touched inconsistent. With
  snapshots the pre-edit value is a whole struct — revert is one assignment and it is complete.
- **The `@Transient persistedFatigueSnapshot` stops crossing actors.** It is written in
  `SetRepository.fetchSets` and read/written by `SetService` (`:234`) — transient state on a model
  being passed between executors. Once mutation lives in the repository it never leaves it.

## 4. The `reindex` fan-out — the concurrent writer

§5.3 identified `reindexOrderInExercise` (`:2103`) and `reindexOrderInWorkout` (`:2125`) as the thing
that *manufactures* the overlap: each loops over sets and spawns **one unawaited
`Task { setService.edit(set) }` per changed set**, on routine set insertion and deletion.

Under this design that collapses to a single call:

```swift
try await setService.reorder(ordering)   // one repository call, one save, ordered
```

The whole set of new order values is computed on the ViewModel from snapshots, sent down once, and
applied inside the repository in one transaction. This removes N interleaving main-actor tasks and
N serialised background saves per insertion — and it is worth doing on its own merits regardless of
the crash, since the current code issues an unbounded number of unawaited writes and swallows every
error in a `#if DEBUG` log.

## 5. `ActiveSetSnapshot` — why not just `ChartSetData`

`ChartSetData` (extended in Stage 1) covers most of it, but the active-workout table reads fields the
read-only cards never needed. Union of what `SetTableView` and `ActiveWorkoutViewModel` actually read:

> completed · completedAt · distanceMeters · durationSeconds · effectiveWeight · exerciseId · id ·
> leftRIR · leftReps · notes · orderInExercise · orderInWorkout · prStatus · reps · restDurationSeconds ·
> rightRIR · rightReps · rir · setType · side · updatedAt · weight · workoutId · targetRIR ·
> overrideTargetRepMin · overrideTargetRepMax · preferredTargetRepBounds · syncDerivedPerformanceFields

Missing from `ChartSetData` today: `completedAt`, `side`, `restDurationSeconds`, `updatedAt`,
`targetWeight`, `targetRepMin/Max`, `overrideTargetRepMin/Max`, `targetRPE`, `targetRIR`,
`excludeFromPRs`, `supersetGroupId`.

**Recommendation: extend `ChartSetData` rather than add a second set snapshot type.** Two snapshot
types for one entity would mean two `init(from:)`s to keep in sync — the exact drift that produced the
RIR bug in Stage 1. The added fields are cheap (flat attributes, no relationships anywhere in the
model layer per §13.1) and the read-only screens simply ignore them.

`preferredTargetRepBounds` and `syncDerivedPerformanceFields` are computed logic on the model; both
are pure functions of fields the snapshot will carry, so they move to the snapshot (and, for the
derived-fields sync, to a shared function the repository also uses when applying a completion).

## 6. Blast radius

| File | Lines | What changes |
|---|---|---|
| `ActiveWorkoutViewModel.swift` | 2,235 | state types, ~26 `currentExercise` sites, all write paths, both reindex functions |
| `SetTableView.swift` | 2,051 | row/wrapper types, `CustomRepRangeCommitter`, header + input rendering |
| `SetService.swift` | 443 | mutations move out to the repository; orchestration becomes value-only |
| `WorkoutSummarySheet.swift` | 908 | reads `workout?.title/.notes/.perceivedEffort` and `.displayTitle` in a body, during `finishWorkout`'s save |
| `SetTableDataSource.swift` | 154 | four live-model members + seven action signatures |
| **`EditWorkoutViewModel.swift`** | **614** | **dragged in by the protocol change** — it also conforms (`:586`) and holds live `Workout`/`[Exercise]`/`[UUID: [WorkoutSet]]` (`:23/24/26`) |
| `SetRepository.swift` | — | gains the `apply*` mutation API |
| `ExerciseService` + `CreateEditExerciseViewModel` | — | `updateExercise` stops taking the live instance the UI renders |

`EditWorkoutViewModel` deserves flagging: §5.4 filed it as "not audited", and §10/§11 nominate its
flow as Stage 1's staleness risk. It is not optional here — changing `SetTableDataSource` breaks it —
so Stage 2 ends up auditing it whether or not that was planned.

## 7. Recommended order of work

The ordering below is deliberate: **the smallest slice that fixes the actually-reported crash comes
first**, so the highest-value change is not gated behind the largest one.

1. **The exercise slice — this alone fixes crash B.** Convert `exercises: [Exercise]` →
   `[ChartExerciseData]` and `currentExercise` on `SetTableDataSource` + both conforming ViewModels,
   and make `ExerciseService.updateExercise` take values rather than the live instance the UI is
   rendering. Crash B is precisely `SetTableView.inputHeaders(for:)` faulting `Exercise.trackingType`
   while `ExerciseRepository.save` runs from the edit sheet — both ends of that are in this slice, and
   it does not touch the set write path at all.
2. **Extend `ChartSetData`** with the §5 fields; move `preferredTargetRepBounds` and the
   derived-fields sync to shared value-level logic.
3. **Add the `SetRepository.apply*` API** and move `SetService`'s mutations into it, leaving
   `SetService`'s signatures alone. Verifiable on its own: the suite should stay green with no UI
   change whatsoever.
4. **Replace the reindex fan-out** with the single batched `reorder` call (§4).
5. **Convert the set state and action signatures** — `SetTableDataSource`, `ActiveWorkoutViewModel`,
   `SetTableView`, `SetRowWrapper`.
6. **`EditWorkoutViewModel`** — forced by step 5.
7. **`WorkoutSummarySheet`.**
8. Then §12's guardrail: drop `@unchecked Sendable` from `Workout`, `Exercise`, `WorkoutSet` and fix
   what the compiler surfaces.

Steps 1, 3 and 4 are each independently shippable and independently verifiable. Step 5 is the one
that needs care.

## 8. Verification

The Stage 1 harness pattern transfers directly and should be built **before** step 5, not after:
a repository-level test that drives concurrent saves against a main-actor reader, in the live-model
shape (control, expected to crash) and the snapshot shape (expected clean). That pairing is what made
Stage 1's result trustworthy — a clean run means nothing without a control proving the detector works.

Beyond that, Stage 2 needs something Stage 1 did not, because the failure mode is different:

- **Data-integrity tests, not just crash tests.** Complete a set, uncomplete it, re-complete it,
  change its type, delete it — and assert the persisted row and the on-screen snapshot agree at every
  step. The risk here is silent divergence between UI state and the database, which no crash test
  catches.
- **An ordering test for the batched reorder** — insert and delete sets mid-workout, assert
  `orderInExercise`/`orderInWorkout` are contiguous and warmup-first afterwards.
- **A failure-path test** — make the service throw mid-pipeline and assert the UI snapshot reverts
  completely, not partially.

## 9. Open questions — need a decision before step 5

1. **Does `SetService` stay `@MainActor`?** Once it holds no models it does not need to be, and moving
   it off would take pipeline orchestration off the main thread's 100 ms budget. But `@MainActor`
   currently gives its body a serialization property that the callers may lean on (§5.3 notes it never
   reads while its own save runs). **Recommendation: leave it `@MainActor` for this pass.** The
   crash-relevant change is that it stops touching models; changing its isolation at the same time
   mixes two independent risks in the riskiest file in the app.
2. **Optimistic UI or awaited?** Today the row updates instantly because the object mutates before the
   `await`. Preserving that means applying an optimistic snapshot and reconciling with the returned
   one. **Recommendation: preserve it** — this is the highest-frequency interaction in the app and
   making set completion feel slower would be a real product regression traded for internal tidiness.
3. **Is `updatedAt` on the snapshot load-bearing anywhere**, or is it only ever written? If only
   written, it can stay out of the snapshot and be stamped inside the repository, which is where it
   belongs anyway.
4. **Does anything depend on two ViewModel-held sets being the *same instance*?** The
   `applyAffectedSets(result.prResult.affectedSetIds)` path updates PR status on sets other than the
   one being edited, and today that works partly because everything shares object identity. With value
   types those updates must be applied by id explicitly. This is the single most likely place for a
   subtle correctness bug and should be read carefully before step 5.

---

## 10. Step 1 implementation record — 2026-08-12

The exercise slice (§7 step 1) is done. **Crash B is fixed**, verified by reproduction. Nothing in
§3's design changed; the notes below are what the implementation added to it.

### 10.1 What landed

**Read side.** `SetTableDataSource.exercises`/`currentExercise` are now `ChartExerciseData`, and with
them `ActiveWorkoutViewModel`, `EditWorkoutViewModel`, `SetTableView`, `SetRowView`,
`ExerciseTabStripView`, `SuggestionCoordinator`, `ExerciseInfoProvider`, `ExerciseHistoryView` and
`WorkoutExclusionSheet`.

**Write side.** Mutation moved into the owning actor, per §3.2's Rule 3: `ExerciseRepository` gained
`applyEdit(id:fields:)`, `create(fields:)` and `fetchMetadataSnapshot(byId:)`.
`ExerciseService.updateExercise` now takes `(id:fields:)` and `createExercise` takes `(fields:)`.
`CreateEditExerciseViewModel`, `ExerciseSettingsSheet` and `AssignMuscleGroupsView` send values and
no longer mutate a live model.

### 10.2 Decisions taken during implementation

**`ChartExerciseData` became a complete mirror of `Exercise`** — all 20 stored properties, not just
the fields current callers read. Rationale is §5's: one snapshot type per entity means one
`init(from:)` to keep in sync.

**The shared computed logic now has exactly one implementation each.** `supportsUnilateralLogging`
moved to `TrackingType`; `UnilateralRepTargetMode.resolve` and `ExerciseFatigueRateSource.resolve`
became static functions; `isBodyweightStyle` became a free function. `Exercise` and
`ChartExerciseData` both delegate. This matters most for `unilateralRepTargetMode`, whose fallback
depends on the exercise **name** — two copies could have silently flipped rep targets from per-side to
total for the affected exercises.

**`updateExercise` reads the pre-edit state itself** instead of taking a caller-supplied `original`.
The old contract required callers to snapshot *before* mutating and silently detected no change if
they got it wrong — its own doc comment warned about this. Same semantics, one less trap. It now
throws `exerciseNotFound` for a missing id rather than saving a deleted model.

**`ExerciseEditableFields` excludes the fatigue-learning fields** (`fatigueRate`,
`fatigueLearningSessionCount`, `fatigueLearningCumulativeError`, `recoveryConstant`,
`fatigueRateSourceRawValue`). Those are owned by `FatigueLearningService` and a metadata edit must
not clobber them. Pinned by `testUpdateExercisePreservesFatigueLearningState`.

**Three transitional mixed overloads** were added to `WorkoutSetPerformanceFormatter`
(`display`/`performanceLabel`/`fieldDisplay` for a live `WorkoutSet` with a snapshot exercise) plus
one on `WorkoutAggregateSummary.summarize`, and a `syncDerivedPerformanceFields(for: ChartExerciseData?)`
overload on `WorkoutSet`. They exist only because exercises convert before sets. Each is marked
**DELETE once sets are snapshots too** — step 5 should remove them.

### 10.3 A latent bug found and fixed

`ExerciseSettingsSheet.handleNestedExerciseSave` re-read `exercise.defaultRestTime` and
`.weightIncrement` off the live model after the nested full-settings sheet saved, and got the updated
values for free. A snapshot is frozen, so a naive conversion would have shown pre-edit values with no
error. It now re-fetches explicitly. This is §10's staleness class from the crash analysis, in the
wild — worth expecting more of these in steps 5–7.

### 10.4 Verification

| Check | Result |
|---|---|
| Full suite | **365 tests, 0 failures** (was 355; +10) |
| Crash B control — live `Exercise` read racing a repository save | **crashes**: `EXC_BAD_ACCESS`/`SIGSEGV`, `KERN_INVALID_ADDRESS at 0x8000000000000010`, faulting frame **`Exercise.trackingType.getter`** — the exact frame from TestFlight crash B (§2.2) |
| Same load through the converted path (`fetchAllChartExercises` + `applyEdit`) | **passes** (13.2 s) |
| Live `Exercise` remaining on the crash-B surface | none (audited by grep) |

The temporary race harness was deleted after the run;
`RepsterTests/HealthKitEnergyEstimateTests.swift` is back to pristine.

**New tests, and evidence they have teeth.** Ten tests were added covering snapshot/model parity,
the name-based rep-target fallback, `ExerciseEditableFields` round-tripping, and the persistence
semantics of `applyEdit`/`create`. Each was mutation-tested rather than assumed:

- breaking the snapshot's rep-target rule alone → **7 assertions fail**
- breaking the *shared* rule so model and snapshot are wrong together → **4 assertions fail**
  (the parity assertions can't catch this; the absolute ones do)
- adding a stored property to `Exercise` and not to the mirror →
  `testChartExerciseDataCoversEveryStoredExerciseProperty` fails and **names the missing property**

That last one is a reflection-based drift guard: the field-by-field test can only compare fields
present on both types, so it is blind to a newly added one.

### 10.5 Still outstanding

- Steps 2–8 of §7. Crash A and crash B are both fixed, but the set write path is untouched, so
  `SetService` still mutates `SetRepository`-owned models on the main thread (§3.2 Rule 3), and the
  unawaited reindex fan-out (§4) is still there.
- The §9 open questions — particularly #4, `applyAffectedSets` and object identity.
- On-device QA: edit an exercise mid-workout, per-side rep targets on a `.totalAcrossSides` exercise
  (Dumbbell Lunge is the one with the name-based fallback), and the exercise settings sheet's
  rest-time/increment rows after a nested full-settings save (§10.3).

---

## 11. Steps 4 and 3 implementation record — 2026-08-12

### 11.1 Step 4 — the reindex fan-out is gone (complete)

`SetRepository.applyOrdering(_:)` applies a whole reindex in one transaction inside the actor.
`ActiveWorkoutViewModel`'s two reindex functions now *return* `[SetOrderUpdate]` and the callers
hand them to `persistSetOrdering` in one batch.

**What this removes.** Each changed set used to be persisted by its own unawaited
`Task { setService.edit(set) }` — the full effectiveWeight → PR → stats → fatigue pipeline, for a
change that only touches `orderInExercise`/`orderInWorkout`. With unchanged values that pipeline was
a no-op, so nothing is lost behaviourally; what goes away is N concurrent saves per routine action.
This is the concurrent writer §5.3 identified as *manufacturing* the overlap.

**How much.** The mutation test quantifies it: adding one warmup set to an exercise that already had
two sets issued **5 separate writes** before, and ≤2 batches now. `EditWorkoutViewModel`'s reindex
was already local-only and needed no change.

Error handling is deliberately unchanged — `persistSetOrdering` swallows and logs, exactly as the
per-set `Task`s did, so an ordering write failing still cannot abort the caller's remaining work.

### 11.2 Step 3 — partly done, and the boundary is deliberate

**Done.** `SetRepository` gained `applyUncomplete(setId:)`, `applyPRStatus(setId:status:)` and
`applyTargetRepOverride(setId:min:max:)`. `SetService`'s mutation sites went from **15 to 6**:
uncomplete, both PR-status write-backs and the rep-target override now happen inside the owning
actor. `updateInProgressTargetRepOverride` no longer touches a live model at all.

**Not done — the six remaining sites, all in `save()`/`edit()`:**

```
SetService.swift:53   set.effectiveWeight = effectiveWeight
SetService.swift:65   set.prStatus = nil
SetService.swift:136  set.effectiveWeight = newEffectiveWeight
SetService.swift:137  set.updatedAt = Date()
SetService.swift:151  set.prStatus = nil
SetService.swift:234  set.persistedFatigueSnapshot = currentFatigueSnapshot
```

These are harder than the doc implied, for three specific reasons — worth writing down so the next
pass doesn't rediscover them:

1. **They happen *before* `setRepo.save(set)`, which is also the insert path for new sets.** A
   fetch-by-id-then-mutate method cannot work for a set that isn't in the context yet. The shape
   needed is `persist(_ set:applying:) -> ChartSetData` — insert *and* apply, in one actor hop,
   returning the post-mutation snapshot.
2. **The pipeline reads the set back after mutating it.** `save()` uses `set.prReps`, `.hasData`,
   `.statsReps` and `.excludeFromPRs` *after* `syncDerivedPerformanceFields` has changed them, and
   some of those reads sit after `await`s. Returning a `ChartSetData` from the persist call fixes
   this properly, but `ChartSetData` needs `excludeFromPRs` added first (it is already on step 2's
   list).
3. **`persistedFatigueSnapshot` is `@Transient`.** It is written by `SetRepository.fetchSets` and
   read/written by `SetService`, so it crosses actors as transient state on a model. It has no
   persistence semantics, so it is the lowest-risk of the six, but it needs a decision rather than a
   mechanical move.

Splitting here is a real boundary, not a stopping point of convenience: every mutation that could be
moved without restructuring `save()`/`edit()` has been moved, and what remains needs step 2's
`ChartSetData` fields to land first. Attempting it in the same pass would have meant reshaping the
app's highest-frequency write path without the type it depends on.

### 11.3 Verification

| Check | Result |
|---|---|
| Full suite | **375 tests, 0 failures** (was 365; +10) |
| Reindex batching | Mutation-tested: reverting to per-set writes makes the batching assertion fail with **5 writes vs ≤2** |
| Uncomplete via the repository | Asserted on **both** the persisted row and the caller's own `@Model` instance — `ActiveWorkoutViewModel` depends on the latter to refresh the set table without a reload. Mutation-tested: dropping the `prStatus` write fails both assertions |
| `applyOrdering` contract | `nil` means "leave alone", unknown ids are skipped, empty batch is a no-op, and `updatedAt` is bumped **only** for sets that actually moved |
| Ordering behaviour | Warmup-first placement and contiguous `orderInExercise` after insert and after delete |

New tests live in `SetServiceTests.swift` (end-to-end, against the real `SetService` +
`SetRepository`, not stubs) and `WorkoutSetTests.swift` (repository contract).

### 11.4 Where Stage 2 now stands

Done: step 1 (exercise slice, crash B), step 4 (reindex fan-out), step 3 (9 of 15 mutations).
Outstanding: step 2 (`ChartSetData` fields), the rest of step 3, and steps 5–8 — with step 5 still
the large one, and §9's open questions still unanswered.

---

## 12. Screen-data golden masters — 2026-08-12

Added because the coverage was measured, not assumed. The change to date splits as:

| Layer | Changed | Coverage before |
|---|---|---|
| `Core/` (services, repositories) | +734 / −76 | good — 7 test files drive real repositories against a real `ModelContainer` |
| ViewModels | +120 / −107 | stub-level |
| **SwiftUI views** | **+141 / −127** | **none** — there is no UI test target, and no view is constructed anywhere in the suite |

So ~80% of the diff sits in the best-tested layer, and the exposed part is ~270 lines, most of it
type substitution the compiler checks. But that exposed part is exactly where a *silent* regression
lands, and the RIR near-miss proved the app has no other guard against it.

**`RepsterTests/ScreenDataGoldenMasterTests.swift`** closes that gap without a UI target, by
asserting one level below the view: seed a fixed workout through the **real** service stack
(real repositories, real persistence — the only stubs are HealthKit and analytics), then pin the
complete data each screen produces. Covered: Home recent workouts, week strip, active-workout
detection, recent PRs; Calendar dots, the full `WorkoutDetail` tree, the detail card's rendered
columns, and post-edit reload.

The fixture is deliberately non-default in every field a card renders — a snapshot that drops a
field shows up as a concrete diff rather than a plausible zero.

**These were verified by reintroducing real bugs, not by passing on the first run:**

| Reintroduced bug | Result |
|---|---|
| The **exact** Stage 1 RIR regression (`display(for: ChartSetData)` hardcoding `rir: nil`) | caught, as a readable diff: `["100 kg", "5", "2"]` → `["100 kg", "5", "—"]` |
| Reversed warmup-first set ordering in `selectDate` | caught by **6** assertions — order, set types, reps, RIR, note flags and note text |

The first is the significant one: that bug had no crash, no error and no failing test when it was
found by reading the analysis document. It now fails automatically.

**Registration note.** Only the `WorkoutLiveActivity` extension uses a file-system synchronized
group; `RepsterTests` is a classic target, so this file is registered in `project.pbxproj` by hand
(ids `TT0099` / `TT2099`, following the existing `TT####` convention). Future test files need the
same four entries: `PBXBuildFile`, `PBXFileReference`, group children, and the sources build phase.

Suite: **383 tests, 0 failures** (was 375).

---

## 13. `edit()` converted — 2026-08-12

`SetService`'s live-model mutations are now **24 → 8** (the count in §11.2 said 15; that was measured
with a grep whose character class silently skipped `e1RM` and which missed mutating *method* calls
entirely — the real starting figure was 24).

### 13.1 What changed

`SetRepository` gained `applySyncDerivedFields(setId:exercise:)` and
`applyEditedValues(setId:effectiveWeight:e1RM:e1RMFormulaVersion:clearPRStatus:)`, both returning the
post-mutation `ChartSetData`. `edit()` now computes in values and lets the repository mutate.

Two things fell out of that beyond the mutations themselves:

- **The whole downstream pipeline reads the returned snapshot**, not the live model — PR
  re-evaluation, the stats delta and the PR-status write-back all take `updated.*`. Several of those
  reads previously sat *after* `await`s, so a background save could land mid-read.
- **`ChartSetData` gained `excludeFromPRs` and `statsReps`** (step 2's list), which is what let the
  pipeline stop touching the model.

`edit()` is now the only one of the three write paths that holds no live model between its entry and
its return.

### 13.2 What is left, and why

```
SetService.swift:45,53,59,60,65,68   save()  — 6 sites
SetService.swift:247,267            @Transient fatigue snapshot — 2 sites
```

`save()` still needs the insert-and-apply shape described in §11.2 — its mutations run before
`setRepo.save(set)`, which is also the insert for a brand-new set, so there is no row to fetch yet.
The two `@Transient` sites never touch the persistent store.

### 13.3 Two mutation tests, one real gap found

The suite was green immediately after the conversion, so both preserved behaviours were mutation
tested rather than trusted:

| Mutation | Result |
|---|---|
| Flatten `e1RMFormulaVersion == nil means "leave alone"` into an unconditional assignment | **Not caught** — 383 tests passed with the bug |
| Move the unilateral derivation *after* the old-contribution capture | **Not caught** |

The first is a genuine gap and is now covered by
`testEditClearsE1RMButKeepsTheStoredFormulaVersion`, which fails with the exact message
`("nil") is not equal to ("Optional("epley"))` when the rule is flattened. Clearing a set's estimate
must not wipe the formula version that produced it.

The second turned out to be a **false alarm, and the code comment claiming otherwise was wrong**.
`syncDerivedPerformanceFields` only writes `reps`/`rir`/`side`; `SetContributionSnapshot` captures
`statsReps` and `prReps`, which read `leftReps`/`rightReps` whenever both are set and fall back to
`reps` only in the case where the derivation writes it back unchanged. The order cannot affect the
snapshot. The original order is still preserved — free insurance if that snapshot grows a field that
does depend on it — but the comment now says that accurately instead of overstating it.

Worth noting as a method point: a green suite after a refactor of this path means very little on its
own. Both of these looked verified and neither was.

Suite: **384 tests, 0 failures.**

---

## 14. `save()` converted — step 3 complete — 2026-08-12

`SetService`'s live-model mutations are **24 → 3**, and the three that remain are all
`@Transient` (`persistedFatigueSnapshot`) — they never touch the persistent store, so they are not
the §5.5 hazard. **Rule 3 of §3.2 now holds for the whole set write path.**

### 14.1 The shape that unblocked it

§11.2 recorded `save()` as blocked because its mutations run before `setRepo.save(set)`, which is
also the insert — so a fetch-by-id-then-mutate method cannot work. The resolution was to split
differently rather than by id:

```swift
func syncDerivedFields(on set: WorkoutSet, exercise: ChartExerciseData?) throws -> ChartSetData
func persist(_ set: WorkoutSet, effectiveWeight:, e1RM:, clearPRStatus:, touchUpdatedAt:) throws -> ChartSetData
```

Both take the model rather than an id, which works for a set that isn't in the store yet. Neither
`syncDerivedFields` nor the computation between them touches the context, so there is still exactly
**one** insert-and-save, in the same place the old `setRepo.save(set)` sat. `edit()` was moved onto
the same pair, so the two pipelines no longer have separate repository APIs.

Passing the model into the repository is not a step backwards: the hazard was never "the object
crosses an actor boundary", it is "a non-owning executor mutates it". The repository owns the
context.

### 14.2 The nil-convention is gone

The `e1RM: Double?` + `e1RMFormulaVersion: String?` pair encoded three different behaviours in two
nullable parameters, and the "nil version means leave alone" rule is exactly the one §13.3 found
untested. It is now an explicit type:

```swift
enum E1RMUpdate { case leaveAlone, clear, set(value: Double, formulaVersion: String) }
```

- `save()` → `.leaveAlone` when a set doesn't qualify (it has no `else` branch and never removed a
  stored estimate)
- `edit()` → `.clear` (its `else` branch nils the estimate but keeps the formula version)

The distinction between the two pipelines is now visible at the call site instead of implied by a
nil.

### 14.3 Mutation testing — two more real gaps

As in §13.3, the suite was green immediately and both preserved behaviours turned out to be
unverified:

| Mutation | Before | After |
|---|---|---|
| `save()` uses `.clear` instead of `.leaveAlone`, wiping a stored estimate | **not caught** (384 passed) | fails: `("nil") is not equal to ("Optional(116.66…)") - save() must not clear a stored estimate` |
| `save()` stamps `updatedAt`, which it never did | **not caught** (384 passed) | fails: `save() must not stamp updatedAt` |

Covered by `testSaveLeavesAnExistingE1RMAloneWhenTheSetNoLongerQualifies` and
`testSaveDoesNotStampUpdatedAtButEditDoes`.

That is now **three** genuine gaps found by mutation testing on this path and zero found by the
suite passing. The pattern is consistent enough to state plainly: on this pipeline, a green run
after a refactor carries almost no information. Mutate the behaviour you claim to have preserved.

Suite: **386 tests, 0 failures.**

### 14.4 Where Stage 2 stands

| Step | State |
|---|---|
| 1 — exercise slice (crash B) | done |
| 2 — `ChartSetData` fields | partly — `completed`, ordering, `notes`, RIR, `excludeFromPRs`, `statsReps` added as needed |
| 3 — mutations into the repository | **done** (3 `@Transient` sites remain by design) |
| 4 — reindex fan-out | done |
| 5 — set state + action signatures | outstanding — the large one |
| 6 — `EditWorkoutViewModel` | outstanding |
| 7 — `WorkoutSummarySheet` | outstanding |
| 8 — remove `@unchecked Sendable` | outstanding |

`SetService` is still `@MainActor` and still *reads* live models it is handed. Those reads go when
step 5 changes the signatures to ids and values (§9 open question 1 recommends leaving its isolation
alone until then).
