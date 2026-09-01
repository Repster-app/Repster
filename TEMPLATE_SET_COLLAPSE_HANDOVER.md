# Template sets collapsing onto the first exercise — handover

**Status:** half solved. The "Unknown Exercise" row is explained and fixed. The set distribution is
still unexplained, and the evidence now leans toward it never having been configured — see the
2026-09-01 update below, which supersedes several claims in the original write-up.
**Date:** 2026-09-01
**Branch:** `NewMain`. Suspect release: commit `3cf55ed` ("Rebuild templates around folders,
a detail view, and paired supersets") and the commits after it.

---

## The symptom

After updating to the templates rework, existing templates render with **every set piled onto the
first exercise** and one set left on each of the others. Two confirmed examples:

| Template | Exercises | Sets | Distribution |
|---|---|---|---|
| Upper Body 2 | 9 | 20 | **12**, 1, 1, 1, 1, 1, 1, 1, 1 |
| Arms | 4 | 12 | **10**, 1, 1 (+1 unresolvable) |

Also true of both:

- **Total set count is preserved.** Nothing was deleted — 12 + 8 = 20.
- **Every set has no rep target** (`targetRepMin`/`Max`/`RIR` all nil).
- **One exercise per template is "Unknown Exercise"** — a `TemplateExercise.exerciseId` with no
  matching `Exercise` row. `orderInTemplate` has a gap where it sits.

The owner is confident the templates had real sets on each exercise before the update. There is no
before-snapshot to confirm that — templates were not included in the backup archive until this
release, so no pre-upgrade export of them exists.

---

## Update — what the two export files actually say

Both `.repstertemplate` files were re-read rather than the summary of them. Three facts the table
above does not carry:

**`orderInTemplate == 2` is missing from both.** Not a random slot — position 2 in each. That is the
dangling row, skipped by export.

**Seven of the eleven surviving exercises are user-created, not seeded.** `Cable Row`, `Cable Curl`,
`Cable Fly` and `Close Grip Bench Press` match `seed_exercises.json`; the rest carry the custom shape
(`equipmentType: "other"`, capitalised `primaryMuscle`, no `movementPattern`). Two are typos —
`Wrist Cur`, and `Bar  Curl` with a double space. This device has a history of custom exercises being
made, mistyped and remade.

**Nothing in either template was ever configured, on any axis.** No warmup set anywhere — every
`setType` is `working`. No note, no superset group, no folder. `restTimeSeconds` equals the exercise's
`defaultRestTime` on every single row, including `null` where the exercise has none.

That last point is the load-bearing one. The rep-target wipe (fix 3 below) explains the nil targets
regardless of history, so those are no longer evidence either way. But **warmups, notes and rest time
are untouched by every bug found so far** — if these templates had ever been configured, one of them
would have survived. None did. Every exercise but the first holds exactly the single default working
set `addExercises` auto-adds, with the rest time it was born with.

Also worth knowing: both the old and the new editor show `"N working"` on the *collapsed* card. A
12-set card was legible in the list the whole time, in every build.

This does not close the question — 10-12 sets on one exercise still needs an explanation, and the only
one available is repeated `+ Working Set` on the one card `addExercises` auto-expands
(`isExpanded: exercises.isEmpty`). But hypothesis 3 is now the strongest of the three, not the
weakest, and there is nothing further to find without a before/after pair.

## Solved: the "Unknown Exercise" rows

`ExerciseService.deleteExercise` described itself as a full cascade and was not one. It cleared sets,
stats, PRs and fatigue rows and never touched `TemplateExercise` or `TemplateSet`, so deleting a
custom exercise left every template that used it holding a row pointing at an id that no longer
resolved. Given the custom-exercise churn above, that is the whole story for both missing order-2
rows.

Fixed: `TemplateRepository.deleteTemplateReferences(toExerciseId:)`, called before the exercise row is
deleted so a throw leaves the library intact. It also closes the `orderInTemplate` gap and dissolves a
superset left with one member. One commit, rollback on throw, survivors read before anything is
deleted. Seven tests.

Forward-only: templates already holding a dangling row keep it. Repair by hand — open the template,
the unknown card's **More → Remove exercise**, save.

**Drop this symptom from the case.** It is not evidence that anything rewrote the templates.

## What the data does and does not prove

Both templates were exported as `.repstertemplate` and inspected.

**Proven:** the exercises were added through the editor's **Add Exercise**, not via *Save as
Template*. `addExercises` sets `restTimeSeconds: exercise.defaultRestTime`
([CreateEditTemplateViewModel.swift](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift)),
while `createTemplateFromWorkout` always writes `restTimeSeconds: nil`
([TemplateService.swift:339](Repster/Core/Services/TemplateService.swift:339)). Both files carry
`restTimeSeconds` exactly matching each exercise's `defaultRestTime`, and omit it on exercises that
have none.

**Not proven, and I wrongly claimed it was:** that the templates were never configured.
`restTimeSeconds` is written once at add-time and never touched again, so it is identical whether
the sets were later configured or not. It says nothing about the sets.

> Still true as stated — `restTimeSeconds` alone proves nothing. But the update above reaches the same
> conclusion by a different route that does hold: the total absence of warmups, notes and supersets,
> none of which any known bug can erase.

---

## Already ruled out — do not redo these

All of the following are covered by passing tests in `RepsterTests/TemplateServiceTests.swift`:

- **`createTemplateFromWorkout`** preserves per-exercise set counts: uneven counts (3/2/4/1),
  interleaved superset logging (A,B,A,B,A,B), and nine exercises each with their own sets.
- **Editor round trip**: loading a template and saving it unchanged three times keeps a 3/1/2
  distribution intact.
- **Removed exercises**: sets belonging to a deleted template exercise are not adopted by another.
- **`replaceTemplateContents` / `deleteTemplateAndContents`** write correctly given correct input,
  in a single commit with rollback on throw.
- **Copy Previous** ([ContentView.swift](Repster/App/ContentView.swift) `performCopy`) copies
  `exerciseId` and `reps` faithfully per set; it cannot redistribute.

**Not reproduced:** a controlled upgrade on a second phone — old build, two hand-built templates with
sets/reps/RIR, then update — came through completely intact. That store was fresh, however, with no
migration history, and the affected store has years of it.

---

## Fixes already shipped (all real, none confirmed as the cause)

1. **`migrationPlan:` wiring reverted** (`7c76320`). `SchemaV1.models` returns the *live* model
   types, so it describes the current schema while claiming to be version 1. Wiring it told
   SwiftData that 1.0.0 already looks like today's types with no stage to reach it from an older
   store. This ran at store-open on upgrade, which is why it was the leading suspect. Now reverted
   to implicit lightweight migration, which is what shipped originally.
2. **Editor mutations addressed by identity, not array index** (`5736b35`, `7c76320`).
   `addWorkingSet(to:)`, `addWarmupSet`, `removeExercise`, `toggleExpanded`, set edits and superset
   pairing all took array indices captured by a card when it rendered — while `moveExercise` mutates
   that array on every `dropEntered` during a drag. A tap after a reorder acted on whatever moved
   into that slot. **This can append sets to the wrong exercise, silently, when that exercise is
   collapsed.** Pre-existing, not introduced by the rework.
3. **Rep-field seeding no longer writes to the model** (`64a24ee`). `applyRepBounds()` writes *both*
   rep bounds from the row's `@State` strings, and `onAppear` seeded them one at a time — so between
   `minText = "8"` and `maxText = "10"` an `onChange` could persist `targetRepMax = nil`. A genuine
   target-wipe path, and the best candidate for the missing targets.
4. **Template export survives a dangling exercise** (`d394ee7`). It previously threw
   `exerciseNotFound` and produced no file at all, which blocked getting the damaged data out.

---

## The part nobody has explained

**Nothing found so far moves an existing set from one exercise to another.**

`TemplateSet` stores its parent as a plain `templateExerciseId: UUID`. The only writers are
`TemplateRepository.replaceTemplateContents` (driven by `TemplateSaveData` built in the editor) and
the backup restore path. Both are tested and correct for correct input. So either:

- the editor produced that distribution in memory and saved it, or
- something outside those two paths rewrote the rows, or
- the distribution was always that way and the new detail screen is simply the first surface in the
  app's history that shows per-exercise set counts (the old card only ever showed
  "9 exercises · 20 sets").

The third possibility cannot be dismissed on the evidence available, and the owner's recollection is
the only thing arguing against it.

---

## The one artefact that would settle it

> **Superseded.** This plan does not work, and the reason matters for anything built next.
> `replaceTemplateContents` constructs brand-new rows, so **every exercise and set gets a fresh
> `createdAt`/`updatedAt` on every save** — and `TemplateListViewModel.setFolder` and
> `duplicateTemplate` both route through it, so filing a template into a folder rewrites all its
> rows. `startWorkoutFromTemplate` also stamps `WorkoutTemplate.updatedAt` on every use. A recent
> timestamp therefore proves nothing; only an old one is informative, and it proves the opposite of
> what you would be looking for. The pre-write snapshot below is the only artefact that would work.

**A full backup export (Settings) from a device with damaged templates.**

Templates entered the backup archive in this release (`WorkoutHistoryArchive` v2), and
`WorkoutHistoryArchiveTemplate` carries `createdAt` / `updatedAt`, with `createdAt` / `updatedAt` on
every template exercise and every set
([ExportServiceProtocol.swift](Repster/Core/Services/Protocols/ExportServiceProtocol.swift)).

That gives a direct answer instead of an inference:

- **`updatedAt` ≈ upgrade date** → the template was rewritten when it was opened on the new build.
  The damage is real and recent; find what wrote it.
- **`updatedAt` ≈ months old** → nothing has written to that template since it was created, and it
  has always looked like this.

Per-set `createdAt` goes finer still: sets created seconds apart months ago were added by the user in
one sitting; sets created on the upgrade date were written by the new code.

The `.repstertemplate` export does **not** carry timestamps, which is why the two files already
collected cannot answer this.

---

## Before shipping

Templates were not in the backup archive before this release, so an affected user has **no way to
recover**. Recommended prerequisite regardless of whether the cause is found: on first launch after
an upgrade, silently write a one-time snapshot of all templates to disk *before* any template code
reads or writes them. That turns an unexplained failure into a recoverable one, and gives a
before/after pair from any user who reports it — the artefact that has been impossible to obtain so
far.

---

## Where to look

| | |
|---|---|
| Set parentage writers | `TemplateRepository.replaceTemplateContents`, `ExportService` restore path |
| Editor state → save | `CreateEditTemplateViewModel.buildSaveData` / `applyTemplateDetail` |
| Read path | `TemplateService.fetchTemplateDetail`, `TemplateRepository.fetchTemplateSets(for:)` |
| Reorder that mutates mid-drag | `CreateEditTemplateView` `TemplateExerciseDropDelegate.dropEntered` → `moveExercise` |
| Existing coverage | `RepsterTests/TemplateServiceTests.swift`, `TemplateImportExportTests.swift` |
| Context | `TEMPLATES_IMPLEMENTATION_PLAN.md`, `TEMPLATES_REDESIGN_SCOPING.md` |

---

## Known, not doing

Found while investigating. All three are latent risk, not observed defects — nothing has been
reported against any of them. Written down so they are not re-discovered from scratch.

**Scoped in [TEMPLATE_HARDENING_SCOPING.md](TEMPLATE_HARDENING_SCOPING.md)** — files, tests, sizes and
the open decisions on the snapshot. The summaries below are the why; that document is the what.

**1. A folder move rewrites the whole template.** `TemplateListViewModel.setFolder` reads the full
detail and pushes it back through `replaceTemplateContents` to change one nullable string, so filing a
template deletes and recreates every exercise and set row. The round trip is correct, but a gesture
that should change a label goes through the most destructive path in the feature — and it is what
resets the timestamps above. Fix is a service method that touches `WorkoutTemplate.folder` and
nothing else.

**2. `fetchTemplateDetail` hands `@Model` objects across the actor boundary.** `fetchAllTemplates` was
converted to value types in the rework; the detail read was not. It faults `templateExercise.id` on
the `TemplateService` actor and feeds it into the next query — the query that establishes set
parentage — which is the crash class `TemplateRepositoryProtocol`'s own doc comment names. Also
`1 + E` actor round trips per read. Convert it the way `fetchTemplateListRows` already is.

**3. No pre-write snapshot of templates.** Templates entered the backup archive only in this release,
so a user whose templates come out wrong has no way back and no before/after to diagnose from. A
one-time snapshot to disk on first launch after an upgrade, written before any template code reads or
writes, turns the next unexplained failure into a recoverable one. It would not have helped here —
the damage predates it — but it is the only thing that would help next time.

## Done since

- `ExerciseService.deleteExercise` now cascades to templates (see above).
- The last four editor writes that addressed exercises by array position — the note action, the
  rest-time field and the notes editor — now go through `updateExercise(id:_:)`, completing the
  conversion `5736b35` started. `TemplateExerciseCard` no longer stores an index at all, and
  `SupersetCandidate.index` (dead, read by nothing) is gone with it. One of those four was an
  unguarded subscript that could go out of bounds once the array shrank.
- **The editor no longer presents a saveable form for a template it failed to read.** A throw, a
  missing template, or a read that comes back with no exercises when the list says the template has
  some, all set `loadFailed`: the form is not rendered at all and Save is blocked, with a Try again.
  Previously the editor showed a blank form indistinguishable from an empty template, and saving it
  replaced the real contents. `expectedExerciseCount` comes from the list row, so a template that is
  *genuinely* empty — every exercise it used was deleted — is not caught; a second read that is also
  empty is accepted as the truth so that one stays editable.
- **A generation guard on the load**, so a superseded read cannot land after a newer one and put one
  template's contents in front of another template's id. Defensive only: `TemplateFlowView` gives the
  editor a fresh identity per route (`.id(route.id)`), so the id never changes under a live view and
  the window is not currently reachable. Not separately tested for that reason.
- Suite: 761 passing, 0 failures.
