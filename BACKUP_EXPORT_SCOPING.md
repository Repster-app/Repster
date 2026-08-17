# Backup Export — Scoping

**Status:** Phases 2 and 4 implemented 2026-08-17 (uncommitted on `NewMain`); Phases 0, 1, 3, 5, 6
still open. Written 2026-08-16 against `NewMain` @ `d45d01e`.
**Scope:** `WorkoutHistoryBackupService` export path, its restore counterpart where the two are
coupled, and the archive format.

Every claim below was read out of the code or measured; line references are to the tree as of
`d45d01e`. Where something is *suspected* rather than verified, it says so and names the experiment
that would settle it.

---

## 1. What exists today

**Entry point.** Settings → Data & Backups → Export Backup ([SettingsView.swift:953](Repster/Features/Settings/Views/SettingsView.swift:953)),
one button, push navigation. Siblings: CSV Import and Restore Backup.

**Pipeline.** `ExportView` → `ExportViewModel.generateExport()` → `WorkoutHistoryBackupService.exportBackup()`
(an `actor`) → `Data` → temp file → `UIActivityViewController` → `backup exported` analytics event.

**Archive contents** ([ExportService.swift:54-111](Repster/Core/Services/ExportService.swift:54)):

| Data | Source | Notes |
|---|---|---|
| Workouts | `workoutRepo.fetchAllWorkouts(limit: nil, offset: nil)` | all statuses, in-progress included |
| Sets | `setRepo.fetchSets(.distantPast, .distantFuture)` | everything |
| Exercises | `exerciseRepo.fetchAll()` **filtered to ids appearing in a set** | unused exercises excluded |
| `FatigueObservation`, `FatigueLearningSetAudit` | ad-hoc `ModelContext(modelContainer)` at [:72](Repster/Core/Services/ExportService.swift:72) | not via the injected repos |
| `HealthProfile` | same ad-hoc context | **only** the 3 `prescription*` learning fields |

**Format.** `JSONEncoder` with `.prettyPrinted`, `.sortedKeys`, ISO8601 dates. Plain JSON, no
compression, no encryption. `.repsterbackup` / UTI `com.magnusespensen.repster.workout-history`,
exported and conforming to `public.json` ([Info.plist:92](Repster/Info.plist:92)). Legacy
`.reppobackup` is declared import-only. Archive `version = 1`.

**Excluded by design.** `ExerciseStats` and `PerformanceRecord` — restore rebuilds them via
`statsService.rebuildAll()` / `prService.rebuildAll()`. **Excluded, apparently not by design:**
templates, programs, bodyweight logs, settings, the rest of `HealthProfile`, `InsightRecord`.

**Measured shape** (`RepsterTests/Fixtures/Local/real-history.repsterbackup`, one real user):

```
579 workouts · 11,785 sets · 171 exercises · 193 observations · 556 audits
7,376,244 bytes pretty-printed   →   5,474,175 compact (pretty costs +35%, ~1.9 MB)
```

Sets dominate; exercises are ~1.5% of rows. Seed library is 69 exercises
(`Repster/Resources/seed_exercises.json`), so this user has ~100 custom ones.

---

## 2. Findings

Ordered by risk, not by effort. F1 is the reason this document exists — it is not what I flagged
first when I skimmed the file, and it is the one that could hurt users.

### F1 — Export reads ~12k live `@Model` objects across actor boundaries (**CONFIRMED 2026-08-17**)

> **Phase 0 result.** `testExportBackupUnderConcurrentSaves` crashed the runner on the first run.
> `EXC_BAD_ACCESS` / `SIGSEGV`, `KERN_INVALID_ADDRESS at 0x8000000000000010` — byte-identical to the
> signature in `SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md`. Faulting stack:
>
> ```
> SwiftData (×5)
> WorkoutSet.setType.getter                              ← faults here
> WorkoutHistoryArchiveSet.init(_:)                      ← ExportService.swift:467
> implicit closure #3 in WorkoutHistoryBackupService.exportBackup()
> Collection.map<A, B>(_:)
> WorkoutHistoryBackupService.exportBackup()
> ```
>
> Not a suspicion any more: **backup export is a live instance of the crash class that shipped in
> 1.3 and twice in TestFlight 1.4.** Phase 1 is mandatory and jumps the queue. The severity caveat
> below still stands — the harness drives 2,000 concurrent writer saves, which is heavier than
> normal use — but the mechanism is now demonstrated rather than argued.
>
> Crash report: `~/Library/Logs/DiagnosticReports/Repster-2026-08-17-093427.ips`.

Every repository is a `@ModelActor` owning its own `ModelContext`
([RepositoryContainer.swift:22-33](Repster/Core/Repositories/RepositoryContainer.swift:22)).
`exportBackup()` calls three of them and gets back live `Workout` / `WorkoutSet` / `Exercise`
objects, then reads ~40 properties off each one from inside a *different* actor
([ExportService.swift:55-84](Repster/Core/Services/ExportService.swift:55)). SwiftData faults
properties lazily, so those reads fault through a context the backup actor does not own.

That is precisely the pattern documented in `SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md` and fixed
across the UI in the step-1–4 work: it shipped as `EXC_BAD_ACCESS` at `0x8000000000000010` in 1.3
and twice in TestFlight 1.4. All three observed crashes were **reads** faulting. Export is a read
path that was never converted — `WorkoutRepository`'s own comment
([:66-72](Repster/Core/Repositories/WorkoutRepository.swift:66)) says the snapshot queries exist
"to avoid sending live Workout models across actors", and export is calling the non-snapshot one.

Two things make this less alarming than the shipped crashes, and one makes it worse:

- *Less:* the reader is a background actor, not `@MainActor`, and export is rare and user-initiated.
- *Less:* the repo contexts are not obviously autosaving — only `ExportService`, `ImportService` and
  `SettingsService` set `autosaveEnabled` explicitly, all to `false`.
- *Worse:* 11,785 sets × ~40 faulting property reads is a very wide window, and export is exactly
  the thing a user reaches for *before* doing something risky. A crash here is rare, unattributable,
  and lands on the user who was being careful.

**This is a hypothesis, not a diagnosis.** `RepsterTests/CrossContextRaceTests.swift` already holds a
working paired-control harness for this exact bug class, including the marker-file trick that works
in this project where the `TEST_RUNNER_` env-var approach does not. Settling F1 means adding one
export-shaped control to that file. Do that *before* deciding how much Phase 1 is worth.

### F2 — Version equality lock will orphan every backup in the wild the day you bump

`decodeArchive` guards `archive.version == currentVersion`
([ExportService.swift:253](Repster/Core/Services/ExportService.swift:253)), and `currentVersion = 1`
([ExportServiceProtocol.swift:49](Repster/Core/Services/Protocols/ExportServiceProtocol.swift:49)).

Rejecting a *newer* archive is correct. Rejecting an *older* one is not — and that is what this
guard does. The moment `currentVersion` becomes 2, every `.repsterbackup` file any user has ever
saved stops restoring, with "Unsupported backup version: 1." Those files are the entire point of the
feature; they are sitting in iCloud Drive and Files folders since 1.0.

The same exact-equality pattern is in `TemplateService` for `TemplateArchive`,
`AITemplateContextArchive` and `AITemplateDraft` ([TemplateService.swift:648](Repster/Core/Services/TemplateService.swift:648),
[:672](Repster/Core/Services/TemplateService.swift:672), [:712](Repster/Core/Services/TemplateService.swift:712)) — same latent
problem, out of scope here, worth a follow-up.

This is cheap to fix now and expensive to retrofit. It gates any archive change (F7).

### F3 — One orphaned set makes the entire backup impossible

`validateCoreArchive` throws if any set references a missing workout or exercise
([ExportService.swift:288-295](Repster/Core/Services/ExportService.swift:288)). It runs on the
**export** side too, against the live store. So a single inconsistent row means the user cannot back
up *at all*, and what they see is the raw `"Set 8F3A… references a missing workout."`

Cascades are service-level discipline, not a store constraint: sets hold UUID foreign keys, no
`@Relationship`, and `ExerciseService.deleteExercise` cleans up across five separate awaited steps
([ExerciseService.swift:237-258](Repster/Core/Services/ExerciseService.swift:237)) — an interruption
or a throw partway leaves exactly the orphan that blocks all future exports. Restore already handles
its equivalent problem gracefully by *skipping* and reporting counts; export should match.

### F4 — Restore reports failure after the destructive part already committed

Restore's core mutation is genuinely atomic — one context, autosave off, single `save()` at
[:209](Repster/Core/Services/ExportService.swift:209). But two things happen *after* that save:

- `healthProfileLearning` is applied in a **second context with its own save** ([:211-217](Repster/Core/Services/ExportService.swift:211)),
  and `fetchOrCreateHealthProfile` saves a third time ([:345](Repster/Core/Services/ExportService.swift:345)).
- `statsService.rebuildAll()` and `prService.rebuildAll()` run outside the transaction ([:219-220](Repster/Core/Services/ExportService.swift:219)).

If a rebuild throws, `RestoreBackupViewModel` shows **"Restore Failed"** — but the old history is
already deleted and the new history is already committed. The user is told the operation failed while
looking at a database that was in fact replaced. The comment at [:141](Repster/Core/Services/ExportService.swift:141)
("all-or-nothing") is accurate about the save and misleading about the operation.

### F5 — Export computes what it silently dropped, then discards it

`sanitizeLearningData` returns `skippedObservationCount` / `skippedAuditCount`, and the export path
throws the counts away ([ExportService.swift:90-94](Repster/Core/Services/ExportService.swift:90)).
Restore surfaces the same counts through `learningDataWarningMessage`. So the file can be quietly
lossier than the user thinks, and the one place that knows it already computed the number.

### F6 — Hygiene

- **Dead dependencies.** `fatigueObservationRepo` and `fatigueLearningAuditRepo` are injected and
  never read ([:24-25](Repster/Core/Services/ExportService.swift:24)). Note this is *not* laziness:
  neither protocol has a fetch-all method (`FatigueObservationRepositoryProtocol` fetches only by
  workout or exercise), so the ad-hoc context was the only way to get all rows. Resolving this means
  choosing a direction (see Phase 4), not just deleting two lines.
- **Temp files are never cleaned up.** Each export writes a new timestamped file into
  `FileManager.default.temporaryDirectory` and nothing ever removes it
  ([ExportViewModel.swift:60-72](Repster/Features/Settings/ViewModels/ExportViewModel.swift:60)).
  At ~7 MB a file for a heavy user, ten exports is 70 MB held until iOS decides to purge.
- **Unused exercises are not backed up.** A custom exercise with no logged sets does not survive a
  restore onto a fresh device. Exercises are 1.5% of rows, so including all of them is free.

### F7 — "Backup" means workout history only

The UI has to say so three separate times ([SettingsView.swift:979](Repster/Features/Settings/Views/SettingsView.swift:979),
[ExportView.swift:129](Repster/Features/Settings/Views/ExportView.swift:129),
[:187](Repster/Features/Settings/Views/ExportView.swift:187)). Templates, programs, planned
workouts, bodyweight logs and insight user-state are all absent. A user who restores onto a new phone
gets their history and loses their templates.

De-risking finding: **every one of these models uses UUID foreign keys, not SwiftData relationships**
(verified across `WorkoutTemplate`, `TemplateExercise`, `Program`, `ProgramExercise`, `PlannedWorkout`,
`PlannedSet`, `BodyweightEntry`), and each carries 6–9 fields. So widening the archive is flat arrays
of small value structs — the same shape the archive already has. Mechanical, not architectural.

`InsightRecord` is the one judgement call: it is regenerated from history by `InsightsService.persist`
([:334-392](Repster/Core/Services/InsightsService.swift:334)), so the *content* is derived — but
`snoozedUntil`, `seenAt` and `stateRaw` are genuine user state that regeneration deliberately
preserves. Recommend exporting only that triple keyed by `(ruleId, subjectId)`, not whole records.

### Adjacent, out of scope

`resetAllAppData` deletes 16 entity types and **not** `InsightRecord`
([SettingsService.swift:171-186](Repster/Core/Services/SettingsService.swift:171)). Insights survive
a full reset until the next generation run prunes them. Self-healing, but a user can see cards about
exercises that no longer exist. Same gap after a restore. Not a backup bug; worth its own ticket.

---

## 3. Proposed phases

Effort ranges assume this codebase's verification standard, which dominates the cost. Per
`project-swiftdata-crosscontext-crash`: *a green suite after a refactor on this path is near-zero
evidence — mutate the behaviour you claim to have preserved.* Every phase below budgets for that.

### Phase 0 — Settle F1 · **DONE 2026-08-17 — it crashes** · risk: none

`testExportBackupUnderConcurrentSaves` in `CrossContextRaceTests.swift`, gated behind
`Fixtures/Local/RUN_EXPORT_RACE_REPRO` (consumed on run, so a forgotten marker cannot kill a later
suite). Verified to skip cleanly without the marker.

Two design points that decide whether the harness means anything:

- **The reader stays on the backup actor.** Hopping to `@MainActor` would reproduce the already-known
  crash instead of the question being asked.
- **The exporter shares the writers' repository instances.** `ServiceContainer` hands the backup
  service the same `RepositoryContainer` actors the app writes through, so the exporter faults models
  out of a context others are saving. Giving it private repositories would have produced a fast,
  clean, worthless run — the failure mode this file warns about.

**Gate resolved: crashed on the first run.** See F1 above. Phase 1 is now mandatory.

### Phase 1 — Convert the export read path · **DONE 2026-08-17** · risk: medium

`exportBackup()` now reads everything through a single `ModelContext` the backup actor creates, uses
and discards. No `@Model` object crosses an actor boundary. The service takes **no repositories at
all** — export and restore each own their context, and the only remaining dependencies are the two
rebuild triggers plus the container.

Paired evidence, on the identical harness and load:

| | Result |
|---|---|
| Before | SIGSEGV, `0x8000000000000010`, faulting in `WorkoutSet.setType.getter` |
| After | passes in 8.46 s |

Behaviour preservation was pinned *before* the refactor by `testExportBackupOrderingContract`, which
locks the archive's three ordering pipelines (workouts by date→createdAt, sets by workout position→
orderInWorkout→createdAt, exercises case-insensitively by name). It passed against the old code, then
against the new. The fetch descriptors deliberately mirror the sort orders the repositories used,
because the re-sorts are not total orders and `Array.sorted(by:)` is not stable — same input order in,
same tie resolution out.

Full suite: 456 tests, 0 failures, 3 skipped by design (the two gated race controls plus the
pre-existing local-fixture skip).

<details>
<summary>Directions considered</summary>

1. **Snapshot queries on the repos** — add `fetchAll…Snapshots()` returning `Sendable` value structs,
   matching `WorkoutSnapshot` / `ChartSetData`. Consistent with the established fix pattern. But
   `ChartSetData` is already a hand-maintained 40-field mirror with a drift guard, and this adds
   another.
2. **Do the whole export inside one `ModelContext` in the backup actor** — it already does this for
   fatigue rows and the health profile. Deletes the cross-actor reads outright, removes the need for
   new snapshot types, and makes the export a single consistent read of the store rather than four
   independently-timed ones. Also resolves F6's dead-dependency question by deleting the deps.

**Took (2).** It moves export off the repository abstraction the rest of the app uses, which is the
one real cost — but for a read-only, whole-store, point-in-time operation it is the right trade, and
it is strictly less code than (1).

</details>

### Phase 2 — Version tolerance · **DONE 2026-08-17** · risk: low

Change the guard to accept `archive.version <= currentVersion` and route by version. Add a decode
test per supported version, using a checked-in v1 fixture so future bumps cannot silently break v1.
**Do this regardless of everything else, and do it first** — it is cheap now, it is a migration
later, and it gates Phase 6.

### Phase 3 — Resilience and honesty · ~1 day · risk: low–medium

- Export skips orphaned sets instead of throwing (F3), mirroring restore's sanitize-and-count.
- Surface the skip counts, export-side and already-computed, in `ExportView` (F5) — plus the row
  counts, so the user can see what the file contains before trusting it.
- Fix F4 (decided, see §5): fold the health-profile write into the main transaction, and treat
  rebuild failure as a **non-fatal warning** rendered in the existing warning block that
  `learningDataWarningMessage` already uses:

  > Your workout history was restored. Volume stats and personal records couldn't be rebuilt
  > automatically — open Settings → Rebuild Stats to finish.

### Phase 4 — Hygiene · **DONE 2026-08-17** · risk: low

Temp-file cleanup; export the full exercise library (F6). Dead deps were deleted here rather than
waiting on Phase 1, since adding fetch-all methods to two protocols and their test doubles for a
single caller was the worse of the two options either way.

### What landed in Phases 2 + 4

- `minimumSupportedVersion` added; `decodeArchive` accepts `minimumSupportedVersion ... currentVersion`
  and distinguishes "newer than this build" (`archiveVersionTooNew`, tells the user to update) from
  malformed.
- Export carries the whole exercise library, not only exercises with logged sets.
- Export temp files are written to their own `WorkoutHistoryBackups/` directory, swept each run.
- `fatigueObservationRepo` / `fatigueLearningAuditRepo` removed from `WorkoutHistoryBackupService`
  and its five construction sites.
- `RepsterTests/Fixtures/archive-v1.repsterbackup` — a synthetic v1 payload, checked in (unlike
  `Fixtures/Local/`, which is gitignored because the repo is public) as the format tripwire.

Verified by mutation, not just a green suite, per the rule from the crash work:

| Mutation | Result |
|---|---|
| `currentVersion` → 2 | v1 fixture still restores — forward tolerance works |
| …plus the old `==` guard restored | fails with `invalidArchiveVersion(1)` — the exact breakage F2 predicted |
| Exercise filter reinstated | `testExportBackupIncludesExercisesWithNoLoggedSets` fails |
| Temp sweep removed | `testExportViewModelSweepsPreviousTemporaryFiles` fails, 3 files accumulate |

Full suite green at 454 tests / 0 failures / 2 skipped by design before an unrelated in-flight
onboarding refactor started breaking the build.

Two existing assertions were updated rather than preserved, both pinning behaviour this work
deliberately changed: `exercisesUpserted` 1 → 2 in `testRestoreBackupReplacesHistoryAndKeepsUnrelatedData`
(an exercise with no sets is now archived), and the version-rejection test now expects
`archiveVersionTooNew`. Both exist in duplicate — `WorkoutHistoryBackupTests.swift` and a near-identical
class in `ActiveWorkoutViewModelSuggestionRefreshTests.swift` — which is worth consolidating at some point.

### Phase 5 — Compression and size · ~2–4 h · risk: low · optional

Dropping `.prettyPrinted` saves 26% (1.9 MB on the measured fixture); gzip would save far more. But
readable JSON is arguably a feature for a user-facing backup, and 7 MB is not a problem yet. Keep
`.sortedKeys` either way — it makes files diffable. **Recommend deferring** until a real user hits a
share-sheet or memory limit; revisit if peak memory shows up in Phase 0/1 profiling.

### Phase 6 — Archive v2: templates, programs, bodyweight, insight state · ~3–5 days · risk: medium

Requires Phase 2. Eight new archive structs (~60 fields), flat arrays, no relationship handling
(per F7). The work is not the encoding — it is:

- **Restore semantics.** Today restore replaces history and explicitly leaves templates/programs
  alone, and the UI promises that in three places. v2 has to decide per-entity: replace, merge, or
  ask. My recommendation is replace-all-with-confirmation, with the copy rewritten to match, because
  a partial-merge restore is very hard to explain and very easy to get subtly wrong.
- **Referential integrity across the wider graph.** `TemplateExercise.exerciseId` and
  `ProgramExercise` must resolve post-restore; the sanitize step needs extending.
- **The v1→v2 story.** A v1 file restored into v2 has no templates — is that "leave existing
  templates alone" or "wipe them"? Must be decided explicitly, not fall out of the code.

Treat this as its own design pass with its own document. Not a continuation of the batch.

---

## 4. Recommended sequence

Revised 2026-08-17, after Phase 0 came back positive:

```
Phase 2 (version tolerance)          ← DONE
Phase 4 (hygiene)                    ← DONE
Phase 0 (crash control)              ← DONE — crashed, F1 confirmed
Phase 1 (fix the read path)          ← DONE — crash gone, archive unchanged
Phase 3 (resilience + honesty)       ← next
Phase 6 (archive v2)                 ← separate design pass
Phase 5 (compression)                ← defer
```

Phase 1 is no longer a judgement call about code cleanliness — it closes a demonstrated crash on a
path users reach for specifically when protecting their data. Direction is already decided (§5.2):
one `ModelContext` inside the backup actor, which removes the boundary crossing entirely rather than
mirroring more models into snapshot types.

The Phase 0 test becomes the regression guard: after Phase 1 it should run **clean** under the same
load, and the crash report above is the paired control proving the harness can still detect the bug.
Keep both halves, exactly as `CrossContextRaceTests` does for the shipped crashes.

## 5. Decisions

Recorded here so the reasoning is visible and can be overridden later. None of these block the first
PR.

1. **F4 — non-fatal warning.** Decided by the code, not by preference: Settings already ships a
   user-facing Rebuild Stats screen ([SettingsView.swift:262](Repster/Features/Settings/Views/SettingsView.swift:262))
   with separate volume-stats and PR actions. So a post-commit rebuild failure has a recovery path
   the user can reach, which makes "failed" straightforwardly wrong — the history *is* restored and
   the missing piece is derived, rebuildable, and one tap away. Copy in Phase 3.
2. **Phase 1 — single `ModelContext` inside the backup actor**, not new repo snapshot types. Export
   is a read-only, whole-store, point-in-time operation; it wants one consistent read, not four
   independently-timed ones. It also avoids hand-maintaining a second 40-field mirror alongside
   `ChartSetData`, and it deletes the dead deps (F6) as a side effect rather than growing two
   protocols for a single caller. Revisit only if Phase 0 shows the crossing is harmless *and*
   someone wants export back on the repository abstraction for consistency's sake.
3. **Phase 6 restore semantics — deferred, deliberately.** Not answerable until the v2 archive is
   designed, and answering it early would just constrain that design. Placeholder recommendation
   stands (replace-all with confirmation).
4. **`InsightRecord` reset gap — split out.** Adjacent bug, not backup's. Tracked separately.

## 6. What I did not verify

- Whether F1 actually crashes. Phase 0 exists to answer this; everything about F1's priority is
  provisional until it runs.
- Peak memory during export on device. The 7.4 MB figure is file size; in-flight cost is the models
  plus the archive structs plus the encoded `Data`, and I did not measure it.
- Whether any user has actually hit F3 in the wild. PostHog would show `backup export` error events
  via `captureError(_:context: .backupExport)` — the connector is not authorized in this session, so
  that check is yours to run and would move F3's priority either way.
