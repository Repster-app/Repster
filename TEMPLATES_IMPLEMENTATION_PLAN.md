# Templates Redesign — Implementation Plan

**Date:** 2026-09-01
**Branch:** `NewMain`
**Status:** **all phases complete**, landed 2026-09-01. Suite green at 737 tests, 0 failures (691 at
the start; 62 template tests, up from 9). Nothing outstanding in this plan.
**Why:** [TEMPLATES_REDESIGN_SCOPING.md](TEMPLATES_REDESIGN_SCOPING.md) — findings, options, open questions
**Design:** https://claude.ai/code/artifact/101cd788-c99b-45f4-94bd-0dc5c9af154c
**Working files:** `design/templates/` (`.dc.html` artboards + `canvas.json`)
**Interacts with:** [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §6, [DROP_SETS_SCOPING.md](DROP_SETS_SCOPING.md) Decision 1–2

---

## What was settled visually

| Surface | Decision |
|---|---|
| Landing | Folder **chips filter**; a selected folder gives a flat list, `All` falls back to grouped runs with full-width headers. Dense 60px rows. No row tags — they cannot survive user-named folders |
| Folders | User-created. One nullable name on the template; a folder exists because a template points at it |
| Detail | New surface. Tapping a template opens it; Start / Edit / Duplicate; superset pairs read as one block with 3a/3b |
| Editor | Action row is `[＋ Warmup 84] [＋ Working Set flex] [More ▾ 78]`. **More absorbs the header ellipsis** |
| Supersets | You pick a **partner**, not a letter. The app assigns the letter |
| Rep targets | Two fields with a dash. A fixed target becomes deliberate rather than accidental |

**Not "Add special".** Checked against DROP_SETS Decision 2 (drop sets are a *set* annotation with real
logged weights — a template has no weights) and Decision 1 (the other eleven types are hidden), that
drawer holds superset alone today. `More` holds actions on the exercise. The grouping drawer earns its
own word when circuits/AMRAP land.

---

## Gates — both smaller than the record says

The decision record ([1_5_DECISION_RECORD.md:711](1_5_DECISION_RECORD.md:711)) names two hard
prerequisites for any schema change. Re-checked today:

**G1 — the backup version guard: already fixed. Strike it.**
[ExportService.swift:257](Repster/Core/Services/ExportService.swift:257) now range-checks against
`minimumSupportedVersion ... currentVersion` and throws `archiveVersionTooNew` above the range. Nothing
owed.

**G2 — the migration plan is dead, but does not block this work. · FIXED 2026-09-01**
`RepsterMigrationPlan` ([RepsterMigrationPlan.swift](Repster/Data/Persistence/RepsterMigrationPlan.swift))
is **referenced nowhere** — `ModelContainerSetup.createContainer()`
([ModelContainerSetup.swift](Repster/Data/Persistence/ModelContainerSetup.swift)) builds
`ModelContainer(for:configurations:)` with **no `migrationPlan:` argument**, so SwiftData is doing
implicit lightweight migration and the plan is inert. `SchemaV1` is also already stale — it omits
`InsightRecord`, which the live container registers.

Adding `folder: String?` is an **optional property addition**, which lightweight migration handles, so
P1.1 can ship without a stage. Recording it because the next non-lightweight change will discover this
the hard way, and fixing it is an hour: sync `SchemaV1` to the container list and pass
`migrationPlan: RepsterMigrationPlan.self`. **Do it in P1.1's pass** while the file is open — cheap
insurance, no behaviour change.

**It was worse than described.** `RepsterMigrationPlan.swift` was not in `project.pbxproj` at all — an
orphaned file on disk that never compiled, so `migrationPlan:` could not even be referenced. Adding it
to the target, syncing `SchemaV1` (it omitted `InsightRecord`) and passing `migrationPlan:` is done.
Behaviour is unchanged today because every migration so far is lightweight; the difference is that the
first stage that *is* needed will now actually run.

---

## Data safety — no user loses a template

A hard requirement on this work, and two of the four risks below are **live today**, not introduced by
the redesign. Every item here is a build rule, not a nice-to-have.

### D1 — Restoring an old backup must not delete templates · **the big one**

`restoreBackup` is a **replace, not a merge**
([ExportService.swift:150](Repster/Core/Services/ExportService.swift:150)): it deletes every
`WorkoutSet`, `Workout`, `ExerciseStats`, `PerformanceRecord`, `FatigueObservation` and
`FatigueLearningSetAudit`, then writes the archive's. Templates survive today **only because they are
not in the archive at all**.

The moment P0.1 puts them in, naive replace semantics would mean: restore a v1 backup → `templates`
decodes as `nil` → delete all templates, insert none. **Every backup a user owns today is v1.** That
turns the feature that was supposed to protect templates into the thing that destroys them.

**Rule — `nil` and `[]` must mean different things:**

| `archive.templates` | Meaning | Restore does |
|---|---|---|
| `nil` (absent) | Archive predates template backup | **Leave existing templates untouched** |
| `[]` (present, empty) | The user genuinely had none | Delete existing templates |
| non-empty | Normal case | Replace with the archive's |

Decode into `[WorkoutHistoryArchiveTemplate]?` and branch on the optional. Do **not** default it to `[]`
at the decode boundary, and do not let a `?? []` creep in anywhere between decode and the delete pass —
that one operator is the whole bug.

### D2 — `updateTemplate` can leave a template permanently empty · **FIXED 2026-09-01**

`updateTemplate` ([TemplateService.swift:230](Repster/Core/Services/TemplateService.swift:230)) deletes
every `TemplateExercise` and `TemplateSet` — and `deleteTemplateExercises` **commits that delete**
([TemplateRepository.swift:64](Repster/Core/Repositories/TemplateRepository.swift:64)) — then re-inserts
row by row, each `save()`ing separately
([TemplateRepository.swift:39](Repster/Core/Repositories/TemplateRepository.swift:39)).

There is no transaction. A throw, a crash, or a background kill between the delete and the last insert
leaves the template alive with **zero exercises**, and nothing recovers it.

This is a live defect. The redesign makes it likelier, because every folder assignment and every
superset pairing is now an edit where before you might never have reopened the template.

**Rule:** make the update atomic before Phase 4 ships. `restoreBackup` already demonstrates the pattern
in this codebase — `context.autosaveEnabled = false`, mutate, one `save()` at the end, so the whole
thing lands or none of it does. `TemplateService` should do the same: one context, one save, no
per-row commits.

**Done.** `TemplateRepository.replaceTemplateContents(templateId:exercises:)` and
`deleteTemplateAndContents(templateId:)` do the whole delete-and-insert inside the `@ModelActor` in one
`save()`, with `modelContext.rollback()` on throw so a failed batch cannot be committed later by an
unrelated save. `createTemplate`, `updateTemplate` and `deleteTemplate` all route through them, which
also collapses the per-row commits: renaming a 6×4 template went from ~60 saves to 2. Models are now
constructed inside the actor rather than handed across, which removes a context-crossing pattern
`SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md` exists about.

This is the T2 rewrite the plan otherwise defers. **The atomicity half is not deferrable**; the ID-churn
half still is.

### D3 — Existing superset data must survive the new editor

Today's flow makes a **group of one** trivially — assign Group A to one exercise, never do the second
half. That is exactly what happens when someone can't find the second step, so this data exists in the
wild. Import can also produce **more groups than the editor renders**: `supersetGroupKey` is free text
mapped to UUIDs ([TemplateService.swift:525](Repster/Core/Services/TemplateService.swift:525)), past
five letters `supersetLabel` returns nil.

The new editor produces neither state. It must still **read** both.

**Rules:**
- A group of one renders as a normal ungrouped exercise with its `supersetGroupId` **preserved on
  disk**, not silently cleared. Offer *Superset with…* as usual; pairing it adopts the existing id.
- More than four groups keeps cycling colour by index mod 4 and keeps assigning letters past E by
  extending `supersetLetters` — never render an unlabelled group.
- Never write `supersetGroupId = nil` as a side effect of opening or saving an unmodified template.

### D4 — The list rewrite must not hide templates

P1.2 replaces the per-template fetch loop with one in-memory join. A template with **zero exercises**
(reachable via import, and via a D2 half-failure) must still appear in the list — an inner join drops
it and the template looks deleted. Show it with `0 exercises · 0 sets`.

Same for a template whose `exerciseId` no longer resolves: today `fetchTemplateDetail` renders
"Unknown Exercise" ([TemplateService.swift:145](Repster/Core/Services/TemplateService.swift:145)). Keep
that behaviour rather than filtering the row out.

### D5 — The folder field cannot fail closed

`folder: String?` is an optional property addition, so lightweight migration handles it and existing
templates get `nil` — which the design already treats as a first-class state ("Not in a folder"). No
default string, no backfill, no migration stage.

### Verification before any of this ships

- Restore a **real v1 `.repsterbackup`** onto a build with P0.1 and confirm the template count is
  unchanged, not zero. This is the single most important test in the plan.
- Take a store snapshot from the current App Store build, open it on a P1.1 build, confirm every
  template, exercise, set and superset group is intact.
- Kill the app mid-`updateTemplate` (breakpoint after the delete, stop the process) on a pre-D2 build
  to reproduce the empty template, then confirm the post-D2 build survives the same interruption.

---

## Phase 0 — owed regardless, ships independently

These are from the scoping doc's Tier 0. None depends on a design decision, and P0.1 gets *harder* if
folders land first.

### P0.1 — Templates in the backup archive · M · **DONE 2026-09-01**

`WorkoutHistoryArchive` carries workouts, exercises and sets
([ExportServiceProtocol.swift:66](Repster/Core/Services/Protocols/ExportServiceProtocol.swift:66)).
**No templates.** A restore loses every one.

- Add `templates: [WorkoutHistoryArchiveTemplate]?` — optional, so v1 archives still decode.
- Bump `currentVersion` to 2; leave `minimumSupportedVersion` at 1.
- Nest exercises and sets under each template rather than three flat arrays; template ids are internal
  and nothing else references them.
- Restore maps template exercise ids to the exercise ids the same restore just upserted.

**Done.** `WorkoutHistoryArchive.currentVersion` is 2 and carries `templates: [...]?` nested
exercises-and-sets-under-template. `minimumSupportedVersion` stays 1.

The D1 rule is implemented as written: restore branches on the optional, and only a **present** array
authorises deleting templates. `WorkoutHistoryArchive`'s explicit init defaults `templates` to nil so
an archive built without it is v1-shaped, which is what it means. `WorkoutHistoryRestoreResult
.templatesRestored` and `WorkoutHistoryBackupPreview.templateCount` are both `Int?` for the same
reason — "not described" is not "zero".

### P0.2 — Instrument the feature · S · **DONE 2026-09-01**

`AnalyticsScreen.templates` is defined
([AnalyticsServiceProtocol.swift:803](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift:803))
and never emitted. `templateCreated` fires only from the create form
([CreateEditTemplateViewModel.swift:180](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:180)).

- `screenViewed(.templates)` on the flow, and on the new detail view.
- `templateCreated` from all three paths, with `source`: `create_template_form`,
  `save_from_workout`, `import`.
- New: `template edited`, `template deleted`, `template duplicated`, `template started`.

**Done.** `screen(.templates)` fires from the flow's `.task` — the single emitter, per the note in
`AnalyticsServiceProtocol` about why `screenViewed(_:hasData:)` was removed. `templateCreated` now
fires from all three paths with `source` of `create_template_form`, `save_from_workout` or `import`.
`template edited` and `template started` carry `exercise_count_bucket` and `in_folder`.

`template duplicated` is declared and fires once P1.3 lands. Q5 becomes answerable with data one
release after this ships.

### P0.3 — Fix the workout→template group derivation · S · **DONE 2026-09-01**

`createTemplateFromWorkout` reads `sortedSets.first?.supersetGroupId`
([TemplateService.swift:350](Repster/Core/Services/TemplateService.swift:350)) — the exact derivation
[SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §2.1 rules out for the workout side. Adopt *any non-nil set
in the exercise defines the group*. Land it in the same release as that doc's work item 1 so both
directions agree.

---

## Phase 1 — data and service

### P1.1 — `WorkoutTemplate.folder` · S · **DONE 2026-09-01**

- `var folder: String?` on [WorkoutTemplate.swift](Repster/Data/Models/WorkoutTemplate.swift).
- Add to `TemplateSummary`, `TemplateSaveData`, `TemplateArchiveTemplate`, and the P0.1 backup type.
- Same pass: sync `SchemaV1` and wire `migrationPlan:` (G2 above).

Trim on write, treat empty as nil, and match case-insensitively when grouping so "Deload" and "deload"
are one folder. No folder entity — a folder exists because a template names it.

### P1.2 — Fix the N+1 in `fetchAllTemplates` · M · **DONE 2026-09-01**

Today it is `1 + T + 2TE` queries: per template a fetch for exercises, then per exercise a fetch for
sets *and* a fetch for the `Exercise`
([TemplateService.swift:89](Repster/Core/Services/TemplateService.swift:89)). At 25 templates × 8
exercises that is 426 actor hops to draw a list.

**Done.** `TemplateRepository.fetchTemplateListRows()` assembles everything inside the actor in three
fetches and returns `TemplateListRow` **value types**, so no `@Model` crosses the boundary — the same
reason `exportBackup` was rewritten that way. The service adds one `exerciseRepo.fetchAll()` for muscle
groups: **two actor round trips regardless of library size**, down from 426 at 25×8.

### P1.3 — `duplicateTemplate(_:) -> UUID` · S · **DONE 2026-09-01**

Fetch detail → map to `TemplateSaveData` → `createTemplate`. Name via the existing
`uniqueImportedTemplateName` helper, reworded ("Push Day A (Copy)"). Carries folder.

### P1.4 — Folder listing · XS · **DONE 2026-09-01**

`fetchAllTemplates` already returns every summary, so distinct folders derive in the view model. No new
service method.

---

## Phase 2 — landing

### P2.1 — `TemplateListViewModel` · M · **DONE 2026-09-01**

**Done.** The rules live in `TemplateListGrouping`, a pure enum with no service and no main actor, so
each decision the design argued about is a one-line test: folders order by their most recently used
template then by name, case-folded names are one folder with the first spelling as the display name,
ungrouped is always last and always shown, search matches name *or* folder, and a selected folder
yields one **untitled** section because a header would only repeat the chip.

`loadTemplates` also clears a selection whose folder no longer exists — otherwise deleting the last
template in a folder left the list filtered to nothing with no way back.

### P2.2 — `TemplateRowView` · M · **DONE 2026-09-01**

New 60px row: 4px muscle-coloured bar, name (+ link glyph when the template contains a superset), meta
line `N ex · N sets · relative date`. Replaces `TemplateCardView`
([TemplateCardView.swift](Repster/Features/Templates/Views/Components/TemplateCardView.swift)) — delete
it and `TemplateMuscleTagLayout` with it.

### P2.3 — Chips, search field, section headers · M · **DONE 2026-09-01**

Horizontally scrolling chip row; search as a persistent field. Full-width section headers with folder
icon, name, count and a `…` for rename/delete.

### P2.4 — Delete the intro card · XS · **DONE 2026-09-01**

[TemplateListSheet.swift:287](Repster/Features/Templates/Views/TemplateListSheet.swift:287). A permanent
paragraph explaining the buttons is a sign the UI isn't explaining itself; the redesign removes the need.

---

## Phase 3 — template detail (new)

### P3.1 — `TemplateDetailView` + view model · L · **DONE 2026-09-01**

Reads `fetchTemplateDetail` — no new service call. Stat tiles, per-exercise prescription rows, superset
pairs as one purple block with 3a/3b numbering, sticky action bar.

### P3.2 — Reroute the tap · S · **DONE 2026-09-01**

Today tapping a card starts a workout immediately. Tap now pushes detail; Start moves inside it.

**Confirmed 2026-09-01:** the instant start reads as annoying rather than fast, so the extra tap is the
point, not the cost. Still the biggest behaviour change here and still worth a device pass.

### P3.3 — Labelled actions · S · **DONE 2026-09-01**

Start (primary), Edit and Copy as **labelled** icon buttons — icon-only was the same discoverability
trap as the superset menu at smaller scale. Export and Delete stay in the `…` menu; rare and destructive
belongs there.

### P3.4 — The gated tiles · — · **RESOLVED 2026-09-01**

Shipped with **three** tiles, all of them real: EXERCISES, SETS, LAST USED.

`TIMES DONE` is out entirely until `Workout.templateId` exists (**Q3**) — nothing links a workout back
to the template that produced it, so any count would be invented. The third tile reads **Last used**,
not "Last done", because `lastUsedAt` is stamped when a workout *starts*: an abandoned session counts.
The label carries that distinction rather than the number pretending it doesn't exist.

Est. time was dropped from the design: the only per-exercise rest figure a template holds is the dead
`restTimeSeconds` field, so any estimate would be built on something that has never worked.

---

## Phase 4 — editor

### P4.1 — Three-button action row · M · **DONE 2026-09-01**

`[＋ Warmup 84pt] [＋ Working Set flex] [More ▾ 78pt]`. `More` absorbs the header ellipsis entirely, so
the unlabelled glyph leaves every card. Menu: Superset with… / Add note / Move to folder / Remove
exercise.

**Known tradeoff, decided:** acting on a collapsed exercise now means expanding it first. Accepted — one
extra tap for a once-per-exercise action, against removing a mystery glyph from every row.

### P4.2 — Two-field rep range · M · **DONE 2026-09-01**

Replace the free-text field and `parseRepRange`
([CreateEditTemplateView.swift:681](Repster/Features/Templates/Views/CreateEditTemplateView.swift:681)),
which silently keeps the previous value on malformed input. Two numeric fields; a fixed target means
typing the same number twice.

Does not fix `SUGGESTION_PROGRESSION_DESIGN.md` P2 — a fixed target still cannot progress. It stops the
editor **producing** that shape by accident, which is the templates-side half.

### P4.3 — Superset partner picker · L · **DONE 2026-09-01**

The core discoverability fix. Replaces `Menu("Superset Group")` + the letter list
([CreateEditTemplateView.swift:327](Repster/Features/Templates/Views/CreateEditTemplateView.swift:327)).

- Sheet lists the template's *other* exercises — editor state, not the library, so no
  `ExerciseListView` reuse and no fetch.
- Already-grouped exercises shown disabled, not hidden.
- Non-adjacent partner says "Moves up to sit next to X" (SUPERSETS_SCOPING §6 constraint 1) and reorders
  on confirm.
- **Letter is assigned, not chosen**: first free letter from `supersetLetters`, colour cycling
  `[accent, chart5, chart7, chart8]` by index mod 4.
- Pairs only, matching §6 constraint 2.
- A group of one becomes unreachable.

`viewModel.setSupersetGroup(for:label:)` is replaced by `pairExercise(_:with:)` and
`removeFromSuperset(_:)`.

### P4.4 — Folder row and move sheet · M · **DONE 2026-09-01**

Folder row under the template name in the editor; a `Move to folder` sheet listing existing folders,
"Not in a folder", and "New folder…" as a text prompt. Same sheet from the row menu in P4.1.

---

## Phase 5 — cleanup

### P5.1 — Delete the AI helper · M · **DONE 2026-09-01 — Q5 answered: delete**

~469 lines plus 3 of the 9 template tests and the `exerciseStatsRepository` dependency on
`TemplateService` ([ServiceContainer.swift:158](Repster/Core/Services/ServiceContainer.swift:158)),
which nothing else in that service uses. `.repstertemplate` import/export **stays** — the UTTypes are
registered in [Info.plist](Repster/Info.plist) with the app as `Owner`, and files exist in users' Files
and iCloud. `TemplateImportReviewSheet` stays; the archive path needs it.

**Done.** `AITemplateHelperSheet.swift` deleted outright (311 lines), plus `AITemplateContextArchive`,
`AITemplateDraft` and their children from the protocol, `exportAITemplateContext` and the draft parse
branch from the service, two error cases, the toolbar menu, and 3 tests. `TemplateImportSource` is down
to one case.

`TemplateService` lost the `exerciseStatsRepository` dependency entirely — nothing else in it used that
repo — so `ServiceContainer` and five test harnesses got simpler with it.

`.repstertemplate` import and export are untouched and still covered by 6 tests. The UTTypes stay
registered, so files in users' Files and iCloud still open.

**Deliberately not done in the same pass:** `supersetGroupKey: String?` still threads through the import
layer, and with only the archive path left it could carry group identity directly. That is a
behaviour-neutral refactor of a tested path and belongs on its own, not bundled into a deletion.

Also closes the DROP_SETS Decision 1 violation — the AI prompt hands ChatGPT all 13 `SetType` raw values
([TemplateListSheet.swift:985](Repster/Features/Templates/Views/TemplateListSheet.swift:985)).

### P5.2 — Split `TemplateListSheet.swift` · S · **DONE 2026-09-01**

**Done.** It had grown to 1,271 lines. Now four files: `TemplateFlowView` (597), `AITemplateHelperSheet`
(311), `TemplateImportReviewSheet` (290) and `TemplateSharing` (99).

The AI flow is deliberately alone in its file, so **Q5 becomes a one-file deletion** rather than surgery
through a shared file.

One wrinkle worth recording: the shared helpers were file-private and had to become internal to cross
the split, which collided with identically-named privates elsewhere — `ActivityShareSheet` in
`ExportView`, `temporaryShareURL` in `ExportViewModel`, `formatRestTime` in two more. The templates
copies are namespaced (`TemplateShareSheet`, `templateTemporaryShareURL`, `templateFormatRestTime`)
rather than claiming the general names. Consolidating the four near-duplicates is a separate job.

### P5.3 — Extract and extend the tests · M · **DONE 2026-09-01**

`RepsterTests/TemplateServiceTests.swift` now exists with **16 tests** covering
`startWorkoutFromTemplate` (targets, superset propagation, `lastUsedAt`), the atomic replace, delete
cascade, P0.3 group derivation both ways, folders (round trip, clearing, normalisation, case-folded
grouping, export/import, legacy archives with no `folder` key), D3 group-of-one preservation and D4
missing-exercise rendering.

The nine import/export tests are now in `TemplateImportExportTests.swift`, moved unchanged along with
the private harness they used. `ActiveWorkoutViewModelSuggestionRefreshTests.swift` drops from 7,746 to
7,025 lines and no longer contains any template coverage.

Template tests now total **62** across three files — 48 in `TemplateServiceTests`, 9 in
`TemplateImportExportTests`, 5 backup-safety tests in `WorkoutHistoryBackupTests` — up from 9.

Nine template tests are buried in
`RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift` (7,746 lines, named for something
else) at lines 3631–4098, and **all nine cover import/export**. Move to `TemplateServiceTests.swift`.

Coverage owed before touching the service — none of these exist today:

- `startWorkoutFromTemplate` — the most-used function in the feature, zero tests
- `createTemplate` / `updateTemplate` round trip, including folder
- `deleteTemplate` and its hand-rolled cascade
- `fetchAllTemplates` counts, sort, and grouping after P1.2
- `duplicateTemplate`
- superset propagation template→workout and workout→template (P0.3)

---

## Deferred, with reasons

**T2 — delete-and-recreate on update, the ID-churn half only.** `updateTemplate` wipes every exercise
and set and re-inserts with fresh UUIDs
([TemplateService.swift:220](Repster/Core/Services/TemplateService.swift:220)). The churn only bites
once something needs a durable per-exercise reference, which is Q3's lineage work, so it waits.

**The atomicity half does not wait — see D2.** The same method's uncommitted-delete window is a live
data-loss path and is a build rule for this work, not a deferral. Doing D2 collapses the per-row saves
as a side effect, so the ~60-saves-to-rename problem largely goes with it; what remains deferred is
only the fresh-UUID behaviour.

**T3 — the 120ms sleep.** `fetchTemplateDetailWithRetry`
([CreateEditTemplateViewModel.swift:112](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:112))
sleeps and refetches to dodge a transient empty read. P1.2 changes that read path, so **re-test whether
the race still reproduces** and delete the sleep if it does not. Do not carry it forward untested.

**T7 — `Program` / `Planned*`.** Registered in the container, listed in the migration plan, wiped by
`SettingsService`, read by no feature. **Q6.** If folders ever gain ordering or metadata, this is the
upgrade path and the schema is already there — which is an argument for leaving it alone this round.

---

## Test plan

**Unit** — everything in P5.3, plus: folder trim/case-fold on save; grouping puts ungrouped last;
duplicate carries folder and superset groups; partner picker letter assignment skips taken letters and
cycles colour past D; pairing a non-adjacent exercise reorders; unpair clears both sides.

**Backup** — **v1 archive restores under the v2 reader and leaves existing templates untouched (D1)**;
an archive with `templates: []` clears them; v2 round-trips templates, folders and superset groups; a
template whose exercise is missing resolves the same way import does.

**Data safety (D1–D5)** — `updateTemplate` interrupted after the delete leaves the template intact
(D2); a template holding a group of one keeps its `supersetGroupId` through an open-and-save cycle
(D3); a six-group imported template renders every group with a letter (D3); a zero-exercise template
appears in the list (D4); a template whose exercise id no longer resolves still renders (D4).

**Device pass** — the P3.2 reroute is a behaviour change on the busiest path; run it against a real
library. Also: long folder name in a chip and in a section header; 20+ templates across 5 folders;
VoiceOver on the chip row and the `More` menu; Dynamic Type at XXL on the 60px row.

---

## Sequencing

1. **P0.2** first — instrumentation before changes, so the before/after reads.
2. **P0.1**, then **P1.1** — archive gains templates, then templates gain folder. One version bump.
3. **P0.3** alongside SUPERSETS_SCOPING item 1.
4. **P5.3** before Phase 2 — cover `startWorkoutFromTemplate` before refactoring around it.
5. **P1.2** — the list gets heavier next.
6. **Phase 2**, then **Phase 3**. The landing is meaningless without detail to open.
7. **Phase 4** — independent of 2 and 3; can run in parallel.
8. **P5.1 / P5.2** once Q5 is answered.

Phases 2–4 are shippable separately. Phase 3 is the one users will notice.

---

## Still blocked on decisions

| | Question | Blocks |
|---|---|---|
| **Q1** | Does the workout grow an exercise level? | `TemplateExercise.restTimeSeconds` and `.notes` stay dead until answered. The editor deliberately does not offer per-exercise rest |
| **Q3** | `Workout.templateId`? | P3.4's two tiles; per-template progression; "3 templates use this exercise" |
| **Q5** | Delete the AI helper? | P5.1, P5.2 |
| **Q6** | Absorb or delete `Program`? | Whether folders stay a string or become an entity |

None blocks Phases 0–4 as written.

---

## Docs to reconcile

- **[SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §6** — "Drive the menu from `supersetLetters` instead
  of a literal" is now the wrong fix for the template editor. The letter is auto-assigned; there is no
  letter menu. The rest of that section (letter as identity, colour cycling mod 4, pairs only,
  contiguity) is unchanged and is what P4.3 implements.
- **[TEMPLATES_REDESIGN_SCOPING.md](TEMPLATES_REDESIGN_SCOPING.md)** — F1, F2, F3 and Q7 are now
  answered by the design; §2.4's "picker is on a clock" is resolved.
