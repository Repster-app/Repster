# Supersets — implementation plan

**Date:** 2026-08-31 · **Branch:** `NewMain` · **Status:** PR1–PR9 + PR11 built and green (686 tests). Only PR10 remains, and it is still an open question. Both PF2
decisions settled 2026-08-31.

| Step | State |
|---|---|
| PF1 · no data, no safety net | **accepted** — every test below is fixture-built |
| PF2 · the two decisions | **settled** — all-or-nothing grouping; replacement inherits |
| PR1 · create carries the group | **done** — `SupersetGroupingTests`, 8 green, mutation-checked |
| PR2 · derivation | **done** — folded into PR1, see below |
| PR3 · the marking | **done** — runs render as segmented containers, 10 grouping tests green |
| PR4 · rest branch + the zero | **done** — 4 behaviour tests, mutation-checked |
| PR5 · the prompt in the slot | **done** — 6 lifecycle tests + 2 slot-arbitration tests |
| G7 · `supersetPromptTaps` | **done** — landed with PR5, as the gap said it must |
| PR6 · extract the group builders | **done** — and it fixed a live Calendar/Home divergence, below |
| PR7 · history chip | **done** — batched partner lookup + 4 tests |
| PR8 · joined workout-detail card | **done** — one change covers Calendar and Home |
| PR9 · authoring | **done** — 6 tests; menu, picker, create, dissolve, reorder-on-create |
| G7 · `supersetCreates` | **done** — landed with PR9 |
| PR10 · Live Activity | **not built** — still an open question, not a defect |
| PR11 · template palette | **done** — menu drives off `supersetLetters`, colour cycles |

**Companion to:** [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) (the why, the rules, the marking spec) ·
[FEATURE_SCOPING_BRIEF.md](FEATURE_SCOPING_BRIEF.md) §7 (superseded) ·
**Design:** https://claude.ai/code/artifact/a2262a93-3765-4e2c-9e73-8b2726353389

This is the build order. **Section 3 is the part to read before starting** — it lists what the
scoping doc did not consider, including three items that change the plan and one that changes a
number the fatigue model consumes.

| PR | What | Visible? | Gated by |
|---|---|---|---|
| PF1–PF2 | Pre-flight — **PF2 settled** | — | — |
| PR1 | Thread `supersetGroupId` through set creation | no | — |
| PR2 | Derive the group once, for both screens | no | PR1 |
| PR3 | The marking in the tab strip | yes | PR2 |
| PR4 | Rest behaviour + the honest zero | **yes** | PR2 |
| PR5 | The prompt in the accessory slot | yes | PR4 |
| PR6 | Extract the two duplicated group builders | no | — |
| PR7 | History chip | yes | PR1, PR6 |
| PR8 | Joined card in workout detail | yes | PR1, PR6 |
| PR9 | Authoring — create and dissolve | yes | PR2 |
| PR10 | Live Activity next-up line | yes | PR5 |
| PR11 | Template picker — cycle the palette | yes | — |

PR6–PR8 depend only on PR1 and can run in parallel with PR2–PR5.

---

## 1. Pre-flight

### PF1 · Accept that there is no data and no safety net

`supersetGroupId` appears in **zero sets** of the 11,785-set real history
([STEP5_SCOPE_AND_TEST_STRATEGY.md](STEP5_SCOPE_AND_TEST_STRATEGY.md) §5.2). Three consequences,
all of which shape the rest of this document:

- **No migration, no backfill, no rollout risk.** Nothing in production carries the field, so no
  existing user's numbers move on the day this ships. This is why there is no kill switch (§6).
- **The golden master and the differential tests protect nothing here.** They only cover behaviour
  the real history exercises. Every test in this plan is written from scratch against constructed
  fixtures — do not assume an existing suite will catch a regression.
- **You cannot dogfood on old data.** The first real superset will be one you create. Budget a
  device pass (§4) rather than expecting history to surface problems.

### PF2 · The two blocking questions · **settled 2026-08-31**

1. **Grouping is all-or-nothing per exercise.** Creating stamps every set of both exercises;
   dissolving clears every set of the exercise, completed rows included. Rationale and the rejected
   alternative are in [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §6.
2. **A replaced exercise inherits its group.** You swapped the movement, not the structure.

**Decision 1 simplifies three later PRs**, so it is worth stating what it removes rather than only
what it decides. Because writes are all-or-nothing, **an exercise's sets always agree about their
group.** There is no half-tagged state, so PR2 needs no read rule that prefers one kind of row over
another, PR7's chip has one unambiguous meaning, and the only surviving disagreement is the
pre-PR1 defect this plan fixes in PR1. The accepted cost: a set logged *before* a group is created
reads as supersetted afterwards.

Everything else in §7 (Live Activity, the template editor's A/B/C picker) can be decided later
without stalling a PR.

---

## 2. Build order

### PR1 · Thread `supersetGroupId` through set creation · no behaviour change

The gating defect from [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §2.1. Add the parameter to:

- [SetRepository.create](Repster/Core/Repositories/SetRepository.swift:30)
- [SetService.create](Repster/Core/Services/SetService.swift:43)
- Both declarations in [SetServiceProtocol.swift](Repster/Core/Services/Protocols/SetServiceProtocol.swift:88) (`:88` and `:261`)

Six call sites, and they do **not** all pass the same thing:

| Call site | Passes |
|---|---|
| `ActiveWorkoutViewModel.addSet` — Add Set | the exercise's current group |
| `ActiveWorkoutViewModel.addWarmupSet` — Add Warmup | the exercise's current group — see below |
| `EditWorkoutViewModel.addSet` / `.addWarmupSet` | the exercise's current group |
| `ContentView.startWorkoutWithExercises` | **nil** — brand-new exercises off the picker, nothing to inherit |
| `ContentView.performCopy` — Copy Previous | the source set's group, **remapped** to a fresh id per group |
| `ActiveWorkoutViewModel.replaceExercise` | the **outgoing** exercise's group (PF2.2) |

**Warm-ups carry the id.** It is tempting to leave them ungrouped since they rest normally, but then
"every set of this exercise carries the group" stops being true and every later derivation needs a
`setType` exception. Carry the id on all sets; branch on `setType` in PR4 where the behaviour
actually differs.

**Copy Previous must preserve grouping** — and remap. Copying a workout that contained a superset
and getting back an ungrouped one is silent data loss. The ids are remapped to fresh UUIDs per
group rather than reused, so each workout owns its own, matching what `TemplateService`'s import
path already does.

**Three corrections found while building this:**

1. `ContentView.swift:595` is `startWorkoutWithExercises` — the exercise-picker path, **not** Copy
   Previous as the first draft of this table said. It passes nil. Only `performCopy` copies.
2. `SetRepositoryProtocol.create` needs the parameter too, not just the concrete `SetRepository` —
   `SetService` holds the protocol type, so the concrete default is invisible to it.
3. `replaceExercise` deletes the outgoing rows *before* adding the replacement's first set, so by
   then there is nothing to derive from. It captures the group before the delete loop and passes it
   to a private `addSet(for:supersetGroupId:)`. The public `addSet(for:)` cannot simply gain a
   defaulted parameter — it is a `SetTableDataSource` requirement, and Swift does not match a
   witness with extra defaulted arguments.

*Acceptance:* **done** — `RepsterTests/SupersetGroupingTests.swift`, plus a mutation check:
dropping `supersetGroupId:` from `SetRepository.create`'s `WorkoutSet(...)` fails
`testCreatedSetCarriesTheGroupItWasGiven` (verified).

**Registering a new test file is manual.** Only the `WorkoutLiveActivity` target is a
`PBXFileSystemSynchronizedRootGroup`; the app and test targets use explicit file references. A new
test file needs four entries in `project.pbxproj` (build file, file reference, group child, sources
phase) or it silently compiles nothing and `-only-testing:` reports *Executed 0 tests*.

### PR2 · Derive the group once, for both screens · no behaviour change · **built with PR1**

Not separable in practice: PR1's call sites need "the exercise's current group" to pass anything
sensible, and a PR that threads a parameter and then passes nil everywhere cannot be reviewed for
correctness. Built together.

**Shipped shape differs from the sketch below.** The rules live in a `SupersetGrouping` enum of
pure static functions over `exercises` and `setsByExercise`; the protocol extension is thin
delegation. Reason: conforming a test double to the whole of `SetTableDataSource` — 20-odd members
— to assert "is this exercise in a group" is ceremony around nothing, and the rules are the part
worth testing directly. Both conformers still get identical behaviour through the extension.

`SupersetGrouping.runs(exercises:setsByExercise:)` was added here rather than in PR3, for the same
reason: it is the pure part of the strip's rendering and it is where **G4** and **G5** are actually
enforced. PR3 consumes it and draws.

Put the derivation in the **protocol extension** on
[SetTableDataSource](Repster/Features/Workout/Protocols/SetTableDataSource.swift:105), which already
has default-implementation extensions at `:223` and `:229`:

```swift
func supersetGroupId(for exerciseId: UUID) -> UUID?      // any non-nil set in the exercise wins
func supersetMembers(of groupId: UUID) -> [ChartExerciseData]   // filter `exercises`, existing order
func nextInSuperset(after exerciseId: UUID) -> ChartExerciseData?
func isLastInSuperset(_ exerciseId: UUID) -> Bool
```

All four read only `exercises` and `setsByExercise`, both already on the protocol. **No new stored
state, and both conformers — `ActiveWorkoutViewModel` and `EditWorkoutViewModel` — get it for
free.** See **G2** for why that matters and where it must stop.

"Any non-nil set wins" stays the rule, but after PF2.1 it is **defensive rather than load-bearing**:
writes are all-or-nothing, so an exercise's sets always agree. Keep it anyway — it costs nothing and
it is the correct reading of the one disagreement that can still exist, which is data written before
PR1 fixed the create path. Do not use `sets.first?.supersetGroupId`, which picks arbitrarily.

A group with **fewer than two members** is not a group — see **G5**. `supersetMembers` returns the
raw list; the callers in PR3/PR4 must treat `count < 2` as ungrouped.

*Acceptance:* unit tests against a stub conformer, covering: no group; a clean pair; a one-member
group; a **non-contiguous** group (**G4**); and a half-tagged exercise (one set grouped, three not)
as a **defensive** case — unreachable after PR1, asserted so a future write path cannot reintroduce
it silently.

### PR3 · The marking · visible, read-only

[ExerciseTabStripView](Repster/Features/Workout/Views/ExerciseTabStripView.swift) renders
`dataSource.exercises` as a flat `HStack`. Change it to render *runs*: walk the array, and emit
either a loose tab or a segmented container for a contiguous run of the same group.

Spec is in [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §3 — filled container, link glyph joiner,
inner tabs transparent. Keep the existing context menu wiring on each inner tab.

**Two cases the run-builder must survive** (both reachable today, see **G4** and **G5**):

- a group whose members are **not adjacent** — render them as loose tabs, marked or not, but never
  let a container span an exercise that is not in the group;
- a group with **one member** — render as a loose tab.

*Acceptance:* **done** — `SupersetGrouping.runs` is tested directly across seven shapes, including
the two that would break rendering (non-contiguous, group-of-one) and the two that protect everyone
who has no supersets at all (all-ungrouped, exercise with no rows). Still wants a visual check on
**both** the active-workout and historic-edit screens.

**One deviation from §3's spec, taken deliberately.** The spec had inner tabs at `height 32,
padding 0 12` so the container matched a loose tab's 36pt and the strip's height did not move. Built
instead with inner tabs **identical** to loose tabs (36pt, padding 14), which makes the container
40pt and the strip 4pt taller. Reason: 32pt is a smaller tap target than the 36pt the strip already
has, and the design system's stated floor is 44pt — the strip is already under it and this would
have gone further. The user's constraint was horizontal, and horizontal is unchanged at +10px,
because the inner tabs keeping `padding 14` is what preserves that arithmetic.

**Colour assignment lives in the view, not in `SupersetGrouping`.** Groups on screen are coloured by
order of appearance from `[accent, chart5, chart7, chart8]`, cycling. The strip has no letters, so
the palette only has to separate two groups that are *both visible*.

### PR4 · Rest behaviour and the honest zero · **behaviour change**

One branch at step 6 of `completeSet`
([ActiveWorkoutViewModel.swift:510](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:510)):

```
if set.setType != .warmup, exercise is in a group of ≥2, and it is not the last member:
    do not start a timer
    write restDurationSeconds = 0 on the completed set     ← not optional, see G6
    updateLiveActivityState()
else:
    unchanged
```

The `= 0` write is the fix for [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §2.2. Leaving it unset
makes the fatigue model read the exercise's *configured* rest and decay fatigue as though the lifter
rested — over-estimating readiness on exactly the sets where they are most cooked. **Read G6 before
implementing this: zero is a floor, not the truth, and the plan should say so in the code comment.**

*Acceptance:* four tests, and one mutation check —

1. mid-group working set → `restTimer == .idle` **and** `restDurationSeconds == 0`;
2. last-member working set → timer starts with that exercise's rest time;
3. warm-up inside a group → timer starts with the warm-up rest time;
4. ungrouped set → unchanged;
5. **mutation check:** delete the `= 0` write and test 1 must fail. If it still passes, the test is
   asserting the timer and not the field.

### PR5 · The prompt in the accessory slot · visible

Add `supersetPrompt: SupersetPrompt?` to `ActiveWorkoutViewModel` — **a sibling property, not a
fifth case on `RestTimerState`** ([:45](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:45)).
It is not a timer, it has no duration, and folding it in would make every `switch` in the timer code
answer a question about supersets.

Set it in PR4's branch, clear it on: exercise change (`selectedExerciseId`), tapping it, workout
finish, and set un-completion. Render one branch in `bottomAccessoryArea`
([ActiveWorkoutView.swift:319](Repster/Features/Workout/Views/ActiveWorkoutView.swift:319)) — same
43pt row, same 2px rule.

Extend `ActiveWorkoutBottomAccessoryLayout` ([:12](Repster/Features/Workout/Views/ActiveWorkoutView.swift:12))
with the keypad rule, mirroring `.finished`: suppress the prompt while the set keypad is open.
Add `supersetPrompt` to `bottomAccessoryAnimationKey` or the slot will not animate.

*Acceptance:* prompt appears, names the right partner, clears on each of the four routes above, and
is suppressed with the keypad up.

### PR6 · Extract the two duplicated group builders · no behaviour change

**Do this before PR7 and PR8.** See **G1**: `ExerciseGroup` is assembled independently in
[CalendarViewModel.swift:199](Repster/Features/Calendar/ViewModels/CalendarViewModel.swift:199) and
[WorkoutDetailFromHomeView.swift:220](Repster/Features/Home/Views/WorkoutDetailFromHomeView.swift:220),
and `WorkoutHistoryGroup` in
[ExerciseDetailViewModel.swift:76](Repster/Features/Exercise/ViewModels/ExerciseDetailViewModel.swift:76)
and [ActiveWorkoutViewModel.swift:1755](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1755).

Four build sites for two concepts. Adding a superset field to each by hand is the exact drift that
produced the RIR bug ([STAGE2_WRITE_PATH_DESIGN.md](STAGE2_WRITE_PATH_DESIGN.md) §"two `init(from:)`s
to keep in sync"). Extract one builder per concept first, with the existing behaviour unchanged.

*Acceptance:* **done, but not byte-identical — and deliberately so.** The two copies had already
drifted, which is the whole reason G1 flagged them:

- `CalendarViewModel` ordered exercises by `sets.first?.orderInWorkout`
- `WorkoutDetailFromHomeView` ordered by `sets.map(\.orderInWorkout).min()`

`sets` is sorted by `orderInExercise`, and a warm-up added mid-workout carries
`orderInExercise == 1` with the **highest** `orderInWorkout` in the session. So for any workout
with a late-added warm-up, Calendar and Home listed the same exercises in a different order.

Kept `min()`: it is what `ActiveWorkoutViewModel` uses to order the tab strip, so the live screen
and both history screens now agree. Mutation-checked — restoring Calendar's old rule fails
`testExerciseGroupsOrderByEarliestSetNotByFirstListedSet`.

`ExerciseGroupRun` landed here too, alongside the builder: the workout-detail equivalent of
`SupersetGrouping.Run`, enforcing the same G4/G5 rules one level up. PR8 draws it.

`WorkoutHistoryGroup`'s two build sites are **not** extracted yet — PR7 does that.

### PR7 · History chip · visible

`WorkoutHistoryGroup` ([ExerciseModels.swift:17](Repster/Features/Exercise/Models/ExerciseModels.swift:17))
gains `supersetPartnerNames: [String]`, populated in PR6's single builder.

`ChartSetData` **already mirrors `supersetGroupId`**
([ChartSetData.swift:47](Repster/Core/Services/ChartSetData.swift:47)), so no snapshot work is
needed — the history surfaces can already see the field. This makes PR7 and PR8 cheaper than the
scoping doc assumed.

New `SupersetChip` beside `ProgressionExclusionChip`
([ProgressionExclusionViews.swift:20](Repster/Features/Workout/Views/Components/ProgressionExclusionViews.swift:20)),
matching its geometry exactly: `HStack(spacing: 3)`, 8pt glyph, 9pt bold, `padding 3/5`,
`cornerRadius 4`, soft background, 20% border. Group colour, not `.stale`. Render it in the session
header next to the exclusion chip, which already sits there.

Set rows are **not** touched — same call the exclusion work made
([ExerciseHistoryView.swift:42](Repster/Features/Exercise/Views/ExerciseHistoryView.swift:42)).

*Acceptance:* **done.** Both consumers of `WorkoutHistoryGroup` populate the field — the
exercise-detail screen and the in-workout History sub-tab — and the chip sits beside the exclusion
chip in the same header slot.

**Partner names needed a new query, which the sketch above missed.** Both build sites fetch only
*this* exercise's sets, so neither can see who it was paired with. Added
`SetService.supersetPartnerNames(workoutIds:exerciseId:)`, shaped deliberately like
`excludedWorkoutIdsForProgressionHistory`: one batched lookup for a whole history tab, because that
screen renders dozens of sessions and a per-session fetch would be dozens of round trips for a chip.
It landed on `SetService` rather than `WorkoutService` for the mundane reason that `WorkoutService`
holds no exercise repository and so cannot resolve names.

**Header overflow is handled by truncation, not layout.** Date + superset chip + exclusion chip on a
390pt screen is right at the edge. The chip is `lineLimit(1)` inside an `HStack` with
`Spacer(minLength: 0)`, so a long partner name truncates rather than clipping the row, and the
accessibility label carries the full text. Three-plus partners collapse to a count.

### PR8 · Joined card in workout detail · visible

`WorkoutDetail` gains grouping runs from PR6's builder. Render a contiguous run as one container —
spec in [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §5.2. Same run-builder shape as PR3, one level
up; consider sharing it.

*Acceptance:* **done** — and it was one change, not two: `WorkoutDetailFromHomeView` renders
`CalendarWorkoutDetailView`, so Home inherits it. `CalendarExerciseCard` gained an
`insideSupersetCard` flag that drops only its own background and radius; padding is untouched so
nested rows align with un-nested cards above and below. Non-contiguous groups and groups of one
fall back to ordinary cards through `ExerciseGroupRun` (**G4**, **G5**), which is unit-tested.

### PR9 · Authoring — create and dissolve · visible

Two menu items on the existing tab-strip context menu
([ExerciseTabStripView.swift:70](Repster/Features/Workout/Views/ExerciseTabStripView.swift:70)):
*Superset with…* when ungrouped, *Remove from superset* when grouped.

Per **PF2.1**, both writes are all-or-nothing and symmetric:

- **Create** — partner sheet, then stamp one new `UUID` on **every** set of both exercises,
  completed rows included.
- **Dissolve** — clear `supersetGroupId` on **every** set of the exercise, completed rows included.
  Dissolving one half of a pair leaves the other a group of one, which **G5** already requires every
  reader to treat as ungrouped — so a pair dissolves cleanly from either side with no second write.

Both go through the repository on the owning actor
([SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md](SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md)) — these touch
completed rows, which the live-model crash work is specifically about.

**Not gated, contrary to earlier drafts of this plan.** Picking a non-adjacent partner calls
`reorderExercises` ([:960](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:960)),
and the first draft said the two live reorder defects had to land first. **They already did** —
[EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md) records both fixed
2026-08-29, plus two more found in the same pass, with the DEBUG ordering assertion in place. The
claim came from a stale note, not from the tree. Verified 2026-08-31.

*Acceptance:* **done.** Six tests: stamping every set of both exercises (warm-ups included),
leaving unrelated exercises alone, reordering a non-adjacent partner into place, dissolving over
already-completed rows, dissolving one half leaving the other ungrouped in **one** write, and
refusing to pair an exercise with itself.

**Two implementation notes.** Authoring is gated behind `supportsSupersetAuthoring` on
`SetTableDataSource`, defaulting to `false` — the historic-edit screen shows the *marking* but gets
no menu items, per **G2**. And the sheet holds a boxed anchor id rather than an index: a reorder or
a replace behind an open sheet would silently repoint an index at a different exercise.

`moveAdjacent` uses `toOffset: anchorIndex + 1` in both directions — moving forward the partner is
removed first so the destination shifts down one and it lands right after the anchor; moving
backward it lands there directly. Same convention as the strip's existing Move Left / Move Right.

### PR10 · Live Activity next-up line · visible

A sixth `RestDisplay` case carrying the partner's name
([WorkoutActivityAttributes.swift:84](Repster/Features/Workout/Models/WorkoutActivityAttributes.swift:84)),
plus a `String?` on `ContentState`. Leave `exerciseName` alone — navigation is manual in this design,
so overriding it would make the widget contradict the screen in the user's hand.

Mid-group today the widget falls through to `.ready` and reads *"Bench Press · Ready for next set"*:
a valid state pointing at the exercise you just finished. Not broken, just unhelpful — which is why
this is a follow-up and not part of the release.

*Acceptance:* both view chains read `restDisplay()`, so one unit test over `ContentState` covers the
Lock Screen and the Dynamic Island together — that is what the helper exists for.

### PR11 · Template picker — cycle the palette · visible · **independent**

Not gated by anything here and touches nothing this feature builds; listed because supersets are
what make it worth fixing. Three disagreeing limits (picker 3, colours 4, letters 5) collapse into
one — see [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §6:

- drive the menu from `supersetLetters` rather than the literal `["A", "B", "C"]`;
- `supersetColor` indexes `[accent, chart5, chart7, chart8]` by letter position, modulo four;
- delete the `textTertiary` fallback — it is now unreachable, which is the point.

*Acceptance:* five groups assignable, each labelled and coloured, E reusing A's blue. An imported
template with more groups than letters still renders without a nil label.

---

## 3. What the scoping doc did not consider

### G1 · Four build sites for two concepts · **changes the plan**

`ExerciseGroup` and `WorkoutHistoryGroup` are each assembled in two places (PR6). The scoping doc
treated history as "add a field", which is true — but adding it four times by hand is how the two
`ChartSetData` initialisers drifted and produced the RIR bug. **PR6 is inserted ahead of the history
work as a consequence.**

### G2 · The historic-edit screen shares the tab strip · **name the boundary**

`EditWorkoutViewModel` also conforms to `SetTableDataSource`
([:632](Repster/Features/Workout/ViewModels/EditWorkoutViewModel.swift:632)), so PR3's marking
appears when editing a past workout. That is **correct and wanted** — grouping should be visible
where you are looking at the sets.

But the *behaviour* must not follow: `EditWorkoutViewModel` has no rest timer and no accessory slot.
Keep the derivation (PR2) on the protocol and the behaviour (PR4, PR5) in `ActiveWorkoutViewModel`
alone. Do not be tempted to move `supersetPrompt` onto the protocol for symmetry.

### G3 · Zero production data cuts both ways

Covered in PF1. Named here too because it is the reason several habits from the suggestion-engine
work do not apply: no golden master to diff, no backfill decision, no staged rollout, no kill switch.

### G4 · A non-contiguous group can already exist · **a bug this can ship with**

`CreateEditTemplateViewModel.setSupersetGroup(for:label:)`
([:330](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:330)) assigns a
group by exercise index with **no contiguity check**. A template with group A on exercises 1 and 3,
and something else at 2, is constructible today and propagates into a workout intact.

The scoping doc discussed adjacency only for the *authoring* flow — for data being created. It said
nothing about data that already exists. A run-builder that assumes contiguity will draw a container
spanning an exercise that is not in the group, which is worse than not marking it at all.

**PR3 and PR8 must both handle it**, and PR2's tests must include the shape. Whether the template
editor should also start preventing it is a separate question and not blocking.

### G5 · A group of one is reachable four ways

Delete one half of a pair; replace one half; import a template with a single-member group; dissolve
a group partially. In each case the survivor keeps a `supersetGroupId` with no partner.

`nextInSuperset` returns nil, so PR5's prompt correctly never appears. But PR3 would render a
one-member segmented container, which looks like a rendering bug. **Treat `count < 2` as ungrouped
everywhere** — stated in PR2, tested in PR2 and PR3, exercised in PR9's acceptance.

### G6 · Zero is a floor, not the truth · **changes what the number means**

PR4 writes `restDurationSeconds = 0` because the alternative (`nil`) asserts a *full configured
rest*, which is flatly wrong. But 0 is not literally right either: you did not rest, yet ~45 seconds
of wall-clock time passed while you did the partner exercise, and some recovery happened in it.

Two things follow, and both should be in the code comment rather than discovered later:

1. **0 is deliberately conservative.** It under-credits recovery slightly, where `nil` over-credits
   it enormously. Given the model's job is to avoid prescribing more than the lifter can do, erring
   toward "less recovered" is the safe direction. The accurate fix — recording real elapsed time
   between same-exercise sets — needs `WorkoutSet.startedAt`, which exists on the model and is
   [never populated](FEATURE_SCOPING_BRIEF.md). Out of scope; recorded as the better answer.
2. **The fatigue chain cannot see the partner at all.** "Session fatigue" is computed per exercise
   ([SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md](SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md) §3 G6), so
   Bench's chain never learns that four sets of Incline happened between its sets. Supersets make
   that pre-existing gap materially worse, because interleaving is the whole point. **This is not
   fixed here** — it is a modelling change, not a superset feature — but supersets are the first
   thing to make it visible, and it belongs in the suggestion program's backlog.

### G7 · Nothing will measure whether anyone uses this

The same hole PF3 named in the suggestion plan, where measuring turned out to be the highest-value
item in the document. `WorkoutInteractionTally` already exists and its enum raw values *are* the
analytics property names ([WORKOUT_INTERACTION_TALLY_DESIGN.md](WORKOUT_INTERACTION_TALLY_DESIGN.md) D3),
so adding counters is two enum cases and no new plumbing:

- `supersetPromptTaps` — did the one-tap shortcut earn its place, or do people use the tabs anyway?
- `supersetCreates` — is in-workout authoring (PR9, the most expensive item here) actually used?

Land these **with PR5 and PR9 respectively**, not after. Without them the follow-up question
"should we build option (b) after all" has no evidence behind it.

---

## 4. Test plan

Run the suite **once**, into a log — concurrent `xcodebuild` runs invent failures and truncate the
count:

```bash
xcodebuild test -project Repster.xcodeproj -scheme Repster \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tee /tmp/superset-tests.log
```

| PR | New coverage |
|---|---|
| PR1 | `SetServiceTests` — three inheritance shapes |
| PR2 | Stub conformer — no group, clean pair, half-tagged, one-member, non-contiguous |
| PR3 | Run-builder as a pure function, same five shapes |
| PR4 | Four behaviour cases **plus the mutation check** on the `= 0` write |
| PR5 | Prompt lifecycle — four clear routes, keypad suppression |
| PR6 | Refactor: existing tests must pass unchanged |
| PR7 | Both `WorkoutHistoryGroup` consumers; chip stacking |
| PR8 | Both workout-detail surfaces; non-contiguous fallback |
| PR9 | Create adjacent / non-adjacent / dissolve / degrade-to-one |

### Device pass

Per PF1 there is no historic data to shake this out, so the device pass carries more weight than
usual. Add to [DEVICE_TEST_PASS.md](DEVICE_TEST_PASS.md):

1. Superset from a template → strip marked, ticking mid-group starts no timer, prompt names the partner.
2. Create one mid-workout on ungrouped exercises → marking appears, behaviour follows immediately.
3. Backgrounding mid-group → no stale rest timer on return (`recalculateTimerAfterBackground`).
4. Finish the workout → history chip and joined card both correct in Calendar and Home.
5. Live Activity through a full group (PR10).

---

## 5. Release shape

**PR1–PR5 ship together.** The marking without the rest behaviour is decoration; the rest behaviour
without the marking is unexplained. Neither half is releasable alone.

**PR6–PR8 (history) can ship in the same release or the next one.** They depend only on PR1. If
the release is getting long, they are the safe thing to defer — with the caveat that a user who
supersets in release *n* and gets history in *n+1* has a window of sessions they cannot explain.
Prefer shipping together.

**PR9 (authoring) is separable.** Shipping PR1–PR8
first means supersets work but can only be defined in a template — which is exactly today's
capability plus everything that makes it useful, so it is a coherent release on its own.

**PR10 is a follow-up.**

---

## 6. Deliberately not done

- **A kill switch.** The suggestion-engine work added one for the capacity guards because that
  change moved everyone's numbers on the same day. This changes nothing for anyone who does not
  have a grouped template, and per PF1 that is currently everyone. A switch would be ceremony.
- **Fixing the early-dismissal case of the `restDurationSeconds` bug.** Pre-existing, wider than
  supersets, and a behaviour change for every user. Owed, but separately — see
  [SUPERSETS_SCOPING.md](SUPERSETS_SCOPING.md) §9.
- **Teaching the fatigue model about cross-exercise interleaving** (G6.2). A modelling change that
  belongs in the suggestion program, not in this feature.
- **Preventing non-contiguous groups in the template editor** (G4). PR3 and PR8 handle the data
  defensively; whether the editor should stop producing it is a separate call.
- **Groups of three or more.** A data-model no-op and a strip-width problem. Ship pairs, see if
  anyone asks — and `supersetPromptTaps` (G7) is how you would know.
