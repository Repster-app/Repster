# 1.5 — Decision Record

**What this is:** why things were *not* done. One entry per feature area.

This is the counterpart to [RELEASE_1_5_PLAN.md](RELEASE_1_5_PLAN.md), which says
what 1.5 contains. This file says what was considered and dropped, what was argued
about, and what turned out to be wrong — the things that are invisible a month
later and get rediscovered the hard way.

**Read an entry before restarting work on that feature.** Scoping docs say what to
build; this says why the obvious version wasn't built.

---

## Index

| Feature area | Status | Scoping doc | Session |
|---|---|---|---|
| [Muscle coverage](#muscle-coverage) | Scoping only, Phase 1 may ride 1.5 | [SECONDARY_MUSCLES_SCOPING.md](SECONDARY_MUSCLES_SCOPING.md) | "Secondary muscle group" |
| [Exercise replace & reorder](#exercise-replace--reorder) | Scoping only; two live defects found | [EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md) | "Improve exercise replacement and move left UI" |
| [Set types](#set-types) | Scoping only, not proposed for 1.5 | [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md) | "Available set types" |
| [Workout blocks](#workout-blocks) | Interaction design in progress, nothing built | none yet — artifacts only | "Workout tracking in Repster" |
| [Unperformed sets & exercise removal](#unperformed-sets--exercise-removal) | Scoping only; live data defect on shipped builds | [UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md) | "Incomplete workout logging behavior" |
| [Competitive demand analysis](#competitive-demand-analysis) | Analysis only; no code, no release commitment | [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md) | "Hevy feature requests summary" |
| [Smart Suggestions undershoot](#smart-suggestions-undershoot) | Design only, guardrail specced | [SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md) | "Smart suggestion logic for new exercises" |
| [Coaching tiles](#coaching-tiles) | Exploration only; parked, nothing built | [COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md) | "Training insights and Monthly stats positioning" |

---

## Conventions

**Verdict vocabulary** — every dropped item gets exactly one:

| Verdict | Means |
|---|---|
| *rejected* | Considered and decided against. Don't re-propose without new information |
| *deferred* | Wanted, not now. Should say what unblocks it |
| *left alone* | Touching it would make the surface worse |
| *out of scope* | Unrelated to this feature; recorded because it looks related |
| *superseded* | An earlier decision this one replaces |

**Entry rules**

- Append new entries at the bottom. Never rewrite someone else's entry — add a
  *superseded* line to it and write a new one
- Record contentions in the user's own framing, not a tidied paraphrase
- Record corrections even when embarrassing. A wrong number is remembered longer
  than its fix
- Don't restate the scoping doc. Link it and stay on the *why not*
- Keep entries under ~120 lines

---

## Entry template

Copy this block for a new feature area.

```markdown
## <Feature name>

**Date:** YYYY-MM-DD
**Session:** "<session title>" (`<session-id>`), branch `<branch>`
**Scoping doc:** [NAME.md](NAME.md)
**Status:** <one line>

### The feature area
2–4 sentences. What it is and what exists today.

### Documents
| Doc | What it holds |
|---|---|

### Release position
Where it sits and why. If it was pushed out of a release, say what that protected.

### Deliberately NOT done, and why
The core section. One bolded item per decision, each tagged with a verdict, each
with the reasoning that would otherwise be lost.

### Main contentions
The objections raised, and what each one changed. Number them.

### Corrections on record
Claims that turned out wrong, with the corrected fact. Omit if none.

### Where it stands
Status, what blocks the next step, and the single open question that matters most.
```

---

## Prompt for other sessions

Paste this into any session that has finished scoping a feature.

```
Append an entry to 1_5_DECISION_RECORD.md in the repo root for the feature area we
just worked on.

Read the file first: follow its entry template and verdict vocabulary exactly, and
append at the bottom rather than editing existing entries. Add a row to the Index
table at the top.

The point of this file is why things were NOT done, so a reader in a month
understands the reasoning without re-deriving it. Specifically:

- The largest section must be what was deliberately not done. Tag each item
  rejected / deferred / left alone / out of scope, and give the reasoning that
  would otherwise be lost. "Deferred" should say what unblocks it.
- Record my objections and pushback in my own framing, and what each one changed
  about the plan. If I made you rethink an approach, that belongs here.
- Record any claim you made that turned out to be wrong, with the correction.
- Don't restate the scoping doc — link it and stay on the reasoning.
- End with what blocks the next step and the single open question that matters most.
- Keep it under ~120 lines. Concise, no filler.

For the session identity line: my session transcripts are in
~/.claude/projects/<project-slug>/<session-id>.jsonl and carry `customTitle` and
`aiTitle` fields — read the title from there rather than guessing. The session id
is the directory name in your scratchpad path.
```

---

# Entries

## Muscle coverage

**Date:** 2026-08-18
**Session:** "Secondary muscle group" (`905abb53-9230-4ac1-959e-9aadad6bcac0`), branch `NewMain`
**Scoping doc:** [SECONDARY_MUSCLES_SCOPING.md](SECONDARY_MUSCLES_SCOPING.md)
**Status:** scoping only, nothing built. Phase 1 may ride 1.5; Phase 2 proposed for 1.6

### The feature area

Users tracking **which muscles they train** — while planning a routine, right after
a workout, and over time.

`Exercise.secondaryMuscles` has existed since the first commit. It is persisted,
seeded (54 of 69 exercises, 96 tags), exported, and carried through templates — and
**read by nothing**. Everything muscle-related keys off `primaryMuscle` alone. The
work is giving that field consumers.

### Documents

| Doc | What it holds |
|---|---|
| [SECONDARY_MUSCLES_SCOPING.md](SECONDARY_MUSCLES_SCOPING.md) | Three phases, the taxonomy problem, all technical detail |
| [RELEASE_1_5_PLAN.md](RELEASE_1_5_PLAN.md) | Full 1.5 scope — this is Part 3 |
| [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md) | Demand evidence. Ranks this 4th |

### Release position

Not in 1.4. That release is privacy-and-measurement, still unshipped, ~138 open
items. Its attribution work is forward-only and can't be backfilled, so adding
features to it costs measurement that can never be recovered. Nothing here
justified that.

### Deliberately NOT done, and why

**Fine-grained taxonomy** (glutes, quads, hamstrings, calves, front/rear delts as
first-class groups) — *deferred.* Would change the **primary** taxonomy too:
migration, seed re-tag, new filter pills, new colors, and a visible shift in every
user's insights baselines. The rollup to `legs` gets most of the value for a lookup
table. **Unblocked by:** users asking for the split by name.

**Per-exercise credit values** — *rejected.* 96 tags to author by hand, UI on every
custom exercise, and the AI generator emitting numbers it gets wrong — for
precision that mostly cancels out (contention 3).

**Insights panel weighting, Phase 3 entirely** — *deferred.* The two surfaces users
asked for need no arithmetic. Weighting only affects the panel that already exists.
**Unblocked by:** Phase 2 shipping.

**`MuscleBalanceInsightRule`** — *left alone, permanently.* It compares groups
*against each other*, which is exactly where a flat credit distorts — inflating
frequently-secondary groups (triceps, shoulders, abs). Leaving it also keeps its
tuned thresholds working.

**Charts donut** — *left alone.* One set fanning into several slices means the pie
stops summing to the total.

**Home / Calendar workout dots** — *left alone.* Include secondary and nearly every
workout shows the same three dots. The signal dies.

**Fatigue / e1RM model** — *out of scope.* `FatigueLearningService` is per-exercise
with no muscle concept. Recorded because the technical positioning leans on it and
it looks related.

**Settings toggle** — *deferred* with Phase 3. Coverage display is information and
needs no setting. A toggle is only warranted once numbers users have seen change.

### Main contentions

**1. "Not sure I understand what your suggestion is?"**
The first scoping gave options without picking one. Fixed by forcing a single
recommendation per decision. A future doc that reads as a menu is the same failure.

**2. "I'm not sure what you mean by weight?"**
In a lifting app "weight" means kilos on the bar. The multiplier was renamed
**credit** throughout. Keep it that way.

**3. "That's a whole can of worms — it's super dependent on the specific exercise."**
Correct, and it held. But the panel compares each muscle to *its own baseline*
computed under the same rule, so the constant appears on both sides and largely
cancels: 0.5 vs 0.7 changes the printed number, not whether a row reads up or down.
That's why a flat constant survived — and why the balance rule, where it *doesn't*
cancel, was pulled out of scope.

**4. "Is this mostly in the insights context? I just want users to be able to keep
track of their muscle groups."**
The important one. The scoping had been built around insights attribution because
insights is the only place muscle data is consumed today — reasoning from the code
rather than from the user. Checking the two surfaces nobody had looked at found
**both empty**: no muscle overview in the routine editor, none on the post-workout
sheet. The doc was rewritten around coverage and the credit debate shrank to one
deferred panel.

### Corrections on record

An early claim that the rollup would leave ~44% of seed tags inert was **wrong**.
Measured: **59 of 96 survive**, and 41 of 69 exercises gain at least one group —
Deadlift gains legs, Bench gains shoulders and triceps. The rollup is worth more
than that estimate suggested.

### Where it stands

- **Blocking before any code:** the taxonomy rollup and the dedupe helper. Small, but first
- **Phase 1** (rollup, helper, editor picker, detail display) — rides 1.5 if convenient
- **Phase 2** (routine coverage overview, post-workout summary) — proposed 1.6 headline. This is the feature
- **Phase 3** — deferred, no date

Cheapest thing available: the exercise editor picker. `CreateEditExerciseViewModel`
already reads and writes the field — a missing control, not missing plumbing.

**Open question that matters most:** does the routine overview show *coverage*
("hits chest, shoulders, triceps") or *volume per muscle*? Coverage is simpler,
needs no weighting, and matches what was asked for. Volume drags Phase 3's credit
constant into Phase 2.

---

## Exercise replace & reorder

**Date:** 2026-08-18
**Session:** "Improve exercise replacement and move left UI" (`4e3d72e3-9cdd-4ec3-82c1-58cb47d3df3e`), branch `NewMain`
**Scoping doc:** [EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md)
**Status:** scoping only, nothing built. Two live defects found in existing reorder; their fixes are sequenced *ahead* of the feature

### The feature area

Swapping an exercise mid-workout without losing its position. Today the only route is
delete → add (lands at the end) → Move Left N times, from the tab strip context menu.
Asked for as a replace-in-place action, plus "move left being made better."

Investigating it turned up two defects in the reorder path that already ship.

### Documents

| Doc | What it holds |
|---|---|
| [EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md) | Both defects, replace design, risk register, test plan, sequencing |
| [SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md](SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md) | §5.3 — the fan-out pattern reorder still uses |
| [SWIFTDATA_CRASH_WORK_RECORD.md](SWIFTDATA_CRASH_WORK_RECORD.md) | §2.3 — the migration that missed this caller |

### Release position

Not assigned to a release in this session. The two defect fixes are argued as shippable
independently of the feature: both are small, one is a deletion, and both sit on the active
logging path where they are live now.

### Deliberately NOT done, and why

**Reassigning `exerciseId` onto the existing sets** — *rejected.* The cheap replace: keep the
rows, retarget them. It writes fabricated history into the new exercise's PR table, e1RM series,
charts and fatigue model, and silently removes it from the old one's. 80 kg × 8 logged for Incline
DB Press is not a Cable Fly set. Wrong data the user cannot see is wrong is worse than no feature.

**Drag-to-reorder on the strip itself** — *rejected.* Has to arbitrate against the horizontal
`ScrollView` pan and the existing long-press context menu on the same views. A gesture-precedence
problem on the most safety-critical screen in the app, for a cosmetic gain.

**"Reorder Exercises" sheet (`List` + `.onMove`)** — *deferred.* The real fix for O(n) taps, and
cheap. But walking a tab left is overwhelmingly what you do *because* you were forced to
delete-and-re-add. **Unblocked by:** replace shipping and the complaint surviving it.

**A real exercise-order field on the schema** — *deferred.* Order is reconstructed on load from
`MIN(orderInWorkout)` across each exercise's sets; a stored order would make all of this simpler.
It is a workout schema migration and is not justified by this change alone. **Unblocked by:**
supersets going ahead, which needs somewhere to put grouping anyway.

**Building replace first, defects after** — *rejected.* Replace reuses the same renumbering
machinery and the same selection logic. Built on today's reorder it inherits both defects
somewhere harder to see. Hence steps 1–3 before step 4.

**Hiding replace on the historic-edit screen** — *rejected.* `EditWorkoutViewModel` shares the
protocol and the strip, so the menu item appears there for free. Conditionally suppressing it
costs more than implementing it, and divergence between the two view models is exactly the drift
`PRBadgeApplier`'s doc comment records as a prior near-miss.

**Making `selectedExerciseIndex.didSet` fire unconditionally** — *rejected.* Would fix the skipped
side effects in one line, and double-fire them on the common tap-a-tab path. An explicit
"exercise changed" trigger alongside the existing "index moved" one instead.

**Undo for replace** — *rejected.* Delete has no undo today. Adding it for one destructive
operation and not its neighbour is worse than neither.

**Supersets / grouped exercises in the strip** — *out of scope.* The strip needs rework there, but
neither blocks the other. Recorded because both are "the tab strip."

**Stale IDs in `workout.excludedExerciseIdsFromProgressionHistory` after a replace** — *out of
scope.* Exclusions are only set from the historic-edit screen, and the write path sanitizes by
intersection with the workout's actual exercise IDs. Looked like a work item; isn't one.

### Main contentions

**1. "We cannot afford to mess up this part of the app, so lets scope it really thoroughly
before we build."**
The one that changed the outcome. The first answer offered to start immediately with the selection
fix — small, standalone, real. That fix was correct and would have landed on top of a caller still
running the pattern that caused a shipped crash, and been followed by a replace feature that
silently reorders itself on relaunch. Neither was visible from the first pass. The thorough version
is what found both.

**2. "we scoped something about the ui not updating properly when moving left, i dont think we
implemented it? or else it doesnt work."**
Treated as a memory to verify rather than a fact, and it split: there was **no** scoping doc and no
commit — that half of the recollection was wrong — but the bug is real and was reproduced from the
code. Worth keeping: "we scoped this" did not survive checking; "it doesn't work" did.

### Corrections on record

**The batched ordering API was already built.** Claimed in the first answer that
`STAGE2_WRITE_PATH_DESIGN.md` §4's `setService.reorder(ordering)` "was never built" and that fixing
reorder meant building it. Wrong — it shipped as `SetService.applyOrdering`, backed by
`SetRepository.applyOrdering`, with `reindexOrderInWorkout()` and `persistSetOrdering()` sitting in
the same view model as `reorderExercises`. The real finding is different and worse: the migration
was scoped as *"reindexing after a set insert/delete,"* so `reorderExercises` fell outside it and is
now the last caller still doing per-set `edit()` in unawaited Tasks. Changed the fix from "build an
API" to "delete a loop" — and changed its severity, because the pattern is documented as the
concurrent writer that armed crash B.

**Stale History/PR rows are a flash, not a stuck state.** First framed as a headline symptom of the
selection bug. Tracing `loadHistoryForCurrentExercise` shows the `.task(id:)` refetch self-corrects;
the cache is just never cleared first. The durable damage is elsewhere: Live Activity name,
persisted resume state diverging from the screen, and the keypad left bound to a deleted row.

### Where it stands

- **Blocking any replace code:** steps 1–3 — identity-based selection, the fan-out deletion, and
  journey tests for reorder. There is currently **no** journey test for reorder at all, and the
  journey harness is the only level that caught the last two ordering defects
- **Known casualty:** `testReorderExercisesPreservesMovedSelectionAndPersistsContiguousOrder` asserts
  `editedSetIds`, so it pins the implementation being removed. It fails *by design* in step 2 —
  rewrite against `SetServiceStub.orderingBatches`, which the stub already records. Flagged so the
  failure is not read as a regression
- Five decisions open at §10 of the scoping doc

**Open question that matters most:** confirm that replace **deletes** the outgoing exercise's logged
sets rather than carrying them over. Everything in §4.4 is ordered around it, and the alternative
isn't a variation on the design — it's a different feature with data-integrity consequences that
reach the PR table, e1RM series and fatigue model.

---

## Set types

**Date:** 2026-08-18
**Session:** "Available set types" (`082bb6e2-c1ae-4045-a984-5c5d7a832d07`), branch `NewMain`
**Scoping doc:** [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md)
**Status:** scoping only, nothing built. Not proposed for 1.5

### The feature area

`SetType` has 13 cases. Two do real work — `warmup` (badge, own rest default, excluded
from volume/PR/charts/learning) and `partial` (excluded from everything). The other 11
are labels the user cannot see, attached to features that were never built.

Their only behavior is a fatigue coefficient that silently scales prescribed weight.
Nobody knew it was there.

### Documents

| Doc | What it holds |
|---|---|
| [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md) | Three phases, the Group A/B split, all technical detail |
| [RELEASE_1_5_PLAN.md](RELEASE_1_5_PLAN.md) | Part 7 — listed as scoped, not a commitment |
| [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md) | Largest single gap, ~16 requests |

### Release position

Part 7 of the 1.5 plan: open design doc, no commitment. The standing 1.4-first
constraint applies. Phase 1 (the fatigue decoupling) is independent of the product
work and could ride any release, but it does change shipped suggestion behavior for
importer users — so it needs a deliberate slot, not a drive-by.

### Deliberately NOT done, and why

**Authored per-type fatigue multipliers** — *rejected.* The 0.5–1.5 coefficients appear
in no design doc and no commit message. They can never be validated: `FatigueObservation`
has no `setType`, and the learner collapses a session to one median error, nudging a
single per-exercise rate *and* the global profile rate. A wrong coefficient is absorbed
into the learned rate and reapplied to every set of that exercise. Replace with a flat
1.0 (warm-up 0.0, partial 0.5) and record `setType` on observations.

**Deleting the multipliers outright** — *rejected.* Cheaper than flattening + instrumenting,
but throws away the only path to ever learning real per-type values from data.

**Deleting the 12 unbuilt cases** — *rejected.* Raw values persist in SwiftData, ride the
JSON archive, and **both** importers emit `dropset`/`failure`. Deletion needs a migration
mapping or old archives fail to decode. Real user data already carries these types.

**Cutting just `tempo` / `isometric` / `eccentric`** (no import path, no demand evidence)
— *rejected.* Same migration cost for three cases nobody asked about. The real problem
with the list is that the context menu shows 13 undifferentiated options; group it instead.

**The sub-set primitive — drop set, rest-pause, cluster, myo-rep** — *deferred.* All four
need the same thing: a set containing sub-sets. Building it per-type would produce four
half-mechanisms. **Unblocked by:** designing that model once, against the existing
`supersetGroupId` and `pauseDuration`, rather than inventing a second grouping mechanism.

**A new column for the type indicator** — *rejected.* The row already spends 162pt on fixed
columns (36 badge / 42 RIR / 44 PR / 40 checkbox) before inputs get anything. The indicator
has to reuse the badge column warm-up already repurposes.

**Type visible only in the expanded/edit state** — *rejected.* Cheapest option, but fails
the actual complaint: you still can't scan a finished workout and see which set was which.

**`WorkoutSet.pauseDuration`** — *left alone.* Persisted, exported, written by nothing.
Deleting it costs a migration and destroys a slot that looks purpose-built for rest-pause.

**Warm-up and partial behavior in every consumer** — *left alone.* Correct and well covered.

**The learning algorithm itself** — *out of scope.* Phase 1 adds a field; it does not touch
how the rate is learned.

**EMOM and time-under-tension** (from the competitive analysis) — *out of scope.* Recorded
because they sit in the same request cluster, but neither is a set type.

### Main contentions

**1. "these types dont mean anything in the app right now."**
The first pass had presented the 13 types as a tidy inventory with a multiplier column,
which read as though the ratios were designed behavior. They aren't a feature to extend —
they're a label set that shipped ahead of its features. This produced the doc's central
claim: the enum conflates **execution structure** (4 types needing sub-rows) with **effort
annotation** (7 types needing only a visible badge). The cheap half had been blocked behind
the expensive half for no reason, which is why 13 types shipped with zero features.

**2. "I am also not sure what I feel about the fatigue ratios, didnt know they were built."**
The important one. Prompted tracing the constants instead of reporting them — which found
the structural flaw, not just uncalibrated numbers. Turned "maybe retune these" into a
standalone Phase 1 that shouldn't wait on any product decision.

**3. "Lets scope it out before we start touching anything."**
The flatten is small enough (two test assertions, one diagnostics row, one field) to be
tempting as a drive-by. Correctly held back: it shifts suggestions for anyone who imported
from Strong or Hevy, which belongs in release notes rather than in a scoping session.

### Corrections on record

The import exposure was first reported as **Hevy only**. Wrong — **Strong** also emits
`dropset` and `failure`, mapping `W`/`D`/`F` at
[ImportService.swift:991](Repster/Core/Services/ImportService.swift:991). Two importers,
not one. This roughly doubles the population holding non-`working` types in real data and
is the main reason deleting cases is rejected rather than merely awkward.

### Where it stands

- **Phase 1** (flatten multipliers, record `setType` on observations) — independent, small,
  ready. Needs a release slot because it changes shipped suggestion behavior
- **Phase 2** (visible badges for the 7 annotation types, grouped context menu) — the thing
  users would notice. No schema change
- **Phase 3** (sub-set primitive) — a real feature project, no date

**Blocking the next step:** whether Phase 1 ships on its own or waits for Phase 2. Shipping
it alone means telling importer users their suggestions moved, with nothing visible in
exchange.

**Open question that matters most:** should annotated sets count toward PRs like working
sets? Today AMRAP, failure and back-off all count identically. A set taken to failure is
legitimate PR evidence, an AMRAP arguably the best, back-off is not. Phase 2 ships badges
that imply the app knows the difference — it doesn't.

---

## Workout blocks

**Date:** 2026-08-18
**Session:** "Workout tracking in Repster" (`dd93a528-cc41-491f-8fef-e912e3955565`), branch `NewMain`
**Scoping doc:** none in repo yet — see Documents
**Status:** interaction design in progress at user's direction. No technical scope agreed, no code

### The feature area

A **block**: a container above sets holding one or more exercises plus a rule for advancing
through them — straight sets, superset, circuit, AMRAP, EMOM. Started from a support question
(20-min AMRAP of pull-up / push-up / air squat) the app cannot express: there is no rounds
concept, and `supersetGroupId` exists on the model and in template authoring but **nothing in
`Features/Workout/` reads it**.

### Documents

| Doc | What it holds |
|---|---|
| [Design sketch](https://claude.ai/code/artifact/ed5be1f7-43cc-4871-a715-50b7ba9edfcb) | Block concept, schema shape, PR-safety matrix |
| [Impact audit](https://claude.ai/code/artifact/1a90add2-0ae2-487e-9454-413e74af5d5a) | 31 subsystems graded, 5 add/edit surfaces, 7 landmines |
| [Interaction patterns](https://claude.ai/code/artifact/7d1a7833-3524-4c09-9bd4-32c4f1d8b826) | Current thinking. Tally counter, bracket grammar, row reduction, templates |

**No repo scoping doc exists** — deliberate. The user stopped technical scoping to settle
interaction first. Write one before any code.

### Release position

Not in 1.5. Nothing built or committed to. The interaction model was still moving as of this
entry, and its last change (tally counter) altered the technical shape enough that scoping
earlier would have scoped the wrong thing.

### Deliberately NOT done, and why

**One screen for all block types** — *rejected.* A superset is a precision instrument (weight
varies, logged live, the number is the point). A metcon is a pace instrument (taps-per-minute
binds). Forcing both through one interface generated most of the open questions; splitting them
dissolved them.

**Per-round rep logging in metcons** — *rejected.* The first sketch put three checkboxes in every
round: 36 taps for 12 rounds of Cindy, gasping, against a clock. Replaced by a tally counter —
one tap per round, reps typed once after time is called, sets **derived** on completion from
rounds × scheme so volume still lands. Consequence worth keeping: the metcon screen renders no
set row, so it never touches `SetTableView`.

**`+` menu offering "Add exercise / Add block"** — *rejected.* Forks before the user has the
information to choose; at `+` you know you want exercises, not whether they're grouped.
`ExercisePickerSheet` already multi-selects with `Add (N)`, so "Add as a block…" becomes a
secondary action appearing only at N≥2. User raised and doubted this themselves.

**Block as its own tab in the strip** — *rejected.* The sub-tabs (Sets / History / PRs / Charts)
are **per-exercise**; a block-as-tab orphans them. Bracket-around-tabs keeps tabs = exercises
always, so a block reads as a relationship between known things.

**Set table restructure — grouped, interleaved rows** — *deferred.* Phase 1 auto-advance keeps
one-exercise-per-screen and delivers most of the superset experience without touching the ~5,300
lines across `SetTableView` / `SetRowView` / both view models. **Unblocked by:** phase 1 shipping
and showing real block usage.

**Benchmark scoring across sessions** — *deferred.* `PerformanceRecord` is keyed by `exerciseId`
and structurally cannot hold "14+12 of Cindy"; needs named-block identity and a new record type.
**Unblocked by:** phase 2 shipping plus evidence metcon users exist here — this phase bets on a
different user than the fatigue/e1RM model was built for.

**Reorganising the straight-sets row** — *left alone.* Now owned by [Set types](#set-types);
folding it in would hide a row redesign inside a block feature.

**Fixing the dead migration plan and the exact-equality backup guard** — *out of scope* for
interaction, but hard prerequisites for any schema change. Recorded because they surfaced here
and look like blocks work: they are not, and they are owed regardless.

### Main contentions

**1. "I would be scared that it would ruin a lot of the pr and history stuff."**
The load-bearing objection. Drove the central finding: PRs/stats/charts read `WorkoutSet` keyed
by `exerciseId`, and a block sits *above* sets — keep `exerciseId`/`weight`/`reps` untouched and
the pipeline cannot tell the difference. Better, `excludeFromPRs` and
`excludeFromProgressionHistory` already exist and are honored by `PRService`,
`LoadPrescriptionService` and `InsightRules`, so blocks drive an existing flag rather than
needing new protection. Reframed "block or no block" into "does this block *type* count as a
strength attempt" — a per-type property, one derived flag.

**2. "So it sounds like there is a lot of things in the existing structure that needs work before
implementing new aspects?"**
Forced a recalibration that was owed. Seven landmines had been presented flat, reading as a rotten
foundation. Only **two** are gates (migration plan, backup version guard), both hours. The cost
driver is that this feature targets the largest, least-tested surface — not debt.

**3. "The current views are also a bit bloated because they were continuously built, not designed
properly."** Accepted, with evidence: `SetTableView` is 2,051 lines carrying three preview
fixtures inline, and the two view models re-implement the same reindexing independently.

**4. "I think we need to work on the interaction patterns, when we have nailed those we should
scope the technical requirements."** Stopped technical scoping mid-stream. Directly produced the
tally-counter reframe, which then changed the *technical* shape too. Vindicates the sequencing.

### Corrections on record

**The first metcon sketch was wrong**, not merely suboptimal — three checkboxes per round is
unusable under a running clock. Superseded by the tally counter.

**`FatigueLearningService` was described as needing its exclusion filter "extended".** Wrong: it
has **no eligibility filter of any kind** — neither `setType` nor either exclusion flag. Larger
gap than stated, and the one service that would silently degrade Smart Suggestions.

**`supersetGroupId` was implied possibly broken template→workout**, per the older brief. Half
wrong: it *does* propagate (`TemplateService.swift:292`), but `addSet` never carries it
(`ActiveWorkoutViewModel.swift:587`, `EditWorkoutViewModel.swift:209`), so any set added during a
live workout silently falls out of its group. Invisible today because nothing reads the field.
Two-line fix in two files, and a prerequisite for phase 1.

### Where it stands

- **Blocking the next step:** interaction is not settled (open question below), and no repo
  scoping doc exists. Write it only after that decision
- **Collision with [Set types](#set-types) — resolve before either ships.** `SetType.amrap` is a
  *set* for max reps; block-level AMRAP is max *rounds*. That entry's phase 2 puts a visible `A`
  badge on the row, which makes the clash user-facing rather than internal. Renaming the set type
  to "Max reps" is the cheaper side, but it is **their** entry's call, not this one's
- That entry also found the row has **no room for a new column** (162pt fixed before inputs),
  which strengthens the block row-reduction argument: a block must *remove* affordances, never add
- **One real data-model divergence:** `TemplateSet` holds per-set targets, which cannot express a
  metcon (one rep number per exercise + time cap + unknown rounds). A metcon `TemplateBlock` holds
  the scheme instead. Know this before the authoring screen is built
- Phase 1 (auto-advance) stays justified by supersets alone and needs no schema change

**Open question that matters most:** does the metcon screen live inside the tab strip, or take
over the whole screen? A tally counter is arguably a takeover — clock-dominant, everything else
gone — which reads better for the twenty minutes it's up and worse the moment you want to check
what's next. Wants a prototype rather than an argument, and it gates the scoping doc.

---

## Unperformed sets & exercise removal

**Date:** 2026-08-18
**Session:** "Incomplete workout logging behavior" (`d9e4a36d-e11d-45e1-8cc5-28e4d6a57dff`), branch `NewMain`
**Scoping doc:** [UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md)
**Status:** scoping only, nothing built. Phase 0 is a live data defect, not a feature

### The feature area

What happens to a set row that is created but never ticked. Copy Previous is the only
start path that prefills real `weight`/`reps` — templates write targets, browse-start
writes nils — so a copied workout begins full of rows that read as data but were never
performed, and finishing does nothing about them.

Arrived as a bug report: a copied workout finished with two exercises untouched, both
shown in history as logged. The second half of that report — "I couldn't delete the
exercise" — turned out to be discoverability, not a missing feature.

### Documents

| Doc | What it holds |
|---|---|
| [UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md) | Eligibility audit, consequences C1–C4, decisions D1–D6, phasing, test plan |
| [EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md) | §7 wants the same exercise-management sheet §5.4 here would build |

### Release position

Not decided this session. The phasing in the scoping doc is ordered by dependency, not
by release: Phase 0 must precede Phase 1 (it turns the delete into a plain row delete)
and Phase 2 (or the rebuild re-poisons exactly what the migration clears).

For whoever does decide: C2 and C3 are not cosmetic. They corrupt `ExerciseStats` and
can award a rep-max to a weight nobody lifted, on builds already in users' hands. That
is a stronger argument for riding the next release than a feature has.

### Deliberately NOT done, and why

**Any code** — scoping only. Nothing in this area was implemented.

**Copy Previous writing targets instead of actuals (D6)** — *deferred.* It fixes more
than first credited (see corrections), but `targetWeight` is rendered nowhere in the
app — the weight field's placeholder is a hardcoded `"0"`. Ship the swap alone and last
session's weight becomes invisible, which guts the feature people use Copy Previous for.
**Unblocked by:** rendering `targetWeight` as the weight placeholder, and extending
tap-to-accept beyond its current reps-only, single-value-target form.

**Filtering ghost rows out instead of deleting them at finish** — *rejected.* A row that
is invisible in history but still editable, still rebuild-eligible and still delta-eligible
is a trap that has already produced two of the four consequences. Cheaper today, permanent
liability after.

**A confirmation tap when a whole exercise is untouched** — *rejected.* Copy Previous users
skip exercises often; a dialog on every finish trains dismissal and then stops being read.
A notice above Save & Close carries the same information without that cost.

**Keeping unticked rows when the exercise was partly trained** — *rejected.* Four planned,
two performed is a two-set exercise. Keeping the other two because the exercise *was*
trained is the same defect at smaller scale.

**Reviving `PlannedWorkout` / `PlannedSet`** — *rejected.* They sit in the schema referenced
by nothing but container setup and the wipe-all path, and they look like the obvious home
for "planned but not performed". Planned-vs-performed is a feature with its own UI surface
and its own migration; it is not the fix for a filter that forgot a flag.

**The exercise-management sheet** (reorder + replace + delete in one list) — *deferred.*
It is the right end state, and it is also what
[EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md) §7 wants
for its own reason. Building it from this side means building it twice.
**Unblocked by:** deciding whether that doc's sheet is going ahead.

**Charts and Insights** — *left alone.* Both already enforce `completed && hasData`.
`ChartDataService.chartEligibleSets` is the canonical statement of the rule, comment
included — promote it, don't rewrite it.

**Export** — *out of scope.* Rows go out carrying their real `completed` flag, so an export
makes no false claim. Recorded because it reads as an affected surface and isn't.

**Superset behaviour when rows are removed at finish** — *out of scope, with a tripwire.*
`supersetGroupId` is copied but unused by any flow here. Re-check before shipping Phase 1
if supersets have landed by then.

### Main contentions

**1. "when I tried to click edit workout and delete that exercise I couldn't, so i had to
delete the sets"**
Read at face value this scopes a feature: build exercise deletion into Edit Workout. The
code says otherwise — `removeExercise(at:)` is wired, correct, and reachable by long-press
on the tab chip. What changed: the work went from building deletion to surfacing it, and
from one M item to three S/XS ones — put it in the header menu, drop the `count > 1` gate,
and stop leaving an empty chip on screen after the last set is deleted. It also surfaced
why nobody finds it: the header's `ellipsis.circle`, the control everyone tries first, is
spent on the progression-exclusion sheet.

**2. "how much of it would be sorted if copy previous wrote targets rather than real
numbers?"**
A direct challenge to the D1-first recommendation, and it forced a derivation I had not
done. What changed: D6 went from a two-bullet rejection to a scoped alternative with a
fix / doesn't-fix table and a real cost breakdown, and its verdict moved to *deferred*.
What didn't change: D1 still goes first, because the swap leaves the reported symptom —
the phantom exercise card — standing.

### Corrections on record

**D6 was understated.** The scoping doc first dismissed targets-instead-of-actuals as
breaking the flow and "not removing the need for D1", which implies it fixes little.
Measured, it fixes a lot: C1's set counts and volume, C2, C3 and C4 all go away for rows
created after it, because every broken filter guards `hasData` before anything else, so
making it false short-circuits all of them without touching that code. The accurate reason
it still isn't the answer is narrower than what was written — the phantom exercise card and
the finish sheet's "N logged" have no data check at all, so they survive the swap. D6 in
the doc has been rewritten to say this.

### Where it stands

- **Phase 0** (one `completed && hasData` predicate across all read + write paths) needs no
  decision — it is correct under every branch below, and it is the only phase that closes
  the reported symptom
- **Phase 1** (delete at finish, finish-sheet notice, fix "N logged") blocked on D2 and D4
- **Phase 2** (migration + rebuild) blocked on D5, and on Phase 0 landing first
- **Phase 3** (exercise-delete discoverability) blocked on nothing, unless §5.4's sheet is
  going ahead — then fold it in

**Open question that matters most:** D2 — delete unticked rows at finish, or filter only?
It is upstream of the rest. Filter-only reshapes Phase 1 and makes the migration close to
mandatory, because the edit and delete traps stay live for every row ever created. The
recommendation is to delete, with the notice from D4.

---

## Competitive demand analysis

**Date:** 2026-08-18
**Session:** "Hevy feature requests summary" (`202fb59f-a46b-4874-84d9-7087ae5df673`), branch `NewMain`
**Scoping doc:** [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md)
**Status:** analysis only. No code, no release commitment

### The feature area

External demand evidence. Hevy's cofounder opened a feature-request megathread on
r/Hevy; ~150 of its ~503 comments were read, ranked into demand tiers, and
cross-referenced against Repster's code and roadmap. The output is an analysis doc
that other entries cite as evidence — not a feature.

### Documents

| Doc | What it holds |
|---|---|
| [COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md) | Demand tiers, crossover, six ranked gaps, sequencing |
| [FEATURE_SCOPING_BRIEF.md](FEATURE_SCOPING_BRIEF.md) | The roadmap this was cross-referenced against |

### Release position

No release. Analysis feeds 1.6 scoping. Nothing here is a 1.5 commitment, and the
one item tempting enough to just build is blocked on a data decision (below).

### Deliberately NOT done, and why

**Social features** — *rejected.* "Skip all social stuff that is not happening."
~12 people asked for DMs, feed filtering, follower management, member search, friend
comparison. Excluded from the doc **entirely** rather than listed as a rejected
option — a rejected-options list still spends the reader's attention on something
that will never be built. The thread also contains a counter-camp asking Hevy to let
them *turn social off*; that was dropped too, since it is only interesting as a
defence of a settled decision.

**AI features** — *rejected.* ~7 asked for it, 2 pushed back hard, one saying they
would cancel if it landed in the base tier. `LoadPrescriptionService` already answers
the substantive ask — "tell me what weight to use" — without the framing the
objectors dislike. Don't re-propose this as "AI."

**Multi-gym as a first-class model** — *deferred.* Second-largest cluster (~16
people) and the pain is real: one exercise means different things at different gyms.
But it touches PR scoping, stats, and previous-value resolution at once — far larger
than the per-exercise setup settings that cover most of the same complaint.
**Unblocked by:** shipping per-exercise setup settings and finding them insufficient
in user feedback.

**Fine-grained muscle taxonomy** — *deferred*, recommendation unchanged. The thread
supplies exactly the evidence [SECONDARY_MUSCLES_SCOPING.md](SECONDARY_MUSCLES_SCOPING.md)
named as its unblock — users asking for front/side/rear delts and obliques by name.
Recorded but did **not** change that doc's call to ship the rollup first. One thread
is weak evidence for a migration that shifts every user's baselines.

**Cardio and interval tracking** — *out of scope.* EMOM, Tabata and interval timers
appear in the thread. Recorded because it looks adjacent to rest-timer work Repster
already does well; it is a different product.

**Seeding dumbbell exercises with `bilateralLoadFactor = 2.0`** — *deferred.* Would
change existing users' logged volume on update. **Unblocked by:** the backfill policy
decision below.

**Writing any code** — *out of scope for this session.* The analysis found a wiring
job small enough to be tempting. It was left alone because answering the persisted-
`effectiveWeight` question inside an implementation pass is how a silent data change
ships.

**Fetching the thread programmatically** — *rejected.* Reddit is blocked on WebFetch,
blocked by policy in the in-app browser, and 403s to curl. Routing around that with a
reader proxy or mirror was declined; the user pasted the content instead. Recorded so
the next session doesn't rediscover the block.

### Main contentions

**1. "can you make the tiers again, and then a section on repster crossover or
suggestions on how what it could look like in repster"**
The first pass summarised the thread and appended a short relevance note built from
memory and the scoping docs. Being asked for a real crossover section forced reading
the source instead — which is the only reason `bilateralLoadFactor` was found. The
first version would have shipped without its single most valuable finding. Reasoning
from docs *about* the code rather than the code is the same failure as contention 4
in [Muscle coverage](#muscle-coverage).

**2. "yeah make a doc, but skip all social stuff that is not happening"**
Changed the output from terminal scrollback to a linkable doc, and changed how
exclusions are handled: omitted with one scope line at the top, not enumerated. Stops
a settled decision being re-litigated by everyone who reads the analysis.

### Corrections on record

The first pass called the dumbbell/unilateral cluster "a small, self-contained
feature — worth considering against your current shortlist." **Wrong on two counts.**
It is not a feature to build: `Exercise.bilateralLoadFactor` is already on the model,
round-tripped through export, templates and charts, and already read and written by
`CreateEditExerciseViewModel`. Missing are a control in the editor sheet and one
branch in `computeEffectiveWeight` ([SetService.swift:520](Repster/Core/Services/SetService.swift:520)),
which today applies `bodyweightFactor` only. And the risk is not engineering —
`effectiveWeight` is persisted per set, so the cost is a data-migration question.

Same pass implicitly framed several Tier 1–2 items as gaps Repster could fill.
Reading the code found them **already shipped**: separate warm-up rest timers,
warm-up exclusion from volume and PRs, selectable e1RM formula, per-side rep/RIR
logging, and a continuous `Date` chart axis — the thread's most-cited "easy fix."
Under-crediting shipped work is the mirror of the same error.

### Where it stands

- Analysis complete. Ranked shortlist in the doc: `bilateralLoadFactor` wiring (S),
  `Exercise.notes` (S), custom-exercise-creation analytics (XS), then secondary
  muscles, machine setup, Programs UI, supersets
- Cheapest genuinely useful item is the analytics event — one `capture` call that
  turns "our library has 69 exercises" into a ranked list of what users actually miss

**Blocking the next step:** the backfill policy for persisted `effectiveWeight`. Both
the load-entry factor and the machine starting-weight offset change how effective load
is computed for exercises that already have history. `effectiveWeight` is stored per
set, not computed on read, so neither is retroactive without an explicit backfill, and
either produces a visible step in that exercise's e1RM and volume charts. One answer
must cover both, decided before either is built — shipping them with different
behaviours would be worse than either choice alone.

**Open question that matters most:** is per-exercise machine setup useful without a
gym concept? It is the strongest differentiator in the analysis and the one nobody
serves — but the users describing the pain are describing it *across* gyms. If
per-exercise settings only work for single-gym users, the differentiator is a
half-measure and the honest version is the deferred multi-gym project.

---

## Smart Suggestions undershoot

**Date:** 2026-08-18
**Session:** "Smart suggestion logic for new exercises" (`b18d618e-7b1c-47fb-8bbf-5a29da174b82`), branch `NewMain`
**Scoping doc:** [SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md)
**Status:** design only, nothing built. Guardrail specced, two follow-ups unspecced

### The feature area

The magic-wand weight prescription — `SuggestionEngine` in
`LoadPrescriptionServiceProtocol.swift`. Shipped and live. On a first session of
"Leg Extension - 1 leg" it suggested **32.5 kg** for set 3 after 20×8 and 35×8,
both logged at the top-of-scale RIR chip `5+`. The user then did **45×10 @ RIR 0**
— a 60 kg e1RM, making ~45 kg correct. The engine is not miscalculating;
hand-reproducing it lands on 32.5 exactly. The defect is in what it is fed and
what it is willing to believe.

### Documents

| Doc | What it holds |
|---|---|
| [SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md) | The floor guardrail: 9 decisions, 13 test cases, limits |

### Release position

Unassigned. Nothing built, no release claim made.

### Deliberately NOT done, and why

**Redefining stored `e1RM` to include RIR** — *rejected in that form.* Eight
consumers: charts, both insight rules, stats trend, export, best-e1RM query,
in-workout E1RM card, prescription baseline. The migration can't be done honestly
— sets logged without RIR can't be backfilled. And e1RM-as-demonstrated is
arguably *right* for a progress chart: a PR line shouldn't jump because someone
felt fresh and tapped a bigger RIR. **Superseded by** a separate `capacityE1RM`
field read only by the prescription path — additive, no migration. **Unblocked
by** the guardrail.

**Opening the RIR < 3 capability gate** — *deferred, and must never ship alone.*
`SessionCapabilityPolicy.observed` *replaces* capability with the last qualifying
set rather than blending. Simulated: a top set of 35×8 @ RIR 2 then a light
back-off 20×8 @ RIR 2 drops capability 44.3 → 27.1 and the next suggestion to
20 kg. The gate is most of what keeps that rare — open it and every light set at
RIR 4–5 starts doing it. **Unblocked by** switching to `.blended`, which already
exists at 0.7/0.3 and is entirely unused. That bug is live today regardless.

**Extending the RIR chip past "5+"** — *rejected.* Nobody can tell 10 reps in
reserve from 14, so a longer scale collects numbers that must be discounted
anyway. Weight a censored value; don't demand precision the user can't supply.

**Capping how far the floor may raise the answer** — *rejected.* A large gap
between floor and model is the signal the model is wrong, and the floor reports
something that physically happened.

**Relaxing the floor as projected fatigue grows** — *deferred.* By set 8 the model
may legitimately project 25% fatigue and want to go below a floor set early. v1
clamps anyway: relaxing adds a tuning constant to a change whose whole appeal is
having none. **Unblocked by** an actual late-set complaint.

**First-pending-set fatigue decay** — *deferred, demoted.* Opened as the
recommended first move and was wrong to be: it moves ~2.4% of e1RM and flipped the
observed case only because 34.35 cleared the 33.75 rounding boundary on a 2.5 kg
grid — on a 1 kg increment it changes nothing. Still a real inconsistency, since
both neighbouring transitions decay and this one doesn't. **Unblocked by** the
guardrail.

**Elapsed rather than configured rest for that decay** — *rejected.* Makes the
suggestion drift upward while the user sits there, and the cache key has no time
term, so a live value goes stale until something else invalidates it.

**Progression bias for single-rep-target users** — *out of scope.*
`.firstSetProgressionAboveRecentPeak` exists only in the rep-range branch, so on
defaults the policy is always `.closestMatch` and "Nudging up from your last
workout's peak" is unreachable. A separate missing mechanism, not this one.

**Bodyweight-factor suggestion display** — *out of scope.* `prescribedWeight` is
in `effectiveWeight` space but is applied as the literal weight to enter. The
guardrail is unaffected — both sides of its comparison sit in the same space.

### Main contentions

**1. "3 sounds like it would get nowhere near the real potential."**
Decisive. The first pass ranked the fatigue-decay fix first because it was
cheapest and cleanly correct. The actual session outcome made every model fix look
marginal — 32.5 → 35 for the decay fix, → 37.5 for the full rewrite, against a
correct answer of 45. Forced a re-rank producing the guardrail / lower-bound /
probe trio, none of which were among the original four options.

**2. "I dont think I understand what that means exactly but it sounds more right."**
The trio was written in jargon — *monotonicity guardrail*, *logical invariant*,
*censored point estimate*. Rewritten in plain language before any doc was
produced; the concepts survived translation and the vocabulary didn't.

### Corrections on record

**The censored RIR scale was ranked last of four and called "the weakest as a
fix". Wrong.** Back-solving the 35×8 set against a 60 kg e1RM gives **~13.4 reps
in reserve**, not the 5 recorded. The truncation is the binding constraint: after
every model fix, the residual gap (37.5 → 45) is entirely attributable to it.

**Build order reversed.** Was: decay fix → RIR-aware e1RM → gate. Now:
guardrail → lower-bound → probe.

### Where it stands

- **Guardrail** — specced, not built. Pure function in the engine, no repository
  access, no migration. Needs a decision on whether it rides 1.5
- **Lower-bound reading of `5+`** — unspecced. Where most of the missing weight is
- **Probe mode** — unspecced. The real fix for a first session
- **`.observed` replacement bug** — live today, independent of all the above

Nothing technical blocks the guardrail, but it must land *before* the lower-bound
change or a regression can't be attributed to either.

**Open question that matters most:** what inflation does a top-of-scale `5+`
deserve? Treating it as 8 reaches 40 kg, as 10 reaches 42.5, the honest 13.4
reaches 45. Those constants are illustrations with nothing behind them, and the
guardrail cannot settle it, reaching only one increment above a demonstrated
set. Needs logged data from users who tap `5+`, not reasoning.

---

## Coaching tiles

**Date:** 2026-08-11 (recorded 2026-08-18)
**Session:** "Training insights and Monthly stats positioning" (`70ba4f3c-350f-410f-ba64-5e94cc3cb2bd`), branch `NewMain`
**Scoping doc:** [COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md)
**Status:** exploration only, nothing built or agreed. Parked mid-session at the user's request

### The feature area

A proposed *second* category of Insights tiles — ones that name the next training
step, as distinct from Smart Suggestions, which prescribes a weight inside a
workout. Nothing exists today. Ten tiles were mocked (2 model transparency +
8 coaching), every one on data already stored; no rule, view or engine was written.
It surfaced as a side-branch of the insights chart rework and was split off before
it could absorb it.

### Documents

| Doc | What it holds |
|---|---|
| [COACHING_TILES_EXPLORATION.md](COACHING_TILES_EXPLORATION.md) | Framing question, the two gates, per-tile data backing, the four decisions |
| `html prototype/prototype-coaching-tiles.html` | The 10 tiles, incl. the Today tile in both copy registers |
| [TRAINING_INSIGHTS_V2_DESIGN.md](TRAINING_INSIGHTS_V2_DESIGN.md) | §2 locked names, §5.1 coverage caveat, §6 curation contract, §12 out of scope |

### Release position

[RELEASE_1_5_PLAN.md](RELEASE_1_5_PLAN.md) Part 7 — scoped, not proposed. Parking it
protected the insights chart rework, which shipped four reworked chart kinds the same
morning instead of stalling behind an unanswered product question.

### Deliberately NOT done, and why

**Building any tile** — *deferred.* **Unblocked by** the stance decision below. Until
that lands, four of the eight coaching tiles have no copy that can be written honestly.

**Keeping coaching inside the insights prototype** — *superseded.* It was mocked there
first. Splitting it cost that file 10 of its 29 cards plus the coaching CSS, and was
worth it: the two now move at different speeds.

**Calling it "Suggestions"** — *rejected.* §2 locks that name to Smart Suggestions,
which owns a Settings screen and the workout-screen wand. A second feature that
prescribes would read as the same thing said twice.

**Deep links from a tile ("Load this session", "Start a legs session")** — *out of
scope.* §12 defers actions from findings into editors. Recorded because a coach tile
that can't act is half a feature — this is the deferral to revisit *first* if the
category proceeds, not a detail.

**Register B of the Today tile** ("Train legs today — 4 sets of squats to start") —
*deferred.* Register A states the facts and offers, which stays inside what
`deloadReadiness`'s never-say-take-a-deload-week rule is protecting. B needs stance,
name and deep links all three. Both were mocked side by side rather than one being
picked, so the register choice stays concrete.

**Model check and Fatigue cost as Tier 1 cards** — *rejected.* Both read
`FatigueObservation`, which only exists where Smart Suggestions produced a prediction.
Blank for anyone not using the wand — the same coverage caveat §5.1 already records
for `deloadReadiness`.

**Ranking exercises by `appliedFatigueRate` as it stands** — *rejected.*
`appliedFatigueRateInfo(for:profile:)` returns a *default* rate when nothing has been
learned. Rank those and the tile shows the model's priors dressed up as a fact about
the user's training. Any build gates on `source` and `hasAuditHistory`.

**"Stalled" firing on a flat weight run alone** — *rejected.* An intentional maintenance
block is indistinguishable from a plateau unless reps are rising underneath. Reps-rising
is a firing condition, not a nicety.

**"On pace" as a plain extrapolation line** — *left alone.* Nearly free to build and the
easiest way to ship the most disappointing card in the app: a dashed line reads as a
promise, and linear extrapolation of strength is wrong over any real horizon. Short
window and a visible hedge, or it shouldn't exist.

**Balance (push : pull)** — *deferred.* **Unblocked by** a movement-pattern taxonomy,
which does not exist in the model today — on top of stance.

**Writing new rules as the first move** — *rejected as the framing.* Most of the category
is a re-frame of `deloadReadiness`, `muscleBalance` and `restSweetSpot` plus two or three
new rules. Grouping and copy-register decision first, engine decision second.

### Main contentions

**1. "is that all the coaching? I guess a lot ofthe other graphs are coaching related,
but I am thikning that a coaching part could have more."**
Decisive. The first pass was two tiles — the same "what to train" idea in two voices —
presented as a category. This forced eight, across the domains a coach actually covers,
and produced the definition the doc now leads with: a coaching tile is one that **names
the next step**. It also exposed the stance gate, which two tiles never would have reached.

**2. "cna we store all the coaching stuff seperately? and then just focus on the insihgts
for now."**
Changed the deliverable from a section inside the insights mockup to a standalone
prototype *plus* a markdown doc. The reasoning was the part a mockup can't hold — "this
collides with §2 but not with the organising idea" has nowhere to live in HTML.

### Corrections on record

**"A coaching category departs from the locked design." Wrong.** The assumption going in
was that it contradicted TRAINING_INSIGHTS_V2_DESIGN.md. §"The organising idea" already
assigns findings the *prescribing* role; only the status layer is restricted to
describing. The real collisions are narrower and all fixable — name, deep links,
contract. Easy to re-derive the wrong conclusion in a month, which is why it leads the doc.

**Two tiles were presented as a category.** They were one idea in two registers.
Corrected under pushback — see contention 1.

**The mocked table was reported as blowing out the grid track.** It wasn't; the browser
pane had been resized and one column was correct at that width.

### Where it stands

- Prototype and doc are committed on `NewMain` (`9106306`). Ten tiles, nothing in the
  app, no release claim
- **Session order** is the build-first candidate if it proceeds: `orderInWorkout` plus
  within-session e1RM decay computed straight from `WorkoutSet` sidesteps the Smart
  Suggestions coverage gate entirely, so it works for every user and needs no new model

Nothing technical blocks this — the block is the stance decision. Name and contract both
hang off it, since whether coaching lives in the gated feed (§6 allows findings to say
nothing) or as an always-on surface is a different promise, not a different implementation.

**Open question that matters most:** does Repster assert training opinions — "spread your
chest volume", "vary your rep ranges", "keep push and pull even" — or only state the
user's own patterns back to them? Insights makes no claim of that kind today. No amount
of data settles it; it is a product-voice decision.
