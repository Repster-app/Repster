# Bugs 2 and 3: full fix scoping

**Written:** 2026-09-11. **Implementation update:** 2026-09-12 — Phases 0, 1 and 4, plus the
Settings slice of Tier C, are built and verified; Phases 2, 3, 5 and the remainder of 6 remain.
**Cleanup verification:** 2026-09-13 — Settings error recovery, the source ratchet and the
documentation corrections below are complete and verified.
**Source investigation:** [TEST_SUITE_FAILURES_INVESTIGATION.md](TEST_SUITE_FAILURES_INVESTIGATION.md) (§4 bug 2, §10.2 bug 3).
**Builds on:** [SWIFTDATA_CRASH_WORK_RECORD.md](SWIFTDATA_CRASH_WORK_RECORD.md) and
[STAGE2_WRITE_PATH_DESIGN.md](STAGE2_WRITE_PATH_DESIGN.md), the August work this finishes.

## Plain summary (read this first)

- **Bugs 2 and 3 come from one problem.** A live database record leaves the part of the app that
  owns it and gets used somewhere else, on another thread.
  - **Bug 2** (iOS 17): the other code *changes* the record.
  - **Bug 3** (iOS 18): the other code *reads* the record while its owner saves it, or while the
    owner first re-fetches a new record it just saved.
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
  - Bug 3's trigger is a repository **saving** a record, or first re-fetching one it just
    created, while other code holds it. That's the workout screen's normal state.
  - iOS 26 isn't immune to the pattern. The same harness crashes there with August's older
    signature, so bug 3's exposure may be 139 users, not 10 (§8).
- **Built now:**
  - **Phase 1:** all 20 `HealthProfile` write sites run inside `HealthProfileRepository`.
  - **Phase 4:** the suggestion engine reads set, exercise, workout and profile snapshots;
    `ActiveWorkoutViewModel.workout` is also a snapshot.
  - **Tier C / Settings:** `SettingsService` exposes only profile snapshots; its setters return
    the saved snapshot, and `SettingsViewModel` renders that value instead of a live model.
- **Still needed:** Phase 5 converts the workout screens' held `[WorkoutSet]` values. Until then,
  those screens still have the risk represented by the held-live-set positive control. The
  control itself is intentionally unsafe and must keep crashing after Phase 5.
- **Minimum iOS is now 18.0 (2026-09-13).** Bug 2 exists only on iOS 17, so it can no longer
  happen on a supported OS. Phases 2–3 are now optional architecture work, not crash fixes (§8.3).
- **Recommended next order:** Phase 5 → Phase 6, with Phases 2–3 when convenient. See the short
  operator checklist in
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
4. Its claim that `@Model` types already conform to `Sendable` is correct on the **current**
   toolchain. A clean Xcode 26.3 (17C529) build shows the macro itself emitting
   `extension <Model>: Sendable` for all 13 model types in this audit; the explicit
   `@unchecked Sendable` conformances are redundant. Removing them is optional cleanup and does
   not restore compiler checking. The replacement guards are the source ratchet (§4.5) and the
   Phase 3 insert-only repository assertion (§3).

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
- `RepsterTests/LiveModelRaceReproTests.swift`: marker-gated real-path regressions,
  mechanism discriminators and deliberately crashing positive controls
- `SwiftDataSnapshotBoundaryTests` in that file: snapshot/model parity guards
- `AffectedSetsPreconditionTests`, which guards PR-badge identity
- the opt-in race tests in `CrossContextRaceTests`

---

## 3. Bug 2 scope: 47 write sites

Every site does fetch → change → `repo.save(model)` from a plain actor. Inserts of brand-new
records are excluded (nothing to race): `PRService:86/515`, `StatsService:113/270` (new stats),
`WorkoutService:55`, `TemplateService:202/292/311/498` and `BodyweightService:32`.

| Service | Sites (save line) | Model | Replacement | Difficulty |
|---|---|---|---|---|
| `SettingsService` | **17**: `:53 60 67 75 83 90 97 106 113 120 127 134 142 149 156 163 170` | HealthProfile | **Built:** `HealthProfileRepository.update(_ body:)` fetches/creates, applies, stamps and saves inside the owner | Done |
| `FatigueLearningService` | **3** profile: `:420` (fields set `:723-732`), `:490`, `:521` | HealthProfile | **Built:** same `HealthProfileRepository.update(_ body:)` | Done |
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

Bug 3 needs a live record read outside its owner when the owner saves that record, or when the
owner first fetches a new record it just saved. A save in another context and a plain re-fetch
keep the held instance's backing data. The fix is to read copies. Tiers are in risk order.

### 4.1 Tier A: the suggestion engine (both observed crashes) — **done 2026-09-12**

**Crash B's reader:** `LoadPrescriptionService` (a plain actor) previously fetched and read live
records. Phase 4 built these replacements:

| Line | Former live read | Built replacement |
|---|---|---|
| `:225`, `:250` | `setRepo.fetchSets(exerciseId:from:to:)` → `[WorkoutSet]` | `fetchChartSets(exerciseId:from:to:)` → `[ChartSetData]` |
| `:378` | `workoutRepo.fetch(byIds:)` → `[Workout]` | `fetchWorkoutSummaries(byIds:)` → `[WorkoutSnapshot]` |
| `:56`, `:71` | `healthProfileRepo.fetchOrCreate()` | `fetchSnapshotOrCreate()` → `HealthProfileSnapshot` |
| `:77` | `exerciseRepo.fetch(byId:)` | `fetchChartExercise(byId:)` → `ChartExerciseData` |

Also:
- `isEligibleForCapacity`, `peakAcrossRecentWorkouts` and `capacityE1RM(for:)` take `ChartSetData`.
- `ChartSetData.performanceRIR` now shares the model's calculation, following the August pattern
  for `statsReps`.
- `FatigueLearningService.appliedFatigueRateInfo(for:profile:)` now accepts snapshot inputs.
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
- **Settings screen and SettingsService profile reads — done 2026-09-12.** `SettingsViewModel`
  and the advanced Settings sections hold `HealthProfileSnapshot`. The service's snapshot fetch
  is also used by `ServiceContainer`, `BodyweightLogViewModel`, `CreateEditExerciseViewModel`,
  `EditWorkoutViewModel` and `ExerciseSettingsSheet`; all six callers only read it. Settings
  writes remain routed through service setters, which now return the saved snapshot directly.
- **August's unaudited screens:** `ExerciseDetailViewModel`, `ExerciseListViewModel`,
  `BodyweightLogViewModel`, `AssignMuscleGroupsView`, `TemplateListSheet`, `ExercisePickerSheet`.
- **Reads inside services.** A grep finds about 145 live-record fetches in plain-actor services:

  | Service | Fetches |
  |---|---|
  | `PRService` | 24 |
  | `FatigueLearningService` | 23 |
  | `SettingsService` | 19 in the original scan; now 0 live-profile reads through its public API |
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

### 4.5 The source ratchet for both bugs

The old compile-time plan no longer works. A clean build with Xcode 26.3 (17C529) shows the
`@Model` macro itself generating `extension <Model>: Sendable`. It reports 13 expected
"redundant conformance" warnings where this project also declares `@unchecked Sendable`, but
removing those declarations leaves the macro conformance in place. Swift therefore cannot flag
these actor-boundary crossings on this toolchain.

`SwiftDataLiveModelBoundaryRatchetTests` is the replacement guard. It scans source for:

- repository protocol methods returning any of the 13 audited `@Model` types; and
- views or view models under `Repster/Features` that store any of those types.

Every current crossing is in an explicit allowlist grouped by the phase expected to remove it:
Phases 2–3 service writes, Phase 5 workout-screen sets and Phase 6 long-tail reads. The test fails
both when a new crossing appears and when a listed crossing vanishes without its stale entry
being removed, so the inventory can only shrink deliberately. A planted `HealthProfile`
property was verified to fail with its file and declaration named, then removed.

The write-side guard remains the end of Phase 3 (§3): rename repository `save(_:)` methods to
insert-only APIs and add `#if DEBUG` assertions that `model.modelContext == nil`. Removing the
now-redundant explicit `@unchecked Sendable` conformances is optional warning cleanup, not a
safety guard.

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
| **6. Tier C + ratchet closure** | Remaining unaudited screens and service reads; shrink the source-ratchet allowlist to zero. Settings/profile slice **done 2026-09-12**. Redundant explicit `@unchecked Sendable` removal is optional cleanup | The rule everywhere; the ratchet prevents new crossings | 2+ sessions, can be spread out |

Sizes are estimates. For scale: August's comparable Stage 1 + 2 touched 52 files
(+2,897 / −492).

**Why this order:**
- Completed first: Phase 1 closed the only known real-user crash; Phase 4 closed both observed
  bug-3 readers without changing the set table.
- Next, Phase 5 closes the remaining high-traffic workout-screen reads. It is the riskiest change,
  so it stays isolated behind its own real-path regression and device pass.
- Then Phase 2 before Phase 3: PR/stats is the hotter bug-2 path, followed by the remaining writes
  and the insert-only guard.
- Phase 6 comes last because it is the long-tail audit and closes the source-ratchet allowlist.

---

## 6. Verification

The August rule applies: **a green suite is close to no evidence on these paths.** Every fix
needs a control that still detects the bug.

| Phase | Harness | Pass condition |
|---|---|---|
| 0 | Bug 2: the real `OnboardingViewModel.finish()` with main-built repositories, iOS 17.5, plus two discriminators. **Built**, marker-gated like `CrossContextRaceTests` | Pre-fix crashed on 17.5, 5/5; clean after Phase 1 |
| 0 | Bug 3: a live record held by other code while its repository saves it (in-memory, iOS 18.6). **Built** | Crashes on 18.6 today, 10/10 |
| 1 | Real onboarding regression, 2,000 rounds | **Clean on iOS 17.5 (2026-09-12)** |
| 2–3 | `AffectedSetsPreconditionTests` (crashes every run on 17.5 today); `SetServiceTests` with repositories built on main (crashes today, investigation §9.3) | Clean ×20 on 17.5; badge identity measurements unchanged |
| 4 | Real suggestion-engine regression plus set/workout snapshot stress | **Clean on iOS 18.6 and 26.3.1 (2026-09-12)** |
| Tier C / Settings | Real `SettingsViewModel` toggles save in a loop while a main-actor loop reads its profile fields | **Pre-fix crash on iOS 18.6; clean on 18.6 and 26.3.1 (2026-09-12)** |
| 5 | Keep `testBug3Control_HeldSetsReadWhileOwnerSaves` as the synthetic positive control. Add a separate real-path regression that drives the converted active/edit workout view-model set flows while repository saves overlap their reads | The synthetic held-live-set control must still crash; the new snapshot-based real-path regression must be clean on 18.6 and 26.3 |
| All | Full suite on **18.6 and 26** (17.5 was dropped with the iOS 18 minimum), one `xcodebuild` at a time, totals from `.xcresult`; golden masters unchanged; mutation checks on the changed surface (August §16) | — |
| 5 | Device pass: log sets, PR badges appear and demote, edit a finished workout, finish a workout, suggestions refresh on exercise switch | — |

**Why the harness, not `WorkoutJourneyTests`.** Re-running the journey tests on 18.6 crashes
about once per 360 runs, so 30 clean iterations would still happen about 5% of the time with the
bug present. The bug-3 controls crash every run on 18.6.

**Destinations:**
- Standing test destinations: iOS 18.6 (iPhone 16 Pro, the oldest supported runtime) and
  iOS 26.3.1 (iPhone 17 Pro). iOS 17.5 was dropped when the minimum was raised to iOS 18 (§8.3).
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

### 8.1 Settings snapshot follow-up — done 2026-09-12

**Test first.** Added
`testBug3Regression_SettingsViewModelUsesSnapshotWhileTogglesSave`, gated by
`RUN_BUG3_SETTINGS`. It uses the real `SettingsViewModel` and `SettingsService`: one loop changes
units, rest time and Smart Suggestions while a main-actor loop reads the held profile fields.
Before changing app code, the test crashed on iOS 18.6 with
`KnownKeysDictionary deallocated with non-zero retain count` and the `.xcresult` reported a signal
trap. This proves the test exercised the same bug-3 mechanism as the Settings screen risk.

**Implementation:**

- Replaced `SettingsServiceProtocol.fetchSettings() -> HealthProfile` with
  `fetchSettingsSnapshot() -> HealthProfileSnapshot`; the live service read no longer exists.
- Every Settings setter now returns the `HealthProfileSnapshot` produced by
  `HealthProfileRepository.update`, including setters that subsequently rebuild PRs or stats.
- `SettingsViewModel.profile` and the advanced Smart Suggestions views now hold
  `HealthProfileSnapshot`. After a change, the view model assigns the setter's returned snapshot
  directly instead of saving and then re-fetching the profile.
- Onboarding and advanced-settings callers that do not own profile state explicitly discard the
  returned snapshot. Protocol test doubles and Settings summary fixtures were migrated too.
- Corrected the race-harness comments: Phase 1 now has an owner-side update method, and bug 3's
  backing replacement is caused by an owning-context save or the first fetch after it saved a new
  model—not by another context saving the row.
- If a warmup setting is saved but its follow-up stats/PR rebuild throws, `SettingsViewModel`
  now presents the rebuild error and reloads the committed snapshot. Paired unit tests cover the
  volume and PR toggles so the UI cannot silently show the old value.

**Settings snapshot caller audit:**

| Caller | Profile data used | Writes through the fetched value? |
|---|---|---|
| `ServiceContainer` | Unit preference cache | No |
| `BodyweightLogViewModel` | Display unit | No |
| `SettingsViewModel` | Rendered Settings state | No; changes use SettingsService setters |
| `CreateEditExerciseViewModel` | Default rest and weight increment | No |
| `EditWorkoutViewModel` | Unit and default weight increment | No |
| `ExerciseSettingsSheet` | Default rest and weight increment | No |

**Verification:**

| Gate | Runtime | Result from `.xcresult` |
|---|---|---|
| Settings regression, before migration | iOS 18.6 | Crashed: 1 failed, signal trap; non-zero-retain-count log signature |
| Settings regression, after migration | iOS 18.6 | Passed: 1/1; 2,000 toggle rounds, 6,363,100 profile-read passes |
| Settings regression, after migration | iOS 26.3.1 | Passed: 1/1; 2,000 toggle rounds, 4,979,150 profile-read passes |
| `RUN_BUG2_UNSAFE_WRITES` positive control | iOS 17.5 | Still crashed: 1 failed, SIGSEGV |
| `RUN_BUG3_HELD_SETS` synthetic positive control | iOS 18.6 | Still crashed: 1 failed, SIGSEGV; non-zero-retain-count log signature |
| Full suite | iOS 26.3.1 | Passed: 910 total, 896 passed, 14 gated skips, 0 failures |

The test target builds with no new warnings from this work. Earlier verification in the same work
record covers the onboarding regression on iOS 17.5 and the suggestion-engine regression on iOS
18.6 and 26.3.1.

**Next decision:** schedule Phase 5 separately. It is still recommended because the active and
edit screens retain live `WorkoutSet` objects, but it is intentionally not bundled into this
lower-risk change. After its device pass, complete Phases 2–3 and then close the long-tail
ratchet allowlist.

### 8.2 Guard and documentation cleanup — done 2026-09-12

- Replaced the invalid compiler-guard plan with
  `SwiftDataLiveModelBoundaryRatchetTests`, enrolled in the test target with an explicit phased
  allowlist. Its baseline passes and a temporary unlisted `HealthProfile` property produced the
  intended clear failure before being removed.
- Recorded the Xcode 26.3 macro behavior, the built Fatigue profile writes and the existing race
  and parity harnesses throughout this plan.
- Removed the unused `SmartSuggestionsAdvancedSettingsView` wrapper after a project-wide caller
  search; `SmartSuggestionsAdvancedSections`, which `SettingsView` uses, remains.
- Kept the Phase 3 insert-only `save` rename and DEBUG detached-model assertion as the write-side
  guard. Explicit `@unchecked Sendable` removal is now documented only as optional cleanup.

**Verification (2026-09-13, from `.xcresult`):** the focused Settings/ratchet run passed 6/6;
the planted-offender proof failed 1/1 with the added declaration named; the iOS 17.5 unsafe-write
control crashed with `SIGSEGV`; and the iOS 18.6 held-set control crashed with `SIGABRT` plus the
expected non-zero-retain-count log signature. The full iOS 26.3.1 suite passed: 913 total, 899
passed, 14 marker-gated skips and 0 failures. Both race markers were consumed.

### 8.3 Minimum iOS raised to 18.0 — 2026-09-13

- **What changed:** `IPHONEOS_DEPLOYMENT_TARGET` went from 17.0 to 18.0 in all six build
  configurations (the project, `Repster` and `WorkoutLiveActivityExtension`).
- **Why:** four tests kept crashing on iOS 17.5 through the remaining bug-2 writers. One of
  those writers, `WorkoutService.finishWorkout`, had never been seen before (investigation
  §13). Bug 2 exists only on iOS 17. About 2–3% of iPhones were below iOS 18 in August 2026,
  and every iOS 17 device can run iOS 18.
- **Effect on this plan:**
  - Phases 2–3 no longer fix a crash. They stay as optional work under the one-owner rule.
  - Phase 5 (bug 3 on iOS 18 and 26) and the Phase 6 ratchet are unchanged.
  - The `RUN_BUG2_*` harness tests are kept as history only.

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
