# Test suite failures — investigation record

**Written:** 2026-09-11. **Revised:** 2026-09-13 after verification, reproduction and the
Xcode 26.3 guard audit. §12 records the Phase 1 and Phase 4 implementation; corrected historical
claims in the body are marked and point to §11/§12. §13 (2026-09-13) diagnoses four tests that
crash on iOS 17.5: bug 2, with a new writer (`WorkoutService.finishWorkout`).

## Plain summary (read this first)

- **Nothing new broke.** The full suite went red on 2026-09-11 only because that run used the
  **iOS 17.5** simulator, which the project doesn't normally test on. On **iOS 26** (the usual
  test destination, and 139 of about 150 active users) the whole suite passes.
- **Three separate problems were found.** Only one needed fixing now.

| | What it is | Who it affects | Status |
|---|---|---|---|
| **Bug 1** | Two test helpers built their test database without the template tables | Tests only, never the app | **Fixed 2026-09-11** (uncommitted). Suite green on iOS 17.5 and 26 (§3.6) |
| **Bug 2** | A crash on iOS 17 when a service changes a saved record it doesn't own | iOS 17 only: **1 active user**, and it **has crashed a real phone** (1.3, iOS 17.5.1, onboarding) | **Real onboarding path fixed (Phase 1)**; other services remain for Phases 2–3 (§12). Those remaining writers still crash 4 tests on iOS 17.5 (§13) |
| **Bug 3** | A crash when code is holding a record at the moment its repository saves it, or first fetches a record it just saved | iOS 18: 10 active users. The same pattern also crashes the harness on iOS 26 (§11.3) | **Both observed readers fixed (Phase 4)**; held workout sets remain for Phase 5 (§12) |

- **"47 places" is not 47 bugs.** It is one unsafe write shape repeated across seven services.
  Phase 1 removes the 20 profile writes; the remaining 27 are staged as Phases 2–3.
- **Done since (2026-09-11/12):**
  - Organizer checked. Bug 2 has one real-device crash (§11.1).
  - Both bugs reproduce on demand in `RepsterTests/LiveModelRaceReproTests.swift` (§11).
  - Phases 1 and 4 are implemented and verified (§12); the remaining work is tracked in
    [SWIFTDATA_LIVE_MODEL_FIX_SCOPING.md](SWIFTDATA_LIVE_MODEL_FIX_SCOPING.md).

---

## 1. Summary

On the **iPhone 15 Pro / iOS 17.5** simulator, the full suite failed 13 of 866 tests. On
**iPhone 17 Pro / iOS 26.3.1**, the destination the project normally tests on, the affected
classes pass. On **iPhone 16 Pro / iOS 18.6**, bug 2 is absent but a third, rarer crash appears.

**How this came up:** while verifying the share-from-history work
([SHARE_FROM_HISTORY_SCOPING.md](SHARE_FROM_HISTORY_SCOPING.md)), the full suite came back red.
Every failure turned out to predate that work (§2).

| | Bug 1: template models missing | Bug 2: cross-actor write race | Bug 3: held-model read during owner save / first post-create fetch |
|---|---|---|---|
| Runtime | iOS 17.5 (passes on 26; 18.6 was only tested after the fix) | iOS 17.5 only. Clean on 18.6 (§10.1) and 26 (§9) | Backing replacement observed on iOS 18.6; the broader held-read/owner-save pattern also crashes the harness on iOS 26.3.1 (§11.2–11.3) |
| Tests affected | 5, the same five every run | ~7, **different ones every run** | 2 crashes seen, in `WorkoutJourneyTests` |
| How it fails | Uncaught ObjC exception → XCTest aborts the process (`SIGABRT`) | `EXC_BAD_ACCESS` at `0x8000000000000010`, main thread, inside a SwiftData run-loop observer | `EXC_BAD_ACCESS` at `0x10` while reading a `@Model` property |
| Cause | Two test helpers never registered the template models after the 2026-09-01 templates redesign made backup touch templates | A plain-actor service (`PRService`, `StatsService`, …) writes to a `@Model` owned by a repository whose context was created on the main thread (§4.2) | Other code holds and reads a live `@Model` while its owner saves it, or first fetches a model it just saved; iOS 18 may replace and free the held backing data (§11.2) |
| Since | Commit `3cf55ed`, 2026-09-01 | Unknown | Unknown |
| Affects the app? | No | **Yes:** one real-device crash in 1.3 on iOS 17.5.1, during onboarding (§11.1) | The risky pattern is present; no real-device bug-3 crash has been seen (§11.2–11.3) |
| Status | **Fixed** (§3.6) | Real onboarding/profile path fixed in Phase 1; other write owners remain for Phases 2–3 (§12) | Both observed suggestion/workout readers fixed in Phase 4; held workout sets remain for Phase 5 (§12) |

The Bug 2 and Bug 3 cells above were corrected 2026-09-12 after the dedicated harness and device
crash review; §11/§12 preserve the evidence that superseded the original claims.

**The side effect of all three:** each crash kills the test process. XCTest restarts it at the next
test, and a runner that crashed still prints green per-class tallies. **Read totals from the
`.xcresult`, never from the text log** (§7).

---

## 2. How the failures were attributed

All runs were on 2026-09-11, one at a time with no concurrent `xcodebuild`.

| Run | Destination | Tree | Scope | Result (from `.xcresult`) |
|---|---|---|---|---|
| A: full suite | iPhone 15 Pro, **iOS 17.5** | Working tree with the share-from-history changes | Everything | **866 tests, 848 passed, 13 failed, 5 skipped** |
| B: isolated | iPhone 15 Pro, **iOS 17.5** | Same tree | Only the 7 affected classes | **122 tests, 110 passed, 12 failed**, ~12 runner restarts |
| C: baseline | iPhone 15 Pro, **iOS 17.5** | A throwaway worktree at `HEAD` + only the user's pre-existing uncommitted diff | The same 7 classes | **122 tests, 110 passed, 12 failed** |
| D: other runtime | iPhone 17 Pro, **iOS 26.3.1** | Same tree as B | The same 7 classes | **122 tests, 122 passed, 0 failed**, 0 restarts |
| E: solo repeat | iPhone 15 Pro, **iOS 17.5** | Same tree as B | `testAffectedSetEntriesArriveAlreadyAppliedToTheHeldInstances` only, `-test-iterations 10` | **Crashed on iteration 1** with the bug-2 signature, as the only test in the process |

What this shows:
- **B vs A:** the failures are not caused by full-suite load.
- **C vs B:** the failures are not caused by share-from-history.
- **D vs B:** both bugs depend on the simulator runtime. On iOS 26.3.1 neither appears.
- **E:** bug 2 does not need an earlier test to leak state into the process. One test is
  enough.

**Not established:** whether bug 2 exists on bare `HEAD` (run C included the user's uncommitted
edits). The mechanism doesn't depend on those edits (§9.1 reproduces it with no app code), so
this no longer matters much. For iOS 26, a full suite and a targeted probe both came back clean
(§9), which is strong evidence but not proof.

**On timing:** runs A–C used iPhone 15 Pro, which on this machine exists only as an iOS 17.5
simulator. Almost every earlier test record in the project uses `name=iPhone 17 Pro` (iOS 26).
This resolves an apparent contradiction: the project notes record a clean **814-test run on
2026-09-05**, after commit `3cf55ed`. That run was on iOS 26, where bug 1 does not fire. So
"red since 2026-09-01" is true **only for iOS 17.5**, and nobody was testing on that runtime.

---

## 3. Bug 1: backup tests build their database without the template models

### 3.1 Failing tests (identical in runs A–C; all pass in run D)

| Class | Test | Failing line |
|---|---|---|
| `SetServiceTests` | `testBackupRoundTripPreservesTargetRepOverridesOnInProgressSet` (declared `:405`) | [SetServiceTests.swift:437](RepsterTests/SetServiceTests.swift:437) |
| `SetServiceTests` | `testExportBackupKeepsOnlyLearningDataForUntouchedTrackedSets` (declared `:454`) | [SetServiceTests.swift:468](RepsterTests/SetServiceTests.swift:468) |
| `SetServiceTests` | `testExportBackupPreservesUnilateralFields` (declared `:475`) | [SetServiceTests.swift:514](RepsterTests/SetServiceTests.swift:514) |
| `WorkoutHistoryBackupServiceTests` | `testExportBackupPreservesMultipleSameDayWorkoutsAndMetadata` | class declared in `ActiveWorkoutViewModelSuggestionRefreshTests.swift:4128` |
| `WorkoutHistoryBackupServiceTests` | `testRestoreBackupReplacesHistoryAndKeepsUnrelatedData` | same file |

The "failing line" is each test's `exportBackup()` call site.

### 3.2 The error

```
error: -[RepsterTests.SetServiceTests testBackupRoundTripPreservesTargetRepOverridesOnInProgressSet] :
NSFetchRequest could not locate an NSEntityDescription for entity name 'WorkoutTemplate'
(NSInternalInconsistencyException)

*** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
reason: 'NSFetchRequest could not locate an NSEntityDescription for entity name 'WorkoutTemplate''
```

Every one of these crash reports is `EXC_CRASH` / `SIGABRT` on an `NSManagedObjectContext` queue,
with `__pthread_kill ← abort ← … ← _objc_terminate ← _XCTTerminateHandler`. The fetch raises an
Objective-C exception. Neither Swift `try` nor XCTest can catch it, so the whole test process is
killed rather than one test failing cleanly.

On iOS 26.3.1 the same fetch does not throw, and the five tests pass. Why SwiftData 26 tolerates
the unregistered type was not investigated. It does not matter for the fix.

### 3.3 Cause

The templates redesign, commit **`3cf55ed` (2026-09-01)**, added templates to the backup archive:
- **Export** fetches every template:
  [ExportService.swift:94](Repster/Core/Services/ExportService.swift:94) —
  `FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.createdAt)])`
- **Restore** deletes every template before writing the archive's:
  [ExportService.swift:286](Repster/Core/Services/ExportService.swift:286) —
  `for template in try context.fetch(FetchDescriptor<WorkoutTemplate>())`

The five tests date from 2026-05-02 (`045b10b`). The two helpers they use build in-memory
containers that were never updated:

- `SetServiceTests.makeContext()`
  ([SetServiceTests.swift:1884](RepsterTests/SetServiceTests.swift:1884))
- `WorkoutHistoryBackupServiceTests.makeBackupServiceContext()`
  (`ActiveWorkoutViewModelSuggestionRefreshTests.swift:4410`)

### 3.4 What each container registers

| Model | App (`ModelContainerSetup`) | `SetServiceTests` | `WorkoutHistoryBackupServiceTests` | `WorkoutHistoryBackupArchiveServiceTests` (`WorkoutHistoryBackupTests.swift:1550`) |
|---|---|---|---|---|
| `Exercise`, `Workout`, `WorkoutSet` | ✓ | ✓ | ✓ | ✓ |
| `ExerciseStats`, `PerformanceRecord` | ✓ | ✓ | ✓ | ✓ |
| `BodyweightEntry`, `HealthProfile` | ✓ | ✓ | ✓ | ✓ |
| `FatigueObservation`, `FatigueLearningSetAudit` | ✓ | ✓ | ✓ | ✓ |
| **`WorkoutTemplate`, `TemplateExercise`, `TemplateSet`** | ✓ | **✗** | **✗** | ✓ |
| `Program`, `ProgramExercise`, `PlannedWorkout`, `PlannedSet` | ✓ | ✗ | ✗ | ✗ |
| `InsightRecord` | ✓ | ✗ | ✗ | ✗ |

The app's schema is in
[ModelContainerSetup.swift](Repster/Data/Persistence/ModelContainerSetup.swift). Reference
helpers that already register the template models: `WorkoutHistoryBackupTests.swift:1550` and
`:2301`, and `SmartSuggestionSettingsTests` (`ActiveWorkoutViewModelSuggestionRefreshTests.swift:3616`).

Programs and `InsightRecord` are missing too, but the archive does not carry programs (see
[RELEASE_1_6_CONSIDERATIONS.md §1.2](RELEASE_1_6_CONSIDERATIONS.md)), so they don't trigger
this today.

### 3.5 Impact

- **The app is unaffected.** Its real container registers all three template models.
- **On iOS 17.5 the tests have been red since 2026-09-01.** On iOS 26 they have been green.
- **Every iOS 17.5 run pays for it:** each of the five aborts the runner.

### 3.6 Fix

1. **Minimum:** add `WorkoutTemplate.self, TemplateExercise.self, TemplateSet.self` to both
   helpers.
2. **Better (recommended):** build test containers from the app's own schema, so the next model
   added to the archive can't re-break them silently. `ModelContainerSetup` builds its `Schema`
   inline. Expose it (for example `static let schema = Schema([...])`) and have test helpers use
   it with `ModelConfiguration(isStoredInMemoryOnly: true)`.

**Verify on iOS 17.5** (§5). A green result on iOS 26 proves nothing here, because the tests
already pass there.

**Option 1 verified 2026-09-11 in a throwaway worktree on iOS 17.5:** with the three models added
to both helpers, `SetServiceTests` passed 46/46 and `WorkoutHistoryBackupServiceTests` 3/3, each
over 3 iterations (§9, F1).

**Option 2 applied 2026-09-11 (uncommitted):**
- `ModelContainerSetup.modelTypes` is the one model list. `createContainer()` builds its
  `Schema` from it.
- Four test helpers that run backup export or restore now build
  `ModelContainer(for: Schema(ModelContainerSetup.modelTypes), configurations: [inMemory])`:
  - `SetServiceTests.makeContext()`
  - `WorkoutHistoryBackupServiceTests.makeBackupServiceContext()`
  - `CrossContextRaceTests.makeContainer()`, for the opt-in `testExportBackupUnderConcurrentSaves`
  - `RealDataDifferentialTests.makeStack()`, which is also opt-in and restores a real backup

  The last two had the same gap but never ran by default.
- `SchemaV1` in `RepsterMigrationPlan.swift` was deliberately **not** reused, because its header
  says it must not be relied on.

**Results in the real tree:**

| Run | Result |
|---|---|
| The five affected classes, iOS 17.5, `-test-iterations 3` | 81 tests: 77 passed, 4 skipped (gated), 0 failed, 0 restarts |
| Full suite, iOS 26.3.1 | **866 tests: 862 passed, 4 skipped, 0 failed**, 0 restarts |
| Full suite, iOS 17.5 | **866 tests: 861 passed, 5 skipped, 0 failed**, 0 restarts |

The clean 17.5 run means bug 2 did not happen to fire that time. It is a race, and it is **not
fixed**.

---

## 4. Bug 2: a cross-actor model write races SwiftData's main-thread observer

### 4.1 The crash signature (identical across all 10 crash reports)

```
Exception:  EXC_BAD_ACCESS (SIGSEGV)
Subtype:    KERN_INVALID_ADDRESS at 0x8000000000000010
Thread:     0, com.apple.main-thread
Register:   x8 = 0x8000000000000000   (far = x8 + 0x10)

 0  SwiftData  +0x33a18
 1  SwiftData  +0x2dcc4
 2  SwiftData  +0x26c0
 3  SwiftData  +0x15f0
 4  SwiftData  +0x167c
 5  CoreFoundation  __CFRUNLOOP_IS_CALLING_OUT_TO_AN_OBSERVER_CALLBACK_FUNCTION__
 6  CoreFoundation  __CFRunLoopDoObservers
 7  CoreFoundation  CFRunLoopRunSpecific      (one report: __CFRunLoopRun)
 8  XCTestCore      +[XCTWaiter _synchronouslyWaitForTimeInterval:]
 …  XCTestCore      +[XCTFailableInvocation invokeWithAsynchronousWait:…]   ← async test body
 …  UIKitCore       UIApplicationMain  ←  Repster  RepsterApp.$main()
```

The SwiftData frames cannot be symbolicated (no exported symbols). The simulator runtime is
iOS 17.5 for all ten (device `4CB40DB5…`, iPhone 15 Pro).

**This is the same fingerprint as the production crash.** The 1.3 / TestFlight 1.4 (6) crashes
in [SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md §2.3](SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md) fault at
the same `0x8000000000000010`, with the same poisoned `0x8000000000000000` in a register. That
crash was a Swift dictionary inside SwiftData being read on one thread while another thread
replaced its storage. The first version of this document called the two signatures different.
The main-thread frames differ (observer here, property getter there), but the fault is the same.

### 4.2 The second thread: what the first version missed

Every SIGSEGV report has a **second thread**, on the Swift cooperative pool, that is **inside a
SwiftData model setter** at the moment of the crash. In 8 of 10 reports it is blocked in
`-[NSManagedObjectContext performBlockAndWait:]` → `_dispatch_sync_f_slow`. It is waiting for
the queue that the main thread is running the observer on.

| Report | Concurrent writer (cooperative thread) | Called from |
|---|---|---|
| `101406` | `WorkoutSet.prStatus.setter` ← `PRService.recomputeFrontierBadges` | `AffectedSetsPreconditionTests` via `SetService.save` |
| `101747`, `101749`, `102013` | `ExerciseStats.totalSets.setter` ← `StatsService.handleSave` | `ScreenDataGoldenMasterTests.makeFixture`, `AffectedSetsPreconditionTests` via `SetService.save` |
| `101751` | `WorkoutSet.prStatus.setter` ← `PRService.recomputeFrontierBadges` | `ScreenDataGoldenMasterTests.makeFixture` |
| `101758` | `ExerciseStats.totalWorkouts.setter` ← `StatsService.handleSave` | `ScreenDataGoldenMasterTests.makeFixture` |
| `101806` | `WorkoutSet.prStatus.setter` ← `PRService.rebuildAll` | `WorkoutHistoryBackupService.restoreBackup` |
| `101812` | `ExerciseStats.totalWorkouts.setter` ← `StatsService.handleDelete`, **allocating a Swift `Set` inside SwiftData** | `ActiveWorkoutViewModel.replaceExercise` |
| `102201` | `PerformanceRecord.value.setter` ← `PRService.findNewPROwner`, **scheduling an `NSTimer` inside SwiftData** | `ActiveWorkoutViewModel.deleteSet` |
| `104119` (run E) | `WorkoutSet.prStatus.setter` ← `PRService.recomputeFrontierBadges` | `AffectedSetsPreconditionTests` |

The pattern is the one the August work banned. A plain `actor` service fetches a live `@Model`
from a `@ModelActor` repository, mutates it on **its own** executor, and hands it back to save.
[PRService.swift:625-628](Repster/Core/Services/PRService.swift:625) is typical:

```swift
if let owningSet = try await setRepo.fetch(byId: record.setId) {
    if owningSet.prStatus != desiredStatus {
        owningSet.prStatus = desiredStatus          // written on PRService's executor
        try await setRepo.save(owningSet)
```

`StatsService.handleSave` / `handleDelete` do the same to `ExerciseStats`
([StatsService.swift:259-306](Repster/Core/Services/StatsService.swift:259), and `:341-414`).
`PRService` writes `prStatus` / `value` at `:113, :119, :250, :287, :309, :333, :348, :470, :539,
:557, :627, :686, :701`.

**Why the main thread is involved.** All five crashing classes are `@MainActor`
(`PipelinePerformanceTests.makeStack` is `@MainActor`). So they construct the `@ModelActor`
repositories on the main thread, and each repository's `ModelContext` is created there. On
iOS 17.5, SwiftData treats that context as a main-thread context. Its run-loop observer runs
on the main thread, and `performBlockAndWait` dispatches to the main queue. The model setter
does its own bookkeeping first, on the calling thread: it inserts into a Swift collection (report
`101812`) and schedules a timer (report `102201`). Only then does it wait for the main queue. The
observer reads the same state with no lock. That is a data race. The main thread loses it and
dereferences a torn pointer.

**Why the victim rotates.** It is a race inside whichever test is saving while XCTest spins the
main run loop. It is not state leaking from an earlier test. Run E crashed with one test in the
process.

**The discriminator.** `SetServiceTests` is **not** `@MainActor`. Its repositories are built
inside `async` test bodies, off the main thread. It drives the same `SetService.save` →
`StatsService` / `PRService` write paths (46 tests, 86 save calls) and has **never** segfaulted.

**Measured since (§9):** on iOS 17.5 the crash needs **both** conditions. The repository must be
built on the main thread, and the model must be written by an actor other than its owner. Take
either away and it stops. A 20-line synthetic probe with no app services reproduces it with the
identical signature. What remains unknown is which SwiftData structure is torn, because the
frames are unsymbolicated.

### 4.3 Which tests crashed

| Run A (full suite) | Run B (isolated, with share work) | Run C (baseline, without it) |
|---|---|---|
| `AffectedSetsPreconditionTests.testAffectedSetEntriesArriveAlreadyAppliedToTheHeldInstances` | `AffectedSetsPreconditionTests.testAffectedSetEntriesArriveAlreadyAppliedToTheHeldInstances` | `AffectedSetsPreconditionTests.testAffectedSetEntriesArriveAlreadyAppliedToTheHeldInstances` |
| `PipelinePerformanceTests.testLoggingPipelineStaysWithinItsLatencyBudget` | `ScreenDataGoldenMasterTests.testCalendarDotsGoldenMaster` | `PipelinePerformanceTests.testLoggingPipelineStaysWithinItsLatencyBudget` |
| `ScreenDataGoldenMasterTests.testHomeExcludesInProgressWorkouts` | `ScreenDataGoldenMasterTests.testHomeActiveWorkoutDetectionGoldenMaster` | `ScreenDataGoldenMasterTests.testHomeActiveWorkoutDetectionGoldenMaster` |
| `ScreenDataGoldenMasterTests.testHomeWeekStripAndActivityGoldenMaster` | `ScreenDataGoldenMasterTests.testHomeExcludesInProgressWorkouts` | `WorkoutHistoryBackupArchiveServiceTests.testBackupPreservesUnilateralRepTargetModeMetadata` |
| `WorkoutHistoryBackupArchiveServiceTests.testCheckedInV1ArchiveStillPreviewsAndRestores` | `ScreenDataGoldenMasterTests.testHomeWeekStripAndActivityGoldenMaster` | `WorkoutHistoryBackupArchiveServiceTests.testRestoreBackupReplacesHistoryAndKeepsUnrelatedData` |
| `WorkoutHistoryBackupArchiveServiceTests.testTemplateStartWorkoutOptionsPersistProgressionHistoryChoice` | `WorkoutHistoryBackupArchiveServiceTests.testCheckedInV1ArchiveStillPreviewsAndRestores` | `WorkoutJourneyTests.testDeletingASetRemovesItFromTheHistoryTabWithoutSwitchingExercise` |
| `WorkoutJourneyTests.testDeletingAMiddleSetClosesTheOrderGapAndSurvivesRelaunch` | `WorkoutJourneyTests.testReplacingAnExerciseRemovesItsSetsFromTheStore` | `WorkoutJourneyTests.testWarmupSetIsPlacedFirstAndTheReindexSurvivesRelaunch` |
| `WorkoutJourneyTests.testHistorySubTabShowsPastSessionsNewestFirst` | — | — |

`testAffectedSetEntriesArriveAlreadyAppliedToTheHeldInstances` crashes every time because it
does the most saves through `PRService.recomputeFrontierBadges`, which gives the race the
widest window. XCTest reports these as "Test crashed with signal segv" or "Crash: Repster at
&lt;external symbol&gt;".

**Caveat, added after §10.2:** most of these crashes left no `.ips` (§4.4), so their cause was
inferred from the others. `testHistorySubTabShowsPastSessionsNewestFirst` (run A) later crashed
on iOS 18.6 as **bug 3**. Some entries in this table may be bug 3 rather than bug 2.

### 4.4 Crash report inventory

All reports are in `~/Library/Logs/DiagnosticReports/Repster-2026-09-11-10*.ips`. macOS prunes
these eventually.

| Run | `SIGSEGV` (bug 2) | `SIGABRT` (bug 1) |
|---|---|---|
| A (10:12–10:16) | `101406` | `101529`, `101530`, `101531`, `101537`, `101539` |
| B (10:17–10:19) | `101747`, `101749`, `101751`, `101758`, `101806`, `101812` | `101801`, `101803`, `101804`, `101808`, `101809` |
| C (10:19–10:22) | `102013`, `102201` | `102106`, `102108`, `102109`, `102158`, `102159` |
| E (10:41) | `104119` | — |

The reports are incomplete for bug 2: run A had 8 bug-2 crashes but only 1 report, and run C had
7 but only 2. The simulator appears to rate-limit repeated reports.

### 4.5 Does it affect the app?

Yes, **on iOS 17 devices**, which today is one active user. It was observed once: version 1.3
crashed on that user's iOS 17.5.1 device during the final onboarding write (§11.1). *(Corrected
2026-09-12, see §11/§12.)* The synthetic bug-2 race ran 20,000 cross-actor writes without a crash
on both iOS 18.6 (§10.1) and iOS 26.3.1 (§9), so that specific write mechanism looks confined to
iOS 17.
- `RepsterApp.init()` builds every repository on the main thread
  ([RepsterApp.swift:38](Repster/App/RepsterApp.swift:38) → `RepositoryContainer`). That is the
  same construction as the crashing test classes.
- The racing writes (`PRService` badge recompute, `StatsService` totals) run on **every set
  save**, and the app's main run loop spins constantly, not only during `XCTWaiter` waits.
- The deployment target is **iOS 17.0**, so users on 17.x run the SwiftData that crashes here.
- **Checked in PostHog on 2026-09-11.** These are distinct iOS users over 30 days (on
  `Application Opened`, `$screen` and workout events); no standard PostHog metric for this exists,
  so the numbers are my own query:

  | iOS | Users | Events |
  |---|---|---|
  | 26 | 139 | 2,892 |
  | 18 | 10 | 260 |
  | 27 | 2 | 13 |
  | **17** | **1** | **1** |

  **The confirmed exposure (iOS 17) is one user (on 17.5.1).** iOS 18 was checked afterwards on
  the 18.6 simulator: bug 2 does not reproduce there (§10.1).
- **PostHog cannot see this crash.** The project has no `$exception` events in the last 30 days,
  so crashes are not reaching PostHog error tracking. Xcode Organizer is the only place to look:
  1.5 crashes at `0x8000000000000010` where the main thread is in `__CFRunLoopDoObservers`.

### 4.6 Scope of a fix, and the decision

**Decision (2026-09-11, superseded 2026-09-12):** the original decision was not to fix bug 2
without device evidence. Organizer then showed the onboarding crash, so Phase 1 moved all 20
profile writes into `HealthProfileRepository` and is built and verified. Phases 2–3 retain the
remaining 27 sites. *(Corrected 2026-09-12, see §11/§12.)*

**The rule a fix would complete.** From the August work: pass ids and `Sendable` values across
the actor boundary, and let the `@ModelActor` fetch and change its own models. Reads were
converted in August. These writes were not.

#### What is in scope: 47 write sites in 7 services (audited from the code)

Each site does this: a plain `actor` service fetches a saved model from a repository, changes
it, and passes it back to `repo.save(model)`.

| Service | Sites | Models | When it runs |
|---|---|---|---|
| `PRService` | 13: 7 × `WorkoutSet.prStatus` (`:113, :348, :470, :539, :557, :627, :701`), 6 × `PerformanceRecord` (`:119, :250, :287, :309, :333, :686`) | WorkoutSet, PerformanceRecord | Every set save, edit or delete |
| `StatsService` | 3 blocks, about 25 field writes: `handleSave` (`:259-311`), `handleEdit` (`:322-378`), `handleDelete` (`:388-419`) | ExerciseStats | Every set save, edit or delete |
| `SettingsService` | 17: `fetchOrCreate()` → set one field → `save(profile)` (`:50-170`) | HealthProfile | Settings toggles; all moved owner-side in Phase 1 |
| `FatigueLearningService` | 8: `processSessionEnd` (`:420`, `:752`), `resetLearning` (`:448`), `resetLearnedRatesPreservingHistory` (`:477`, `:486`), `resetAllLearning` (`:505`, `:517`), `applyManualNudge` (`:650`) | Exercise, HealthProfile | Workout finish, settings |
| `WorkoutService` | 3: `finishWorkout` (`:75-91`), `updateWorkoutMetadata` (`:186-189`), `updateProgressionHistoryExclusions` (`:207-212`) | Workout | Finish workout |
| `TemplateService` | 2: `updateTemplate` (`:212-217`), `lastUsedAt` in `startWorkoutFromTemplate` (`:317-319`) | WorkoutTemplate | Template edit and start |
| `BodyweightService` | 1: `updateEntry` changes a model passed in by the caller (`:37`) | BodyweightEntry | Bodyweight edit |

The test crash reports in §4.2 have writers in `PRService` or `StatsService`, but the real-device
writer was `SettingsService`. Therefore the original options B and C below would not have covered
the observed device crash. *(Corrected 2026-09-12, see §11/§12.)*

#### What is out of scope, and why

| Pattern | Why it's excluded | Evidence |
|---|---|---|
| Services **reading** repository-owned models | They do not reproduce bug 2's iOS 17 observer race, but held reads can trigger bug 3 and belong to Phases 4–6 | §9.4b R1/R2 were clean because each read fetched after the swap; corrected by §11.2 |
| `@MainActor` writes (ViewModels, `SetRowWrapper` keystrokes, `SetService`) | Repositories run on the main thread (P0), so these writes share the owner's thread and cannot race the main-thread observer | P0; no crash report ever showed a main-thread writer |
| Inserting brand-new models (about 10 sites) | A new model has no context until it is inserted, so there is nothing to race | By construction |
| Deletes via `repo.delete(model)`; services with their own context (`InsightsService` is a `@ModelActor`; `ImportService`, `WorkoutHistoryBackupService`, `SettingsService.resetAllAppData` create their own `ModelContext`) | The work runs on the context's owner | Code review |
| Turning autosave off | Tested; still crashes | §9.4b R3 |
| Building repositories off the main thread | It only avoided the measured bug-2 race on 17.5 and is not an architectural fix | P0 probe calls plus the context-queue crash reports in §11.2–11.3 |

#### Options

| Option | Change | Covers | Risk |
|---|---|---|---|
| **A. Do nothing (original choice; superseded)** | None. iOS 17.5 stays a known-flaky test runtime | Nothing | The 1 iOS 17 user stays exposed |
| **B. Move two services to the main thread** | `PRService` and `StatsService` become `@MainActor final class` instead of `actor`: about 2 lines | The test writers in §4.2, but not the observed Settings writer | **Untested.** Needs one probe (main-actor writer, iOS 17.5) and a check that the PR/stats rebuild at startup and after restore doesn't hitch the UI |
| **C. Targeted rewrite** | The 16 sites in `PRService` and `StatsService` | The test writers in §4.2, but not the observed Settings writer | Moderate: the hottest path, and the identity dependency below |
| **D. Full fix** | All 47 sites plus source and insert-only guards | The whole pattern | Most work; the lower-traffic sites are largely mechanical |

#### How C or D would be built, if chosen

1. **One generic helper**, written once as an extension on SwiftData's `ModelActor` protocol, so
   all 11 repositories get it:
   `func update<M: PersistentModel>(_ id: PersistentIdentifier, _ body: @Sendable (M) -> Void) throws`.
   This is the P2 shape (§9.1): the write runs inside the repository that owns the model.
2. **Mechanical sites** (all of `SettingsService`, `TemplateService`, `WorkoutService` and
   `BodyweightService`, plus the `FatigueLearningService` resets; about 30): the body moves
   into the closure unchanged.
3. **Hard sites** (`PRService`, `StatsService`): some writes wait on async work partway through
   (`StatsService` edit and delete call `recomputeMaxWeight` mid-update). These need "compute
   the new values first, then apply them in one closure".
4. **Identity dependency.** `applyAffectedSets` relies on `PRService` changing the very
   `WorkoutSet` instance the ViewModel holds. Writing inside `SetRepository` keeps the same
   context and instance. `AffectedSetsPreconditionTests` guards this; keep it green on every
   runtime.
5. **Guard against regression (corrected 2026-09-12, see §11/§12):** Xcode 26.3's `@Model`
   macro itself adds `Sendable`, so the original statement that these types already conform is
   correct on the current toolchain. Removing the project's redundant explicit
   `@unchecked Sendable` conformances will not make actor crossings fail compilation. The
   replacement is `SwiftDataLiveModelBoundaryRatchetTests`, plus the Phase 3 rename from
   `save(_:)` to insert-only APIs with DEBUG `assert(model.modelContext == nil)` checks.

**Verification:** `AffectedSetsPreconditionTests` × 20 on iOS 17.5 (crashes every run today);
`SetServiceTests` with its database built on main (crashes today, §9.3); full suite on 17.5,
18.6 and 26; and a device pass on set logging, PR badges and finish workout. The August notes
warn that a green suite is weak evidence on this path.

**Size:** one to two focused sessions; `PRService` is about half of it.

**What not to do:** don't "fix" the tests by removing `@MainActor` from the test classes or
building test repositories off main. That hides the race in tests while the app keeps the
production construction.

**Also recommended regardless:** add iOS 17.5 as a second test destination, since it is the
oldest supported runtime and it found bugs 1 and 2. Every run record should name the device
and OS.

### 4.7 Hypotheses from the first version, retired

- **"A container is freed while an observer survives" (use-after-free, cross-test leak).**
  Contradicted by run E, where one test alone crashed. Also, nothing in the ten reports shows a
  deallocation. What they show is a live concurrent write.
- **"The test drops an intermediate container during a relaunch."** Not needed. The victims
  include tests with no relaunch (`ScreenDataGoldenMasterTests`, `AffectedSetsPreconditionTests`).
- **"The host app's own `mainContext` / startup maintenance."** Not ruled out as a contributor,
  but the concurrent writer is always the test's own stack. Skipping host-app setup under XCTest
  is still reasonable hygiene, but it is not the fix.

---

## 5. Reproducing

**The runtime matters.** `name=iPhone 15 Pro` alone fails on this machine ("Unable to find a
device"), because xcodebuild defaults to the latest OS and that device exists only on 17.5.
Always pass the OS.

**The seven affected classes, iOS 17.5** (about 2 minutes):

```bash
xcodebuild -project Repster.xcodeproj -scheme Repster -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5' test -only-testing:RepsterTests/AffectedSetsPreconditionTests -only-testing:RepsterTests/SetServiceTests -only-testing:RepsterTests/WorkoutHistoryBackupArchiveServiceTests -only-testing:RepsterTests/WorkoutHistoryBackupServiceTests -only-testing:RepsterTests/WorkoutJourneyTests -only-testing:RepsterTests/ScreenDataGoldenMasterTests -only-testing:RepsterTests/PipelinePerformanceTests > test.log 2>&1
```

**Bug 2 alone, fastest repro:**

```bash
xcodebuild -project Repster.xcodeproj -scheme Repster -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5' test -only-testing:RepsterTests/AffectedSetsPreconditionTests/testAffectedSetEntriesArriveAlreadyAppliedToTheHeldInstances -test-iterations 10 > test.log 2>&1
```

After a crash, XCTest does not resume the remaining iterations. One crash ends the run.

**Authoritative totals and failures** from the result bundle (the path is printed near the end
of `test.log`):

```bash
xcrun xcresulttool get test-results summary --path "<path>.xcresult"
```

**Rules that matter here:**
- Run `xcodebuild test` one run at a time.
- `Restarting after unexpected exit, crash, or test timeout` in the log means a crash. The test
  on the last `started` line before it is the victim.
- For bug 2, open the `.ips` and look at the **other** threads, not only the crashed one. The
  concurrent writer is what identifies the cause.
- To prove a failure isn't caused by your change, build a throwaway worktree at `HEAD`, apply
  only the uncommitted diff you want to keep, and run the same classes.

---

## 6. Evidence locations (2026-09-11)

| What | Where | Lasts? |
|---|---|---|
| Run A result bundle | Already gone from DerivedData at revision time | Gone; its failures are in §3.1 and §4.3 |
| Run B result bundle | `~/Library/Developer/Xcode/DerivedData/Repster-hjxdomcocdypqyaozeksllqltljz/Logs/Test/Test-Repster-2026.09.11_10-17-07-+0200.xcresult` | Until DerivedData is cleaned |
| Run C result bundle | Deleted along with the throwaway worktree | Gone |
| Run D result bundle (iOS 26.3.1, 122/122) | `…/Logs/Test/Test-Repster-2026.09.11_10-40-10-+0200.xcresult` | Until DerivedData is cleaned |
| Run E result bundle (solo repeat) | `…/Logs/Test/Test-Repster-2026.09.11_10-40-50-+0200.xcresult` | Until DerivedData is cleaned |
| Crash reports: bugs 1 and 2 (iOS 17.5) | `~/Library/Logs/DiagnosticReports/Repster-2026-09-11-10*.ips` and `…-11*.ips` | Until macOS prunes them |
| Crash reports: bug 3 (iOS 18.6) | `~/Library/Logs/DiagnosticReports/Repster-2026-09-11-120238.ips` (crash A) and `…-120357.ips` (crash B) | Until macOS prunes them. The stacks that matter are quoted in §10.2 |
| Bug-1 fix verification bundles (real tree) | `…/Logs/Test/` in the project's DerivedData, 2026-09-11 afternoon | Until DerivedData is cleaned; the results are in §3.6 |
| Experiment code (§9, §10) | **Appendix A of this file.** The throwaway worktrees were deleted | Permanent |

---

## 7. Appendix: why a red run can look green

Each crash ends the test process. XCTest relaunches it and carries on from the next test, and
**each relaunch prints its own "Executed N tests, with 0 failures" tallies** for the classes it
ran. In run A, the last lines of the log read "Executed 108 tests, with 1 test skipped and 0
failures" immediately before `** TEST FAILED **`. That 108 is just the final relaunch's share of
866. The real result (13 failures) exists only in the `.xcresult` summary and the
`** TEST FAILED **` line.

---

## 8. What the verification pass changed

1. **Added the runtime.** All original runs were iOS 17.5. A new iOS 26.3.1 run passes 122/122.
   This also explains the recorded clean 814-test run on 2026-09-05.
2. **Replaced bug 2's diagnosis.** It was "use-after-free, root owner unknown". Every crash
   report shows a concurrent cross-actor model write in `PRService` or `StatsService`. The old
   hypotheses are retired in §4.7.
3. **Corrected "different signature".** Bug 2 has the production crash's fault address and
   poisoned register.
4. **Corrected "doesn't affect the app".** The app uses the same main-thread repository
   construction and the same write paths. iOS 17 users are plausibly exposed.
5. **Fixed the repro command.** It lacked `OS=17.5` and does not run as written.
6. **Smaller fixes.** `SetServiceTests` line numbers are call sites, not declarations. The run A
   bundle is gone. One of the nine original reports differs at frame 7.
7. **Ran the confirming experiments** (§9). Both predictions held, the mechanism was reproduced
   from scratch, the fix direction was validated, and the bug-1 fix was verified.
8. **Applied the bug-1 fix** to the real tree, using the app's shared model list (§3.6).
9. **Measured exposure in PostHog** (§4.5): iOS 17 has 1 active user, iOS 18 has 10.
10. **Tested iOS 18.6** (§10). Bug 2 is absent there, and bug 3 was found.
11. **Recorded the bug-2 scope and decision** (§4.6): 46 audited sites, options A–D, and
    "not fixing now".

---

## 9. Experiments (2026-09-11)

Everything ran in a throwaway git worktree: `HEAD` + the user's uncommitted diff + the changes
below. Runs used one build (`build-for-testing`) and one `test-without-building` invocation at a
time. Variants were switched with `TEST_RUNNER_PROBE_*` environment flags, so each experiment and
its control ran the same binary. Totals come from `.xcresult`. After a crash, XCTest does not
resume `-test-iterations`, so "crashed" means it crashed before the iterations finished.

### 9.1 Synthetic probe: real `ExerciseStats` models, no app services

A `@ModelActor ProbeStatsRepo` shaped exactly like `ExerciseStatsRepository` (`fetch(for:)`,
`save(_:)`), plus:
- `bumpInside(exerciseId:)`: the owning actor fetches and mutates its own model (the fix shape)
- `actor ProbeMutator.bumpOutside(repo, exerciseId:)`: `StatsService.handleSave`'s shape. It
  fetches from the repo, mutates on its own executor, and calls `repo.save(model)`.

Each hammer test does 2,000 writes from a `@MainActor` test, as the crashing classes do.

| Probe | Repo built on | Who writes | iOS 17.5 | iOS 26.3.1 |
|---|---|---|---|---|
| P0: where code runs | — | — | Repo built on main runs **on main**. Repo built off main runs **off main**. Plain actor runs off main (3/3 runs) | Repo runs **on main wherever it was built**. Plain actor runs off main (3/3 runs) |
| P1 | main | plain actor | **Crashed, 4/4 invocations**, identical signature (`SwiftData+0x33a18`, `0x8000000000000010`, run-loop observer), writer `ProbeMutator.bumpOutside` | 10 iterations, 20,000 writes, **no crash** |
| P2 | main | owning actor | 10 iterations, 20,000 writes, **no crash** | 5 iterations, no crash |
| P3 | off main | plain actor | 10 iterations, 20,000 writes, **no crash** | — |
| P4 | off main | owning actor | 10 iterations, 20,000 writes, no crash | — |

**Reading:**
- On iOS 17.5 the crash needs **both** a main-built repository and a cross-actor write (P1 vs
  P2/P3).
- P2 is safe because a main-built repository runs its own code on the main thread (P0), in step
  with SwiftData's observer. That is why moving writes into the owning actor works *even though
  the app builds its repositories on main*.
- P3 is safe here only because the probe is strictly sequential. It is still a cross-actor write,
  so don't read it as a green light.
- On iOS 26 the race does not reproduce.

**P0 qualification:** the probe reported that an off-main-built `@ModelActor` ran on main on
iOS 26, and that the app's main-built repositories ran on main on iOS 17.5. Later bug-3 crash
reports show repository work on `NSManagedObjectContext` queue threads while main was reading,
on both iOS 18.6 and 26.3.1. P0 therefore describes those probe calls, not a guarantee about every
repository operation. *(Corrected 2026-09-12, see §11.2–11.3.)*

### 9.2 Real code: `AffectedSetsPreconditionTests` (iOS 17.5)

`PROBE_REPOS_OFF_MAIN=1` builds the container and all nine repositories in `Task.detached`.
Services and the `@MainActor` `SetService` are unchanged.

| Run | Result |
|---|---|
| R1 control (flag off), `-test-iterations 5` | **Both tests crashed.** Writer: `StatsService.handleSave` → `ExerciseStats.totalSets.setter`. `testDeletingAPROwnerPromotesAnotherSetThroughIdentityAlone` had not been seen crashing before |
| R2 flag on, `-test-iterations 20` | **40/40 passed, 0 crashes.** The test's measurements match the control's: 4 `affectedSetIds` entries, 1 would be suppressed |

### 9.3 Real code: `SetServiceTests`, the converse (iOS 17.5)

`PROBE_REPOS_ON_MAIN=1` runs the unchanged `makeContext()` body via `DispatchQueue.main.sync`. The
test bodies stay nonisolated.

| Run | Result |
|---|---|
| R3 control (flag off), `-test-iterations 3` | **46/46 passed**, 0 crashes (includes the three bug-1 tests, now fixed) |
| R3 flag on, `-test-iterations 3` | **2 tests segfaulted** (`testEditClearsE1RMButKeepsTheStoredFormulaVersion`, `testSaveDoesNotStampUpdatedAtButEditDoes`), neither ever seen crashing. No `.ips` was written (the simulator was rate-limiting), so the evidence is XCTest's "crashed with signal segv" |

### 9.4 Full suite with the bug-1 fix applied (no flags)

| Run | Result |
|---|---|
| F1: iPhone 15 Pro, iOS 17.5 | 866 tests: 858 passed, 6 skipped, 2 failed. One is bug 2 (`WorkoutJourneyTests.testEditingAFinishedWorkoutUpdatesTheSetAndItsStats`, segv; only one bug-2 crash this run, against 7–8 before, since it is a race). The other is the artifact below. **No bug-1 failures** |
| F2: iPhone 17 Pro, iOS 26.3.1 | 866 tests: 860 passed, 5 skipped, 0 crashes. The only failure is the artifact below |

**The artifact:** `ReplayMaskCoverageTests.testEveryTextInputIsClassified` fails in any worktree
under `/private/tmp`. Its path stripping produces `/privateFeatures/...` and flags every text
field. Run from the real tree it passes 3/3. It is not a product failure. It is worth knowing
before anyone reruns this from a scratch worktree.

### 9.4b Reads, and autosave (iOS 17.5, repo built on main, 2,000 rounds per iteration)

| Probe | Result |
|---|---|
| R0: plain actor fetches, writes, `repo.save` (the control) | **Crashed, 2/2 invocations** |
| R1: plain actor fetches and **reads** fields only | 10 iterations, no crash |
| R2: plain-actor **reads** while the owning repository writes and saves concurrently | 10 iterations, no crash |
| R3: the R0 write shape with `modelContext.autosaveEnabled = false` on the repository | **Still crashed** |

**Reading:**
- Cross-actor **reads** do not reproduce the crash. Only writes do.
- Turning autosave off is **not** a fix. It stays a relevant clue: the crashing setter was
  seen scheduling SwiftData's `checkAutosaveConditions` timer from the background thread
  (register `x3` of the R0 report).

### 9.5 What this settles

1. Bug 2's mechanism is confirmed by experiment. The crash needs a main-built context plus a
   write from a non-owning actor. It is reproducible in about 20 lines with no app code.
2. The fix direction, writes inside the owning repository actor, is validated on both runtimes
   (P2) without changing where the app builds its repositories.
3. Bug 1's minimum fix works on iOS 17.5.
4. iOS 26.3.1 shows neither bug, and iOS 18.6 does not show bug 2 (§10.1). Bug 2's exposure is
   iOS 17.x.

---

## 10. iOS 18.6 (2026-09-11)

The iOS 18 users over 30 days are on 18.7.x (7), 18.6.2 (1, the most active: 189 events), 18.4.1
(1) and 18.0.1 (1). The runtime tested is the iOS 18.6 simulator (iPhone 16 Pro), in a throwaway
worktree of the current tree.

### 10.1 Bug 2 does not reproduce on 18.6

| Run | Result |
|---|---|
| P0: where code runs | The probe calls ran on main wherever the repositories were built; later crash reports show repository operations can run on context queues while main reads (§11.2–11.3) |
| P1: plain-actor writes into a main-built repo | 10 iterations, 20,000 writes, **no crash** (17.5: crashes on iteration 1) |
| R0: the same write shape through `repo.save` | 10 iterations, **no crash** |
| R1 / R2: cross-actor reads, alone and during owner writes | 10 iterations each, no crash |
| `AffectedSetsPreconditionTests`, `-test-iterations 10` | 20/20 passed (17.5: crashes every run) |

**Bug 2 is effectively iOS 17 only: one active user (on 17.5.1).**

### 10.2 A different crash found on 18.6 ("bug 3"): reading a held live model while its owner saves it

The 18.6 full suite: 870 tests (866 plus 4 probe tests), 863 passed, 5 skipped, 2 failed. One is
the `/private/tmp` ReplayMask artifact (§9.4). The other is a segfault with a **different
signature** from bug 2:

| | Crash A (`120238`) | Crash B (`120357`) |
|---|---|---|
| Fault | `EXC_BAD_ACCESS` at **`0x10`** | same |
| Victim test | `WorkoutJourneyTests.testHistorySubTabShowsPastSessionsNewestFirst` (full suite) | `WorkoutJourneyTests.testBothHistoryLoadersMarkTheSameExcludedSession` (journey class ×5) |
| **Reader** | Main thread, reading the live `Workout.excludedExerciseIdsFromProgressionHistory` in `SuggestionCoordinator.workoutProgressionHistorySignature` (`WeightSuggestionData.swift:634`) ← `cacheKey` ← `prepare` ← `ActiveWorkoutViewModel.performWeightSuggestionRefresh` (`:2260`) | Cooperative thread: `LoadPrescriptionService.peakAcrossRecentWorkouts` (`:327-339`) reading `WorkoutSet.reps` via `prReps` ← `evaluateSuggestions` ← `performWeightSuggestionRefresh` (`:2273`) |
| **Concurrent owner action observed** | The first `WorkoutRepository.fetch(byIds:)` after creation, on its context queue, runs `Workout.persistentBackingData.setter` and frees the old backing data (`swift_deallocClassInstance` fatal on that thread) | Main thread: the first `SetRepository.fetchChartSets(for:)` after the sets were saved, via `SetService.supersetPartnerNames` ← `ActiveWorkoutViewModel.loadHistoryForCurrentExercise` (`:1972`), runs `WorkoutSet.persistentBackingData.setter` |

**Mechanism, corrected by the probes in §11.2:**
- One piece of code holds a *live* `@Model` instance and reads it.
- The owning repository saves that record, or performs the first fetch after saving a newly
  created record. SwiftData 18 can swap the held instance's backing data and free the old one
  under the reader. A different context's save and later ordinary re-fetches keep it.
- Both reports above happened on the first post-create fetch case. *(Corrected 2026-09-12, see
  §11.2.)*
- Both reports are in the **weight-suggestion refresh**, which runs during a workout. That is
  the "live models held across actors" class from August (`SWIFTDATA_CRASH_WORK_RECORD.md`),
  seen from a new angle.

**Frequency:**
- **iOS 18.6:** 1 crash in the full suite, then 1 in 2 × 5 iterations of `WorkoutJourneyTests`
  (360 test executions).
- **iOS 26.3.1:** 0 crashes in 2 × 5 iterations of the same class, plus 3 clean full suites.

**Reproduced synthetically with in-memory stores.** The 2026-09-12 held-model controls reproduce
both the backing replacement and the crashes on iOS 18.6; the older R2 probe was clean because
its reader fetched the row itself after the swap instead of holding it beforehand. The journey
tests and every dedicated control use in-memory containers. *(Corrected 2026-09-12, see §11.2.)*

**Possible mis-attribution on 17.5:** runs A–C had bug-2 crashes with no `.ips` (rate-limited),
and `testHistorySubTabShowsPastSessionsNewestFirst` was among them in run A. Some of those may
have been this bug, not bug 2.

**Exposure:** iOS 18 is 10 active users (about 7%), and crash A's reader is on the main thread
during a live workout. PostHog records no `$exception` events, so only Xcode Organizer can say
whether it happens on devices. No device bug-3 crash has been seen. Both observed readers were
converted to snapshots in Phase 4; live sets held by the workout screens remain for Phase 5.
*(Corrected 2026-09-12, see §11/§12.)*

---

## 11. Reproduction harness (2026-09-12)

`RepsterTests/LiveModelRaceReproTests.swift` holds opt-in controls for bugs 2 and 3, each paired
with discriminators under the same load. Its header lists the markers and commands. Without
markers all 8 tests skip, so a normal suite run is unaffected. Runs were one `xcodebuild` at a
time, and results come from `.xcresult`.

### 11.1 Bug 2

**Device evidence** (found 2026-09-11 in Xcode Organizer's local cache): 1.3 (3), iPhone13,2,
iOS 17.5.1, 2026-08-14, 23 seconds after launch. The main thread is in SwiftData's run-loop
observer at `0x8000000000000010`. The writer thread is
`SettingsService.updatePrescriptionDefaultTargetRIR` ← `OnboardingViewModel.finish()`.

This corrects three earlier statements:
- §4.5 says "It has not been observed". It has, once, on the last onboarding screen.
- §4.6 says "Every observed crash writer is in `PRService` or `StatsService`". The only
  real-user crash is in `SettingsService`.
- §4.6 counts 46 sites. `SettingsService` has 17 save sites, not 16, so the total is **47**.

| Test | iOS 17.5 | iOS 18.6 |
|---|---|---|
| Control: the real `OnboardingViewModel.finish()` and `SettingsService`, repositories built on main | **Crashed 5/5** (SIGSEGV) | Clean 1/1 |
| Discriminator: the same, repositories built off main | Clean 2/2 | — |
| Discriminator: the same writes, made inside the owning actor | Clean 2/2 | — |

The crash needs both a main-built repository and a write from a different actor, on the real
onboarding path, on iOS 17 only. This matches §9.1.

### 11.2 Bug 3: the mechanism

Both bug-3 reports died inside `persistentBackingData.setter`, called from a repository fetch
(`WorkoutRepository.fetch(byIds:)` in crash A, `SetRepository.fetchChartSets(for:)` in crash B).
The swapping thread was in Swift's fatal error for an object "deallocated with non-zero retain
count"; the reader faulted at `0x10`. `testBug3Mechanism_WhenIsBackingDataReplaced` measured,
one step at a time, when SwiftData replaces a model's backing data:

| Step | iOS 17.5 | iOS 18.6 | iOS 26.3.1 |
|---|---|---|---|
| The owner saves a new or changed model | kept | **replaced** | kept |
| The first fetch after a new model was saved | kept | **replaced** | kept |
| Any other fetch, a pending change, another context's save | kept | kept | kept |
| Backing-data type | `_DefaultBackingData` | `_KKMDBackingData` | `_KKMDBackingData` |

So on iOS 18, code that is **holding** a live record when its repository saves it, or first
re-fetches it after creating it, can have the record's storage freed under it.
- Crash A (the workout `startWorkout` created, first re-fetched by the History loader) and crash
  B (sets just logged, first re-fetched by the History loader) are both the second case.
- The first case is the workout screen's normal state: `workout` and `setsByExercise` are live,
  and every set save goes through their repository.

| Control, iOS 18.6 | Result |
|---|---|
| Live sets held by a plain actor and read while `SetRepository` saves them | **Crashed 4/4** |
| The real `LoadPrescriptionService.estimateBaseE1RM` (crash B's stack) while `SetRepository` saves, 40 sets | **Crashed 4/4** |
| A live workout held and read on main (crash A's getter) while `WorkoutRepository` saves it | **Crashed 2/2** |
| Discriminator: the held-sets load, reading `ChartSetData` copies instead | Clean 2/2 |

9 of the 10 crash logs contain Swift's line "Object … of class `KnownKeysDictionary` (or
`_KKMDBackingData`) deallocated with non-zero retain count 2", which is the swapping thread's
fatal error from the real reports. The signal (SIGSEGV, SIGABRT or SIGTRAP) depends on which
thread dies first.

**Why the earlier probes were clean.** A reader that fetches the record itself, or reads a row
seeded by another context, only ever sees it after the swap. Three such harnesses ran 2,000
rounds clean on iOS 18.6: seeded on-disk rows, fresh rows fetched by the reader, and a new
workout re-fetched from another actor. The engine control with 3 sets was also clean over 5,998
calls, because its read window is microseconds long. It crashes with 40 sets.

**Corrections:**
- §10.2 says this class "needs an on-disk store". It doesn't. `WorkoutJourneyTests` uses an
  in-memory store, and so does every control here.
- §9.1 P0 says repositories run on main wherever they are built, on 18.6 and 26. That isn't
  reliable. Crash A's fetch, and the iOS 26 report in §11.3, ran repository work on an
  `NSManagedObjectContext` queue thread while main was reading.

### 11.3 iOS 26 is not immune to the pattern

SwiftData 26 never replaced backing data in the probe, and the held-sets control was clean on
26.3.1 over 223,167 reader passes. But two controls crashed there:

| Control, iOS 26.3.1 | Result |
|---|---|
| `LoadPrescriptionService` while `SetRepository` saves | **Crashed 2/2** (SIGSEGV) |
| A live workout read on main while `WorkoutRepository` saves it | **Crashed 2/2** (SIGSEGV, SIGABRT) |

None of these logs has the "non-zero retain count" line. In report
`Repster-2026-09-12-100109.ips`:
- the main thread faults inside SwiftData under
  `Workout.excludedExerciseIdsFromProgressionHistory.getter` (bad address `0x736e6f69`)
- another thread is inside `performBlockAndWait` on the context
- the writer is in `WorkoutRepository.fetch(byId:)` ← `setHealthKitUUID`

That is the shape of August's crash A (a live record read on main while its repository works on
it on another thread), which shipped on 1.0 to 1.4 (6). The fault address is different.

So the backing-data swap is how iOS 18 fails, but reading a live record outside its owner while
the owner saves it is unsafe on every runtime. Two caveats:
- The harness saves thousands of times a second, far more than the app does.
- `WorkoutJourneyTests` crashed 0 times in 360 runs on 26.

So on iOS 26 this is a hazard, not an observed 1.5 user crash.

On iOS 17.5 the held-sets control was clean, but its reader managed only 203 passes, so that
result says nothing.

### 11.4 Crash reports

macOS keeps about 25 reports per app per rolling day. The 2026-09-11 session used 25, so most
crashes on 2026-09-12 wrote no report. For bug 3 on iOS 18.6, Swift's log line gives the thread
picture instead (§11.2). For bug 2, the thread picture rests on the device report (§11.1) and
the ten 2026-09-11 reports (§4.2).

---

## Appendix A: probe code (§9, §10)

Throwaway test code, **never committed**. To rerun it:
1. Create a throwaway worktree (`git worktree add --detach <dir> HEAD`, then apply your
   uncommitted diff).
2. Append both blocks to an existing, compiled test file (the test target is not a synchronized
   folder, so a new file would need a project entry). `AffectedSetsPreconditionTests.swift` was
   used.
3. Build once with `build-for-testing`.
4. Run one test at a time with `test-without-building -only-testing:RepsterTests/<Class>/<test>
   -test-iterations 10`, passing the device **and OS**.

On iOS 17.5, `testP1…` and `testR0…` crash with bug 2's signature. Everything else passes.

### A.1 Threading probe: P0–P4 (§9.1, §10.1)

```swift
// THROWAWAY investigation probe for TEST_SUITE_FAILURES_INVESTIGATION.md §4.6.
// Lives only in a scratch worktree. Never commit.
//
// Isolates the suspected bug-2 mechanism with real `ExerciseStats` models and a repository
// shaped exactly like `ExerciseStatsRepository`, varying two things only:
//   - where the @ModelActor repository (and so its ModelContext) is created: main vs off-main
//   - who writes the model: the owning repository actor vs a plain actor (StatsService's shape)

@ModelActor
actor ProbeStatsRepo {
    func runsOnMainThread() -> Bool { pthread_main_np() != 0 }

    func fetch(for exerciseId: UUID) throws -> ExerciseStats? {
        let descriptor = FetchDescriptor<ExerciseStats>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        return try modelContext.fetch(descriptor).first
    }

    func save(_ stats: ExerciseStats) throws {
        modelContext.insert(stats)
        try modelContext.save()
    }

    /// The proposed fix's shape: the owning actor fetches and mutates its own model.
    func bumpInside(exerciseId: UUID) throws {
        guard let stats = try fetch(for: exerciseId) else { return }
        stats.totalSets += 1
        stats.totalReps += 5
        stats.totalVolume += 100
        try modelContext.save()
    }

    func totalSets(exerciseId: UUID) throws -> Int {
        try fetch(for: exerciseId)?.totalSets ?? -1
    }
}

actor ProbeMutator {
    func runsOnMainThread() -> Bool { pthread_main_np() != 0 }

    /// `StatsService.handleSave`'s shape: fetch a live model from the repository actor, mutate it
    /// on this actor's executor, hand it back to save.
    func bumpOutside(_ repo: ProbeStatsRepo, exerciseId: UUID) async throws {
        guard let stats = try await repo.fetch(for: exerciseId) else { return }
        stats.totalSets += 1
        stats.totalReps += 5
        stats.totalVolume += 100
        try await repo.save(stats)
    }
}

@MainActor
final class ZZProbeSwiftDataThreadingTests: XCTestCase {
    private let rounds = 2000

    nonisolated private static func makeRepo() throws -> (repo: ProbeStatsRepo, builtOnMain: Bool) {
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, WorkoutSet.self, ExerciseStats.self,
            PerformanceRecord.self, BodyweightEntry.self, HealthProfile.self,
            FatigueObservation.self, FatigueLearningSetAudit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (ProbeStatsRepo(modelContainer: container), pthread_main_np() != 0)
    }

    private func makeRepo(onMain: Bool) async throws -> ProbeStatsRepo {
        let built = onMain
            ? try Self.makeRepo()
            : try await Task.detached { try Self.makeRepo() }.value
        XCTAssertEqual(built.builtOnMain, onMain, "repository was not built where the probe intended")
        return built.repo
    }

    func testP0WhereCodeRuns() async throws {
        let repoBuiltOnMain = try await makeRepo(onMain: true)
        let repoBuiltOffMain = try await makeRepo(onMain: false)
        let a = await repoBuiltOnMain.runsOnMainThread()
        let b = await repoBuiltOffMain.runsOnMainThread()
        let c = await ProbeMutator().runsOnMainThread()
        print("PROBE P0 repoBuiltOnMain.runsOnMain=\(a) repoBuiltOffMain.runsOnMain=\(b) plainActor.runsOnMain=\(c)")
    }

    func testP1CrossActorWriteRepoBuiltOnMain() async throws { try await hammer(onMain: true, inside: false) }
    func testP2InActorWriteRepoBuiltOnMain() async throws { try await hammer(onMain: true, inside: true) }
    func testP3CrossActorWriteRepoBuiltOffMain() async throws { try await hammer(onMain: false, inside: false) }
    func testP4InActorWriteRepoBuiltOffMain() async throws { try await hammer(onMain: false, inside: true) }

    private func hammer(onMain: Bool, inside: Bool) async throws {
        let repo = try await makeRepo(onMain: onMain)
        let exerciseId = UUID()
        try await repo.save(ExerciseStats(exerciseId: exerciseId))
        let mutator = ProbeMutator()

        for _ in 0..<rounds {
            if inside {
                try await repo.bumpInside(exerciseId: exerciseId)
            } else {
                try await mutator.bumpOutside(repo, exerciseId: exerciseId)
            }
        }

        let total = try await repo.totalSets(exerciseId: exerciseId)
        XCTAssertEqual(total, rounds)
        print("PROBE hammer builtOnMain=\(onMain) writeInsideOwner=\(inside) rounds=\(rounds) total=\(total)")
    }
}
```

### A.2 Read and autosave probe: R0–R3 (§9.4b, §10.1)

```swift
// THROWAWAY probe (scratch worktree only): do plain-actor READS of repository-owned models race
// too, or only writes? Repo built on main, as in the app. iOS 17.5.

@ModelActor
actor ReadProbeRepo {
    func autosaveEnabled() -> Bool { modelContext.autosaveEnabled }
    func setAutosave(_ on: Bool) { modelContext.autosaveEnabled = on }
    func fetch(for exerciseId: UUID) throws -> ExerciseStats? {
        let descriptor = FetchDescriptor<ExerciseStats>(predicate: #Predicate { $0.exerciseId == exerciseId })
        return try modelContext.fetch(descriptor).first
    }
    func save(_ stats: ExerciseStats) throws {
        modelContext.insert(stats)
        try modelContext.save()
    }
    func bumpInside(exerciseId: UUID) throws {
        guard let stats = try fetch(for: exerciseId) else { return }
        stats.totalSets += 1
        stats.totalReps += 5
        stats.totalVolume += 100
        stats.updatedAt = Date()
        try modelContext.save()
    }
}

actor ReadProbeReader {
    /// A service's read shape: fetch a live model from the repository, read fields on this actor.
    func readOutside(_ repo: ReadProbeRepo, exerciseId: UUID) async throws -> Double {
        guard let stats = try await repo.fetch(for: exerciseId) else { return 0 }
        return Double(stats.totalSets) + Double(stats.totalReps) + stats.totalVolume
            + stats.updatedAt.timeIntervalSince1970
    }
    func writeOutside(_ repo: ReadProbeRepo, exerciseId: UUID) async throws {
        guard let stats = try await repo.fetch(for: exerciseId) else { return }
        stats.totalSets += 1
        try await repo.save(stats)
    }
}

@MainActor
final class ZZReadProbeTests: XCTestCase {
    private let rounds = 2000

    private func makeRepo() throws -> ReadProbeRepo {
        let container = try ModelContainer(
            for: Schema(ModelContainerSetup.modelTypes),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ReadProbeRepo(modelContainer: container)
    }

    /// Positive control: the known-bad write shape. Should crash on 17.5.
    func testR0ControlCrossActorWrite() async throws {
        let repo = try makeRepo()
        let id = UUID()
        try await repo.save(ExerciseStats(exerciseId: id))
        let other = ReadProbeReader()
        for _ in 0..<rounds { try await other.writeOutside(repo, exerciseId: id) }
        print("PROBE R0 survived rounds=\(rounds)")
    }

    /// Reads only, nothing else writing.
    func testR1CrossActorReadsAlone() async throws {
        let repo = try makeRepo()
        let id = UUID()
        try await repo.save(ExerciseStats(exerciseId: id))
        let reader = ReadProbeReader()
        var sum = 0.0
        for _ in 0..<rounds { sum += try await reader.readOutside(repo, exerciseId: id) }
        print("PROBE R1 survived rounds=\(rounds) sum>0=\(sum > 0)")
    }

    /// Reads from a plain actor WHILE the owning repository writes and saves: the app's normal state
    /// (services read the profile/stats while set saves land).
    func testR2CrossActorReadsDuringOwnerWrites() async throws {
        let repo = try makeRepo()
        let id = UUID()
        try await repo.save(ExerciseStats(exerciseId: id))
        let reader = ReadProbeReader()
        let rounds = self.rounds
        async let writes: Void = {
            for _ in 0..<rounds { try await repo.bumpInside(exerciseId: id) }
        }()
        async let reads: Double = {
            var sum = 0.0
            for _ in 0..<rounds { sum += try await reader.readOutside(repo, exerciseId: id) }
            return sum
        }()
        let (_, sum) = try await (writes, reads)
        print("PROBE R2 survived rounds=\(rounds) sum>0=\(sum > 0)")
    }

    /// Known-bad write shape, but with autosave switched off on the repository's context.
    func testR3CrossActorWriteAutosaveOff() async throws {
        let repo = try makeRepo()
        let defaultAutosave = await repo.autosaveEnabled()
        await repo.setAutosave(false)
        let nowAutosave = await repo.autosaveEnabled()
        let id = UUID()
        try await repo.save(ExerciseStats(exerciseId: id))
        let other = ReadProbeReader()
        for _ in 0..<rounds { try await other.writeOutside(repo, exerciseId: id) }
        print("PROBE R3 defaultAutosave=\(defaultAutosave) autosaveNow=\(nowAutosave) survived rounds=\(rounds)")
    }
}
```

---

## 12. Phase 1 and Phase 4 implementation (2026-09-12)

**Phase 1 — real iOS 17 crash path:** `HealthProfileRepository.update` now performs fetch/create,
mutation, `updatedAt` and save on its own actor. All 17 `SettingsService` writes and three global
profile-learning writes use it. The old external fetch-mutate-save shape remains only in the
marker-gated positive control.

**Phase 4 — both observed bug-3 readers:** `LoadPrescriptionService` now consumes
`HealthProfileSnapshot`, `ChartExerciseData`, `ChartSetData` and `WorkoutSnapshot`.
`ActiveWorkoutViewModel.workout` and `SuggestionCoordinator` use `WorkoutSnapshot`; the active
screen's profile reads are snapshots too. Set and live-workout controls remain in the harness so
later clean runs cannot pass merely because the race stopped reproducing.

**Measured here:**

- Test target build: passed.
- Focused active-workout, suggestion and fatigue suites: passed on iOS 18.6.
- Real onboarding regression: 2,000 rounds, passed on iOS 17.5.
- Real suggestion-engine regression: 2,000 concurrent saves, passed on iOS 18.6.
- Set and workout snapshot stress: 2,000 concurrent saves each, passed on iOS 18.6.

This does **not** close the entire architectural issue. Phase 5 still converts live sets held by
the active/edit workout screens; Phases 2–3 move the remaining non-profile writes into their
repository owners and finish the insert-only DEBUG guard; Phase 6 removes the long tail and
closes the source-ratchet allowlist. The concise
manual and automated gates are in
[SWIFTDATA_LIVE_MODEL_TEST_CHECKLIST.md](SWIFTDATA_LIVE_MODEL_TEST_CHECKLIST.md).

---

## 13. Four tests crash on iOS 17.5 during new-feature testing (2026-09-13)

**Plain summary.**
- **What:** four tests segfault on the iOS 17.5 simulator and pass on 18.6 and 26.3.
- **Cause:** this is **bug 2**, the iOS 17-only cross-actor write race (§4). It is not Phase 5,
  it is not new, and it is not caused by the onboarding polish work.
- **Stack:** the one stack trace captured shows `WorkoutService.finishWorkout` writing
  `Workout.status` from its own actor while SwiftData's main-thread observer reads the same
  state. That writer had not been seen before.
- **Exposure:** a real iOS 17 user goes through the same code whenever they finish a workout or
  save, uncomplete or edit a set. Today that is one active user.
- **Fix:** Phases 2–3 of the fix scope, starting with the three small `WorkoutService` sites.
  Alternatively, drop iOS 17 support.

The crashing tests:

| ID | Test | Added |
|---|---|---|
| T1 | `AffectedSetsPreconditionTests.testAffectedSetEntriesArriveAlreadyAppliedToTheHeldInstances` (`:209`) | c5b52e7, 2026-08-13 |
| T2 | `WorkoutJourneyTests.testUncompletingThenRecompletingASetRestoresStatsAndPR` (`:886`) | c5b52e7 |
| T3 | `WorkoutJourneyTests.testEditingAFinishedWorkoutUpdatesTheSetAndItsStats` (`:1298`) | c5b52e7 |
| T4 | `WorkoutJourneyTests.testEditScreenAddsOnlyTheExercisesNotAlreadyInTheWorkout` (`:1373`) | befacc4, 2026-09-12 |

### 13.1 Reproduction

All runs used the iPhone 15 Pro, iOS 17.5 simulator (id `4CB40DB5…`) unless stated otherwise.
Each ran as one `xcodebuild` at a time. Totals come from `.xcresult`. Load average was 2.9–9.

| Run | Result |
|---|---|
| Full suite (the user's run, 10:06) | 915 tests: 896 passed, 15 skipped, **4 failed (SIGSEGV)**, 4 runner restarts |
| T1–T4 together, once | T3 crashed; the other 3 passed |
| Each test alone, once | 4/4 passed |
| Each test alone, `-test-iterations 10` (a crash ends the run) | **All four crash on their own**: T1 on iteration 5, T2 on 6, T3 on 1, T4 on 6 |
| Each alone ×10 again (T1, T2, T4) | T1 crashed, T2 crashed, T4 survived 10 |
| T1–T4 together ×3, with `-com.apple.CoreData.ConcurrencyDebug 1` | T1 SIGSEGV, T3 crash. Assertions were active (the log shows "multi-threading assertions enabled"), but **no violation was raised** |
| iPhone 16 Pro, **iOS 18.6** (id `B7F9246C…`): T1–T4 together ×3 | 12/12 passed |
| iPhone 17 Pro, **iOS 26.3** (the user's full suite) | 0 failures |
| **Baseline:** worktree at `befacc4^` (b7944c8), T1–T3 together ×5 | T1 and T3 crashed |

**Reading:**
- It is a race: each test crashes on its own, and ordering doesn't matter.
- It depends on the runtime: iOS 17 only.
- It is not new. It already crashes before befacc4. T1 and T3 were crashing on 2026-09-11
  (§4.3, §9.4 F1), before any of the fix work.
- T4 is a new test, but it drives the same complete-set and finish-workout paths. The
  duplicate-exercise change it covers is not involved in the crash.

### 13.2 Stack trace

Only one report was written. It is `~/Library/Logs/DiagnosticReports/Repster-2026-09-13-102312.ips`,
incident `01C458D6`, and the same report is attached to the ConcurrencyDebug run's `.xcresult`.
It comes from T3:

```
EXC_BAD_ACCESS (SIGSEGV)  KERN_INVALID_ADDRESS at 0x8000000000000010

Thread 0  com.apple.main-thread  (crashed)
  SwiftData +0x33a18 / +0x2dcc4 / +0x26c0 / +0x15f0 / +0x167c
  CoreFoundation  __CFRunLoopDoObservers
  XCTestCore      +[XCTWaiter _synchronouslyWaitForTimeInterval:] …

Thread 3  com.apple.root.user-initiated-qos.cooperative
  libdispatch  _dispatch_sync_f_slow
  CoreData     -[NSManagedObjectContext performBlockAndWait:]
  SwiftData    +0x87944 / +0x8b25c / +0x8ee34 / +0x48aa8
  Repster      Workout.status.setter
  Repster      WorkoutService.finishWorkout(_:title:notes:perceivedEffort:durationSecondsOverride:)
  Repster      ActiveWorkoutViewModel.finishWorkout(title:notes:perceivedEffort:)
  RepsterTests WorkoutJourneyTests.testEditingAFinishedWorkoutUpdatesTheSetAndItsStats()
```

- **Main thread:** its frames and fault address are identical to bug 2's signature (§4.1).
- **Writer:** `WorkoutService.finishWorkout` fetches the `Workout` from `WorkoutRepository`, sets
  `status`, `endTime`, `duration`, `title`, `notes`, `perceivedEffort` and `updatedAt` on its
  own actor, then calls `workoutRepo.save(workout)`. This is a new writer; §4.2 only saw
  `PRService` and `StatsService`. It is the Phase 3 `WorkoutService :91` site.
- **Timing:** T3 crashed while *finishing* the workout, before the edit step ran.

**T1, T2 and T4.**
- About 8 crashes today wrote no report, and nothing went to `Retired/`. The throttling cause
  is unknown, and it is not the simple 25-per-day cap.
- T1's writers are already on record from ten reports in §4.2: `PRService.recomputeFrontierBadges`
  → `WorkoutSet.prStatus`, and `StatsService.handleSave` → `ExerciseStats` totals.
- T2's and T4's writers are **inferred from their code paths**, not observed.
- A per-test stack could come from attaching command-line `lldb`. That needs Developer Mode, or
  an admin password prompt on this Mac, so it wasn't done.

**Why ConcurrencyDebug stays silent.** In bug 2, SwiftData itself performs the Core Data access
on the context's queue: the writer thread is inside `performBlockAndWait`. The race is in
SwiftData's own Swift-side bookkeeping, which Core Data's checker never sees. That launch
argument cannot detect bug 2.

### 13.3 Classification: bug 2, the Phases 2–3 writes

- **Same signature** as bug 2 (§4.1).
- **Same two conditions:**
  - Both test classes are `@MainActor`, so they build their repositories on the main thread,
    as `RepsterApp.init` does.
  - A plain-actor service writes a model that one of those repositories owns.
- **Same runtimes:** clean on 18.6 and 26.3, like bug 2 in §10.1.
- **Not Phase 5.** Phase 5 is bug 3: live sets *held* by the workout screens while their
  repository saves them. That fails on iOS 18.6 through the backing-data swap, and on 26 in the
  harness. These four tests are clean on both runtimes. An earlier note that filed these four
  under Phase 5 was wrong.

| Test | App path it drives | Cross-actor writers on that path | Removed by |
|---|---|---|---|
| T1 | Set saves and PR frontier recompute | `PRService` (`WorkoutSet.prStatus`, `PerformanceRecord`), `StatsService` (`ExerciseStats`), observed in §4.2 | Phase 2 |
| T2 | Complete, uncomplete, re-complete a set | `SetService.save` / `uncomplete` → `PRService.evaluate` / `handleDeletion`, `StatsService.updateStats` (inferred) | Phase 2 |
| T3 | Complete a set, finish the workout, edit the set | `WorkoutService.finishWorkout` (observed), then `SetService.edit` → `PRService.evaluateAfterEdit`, `StatsService` | Phase 3 (finish), Phase 2 |
| T4 | Complete a set, finish the workout, add exercises on the edit screen | `WorkoutService.finishWorkout`, `PRService`, `StatsService` (inferred) | Phases 2–3 |

### 13.4 Can a real user hit this?

**Yes, on iOS 17 only, and on core paths:**
- finishing any workout (`WorkoutService.finishWorkout`)
- logging, uncompleting or editing a set (`PRService`, `StatsService`)

The app has the same construction: `RepsterApp.init` builds every repository on the main
thread, and on iOS 17 main-built repositories run on main (§9.1). This is not a test-only
pattern.

Scale:
- **One** active iOS 17 user (PostHog, 30 days to 2026-09-11).
- The only device crash on record is the onboarding one (§11.1), which Phase 1 fixed.
- Organizer shows no device crash on these paths so far.
- Per action, the harness saves far faster than a person does, so the risk on a device is much
  lower than in the tests. But it is not zero: the same race already crashed a phone once,
  through a different writer.

### 13.5 Recommended fix (not built)

1. **Phase 3, `WorkoutService` first** (3 sites: finish, metadata, progression exclusions).
   - Move each write into a `WorkoutRepository` method, following the precedent of
     `setHealthKitUUID` and `HealthProfileRepository.update`.
   - It is small and mechanical, it removes the writer caught here, and it runs on every workout
     finish.
2. **Phase 2, `PRService` and `StatsService`** (13 sites and 3 blocks).
   - This is the hot path and the bulk of the work: about 1–2 sessions.
   - Keep the badge-identity dependency until Phase 5
     (SWIFTDATA_LIVE_MODEL_FIX_SCOPING.md §3, §7).
3. **The rest of Phase 3** (Fatigue exercise 5, Template 2, Bodyweight 1), plus the insert-only
   `save` guard.
4. **Verification:**
   - T1–T4 become the iOS 17.5 regression gate: each alone ×10 (today every one crashes within
     10), and T1 ×20.
   - `RUN_BUG2_UNSAFE_WRITES` must keep crashing, to prove the harness still detects the bug.
   - Full suite on 17.5, 18.6 and 26.3.
5. **Alternative (a product decision):** raise the deployment target to iOS 18.
   - Bug 2 exists only on iOS 17, so this removes the whole class and Phases 2–3 stop being
     crash fixes.
   - The cost is the one active iOS 17 user, who would stop getting updates.
6. **Don't** make these tests pass by removing `@MainActor` or building their repositories off
   the main thread. That would hide the race while the app keeps the crashing construction
   (§4.6).

**Until one of those lands:** judge regressions on 26.3 and 18.6, and expect T1–T4 (plus other
rotating `WorkoutJourneyTests` victims, §4.3) to segfault intermittently on 17.5.

**Decision, 2026-09-13: option 5.** The deployment target was raised to iOS 18.0 (all six
configurations: project, `Repster`, `WorkoutLiveActivityExtension`).
- Bug 2 can no longer happen on a supported OS, so T1–T4 stop mattering: the app no longer runs
  on 17.5.
- The iOS 17.5 simulator stops being a test destination. The oldest one is now iOS 18.6.
- Phases 2–3 are no longer crash fixes. They stay as optional architecture work under the
  one-owner rule.
- The bug-2 tests in `LiveModelRaceReproTests` (`RUN_BUG2_*`) only ever reproduced on iOS 17.
  They stay in the file as history, but they can't demonstrate anything any more.
- Market context: roughly 2–3% of iPhones worldwide were below iOS 18 at the end of August 2026
  (TelemetryDeck). Every iPhone that runs iOS 17 can also run iOS 18.

### 13.6 Evidence

- **The user's full-suite result:**
  `DerivedData/Repster-hjxdomcocdypqyaozeksllqltljz/Logs/Test/Test-Repster-2026.09.13_10-06-04-+0200.xcresult`
- **The crash report:** `~/Library/Logs/DiagnosticReports/Repster-2026-09-13-102312.ips`, kept
  until macOS prunes it.
- **Diagnostic setup:** the baseline worktree, its DerivedData, and a temporary
  `.xctestrun` copy carrying the ConcurrencyDebug argument. All were removed after the runs.
- **Scope:** no app code, tests, scheme or project settings were changed.
