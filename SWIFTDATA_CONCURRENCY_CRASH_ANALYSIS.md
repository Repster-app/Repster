# SwiftData Cross-Context Crash — Analysis, Reproduction Plan, and Fix

**Status:** diagnosed, **reproduced** (§7.5), **Stage 1 implemented and verified** (§14).
**Stage 2 step 1 done — crash B is fixed** (see `STAGE2_WRITE_PATH_DESIGN.md` §10); steps 2–8 outstanding
**Date:** 2026-08-11
**Affected builds:** 1.4 (6) TestFlight — and 1.3 (3) on the App Store, same root cause
**Crash signature:** `EXC_BAD_ACCESS (SIGSEGV)` at `0x8000000000000010`

> **§13's corrections have now been folded into §5, §8, §9 and §10** (2026-08-11), in the order
> §13.7 recommends. Every §13 claim was re-verified against source first; all held. §13 is retained
> below as the review record — if it and an earlier section still disagree anywhere, **§13 wins** and
> the earlier section has a merge bug worth fixing.
>
> Two things §13 left open have since been resolved: the `SetService` exposure was investigated and
> **the concurrent writer was found** (§5.3 — the caller fan-out, not some hypothetical other task),
> and Stage 2's approach is now decided rather than undecided (§9).
>
> **A second review pass** then found five further blockers, all verified against source and folded in:
> `ChartSetData` needs seven new fields rather than one; the RIR column silently blanks without them
> (§8.1, §10, §11); `fieldDisplay` and `CachedPRStatus.effectiveStatus` need snapshot overloads or
> Stage 1 will not compile (§8.2); `CalendarView` is on the Stage 1 path (§5.2, §8.3); and
> `CalendarExerciseCard:84` is a fourth, already-patched-over instance of this bug class (§5.2). It
> also added a missing category — non-main cross-context mutation (§5.5) — and corrected §5.3's
> mechanism, which was described wrongly here first.
>
> Line numbers throughout are accurate as of 2026-08-11 but will drift as soon as you start
> editing — re-grep rather than trusting them after your first change.

---

## 0. Decisions and order of work

**Working-tree state as of 2026-08-11 — superseded.** Stage 1 is now implemented; see §14 for what
landed, what deviated from the plan below, and the verification results. The reproduction harness has
been deleted and `RepsterTests/HealthKitEnergyEstimateTests.swift` is back to its pristine state.
Everything in §9 (Stage 2) is still to do.

Settled 2026-08-11. Recorded here because they are scattered across §8, §9 and §13 otherwise.

| Decision | Outcome |
|---|---|
| **Release gate** | Nothing ships until **both** crashes are fixed. No hotfix-then-follow-up split. |
| **Stage 1 scope** | Home path **plus** the adjacent read screens — Copy Previous, Calendar, both workout-detail screens. Not Home alone. |
| **Stage 2** | Its own pass, after Stage 1 is verified, still before release (§9). |
| **Stage 2 approach** | Snapshot the active-workout surface. The `@MainActor ExerciseRepository` option is **dropped outright**, not deferred (§9). |
| **`SetService`** | Investigated rather than assumed (§5.3). A concurrent writer was found, so it is **part of Stage 2**, not a third pass. |
| **Signature changes** | Allowed. The original "additive only" constraint is withdrawn (§8). |
| **New files** | Avoided — everything lands in files already registered with the Xcode targets (§8.1). |
| **Fix strategy** | Snapshots, over main-context re-fetch or `@Query`. Reasoning in §4.1. |

Order of work:

1. Snapshot types in `ChartSetData.swift` — `ChartSetData` gains **seven** fields, and the RIR hazard
   must be handled here or it ships invisibly (§8.1)
2. Formatter + PR-status snapshot overloads — `fieldDisplay`, `CachedPRStatus.effectiveStatus`, and fix
   `display(for: ChartSetData …)`'s hardcoded `nil` RIR. **Stage 1 does not compile without these** (§8.2)
3. Repository, then service, then protocol changes (§8.2)
4. The seven test stubs, so the suite compiles (§10)
5. Convert readers: `HomeViewModel` → Copy Previous → `CalendarViewModel` (incl. `selectDate`) →
   both detail screens → `CalendarExerciseCard` → **`CalendarView`** (forced by the `workoutHeader`
   signature change) (§8.3)
6. `mirrorToHealthKit` hygiene (§8.4)
7. Verify in the order §11 specifies — race harness before/after **first**, then delete it, then full
   suite. Do not skip §11's silent-regression block; the RIR column fails without any error.
8. Stage 2 as a separate change (§9)

---

## 1. Summary

Repster hands **live SwiftData model objects** (`Workout`, `Exercise`, `WorkoutSet`, …) out of
background `@ModelActor` repositories and into `@MainActor` UI code. A SwiftData `@Model` object is
not plain data — it is a handle bound to the `ModelContext` that produced it, and reading a persisted
property can fault back into that context to fetch the value.

Because those contexts live on background executors, the main thread ends up faulting properties
through a context it does not own. When that context is simultaneously running `ModelContext.save()`
— which tears down internal registry state — the main thread's read lands on freed memory.

Two crashes were captured on 2026-08-11 in TestFlight 1.4 (6). They are the same bug on different
screens.

**This is the third instance, and the first two were known.** The same class shipped in 1.3 (build 3)
with the same signature — main thread faulting `Exercise.equipmentType` while `ExerciseRepository.save`
ran. On 2026-08-08 the decision was taken to **hold and monitor** rather than fix: there had been one
crash report, and the fix path ran through `ActiveWorkoutView` → `ExerciseSettingsSheet` →
`CreateEditExerciseSheet`, which was fenced off as workout-logging territory at the time. Both
premises have since expired — the count is now three, the logging fence is lifted, and crash B is that
exact path recurring. Worth recording so the "monitor" option isn't reached for a fourth time.

---

## 2. Evidence

Both reports come from **one TestFlight session on one device**: iPhone18,1, iOS 26.6 (23G71),
Repster 1.4 (6), locale da-DK, arm64e, ~100 GB disk free. Same tester, both submitted with a
one-line comment.

**Chronology matters more than the section order below suggests.** Crash B (exercise edit) happened
*first*, at 20:09:17. The app was relaunched two seconds later — 20:09:19 is crash A's launch time —
and crash A (save workout) followed 14 minutes into that new session, at 20:23:58. So a single sitting
produced both, from two unrelated screens. That is a useful frequency signal: this is not a
one-in-a-thousand alignment.

### 2.1 Crash A — "Crashed when I saved workout" (20:23:58)

Incident `258A1C64-E6F0-4B35-96B0-866D6A40C29E`

**Thread 0 (main) — the read:**

```
0  SwiftData  specialized Dictionary.subscript.getter + 0
1  SwiftData  DefaultStore.fulfill<A>(_:from:for:editingState:) + 2552
2  SwiftData  ModelContext.fulfill<A, B>(_:of:for:) + 1164
3  SwiftData  _KKMDBackingData.getValue<A>(forKey:) + 564
5  SwiftData  PersistentModel.getValue<A>(forKey:) + 496
6  Repster    Workout.status.getter
7  Repster    closure #1 in HomeViewModel.loadRecentWorkouts()   HomeViewModel.swift:335
9  Repster    HomeViewModel.loadRecentWorkouts()                 HomeViewModel.swift:335
10 Repster    HomeViewModel.loadData()                           HomeViewModel.swift:129
11 Repster    closure #2 in HomeView.body.getter                 HomeView.swift:107
```

**Thread 11 — the concurrent write:**

```
7  CoreData   -[NSManagedObjectContext reset] + 776
8  SwiftData  closure #2 in closure #1 in DefaultStore.performAndWaitOnContext<A>(for:)
28 SwiftData  DefaultStore.save(_:) + 140
31 SwiftData  ModelContext.save() + 2148
33 Repster    WorkoutRepository.save(_:)                         WorkoutRepository.swift:11
35 Repster    WorkoutService.mirrorToHealthKit(workoutId:start:end:)  WorkoutService.swift:137
```

The main thread is faulting `Workout.status` off the `WorkoutRepository` context while that same
context runs `NSManagedObjectContext.reset()` inside `save()`.

### 2.2 Crash B — "Crash when I edited a exercise" (20:09:17)

Incident `509F4C8F-4FE7-4178-A440-9DEC5CDF75A8`

**Thread 0 (main) — the read, inside a render pass:**

```
0  SwiftData  specialized Dictionary.subscript.getter + 0
1  SwiftData  DefaultStore.fulfill<A>(_:from:for:editingState:) + 2552
...
6  Repster    Exercise.trackingType.getter
7  Repster    SetTableView.inputHeaders(for:)                    SetTableView.swift:219
8  Repster    closure #1 in SetTableView.headerRow(for:)         SetTableView.swift:188
13 Repster    closure #1 in SetTableView.body.getter             SetTableView.swift:133
...
48 UIKitCore  UIHostingViewBase.layoutSubviews()
59 UIKitCore  -[UIView(CALayerDelegate) layoutSublayersOfLayer:]
67 QuartzCore CA::Transaction::commit()
```

**Thread 7 — the concurrent write:**

```
0  libsystem_malloc  malloc_zone_free + 60
1  CoreFoundation    _CFRelease + 1220
3  libswiftCore      _DictionaryStorage.deinit + 568
12 SwiftData         ModelContext.save() + 4528
14 Repster           ExerciseRepository.save(_:)                 ExerciseRepository.swift:11
16 Repster           ExerciseService.updateExercise(_:original:) ExerciseService.swift:122
17 Repster           CreateEditExerciseViewModel.save()          CreateEditExerciseViewModel.swift:131
18 Repster           closure #1 in CreateEditExerciseSheet.saveExercise()  CreateEditExerciseSheet.swift:269
```

This one is unusually explicit: thread 7 is inside `_DictionaryStorage.deinit` → `_CFRelease` →
`malloc_zone_free`, **freeing dictionary storage**, while thread 0 subscripts a dictionary in the
same subsystem.

Note also that `ExerciseService.updateExercise(_:original:)`
(`ExerciseService.swift:106`) receives the **same live `Exercise` instance** the active-workout UI is
rendering — the sheet mutates it on the main actor, then hands it to the repo actor to save.

### 2.3 The shared fingerprint

| | Crash A | Crash B |
|---|---|---|
| Exception | `EXC_BAD_ACCESS` / `KERN_INVALID_ADDRESS` | identical |
| Fault address | `0x8000000000000010` | identical |
| `pc` | `0x1a827207c` (`Dictionary.subscript.getter`) | identical |
| `x20` | `0x8000000000000000` | identical |
| `esr` | `0x92000006` byte read Translation fault | identical |
| Model faulted | `Workout.status` | `Exercise.trackingType` |
| Repository saving | `WorkoutRepository` | `ExerciseRepository` |
| Reader context | ViewModel async load | SwiftUI body during layout |

Two independent events, different screens, different model types, different repositories — landing on
the same instruction with the same poisoned pointer in the same register, each with a `save()` in
flight on another thread.

---

## 3. Root cause

Four design facts combine into the bug:

1. **Every repository is a `@ModelActor`.** `WorkoutRepository`, `ExerciseRepository`,
   `SetRepository` and the other eight in `RepositoryContainer` (`RepositoryContainer.swift:21-34`)
   each own a `ModelContext` on their own background executor, all from the same `ModelContainer`.

2. **Repositories return live models across the actor boundary.** e.g.
   `WorkoutRepository.fetchAllWorkouts` (`WorkoutRepository.swift:57`) returns `[Workout]` — handles
   into the repo's context — straight to `@MainActor` callers.

3. **`@unchecked Sendable` silences the compiler.** All 17 `@Model` types carry it
   (`Repster/Data/Models/*.swift`), e.g. `Workout.swift:95`. Without that, every one of these
   boundary crossings would be a compile error.

4. **The app has no `@Query` anywhere**, so *every* model object the UI touches came out of a
   background context. There is no main-context path.

Then: SwiftData faults persisted properties lazily. `workout.status` is not materialised when the
array crosses the actor boundary — the getter reaches back into the owning context from whatever
thread performs the read. **Actor isolation gives zero protection here**, because the fault happens
later, on the main thread, outside the actor. Meanwhile `ModelContext.save()` tears down that
context's internal state (`reset()` in crash A, dictionary storage dealloc in crash B). Read and
teardown overlap → segfault.

### 3.1 Why "Save workout" specifically triggers crash A

1. Tap Save → `WorkoutService.finishWorkout` performs save #1, then fires
   `scheduleHealthKitMirror` as a **detached, fire-and-forget `Task`** (`WorkoutService.swift:114-120`)
   and returns immediately.
2. `finishWorkout` returns → the fullScreenCover dismisses → `ContentView.swift:237` assigns a new
   `homeRefreshTrigger` → `HomeView.task(id:)` (`HomeView.swift:105`) runs `loadData()`.
3. The mirror Task is meanwhile awaiting `bodyweightService.closestBodyweight` and the real HealthKit
   write (hundreds of ms), so **its save lands precisely during the Home reload**
   (`WorkoutService.swift:137`).

Before 1.4 the finish path did one save and was done, ahead of any reload. HealthKit mirroring added a
*delayed second write racing the read by design*. The bug is not new; the window is.

The comment at `WorkoutService.swift:93-95` correctly avoided passing the live model *into* the Task
(the 1.3 lesson). What was never closed is the **return direction**: repositories handing live models
out to main-actor code.

### 3.2 Why no write-side change can fix crash B

Routing the mutation through the repo actor does not help: `fetch(byId:)` on that context returns the
*same instance*, and `save()` tears down context-internal state either way. The teardown is
context-wide. **The only reliable fix is to stop the main thread reading context-backed models.**

*(Confidence note: this specific point is inference about SwiftData internals, not something the
crash logs prove directly.)*

---

## 4. Ruled-out alternatives

| Hypothesis | Why it's rejected |
|---|---|
| Access after delete | Neither object was deleted; and it wouldn't correlate with a concurrent `save()`. |
| Schema / migration mismatch | `status` and `trackingType` both exist and are non-optional. Would fail deterministically, not only during a save. |
| Memory pressure / jetsam | 100 GB disk free, `Termination Reason: SIGNAL 11`, no jetsam report. |
| Generic SwiftData framework bug | Possible contributor, but the crash requires our specific main-thread-read-during-background-save pattern to line up. |
| Store corruption | Would not produce a poisoned pointer *only* while a save is in flight, timed to a user action. |

**Confidence: confirmed by reproduction on 2026-08-11.** See §7.5 — the crash was reproduced locally
with a byte-identical exception subtype, fault address and faulting frame. What remains unverified is
only the exact internal structure being corrupted, since Apple's framework internals aren't visible.

### 4.1 Why snapshots, and not the two canonical Apple alternatives

§3.2 says "the only reliable fix is to stop the main thread reading context-backed models." That is
overstated as written: it is the only reliable fix *within the current architecture*. Giving the UI a
main-actor context is a real alternative, and the choice should be on the record rather than assumed.

| Strategy | What it does | Why not chosen |
|---|---|---|
| **Snapshots** (chosen) | Value types built inside the owning actor; the UI holds no handles at all | — |
| **Re-fetch into `container.mainContext` by `persistentModelID`** | The UI's models belong to the context that the main thread owns, so faults happen on the owning thread | Relocates the fault onto the main thread rather than removing it: every read path pays a second fetch on main, and Home/Calendar aggregate across sets + exercises + stats + PRs, so that is real work. It also leaves live models in view state, so nothing stops a future hand-off back to a background actor — the same class of bug stays reachable. And it does nothing about the write side (§5.3's main-thread mutations). |
| **`@Query`** | SwiftUI-native, main-context, auto-updating | Fits simple list screens. Repster's are ViewModel-driven with cross-entity aggregation and caching that `@Query` doesn't express; adopting it here is an architecture rewrite of Home and Calendar, not a crash fix. Worth considering independently, on its own timeline. |

Deciding factors for snapshots: the pattern is **already established and proven in this codebase**
(Charts, §6), it **removes** the fault instead of moving it, it keeps aggregation off the main thread,
and it converts **incrementally** — screen by screen, with the compiler enforcing each step once
`@unchecked Sendable` comes off (§12). The accepted cost is explicit reloads in place of implicit
liveness (§10).

---

## 5. Audit — every main-actor live-model read found

Verified by reading the code, not inferred from the traces.

### 5.1 Home path — the reported crash A

| Site | Reads on main actor |
|---|---|
| `HomeViewModel.swift:335` | `Workout.status`, `.date` ← **crash A** |
| `HomeViewModel.swift:341-343` | live `WorkoutSet.setType`, `.hasData`, `.exerciseId` |
| `HomeViewModel.swift:348-352` | live `Exercise.primaryMuscle` |
| `HomeViewModel.swift:355-358` | `WorkoutAggregateSummary.summarize` live overload → faults `trackingType`, `volume`, `distanceMeters`, `durationSeconds` (`WorkoutSetPerformanceFormatter.swift:465`) |
| `HomeViewModel.swift:362-367` | `Workout.displayTitle`, `.date`, `.duration` |
| `HomeViewModel.swift:195, 202` | `Workout.status`, `.date` in `loadWeekData` |
| `HomeViewModel.swift:226, 244-245` | `Workout.date`, `Exercise.primaryMuscle` in `buildWeekDays` |
| `HomeViewModel.swift:169-173` | `Workout.startTime`, live `WorkoutSet.completed`/`.hasData` in `checkActiveWorkout` |
| `HomeViewModel.swift:306-308` | `Exercise.name`, `.unilateral`, `.supportsUnilateralLogging` |
| `HomeViewModel.swift:306-314` | live `PerformanceRecord.exerciseId`, `.value`, `.reps`, `.date` — `StatsService.fetchRecentPRs` (`StatsService.swift:129`) returns live models |
| `HomeViewModel.swift:97` (decl; written at `:397`) | **`exerciseCache: [UUID: Exercise]`** — parks live models for the ViewModel's lifetime. *Not* because reads re-fault (they don't — §13.8), but because any call site reading a property that was never materialised faults *then*, and `reset()` inside a background `save()` re-arms every cached object as a fault |

Critically: fixing only `Workout` would move the crash line, not remove the crash. The sets,
exercises and PR records come from `SetRepository`/`ExerciseRepository`/`PerformanceRecordRepository`
— different contexts, so they don't race the HealthKit save, but they *do* race every set write and
PR/stats rebuild and the fatigue-learning pass, all of which run at workout finish, on the same Home
load.

**Not a racing writer:** the `InsightsService` analysis save. It is its own `@ModelActor` (§13.3) and
returns only value types, so the UI holds no handle into its context and its `save()` tears down a
registry nobody is reading. It belongs in §3's context inventory, not here. (Corrected — an earlier
revision of this section listed it as a writer.)

### 5.2 Adjacent read screens — same bug, not yet crashed

| Site | Reads on main actor |
|---|---|
| `ContentView.swift:533-564` | `loadCopyPreviousWorkouts` — same pattern as `loadRecentWorkouts` |
| `CalendarViewModel.swift:80-93` | `Workout.date`; **`workoutsByDate: [Date: [Workout]]`** parks live models in `@Observable` main-actor state for the session |
| `CalendarViewModel.swift:242` | `.workout.startTime`, `.createdAt` |
| `CalendarViewModel.swift:16` | `WorkoutDetail.workout: Workout` — a live model carried into two detail screens |
| `WorkoutDetailFromHomeView.swift:53, 64, 77, 130` | `.workout.date`, `.displayTitle`, `.id` **read inside the view body** (crash B shape) |
| `CalendarWorkoutDetailView.swift:40, 61, 67, 74` | `.workout.id`, `.duration` **read inside the view body** |
| `CalendarViewModel.swift:9-13` | `ExerciseGroup` holds live `Exercise` + `[WorkoutSet]` + `ExerciseStats?` |
| `CalendarViewModel.swift:34` / `WorkoutDetailFromHomeView.swift:17` | `workoutDetails` parks all of the above in main-actor state for the session |
| `CalendarViewModel.swift:44` | `exerciseCache: [UUID: Exercise]` — same hazard as the HomeViewModel cache |
| `CalendarViewModel.swift:165-234` (`selectDate`) | builds the groups on main: `set.exerciseId`, `.orderInExercise`, `.orderInWorkout`, `.hasData`, live `summarize`, live `ExerciseStats`. The largest single conversion in Calendar |
| `WorkoutDetailFromHomeView.swift:185-235` (`loadDetail`) | same builder shape as `selectDate` |
| `CalendarExerciseCard.swift` (`Views/Components/`) | **The whole body faults live models**, not just `displaySets`: `:14-16` (`displaySets`, filtering `hasData`, sorting `orderInExercise`), `:20` (`exercise.trackingType`), `:42` (`exercise.name`), `:87-88` (`setType`, `notes` for the note dot), `:107-112` (`fieldDisplay` with live models), `:121` (`effectiveStatus` with live models), `:170` |
| `CalendarExerciseCard.swift:84` | **`if workoutSet.modelContext == nil { EmptyView() }`**, commented *"Guard against deleted/detached SwiftData objects to prevent crashes"* — a **fourth instance of this bug class, already patched over in-tree**. Also a live-model-only API with no snapshot equivalent, so the conversion must decide what replaces it (§8.3) |
| `CalendarWorkoutDetailView.swift:92-96` (`workoutHeader`) | takes three `((Workout) -> Void)?` callbacks — live models handed *out* to the caller |
| `CalendarView.swift:14, 16` | `@State workoutToSaveAsTemplate: Workout?`, `workoutToDelete: Workout?`; the wiring at `:300-308` faults `workout.displayTitle` on main at `:302`. **`CalendarView` is on the Stage 1 path** — changing `WorkoutDetail` breaks those callback signatures whether or not it was originally listed |

### 5.3 Active workout — crash B, and the concurrent writers that arm it

| Site | Detail |
|---|---|
| `SetTableView.swift:219` | `Exercise.trackingType` in the view body ← **crash B** |
| `SetTableView.swift:127` | `dataSource.currentExercise` → `ActiveWorkoutViewModel.swift:249`, a live `Exercise` held all session |
| `ActiveWorkoutViewModel.swift:107, 131` | `workout: Workout?` and `setsByExercise: [UUID: [WorkoutSet]]` — live, held all session |
| `ActiveWorkoutViewModel.swift:257` (`currentSets`) | faults `orderInExercise` in a computed property read from `SetTableView.body:128` — highest render frequency in the app |
| `WorkoutSummarySheet:113-116, 756` | reads `workout?.title/.notes/.perceivedEffort` and `.displayTitle` in a body — on the finish screen, concurrent with `finishWorkout`'s save |
| `ExerciseService.swift:106-122` | `updateExercise` takes the live model the UI renders, mutates on main, saves on the repo actor |

`currentExercise` has ~20 read sites in `ActiveWorkoutViewModel` alone, and `SetTableDataSource:62`
exposes `[Exercise]`, so the protocol changes too.

**`SetService` is `@MainActor` (`SetService.swift:13`)** — an entire service reading *and mutating*
live models on the main thread, on the highest-frequency path in the app. Per logged set it faults a
live `Exercise` from `ExerciseRepository` (`:44`, `:120`), a live `oldSet` from `SetRepository`
(`:124-128`), and mutates `effectiveWeight`, `e1RM`, `e1RMFormulaVersion`, `prStatus`, `updatedAt`
(`:53-68`, `:136-151`, `:201-202`).

**The concurrent writer is the app itself** (investigated 2026-08-11).
`SetService`'s own body is sequential — every `await` suspends the main actor, so it never reads while
its own save runs. But `reindexOrderInExercise` (`ActiveWorkoutViewModel.swift:2103`) and
`reindexOrderInWorkout` (`:2125`) loop over the sets and spawn **one unawaited
`Task { setService.edit(set) }` per changed set**, called at `:647`, `:652` and `:678` — on set
insertion and deletion.

**Get the mechanism right, or a repro built on it will fail.** These are *not* N concurrent saves.
`SetService` is `@MainActor`, so those `Task {}`s inherit the main actor, and `SetRepository` is an
actor, so the saves themselves serialise on its executor. The actual hazard is **N main-actor tasks
interleaving at their `await` points, reading and mutating live models, against a serialised stream of
background saves** — while `SetTableView` re-renders off those same models. Same conclusion, different
shape: don't write a harness that tries to fire simultaneous saves.

This is why the set path is not merely "high frequency, low overlap": the overlap is manufactured by
the callers, on a routine action. It belongs to the **Stage 2 surface** (`SetService` +
`ActiveWorkoutViewModel` + `SetTableView` are one problem), not to a separate pass.

### 5.4 Not audited

Not swept, and each holds live models in main-actor state:

- `EditWorkoutViewModel:23/24/26` (live `Workout`, `[Exercise]`, `[UUID: [WorkoutSet]]`), computed
  `:508`/`:515` — **this is the exact flow §10 and §11 nominate as the staleness risk**
- `ExerciseListViewModel:19/23/24`, including `allExerciseStats: [UUID: ExerciseStats]`
- `ExerciseDetailViewModel:22/23`
- `ExercisePickerSheet:34`, `AssignMuscleGroupsView:12`, `TemplateListSheet:656`
- `BodyweightLogViewModel:12/39` (`entriesForChart` computed in a body)
- Insights, Templates, Programs, Settings and Charts' remaining surfaces. Charts appears already
  hardened (§6); `InsightsService` leaks no live models (§13.3). No claim is made about the rest.

`CalendarView` was previously filed here. It is **Stage 1** — see §5.2.

### 5.5 A category this document originally missed: non-main cross-context mutation

§3 states the invariant as "the main thread faulting through a context it does not own." That is too
narrow. **Every service is its own actor**, so any service that fetches a live model from a repository
actor and mutates it is doing the same illegal thing from a *different* non-owning executor — the main
thread is incidental.

Confirmed sites:

| Site | Mutation |
|---|---|
| `WorkoutService.finishWorkout:75-90` | mutates `status`, `endTime`, `duration`, `title`, `notes`, `perceivedEffort`, `updatedAt` on the `WorkoutService` executor, before `:91`'s save |
| `WorkoutService.updateWorkoutMetadata:169-171` | same shape |
| `WorkoutService.mirrorToHealthKit:136` | `healthKitWorkoutUUID` (§8.4 treats this one as hygiene) |
| `ExerciseService:121` | `updatedAt` before `:122`'s save |
| **`PRService.swift:113`** | `oldSet.prStatus = .previous` on a `SetRepository`-owned set that `SetTableView` may be rendering — the sharpest of these |
| `StatsService:264-286`, `TemplateService:225-227` | multi-property mutations |
| `FatigueLearningService` (6 sites), `SettingsService` (6 sites) | |

**Neither captured crash is this shape**, so it is not Stage 1 work and inventing scope for it now
would delay the fix for the crashes that are actually happening. What matters is that §5 stops
claiming completeness. The mechanism that *systematically* catches this category is §12's removal of
`@unchecked Sendable` per model type — each removal turns these into compile errors.

---

## 6. Existing infrastructure to reuse

The snapshot pattern already exists in this codebase — Charts was hardened against exactly this bug:

- `ChartSetData` and `ChartExerciseData` (`Repster/Core/Services/ChartSetData.swift`) — `Sendable`
  value types with `init(from:)`.
- `SetRepositoryProtocol.fetchChartSets(from:to:)` — *"Used by Charts to avoid crossing live SwiftData
  models between actors."*
- `ExerciseRepositoryProtocol.fetchAllChartExercises()` (`:23`).
- `WorkoutRepositoryProtocol.fetchEarliestCompletedWorkoutDate()` (`:34`) — *"Used by Charts to avoid
  sending live Workout models across actors."*
- `WorkoutAggregateSummary.summarize` already has a **snapshot overload**
  (`WorkoutSetPerformanceFormatter.swift:479`) taking `[ChartSetData]` + `[UUID: ChartExerciseData]`.

Home, Calendar and the detail screens simply never adopted it.

**Gaps to fill:** no `Workout` snapshot type exists; `ChartSetData` lacks `completed` (needed by
`checkActiveWorkout`). `ChartExerciseData` needs nothing — `supportsUnilateralLogging` is derived from
`trackingType` (`Exercise.swift:124-126`).

---

## 7. Reproduction plan

The diagnosis should be confirmed before the fix, and the same harness then verifies the fix.

### 7.1 Option A — direct stress test (fastest confirmation)

> ⚠️ **The code below is the first draft and it does NOT reproduce the crash.** It is kept because
> *why* it fails is instructive (§7.5). Do not copy it: the reader must **re-fetch on every pass**, or
> everything materialises once and nothing ever faults again. Use the corrected shape in §7.5.
>
> It also lives in `RepsterTests/HealthKitEnergyEstimateTests.swift`, not a new file — a new file
> would need registering with the Xcode test target (§8.1).

Mirrors the crash A shape with no UI:

```swift
import XCTest
import SwiftData
@testable import Repster

final class SwiftDataCrossContextRaceTests: XCTestCase {

    /// Reproduces the 1.3/1.4 EXC_BAD_ACCESS: a live model fetched from a @ModelActor
    /// repository is property-faulted on the main actor while that repo saves.
    ///
    /// EXPECTED TO CRASH the test runner (SIGSEGV in SwiftData's fulfill path), not to
    /// fail an assertion. Do not leave enabled in CI.
    func testLiveModelReadRacesRepositorySave() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, WorkoutSet.self, ExerciseStats.self,
                 PerformanceRecord.self, BodyweightEntry.self, HealthProfile.self,
                 FatigueObservation.self, FatigueLearningSetAudit.self,
            configurations: configuration
        )
        let repo = WorkoutRepository(modelContainer: container)

        for _ in 0..<200 {
            try await repo.save(Workout(date: .now, status: .completed))
        }

        // Live models crossing the actor boundary — exactly what HomeViewModel receives.
        let live = try await repo.fetchAllWorkouts(limit: nil, offset: nil)
        let targetId = live[0].id

        await withTaskGroup(of: Void.self) { group in
            group.addTask {                    // writer — mimics mirrorToHealthKit
                for _ in 0..<500 {
                    if let w = try? await repo.fetch(byId: targetId) {
                        w.updatedAt = .now
                        try? await repo.save(w)
                    }
                }
            }
            group.addTask { @MainActor in       // reader — mimics loadRecentWorkouts
                for _ in 0..<5_000 {
                    _ = live.filter { $0.status == .completed }.count
                }
            }
        }
    }
}
```

**Success = a crash** whose stack contains `DefaultStore.fulfill` / `Dictionary.subscript.getter`,
matching the TestFlight traces. If it survives, the window is simply too narrow in-process — go to
Option B rather than concluding the diagnosis is wrong.

### 7.2 Option B — Thread Sanitizer (most credible, and verifies the fix)

TSan detects the *data race* without needing the segfault to land, so it doesn't depend on timing.

```bash
xcodebuild test -project Repster.xcodeproj -scheme Repster -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableThreadSanitizer YES -only-testing:RepsterTests/SwiftDataCrossContextRaceTests
```

Expect a race report naming the SwiftData/CoreData internals with our reader and writer threads.
Caveats: simulator only (TSan is unavailable on device), and CoreData internals can produce unrelated
noise that has to be read past.

After the fix, the same run should be clean — that is the fix's actual pass/fail signal.

### 7.3 Option C — widened-window manual reproduction (proves the user-facing flow)

Temporarily force the overlap that normally depends on luck:

- **Crash A:** add a debug-only `try? await Task.sleep(for: .milliseconds(300))` immediately before
  `workoutRepo.save(workout)` in `mirrorToHealthKit` (`WorkoutService.swift:137`), so the save lands
  squarely inside Home's reload. Then: finish a workout → near-deterministic crash.
- **Crash B:** open a workout, edit an exercise from the settings sheet, save. To widen it, drive
  repeated re-renders of `SetTableView` while the save runs.

This is the end-to-end proof that Stage 1 removes the crash the user actually hit. Both edits must be
reverted before shipping.

### 7.4 Option D — isolated mechanism harness

A throwaway SwiftPM package with a toy `@Model` + `@ModelActor` reproducing the pattern in ~30 lines,
proving the mechanism generally and independently of Repster. Useful only if A and B are both
inconclusive.

**Recommended order: A → B, then C once the fix is in.**

### 7.5 RESULT — reproduced 2026-08-11

Option A succeeded. Harness lives temporarily at the bottom of
`RepsterTests/HealthKitEnergyEstimateTests.swift` as `SwiftDataCrossContextRaceTests`
(**delete before shipping**), run against the iPhone 17 Pro simulator.

**First attempt passed in 0.44 s — and the reason mattered.** The reader fetched the array once and
then re-read `status` 5,000 times. A SwiftData property faults only on its **first** read; after that
the value is cached on the object, so only pass 1 could fault. Both real traces show
`_InitialBackingData` — a freshly fetched, *unmaterialised* object — which is what every Home reload
produces. Corrected harness: **re-fetch on every pass**, then fault immediately.

Second attempt (2 writer tasks × 2,000 saves vs. 2,000 re-fetch-and-filter passes on the main actor)
crashed the test runner immediately: `Restarting after unexpected exit, crash, or test timeout`,
0 tests completed.

*Practical gotcha if you rewrite this:* `XCTUnwrap` takes an autoclosure, so `await` cannot appear
inside it — `try XCTUnwrap(try await repo.fetch…)` fails with "'await' in an autoclosure that does not
support concurrency". Split it into two statements. Also note `xcodebuild` reports exit 65 for both a
compile failure and a crashed runner, so check for `error:` in the log before concluding you
reproduced anything.

Crash report `~/Library/Logs/DiagnosticReports/Repster-2026-08-11-211848.ips`:

| | TestFlight crash A | Reproduction |
|---|---|---|
| Exception | `EXC_BAD_ACCESS` / `SIGSEGV` | identical |
| Subtype | `KERN_INVALID_ADDRESS at 0x8000000000000010` | identical |
| Exception codes | `0x…0001, 0x8000000000000010` | identical |
| Faulting frame | `Workout.status.getter` @ `@__swiftmacro_7Repster7WorkoutC6status18_PersistedPropertyfMa_.swift:9` | identical, same macro file and line |
| Next frame | `_ArrayProtocol.filter(_:)` | identical |
| Thread | `com.apple.main-thread` | identical |

**Conclusion:** the mechanism in §3 is confirmed, not inferred. It triggers within a second under
load; normal-use rarity is purely about a save coinciding with a reload.

**Keep this harness until the fix is verified** — it is the cleanest before/after signal available
(crashes on current code, must survive after Stage 1). Then delete it.

**It is gated** (§13.6) so it cannot kill an ordinary full-suite run:

```swift
try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_RACE_REPRO"] == "1", …)
```

To fire it deliberately, pass the variable through to the test runner process — note the
`TEST_RUNNER_` prefix, which is how `xcodebuild` forwards environment variables to the runner:

```bash
xcodebuild test -project Repster.xcodeproj -scheme Repster -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RepsterTests/SwiftDataCrossContextRaceTests TEST_RUNNER_RUN_RACE_REPRO=1
```

**Two things must be removed before release:** this harness, and the debug `Task.sleep` if §7.3
Option C is used. Both are easy to leave behind precisely because they are meant to survive until the
fix is verified.

---

## 8. The fix — Stage 1 (approved scope)

**Existing signatures will change.** The earlier "additive plumbing only" constraint was self-imposed
and cannot survive §13.2a/§13.2c — `fetchRecentPRs`, `WorkoutDetail` and `ExerciseGroup` all have to
change shape. This is safe: a signature change is a *compile-time* break, so every affected call site
is surfaced by the compiler. It costs diff size and stub updates, not runtime risk.

### 8.1 Snapshot types
All of these go **into `Repster/Core/Services/ChartSetData.swift`**, beside their existing siblings —
no new files, so no Xcode target registration is needed.

- **New** `WorkoutSummaryData: Sendable`: `id`, `date`, `title`, `displayTitle`, `startTime`,
  `endTime`, `duration`, `status`, `createdAt`, via `init(from: Workout)`. `displayTitle` is computed
  inside the actor (it reads `title` + `startTime`).
- **New** `PerformanceRecordSummaryData: Sendable`: `exerciseId`, `value`, `reps`, `date`
  (§13.2a — without this `loadRecentPRs` has nothing to convert to).
- **Extend** `ChartSetData` with **seven** fields, not one: `completed` (for `checkActiveWorkout`),
  `orderInExercise` (`CalendarExerciseCard:14-16` and both builders' sorts), `orderInWorkout` (group
  ordering, `selectDate:208-209` / `loadDetail:210-211`), `notes` (the note dot, `:88`), and
  `rir` / `leftRIR` / `rightRIR` (see the RIR hazard below). Safe to extend — `init(from:)` is its only
  constructor, and the single test site (`WorkoutSetTests.swift:159`) uses it, so that test needs no
  change.

  > ⚠️ **The RIR fields are not optional polish — omitting them silently blanks a column.**
  > `WorkoutSetPerformanceFormatter`'s existing `ChartSetData` overload (`:37-55`) hardcodes
  > `rir: nil, leftRIR: nil, rightRIR: nil` because `ChartSetData` carries no RIR today. And
  > `readOnlyHistoryFields` (`:618-621`) includes `.rir` for `.weightReps` **and** `.custom` — the two
  > most common tracking types. So converting the detail cards to today's `ChartSetData` would render
  > an empty RIR column with no error, no crash and no failing test. This is the one change in Stage 1
  > that could quietly alter what users see, which is why §10's "no behaviour change" is now qualified
  > and §11 has an explicit item for it. **Add the fields *and* update that overload to pass them
  > through.**
- **Extend** `ChartExerciseStatsData` (already exists, `ChartSetData.swift:77`) with whatever the
  detail cards render — it currently carries only `exerciseId` and `lastPerformedDate`.
- **New** snapshot for `ExerciseGroup`/`WorkoutDetail` composition (§8.3).

### 8.2 Repositories + protocols
- `WorkoutRepository`: `fetchAllWorkoutSummaries(limit:offset:)`, `fetchWorkoutSummaries(for:)`,
  `fetchInProgressSummary()`, `fetchWorkoutSummary(byId:)` — all mapping inside the actor.
- `SetRepository`: `fetchChartSets(for workoutId:)`.
- `ExerciseRepository`: by-id snapshot fetch, following `fetchAllChartExercises()` naming.
- `PerformanceRecordRepository` + **`StatsService.fetchRecentPRs` changes return type** to
  `[PerformanceRecordSummaryData]`, mapping inside the actor.
- `ExerciseStatsRepository`: snapshot fetch for the detail cards.
- Matching changes on `WorkoutService` / `SetService` / `ExerciseService` / `StatsService` protocols.

**Formatter and PR-status work — Stage 1 does not compile without it.** Two APIs on the Stage 1 path
take live models and have no snapshot overload. §6 lists only `summarize`, which is why they were
missed:

- `WorkoutSetPerformanceFormatter.fieldDisplay(for:set:exercise:unitPreference:)` (`:109`) — takes live
  `WorkoutSet` + `Exercise?`. Called from `CalendarExerciseCard:107-112`. Needs a
  `ChartSetData`/`ChartExerciseData` overload.
- `CachedPRStatus.effectiveStatus(for:among:)` (`CachedPRStatus.swift:23`) — takes
  `WorkoutSet` + `[WorkoutSet]`. Called from `CalendarExerciseCard:121`. Needs a `ChartSetData`
  overload.
- Plus the existing `display(for: ChartSetData …)` overload (`:37-55`) must stop hardcoding the RIR
  fields to `nil` once `ChartSetData` carries them (§8.1).

**Implementation constraint — don't try to push the status filter into the predicate.**
`WorkoutRepository.fetchInProgress` (`:34-43`) documents that `#Predicate` cannot capture custom enum
values, which is why it fetches all rows and filters in Swift. The same applies to the new summary
fetches: the `status` comparison has to happen in Swift, **inside the actor**. That is fine for
correctness — inside the actor is exactly where we want the fault — but it means these fetches still
read every row, as they do today. Not a regression; just don't mistake it for one and "optimise" it
into a predicate that won't compile.

### 8.3 Convert the readers (the actual fix)
- `HomeViewModel` — `loadWeekData`, `buildWeekDays`, `checkActiveWorkout`, `loadRecentWorkouts`,
  `loadRecentPRs`; `exerciseCache` becomes `[UUID: ChartExerciseData]`; switch to the snapshot
  `summarize` overload; drop `workout: Workout` from `RecentWorkoutSummary`.
- `ContentView.loadCopyPreviousWorkouts`; drop `workout: Workout` from `CopyPreviousWorkout`.
- `CalendarViewModel` — `workoutsByDate`, `buildDots`, the `:242` sort, `exerciseCache` (`:44`), and
  **`selectDate` (`:165-234`)**, the largest single conversion here.
- **`ExerciseGroup` (`:9-13`) and `WorkoutDetail` (`:15-21`) both become snapshot types.** This is the
  part §8.3 originally understated: they carry a live `Exercise`, `[WorkoutSet]` and `ExerciseStats?`
  between them, parked in main-actor state for the session.
- `WorkoutDetailFromHomeView` — **`loadDetail` (`:185-235`)** plus the view-body reads.
- `CalendarWorkoutDetailView` — including **`workoutHeader` (`:92-96`)**, whose three
  `((Workout) -> Void)?` callbacks change type.
- **`CalendarView`** — `@State workoutToSaveAsTemplate`/`workoutToDelete` (`:14`, `:16`) and the
  callback wiring at `:300-308`. Forced by the `workoutHeader` signature change; not optional.
- **`CalendarExerciseCard`** — the entire body (§5.2), not just `displaySets`.
- **Decide what replaces `CalendarExerciseCard:84`'s `workoutSet.modelContext == nil` guard.** It is a
  live-model-only API, so it cannot survive the conversion. Recommended: delete it. It exists to
  swallow exactly the failure mode this whole change eliminates, and a snapshot cannot be
  "detached" — but call it out in review rather than dropping it silently, since it is load-bearing
  today.

Both dropped `workout:` fields are verified dead: no view or test reads them (the `.workout` hits in
those files belong to `WorkoutDetail`, a different struct).

### 8.4 Hygiene (not a fix)
Move the `healthKitWorkoutUUID` mutation into the repo actor
(`setHealthKitUUID(_:forWorkoutId:)`). Removes a third thread mutating a live model. Per §3.2 this
does **not** by itself fix crash A.

---

## 9. Stage 2 — the active-workout surface (crash B)

**Decided 2026-08-11:** snapshot the whole active-workout surface. Done as a **separate pass after
Stage 1**, but before release — nothing ships until both crashes are fixed.

**The `@MainActor ExerciseRepository` alternative is dropped**, not deferred. Per §13.5 that
repository is consumed by nine services (`TemplateService`, `FatigueLearningService`,
`LoadPrescriptionService`, `ExportService`, `StatsService`, `SetService`, `ExerciseService`,
`ImportService`, `PRService`), so it would drag `PRService`, `StatsService` and
`LoadPrescriptionService` — the last of which runs on every smart-suggestion refresh — onto the main
thread. Trading a crash for a hang is not an improvement.

Scope, wider than first estimated (§5.3):

- `ActiveWorkoutViewModel`: `workout` (`:107`), **`exercises: [Exercise]` (`:110`)**,
  `setsByExercise` (`:131`), `currentExercise` (~20 read sites), `currentSets` (`:257`, faults in a
  computed property read every render)
- `SetTableDataSource` protocol — **four live-model members**, not one: `exercises: [Exercise]`
  (`:62`), `currentExercise: Exercise?` (`:70`), `currentSets: [WorkoutSet]` (`:73`),
  `setsByExercise: [UUID: [WorkoutSet]]` (`:126`). Plus `SetTableView` and `SetRowWrapper`
  (`:367-370`, `:402-405` take live `WorkoutSet`/`Exercise?`/`[WorkoutSet]`)
- `WorkoutSummarySheet` (`:113-116`, `:756`) — reads live workout fields on the finish screen while
  `finishWorkout` saves
- `CreateEditExerciseViewModel` and `ExerciseService.updateExercise` (`:106`), which currently takes
  the same live instance the UI renders
- **`SetService` (`@MainActor`, `SetService.swift:13`)** and the unawaited-`Task` fan-out in
  `reindexOrderInExercise`/`reindexOrderInWorkout` that arms it (§5.3). This is the concurrent writer,
  so it is part of Stage 2 rather than a separate pass.

This is the riskiest file in the app — a mistake here costs a user's logged session, not a crash —
which is why it gets its own change and its own test pass.

---

## 10. Implications and risks of Stage 1

**Intended behaviour change: none — with one hazard that must be actively avoided.** Snapshots are
taken at the moment the fetch already happened, so the data and layout are unchanged.

The exception is the **RIR column on the workout-detail cards**. Because the existing `ChartSetData`
formatter overload hardcodes RIR to `nil` (§8.1), a conversion that doesn't add the RIR fields *and*
update that overload will silently render an empty column for `.weightReps` and `.custom` — no crash,
no error, no failing test. Treat "no behaviour change" as a claim to be verified (§11), not an
assumption. The same applies, less severely, to set-note dots and set/exercise ordering, which depend
on `notes`, `orderInExercise` and `orderInWorkout` reaching the snapshot.

**Primary regression risk — staleness.** A live model can silently reflect a later DB change; a frozen
struct cannot. These screens already reload explicitly (`refreshTrigger`, `lastLoadTime`, `.task`), so
this should be invisible. The path to check is **Edit Workout from the detail screen** — edit a title,
return, confirm it updated. If anything relied on implicit live-model refresh, it now needs an
explicit reload.

**Test churn.** Seven stubs conform to the protocols being changed and won't compile until updated:
`WorkoutServiceStub`, `SetServiceStub`, `ExerciseServiceStub`, **`StatsServiceStub`**
(`ActiveWorkoutViewModelSuggestionRefreshTests.swift:3842/3925/4008/4044`),
`ImportWorkoutRepositoryStub` (`:4512`), `ImportExerciseRepositoryStub` (`:4489`),
`InMemoryExerciseRepo` (`FatigueLearningServiceTests.swift:771`). Mechanical but real.
`StatsServiceStub` is needed because `fetchRecentPRs` changes return type (§8.2).

**Performance.** Slightly *less* main-thread work (no faulting during render), slightly more inside
the actors. `fetchAllWorkouts(limit: nil)` still fetches full history — unchanged, not worsened.
Copy cost is negligible at these row counts.

**What Stage 1 does not fix.**
- Crash B — editing an exercise mid-workout still crashes. *(Fixed since, by Stage 2 step 1 —
  `STAGE2_WRITE_PATH_DESIGN.md` §10.)*
- The 15 other `@unchecked Sendable` model types, and the unaudited screens in §5.4.

---

## 11. Verification checklist

Before shipping Stage 1:

Order matters (§13.6): run the harness-based before/after **first**, then delete the harness, then run
the full suite. Never tick "full suite green" from a run in which the repro was skipped.

- [x] Reproduction Option A crashes on the current code with a matching stack — **done, §7.5**
- [x] Same harness survives after the fix (primary pass/fail signal) — **done, §14.3.** Note the shape:
      the harness drives `fetchAllWorkouts`, a live-model repository method Stage 1 deliberately
      *keeps* for Stage 2 callers, so it still crashes and is now the **control**. The paired
      snapshot-path test — identical load through `fetchAllWorkoutSummaries` — passes
- [x] TSan (Option B) clean after the fix — **done, §14.5.** Snapshot path: clean, zero TSan output.
      Live-model control under the same instrumentation: dies inside SwiftData. Note the caveat there
      about *how* it dies — not the race report §7.2 predicted
- [ ] Option C manual repro crashes before, does not crash after
- [x] Harness and any debug `Task.sleep` deleted — no `Task.sleep` was ever added (Option C unused)
- [x] Full test suite green (after the seven stubs are updated) — **355 tests, 0 failures**
- [ ] Home: week strip, recent workouts, monthly stats, recent PRs, insights hook all render correctly
- [ ] Finish a workout → Home reloads with the new workout present, no crash. **Repeat ~10× rapidly**
      — §13.4: spacing the repetitions out is the one pattern that will *not* reproduce this, because
      `HomeView.swift:106` nils `lastLoadTime` to defeat the 2-second debounce, letting two
      `loadData()` passes interleave while the first pass's background saves are still landing
- [ ] Apple Health still receives the workout, and `healthKitWorkoutUUID` is persisted (no double-write)
- [ ] Copy Previous sheet lists workouts correctly
- [ ] Calendar dots correct across months; workout detail opens
- [ ] **Edit Workout from detail → title/notes update on return** (the staleness risk)
- [ ] Save as Template from detail still works — from **both** Home detail and Calendar detail (the
      Calendar path goes through the `workoutHeader` callbacks that change type, §8.3)
- [ ] Delete workout from detail still works and refreshes Home

**Silent-regression checks** — none of the above would catch these (§10):

These are now covered by **automated tests** rather than manual QA alone, in
`RepsterTests/WorkoutSetTests.swift` — the whole point being that a silent failure should become a
loud one. Each asserts live-model and snapshot rendering are *equal*, so the two overloads cannot
drift again. Manual passes still worth doing on device, but no longer the only guard.

- [x] **RIR column still populated** on workout-detail cards for `.weightReps` (and `.custom`, which
      shares `readOnlyHistoryFields`) — `testRIRFieldDisplayMatchesBetweenLiveModelAndSnapshot`,
      plus the per-side variant. Verified non-vacuous: before the §8.1/§8.2 fix the snapshot path
      returned `"—"` here
- [x] **Set-note dots** still shown on sets that have notes — `notes`/`hasNote` pinned by
      `testChartSetDataCarriesFieldsTheDetailCardsRender`
- [x] **Set ordering** (`orderInExercise`) and **exercise ordering** (`orderInWorkout`) reach the
      snapshot — same test
- [x] PR badges still correct on detail cards — `testEffectiveStatusMatchesBetweenLiveModelAndSnapshot`
      covers both the suppressed and shown cases through the new `ChartSetData` overload

---

## 12. Longer-term follow-up

Once the read paths are snapshotted, the durable guardrail is to **remove
`extension <Model>: @unchecked Sendable`** per model type. Each removal turns every remaining live
boundary crossing into a compile error instead of a latent crash, convertible incrementally. 17
models carry it today; `Workout` and `Exercise` are the two implicated so far.

---

## 13. Review addendum — 2026-08-11

Independent pass over §1–§12 against the source. **The diagnosis, the crash reading and the
ruled-out alternatives all hold; no error was found in the mechanism.** What needs correcting is
§5's claim of completeness and, downstream of it, §8's scope.

### 13.1 Confirmed accurate

Every line citation in §2, §3, §5, §6 and §8 was checked and lands on what it claims. Also verified:

- 17 `@Model` types exist and **all 17** carry `@unchecked Sendable` — §3 point 3 is exact.
- `RepositoryContainer` holds 11 repositories — §3 point 1's "the other eight" is right.
- `ChartSetData` has no `completed`, and `init(from:)` is its only constructor. Single test site,
  `WorkoutSetTests.swift:159`, and it calls `init(from:)` — so §8.1's "safe" is correct and that
  test needs **no** change.
- `summarize` live overload at `WorkoutSetPerformanceFormatter.swift:465`, snapshot overload at
  `:479` (full path: `Repster/Core/Formatting/`).
- `supportsUnilateralLogging` is derived from `trackingType` (`Exercise.swift:124-126`), so
  "`ChartExerciseData` needs nothing" holds for the Home path.
- All six stub line numbers in §10 are exact. *(Stale as written — §13.2a below adds a seventh,
  `StatsServiceStub:4044`. All **seven** are exact; §10 now lists all seven.)*
- `RecentWorkoutSummary.workout` and `CopyPreviousWorkout.workout` are genuinely dead.
- `Workout(date:status:)` in the §7.1 repro compiles against the real initializer.

**One fact worth adding to §3:** there are **no `@Relationship` declarations anywhere** in the
model layer. Every fault is a flat attribute fault and every snapshot is a flat copy — no to-many
traversal to design around. It is also why the partial schema in the §7.1 test container is fine.

### 13.2 Blocking scope gaps — these change the Stage 1 plan

**(a) `loadRecentPRs` faults live `PerformanceRecord` on the main actor. Not in the audit, and not
fixable under §8 as written.**

`StatsService.fetchRecentPRs` (`StatsService.swift:129`) returns `[PerformanceRecord]` — live models
out of `PerformanceRecordRepository`. `HomeViewModel` then faults them on main:

| Line | Read |
|---|---|
| `HomeViewModel.swift:306`, `:310` | `record.exerciseId` |
| `HomeViewModel.swift:312` | `record.value` |
| `HomeViewModel.swift:313` | `record.reps` |
| `HomeViewModel.swift:314` | `record.date` |

§5.1 attributes `:306-308` to the *Exercise* reads only. §8.1 defines no `PerformanceRecord`
snapshot; §8.2 extends neither `PerformanceRecordRepository` nor `StatsServiceProtocol`; but §8.3
lists `loadRecentPRs` as a reader to convert. **There is nothing to convert it to.**

Required additions:
- New `PerformanceRecordSummaryData: Sendable` (`exerciseId`, `value`, `reps`, `date`).
- `PerformanceRecordRepository` + `StatsService.fetchRecentPRs` return it, mapping inside the actor.
- **§10's stub list needs a seventh entry:** `StatsServiceStub`
  (`ActiveWorkoutViewModelSuggestionRefreshTests.swift:4044`).

**(b) `SetService` is `@MainActor` — an entire service of main-thread live-model reads *and
mutations*, on the highest-frequency path in the app.**

`SetService.swift:14`. Not mentioned in §5 or §5.4. On every logged set it:

- fetches a live `Exercise` from `ExerciseRepository` and faults it on main (`:44`, `:120`, via
  `syncDerivedPerformanceFields(for:)` at `:45`, `:121`)
- fetches a live `oldSet` from `SetRepository` (`:124`) and faults it (`:128`)
- **mutates** `set.effectiveWeight`, `.e1RM`, `.e1RMFormulaVersion`, `.prStatus`, `.updatedAt`
  (`:53-68`, `:136-151`, `:201-202`) on the main thread

…while both of those contexts save on their own executors. By frequency this is a larger exposure
than crash A's path. It is not Stage 1 scope, but §5 should stop claiming to list *every* main-actor
read until this is recorded, and Stage 2 has to account for it.

**(c) The workout-detail screens carry far more live state than §5.2 records.**

`ExerciseGroup` (`CalendarViewModel.swift:9-13`) holds a live `Exercise` + `[WorkoutSet]` +
`ExerciseStats?`. `WorkoutDetail` (`:15-21`) wraps that plus the live `Workout`. Both are parked in
main-actor state for the session: `CalendarViewModel.workoutDetails: [UUID: WorkoutDetail]` (`:34`)
and `WorkoutDetailFromHomeView.workoutDetails` (`@State`, `:17`).

§5.2 lists 4 view-body lines but omits both **builders**:

| Site | Reads on main actor |
|---|---|
| `WorkoutDetailFromHomeView.swift:185-235` (`loadDetail`) | `set.exerciseId` `:195`, `.orderInExercise` `:204`, `.orderInWorkout` `:210-211`, `.hasData` `:215`, live `summarize` `:216`, live `ExerciseStats` `:205` |
| `CalendarViewModel.swift:165-234` (`selectDate`) | `set.exerciseId` `:186`, `.orderInExercise` `:197`, `.orderInWorkout` `:208-209`, `.hasData` `:214`, live `summarize` `:215`, live `ExerciseStats` `:198` |
| `CalendarViewModel.swift:237-243` (`selectedDateWorkoutDetails`) | computed property read from a view body — faults `workout.id`, `.startTime`, `.createdAt` |
| `CalendarExerciseCard.swift:14` | `displaySets: [WorkoutSet]` computed **inside a view body** |

So §8.3's "`WorkoutDetailFromHomeView`, `CalendarWorkoutDetailView` — read snapshot fields" is a
large understatement: `ExerciseGroup` and `WorkoutDetail` both have to become snapshot types, which
pulls in a set-level snapshot (`ChartSetData` + `completed`, already planned) and a stats snapshot.
`selectDate` is not named anywhere in §8.3 and is the biggest single conversion in Calendar.

Useful: **`ChartExerciseStatsData` already exists** (`ChartSetData.swift:77`) — but it carries only
`exerciseId` and `lastPerformedDate`, so it needs extending for whatever the detail cards render.

### 13.3 Audit gaps — add to §5

- **`CalendarViewModel.exerciseCache: [UUID: Exercise]` (`:44`)** — identical to the HomeViewModel
  cache §5.1 flags as critical; missing from §5.2 and from §8.3's Calendar bullet.
- **§5.4's "not audited" list is itself incomplete.** Beyond Insights/Templates/Programs/Settings/
  Charts, these also hold live models in main-actor state and have not been swept:
  - `EditWorkoutViewModel:23/24/26` (live `Workout`, `[Exercise]`, `[UUID: [WorkoutSet]]`),
    computed `:508/:515` — **this is the exact flow §10 and §11 nominate as the staleness risk**
  - `ExerciseListViewModel:19/23/24` — including `allExerciseStats: [UUID: ExerciseStats]`
  - `ExerciseDetailViewModel:22/23`
  - `CalendarView:14/16` — `@State … : Workout?`
  - `ExercisePickerSheet:34`, `AssignMuscleGroupsView:12`, `TemplateListSheet:656`
  - `BodyweightLogViewModel:12/39` (`entriesForChart` computed in a body)
- **There is a 12th `ModelContext`.** `InsightsService` is a `@ModelActor` (`InsightsService.swift:140`)
  outside `RepositoryContainer`, saving at `:214`, `:228`, `:380`, driven from
  `HomeViewModel.loadData():132`. **Good news:** its API returns `Sendable` value types
  (`InsightItem`, `TrainingStatus`), so it leaks no live models and needs no conversion. But §3's
  repository framing and §5.1's writer list ("every set write, PR/stats rebuild and the
  fatigue-learning pass") should include the insights analysis save — it shipped in the same release
  as the HealthKit mirror and runs on the same Home load.

### 13.4 A second trigger for crash A, missing from §3.1

`HomeView.swift:106` sets `viewModel.lastLoadTime = nil` immediately before `loadData()`,
deliberately defeating the 2-second debounce at `HomeViewModel.swift:119-121`. `.task(id:)` cancels
the previous task, but an in-flight `await` into an actor runs to completion regardless — so two
`loadData()` passes can interleave across their many suspension points while the first pass's
background saves are still landing.

Consequence for §7.3 and §11: "repeat ~10×" should mean **rapid** finish/dismiss and trigger churn,
not spaced repetitions. Spacing them out is the one pattern that will *not* reproduce this.

### 13.5 Corrections to §9 (Stage 2)

- **Option B's blast radius is understated by six services.** `ExerciseRepository` is consumed by
  `TemplateService`, `FatigueLearningService`, `LoadPrescriptionService`, `ExportService`,
  `StatsService`, `SetService`, `ExerciseService`, `ImportService`, `PRService` — and
  **`ChartDataService` (`:33`)**, making **ten**, not nine. Not just Import/Export/FatigueLearning. Moving it to `@MainActor` also drags `PRService`, `StatsService`
  and `LoadPrescriptionService` (which runs on every smart-suggestion refresh) onto the main thread.
  That is strong enough to drop the option outright rather than leave it as a live alternative.
- **Option A under-scopes the active workout.** An `ExerciseSnapshot` alone leaves
  `ActiveWorkoutViewModel.workout: Workout?` (`:107`) and `setsByExercise: [UUID: [WorkoutSet]]`
  (`:131`) live, and `currentSets` (`:257`) faults `orderInExercise` inside a computed property read
  from `SetTableView.body:128` — the identical crash-B shape at the highest render frequency in the
  app. `WorkoutSummarySheet` also reads `viewModel.workout?.title/.notes/.perceivedEffort`
  (`:113-116`) and `.displayTitle` in a body (`:756`) — on the finish screen, concurrent with
  `finishWorkout`'s save. `SetTableDataSource:62` exposes `[Exercise]`, so the protocol changes too.

### 13.6 Notes on §7 and §4

- **The live harness from §7.5 blocks §11's "full test suite green" item.** §7.5 says keep it until
  the fix is verified; it currently sits in `RepsterTests/HealthKitEnergyEstimateTests.swift` and
  kills the runner ("0 tests completed"). So the full-suite check cannot run while it is present.
  Either gate it —
  ```swift
  try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_RACE_REPRO"] == "1")
  ```
  — or sequence §11 explicitly: harness-based before/after first, then delete the harness, then run
  the full suite. Do not tick "full test suite green" from a run that skipped the crash. The
  `-only-testing:` in §7.2 is correct and unaffected either way.
- **§4 never weighs the canonical Apple pattern:** re-fetching by `persistentModelID` into
  `container.mainContext`, or `@Query`. §3 point 4 observes there is no main-context path but the
  fix section never considers giving the UI one, so §3.2's "the only reliable fix" overstates.
  Snapshots are still likely the right call — they keep DB work off the main thread and remove the
  fault entirely rather than relocating it — but the reasoning should be written down rather than
  assumed, so the choice survives review.

### 13.7 Suggested worker order

1. Fix §8.1/§8.2 to include the `PerformanceRecord` snapshot + the 7th stub (13.2a) — otherwise
   Stage 1 does not compile as specified.
2. Re-scope §8.3's detail-screen bullet to cover `ExerciseGroup`/`WorkoutDetail`, `selectDate`,
   `loadDetail` and `CalendarViewModel.exerciseCache` (13.2c, 13.3).
3. Record `SetService`'s `@MainActor` exposure in §5 so it is not mistaken for already-safe (13.2b).
4. Then proceed with §7 → §8 → §11 as written, with the §11 repetition caveat from 13.4.

### 13.8 One correction forced by §7.5's own finding

§7.5 established that **a persisted property faults only on its first read** — after that the value
is cached on the object. That contradicts §5.1's characterisation of the exercise cache:

> `exerciseCache: [UUID: Exercise]` — holds live models for the ViewModel's lifetime; **every later
> hit re-faults**

A materialised object does not re-fault on a repeat read of the *same* property. The cache is still
unsafe, but for two different reasons, and the distinction changes how a worker prioritises:

1. **Reading a property that was never materialised faults then**, whenever "then" happens to be —
   including mid-render, long after the fetch. Different call sites read different properties off
   the same cached `Exercise`.
2. **`NSManagedObjectContext.reset()` turns every registered object back into a fault.** That call
   is on thread 11 of crash A (`§2.1`, frame 7), inside `save()`. So a long-lived cache of live
   models becomes re-faultable *precisely* when a background save runs — the exact overlap this
   whole document is about.

Net effect on priority: the **freshly-fetched, unmaterialised arrays are the sharpest hazard** (as
§7.5 proved — the first harness attempt passed until it re-fetched each pass), and the long-lived
caches are a slower-burning one that a `reset()` re-arms. §5.1's ranking is right; only its
mechanical explanation needs the fix above. Worth correcting in place, because a worker who trusts
"every later hit re-faults" will write a repro that passes and conclude the cache is fine.

---

## 14. Stage 1 implementation record — 2026-08-11

Implemented in §0's order. §8's plan held up; the deviations below are all naming or small scope
extensions, none of them changes to the strategy.

### 14.1 Deviations from the plan

**`WorkoutSummaryData` had to be renamed to `WorkoutSnapshot`.** The name is already taken:
`ActiveWorkoutViewModel.swift:19` defines an unrelated `WorkoutSummaryData` — the finish-screen recap
struct. Renaming *that* one would have meant editing the active-workout surface, which is Stage 2's
riskiest file, so the new type took the new name instead. `PerformanceRecordSummaryData` had no
collision and kept its planned name.

**`ExerciseGroup` / `WorkoutDetail` were converted in place**, in `CalendarViewModel.swift`, rather
than added as new types in `ChartSetData.swift`. §8.3 already required them to *become* snapshot
types; converting in place is the smaller diff, keeps their single definition, and still adds no new
files. They are now `Sendable` holding `ChartExerciseData` / `[ChartSetData]` /
`ChartExerciseStatsData?` / `WorkoutSnapshot`.

**`ChartExerciseStatsData` needed no new fields.** §8.1 says to extend it with "whatever the detail
cards render" — the answer is nothing. `CalendarExerciseCard` takes `stats` and never reads it
(verified by grep, not assumed). The property was kept, retyped, to avoid an unrelated API change.

**Four extra sites in `ContentView` were converted beyond §8.3's `loadCopyPreviousWorkouts` bullet.**
`performCopy` and `discardActiveAndCopy` fault live `WorkoutSet` and `Workout` properties on the main
actor — `setType`, `orderInWorkout`, `orderInExercise`, `weight`, `reps`, `startTime`, `date` — in
exactly the crash-A shape, and they are the *continuation* of the Copy Previous flow the audit does
cover. Fixing the list but not the tap would have left the feature half-converted. `refreshActiveWorkoutState`
and `copyWorkout` only nil-check, but the live model still crossed; both were one-word changes.

**`StatsService.fetchRecentPRs` had its internals converted, not just its return type.** Since its
signature was changing anyway, its `exerciseRepo.fetch(byId:)` and `performanceRecordRepo.fetchAll(for:recordType:)`
calls now use snapshot fetches too, removing three live-model crossings on a path already being
edited. (`healthProfileRepo.fetchOrCreate()` still returns a live model — that is §5.5 category work,
left alone.)

**A `CachedPRStatus.effectiveStatus` overload and both `fieldDisplay` overloads now share one private
body.** Duplicating the switch is precisely how the RIR bug got in; a shared implementation means the
live and snapshot paths cannot diverge without a compile error.

### 14.2 The `CalendarExerciseCard:84` guard

Deleted, as §8.3 recommended. `if workoutSet.modelContext == nil { EmptyView() }` existed to swallow
the failure mode this change eliminates, and a snapshot has no context to detach from. Flagging it
here rather than dropping it silently, since it was load-bearing before.

### 14.3 Verification results

| Check | Result |
|---|---|
| App target builds | clean |
| Test target builds | clean, after the **seven** predicted stubs (all at the predicted lines) |
| Live-model path under load (control) | **crashes** — `EXC_BAD_ACCESS` / `SIGSEGV`, `KERN_INVALID_ADDRESS at 0x8000000000000010`, `Workout.status.getter` → `_ArrayProtocol.filter(_:)`. Byte-identical to §7.5 and to TestFlight crash A |
| Snapshot path under identical load | **passes** (7.05 s) — 4,000 concurrent repo saves against 2,000 main-actor re-fetch-and-filter passes |
| Full suite | **355 tests, 0 failures** |

The control matters: it proves the harness is still a working detector and that the crash was removed
by the conversion, not by the load accidentally getting gentler.

### 14.4 Not done

- **Option C manual repro and the on-device §11 items** — finish-workout ×10 rapid, Apple Health
  double-write, Calendar dots, Edit Workout staleness, Save as Template from both detail screens.
  These need a human on a device.
- **Stage 2 (§9)** — crash B is still live: editing an exercise mid-workout can still crash.

### 14.5 TSan (Option B) — run 2026-08-12

Deferred from the first pass for lack of disk space; run once ~5 GB was freed. Both directions, since
a clean TSan run proves nothing unless the instrumentation demonstrably catches the bad path.

| Run | Result |
|---|---|
| Snapshot path (`fetchAllWorkoutSummaries` + `setHealthKitUUID`) | **clean** — passed in 1.53 s, zero TSan output of any kind |
| Live-model control (`fetchAllWorkouts` + off-actor mutate/save) | **dies inside SwiftData**: `SUMMARY: ThreadSanitizer: SEGV … SwiftData.framework … __swift_allocate_value_buffer`, `Executed 0 tests` |

**Caveat, stated precisely: TSan did not emit a data-race report.** §7.2 predicted one. What actually
happens is that the memory fault lands before TSan can finish attributing a race — the log contains
zero `WARNING: ThreadSanitizer: data race` lines and ends with `ThreadSanitizer can not provide
additional info`. So the honest reading is *"TSan-instrumented, the live-model path segfaults inside
SwiftData and the snapshot path runs clean"*, not *"TSan proved a data race."*

Worth recording anyway: the control's register dump carries **`x[20] = 0x8000000000000000`** — the
same poisoned register as both TestFlight crashes in §2.3's fingerprint table. Under a completely
different toolchain configuration, the same corruption reproduces, and the snapshot path does not.

To repeat either run, re-add the throwaway test to a file already in the test target and:

```bash
xcodebuild test -project Repster.xcodeproj -scheme Repster -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableThreadSanitizer YES
```
