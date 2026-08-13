# SwiftData Cross-Context Crash — Work Record

**Session date:** 2026-08-11 → 2026-08-12
**Outcome:** both shipped crashes fixed and verified by reproduction. Suite 355 → 391 tests, 0 failures.
**Ships after:** the on-device manual pass in §7.1 — the only remaining blocker.

This is the narrative record: what was done, what was proven, what was got wrong, and what is left.
The two design documents carry the detail and are the authority on their subjects:

| Document | Covers |
|---|---|
| `SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md` | Diagnosis, reproduction, Stage 1 scope and record (§14) |
| `STAGE2_WRITE_PATH_DESIGN.md` | Stage 2 design, steps 1/3/4 records, mutation sweep, §12 |

---

## 1. Starting point

Two `EXC_BAD_ACCESS (SIGSEGV)` crashes at `0x8000000000000010`, captured from one TestFlight
session on 1.4 (6), both the same root cause on different screens:

- **Crash A** — main thread faulting `Workout.status` in `HomeViewModel.loadRecentWorkouts` while
  `WorkoutRepository.save` ran from the HealthKit mirror.
- **Crash B** — main thread faulting `Exercise.trackingType` in `SetTableView.inputHeaders` during
  layout, while `ExerciseRepository.save` ran from the exercise edit sheet.

**Root cause.** Repositories are `@ModelActor`s that returned *live* `@Model` objects across the
actor boundary into `@MainActor` UI code. A SwiftData model is a handle into the `ModelContext` that
produced it; reading a persisted property faults back into that context from whatever thread does
the read. When that context is simultaneously in `save()` — which tears down internal registry state
— the read lands on freed memory. All 17 `@Model` types carried `@unchecked Sendable`, which is what
let this compile.

This was the **third** instance of the class. The first shipped in 1.3 and was consciously deferred.

---

## 2. What was done

### 2.1 Stage 1 — crash A (Home, Copy Previous, Calendar, detail screens)

Snapshot value types replace live models on every read path the crash touched.

- **New snapshot types** in `ChartSetData.swift`: `WorkoutSnapshot`, `PerformanceRecordSummaryData`;
  `ChartSetData` extended with `completed`, `orderInWorkout`, `orderInExercise`, `notes`, `rir`,
  `leftRIR`, `rightRIR` (later also `excludeFromPRs`, `statsReps`).
- **Formatter and PR-status snapshot overloads**, sharing one body with their live-model twins so
  the two cannot drift.
- **Repository/service/protocol** snapshot fetches throughout; `StatsService.fetchRecentPRs` changed
  return type.
- **Readers converted**: `HomeViewModel`, `ContentView` (Copy Previous *and* its continuation —
  `performCopy`/`discardActiveAndCopy`), `CalendarViewModel` including `selectDate`,
  `WorkoutDetailFromHomeView`, `CalendarWorkoutDetailView`, `CalendarExerciseCard`, `CalendarView`.
- **`ExerciseGroup` and `WorkoutDetail` became snapshot types**, in place.
- **Hygiene**: `healthKitWorkoutUUID` mutation moved into the repository actor.
- **Deleted** `CalendarExerciseCard`'s `workoutSet.modelContext == nil` guard — it existed to swallow
  exactly the failure this change removes, and a snapshot cannot detach.

**Naming deviation:** the planned `WorkoutSummaryData` collided with an existing finish-screen recap
struct in `ActiveWorkoutViewModel`, so the new type is `WorkoutSnapshot`. Renaming the existing one
would have meant editing Stage 2's riskiest file.

### 2.2 Stage 2 step 1 — crash B (the exercise slice)

- **`ChartExerciseData` became a complete mirror of `Exercise`** — all 20 stored properties, not just
  the fields callers happened to read.
- **Shared computed logic unified**: `TrackingType.supportsUnilateralLogging`,
  `UnilateralRepTargetMode.resolve`, `ExerciseFatigueRateSource.resolve`, `isBodyweightStyle`. Both
  `Exercise` and the snapshot delegate to one implementation each. This matters most for
  `unilateralRepTargetMode`, whose fallback depends on the exercise **name** — two copies could have
  silently flipped rep targets from per-side to total for affected exercises.
- **Write side moved into the owning actor**: `ExerciseRepository.applyEdit/create/fetchMetadataSnapshot`;
  `ExerciseService.updateExercise(id:fields:)` and `createExercise(fields:)` take values.
- **Read side converted**: `SetTableDataSource`, both conforming ViewModels, `SetTableView`,
  `SetRowView`, `ExerciseTabStripView`, `SuggestionCoordinator`, `ExerciseInfoProvider`,
  `ExerciseHistoryView`, `WorkoutExclusionSheet`, and the three edit sheets.

`updateExercise` now reads the pre-edit state itself instead of taking a caller-supplied `original` —
the old contract required callers to snapshot *before* mutating and silently detected no change if
they got that wrong. Its own doc comment had warned about this.

### 2.3 Stage 2 step 4 — the reindex fan-out

Reindexing after a set insert/delete used to persist each changed set through `SetService.edit()` —
the full effectiveWeight → PR → stats → fatigue pipeline — in **one unawaited `Task` per set**. With
unchanged values that pipeline was a no-op, but it produced N concurrent saves per routine action:
§5.3's *manufactured* concurrent writer.

Now one batched, awaited `SetRepository.applyOrdering` call. Measured: adding one warmup set to a
2-set exercise issued **5 separate writes** before, ≤2 batches now.

### 2.4 Stage 2 step 3 — mutations into the repository

`SetService` is `@MainActor` and mutated `SetRepository`-owned models on the main thread. Its
live-model mutations went **24 → 3**, and the three remaining are all `@Transient`
(`persistedFatigueSnapshot`) — they never touch the persistent store.

New repository API: `syncDerivedFields(on:exercise:)`, `persist(_:effectiveWeight:e1RM:clearPRStatus:touchUpdatedAt:)`,
`applyUncomplete`, `applyPRStatus`, `applyTargetRepOverride`, `applyOrdering`. Both `save()` and
`edit()` use the same pair, with exactly one insert-and-save each — the same transaction boundary as
the `setRepo.save(set)` they replaced.

The `e1RM: Double?` + `e1RMFormulaVersion: String?` nil-convention was replaced with an explicit
`E1RMUpdate { leaveAlone, clear, set(value:formulaVersion:) }`, because that convention hid a real
untested behaviour difference between the two pipelines.

### 2.5 Test infrastructure

- **`ScreenDataGoldenMasterTests.swift`** (new, registered by hand in `project.pbxproj`) — seeds a
  fixed workout through the *real* service stack and pins the complete data each screen produces.
  Closes the gap left by there being no UI test target.
- **Snapshot/model parity tests** including a reflection-based drift guard that fails, naming the
  property, when `Exercise` gains a field `ChartExerciseData` does not mirror.
- **Persistence semantics tests** for the new repository API and `updateExercise`.

### 2.6 §12 first pass

`@unchecked Sendable` removed from four models with zero actor-boundary crossings:
`ProgramExercise`, `PlannedWorkout`, `PlannedSet`, `InsightRecord`. 16 → 12 annotated.

---

## 3. Verification — what was actually proven

### 3.1 Both crashes reproduced, then shown fixed

The strongest evidence available, and the method worth reusing: a **paired control**. A clean run
means nothing unless the same harness still detects the bug.

| | Control (pre-fix shape) | Converted path |
|---|---|---|
| **Crash A** | crashes: `KERN_INVALID_ADDRESS at 0x8000000000000010`, `Workout.status.getter` → `_ArrayProtocol.filter` — byte-identical to TestFlight | passes, 4,000 concurrent saves vs 2,000 main-actor re-fetch passes |
| **Crash B** | crashes: same address, faulting frame **`Exercise.trackingType.getter`** — the exact frame from the report | passes under identical load |

Under Thread Sanitizer the live-model path dies inside SwiftData with `x[20] = 0x8000000000000000` —
the same poisoned register as both TestFlight reports — while the snapshot path runs clean.

**Caveat recorded honestly:** TSan never emitted a data-race report; the memory fault lands first. The
correct claim is *"TSan-instrumented, the live path segfaults and the snapshot path is clean"*, not
*"TSan proved a data race."*

All reproduction harnesses were deleted afterwards; `HealthKitEnergyEstimateTests.swift` is pristine.

### 3.2 Mutation testing — the main methodological finding

Three times, a real gap was found by deliberately breaking code while the full suite was green. That
made "N tests pass" untrustworthy here, so coverage was **measured**: 15 mutations across the changed
surface, chosen independently of which behaviours had been consciously preserved.

**Result: 9/14 caught (64%).** The five misses were not logic errors — every one was a *case the
fixtures did not contain*:

| Miss | Root cause |
|---|---|
| `fieldDisplay` renders `weight` not `effectiveWeight` | no test anywhere had `effectiveWeight ≠ weight` |
| `applyOrdering` writes `orderInExercise` when nil | contract tested in one direction only |
| `persist` ignores `clearPRStatus` | every set fixture was `.weightReps` |
| `setHealthKitUUID` is a no-op | no test at all |
| Home includes non-completed workouts | fixture seeded only completed workouts |

All five now have tests, each re-verified by re-applying its mutation.

**Eight genuine gaps were found in one day — every one by breaking code on purpose, none by the suite
turning green.** On the set/snapshot paths, a passing run after a refactor is close to no evidence.

### 3.3 Two results that were not results

Both looked like evidence and were not — worth guarding against when repeating this:

- **An invalid mutation is not a passing test.** One of the fifteen did not compile and exercised
  nothing while sitting in the results.
- **A failed build is not a surviving mutation.** One mutation reported `BUILD-FAILED` purely because
  disk had fallen to ~1 GB under repeated builds. Re-run with space, it was caught immediately.

### 3.4 One unexplained event

A single run reported 1 failure on an unmodified tree, immediately after the module cache was cleared
mid-session. It did not recur in six consecutive runs and the failing test was never captured. Cause
unknown. Recorded rather than dismissed.

---

## 4. Corrections made during this work

Listed because several were assumptions that sounded right and were wrong on inspection.

| Claim | Correction |
|---|---|
| "`RepsterTests` is file-system synchronized, new files are picked up" | Only the `WorkoutLiveActivity` extension is. Test files need four `project.pbxproj` entries |
| "`SetService` has 15 mutation sites" | 24. The grep's `[a-zA-Z]+` skipped `e1RM` (digit) and missed mutating *method* calls |
| "Moving the derivation later would change the stats delta" | It cannot. `sync` writes only `reps`/`rir`/`side`; the snapshot's `statsReps`/`prReps` read `leftReps`/`rightReps`. Code comment corrected |
| "`edit()`'s mutations are blocked by the insert path" | Only `save()`'s were. `edit()` guarantees the row exists |
| "Swift 5 mode means removing `@unchecked Sendable` produces nothing" | It produces precise per-crossing diagnostics |
| "The `@Model` macro already supplies `Sendable`, so §12 is a dead end" | It does not — verified with a compile-time probe |
| "§12 converts this into a compile error" | **Warnings, not errors**, under `SWIFT_VERSION = 5.0`. Errors only in Swift 6 language mode |
| "`Exercise` has 8 crossings" | 18. Protocol-signature counting misses concrete APIs |

---

## 5. Current state

**Committed** (`395ff29 pre step 5 commit`): 52 files, +2,897 / −492 since session start.

**Uncommitted:**
```
Repster/Data/Models/InsightRecord.swift        §12 — annotation removed
Repster/Data/Models/PlannedSet.swift           §12
Repster/Data/Models/PlannedWorkout.swift       §12
Repster/Data/Models/ProgramExercise.swift      §12
RepsterTests/ScreenDataGoldenMasterTests.swift gap-closing test
RepsterTests/SetServiceTests.swift             gap-closing tests
RepsterTests/WorkoutSetTests.swift             gap-closing tests
STAGE2_WRITE_PATH_DESIGN.md                    §17
```

All additive, suite green. **Nothing is in a half-finished state** — the remaining Stage 2 steps are
independent follow-ups, not the back half of something already started.

**Tests: 391, 0 failures** (355 at session start).

---

## 6. What remains

Ordered by real risk, not plan order.

### 6.1 Same shape as a shipped crash

`ActiveWorkoutViewModel` still holds `workout: Workout?` and `setsByExercise: [UUID: [WorkoutSet]]`
as live models, and `SetTableView` renders off them every frame — structurally identical to crash B,
on the highest-frequency screen. Crash B's *specific* trigger is fixed; the set half of that screen
is not converted. **This is Stage 2 step 5** and matters more than the other remaining steps combined.

Its four design questions are already answered (`STAGE2_WRITE_PATH_DESIGN.md` §15), and two of them
*reduce* the work: no optimistic-UI layer is needed, and `updatedAt` need not reach the snapshot. The
one delicate function is `applyAffectedSets` — note that `affectedSetIds` is `[UUID: CachedPRStatus?]`
and the existing `if let` unwraps the *outer* optional, so a present-but-nil entry legitimately clears
a badge. Flattening that with `??` would silently kill demotions.

### 6.2 Stage 2 steps 5–8

Step 5 (above), 6 (`EditWorkoutViewModel`), 7 (`WorkoutSummarySheet` — reads live workout fields
*during* `finishWorkout`'s save), 8 (rest of §12).

### 6.3 §12 remaining, with measured cost

| Model | Crossings |
|---|---|
| FatigueObservation, TemplateSet, TemplateExercise | 3 each |
| HealthProfile, Program, WorkoutTemplate | 4 each |
| ExerciseStats, PerformanceRecord | 6 each |
| BodyweightEntry | 9 |
| Exercise | 18 |

`Workout`/`WorkoutSet` excluded — step 5 deletes exactly those crossings.
Policy: remove a model's annotation only once its crossings hit zero, so the build stays warning-clean
and each removal is a guarantee rather than logged debt.

### 6.4 Unaudited surfaces

Screens still holding live models in main-actor state: `ExerciseDetailViewModel`,
`ExerciseListViewModel`, `BodyweightLogViewModel`, `AssignMuscleGroupsView`, `TemplateListSheet`,
`ExercisePickerSheet`. Services still mutating repository-owned models on their own executor (§5.5):
`PRService` (including `oldSet.prStatus = .previous` on a set the table may render), `StatsService`,
`FatigueLearningService`, `TemplateService`, `WorkoutService.finishWorkout`, others. Neither captured
crash was this shape, so it is latent rather than observed. **These counts are grep candidates, not an
audit.**

### 6.5 Verification gaps

No tests of the SwiftUI layer at all — no rendering, bindings or layout is exercised anywhere. Nothing
covers HealthKit, Live Activity or notifications.

---

## 7. Before shipping

### 7.1 Manual device pass — the only remaining blocker

1. **Finish a workout ~10× rapidly** (not spaced — `HomeView.swift:106` nils `lastLoadTime` to defeat
   the 2s debounce, which is what lets two `loadData()` passes interleave). Home reloads, no crash.
2. **Edit an exercise mid-workout** from the settings sheet — crash B's actual user path.
3. **RIR column** populated on a workout-detail card for a `.weightReps` and a `.custom` exercise.
4. **Dumbbell Lunge rep targets** — the one exercise whose rep-target mode comes from the name-based
   fallback.
5. **Exercise settings → full settings → save** — confirm rest time and increment refresh (this had a
   latent staleness bug, fixed).
6. Apple Health receives the workout and `healthKitWorkoutUUID` persists (no double-write).
7. Copy Previous; Calendar dots across months; Edit Workout title/notes update on return; Save as
   Template from **both** Home and Calendar detail; Delete workout refreshes Home.

### 7.2 Commands

```bash
xcodebuild test -project Repster.xcodeproj -scheme Repster -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

TSan (needs ~2 GB free):
```bash
xcodebuild test -project Repster.xcodeproj -scheme Repster -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -enableThreadSanitizer YES
```

---

## 8. Method notes worth keeping

1. **Paired controls.** A clean run proves nothing unless the same harness still catches the bug.
   Every "fixed" claim here has a control showing the detector still works.
2. **Mutate what you claim to have preserved.** Eight real gaps came from this; zero came from the
   suite going green.
3. **Separate infrastructure failure from result.** An invalid mutation and an out-of-disk build both
   masquerade as evidence.
4. **Prefer the compiler to heuristics.** Protocol-signature counting under-reported `Exercise`'s
   crossings by more than half; grep under-counted `SetService`'s mutations by nine.
5. **One implementation per rule.** Every drift-prone rule here (`unilateralRepTargetMode`,
   `supportsUnilateralLogging`, `fieldDisplay`, `effectiveStatus`) now has a single body shared by the
   live and snapshot paths. The RIR near-miss was a duplicated rule.
6. **Assert below the view.** With no UI test target, the highest testable layer is what the ViewModel
   hands the view — which is exactly what the snapshot conversion makes assertable.
7. **Don't pipe a long sweep through `tail`.** It buffers, and progress becomes invisible.
