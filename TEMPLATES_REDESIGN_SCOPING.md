# Templates Redesign — Scoping

**Status:** scoping. Visual direction **settled 2026-09-01** — see
[TEMPLATES_IMPLEMENTATION_PLAN.md](TEMPLATES_IMPLEMENTATION_PLAN.md) for the build plan and
`design/templates/` for the artboards. The feature questions in §6 are still open. Nothing built.
**Date:** 2026-08-31, updated 2026-09-01
**Branch:** NewMain
**Related:** [FEATURE_SCOPING_BRIEF.md](FEATURE_SCOPING_BRIEF.md) §7 (supersets),
[1_5_DECISION_RECORD.md](1_5_DECISION_RECORD.md) "Workout blocks",
[SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) (execution settled 2026-08-31: marked-only),
[design/superset/](design/superset/) (the canvas behind it),
[SUGGESTION_PROGRESSION_DESIGN.md](SUGGESTION_PROGRESSION_DESIGN.md) P2,
[COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md)

---

## What we're deciding

Three threads arrived together and are being scoped as one because they share a root cause:

1. **Structure** — does the templates feature keep its current three-level shape, given the
   workout it produces only has two levels?
2. **Supersets** — templates are the only place a superset can be authored, and the authoring
   model is at odds with how the workout stores grouping.
3. **Cleanup** — the feature has accumulated a large AI-assist surface, an unbalanced test suite,
   and several dead fields. What goes?

The AI helper deletion is a live proposal and is scoped in §5 with the case both ways.

**This document does not settle the interaction design.** It establishes what is true, what it
costs, and what the design phase has to decide.

---

## 0. The feature as it stands

~3,700 lines:

| File | Lines | Holds |
|---|---|---|
| [TemplateListSheet.swift](Repster/Features/Templates/Views/TemplateListSheet.swift) | 1,079 | list + AI helper + import review + prompt builder |
| [TemplateService.swift](Repster/Core/Services/TemplateService.swift) | 770 | CRUD, start-workout, save-from-workout, import/export |
| [CreateEditTemplateView.swift](Repster/Features/Templates/Views/CreateEditTemplateView.swift) | 737 | editor |
| [TemplateServiceProtocol.swift](Repster/Core/Services/Protocols/TemplateServiceProtocol.swift) | 328 | 20 DTOs |
| [CreateEditTemplateViewModel.swift](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift) | 352 | editor state |
| [TemplateCardView.swift](Repster/Features/Templates/Views/Components/TemplateCardView.swift) | 206 | list row |
| [TemplateListViewModel.swift](Repster/Features/Templates/ViewModels/TemplateListViewModel.swift) | 97 | pass-through to service |
| [TemplateRepository.swift](Repster/Core/Repositories/TemplateRepository.swift) | 94 | SwiftData access |

Three models joined by loose UUID foreign keys — no SwiftData relationships, no cascade delete.
The repository hand-rolls the cascade ([TemplateRepository.swift:57](Repster/Core/Repositories/TemplateRepository.swift:57)).

Two entry points: `StartWorkoutSheet` → "Use Template" → `fullScreenCover`
([ContentView.swift:446](Repster/App/ContentView.swift:446)), and "Save as Template" on the
workout summary ([WorkoutSummarySheet.swift:883](Repster/Features/Workout/Views/WorkoutSummarySheet.swift:883)).

---

## 1. The finding that shapes everything: templates model a shape the workout cannot hold

There is **no `WorkoutExercise` model**. A workout is `Workout` + a flat `[WorkoutSet]`. A template
is three levels: `WorkoutTemplate` → `TemplateExercise` → `TemplateSet`.

So `startWorkoutFromTemplate` is a lossy flatten. Of the five fields on `TemplateExercise`, two die
in transit:

| Field | Fate |
|---|---|
| `exerciseId` | survives (onto each `WorkoutSet`) |
| `orderInTemplate` | survives (as `orderInWorkout`) |
| `supersetGroupId` | survives on the model, read by nothing — see §2 |
| **`restTimeSeconds`** | **never read.** [ActiveWorkoutViewModel.swift:513](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:513) resolves rest from `Exercise.defaultRestTime` (library-wide) or the global setting |
| **`notes`** | **never carried in.** `WorkoutSet.notes` is per-set and starts nil |

Both dead fields are authored in the editor, persisted, exported, and re-imported. The user has no
way to learn they do nothing.

The reverse direction is lossy too. `createTemplateFromWorkout`
([TemplateService.swift:314](Repster/Core/Services/TemplateService.swift:314)) has to
*reconstruct* the exercise level by grouping sets on `exerciseId`, and writes `restTimeSeconds` and
`notes` as nil because the workout never held them.

**And there is no link back.** `Workout` has a `programId` (vestigial, see T7) but no `templateId`.
Once a workout starts, nothing knows it came from a template. Consequences:

- No "how has Push Day progressed over eight weeks" — the app's most natural coaching question about
  a template cannot be asked.
- No "3 templates use this exercise" when editing or deleting an exercise.
- Editing a template cannot offer to reconcile anything, because nothing is downstream of it.
- `lastUsedAt` is the only trace, and it is stamped at start
  ([TemplateService.swift:304](Repster/Core/Services/TemplateService.swift:304)) — abandoning the
  workout ten seconds later still counts as "used".

**This is the root cause of §2, most of §3, and F1/F5 in §4.** Every design option below is really
an answer to one question: *do the two shapes converge, or does the template stop promising
structure the workout cannot keep?*

### The three ways out

| | Approach | Cost | Consequence |
|---|---|---|---|
| **A** | Add `WorkoutExercise` — workouts grow the level templates already have | Large. Touches the biggest, least-tested surface in the app (`SetTableView` 2,051 lines, both workout view models) | Everything below becomes easy. Supersets, per-workout rest, per-workout exercise notes, template lineage all fall out |
| **B** | Denormalise — push the exercise-level fields down onto every `WorkoutSet` | Small–medium. New nullable columns, a migration | Fixes the dead fields without restructuring. Grouping stays per-set, which is what §2 says is already wrong |
| **C** | Shrink the template — delete `restTimeSeconds` and `notes` from `TemplateExercise` | Smallest. Deletes code and a migration | Honest immediately, but forecloses supersets and the competitor asks in F6/F7 |

The decision record already leans toward a fourth framing — a **block** above sets, which is
option A restricted to the grouping case. Worth deciding whether templates adopt that vocabulary
or stay separate. See §6 Q1.

---

## 2. Supersets: execution is settled, authoring is not

**Read [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) first.** The direction was settled 2026-08-31:
**option (c), marked only** — grouped exercises are marked in the tab strip, no rest inside a group,
navigation never automatic. In-workout creating and dissolving a group is in scope there, and so is
the `SetRepository.create` defect. **None of that belongs to this document.**

What that doc leaves to templates is the authoring half, and it is not sound:

**2.1 The two sides disagree about what a group belongs to.** Templates store grouping
**per exercise** (`TemplateExercise.supersetGroupId`); workouts store it **per set**
(`WorkoutSet.supersetGroupId`). Template→workout propagation works
([TemplateService.swift:292](Repster/Core/Services/TemplateService.swift:292)) — verified, not
assumed — but the two models are not the same model, and the seam is where the bugs live.

**2.2 The workout→template direction uses the derivation the supersets doc calls wrong.**
`createTemplateFromWorkout` reads `sortedSets.first?.supersetGroupId`
([TemplateService.swift:350](Repster/Core/Services/TemplateService.swift:350)).
[SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §2.1 rules that derivation out for the workout side —
"wrong whenever the first set predates the grouping" — and prescribes *any non-nil set in the
exercise defines the group*. Save-as-template uses exactly the rejected rule, so a workout grouped
at the rack (first set ungrouped, later sets grouped) **saves as a template with the grouping
silently dropped.**

This is a live defect in a templates file, it is created by the very flow supersets is about to
ship, and it is ours. It should adopt the same derivation rule in the same release.

**2.3 Grouping does not affect ordering.** `startWorkoutFromTemplate` emits sets
exercise-by-exercise in template order. An A/B pair interleaves only if the user happened to author
the two exercises adjacently. Order and grouping are independent fields and only order is honoured
— so a template can express a superset whose generated workout lays the lifts out apart. Marked-only
tolerates this better than auto-advance would have, but the template still describes something the
workout doesn't reproduce.

**2.4 The authoring gesture is backwards.** Grouping is a menu of hardcoded `"A"/"B"/"C"` set on
each exercise independently ([CreateEditTemplateView.swift:327](Repster/Features/Templates/Views/CreateEditTemplateView.swift:327))
— while the view model declares five letters and colours four
([CreateEditTemplateViewModel.swift:54](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:54)).
There is no "pair these two" gesture, nothing prevents a group of one, and nothing prevents a group
whose members are scattered through the list. The user assigns labels to a shared namespace and
hopes.

[SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §7 Q3 hands this question here explicitly: *should the
picker widen past A/B/C?* It notes the mismatch "will look like a bug once grouping is visible
during a workout" — which it is about to be. **The picker is on a clock now.**

**2.5 A superset is exercise-level structure — the level §1 says a workout doesn't have.** Marked-only
works around this by reading grouping off sets rather than needing a container. That is the right
call for shipping, and it does not make §1 go away: reusable superset blocks (F6), per-group rest,
and anything that treats a pair as one unit all still want the level that isn't there.

---

## 3. Technical inventory

Ordered by what a redesign would have to confront, not by severity.

### T1 — `fetchAllTemplates` is O(templates × exercises) in queries

For every template it fetches exercises; for every exercise it fetches sets *and* fetches the
`Exercise` row ([TemplateService.swift:89](Repster/Core/Services/TemplateService.swift:89)). Query
count is `1 + T + 2TE`:

| Library | Queries to render the list |
|---|---|
| 10 templates × 6 exercises | 131 |
| 25 templates × 8 exercises | 426 |

Every one is an `await` hop onto the `@ModelActor`. It runs on every appearance and every pull-to-
refresh. The summary only needs a name, two counts, and muscle groups — this should be one or two
fetches with an in-memory join.

### T2 — Editing is delete-and-recreate, and saves per row

`updateTemplate` ([TemplateService.swift:220](Repster/Core/Services/TemplateService.swift:220))
deletes every `TemplateExercise` and `TemplateSet`, then re-inserts with fresh UUIDs. Two costs:

- **ID churn.** Nothing can hold a durable reference to a template exercise across an edit. That
  forecloses per-exercise history, per-exercise lineage, and any future "this exercise in this
  template" record.
- **Write amplification.** The repository calls `modelContext.save()` once per exercise and once per
  set ([TemplateRepository.swift:39](Repster/Core/Repositories/TemplateRepository.swift:39)). A
  6-exercise × 4-set template is ~31 saves to create, and an edit does a delete pass plus a create
  pass — roughly 60 context saves to change a template's name.

### T3 — A 120 ms sleep papers over a read race

`fetchTemplateDetailWithRetry` ([CreateEditTemplateViewModel.swift:107](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:107))
fetches, and if the result is empty, sleeps 120 ms and fetches again — commented as guarding
"transient empty reads when opening editor immediately after sheet transition". A timing constant
compensating for a consistency problem. Whatever the real cause, it should be found rather than
slept through.

### T4 — Templates are not in the backup

`WorkoutHistoryArchive` carries workouts, exercises, and sets
([ExportServiceProtocol.swift:66](Repster/Core/Services/Protocols/ExportServiceProtocol.swift:66)).
**No templates.** A full backup/restore loses every template. The only escape is per-template manual
`.repstertemplate` export — one file at a time, through a share sheet.

For a feature the analytics guide calls a "strong retention predictor"
([POSTHOG_ANALYTICS_GUIDE.md:144](POSTHOG_ANALYTICS_GUIDE.md:144)), that is the most serious defect
in this document. It is also independent of every design decision — it can be fixed now.

### T5 — Test coverage is inverted

Nine template tests exist, all of them buried in
`RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift` (7,281 lines, named for something
else), at lines 3631–4098. **All nine cover import/export.**

Zero tests for:

- `startWorkoutFromTemplate` — the single most-used function in the feature
- `createTemplate` / `updateTemplate` (the delete-and-recreate path)
- `deleteTemplate` and its hand-rolled cascade
- `fetchAllTemplates` summary counts and sort order
- superset propagation

And **three of the nine are AI-draft tests** that would be deleted with the AI feature. The
least-used path has the most coverage; the most-used path has none.

### T6 — `TemplateListSheet.swift` is four screens

The list (1–407), the AI helper (408–651), the import review sheet (652–932), and the prompt builder
(933–991). The AI helper is 244 lines plus a 59-line prompt string — the single most elaborate
component in the feature.

### T7 — Dead schema next door

`Program`, `ProgramExercise`, `PlannedWorkout`, `PlannedSet` are `@Model`s registered in
`ModelContainerSetup`, listed in `RepsterMigrationPlan`, and wiped by `SettingsService` — and read
by **no feature**. `Workout.programId` is written by nothing. This is a vestigial "programs" schema
sitting exactly where a template redesign would go. Decide whether the redesign absorbs it
(templates → programs is a natural growth path) or deletes it.

### T8 — The feature is invisible in analytics

- `AnalyticsScreen.templates` is defined
  ([AnalyticsServiceProtocol.swift:792](Repster/Core/Services/Protocols/AnalyticsServiceProtocol.swift:792))
  and **never emitted**. No `screenViewed` call exists anywhere in `Features/Templates/`.
- `templateCreated` fires only from the create form
  ([CreateEditTemplateViewModel.swift:175](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:175))
  — not from save-from-workout, not from import. The retention metric undercounts by two of three
  creation paths.
- There is no `template edited`, `template deleted`, or `template duplicated` event.

**This is why §5 cannot be settled with data.**

### T9 — Smaller

- **No template-level notes UI.** `WorkoutTemplate.notes` round-trips through the model, the editor
  view model, and import — but no view writes it. Import-only field.
- **Rep parsing fails silently.** `"6-"` leaves the previous min/max in place
  ([CreateEditTemplateView.swift:679](Repster/Features/Templates/Views/CreateEditTemplateView.swift:679)).
  No validation, no error.
- **`TemplateSetRow` copies model → local `@State` in `.onAppear` only.** Works because rows are
  identity-keyed, but the model stops being the source of truth after first render.
- **The AI prompt hands ChatGPT all 13 `SetType` raw values**
  ([TemplateListSheet.swift:985](Repster/Features/Templates/Views/TemplateListSheet.swift:985)),
  including the ones `SET_TYPES_SCOPING.md` decided to hide and the editor cannot create. The AI
  path can inject set types no other surface can produce or display.
- **Card tile colour is `name.first.asciiValue % 6`** — "Push A" and "Pull A" collide.

---

## 4. Feature gaps

### F1 — There is no way to look at a template · ANSWERED 2026-09-01

Tapping a card **immediately starts a workout**. Editing is behind a "…" menu. There is no detail
view, no preview, no "what's in this". For a screen whose whole job is choosing between similar
things, the only way to see what you're choosing is to commit to it and then look at the workout.

This is the highest-value gap and the cheapest to close.

**Answered:** a template detail view, with Start moved inside it. Plan P3.1–P3.3. The user confirmed
the instant start reads as annoying rather than fast, so the extra tap is a gain, not a cost.

### F2 — No duplicate · ANSWERED 2026-09-01

Building "Push B" from "Push A" means authoring it again or export→import (which appends
"(Imported)" to the name). Every competitor has this.

**Answered:** `duplicateTemplate` behind a labelled Copy action in the detail view. Plan P1.3, P3.3.

### F3 — The list does not organise · ANSWERED 2026-09-01

Flat, sorted `lastUsedAt` DESC then `createdAt` DESC. No search, no folders, no tags, no sections,
no manual order, no favourites, no archive. Fine at five templates. A user running an Upper/Lower
4-day split across two mesocycles has twelve, and they are all called some variation of the same
four words.

A permanent instructional card sits above the list explaining what the buttons do
([TemplateListSheet.swift:287](Repster/Features/Templates/Views/TemplateListSheet.swift:287)) —
usually a sign the UI isn't explaining itself.

**Answered:** user-named folders as **filter chips**, a persistent search field, and dense 60px rows;
`All` falls back to grouped runs. Per-row folder tags were drawn and rejected — they cannot survive
names the app did not choose. Plan P1.1, P2.1–P2.4. The intro card goes.

### F4 — The rep-target trap

The editor parses `"8"` → `targetRepMin = 8, targetRepMax = 8`. That is a **fixed** target, and per
[SUGGESTION_PROGRESSION_DESIGN.md](SUGGESTION_PROGRESSION_DESIGN.md) P2 — **still open** — a fixed
rep target can never progress. The engine hands back the last performance forever.

**The template editor is the app's primary producer of exactly that shape**, and gives no signal.
Typing `6-8` avoids it entirely. A user authoring "5×5" is quietly opting out of the app's headline
feature.

Related: targets are per-set, but the collapsed card summary reads only the *first* working set
([CreateEditTemplateView.swift:375](Repster/Features/Templates/Views/CreateEditTemplateView.swift:375)),
so per-set variation is invisible until expanded.

Whether the fix is in the engine (P2) or in the editor (warn, or reinterpret a single number as a
range) is a design call — but the editor is where the shape is created, so it deserves a say.

### F5 — The superset picker is about to look broken

Covered in part elsewhere: in-workout creating/dissolving is scoped in
[SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §6, so the "can't pair two lifts at the rack" gap is
already owned.

What remains here is §2.4 — a three-letter picker backed by a five-letter, four-colour model, in an
editor that cannot express adjacency. Invisible today. Visible the moment marked-only ships.

### F6 — Reusable superset blocks

[COMPETITIVE_FEATURE_ANALYSIS.md:255](COMPETITIVE_FEATURE_ANALYSIS.md:255): a user has an abs
superset they append to every workout and must redefine each time. Nobody serves this. It fits the
template model naturally — a template that is a *fragment* rather than a whole session, insertable
into a workout or another template.

[SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §9 delegates this here in as many words — "Fits the
template model, not this." It is now a templates deliverable, not an unowned wish.

This is also the strongest argument for keeping templates three-level (option A/B in §1) rather
than shrinking them: a fragment that carries a group is exercise-level structure by definition.

### F7 — Two kinds of exercise note, and no way to tell them apart

`notes` exists on `Exercise`, `TemplateExercise`, `WorkoutSet`, `Workout`, and `WorkoutTemplate`.
[COMPETITIVE_FEATURE_ANALYSIS.md:198](COMPETITIVE_FEATURE_ANALYSIS.md:198) identifies the ask:
`Exercise.notes` means "always, everywhere" (my bench setup), `TemplateExercise.notes` means "in
this routine only". Users complain about being forced to paste the same cue into every routine.
Repster already has both fields — it just never surfaces the distinction, and
`TemplateExercise.notes` currently goes nowhere anyway (§1).

---

## 5. The AI helper — the deletion case · RESOLVED 2026-09-01 (deleted)

### What it is

A three-step ChatGPT copy-paste flow: export your exercise library + stats as JSON → copy a
prompt → paste ChatGPT's JSON response back → review unmatched exercises → save as a template.

### What deleting it removes

| Location | Lines | What |
|---|---|---|
| `TemplateListSheet.swift` 408–651 | 244 | `AITemplateHelperSheet` |
| `TemplateListSheet.swift` 933–991 | 59 | `AITemplatePromptBuilder` |
| `TemplateServiceProtocol.swift` 123–191 | 69 | `AITemplateContextArchive`, `AITemplateDraft` + children |
| `TemplateService.swift` 411–452 | 42 | `exportAITemplateContext` |
| `TemplateService.swift` 671–714 | 44 | AI draft parse branch + version guard |
| `TemplateService.swift` errors | ~8 | two error cases + descriptions |
| `TemplateListViewModel.swift` | 3 | pass-through |
| **Total** | **~469** | plus 3 of the 9 template tests |

Also removed: the `exerciseStatsRepository` constructor dependency on `TemplateService`
([ServiceContainer.swift:158](Repster/Core/Services/ServiceContainer.swift:158)) — it is used by
**nothing else** in that service.

And a simplification falls out: `supersetGroupKey: String?` threads through the entire import
preview layer *only* because AI drafts use friendly keys like "A". The archive path converts
`UUID → uuidString → new UUID` for no reason. With AI gone, the archive path can carry group
identity directly.

### What deleting it does NOT remove

**Import/export of `.repstertemplate` files must survive.** The UTTypes are properly declared in
[Info.plist](Repster/Info.plist) as `UTExportedTypeDeclarations` with the app registered as `Owner`
/ `Editor`, plus legacy `com.magnusespensen.reppo.template` as an imported type. Files exist in
users' Files app and iCloud Drive. Deleting the archive path would strand them.

The `TemplateImportReviewSheet` (281 lines) is shared — the archive path needs it whenever an
imported exercise doesn't match the local library. It stays.

### The case for deleting

- **~469 lines and one dependency, for a flow requiring the user to leave the app, use a second
  product, and paste JSON.** The interaction cost is very high relative to any plausible usage.
- **It is the largest single component of the feature**, and it is not the feature. The list has no
  search and no duplicate; the AI helper has a 59-line prompt.
- **It leaks unsupportable state.** It is the only path that can inject the 11 hidden `SetType`
  values into the database (T9), against a decision already taken in `SET_TYPES_SCOPING.md`.
- **It is a maintenance tax on every schema change.** Every new `Exercise` field has to be added to
  `AITemplateContextExercise`, `AITemplateDraftExercise`, and the prompt's schema example. Three of
  the six places already drift.
- **It carves out a third of the test suite** for the least-used path.

### The case against

- **It is the only bulk-authoring path.** Building a 6-exercise template by hand in the current
  editor is slow, and nothing else fills that gap.
- **It works, and it is careful.** The unmatched-exercise review flow is genuinely well built —
  match by ID, then normalised name, then explicit user resolution. That is more rigour than most
  import features get.
- **It may be a differentiator** for a technically-minded audience — the same audience the
  `technical-lifter` campaign targets.
- **Deleting a shipped feature is user-visible.** Someone has templates they built this way and may
  expect to do it again.

### The honest problem: there is no usage data

Per T8, the templates screen is **never** tracked and the AI helper emits **no** events. There is no
way to answer "does anyone use this" from PostHog today. Deleting it is a judgment call about
cost-to-value, not a data-driven one — and that should be stated plainly rather than dressed up.

Two ways to proceed, and they differ in honesty more than in outcome:

- **Instrument first.** Add `screenViewed(.templates)` and an `ai template imported` event, ship,
  wait one release. Costs a release cycle and ~10 lines. Yields a real answer.
- **Delete on cost grounds now.** The argument stands on interaction cost and maintenance tax
  without needing usage numbers — a flow that requires leaving the app for a second product is hard
  to justify at any usage level below "substantial", and if it were substantial we'd likely have
  heard about it.

**Recommendation: delete, and do the instrumentation anyway** — T8 needs fixing regardless, and the
rebuilt feature should be measurable from day one. But note that this forecloses F-bulk-authoring
unless the redesign answers it another way (duplicate, template fragments, a better editor). If the
redesign does not improve authoring speed, deleting the AI helper makes the feature worse for the
users who used it.

---

## 6. What the design phase has to decide

**Q1 — Does the workout grow an exercise level, or does the template lose one?**
The §1 fork. Everything else depends on it. Note the decision record's "block" concept is a
restricted version of option A; decide whether templates adopt that vocabulary or stay parallel to
it. **This gates the superset work, not the other way round.**

**Q2 — Is a template a session, or a fragment?**
F6 (reusable superset blocks) and the "append my abs finisher" ask only work if a template can be
*inserted* rather than *started*. That is a different mental model and it changes the list, the
editor, and the start flow.

**Q3 — Does the workout remember its template?**
A `templateId` on `Workout` is a one-line schema change that unlocks per-template progression — one
of the most natural coaching questions the app could answer, and adjacent to Repster Coach. It also
raises "what happens when the template changes underneath the history".

**Q4 — Does the editor get an opinion about fixed rep targets?**
F4. Engine-side (P2), editor-side (warn/reinterpret), or both.

**Q5 — Delete the AI helper? · ANSWERED 2026-09-01 — deleted**
Removed in full; `.repstertemplate` import/export stays. Bulk authoring is now served by **Duplicate**
(plan P1.3) rather than a round trip through a second product. The analytics added in P0.2 mean the
next comparable question can be answered with data rather than judgement — which this one could not be.

**Q6 — Absorb or delete the `Program`/`Planned*` schema?**
T7. Templates → programs is the obvious growth path; the schema is already there and already
migrated.

**Q7 — How do supersets get authored in a template? · ANSWERED 2026-09-01**
By picking a **partner**, not a letter — the app assigns the letter. This supersedes
[SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §6's "drive the menu from `supersetLetters`" bullet, which
is now marked superseded there; the rest of §6 (letter as identity, colour cycling mod 4, pairs only,
contiguity) stands and is what the plan implements. Grouping stays per-exercise in templates and
per-set in workouts. Plan P4.3.

---

## 7. Sequencing

Three tiers, and the first does not depend on any design decision:

**Tier 0 — owed regardless, ship independently**

1. **T4 — templates in the backup archive.** The most serious defect here; unrelated to any
   redesign. Needs an archive version bump.
2. **T8 — instrument the feature.** `screenViewed(.templates)`, `templateCreated` from all three
   creation paths, plus edit/delete/start events. ~10 lines, and it makes every later decision
   measurable.
3. **§2.2 — `createTemplateFromWorkout` group derivation.** Adopt *any non-nil set defines the
   group* instead of `sortedSets.first`, matching
   [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §2.1. Small, and it should land in the same release
   as that doc's item 1 so the two directions agree. (The `SetRepository.create` fix itself is
   theirs, not ours.)

**Tier 1 — cleanup, independent of the structural decision**

4. **§5 — delete the AI helper** (if Q5 says so). ~469 lines out.
5. **T5 — extract template tests** into `TemplateServiceTests.swift`, and cover
   `startWorkoutFromTemplate` before touching anything.
6. **T1 — fix the N+1** in `fetchAllTemplates`.
7. **T6 — split `TemplateListSheet.swift`** by screen.
8. **F1/F2 — detail view and duplicate.** Highest user-visible value per line in this document.

**Tier 2 — blocked on Q1**

Everything else. The dead fields (§1), supersets (§2), template lineage (Q3), fragments (Q2) are all
the same decision wearing different clothes, and none of them should be built before it is taken.

---

## 8. Explicitly out of scope

- **Superset execution behaviour, in-workout grouping, superset history, and the
  `SetRepository.create` defect** — all owned by [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md), where
  the direction is already settled (marked-only) and the work is broken down. This document covers
  template *authoring* only, plus the one workout→template defect in §2.2 that lives in a templates
  file.
- **Metcon / AMRAP / EMOM blocks** — the decision record already established that `TemplateSet`
  cannot express a metcon (one rep number + time cap + unknown rounds) and that a metcon needs its
  own container. If Q1 lands on a block model, revisit; otherwise not here.
- **`SetType` visibility** — settled in [DROP_SETS_SCOPING.md](DROP_SETS_SCOPING.md). The only
  overlap is that the AI prompt violates that decision (T9), which §5 resolves by deletion.
- **Suggestion engine P2** — F4 flags that templates create the problematic shape; fixing the engine
  belongs to [SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md](SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md).
- **`SetTableView` restructure** — already deferred by the decision record, and folding it into a
  templates redesign would hide a row redesign inside a different feature.

---

## 9. Open questions I could not answer from the code

1. **Does anyone use the AI helper?** Unanswerable today (T8). Blocks a data-driven Q5.
2. **How many templates does a typical user have?** Determines whether F3 (search/organisation) is
   urgent or speculative. Also unanswerable today.
3. **Is per-template rest time wanted, or was it built speculatively?** It has never worked (§1), so
   no user has experienced it. Deleting it is as defensible as fixing it.
4. **Are there `.repstertemplate` files in the wild?** Affects how carefully the archive format has
   to be preserved through a redesign. The UTType registration suggests the path was taken
   seriously; whether it was used is unknown.
