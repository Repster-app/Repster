# Bugs 2 and 3: full fix scoping

**Written:** 2026-09-11. **Implementation update:** 2026-09-12 — Phases 0, 1 and 4 are built and verified; Phases 2, 3, 5 and 6 remain.
**Source investigation:** [TEST_SUITE_FAILURES_INVESTIGATION.md](TEST_SUITE_FAILURES_INVESTIGATION.md) (§4 bug 2, §10.2 bug 3).
**Builds on:** [SWIFTDATA_CRASH_WORK_RECORD.md](SWIFTDATA_CRASH_WORK_RECORD.md) and
[STAGE2_WRITE_PATH_DESIGN.md](STAGE2_WRITE_PATH_DESIGN.md), the August work this finishes.

## Plain summary (read this first)

- **Bugs 2 and 3 come from one problem.** A live database record leaves the part of the app that
  owns it and gets used somewhere else, on another thread.
  - **Bug 2** (iOS 17): the other code *changes* the record.
  - **Bug 3** (iOS 18): the other code *reads* the record while the owner reloads it.
- **The full fix is one rule, finished everywhere:** records never leave their owner.
  - Code that wants to **read** gets a frozen copy.
  - Code that wants to **change** something sends the owner an instruction ("set target RIR to 2"),
    and the owner makes the change itself.
  - August applied this rule to Home, Calendar, exercise edits and set saving. This finishes it.
- **Bug 2 has crashed a real phone.** Version 1.3, iOS 17.5.1, 14 August 2026, on the last
  onboarding screen (§1.3). That makes Phase 1 the priority.
- **Phase 0 is done (2026-09-12).** `RepsterTests/LiveModelRaceReproTests.swift` crashes both
  bugs on demand, and the paired discriminators stay clean (investigation §11). It changed two
  things:
  - Bug 3's trigger is a repository **saving** a record, or first re-loading one it just
    created, while other code holds it. That's the workout screen's normal state.
  - iOS 26 isn't immune to the pattern. The same harness crashes there with August's older
    signature, so bug 3's exposure may be 139 users, not 10 (§8).
- **Built now:**
  - **Phase 1:** all 20 `HealthProfile` write sites run inside `HealthProfileRepository`.
  - **Phase 4:** the suggestion engine reads set, exercise, workout and profile snapshots;
    `ActiveWorkoutViewModel.workout` is also a snapshot.
- **Still needed:** Phase 5 converts the workout screens' held `[WorkoutSet]` values. Until then,
  the minimal held-live-set positive control still represents a real remaining risk.
- **Recommended next order:** Phase 5 → Phases 2–3 → Phase 6. See the short operator checklist in
  [SWIFTDATA_LIVE_MODEL_TEST_CHECKLIST.md](SWIFTDATA_LIVE_MODEL_TEST_CHECKLIST.md).

---

## 1. The rule, and why both bugs break it

### 1.1 How the app is built today

- **Repositories** own the data. There are 10 `@ModelActor` types in `Repster/Core/Repositories/`.
  Each has its own `ModelContext`, and each is built on the main thread in `RepsterApp.init`.
- **Services** are plain `actor`s (`PRService`, `StatsService`, `SettingsService`, …). Several still
  fetch live `@Model` objects; Phase 1 closed profile writes and Phase 4 closed suggestion reads.
- **ViewModels** are `@MainActor`. `ActiveWorkoutViewModel.workout` is now a value snapshot, but
  both workout screens still hold live sets until Phase 5.

### 1.2 What goes wrong

| | Bug 2 | Bug 3 |
|---|---|---|
| What the outside code does | Changes a live record, then hands it back to `repo.save()` | Reads a live record |
| What happens at the same time | SwiftData's main-thread observer reads the record's bookkeeping, unlocked | The owning repository saves the record, or first re-fetches it after creating it, and frees its old contents |
| Runtime | iOS 17 only (SwiftData ships inside iOS; Apple reworked it in 18) | The swap is iOS 18 only. The same read-while-saving pattern crashes the harness on 26.3.1 with August's older signature (investigation §11.3) |
| Fault | `0x8000000000000010` | `0x10` |
| Proven by | A 20-line probe (investigation §9.1) and the real onboarding path, 5/5 (§11.1) | Controls that crash on demand, 10/10 on iOS 18.6 (investigation §11.2) |

Both disappear if a live record never crosses to another thread. That is the rule.

### 1.3 The device crash (new since the investigation doc)

Found in Xcode Organizer's local cache
(`~/Library/Developer/Xcode/Products/com.magnusespensen.Repster/Crashes/`, crash point
`CQYx6eyrFOo0g1u1INyrWf`):

- **What and when:** 1.3 (3), iPhone13,2, **iOS 17.5.1**, 2026-08-14 16:04:33, 23 seconds after
  launch.
- **Main thread:** `SwiftData` → `__CFRunLoopDoObservers`. This is bug 2's exact frame shape.
- **Writer thread:** `HealthProfile.prescriptionDefaultTargetRIR.setter` ←
  `SettingsService.updatePrescriptionDefaultTargetRIR` (`SettingsService.swift:132`) ←
  `OnboardingViewModel.finish()` (`:67` in 1.3, `:141` today). It was blocked in
  `performBlockAndWait`.
- **Fixed by Phase 1.** `finish()` still requests three settings changes, but each mutation, time
  stamp and save now executes inside `HealthProfileRepository`, the context owner.

What this corrects in the investigation doc:

1. It says bug 2 "has not been observed". It has.
2. It says "every observed crash writer is in `PRService` or `StatsService`". The only real-user
   crash is in `SettingsService`. Options B and C in its §4.6 would not have prevented it.
3. It counts `SettingsService` at 16 sites. It is **17** (saves at `:53` through `:170`), so bug 2
   is **47** sites, not 46.
4. It says strict concurrency can't catch this because "`@Model` types already conform to
   `Sendable`". They conform only because 12 models carry an explicit `@unchecked Sendable`.
   August verified the macro does not add it (work record §4). Removing those annotations is the
   compile-time guard (§4.5).

The other crashes in the Organizer cache on iOS 26 are the August getter race, which is already
fixed. The two on iOS 18.6.2 are the 1.4 (17) `RepsterApp.init` fatalError. Neither is bug 2 or 3.

---

## 2. What already exists (reuse, don't rebuild)

**Copy (snapshot) types:**
- `ChartSetData` mirrors every stored field of `WorkoutSet`.
- `ChartExerciseData` mirrors all 20 fields of `Exercise`, with a reflection drift guard.
- `WorkoutSnapshot` includes `excludedExerciseIdsForProgressionHistory` and
  `excludesFromProgressionHistory(exerciseId:)`, exactly what bug 3's crash A read.
- `HealthProfileSnapshot` mirrors profile settings for actor-safe reads.
- `SuggestionSettingsSnapshot`.

**Snapshot fetches already on the protocols:**
- `SetRepository.fetchChartSets(exerciseId:from:to:)` and `fetchChartSets(for:limit:)`
- `ExerciseRepository.fetchChartExercise(byId:)`
- `WorkoutRepository.fetchWorkoutSummary(byId:)`
- `WorkoutRepository.fetchWorkoutSummaries(byIds:)`
- `ExerciseStatsRepository.fetchChartExerciseStats(for:)`

**"Owner makes the change" methods from August:**
- `SetRepository`: `applyPRStatus(setId:status:)` (on the protocol), `applyCompletion`,
  `applyUncomplete`, `applyNote`, `applySetType`, `applyTargetRepOverride`, `applyRestDuration`,
  `applySupersetGroup`, `applyOrdering`, `persist`
- `ExerciseRepository.applyEdit(id:fields:)`
- `WorkoutRepository.setHealthKitUUID`
- `TemplateRepository.updateTemplateFolder`

**`applyAffectedSets` is already a single implementation** in
`SetTableDataSource.swift:84` (August's Q4 recommendation was taken).

**Test infrastructure:**
- `ScreenDataGoldenMasterTests`
- the snapshot/model parity guard
- `AffectedSetsPreconditionTests`, which guards PR-badge identity
- the opt-in race tests in `CrossContextRaceTests`

---

## 3. Bug 2 scope: 47 write sites

Every site does fetch → change → `repo.save(model)` from a plain actor. Inserts of brand-new
records are excluded (nothing to race): `PRService:86/515`, `StatsService:113/270` (new stats),
`WorkoutService:55`, `TemplateService:202/292/311/498` and `BodyweightService:32`.

| Service | Sites (save line) | Model | Replacement | Difficulty |
|---|---|---|---|---|
| `SettingsService` | **17**: `:53 60 67 75 83 90 97 106 113 120 127 134 142 149 156 163 170` | HealthProfile | New `HealthProfileRepository.update(_ body:)` (fetch-or-create, apply, stamp `updatedAt`, save, all inside the owner). Each setter becomes one line | Mechanical |
| `FatigueLearningService` | **3** profile: `:420` (fields set `:723-732`), `:490`, `:521` | HealthProfile | Same `update(_ body:)` | Mechanical |
| `FatigueLearningService` | **5** exercise: `:453 482 510 653 752` | Exercise | New `ExerciseRepository.applyFatigueLearning(id:_:)`. These four fields (`fatigueRate`, `fatigueRateSourceRawValue`, `fatigueLearningSessionCount`, `fatigueLearningCumulativeError`) are **not** in `ExerciseEditableFields`, so `applyEdit` can't be reused | Mechanical; `:752` computes from the old values, so compute first, then apply |
| `PRService` | **7** `prStatus`: `:114 349 471 540 558 628 702` | WorkoutSet | **Existing** `SetRepository.applyPRStatus(setId:status:)`. `:471` clears every set of an exercise in a loop, so add a batch `clearPRStatuses(exerciseId:)` | Hot path |
| `PRService` | **6** record: `:123 253 290 312 337 690` | PerformanceRecord | New `PerformanceRecordRepository.applyUpdate(recordId:_:)` taking a value type with the fields `PRService` changes | Hot path; `evaluateAfterEdit` has four branches |
| `StatsService` | **3** blocks: `handleSave` (`:259-311`), `handleEdit` (`:322-378`), `handleDelete` (`:388-419`) | ExerciseStats | New `ExerciseStatsRepository.applyDelta(exerciseId:_:)`, applied **inside** the owner. See the note below the table | Hardest: `recomputeMaxWeight` runs mid-update |
| `WorkoutService` | **3**: `:91` finish, `:189` metadata, `:212` progression exclusions | Workout | New named methods on `WorkoutRepository` (precedent: `setHealthKitUUID`) | Mechanical |
| `TemplateService` | **2**: `:217` edit, `:319` `lastUsedAt` | WorkoutTemplate | New `TemplateRepository` methods (precedent: `updateTemplateFolder`) | Mechanical |
| `BodyweightService` | **1**: `:38` `updateEntry` takes a live model *from its caller* | BodyweightEntry | Take `id` + values; the caller (`BodyweightLogViewModel`) passes values | Mechanical, plus one caller |

**Why deltas, not computed totals, for stats.** If the service computes new totals outside and
the repository writes them as absolutes, two overlapping set saves can overwrite each other: a
lost update. This is possible today through actor re-entrancy. Increments applied inside the
owner can't lose each other. `maxWeight` is the exception: compute it first, then pass it as an
absolute value in the same call.

**The identity dependency (keep it until Phase 5).** The workout screen still holds live
`WorkoutSet`s. `applyAffectedSets` relies on `PRService`'s badge change showing up on *that same
instance*. `applyPRStatus` runs inside `SetRepository`'s own context, so the instance stays the
same object and this keeps working. `AffectedSetsPreconditionTests` must stay green on every
runtime. Phase 5 removes the dependency.

**Onboarding.** Also consider one `applyOnboardingPreferences(unit:reps:rir:)`, so `finish()`
makes one write instead of three. It's optional; the per-setter fix is enough on its own.

**Guard (end of Phase 3).** Once all 47 sites are converted, `save(_:)` only ever receives new
objects:
- Rename it to `insert(_:)` on each repository.
- Add a DEBUG `assert(model.modelContext == nil)`. A fetched model always has a context, so any
  future fetch-change-save trips the assertion in tests.
- Check `SetService.swift:144` first (a `@MainActor` `setRepo.save`).
- `delete(_ model:)` calls cross too. They're harmless for bug 2 but count against the Phase 6
  guard; convert them to `delete(id:)` there.

---

## 4. Bug 3 scope

Bug 3 needs a live record read outside its owner *at the moment* the owner re-fetches that row.
The fix is to read copies. Tiers are in risk order.

### 4.1 Tier A: the suggestion engine (both observed crashes) — **done 2026-09-12**

**Crash B's reader:** `LoadPrescriptionService` (a plain actor) fetches and reads live records:

| Line | Today | Change to |
|---|---|---|
| `:225`, `:250` | `setRepo.fetchSets(exerciseId:from:to:)` → `[WorkoutSet]` | `fetchChartSets(exerciseId:from:to:)` (**exists**) |
| `:378` | `workoutRepo.fetch(byIds:)` → `[Workout]` | New `fetchWorkoutSummaries(byIds:)` → `[WorkoutSnapshot]`. The snapshot already has the exclusion fields |
| `:56`, `:71` | `healthProfileRepo.fetchOrCreate()` | A profile snapshot. New `HealthProfileSnapshot`, also needed in Tier C |
| `:77` | `exerciseRepo.fetch(byId:)` | `fetchChartExercise(byId:)` (**exists**) |

Also:
- `isEligibleForCapacity`, `peakAcrossRecentWorkouts` and `capacityE1RM(for:)` take `ChartSetData`.
- `performanceRIR` exists only on `WorkoutSet` (`WorkoutSet.swift:143`). Give `ChartSetData` the
  same property through one shared implementation, the August pattern for `statsReps`.
- `FatigueLearningService.appliedFatigueRateInfo(for:profile:)` needs snapshot inputs.
- `WorkoutService.excludedWorkoutIdsForProgressionHistory` (`:228-240`), which is the History
  tab's re-fetch, moves to the same `fetchWorkoutSummaries(byIds:)`.

**Crash A's reader:** `ActiveWorkoutViewModel.workout` and `SuggestionCoordinator.prepare` now
take `WorkoutSnapshot`. The active flow clears the snapshot after finish/delete; it has no
in-place metadata or exclusion edit, so no mid-screen re-fetch is needed today.

**Left over after Tier A:** `prepare(sets:)` still receives the live `currentSets`. That closes in
Tier B.

### 4.2 Tier B: the workout screens (August "Stage 2 steps 5 and 6")

August already designed this (`STAGE2_WRITE_PATH_DESIGN.md` §15). It needs no optimistic-UI
layer and no `updatedAt` plumbing. The one delicate function is `applyAffectedSets`.

- **`ActiveWorkoutViewModel.setsByExercise`** (`:159`, 51 uses) becomes
  `[UUID: [ChartSetData]]`. Its only direct model writes are `:491-492` (after `save` returns),
  which become "splice in the returned snapshot".
- **`SetTableDataSource`** (18 `WorkoutSet` references) moves to `ChartSetData`.
  - `applyAffectedSets` (`:84`) needs a `with(prStatus:)` copy helper.
  - Keep the **outer-optional** unwrap of `CachedPRStatus??`: a present-but-nil entry clears a
    badge. Don't flatten it with `??`.
  - Keep "completed sets get demotions, never promotions".
- **Views:** `SetTableView` (13), `SetRowView` (4), `ExerciseInfoProvider` (7),
  `WeightSuggestionData` (6).
- **`SetService`** (`@MainActor`): `save`/`edit`/`uncomplete`/`delete` take ids and values instead
  of live `WorkoutSet`s (August Q1).
- **`EditWorkoutViewModel` must convert at the same time,** because it shares
  `SetTableDataSource`.
  - It holds live `workout` (`:23`) and `setsByExercise` (`:26`, 34 uses).
  - It is **heavier** than the active screen: it writes input straight into live sets on main:
    - `:540-554`: weight, reps, RIR, sides, duration and distance
    - `:131`, `:201`: completed
    - `:655`: notes
    - `:148-149 185 312-313 523 575-576 666-667`: `effectiveWeight` and `prStatus`
  - Each of these becomes a repository `apply…` call, as `ActiveWorkoutViewModel` already does.
- **Tests:** 154 references to `setsByExercise` / `currentSets` across 11 test files.

### 4.3 Tier C: the long tail

- **`WorkoutSummarySheet`** is now covered by `ActiveWorkoutViewModel.workout: WorkoutSnapshot`.
- **Live `HealthProfile`** is still handed to feature files outside the completed suggestion path:
  `EditWorkoutViewModel`, `ExerciseInfoProvider`, `SettingsViewModel`,
  `BodyweightLogViewModel`, `CreateEditExerciseViewModel`, `ExerciseSettingsSheet`. They should
  get `HealthProfileSnapshot`.
- **August's unaudited screens:** `ExerciseDetailViewModel`, `ExerciseListViewModel`,
  `BodyweightLogViewModel`, `AssignMuscleGroupsView`, `TemplateListSheet`, `ExercisePickerSheet`.
- **Reads inside services.** A grep finds about 145 live-record fetches in plain-actor services:

  | Service | Fetches |
  |---|---|
  | `PRService` | 24 |
  | `FatigueLearningService` | 23 |
  | `SettingsService` | 19 |
  | `StatsService` | 15 |
  | `TemplateService` | 15 |
  | `WorkoutService` | 10 |
  | `BodyweightService` | 6 |
  | `LoadPrescriptionService` | 6 |
  | `ChartDataService` | 4 |
  | `ImportService` | 4 |
  | `ExerciseService` | 4 |
  | `ProgramCatalogService` | 1 |

  `SetService` (14) is main-actor. These are **grep candidates, not an audit**. Many disappear in
  Phases 1–4, because moving a write into the owner usually moves the read that preceded it too.

### 4.4 How sure are we that Tier C matters?

More sure than when this was first written. The harness (investigation §11) showed the trigger is
a repository saving a record, or first re-fetching one it just created, while other code holds
it. Any Tier C reader that holds a live record while its repository saves it is exposed: on
iOS 18 through the swap, on iOS 26 through August's older failure. Tier C paths save less often
than the workout screen, so their risk is lower, not absent. (The earlier note that this class
needs an on-disk store was wrong: every control is in-memory.)

### 4.5 The compile-time guard for both bugs

Finish August's §12: remove `@unchecked Sendable` from the 12 models that still carry it:
BodyweightEntry, Workout, WorkoutSet, FatigueObservation, TemplateExercise, WorkoutTemplate,
Exercise, PerformanceRecord, ExerciseStats, Program, TemplateSet, HealthProfile.

- **What it does:** under `SWIFT_VERSION = 5.0` each remaining crossing becomes a **warning**
  (errors only in Swift 6 mode).
- **Policy (August's):** remove a model's annotation only once its crossings reach zero, so
  every removal is a guarantee and the build stays warning-clean.
- **August's crossing counts (re-measure; they predate today's code):**
  - FatigueObservation, TemplateSet, TemplateExercise: 3 each
  - HealthProfile, Program, WorkoutTemplate: 4 each
  - ExerciseStats, PerformanceRecord: 6 each
  - BodyweightEntry: 9
  - Exercise: 18
- `Workout` and `WorkoutSet` hit zero with Tier B.

---

## 5. Phases

Each phase ships on its own and leaves the app better than before.

| Phase | What | Fixes | Rough size |
|---|---|---|---|
| **0. Harnesses** | Paired controls that crash *before* the fix (§6). **Done 2026-09-12:** `RepsterTests/LiveModelRaceReproTests.swift` | Makes every later "fixed" claim provable | Done |
| **1. HealthProfile writes** | 17 `SettingsService` + 3 `FatigueLearningService` sites → `HealthProfileRepository.update`. **Done 2026-09-12** | **The only real-user crash** (onboarding on iOS 17) | Done |
| **2. PR + stats writes** | 13 `PRService` + 3 `StatsService` blocks | Every bug-2 test crash; the set-save path | 1–2 sessions |
| **3. The rest of bug 2** | 12 sites (Fatigue exercise 5, Workout 3, Template 2, Bodyweight 1, plus the `:471` batch), then `save` → `insert` + assertion | **Bug 2 closed**, with a guard | ½–1 session |
| **4. Bug 3, Tier A** | Suggestion engine on snapshots; `ActiveWorkoutViewModel.workout` → `WorkoutSnapshot`. **Done 2026-09-12** | **Both observed bug-3 readers** | Done |
| **5. Bug 3, Tier B** | Both workout screens, `SetTableDataSource`, `SetService` signatures | **Bug 3 on the workout screens**; removes the badge identity dependency | 2–3 sessions + device pass |
| **6. Tier C + guard** | Summary sheet, profile snapshot, unaudited screens, service reads, `@unchecked Sendable` removal | The rule everywhere; the compiler enforces it | 2+ sessions, can be spread out |

Sizes are estimates. For scale: August's comparable Stage 1 + 2 touched 52 files
(+2,897 / −492).

**Why this order:**
- Phase 1 first because it's the only crash a user has actually hit, and it's the smallest.
- Phase 2 before 3 because it's the hot path and every test crash.
- Phase 4 before 5 because it closes both observed bug-3 readers without touching the set table.
- Phase 5 is the riskiest change in the program: the highest-traffic screen, and August showed
  the suite is weak evidence there.

**Alternative for Phase 1 if you want a hotfix instead:** change `actor SettingsService` to
`@MainActor final class`. That's one line. On iOS 17 the repositories run on main (investigation
§9.1 P0), so a main-thread writer can't race them. It's untested and needs one probe on 17.5.
`resetAllAppData` would then run on main. It doesn't fit the full fix's rule, so treat it only
as a stopgap.

---

## 6. Verification

The August rule applies: **a green suite is close to no evidence on these paths.** Every fix
needs a control that still detects the bug.

| Phase | Control (must crash before the fix) | Pass condition |
|---|---|---|
| 0 | Bug 2: the real `OnboardingViewModel.finish()` with main-built repositories, iOS 17.5, plus two discriminators. **Built**, marker-gated like `CrossContextRaceTests` | Crashes on 17.5 today, 5/5; clean on 18.6 |
| 0 | Bug 3: a live record held by other code while its repository saves it (in-memory, iOS 18.6). **Built** | Crashes on 18.6 today, 10/10 |
| 1 | Real onboarding regression, 2,000 rounds | **Clean on iOS 17.5 (2026-09-12)** |
| 2–3 | `AffectedSetsPreconditionTests` (crashes every run on 17.5 today); `SetServiceTests` with repositories built on main (crashes today, investigation §9.3) | Clean ×20 on 17.5; badge identity measurements unchanged |
| 4 | Real suggestion-engine regression plus set/workout snapshot stress | **Clean on iOS 18.6 (2026-09-12)** |
| 5 | Held-live-set control switched to the converted workout-screen path | Must become clean on 18.6 and 26.3 |
| All | Full suite on **17.5, 18.6 and 26**, one `xcodebuild` at a time, totals from `.xcresult`; golden masters unchanged; mutation checks on the changed surface (August §16) | — |
| 5 | Device pass: log sets, PR badges appear and demote, edit a finished workout, finish a workout, suggestions refresh on exercise switch | — |

**Why the harness, not `WorkoutJourneyTests`.** Re-running the journey tests on 18.6 crashes
about once per 360 runs, so 30 clean iterations would still happen about 5% of the time with the
bug present. The bug-3 controls crash every run on 18.6.

**Destinations:**
- Add iOS 17.5 (iPhone 15 Pro) and iOS 18.6 (iPhone 16 Pro) as standing test destinations.
- Every run record names the device and OS.
- Remember: `ReplayMaskCoverageTests.testEveryTextInputIsClassified` fails in any worktree under
  `/private/tmp`.

---

## 7. Risks and traps

1. **Badge identity (Phases 2–4).** `PRService` badge writes must go through `SetRepository`, so
   the screen's live instance keeps seeing them until Phase 5. Don't give `PRService` its own
   context.
2. **`CachedPRStatus??` in `applyAffectedSets`.** Unwrap the outer optional only. Flattening it
   silently kills demotions to "no badge". Write the test before converting (August Q4).
3. **Stats lost updates.** Apply deltas inside the owner. Don't write absolute totals computed
   outside it (§3).
4. **Don't "fix" tests by removing `@MainActor` or building test repositories off main.** That
   hides the race while the app keeps the crashing construction.
5. **Re-entrancy.** `@MainActor` and actors are re-entrant. Anything that captures an index or
   holds state across an `await` must re-resolve it afterwards. `refreshCurrentExerciseSnapshot`
   is the pattern to copy.
6. **Snapshot staleness.** A copy doesn't update itself. Every code path that changes a workout
   or set must hand back a fresh snapshot, or the screen shows old values. The golden masters
   catch some of this; the device pass catches the rest.
7. **The harness is harsher than the app.** It saves thousands of times a second. A control that
   stops crashing after a fix is strong evidence. A control that crashes on iOS 26 is a hazard,
   not proof that users crash on 26.

---

## 8. Implementation record and next decision

**2026-09-12 verification:** test target builds; focused active-workout, suggestion and fatigue
suites pass on iOS 18.6; the 2,000-round real onboarding regression passes on iOS 17.5; the real
suggestion-engine and set/workout snapshot stress regressions pass on iOS 18.6.

**Next decision:** schedule Phase 5 separately. It is still recommended because the active and
edit screens retain live `WorkoutSet` objects, but it is intentionally not bundled into this
lower-risk change. After its device pass, complete Phases 2–3 and then the long-tail/compile guard.

---

## Appendix: site list for bug 2 (save-call lines, 2026-09-11)

```
SettingsService        :53 60 67 75 83 90 97 106 113 120 127 134 142 149 156 163 170   (17)
FatigueLearningService :420 490 521 (HealthProfile)   :453 482 510 653 752 (Exercise)  (8)
PRService              :114 349 471 540 558 628 702 (WorkoutSet.prStatus)
                       :123 253 290 312 337 690 (PerformanceRecord)                      (13)
StatsService           handleSave :259-311, handleEdit :322-378, handleDelete :388-419   (3)
WorkoutService         :91 189 212                                                        (3)
TemplateService        :217 319                                                           (2)
BodyweightService      :38                                                                (1)
                                                                                   total  47
Excluded (new-record inserts): PRService :86 515, StatsService :113 270 (new stats),
WorkoutService :55, TemplateService :202 292 311 498, BodyweightService :32.
```
