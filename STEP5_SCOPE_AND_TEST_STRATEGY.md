# Step 5 — Verified Scope and Test Strategy

**Date:** 2026-08-13
**Status:** §0.3 items 1–2 done (§6, §7); item 3 done for the create/complete split and
the delete channel (§8, §10). `edit`/`uncomplete` signatures and items 4–10 not started.
**Prerequisite:** Stage 2 steps 1/3/4 committed (`644f8f9`).
**Device pass:** re-run and **passed 2026-08-13** on the tail work — see `DEVICE_TEST_PASS.md`.
Control re-verified the same day: still crashes with the shipped signature.
**Suite:** 422 tests, 0 failures, 2 skipped by design.

`STAGE2_WRITE_PATH_DESIGN.md` §7 step 5 and §15 describe this work. Every claim in those
sections was re-checked against source before writing this. **Most hold. Four do not.** This
document records the corrections, the real blast radius, the decisions still open, and —
separately — what the test suite has to look like for a change this size to be trustworthy.

---

## 0. Conclusions — read this first

Step 5 converts the active-workout **set** state from live SwiftData models to value types. It is
the last piece of the cross-context crash work and the only remaining exposure of the class that
shipped in 1.3 and 1.4: `ActiveWorkoutViewModel` still holds `workout` and `setsByExercise` as
live models, and `SetTableView` renders off them every frame.

**Two items are implemented:** the `ExerciseHistoryView` surface found on review (§6) — the same
crash shape as B, on the same screen, missing from every earlier list — and the full `ChartSetData`
mirror (§7). The rest is a verified plan and a test net built to catch the conversion going wrong.

### 0.1 What the audit changed about the plan

`STAGE2_WRITE_PATH_DESIGN.md` §7/§15 mostly held. Four things did not:

| # | Correction | Effect |
|---|---|---|
| 1 | **§15 Q2's reasoning is wrong.** The row *does* update before the `await` today — `@Model` carries Observation and `SetRowView` reads `set.completed` directly (probed, not assumed). But the pipeline measures **3.5 ms** on a real 11,785-set store, so awaiting it is imperceptible. | Conclusion unchanged (no optimistic layer), basis replaced. A latency budget now exists and is enforced by a test. |
| 2 | **The blast radius is bigger.** `ExerciseInfoProvider` (which also fetches its own live sets), `WeightSuggestionData`, `SetRowView` and two more fetch sites are missing from §6. | More work than planned; steps 5 and 7 overlap. |
| 3 | **§5's field list is partly wrong.** `targetWeight`, `targetRPE` and `supersetGroupId` are named as needed and have **zero** reads; `completedAt`, `targetRIR`, `side`, `restDurationSeconds` and the override fields are needed and mostly unlisted. | Mirror every field and add a drift guard, on the real reason. **Count corrected: `WorkoutSet` has 40 stored properties + 1 `@Transient`, not 39** — this document undercounted by skipping the legacy `cachedPRStatus`. |
| 4 | **Step 8 is not reachable for `Exercise`** (18 crossings), **and the same is true of `Workout` and `WorkoutSet`.** `SetRepositoryProtocol` returns live `[WorkoutSet]` from five methods and `WorkoutRepositoryProtocol` live `[Workout]` from three, consumed by `StatsService`, `WorkoutService`, `ChartDataService`, `LoadPrescriptionService`, `TemplateService`, `InsightsService`, `ExportService`, `ImportService` and the two backfill migrations — all actors step 5 does not touch. | **Predict nothing. Measure all three with the compiler after the conversion** and remove only what reaches zero. Both the original §7 claim and its first correction were unverified guesses. |

### 0.2 Decisions now settled

1. **Await, then splice.** No optimistic/reconcile machinery (§1.2). Verify on device that
   completing a set still feels instant — the one thing simulator numbers cannot settle.
2. **`ChartSetData` becomes a complete mirror** — done (§7). 40 stored properties, not the 39 this
   document first claimed, and the drift guard needed three declared exemptions rather than being
   a copy of the `ChartExerciseData` one.
3. **Set creation moves into `SetRepository`**, so "the UI never holds a model" stays absolute.
4. **`@Transient persistedFatigueSnapshot` becomes actor-internal** once `edit` takes an id.
5. **`SetService`'s isolation is left alone** until after the conversion.

### 0.3 What has to be done, in order

1. ~~**`ExerciseHistoryView` + `WorkoutHistoryGroup`.**~~ **Done 2026-08-13** — see §6.
2. ~~Extend `ChartSetData` to a full mirror + drift guard.~~ **Done 2026-08-13** — see §7.
3. Convert `SetService`'s **six** live-model signatures to ids and values — `save`, `edit`,
   `uncomplete`, `delete`, plus `fetchSets(for workoutId:)` (`:373`) and
   `fetchSets(for exerciseId:limit:)` (`:391`), which otherwise keep handing live models to the UI.
   Capture the contribution inside the repository. ~~**`delete` must start returning its
   `PREvaluationResult`**~~ **done 2026-08-13, see §8** — split out first because it is additive
   and the signature conversion is not.
4. Convert `ActiveWorkoutViewModel` state and actions. **Gated on `STEP5_DRAFT_STATE_DESIGN.md`**
   — `SetTableView` writes drafted values into the live model on every keystroke (23 sites), and
   the weight-suggestion pipeline reads them, so in-progress edits need a home before
   `setsByExercise` can hold value types. The badge channel and `applyAffectedSets` rewrite are
   done (§9).
5. Convert `SetTableView`, `SetRowView`, `SetRowWrapper`, `CustomRepRangeCommitter`; delete the
   transitional overloads in `WorkoutSetPerformanceFormatter` (note two of the four — the
   `Exercise?`-taking `display` at `:17` and `fieldDisplay` at `:161` — already have zero call
   sites and are deletable now).
6. `ExerciseInfoProvider` and `WeightSuggestionData`.
7. `EditWorkoutViewModel` (forced by the protocol change).
8. `WorkoutSummarySheet` / `computeSummary` (`:1895`) — mechanical, `WorkoutAggregateSummary.summarize`
   already has a generic overload, but it has to be in the list.
9. **`refreshCurrentExerciseConfigurationData` must re-fetch the sets, not just the exercise.**
   `ExerciseService.updateExercise` runs `prService.rebuild` + `statsService.rebuild` when
   `equipmentType`, `unilateral`, `bilateralLoadFactor` or `bodyweightFactor` change (`:227`) — all
   reachable mid-workout from Exercise Settings → More. `rebuild` rewrites `prStatus` on every set
   of that exercise and reports nothing in `affectedSetIds`. Free today via shared instances; stale
   after the conversion.
10. ~~Re-measure `@unchecked Sendable` crossings.~~ **Measured 2026-08-13 — the item is moot.**
    Removing the annotation from `Workout`, `WorkoutSet` and `Exercise` and doing a *clean* build
    produces **zero** crossing diagnostics. The only Sendable warnings emitted are `redundant
    conformance of 'X' to protocol 'Sendable'` for the models that still carry the annotation —
    i.e. the `@Model` macro already conforms them, and the explicit annotations have been
    redundant all along.

    This contradicts two entries in the work record's correction table ("the macro does not supply
    Sendable" and "removing it produces precise per-crossing diagnostics"). Whatever was true when
    those were written, it is not true of the current toolchain. **The annotations were never what
    let the unsafe code compile, and removing them cannot be used to measure exposure.** Any future
    crossing audit needs Swift 6 language mode, not annotation removal. See §11.

Full detail in §3. The delicate functions are `applyAffectedSets` and the delete path — see §0.5.

### 0.4 The test net that exists now

Built 2026-08-13, suite **393 → 422**, 0 failures, 2 skipped by design, runtime 14 s → 34 s.
Most pieces were verified by breaking the code; the exceptions are named honestly below.

| Test file | What it protects | Proven by |
|---|---|---|
| `WorkoutJourneyTests.swift` (14) | the real stack driven from the ViewModel; screen state, committed rows, and a simulated relaunch | 6 of 7 mutations caught |
| `CrossContextRaceTests.swift` (3) | snapshot paths clean under concurrent saves, plus the live-model control | control **crashes** with the exact TestFlight signature |
| `AffectedSetsPreconditionTests.swift` (2) | the two facts step 5's badge plan rests on (§0.5) | measures rather than asserts; fails loudly if identity stops carrying the badge |
| `PipelinePerformanceTests.swift` (1) | the 3.5 ms latency budget the design depends on | **not mutation-tested.** Budget derived from an *on-disk* measurement but enforced on an in-memory store, so it catches order-of-magnitude regressions only — which is what it claims, but the calibration is not like-for-like |
| `RealDataDifferentialTests.swift` (2) | before/after equivalence on real history | catches the Stage 1 RIR bug; false positives eliminated. **Scope is narrower than §4.3b promises:** it renders from `setRepo.fetchChartSets` + the formatter — the Stage-1 read path — and never touches `ActiveWorkoutViewModel`, `SetTableView`, `ExerciseInfoProvider` or the finish summary. A strong net for step 1's `ChartSetData` extension; not a net for steps 4–8 |

Plus what was already there: 383 tests including the screen-data golden masters.

### 0.5 Known gaps — carry these into step 5

- **`applyAffectedSets` is inert today — measured, not argued (2026-08-13).**
  `RepsterTests/AffectedSetsPreconditionTests.swift` drives the real stack and pins two separate
  facts that were previously conflated:

  1. **Every** `affectedSetIds` entry arrives *already applied* to the instance the caller holds
     (4 entries across 5 scenarios, 0 mismatches). All five contributing sites in `PRService`
     pair a write to the instance with the map entry — `:113`/`:115`, `:348`/`:350`,
     `:646`/`:648`, and the two merges at `:134`/`:354` which re-import already-paired frontier
     entries. So every assignment in `applyAffectedSets` is a self-assignment, and the
     `isStatusUpgrade` guard can never fire: it compares `newStatus` against itself.
  2. **The rule is not vacuous, though.** Measured against the status each set held *before* the
     save — which is what the rule will compare against once sets are value types — **one
     reachable case suppresses**: `uncomplete` frees a dominated rep bucket and promotes a
     completed set `.dominated → .current`. Unreachable through `save`; a bucket only returns to
     the suffix-max frontier when a dominating record goes away.

  **So step 5 is a behaviour change here, not a pure refactor.** After the conversion that
  promotion gets suppressed on screen while the store says `.current` — which is precisely the
  divergence `assertScreenMatchesStore` fires on. Decide whether the no-promotion rule should
  survive *before* writing the conversion, then **extract it into one pure function shared by
  both ViewModels and unit-test it directly.** Note `EditWorkoutViewModel.refreshPersistedWorkoutPRState`
  (`:437`) already re-reads statuses by id and applies them **without** the rule — the two
  ViewModels already disagree, and the extraction has to resolve that.

- **The delete path has no channel to the ViewModel at all — worse than `applyAffectedSets`.**
  `SetService.delete` computes `prService.handleDeletion(...)` and discards it (`_ =`, `:338`);
  it returns `Void`, so `ActiveWorkoutViewModel.deleteSet` (`:670`) never calls
  `applyAffectedSets`. Deleting a PR owner promotes another set — `PRService:720` writes
  `winner.prStatus` — and that reaches the screen *only* through object identity. Pinned by
  `testDeletingAPROwnerPromotesAnotherSetThroughIdentityAlone`. **`delete` has to start returning
  its `PREvaluationResult`, and `deleteSet` has to apply it.** Same applies to the two `edit`
  results discarded at `ActiveWorkoutViewModel:826` and `:2242` (`updateSetNote`).
- **No view-layer tests exist.** Prefer extracting the pure decisions out of `SetTableView`
  (`inputHeaders(for:)`, column visibility) over adding a view-testing dependency. XCUITest
  smoke journeys are worth adding after step 5, as a release gate rather than per-commit.
- **The differential only covers what this history exercises.** `excludeFromPRs`,
  `supersetGroupId`, `rpe` and `targetRPE` appear in zero sets.
- **No journeys for Calendar detail or Copy Previous** as sequences; the golden masters cover
  their read paths only.

---

## 1. Verification of the existing plan

### 1.1 What holds

| Claim | Verified |
|---|---|
| §15 Q3 — `updatedAt` is write-only in the UI, need not reach the snapshot | Holds. Zero reads of `.updatedAt` anywhere under `Repster/Features/` that are not writes |
| §15 Q4 — `applyAffectedSets` mutates through a `let` array and only compiles because `WorkoutSet` is a class | Holds verbatim, `ActiveWorkoutViewModel:2086` and `EditWorkoutViewModel:525`, identical bodies |
| §15 Q4 — the dictionary is `[UUID: CachedPRStatus?]` and `if let` unwraps the *outer* optional | Holds. A present-but-`nil` entry legitimately clears a badge; flattening with `??` would kill demotions |
| §15 Q1 — `SetService` still receives live models | Holds. `save`, `edit`, `uncomplete`, `delete` all take `WorkoutSet` |
| §2 — `SetTableDataSource` is mostly intent-based; actions use the model for identity | Holds for 6 of 7. `uncompleteSet` also takes a `SetContributionSnapshot?` captured by the caller *from the live set* |
| §3.3 — capturing the contribution inside the actor removes an ordering trap | Holds, and is now the natural shape once actions take ids |
| §4 / step 4 — the reindex fan-out is gone | Holds (and its persistence hole was fixed 2026-08-12) |

### 1.2 Correction 1 — §15 Q2's conclusion is right, its reasoning is wrong. No optimistic path.

§15 Q2 concludes: *"`completeSet` mutates `set.effectiveWeight` / `set.prStatus` **after**
`setService.save(set)` returns … So today's behaviour is already await-then-update. Same latency,
less code, no optimistic/reconcile machinery required."*

That reads only lines 441-445. Lines **432-435 run before the await**:

```swift
applyCompletionInput(input, to: set)   // writes weight/reps/RIR/left/right — 9 fields
set.completed = true
set.completedAt = Date()
set.updatedAt  = Date()

let result = try await setService.save(set)   // ← the await
```

The question is whether those pre-await writes are *visible*. They are:

- `SetRowView` takes `let set: WorkoutSet` and reads `set.completed` directly in its body
  (`SetRowView.swift:233, 377, 385, 404, 415, 429, 441, 452` — 37 `set.` reads in total).
- `@Model` carries Observation. Probed rather than assumed: `WorkoutSet is any Observable` is
  true, and `withObservationTracking { _ = set.completed } onChange:` **fires** when `completed`
  is set. So the row re-renders on the pre-await mutation, not on the array self-assignment
  at step 4b.

**So the current UX is: tap → the row flips to completed with the typed values immediately →
the PR badge and effectiveWeight land a round-trip later.** A naive conversion — await the
repository, then splice the returned snapshot — moves the *entire* visual response behind
`SetService.save()`: an exercise fetch, a derivation hop, a bodyweight + health-profile fetch,
an insert-and-save, PR evaluation and a stats write.

This is the highest-frequency interaction in the app, so the question is how long that round trip
actually takes.

**Measured, 2026-08-13 — and the answer settles it.** A real 579-workout / 11,785-set / 171-exercise
history was restored into an **on-disk** store and the pipeline timed with the real service stack:

| | Median |
|---|---|
| `SetService.save()` — typical set, no new PR | **3.5 ms** |
| `SetService.save()` — set that sets a new PR (worst case) | **15.7 ms** |
| phase: `fetchChartExercise` / `syncDerivedFields` / `persist` / `prService.evaluate` | ≤ 0.5 ms each |
| phase: effectiveWeight (exercise + profile + bodyweight fetches) | 1.3 ms |
| phase: `statsService.updateStats` | 1.8 ms |

Busiest exercise in that store had 732 sets; 872 PR records and 171 stats rows existed.

**Conclusion: §15 Q2's *conclusion* is right — no optimistic layer is needed — but its *reasoning*
was wrong.** It is not that the UI already waits (it doesn't; the row responds pre-await today).
It is that the round trip is 3.5 ms, so awaiting it is imperceptible. Even a generous device
multiplier leaves the typical case far under the ~50 ms where a tap starts to feel delayed.

Caveats worth carrying:

- **The simulator is a lower bound.** These ran on Mac hardware; an iPhone doing the same SQLite
  work is slower by an unmeasured factor. The typical case has roughly 10x of headroom, the
  new-PR case about 3x.
- **This is the service pipeline only.** It excludes the SwiftUI re-render and the other work
  `completeSet` does around it (suggestion refresh, Live Activity update), and it excludes
  contention — in the real app a save can queue behind the HealthKit mirror or the insights pass.
- Today's flow already contains one await *before* the visual update whenever a suggestion exists
  (`ActiveWorkoutViewModel:406` fetches the health profile for the prediction snapshot), and that
  fetch is in the 1.3 ms bucket. So a single awaited hop before the row updates is already the
  shipped behaviour in the common case.

**Therefore: await-then-splice. Skip the optimistic/reconcile machinery** — but re-measure if
anything heavy is ever added to the pipeline, which is an argument for §4.4 below.

### 1.3 Correction 2 — the blast radius in §6 is missing two files and two fetch sites

§6's table lists `ActiveWorkoutViewModel`, `SetTableView`, `SetService`, `WorkoutSummarySheet`,
`SetTableDataSource`, `EditWorkoutViewModel`, `SetRepository`, `ExerciseService`. Also in scope:

| File | Why it is dragged in |
|---|---|
| **`ExerciseInfoProvider.swift`** | Takes `currentSets: [WorkoutSet]` and `historicalSets: [WorkoutSet]` (4 signatures), **and fetches its own live sets** at `:23` via `setService.fetchSets(for: exerciseId, limit: nil)` — historical sets faulted on the main actor, a live-model surface the audit never listed |
| **`WeightSuggestionData.swift`** | 5 signatures over `[WorkoutSet]` (`:268`, `:309`, `:337`, `:478`) |
| `ActiveWorkoutViewModel:1523` | A second live fetch: `setService.fetchSets(for: exercise.id, limit: nil)` |
| `EditWorkoutViewModel:437` | `setService.fetchSets(for: workout.id)` for the dirty-set flush |
| `SetRowView.swift` (1,011 lines) | Not listed at all in §6, and it is where the 37 direct `set.` reads live |

Corrected line counts: `ActiveWorkoutViewModel` is **2,273** (§6 says 2,235), `SetService` **464**
(§6 says 443), `SetTableView` 2,051 ✓, `EditWorkoutViewModel` 614 ✓. `WorkoutSummarySheet` is at
`Views/`, not `Views/Components/`.

Also note `ActiveWorkoutViewModel:1895` builds `completedWorkoutSets: [WorkoutSet]` for the finish
summary — so **steps 5 and 7 overlap** more than the plan's ordering implies.

### 1.4 Correction 3 — §5's field list for `ChartSetData` is partly wrong

`WorkoutSet` has **39 stored properties + 1 `@Transient`**. `ChartSetData` currently carries 23.
Measured by counting real reads across `Repster/Features/Workout/` and `Repster/Core/Formatting/`:

| Field | Reads | Needed |
|---|---|---|
| `overrideTargetRepMin` / `overrideTargetRepMax` | 9 each | yes |
| `completedAt` | 8 | yes |
| `targetRIR` | 8 | yes |
| `targetRepMin` / `targetRepMax` | 4 each | yes |
| `restDurationSeconds` | 4 | yes |
| `preferredTargetRepBounds` (computed) | 4 | yes — port the computation |
| `side` | 2 | yes |
| `startedAt` | 1 | yes |
| `targetWeight`, `targetRPE`, `supersetGroupId`, `rpe`, `pauseDuration`, `e1RMFormulaVersion`, `createdAt` | **0** | no |

§5 names `targetWeight`, `targetRPE` and `supersetGroupId` as required. Nothing reads them.
`statsReps` already exists as a computed `var` (`= totalReps`), contrary to §13.1's implication
that it was added as a stored field.

**Recommendation: make `ChartSetData` a complete mirror anyway** — all 39 — and add the
reflection-based drift guard that `ChartExerciseData` already has
(`testChartExerciseDataCoversEveryStoredExerciseProperty`). Rationale is the one that made step 1
safe: one snapshot type per entity, one `init(from:)`, and a test that *names* a property when the
mirror drifts. The cost is ~16 extra fields on a struct also used by Charts; at flat attributes
and no relationships anywhere in the model layer, that is a few hundred bytes per set and no extra
faulting (the row is already materialised by the fetch).

### 1.5 Correction 4 — step 8 will not be reachable for `Exercise`

§7 step 8 says to drop `@unchecked Sendable` from `Workout`, `Exercise` and `WorkoutSet` after
step 5. §17.2 measured **18 crossings on `Exercise`**, and §17.3's policy is to remove an
annotation only at *zero* crossings. Step 5 removes the set/workout crossings; `Exercise`
crossings also come from `ExerciseListViewModel`, `ExerciseDetailViewModel`, `ExercisePickerSheet`,
`AssignMuscleGroupsView` and `TemplateListSheet`, none of which step 5 touches.

Expect step 8 to land `Workout` and `WorkoutSet` only. Re-measure with the compiler rather than
predicting — §17.2's own note is that protocol-signature counting under-reported `Exercise` by
more than half.

---

## 2. Decisions to take before writing code

1. **Update shape — settled by the §1.2 measurement: await, then splice.** `completeSet(setId:input:)`
   awaits the repository and replaces the element in `setsByExercise` with the returned snapshot.
   No optimistic copy, no reconcile. On throw, restore the pre-edit snapshot — which is now a whole
   struct, so the revert is complete rather than the current one-field rollback (§3.3).
   **Verify on device during the step-5 QA pass** that completing a set still feels instant; that
   check is cheap and is the only thing the simulator numbers cannot settle.
2. **Set creation.** `addSet`/`addWarmupSet` construct `WorkoutSet(...)` on the main actor today.
   Either keep that (the object never enters UI state, and `persist(_:…)` already accepts a
   not-yet-inserted model) or add `SetRepository.create(...) -> ChartSetData`. Prefer **create** —
   it keeps the rule "the UI never holds a model" absolute and makes step 8 reachable for
   `WorkoutSet`.
3. **`@Transient persistedFatigueSnapshot`.** Once `edit` takes an id, the repository fetches the
   model itself and can compute the snapshot inside the actor — the transient becomes actor-internal
   and the last 3 mutations in `SetService` disappear. Confirm the same instance is returned across
   calls (it is: same context, registered object) so the "as last persisted" semantics survive.
4. **`SetService` isolation** (§15 Q1). After step 5 it holds no models; decide then, as its own
   change, not inside step 5.

---

## 3. Recommended order

Each step below builds and passes the suite on its own.

1. **Extend `ChartSetData` to a full mirror** + drift guard test. No behaviour change; entirely
   additive. Port `preferredTargetRepBounds` and the derived-fields sync to value-level logic.
2. **Write the journey harness and the pre-conversion journey tests** (§4 below), against the
   *current* code. They must pass before the conversion — that is what makes them a regression net
   rather than a description of whatever the new code happens to do.
3. **Build the concurrency paired control** (§8 of the design doc): live-model shape crashes,
   snapshot shape clean.
4. **Convert `SetService`'s four signatures** to ids and values; move contribution capture into the
   repository.
5. **Convert `ActiveWorkoutViewModel` state and actions**, including the `applyAffectedSets`
   rewrite (extract one implementation shared with `EditWorkoutViewModel`) and a badge channel on
   the delete path.
6. **Convert `SetTableView`, `SetRowView`, `SetRowWrapper`, `CustomRepRangeCommitter`**; delete the
   4 transitional mixed overloads in `WorkoutSetPerformanceFormatter` and the
   `syncDerivedPerformanceFields(for: ChartExerciseData?)` overload.
7. **`ExerciseInfoProvider` and `WeightSuggestionData`.**
8. **`EditWorkoutViewModel`** (forced by the protocol change).
9. Re-measure `@unchecked Sendable` crossings; remove what reaches zero.

---

## 4. Test strategy — what the tests are actually worth

### 4.1 The evidence we already have

- **391 tests were green while both of the 2026-08-12 defects were present** (ordering never
  committed; exercise snapshot never refreshed).
- The mutation sweep found **8 genuine gaps in one day. Zero came from the suite turning green.**
- The Stage 1 RIR regression produced no crash, no error and no failing test.

The pattern is not "not enough tests". It is that **every test enters the system below the level
where these bugs live.**

| Test style used today | Enters at | Blind to |
|---|---|---|
| Repository contract tests | `SetRepository` directly | anything that depends on what the *caller* did first — e.g. a caller that already mutated the same instance |
| Service tests | `SetService` + real repos | ViewModel state, ordering of UI updates, staleness |
| ViewModel tests | ViewModel + **stubs** | persistence entirely — a stub always "saves" |
| Screen-data golden masters | services + real repos, seeded fixture | sequences; write paths; anything that only appears as *A then B* |
| — | the view layer | everything. No view is constructed anywhere in the suite |

Two of those blind spots are exactly where the two defects sat.

### 4.2 The principle

A test is worth what its **entry point** and the **realness of everything below it** resemble the
real thing. Stubs below the entry point are the expensive part: a `SetServiceStub` that records
calls can never tell you whether the row reached the database.

### 4.3 Tier 1 — journey tests (the missing net, highest value)

Build **one** harness: `ActiveWorkoutViewModel` wired to **real** `SetService`, `PRService`,
`StatsService`, `FatigueLearningService` and **real repositories** on an in-memory
`ModelContainer`. Stub only HealthKit, analytics and the Live Activity manager. Drive it through
user sequences, and after each step assert **three** things:

1. what the ViewModel exposes to the view (`currentSets`, badges, ordering);
2. what a **separate `ModelContext`** on the same container sees (proves *committed*, not pending);
3. after a **simulated relaunch** — construct a *new* ViewModel from the same container and call
   `loadActiveWorkout()` — that the user gets the same thing back.

The relaunch step is the cheapest high-value trick available here, and it alone would have caught
the ordering defect without any second-context machinery.

Journeys worth pinning, each named after what the user did:

- Log three sets on one exercise → finish → Home shows the workout with the right volume and set count.
- Log a set → uncomplete it → re-complete it → PR status, stats and e1RM end where they started.
- Set a PR → log a heavier set → **the first set's badge demotes** (this is `applyAffectedSets`
  and object identity — the single most likely place for a silent step-5 bug).
- Add a warmup set mid-exercise → warmup is first → **survives relaunch**.
- Delete a middle set → remaining orders are contiguous → **survives relaunch**.
- Change rest time from the settings sheet → the next rest timer uses the new value.
- Edit a completed set's weight → stats delta is applied once, not twice.
- A set on a **bodyweight-style** exercise where `effectiveWeight ≠ weight` → the weight column
  renders `effectiveWeight`.

That last one matters beyond itself: the mutation sweep's five misses were **all** fixture poverty,
not logic gaps. Build one shared fixture factory that is deliberately non-default — a bodyweight
exercise, a `.custom` tracking type, a unilateral exercise with `.totalAcrossSides`, a set with a
note, and one non-completed workout — and use it everywhere.

### 4.3a Implementation record — journey tests landed 2026-08-13

`RepsterTests/WorkoutJourneyTests.swift`, registered by hand in `project.pbxproj`
(`TT0100`/`TT2100`). Suite 393 → **400**, all green, ~0.4 s for the seven journeys.

The harness builds the real object graph — real repositories, `SetService`, `PRService`,
`StatsService`, `WorkoutService`, `ExerciseService`, `LoadPrescriptionService`,
`FatigueLearningService` — over one in-memory container. Only HealthKit, analytics and access
control are stubbed, and none of them touch workout data. `SettingsService` gets a no-op
`seedExercises` closure so the 170-exercise library stays out of the fixtures.

Three assertion shapes, as designed: what the screen shows, what a **separate `ModelContext`**
sees, and what a **freshly constructed ViewModel** loads back (the relaunch stand-in).

Landed journeys: logging three sets; warmup placement; deleting a middle set; PR demotion;
uncomplete/re-complete round trip; bodyweight-style `effectiveWeight`; rest-time edit mid-workout.

**Verified by mutation, not by passing.** Five deliberate breaks, in three batches:

| Mutation | Result |
|---|---|
| Restore the pre-fix `applyOrdering` short-circuit | **caught** — warmup journey (`[1,1,2]` vs `[1,2,3]`) and delete journey (`[1,3]` vs `[1,2]`) |
| Drop `refreshCurrentExerciseSnapshot()` | **caught** — rest-time journey |
| `computeEffectiveWeight` ignores bodyweight | **caught** — bodyweight journey, on both the stored value and the rendered column |
| `uncomplete` decrements zero reps | **caught** — twice: the missing decrement, then the double-count on re-complete |
| **`applyAffectedSets` made a complete no-op** | **SURVIVED** — see below |

**The surviving mutation is the important result.** The PR journey passed with
`applyAffectedSets` entirely disabled, because `PRService.swift:113` demotes the old PR owner by
mutating the set object directly — and the ViewModel holds *that same instance*. The badge
reaches the screen through object identity, not through the ViewModel's update path. So the
journey cannot discriminate today.

That is precisely the coupling step 5 removes, which makes it a scoping fact, not just a test
gap: **after the conversion, `applyAffectedSets` becomes the only path by which a demotion
reaches the screen.** It is currently untested in effect, and §15 Q4 already flagged it as the
most likely place for a silent bug.

Two responses, one landed and one for step 5:

- **Landed:** `assertScreenMatchesStore` — a shared invariant asserting the ViewModel's sets
  equal the committed rows field by field (completed, weight, effectiveWeight, reps, PR status,
  set type, both orderings, and the count). Wired into five journeys. Today both paths agree so
  it cannot fail on the PR case; once sets are value types, a missed badge update becomes a
  screen-vs-store divergence and this fires. It is also the general form of the ordering
  defect — screen said `[1,2,3]`, store said `[1,1,2]`.
- **For step 5:** extract the badge-application rule (the `[UUID: CachedPRStatus?]`
  outer-optional unwrap and the no-promotion-for-completed-sets rule) into one pure function
  shared by both ViewModels, and unit-test it directly. This is §4.6's "extraction over
  inspection" applied to the one function that most needs it.

### 4.3b Real-data differential testing (available since 2026-08-13)

A real 579-workout history now sits at `RepsterTests/Fixtures/Local/real-history.repsterbackup`,
gitignored — **this repo is public, so it must never be committed.** Tests that use it skip when
it is absent, so a clean clone stays green.

This enables the strongest net available for a conversion like step 5, and one fixtures cannot
provide: a **before/after equivalence check on real data.**

1. On today's code, restore the backup and dump what every converted surface produces — the set
   table's rendered columns per exercise, ordering, PR badges, the finish summary, Home's recent
   workouts. Write it to a local baseline file (gitignored).
2. Do the conversion.
3. Re-run and diff. Any difference is either an intended change or a regression, and the diff
   names it.

Why this beats fixtures for *this* job: the five misses in §16's mutation sweep were all cases the
fixtures did not contain. Real history contains what real history contains — bodyweight exercises
where `effectiveWeight ≠ weight`, sets logged before fields existed, exercises whose tracking type
changed, unilateral sets, abandoned workouts. It is not a substitute for the journey tests (it is
non-deterministic and asserts only "unchanged", never "correct"), but for a pure refactor —
which step 5 is meant to be — "byte-identical output on 11,785 real sets" is a very strong signal.

Other uses now open: schema-migration rehearsals, and re-running the §1.2 performance numbers
whenever the pipeline changes.

### 4.4 Tier 2 — targeted mutation testing

Keep the discipline, drop the blanket sweep. Before step 5, write down the invariants the
conversion claims to preserve, then break each one and confirm a test fails:

- completed sets receive PR demotions but never promotions (`isStatusUpgrade`);
- a present-but-`nil` entry in `affectedSetIds` clears a badge;
- `save()` never clears a stored e1RM; `edit()` clears the estimate but keeps the formula version;
- `save()` does not stamp `updatedAt`; `edit()` does;
- warmup-first ordering after insert *and* after delete;
- the unilateral derivation runs before the contribution capture.

### 4.4b A performance regression test

The §1.2 numbers are what makes "just await it" safe, so they should stop being a one-off. The real
backup cannot live in a public repo, but a **generated** store can: seed ~12,000 sets across ~170
exercises with a realistic PR-record population, then assert `SetService.save()` stays under a
threshold (say 25 ms in the simulator, with the typical/PR split measured separately).

Calibrated once against the real backup, this catches the thing that would quietly invalidate the
design decision — someone adding a fetch or a rebuild to the logging pipeline.

Related observation from the same run, **not** step-5 work: restoring that backup took **9.9 s** on
the simulator, including the stats and PR rebuild. On a phone that is plausibly 30 s or more. Worth
checking that the restore flow shows progress and cannot be mistaken for a hang.

### 4.5 Tier 3 — the concurrency control

Unchanged from §8: before step 5, a repository-level harness driving concurrent saves against a
main-actor reader, in both the live-model shape (**must crash**) and the snapshot shape (**must be
clean**). A clean run proves nothing without the control.

### 4.6 Tier 4 — the view layer

There is no UI test target and crash B happened *inside a view body*. Options, honestly ranked:

1. **Extraction over inspection (do this).** The decisions inside `SetTableView` that can silently
   break — which columns to show, `inputHeaders(for:)`, badge selection — are pure functions of a
   snapshot and a tracking type. Pull them out of the view body into functions the existing suite
   can call directly. This costs no new dependency and converts view logic into testable logic.
2. **XCUITest smoke journeys (do this after step 5, as a release gate, not per-commit).** Four or
   five flows: start a workout, log a set, add a warmup, finish, see it on Home. Slow and somewhat
   flaky, but it is the only thing that exercises bindings, layout and the real store together.
3. **ViewInspector / snapshot-image testing (skip for now).** An image snapshot would have caught
   the blank RIR column instantly, but they are brittle across simulator and OS versions, and the
   data-level golden masters now cover that specific class.

### 4.7 What "green" should mean before shipping step 5

- Journey tests pass **before** the conversion and **after** it, unchanged.
- The concurrency control still crashes on the live-model path.
- Every invariant in §4.4 has a test that was shown to fail when the invariant is broken.
- The §7.1 device pass re-run, plus: complete a set and confirm the row responds **immediately**
  (the §1.2 regression risk), and force-quit mid-workout to confirm nothing pending is lost.

---

## 5. Implementation record — test infrastructure, 2026-08-13

Suite **393 → 408**, 0 failures, 2 skipped by design. Runtime 14 s → 32 s; the two heavy files
are the race pair (~8 s) and the real-data differential (~9 s).

Four files, each verified by mutation rather than by passing:

| File | Covers | Runs |
|---|---|---|
| `WorkoutJourneyTests.swift` | 9 journeys, real stack, ViewModel entry | always, 0.8 s |
| `CrossContextRaceTests.swift` | snapshot paths clean + the gated live-model control | 2 always, 1 gated |
| `PipelinePerformanceTests.swift` | the §1.2 latency budget | always, 0.7 s |
| `RealDataDifferentialTests.swift` | before/after equivalence on real history | when the fixture is present |

### 5.1 Mutations run against the journeys

Seven deliberate breaks. Six caught, one survived:

| Mutation | Result |
|---|---|
| Pre-fix `applyOrdering` short-circuit | caught — warmup + delete journeys |
| Drop `refreshCurrentExerciseSnapshot()` | caught — rest-time journey |
| `computeEffectiveWeight` ignores bodyweight | caught — stored value and rendered column |
| `uncomplete` decrements zero reps | caught — missing decrement, then a 1000-vs-500 double-count |
| `finishWorkout` drops the summary-sheet notes | caught — finish journey |
| `edit()`'s stats delta forgets the old contribution | caught — 1100 vs 600 on the edit journey |
| **`applyAffectedSets` made a no-op** | **survived** — see §4.3a |

### 5.2 The differential needed fixing before it was worth anything

First run against unmodified code reported **216 differing lines**. Every one was a PR badge,
and the cause is an app behaviour worth knowing independently of testing:

> **Among sets with identical weight and reps, which set holds the PR badge is not
> deterministic.** `PRService.rebuildAll()` assigns it in fetch order, so restoring the same
> backup twice puts the badge on a different one of the tied sets. Cosmetic — the count of
> badges is right and the numbers are identical — but it means two devices restoring the same
> backup can show the star on different rows.

Had this not been caught, the tool would have produced ~216 false positives on every run, which
is worse than no tool: the §16 lesson about verdicts that look like evidence and aren't.

Fixed by rendering badges as a **per-workout, per-exercise tally** instead of per set. A swap
between tied sets no longer registers; a badge disappearing still does — verified by forcing
`CachedPRStatus.effectiveStatus` to return nil, which produced readable diffs
(`current=1 dominated=1 none=2` → `none=4`). Determinism re-checked by recording a baseline and
re-running: identical.

**It catches the regression that motivated it.** Reintroducing the exact Stage 1 RIR bug
(`display(for: ChartSetData)` hardcoding `rir: nil`) is caught with readable diffs —
`rir=4` → `rir=—` on Rope Push Down, `rir=1` → `rir=—` on Dumbbell Row. 392 of the 11,785 sets
carry a logged RIR, which is thin (3%) but sufficient.

Worth noting *how* that was established: on the first attempt the RIR mutation looked uncaught,
because 216 badge false-positives crowded the first ten diffs. A noisy differential does not
just annoy — it hides the signal it exists to surface.

**The real limitation** is narrower than "no RIR": the differential only covers behaviour this
history exercises. `excludeFromPRs`, `supersetGroupId`, `rpe` and `targetRPE` appear in zero
sets, so nothing about them is protected here. Real data covers what the user actually does —
which is why it complements the journey tests rather than replacing them.

### 5.3 How to use each

```bash
# Everything (differential skips without a local fixture)
xcodebuild test -project Repster.xcodeproj -scheme Repster \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# The control — EXPECTED TO CRASH THE RUNNER. That is the passing result.
# The marker is consumed on start, so a forgotten file cannot crash a later full run.
touch RepsterTests/Fixtures/Local/RUN_RACE_REPRO
xcodebuild test -project Repster.xcodeproj -scheme Repster \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:RepsterTests/CrossContextRaceTests/testLiveModelPathStillCrashesUnderConcurrentSaves

# Re-record the differential baseline after an intended change
xcodebuild test -project Repster.xcodeproj -scheme Repster \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:RepsterTests/RealDataDifferentialTests/testRecordBaseline \
  TEST_RUNNER_RECORD_BASELINE=1
```

**The control was run on 2026-08-13 and does crash**, with a signature byte-identical to
TestFlight crash A: `EXC_BAD_ACCESS` / `SIGSEGV`, `KERN_INVALID_ADDRESS at 0x8000000000000010`,
faulting frame `Workout.status.getter` → `_ArrayProtocol.filter(_:)`. So the pair is proven in
both directions, not merely claimed. Re-run it if the snapshot half ever starts looking too easy.

### 5.3a Corrections to this document's own test infrastructure, 2026-08-13

Found on review, all fixed:

- **`testRecordBaseline` could never run.** It gated on `TEST_RUNNER_RECORD_BASELINE`, the exact
  mechanism §5.3 below documents as non-functional in this project — so the only documented way
  to accept an intended differential change silently skipped while reporting success. The same
  failure mode §5.3 warns about, two files apart. Now gated by a consumed marker file
  (`Fixtures/Local/RECORD_BASELINE`), matching the race control. **"2 skipped by design" was
  really 1 by design and 1 broken.**
- **The set-level race test's writer never dirtied the context.** It replayed the ordering
  already stored, so no property changed and `save()` had nothing pending — no registry teardown,
  nothing for the reader to race. Now alternates two genuinely different orderings.
- **`refreshCurrentExerciseSnapshot` captured its array index before the `await`.** `@MainActor`
  is reentrant, so `reorderExercises` or `removeExercise` during the fetch would write the
  snapshot into the wrong slot or out of bounds. Index is now resolved after the fetch.

**Correction to SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md §7.5:** the `TEST_RUNNER_` environment
variable prefix it recommends for firing the harness **does not work in this project**. Verified
by dumping `ProcessInfo.processInfo.environment` inside the test process — neither
`TEST_RUNNER_RUN_RACE_REPRO=1` nor a bare `RUN_RACE_REPRO=1` passed to `xcodebuild` arrives, and
the gated test silently *skipped* while reporting `** TEST SUCCEEDED **`. That is the most
dangerous possible failure mode for a control: it looks like it ran. Hence the marker file.

### 5.4 Still open

- The differential adds ~9 s to every run and is only meaningful while a refactor is in flight.
  Worth keeping ungated through step 5, then gating it like the control.
- No journeys yet for the Calendar detail screens or Copy Previous — the golden masters cover
  their read paths, but not as sequences.
- `applyAffectedSets` remains untested in effect until step 5 extracts the rule (§4.3a).

---

## 6. Implementation record — step 1 of §0.3, 2026-08-13

**`ExerciseHistoryView` / `WorkoutHistoryGroup` converted to snapshots.** Suite **410 → 411**,
0 failures, 2 skipped by design.

The surface this closes: `WorkoutHistoryGroup.sets` was `[WorkoutSet]`, fed by a live fetch at
`ActiveWorkoutViewModel:1523`, rendered by `ExerciseHistoryView.setRow` **in a view body on the
main actor** — the same shape as crash B, on the same screen (History sub-tab,
`ActiveWorkoutView:242`), and absent from every earlier scope list because it lives under
`Features/Exercise/`.

| Change | File |
|---|---|
| `fetchChartSets(for exerciseId:limit:)` added | `SetRepository` + protocol |
| `fetchSetSnapshots(for exerciseId:limit:)` added | `SetService` + protocol |
| `sets: [WorkoutSet]` → `[ChartSetData]` | `ExerciseModels.WorkoutHistoryGroup` |
| `setRow(_:index:siblings:)` takes snapshots; manual note check → `set.hasNote` | `ExerciseHistoryView` |
| both producers moved to the snapshot fetch | `ActiveWorkoutViewModel.loadHistoryForCurrentExercise`, `ExerciseDetailViewModel.loadHistory` |

`ExerciseDetailView` needed no change — it already did the boundary conversion for the exercise
half. `ExerciseDetailViewModel.exercise` remains a live `Exercise?`; that is a separate unaudited
surface (work record §6.4), not dragged in here.

### 6.1 One deliberate behaviour change, recorded rather than slipped in

The live fetch calls `markFatigueLearningSnapshotPersisted()` on every set it returns
(`SetRepository:163`); the new snapshot fetch does not, and cannot — it returns value types.

That side effect is **not** neutral, and removing it from this path is the safe direction.
`SetService.edit` reads `@Transient persistedFatigueSnapshot` as "the values as last persisted"
(`:148`), and its fallback — `oldSet.fatigueLearningSnapshot()` where
`oldSet = setRepo.fetch(byId:)` — returns *the same instance* from the same context, already
carrying the caller's edits. So the transient is genuinely load-bearing, and re-marking it on a
**read** path rebases it off whatever the instance currently holds, including values the user has
typed into the set table but not committed. Opening the History tab mid-edit could therefore
corrupt the fatigue-learning baseline.

The authoritative marking points are unaffected: workout load (`fetchSets(for workoutId:)`) and
each write (`SetService:79`, `:259`, `:279`).

**Follow-up for §0.3 item 6:** `ExerciseInfoProvider:23` still calls the live
`fetchSets(for exerciseId:limit:)`, so the incidental marking still happens on that path. When
that converts, it disappears entirely — at which point confirm the transient is still refreshed
at every moment `edit()` depends on.

### 6.2 Verified by mutation

| Mutation | Result |
|---|---|
| `fetchChartSets(for exerciseId:limit:)` predicates on `workoutId` | **caught** — history empty, group unwrap fails |
| `loadHistoryForCurrentExercise` groups by `exerciseId` instead of `workoutId` | **caught** — 8 assertions, one collapsed group |

New journey: `testHistorySubTabShowsPastSessionsNewestFirst` — two sessions on a bodyweight-style
exercise, asserting group count, newest-first ordering, within-session `orderInExercise`, and
`effectiveWeight` on the snapshots.

### 6.4 A stale-cache bug the conversion promoted from invisible to obvious

Owning the History surface meant checking what invalidates it. `loadHistoryForCurrentExercise`
caches per exercise (`historyLoadedForExerciseId`) and includes the **current** workout's sets, so
every mutation makes it stale — but four of the seven mutation paths invalidated only the PR
cache: `deleteSet`, `changeSetType`, `addSet`, `addWarmupSet`. `updateSetNote` invalidated
neither, and the History row carries a note indicator.

The user-visible effect: open History, go back to Sets, delete a set, return to History — the
deleted set is still listed until the exercise is switched.

Pre-existing, but the conversion changes its character. Holding a deleted live `WorkoutSet` and
reading its properties is undefined behaviour that merely *looked* like staleness; a snapshot of a
deleted row is deterministically stale. Either way wrong, so it is fixed here rather than carried.

All seven paths (plus `clearSubTabCache`) now route through one
`invalidateSetDerivedSubTabCaches()`, because the failure mode was precisely that four sites had
to remember two assignments and remembered one.

Journey: `testDeletingASetRemovesItFromTheHistoryTabWithoutSwitchingExercise`. **Verified by
mutation** — reverting `deleteSet` to PR-only invalidation fails it.

### 6.3 An inconsistency found while writing it — left alone

The first version of the journey asserted the history row renders `effectiveWeight` (90 kg), by
analogy with the set table. It does not, and never did:

- `ExerciseHistoryView` calls `display(for:exercise:unitPreference:)`, whose `performanceLabel`
  is built from the **raw** `weight` plus an `isBodyweightStyle` marker (`:314`).
- The workout-detail cards call `fieldDisplay(...)`, which resolves `effectiveWeight ?? weight`
  (`:171`).

So the same bodyweight set reads `10 kg × 6` in history and `90` on the detail card. That predates
this work and is **not** changed here — a type refactor is the wrong place to alter what a screen
shows. The journey now pins the actual behaviour, so changing it later registers as a behaviour
change rather than a tidy-up. Worth a product decision on its own.

---

## 7. Implementation record — step 2 of §0.3, 2026-08-13

**`ChartSetData` is now a complete mirror of `WorkoutSet`.** 24 stored fields → 40. Suite
**411 → 412**, 0 failures, 2 skipped by design.

Added: `startedAt`, `completedAt`, `e1RMFormulaVersion`, `rpe`, `pauseDuration`, `side`,
`supersetGroupId`, `targetWeight`, `targetRepMin`, `targetRepMax`, `overrideTargetRepMin`,
`overrideTargetRepMax`, `targetRPE`, `targetRIR`, `createdAt`, `updatedAt`,
`restDurationSeconds`. Ported `overrideTargetRepRange`, `hasOverrideRepTarget` and
`preferredTargetRepBounds` from `WorkoutSet`, since those are the rules `SetTableView` and
`SetRowView` read per row.

No call site needed changing: nothing constructs `ChartSetData` except `init(from:)`, so the
memberwise initialiser was never part of the API.

### 7.1 The drift guard needed three exemptions the `Exercise` one does not

`testChartSetDataCoversEveryStoredWorkoutSetProperty` cannot be a copy of
`testChartExerciseDataCoversEveryStoredExerciseProperty`. Each exemption is a property of
`WorkoutSet`, not a weakening of the technique, so all three are declared in the test:

1. **`@Transient` breaks the prefix strip.** SwiftData's macro rewrites persisted properties to
   `_name`; `persistedFatigueSnapshot` stays unprefixed. The `Exercise` guard's blanket
   `dropFirst()` would compare `ersistedFatigueSnapshot`. Confirmed at runtime rather than
   assumed — the test asserts the transient *is* reflected under its own name, so if SwiftData
   ever changes that, the prefix handling gets rechecked instead of silently passing.
2. **`cachedPRStatus` must never be mirrored.** Legacy persisted enum, kept for schema
   compatibility; `WorkoutSet.swift:40` says app logic must not read it. Requiring it in the
   snapshot would mandate the one thing the model forbids.
3. **`prStatus` aliases `cachedPRStatusRaw`; `prReps`/`totalReps` are derived.** Legitimately on
   the snapshot, legitimately absent from the model's storage.

### 7.2 Verified by mutation, in both directions

| Mutation | Result |
|---|---|
| `WorkoutSet` gains a stored `tempoPrescription` | **caught** — `["tempoPrescription"]` … "gained stored properties that ChartSetData does not mirror" |
| `ChartSetData` gains a phantom `cachedDisplayLabel` | **caught** — `["cachedDisplayLabel"]` … "the mirror has drifted" |

Both name the offending property, which is the entire point of the guard over a hand-maintained
field list.

### 7.3 The differential earned its keep

`RealDataDifferentialTests` ran against the local 579-workout / 11,785-set history and produced
**byte-identical output** to the recorded baseline after the mirror went from 24 fields to 40.

That is the strongest available evidence that this step was genuinely additive, and it is exactly
the job §4.3b describes — the differential renders through `fetchChartSets` + the formatter, which
is the surface this change touches. (Its limits still stand for steps 4–8, per §0.4.)

Housekeeping: a stale `Fixtures/Local/screen-actual.txt` is left over from an earlier failing run
and can be deleted; it is only written when a diff is detected.

---

## 8. Implementation record — the delete badge channel, 2026-08-13

Split out of §0.3 item 3 and done first, because it is purely additive: converting
`save`/`edit`/`uncomplete`/`delete` to ids forces both ViewModels to change in the same commit,
while this does not.

`SetService.delete` now returns the `PREvaluationResult` it always computed and discarded
(`_ = try await prService.handleDeletion(...)`), and both ViewModels apply it. Deliberately
**not** `@discardableResult` — ignoring the result is the exact bug this fixes, so all four call
sites had to say what they do with it. The two `removeExercise` bulk deletes ignore it explicitly,
with a comment: the exercise and its rows are leaving the screen.

### 8.1 Writing the test forced §0.5's open question

The new stub test failed on first run, correctly: `applyAffectedSets` **suppressed** the promotion.
The inheriting set is completed with `prStatus == nil`, the pipeline reports `.current`, and
`isStatusUpgrade(nil, .current)` is true — so the no-promotion rule dropped the very update the
new channel exists to deliver.

That is §0.5's probe-B finding firing in the ViewModel for the first time, and it settles one case
of the open question by itself:

> **On the delete path, the rule must not apply.** Today the promotion *is* visible — the rule
> cannot fire, because `PRService` already wrote the status onto the shared instance. Wiring the
> channel with the rule active would therefore not preserve behaviour, it would degrade it: delete
> your 120 kg PR set and the 110 kg set that legitimately inherits the record shows no badge,
> while the store says `.current`. The promotion there is the direct consequence of the user's
> own action, not a retroactive surprise, which is what the rule was written to prevent.

So `applyAffectedSets` gained `suppressPromotionsOnCompletedSets`, defaulting to `true` to leave
every other path exactly as it was. Only the delete path passes `false`.

**The wider question is still open and still belongs to step 5.** The rule has never had an
observable effect on *any* path. Once sets are value types it starts firing everywhere at once,
and probe B found at least one `uncomplete` case it would suppress. Deciding it here, under the
pressure of one failing test, would have been the wrong place — but note the default of `true` is
*not* a decision that the rule is correct, only that this change does not alter those paths.

### 8.2 Why the test is a stub test

Against the real stack this assertion proves nothing: `PRService` writes the status onto the
shared instance before `applyAffectedSets` runs, so it passes with or without the fix. The stub
touches no models, so `applyAffectedSets` is the only route by which the badge can change — which
makes it the only harness that can currently discriminate. It is also a preview of what every
journey test will be able to check once step 5 lands.

---

## 9. Decision — the no-promotion rule is removed, 2026-08-13

**Decided by the app owner.** §0.5 and §8.1 left this open; it is now closed, and the rest of
step 5 should be built on it rather than re-litigating it.

> **Badges always match the stored state.** A completed set may gain a PR badge mid-workout, not
> only lose one.

### 9.1 What was decided against

The removed rule was: *completed in-session sets receive demotions but never promotions*, to avoid
a ★ appearing on a row the user had already finished.

It never had an observable effect in any shipped version (§0.5, measured). Reviving it at step 5
would have introduced a new failure mode rather than preserving anything: delete or un-tick the
set holding a record, and the set that legitimately inherits it shows **no badge** while the store
says `.current` — a screen-vs-store divergence, and one `assertScreenMatchesStore` is designed to
fail on.

The scenario that forced the question is real and ordinary: log 110 kg, log 120 kg, notice the
120 was mistyped, delete it. The 110 kg set is the record again, and under the rule its ★ would
not come back until the workout was reopened.

### 9.2 What landed

- Both ViewModels' byte-identical private `applyAffectedSets` + `isStatusUpgrade` are gone,
  replaced by one `PRBadgeApplier.apply(_:to:)` in `SetTableDataSource.swift`. This is §0.5's
  "extract the rule into one pure function shared by both ViewModels", done — and it was overdue:
  `EditWorkoutViewModel` already contradicted its own copy elsewhere, applying stored statuses
  unconditionally in `refreshPersistedWorkoutPRState`.
- The extraction also removes the `let updatedSets = sets` + subscript mutation that §15 Q4
  flagged as "only compiles because `WorkoutSet` is a class". Iterating references directly says
  what it means, and stops compiling the moment sets become value types — which is the right
  failure at step 5, not a silent one.
- **Five unit tests on the applier**, which is what §0.5 asked for and what no journey test can
  currently provide: promotions applied, demotions applied, present-but-`nil` clears a badge,
  unmentioned sets untouched, incomplete sets not special-cased.

### 9.3 Verified by mutation

| Mutation | Result |
|---|---|
| Flatten the outer optional (`affectedSetIds[set.id] ?? nil`) | **caught** — `testPresentButNilEntryClearsTheBadge` |

That is the §15 Q4 trap: `affectedSetIds` is `[UUID: CachedPRStatus?]`, and a present-but-`nil`
entry means "clear this badge". Flattening turns every clear into a no-op and strands stale ★s.
It now has a test that fails when someone does it.

---

## 10. Implementation record — the service write path, 2026-08-13

Item 3, first two thirds. `edit` and `uncomplete` still take models.

### 10.1 Assumptions checked before starting — two were wrong

Worth recording, because the plan was written on them:

- **"`SetTableView` doesn't write to the model."** False. `SetRowWrapper` has **23 write sites**:
  every keystroke parses the field and assigns straight into the live `WorkoutSet`. The model is
  the draft buffer. (`SetRowView` is read-only — that is where the wrong generalisation came
  from.) **This makes the view half of step 5 a draft-state redesign, not a type swap**, and it
  is a write-side instance of the crash class in its own right.
- **"The conversion can't be split."** False. Service signatures and ViewModel state are
  independent, which is what made this step possible at all.
- `ContentView` is a third write-path caller (Copy Previous), not just the two ViewModels.

Confirmed and load-bearing: completion is **already value-based** — `SetCompletionInput` is built
entirely from the row's `@State` text and never read back off the model. The keystroke writes feed
live suggestions, the derivation and the auto-uncomplete snapshot, not the save.

### 10.2 What landed

- **`create` split out of `save`.** Six sites (`ContentView` ×2, `addSet`, `addWarmupSet`,
  `EditWorkoutViewModel` ×2) only ever wanted a row created, and built the `WorkoutSet` on the
  main actor to get one. Construction now happens inside the repository actor. The pipeline is
  deliberately **not** skipped for these: a Copy Previous set carries weight and reps, so
  `hasData` is true and it is PR-evaluated and counted in stats despite being incomplete —
  shipped behaviour, preserved.
- **`save(setId:input:)`.** `ActiveWorkoutViewModel.completeSet`'s twelve field writes moved into
  `SetRepository.applyCompletion`. That is the highest-frequency main-actor write to a
  repository-owned model in the app, and it is gone. `applyCompletionInput` deleted.
- `EditWorkoutViewModel.completeSet` deliberately untouched: it branches between `save` and
  `edit`, so converting one branch would split where values get applied. It converts with `edit`.

### 10.3 Three mutations survived, and each taught something different

| Mutation | Result | Why |
|---|---|---|
| `applyCompletion` drops the `rir` write | **survived → gap closed** | Every journey completed sets with weight and reps only; the differential never runs the write path. Fixture poverty, exactly the §16 lesson, on the surface being converted |
| `applyCompletion` skips the unilateral derivation | **survived → code removed** | Genuinely dead. `save`'s own `syncDerivedFields` re-runs it a step later on the same instance. `applyCompletionInput` carried the same redundancy |
| `applyCompletion` never clears `side` | **survived → gap closed** | `side` defaults to nil, so the write only matters on a set already holding `.both` — i.e. an exercise flipped from unilateral to bilateral. A real, uncovered edge case |

Three new journeys close the two real gaps: RIR and completion stamps reaching the store, the
unilateral derivation end to end, and the flip-to-bilateral case. All three were re-run against
their mutations and now fail.

**The general lesson for the rest of step 5:** the differential cannot see write-path regressions
at all — it renders restored data. Every remaining item converts write paths, so from here the
journeys are the only net, and they are only as good as the fields the fixtures exercise.

---

## 11. Implementation record — the low-hanging tail, 2026-08-13

Everything outside items 4–5, taken in one pass. Suite stays **422**, 0 failures.

| Item | Outcome |
|---|---|
| 3 (part) | `updateSetNote` and `changeSetType` moved to `updateNote(setId:note:)` / `changeSetType(setId:to:)`. Their field writes now happen in `SetRepository.applyNote` / `applySetType` instead of on the main actor, in **both** ViewModels |
| 8 | `computeSummary` builds `[ChartSetData]`. It runs during `finishWorkout` — i.e. while the workout is being saved — so every read there was a live-model read on the main actor |
| 9 | **Not independent.** Re-fetching sets after a mid-workout exercise rebuild only matters once `setsByExercise` holds value types; today the ViewModel holds the same instances `prService.rebuild` mutates, so a re-fetch is a no-op. Correctly gated on 4–5 |
| 10 | **Moot — see above.** Measured rather than assumed, and the assumption was wrong |

Not converted, with reasons:

- `EditWorkoutViewModel.updateSetNote` branches on `uncountedSetIds` between `save` and `edit`,
  exactly like its `completeSet`. Converting one branch would split where field writes happen, so
  it moves when `edit` does.
- `edit` / `uncomplete` still take models. Their callers no longer *pre-mutate* on the two paths
  above, which was the actual hazard; the signatures are cosmetic until 4–5.

### 11.1 A test that was passing for the wrong reason

`testSetMutationFlowsStillSucceedThroughSetService` failed on the `changeSetType` conversion. Not
a regression: the test put its sets only in `viewModel.setsByExercise` and never in the stub's
store, so it only ever passed because the old code mutated the caller's instance directly. Once
the write moved into the repository, the stub had nothing to write to.

Worth recording because it is a preview of step 5: every place that currently works via shared
instances will surface exactly this way, as a test that quietly depended on the coupling.
