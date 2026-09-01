# Template hardening — scoping

**1 and 2 are built (769 tests green). 3 is not started and still needs its decision table signed off.**

Three items left over from the 2026-09-01 template-collapse investigation
([TEMPLATE_SET_COLLAPSE_HANDOVER.md](TEMPLATE_SET_COLLAPSE_HANDOVER.md)). None can lose data — every
path that could was fixed during the investigation. These are fragility, cost, and recovery.

Independent of each other. Order below is by ratio of value to size, not dependency.

---

## 1. A folder move must not rewrite the template — **DONE**

**Now.** `TemplateListViewModel.setFolder` reads the whole detail and pushes it back through
`replaceTemplateContents` to change one nullable string. Every `TemplateExercise` and `TemplateSet` is
deleted and recreated with new UUIDs and fresh `createdAt`/`updatedAt`. The round trip is correct, so
nothing is lost — but a gesture that should change a label runs the most destructive code in the
feature, and it is why per-row timestamps are worthless as forensic evidence.

It also mutates a `@Model` across the actor boundary on the way: `updateTemplate` sets
`template.name` / `.folder` on the `TemplateService` actor on an object owned by the repository's
context.

**Build.**

- `TemplateRepository.updateTemplateFolder(templateId:folder:)` — fetch, set `folder` and
  `updatedAt`, save. Inside the actor, so nothing crosses. Plus the protocol requirement.
- `TemplateService.updateTemplateFolder(_:folder:)` passing straight through.
- `TemplateListViewModel.setFolder` calls it instead of building `TemplateSaveData`. The
  `fetchTemplateDetail` read at the top of that method goes away entirely.

**Call sites.** One: `TemplateFlowView.moveTemplate` → `viewModel.setFolder`. No UI change.

**Tests.** Three, in `TemplateServiceTests`:
- folder changes, and clearing to `nil` works;
- exercise and set rows are the **same rows** afterwards — capture ids before and after;
- their `createdAt` is unchanged.

**Size.** ~60 lines plus tests. Contained. No open questions.

**Risk.** None identified. The one behaviour change is that a folder move no longer bumps every row's
`updatedAt`, which is the point.

**Built as scoped**, plus one thing scoping missed: `TemplateSaveData.init` normalises the folder name
through `TemplateFolder.normalized`, so the new path had to as well or a folder called `"   "` would
appear in the list where the editor's path would have trimmed it away. Five tests.

---

## 2. `fetchTemplateDetail` must not read `@Model` across the actor boundary — **DONE**

**Now.** `TemplateService.fetchTemplateDetail` fetches `[TemplateExercise]` from the `@ModelActor`
repository, then reads `templateExercise.id` **on the TemplateService actor** and feeds it into
`fetchTemplateSets(for:)` — the query that establishes which sets belong to which exercise. It then
does the same per exercise against `exerciseRepo.fetch(byId:)`. `TemplateRepositoryProtocol`'s own doc
comment names this as the crash class `SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md` exists about;
`fetchTemplateListRows` was converted for exactly this reason and the detail read was not.

Also `1 + 2E` actor round trips per read, on a path hit by the editor, the detail screen, export,
duplicate, start-workout and the folder move.

`TemplateService.fetchAllTemplates` has the same flaw in miniature — it reads `.id` and
`.primaryMuscle` off `exerciseRepo.fetchAll()` results on its own actor.

**Build.**

- A value type for the rows — `TemplateDetailRows` carrying template fields, exercises, and sets
  nested — alongside `TemplateListRow` in the protocol file.
- `TemplateRepository.fetchTemplateDetailRows(templateId:)`: three fetches inside the actor
  (template, its exercises, all sets), grouped with a dictionary. Same shape as
  `fetchTemplateListRows`.
- Rewrite `fetchTemplateDetail` to map those rows, resolving names and muscles from **one**
  `exerciseRepo.fetchAllChartExercises()` call — `ChartExerciseData` is already a value type and
  already exists. Same one-line swap in `fetchAllTemplates`.

**Call sites.** **None.** `TemplateDetail` / `TemplateExerciseDetail` / `TemplateSetDetail` are
already structs, so the public signature does not change. All seven callers are untouched. This is
the single most important fact about this item and it is why the earlier "about a day" estimate was
wrong.

**Tests.** The existing template suite already covers the behaviour of this read end to end —
distribution, ordering, superset groups, dangling exercises, export. It should pass unchanged; that
is the regression test. Add one: an exercise deleted from the library still resolves as
"Unknown Exercise" through the new path.

**Size.** ~120 lines, no caller changes, no UI. Half a day including running the suite.

**Risk.** Low, and it is the good kind: if the mapping is wrong the existing tests fail loudly rather
than corrupting anything. Watch one thing — `fetchAllChartExercises` must not drop exercises the
per-id fetch would have found, or names silently become "Unknown Exercise".

**Built as scoped.** `TemplateDetailRows` / `TemplateExerciseRow` / `TemplateSetRowData`,
`TemplateRepository.fetchTemplateDetailRows(templateId:)`, and both service reads switched. No caller
changed, as predicted. Three tests added: the dangling exercise still resolves leniently, the row
grouping keeps each exercise's own sets with a second template's sets in the same table, and a
missing template returns nil.

**Still crossing the boundary, deliberately out of scope here.** The same pattern remains in
`TemplateService` on the write and import/export paths: `updateTemplate` and
`startWorkoutFromTemplate` mutate a `WorkoutTemplate` on the service actor, and `exportTemplate`,
`previewTemplateImport` and `finalizeTemplateImport` read `Exercise` models the same way. Lower stakes
— none of them decides set parentage — but it is the remaining tail if this is ever finished
properly.

---

## 3. A pre-write snapshot of templates — not started

**Now.** Templates entered the backup archive only in the last release, so a user whose templates come
out wrong has no way back and nothing to diagnose from. That is why this investigation could not be
closed. It would **not** have helped here — the damage predates any snapshot — so its entire value is
insurance against a recurrence.

**Open decisions, which is why this is not a straight build.**

| | Recommendation |
|---|---|
| **Where** | `Application Support/TemplateSnapshots/`. Not `temporaryDirectory` — everything else in the app writes there for sharing and the system purges it, which is the opposite of what this is for. Nothing uses Application Support yet, so this is a new directory to own. |
| **When** | The one-shot pattern already in `RepsterApp.init` — `runIfNeeded(modelContext:)` guarded by a `UserDefaults` key, alongside `GhostSetRepsBackfillMigration`. Keyed by app version, not a single boolean, so it takes a fresh snapshot on each upgrade rather than once ever. Must run **before** any template code reads or writes. |
| **Format** | `WorkoutHistoryArchiveTemplate` — already `Codable`, already nested exercises and sets, and already carries `createdAt`/`updatedAt` per row, which `TemplateArchive` does not. No new schema. |
| **Retention** | Last 3 files, by version. Bounded, and enough to see across two upgrades. |
| **Recovery** | **Not built in this item.** A file on disk is enough to diagnose from and enough to hand to support. An in-app restore is a separate decision with its own UI and its own merge-vs-replace question, and building it speculatively is how this grows. Ship the write; add reading it only if it is ever needed. |

**Build.** `TemplateSnapshotMigration.runIfNeeded(modelContext:)` + one line in `RepsterApp.init` +
the encode/write/prune. Tests: writes on a version change, does not rewrite on the same version,
prunes to 3, and a snapshot round-trips back into the archive type.

**Size.** ~150 lines plus tests, once the decisions above are accepted. Half a day.

**Risk.** It runs at cold start, before the UI. Must not throw, must not block — wrap the whole thing
and swallow failures to a `dbg`, the way `SeedService` and the backfills already do. A snapshot that
crashes the app on launch is far worse than no snapshot.

---

## Order and cost

| | Value | Size | Blocked on |
|---|---|---|---|
| 1. Folder move | Deletes a destructive path outright | ~60 lines | nothing |
| 2. Detail read | Removes the named crash class; faster | ~120 lines, no callers | nothing |
| 3. Snapshot | Insurance only | ~150 lines | the four decisions above |

1 and 2 are mechanical, contained, and fully specified — either can be picked up cold. 3 needs the
table signed off first.

Total, if all three: roughly a day and a half. If only 1 and 2: a morning.
