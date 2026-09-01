# Supersets — Scoping

**Date:** 2026-08-31
**Branch:** `NewMain`
**Status:** direction settled, nothing built.
**Supersedes:** the options list in [FEATURE_SCOPING_BRIEF.md](FEATURE_SCOPING_BRIEF.md) §7.
**Design:** https://claude.ai/code/artifact/a2262a93-3765-4e2c-9e73-8b2726353389

---

## 0. The decision

**Option (c), marked only** — the brief's cheapest option, not its recommended one (b).

Grouped exercises are marked in the tab strip, no rest runs inside a group, and the bottom
accessory offers the next lift in the group instead of a countdown. **Navigation is never
automatic.** Auto-advance was rejected: the screen moving under you mid-set is a real cost in a
gym, and it buys a tap.

Three things this commits to beyond the brief:

- **Creating and dissolving a group during a live workout.** Today grouping exists only in the
  template editor. Without it, a superset you decide on at the rack cannot be expressed at all.
- **The marking must be nearly free.** The tab strip scrolls horizontally and every exercise competes
  for that width. A first pass using a bracket, a `SUPERSET A` label, a caption row and a prompt
  button was rejected on exactly this.
- **Supersets must be identifiable in history.** A set taken with no rest after another exercise is
  systematically weaker than the same set rested. If history cannot show that, a superset session
  reads as a regression — and §5 shows the model makes the same mistake.

---

## 1. What already exists

The data layer is done and the template path works. This was verified, not assumed.

| Piece | Where | State |
|---|---|---|
| Field on template exercises | [TemplateExercise.swift:10](Repster/Data/Models/TemplateExercise.swift:10) | Done |
| Field on sets | [WorkoutSet.swift:36](Repster/Data/Models/WorkoutSet.swift:36) | Done |
| Template authoring UI | [CreateEditTemplateViewModel.swift:314](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:314), [CreateEditTemplateView.swift:325](Repster/Features/Templates/Views/CreateEditTemplateView.swift:325) | Done, A/B/C only |
| Template → workout | [TemplateService.swift:292](Repster/Core/Services/TemplateService.swift:292) | **Works.** Every seeded set carries the id |
| Workout → template | [TemplateService.swift:350](Repster/Core/Services/TemplateService.swift:350) | Done, reads `sortedSets.first` |
| JSON backup round-trip | [ExportService.swift:501](Repster/Core/Services/ExportService.swift:501) | Done |
| Execution UI | `Features/Workout/` | **Zero references** |

The brief flagged template→workout propagation as *"may already be broken — test this first."*
It is not broken. Strike that risk.

---

## 2. Two defects that gate this

### 2.1 A set added mid-workout is silently ungrouped

**`SetRepository.create` takes no `supersetGroupId`**
([SetRepository.swift:30](Repster/Core/Repositories/SetRepository.swift:30)).

Every set added during a live workout is written with `supersetGroupId = nil`, including on an
exercise whose template sets are grouped. Grouping is stored **per set**, not per exercise, so a real
session ends up half-tagged: the template's four sets carry the id, the fifth you added at the rack
does not.

Nothing notices today because nothing reads the field. Every rule in §4 reads it.

Fix: add the parameter, thread it through `SetService.create`, test it. The same pass decides how
"the exercise's group" is derived — recommend **any non-nil set in the exercise defines the group,
and writes repair the rest**, rather than `sets.first?.supersetGroupId`, which is wrong whenever the
first set predates the grouping.

### 2.2 Skipping rest records *nothing*, and nothing means "a full rest happened"

This one is **created by this design** and must ship with it.

`restDurationSeconds` is written by `captureRestDurationOnLastCompletedSet`
([ActiveWorkoutViewModel.swift:1602](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:1602)),
and its own doc comment says it is *"only called when the timer runs to zero (not on early
dismissal)."* A superset set starts no timer, so the field stays `nil`.

Both fatigue paths in `LoadPrescriptionService`
([:762](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:762),
[:1053](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:1053)) then do:

```swift
let restSeconds = Double(previousSet.restDurationSeconds ?? Int(configuredRestSeconds))
sessionFatigue *= exp(-restSeconds / recoveryConstant)
```

`nil` falls back to the exercise's **configured** rest. So a superset set with zero rest decays
fatigue as though the lifter rested two minutes, when the correct factor is `exp(0) = 1` — no decay
at all. The model **under-estimates accumulated fatigue and over-estimates readiness on exactly the
sets where the lifter is most cooked**, and suggests weights that are too heavy. It also feeds
`FatigueLearningService` ([:244](Repster/Core/Services/FatigueLearningService.swift:244)), so the
error is learned, not merely displayed.

Same shape as the drop-set defect in [DROP_SETS_SCOPING.md](DROP_SETS_SCOPING.md).

Fix: **write `restDurationSeconds = 0` explicitly** on a set whose rest was suppressed, in the same
branch that suppresses it. One line, next to the change.

Worth noting this already bites today whenever someone dismisses the rest timer early — supersets
only make it systematic instead of occasional. Fixing the superset case does not fix the dismissal
case; that is a separate, pre-existing bug and is **not** in this scope.

---

## 3. The marking

Segmented — the pair in one container — chosen over a link node between loose tabs and a rail under
them. It is not new grammar: the sub-tab bar directly below it
(`WorkoutSubTabBar`, [ActiveWorkoutView.swift:467](Repster/Features/Workout/Views/ActiveWorkoutView.swift:467))
is already a segmented container with an inner selected pill.

The first attempt was correct and too quiet. Three intensities of the same idea, costed against
today's two ungrouped tabs (`gap: 7`, tab `padding: 0 14`, `height: 36`, `radius: 7`):

| | Container | Joiner | Horizontal | Vertical |
|---|---|---|---|---|
| 1 · Outline | `bgCard @ 0.9`, border 34% | 1px hairline | −1px | 0 |
| 2 · Filled | group @ 10%, border 55% | 1px hairline | −1px | 0 |
| **3 · Filled + link** *(chosen)* | group @ 10%, border 55% | **link glyph, 11px** | **+10px** | **0** |

**Chosen: 3.** The glyph removes the need to learn what the container means, and +10px is a seventh
of what the bracket-and-label version cost.

```
container   height 40, padding 2, radius 9
            background groupColor @ 0.10, border 1px groupColor @ 0.55
inner tab   height 36, padding 0 14, radius 7   — IDENTICAL to a loose tab but for the surface
            active   → accent fill, white text   (unchanged)
            inactive → transparent, textTertiary (NOT bgCard — the container is the surface)
joiner      `chevron.left.chevron.right`, 10pt semibold, groupColor, 15pt wide
```

**Revised while building (2026-08-31).** The first spec shrank inner tabs to 32pt so the container
matched a loose tab and the strip's height did not move. Built the other way: inner tabs keep their
full 36pt, and the container is 4pt taller. A 32pt tap target is worse than the 36pt the strip
already has, against a design-system floor of 44pt the strip is already under — and the constraint
that started this was **horizontal**, which is unchanged. Keeping `padding 14` on the inner tabs is
exactly what preserves the +10px arithmetic.

Group colour follows the template editor's existing palette
([CreateEditTemplateViewModel.swift:319](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:319)):
A = `accent`, B = `chart5`, C = `chart7`, D = `chart8`.

**No letter label in the strip.** "SUPERSET A" costs ~70px of the scarcest space in the app to name
something the container already shows. The letter is a template-editor concept; during a workout
there is no need to distinguish groups that are not both on screen.

---

## 4. Behaviour in the workout

Most of it lands in one place: **step 6 of `completeSet`**
([ActiveWorkoutViewModel.swift:510](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:510)),
where the rest timer starts today.

| Rule | Behaviour |
|---|---|
| Working set, another member still has work, walk did **not** wrap | **No rest.** Accessory shows that member |
| Working set, another member still has work, walk **wrapped** | Normal rest **and** the prompt, stacked — the round closed |
| Working set, no other member has work left | Normal rest, no prompt — the group is done |
| Working set, ungrouped | Unchanged |
| **Any set whose rest is suppressed** | **Write `restDurationSeconds = 0`** — see §2.2 |
| Warm-up set, any exercise | Unchanged. Warm-up rest time applies; you do not superset warm-ups |
| Order within a group | Derived from existing exercise order, not stored |
| PRs / stats / charts / e1RM | Untouched — a group never touches `exerciseId`, `weight` or `reps` |

### The walk · revised 2026-08-31

"Next in the group" is a **cyclic** walk in strip order, skipping members with no incomplete working
set, and it reports whether it wrapped. One traversal answers both questions the branch asks:

- **where to point** — the first member with work left, going forward and wrapping once
- **whether rest is earned** — wrapping *is* the round closing, so `wrapped` is the rest condition

This replaced a one-directional `isLastMember` rule, for two reasons. The prompt only helped on one
leg of a round: Bench sent you to Incline, and Incline sent you nowhere, so every second round began
with a manual tab hunt. And the old rule suppressed rest for any non-last member **regardless of
whether the partner had sets left** — finish Incline early, go back to Bench, and every remaining
Bench set got zero rest while pointing at an exercise with nothing to do. Both are covered by
`SupersetGroupingTests`.

Warm-ups are excluded from "has work left": a leftover un-ticked warm-up row is common
([UNPERFORMED_SETS_SCOPING.md](UNPERFORMED_SETS_SCOPING.md)) and must not send someone back to an
exercise they have finished.

**Order needs no new field.** Exercise order is already reconstructed from `MIN(orderInWorkout)`
across each exercise's sets ([ActiveWorkoutViewModel.swift:379](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:379)),
so "the next member of this group" is a filter over `exercises` in its existing order.

**Rest inside a group is zero, not short.** `HealthProfile` already carries
`defaultRestTimeSeconds` and `defaultWarmupRestTimeSeconds`, so a third default fits the pattern if
it is ever wanted — but shipping a configurable transition rest before anyone asks is a setting
nobody will find.

### The accessory slot

`RestTimerState` is a four-case enum consumed through
`ActiveWorkoutBottomAccessoryLayout.shouldShowRestTimer(for:isKeyboardVisible:)`
([ActiveWorkoutView.swift:12](Repster/Features/Workout/Views/ActiveWorkoutView.swift:12)).

**The prompt stacks above the timer rather than competing for the slot.** Closing a round earns rest
*and* leaves you needing to walk back to the top of the group, so both answers are live at once: the
timer says how long, the prompt says where. Mid-round only the prompt shows, because no timer is
running. The stack costs 45pt, and only while resting — when nobody is logging.

The superset prompt is **not** a fifth case on that enum — it is not a timer, it has no duration, and
folding it in would make every `switch` in the timer code answer a question about supersets. Add a
sibling property on the view model (`supersetPrompt: SupersetPrompt?`) and one branch in
`bottomAccessoryArea`. Same 43pt row, same 2px rule above it, same slot — so nothing on screen moves.

The keypad rule carries over unchanged: suppress the prompt while the set keypad is open, for the
same reason `.finished` is suppressed.

---

## 5. Behaviour after the workout

Two surfaces, both reusing patterns the app already has. **Set rows are left alone in both** — they
are a true record, exactly as the progression-exclusion work already decided
([ExerciseHistoryView.swift:42](Repster/Features/Exercise/Views/ExerciseHistoryView.swift:42)).

### 5.1 Exercise history — a chip in the session header

`ExerciseHistoryView`'s session card header is `[date] [chips] [Spacer]`, and already renders
`ProgressionExclusionChip` there. The superset chip goes in the same slot and they stack.

Match `ProgressionExclusionChip`'s own geometry
([ProgressionExclusionViews.swift:20](Repster/Features/Workout/Views/Components/ProgressionExclusionViews.swift:20)):
`HStack(spacing: 3)`, 8pt glyph, 9pt bold text, `padding 3/5`, `cornerRadius 4`, soft background,
20% border. Colour is the group colour rather than `.stale` — this is a relationship, not a
lower-confidence state.

Text: `⟨⟩ SUPERSET · <PARTNER NAME>`. **It names the partner here**, because this screen shows one
side of the pair and the partner is the explanation for the numbers.

### 5.2 Workout detail — the pair joins into one card

Calendar and Home render `detail.exerciseGroups` as a `VStack(spacing: 12)` of `CalendarExerciseCard`
([CalendarWorkoutDetailView.swift:92](Repster/Features/Calendar/Views/CalendarWorkoutDetailView.swift:92)).
Grouped exercises collapse into a single container: one `bgCard` card, `groupColor @ 0.32` border,
a 7pt tinted header strip reading `⟨⟩ SUPERSET`, and a `groupColor @ 0.22` hairline between the two
exercises. Same grammar as the tab strip, one level up.

**No partner name needed here** — both sides are visible.

### 5.3 Not in scope

- The finish/summary sheet. Grouping there adds nothing you did not just live through.
- Charts. A superset flag is per-set context, not a series.
- Retro-tagging history from before this ships. There is nothing to read.

---

## 6. Authoring, in-workout

The tab strip's context menu already holds Move Left / Move Right / Replace Exercise… / Delete
Exercise ([ExerciseTabStripView.swift:70](Repster/Features/Workout/Views/ExerciseTabStripView.swift:70)).
**Superset with…** joins it. No new surface, no new gesture, and the same menu carries **Remove from
superset** once the exercise is in one.

Flow: long-press tab → *Superset with…* → sheet listing the workout's other exercises → *Create
superset*. Creating writes one new `UUID` to every set of both exercises, through the repository on
the owning actor (see [SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md](SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md)).

### Grouping is all-or-nothing per exercise · decided 2026-08-31

**Creating** a group stamps the new `UUID` on **every** set of both exercises. **Dissolving** clears
it from **every** set of the exercise, completed rows included.

The alternative — writing only to incomplete sets, so completed rows stayed a literal record of how
each was performed — was considered and rejected. Dissolving a group after logging into it is a
niche case, and *Remove from superset* has to mean the exercise is not in a superset; a history chip
that survives the removal is the confusing outcome, not the honest one.

What this buys, beyond the simpler mental model: **an exercise's sets always agree about their
group**, so there is no half-tagged state to derive around, no read rule that has to prefer one kind
of row over another, and the history chip has one clean meaning — *this exercise was supersetted in
this session*. The cost is that a set logged before the group was created reads as supersetted
afterwards. That is accepted, and it is why the chip is worded per session rather than per set.

**Replacing** an exercise inside a group: the replacement **inherits** the group. You swapped the
movement, not the structure.

### Two constraints fall out of the marking

1. **A group must be contiguous in the strip.** A container cannot wrap two tabs with a third between
   them. Picking a non-adjacent partner therefore reorders — which `reorderExercises`
   ([ActiveWorkoutViewModel.swift:960](Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift:960))
   already does, and which the sheet should say out loud on the row ("Would move up next to Bench
   Press"). Reorder was rebuilt on `applyOrdering` with identity-based selection on 2026-08-29
   ([EXERCISE_REPLACE_AND_REORDER_DESIGN.md](EXERCISE_REPLACE_AND_REORDER_DESIGN.md)), so it is
   sound to build on — an earlier draft of this doc said otherwise and was working from a stale note.
2. **Pairs only, for v1.** Groups of three are a data-model no-op but a strip-width problem. Ship
   two, see if anyone asks.

### Template authoring — cycle the palette · decided 2026-08-31

Three limits disagree today, and none of them is deliberate:

| | Limit | Where |
|---|---|---|
| Groups you can pick | **3** | hard-coded `["A", "B", "C"]` ([CreateEditTemplateView.swift:326](Repster/Features/Templates/Views/CreateEditTemplateView.swift:326)) |
| Groups that get a colour | **4** | `supersetColor(for:)` switches A–D, else `textTertiary` ([CreateEditTemplateViewModel.swift:319](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:319)) |
| Groups that get a letter | **5** | `supersetLetters` ([:54](Repster/Features/Templates/ViewModels/CreateEditTemplateViewModel.swift:54)) |

Past five, `supersetLabel` returns nil and the letter silently vanishes. The picker cap is not
reachable data-wise either — import maps a free-text `supersetGroupKey` to UUIDs
([TemplateService.swift:525](Repster/Core/Services/TemplateService.swift:525)), so an imported
template can already arrive with more groups than the editor can render.

Three is too few for real programming: an antagonist-paired arm day is four pairs and is an entirely
ordinary way to train.

**Decided: the letter is the identity, the colour is reinforcement — so cycle the palette.**

- ~~Drive the menu from `supersetLetters` instead of a literal, keeping the five that are already
  declared.~~ **Superseded 2026-09-01 — there is no letter menu.**
  [TEMPLATES_IMPLEMENTATION_PLAN.md](TEMPLATES_IMPLEMENTATION_PLAN.md) P4.3 replaces the picker with
  *Superset with…*, which asks for a **partner** and assigns the letter itself: the first free entry in
  `supersetLetters`. The user experienced the letter picker as undiscoverable — you assign a letter,
  twice, on two exercises, with nothing saying a second step exists — and picking a partner removes both
  the second step and the group-of-one it could leave behind. Everything else in this section is
  unchanged and is what P4.3 implements.
- `supersetColor` indexes `[accent, chart5, chart7, chart8]` by the letter's position, modulo four.
  E reuses A's blue; the letters keep them apart.
- Wanting more later is then a one-line change to one array, with nothing else to keep in sync.

The palette is four because the rest of the chart colours are spoken for: green means completed, red
means delete, gold means PR, and orange is the note-indicator dot. Do not reach for them.

This does not touch the workout — the tab strip derives grouping from `supersetGroupId` and assigns
its own colours by encounter order, so it never sees these letters. It does slightly widen the
surface for the non-contiguous case in §6's constraint 1, which PR3 and PR8 handle defensively
regardless.

---

## 7. Open questions

1. **Does the Live Activity need the group?** Not stale, as first written — `restDisplay()`
   ([WorkoutActivityAttributes.swift:93](Repster/Features/Workout/Models/WorkoutActivityAttributes.swift:93))
   falls through to `.ready` when no timer runs, so mid-group it reads *"Bench Press · Ready for next
   set"*. A valid state pointing at the exercise you just finished. Cleanest fix is a sixth
   `RestDisplay` case carrying the partner's name, leaving `exerciseName` alone so the widget keeps
   agreeing with the app's own screen — the same move as the in-app rest bar, one level out.

---

## 8. Work breakdown

| # | Work | Size | Gated by |
|---|---|---|---|
| 1 | `supersetGroupId` on `SetRepository.create` + `SetService.create`, with a test | S | — |
| 2 | Group derivation on the view model (`group(for:)`, `nextInGroup(after:)`) | S | 1 |
| 3 | Segmented + link marking in `ExerciseTabStripView` | S | 2 |
| 4 | Rest branch in `completeSet` step 6, **including `restDurationSeconds = 0`** | S | 2 |
| 5 | `supersetPrompt` + accessory branch in `bottomAccessoryArea` | M | 4 |
| 6 | Superset chip in `ExerciseHistoryView` session header | S | 1 |
| 7 | Joined card in `CalendarWorkoutDetailView` / `CalendarExerciseCard` | M | 1 |
| 8 | *Superset with…* / *Remove from superset* + partner sheet | M | 2 |
| 9 | Live Activity next-up line | S | 5 |
| 10 | Template picker: drive from `supersetLetters`, cycle the colour | XS | — |

1–5 are the feature in the workout. 6–7 make it legible afterwards, and depend only on item 1 — they
can go in parallel. 8 is what makes it usable without a template. 9 gives the widget something
useful to say mid-group. 10 is independent of all of it and can go any time.

**Item 4 is not optional and not deferrable.** Shipping the rest suppression without the
`restDurationSeconds = 0` write actively degrades suggestion quality for anyone who supersets.

---

## 9. Deliberately not done

- **Auto-advance (option b).** Rejected in §0. Recorded because it is the brief's recommendation and
  this overrides it.
- **Grouped / interleaved set table (option a).** The 36 / 74 / 74 / 42 / 44 / 40 row has no width
  left for two exercise names, so it is a redesign of `SetTableView` and `SetRowView`, not an
  addition to them — the ~5,300 lines [1_5_DECISION_RECORD.md](1_5_DECISION_RECORD.md) already
  deferred. **Unblocked by:** this shipping and showing real superset usage.
- **Fixing the early-dismissal case of §2.2.** Pre-existing, wider than supersets, and a behaviour
  change for everyone. Owed, but separately.
- **The block container** (circuits, AMRAP, EMOM). A superset is one block type; this builds the
  superset, not the container. See the Workout blocks entry in
  [1_5_DECISION_RECORD.md](1_5_DECISION_RECORD.md).
- **The sub-set primitive.** [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md):145 and
  [DROP_SETS_SCOPING.md](DROP_SETS_SCOPING.md):127 both say to design "a set containing sub-sets"
  once, against `supersetGroupId` and `pauseDuration`. Nothing here changes the shape of
  `supersetGroupId`, so that design is not foreclosed — but it is also not started.
- **CSV import of `superset_id`.** Still ignored
  ([ImportView.swift:543](Repster/Features/Settings/Views/ImportView.swift:543)). Migrating in from
  Hevy or Strong loses grouping. Out of scope, worth a line in the import screen's copy.
- **Reusable superset blocks saved to a library** — the top superset ask in the r/Hevy thread
  ([COMPETITIVE_FEATURE_ANALYSIS.md](COMPETITIVE_FEATURE_ANALYSIS.md) Gap 4). Fits the template
  model, not this.
