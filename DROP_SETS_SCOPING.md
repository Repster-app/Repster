# Drop Sets — Scoping

**Status:** scoping only, nothing built
**Date:** 2026-08-26
**Supersedes:** [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md) Phase 1 and Decision 4. That doc stays
as the full survey of all 13 types; this one is the build scope for the decision actually taken —
hide the unbuilt types, ship drop sets for real, and fix the engine defects that make a tagged
drop set behave badly today.

## What we're deciding

1. Hide the set types that have no feature behind them, without breaking existing data.
2. Make `dropset` a real, selectable type that is **visible in history** — you can look at a
   finished workout and see that set wasn't a warm-up and wasn't a normal set.
3. Fix the suggestion-engine defects that a visible drop set would otherwise expose to users.

These have to ship together. Today drop sets arrive almost exclusively from Strong/Hevy import,
so the defects below are largely invisible. The moment the picker offers "Drop Set" as a real
choice, people will use it, and every one of these becomes a user-facing bug.

---

---

## Build checklist

The actionable form of everything below. Phase order is deliberate — see the sequencing note.

**Phase 1 — engine fixes (ship alone, nothing user-visible)**
- [ ] Capacity-evidence predicate in `normalizedObservedCapability` — accept only `working`, `amrap`, `failure`
- [ ] Use a **new** predicate; do not narrow `isCapabilityTrackingSetType` (it also drives the freshness bonus)
- [ ] Make the `.observed` blend asymmetric — upward replaces freely, downward capped per set
- [ ] Exclude non-capacity types from fatigue learning via a new audit status
- [ ] Tests: drop-set-craters-capability, freshness bonus not re-armed after a drop set, clamp bounds

**Phase 2 — hide the unbuilt types**
- [ ] `SetType.userSelectable` = warm-up, working, drop set; picker uses it instead of `allCases`
- [ ] Picker also shows the set's current type when it's a hidden one (imported `failure` etc.)
- [ ] Narrow the AI template prompt vocabulary to the same list
- [ ] No enum cases removed, no migration

**Phase 3 — drop sets visible**
- [ ] Extract a shared badge + numbering helper across the three renderers
- [ ] Fix history numbering counting warm-ups; add the missing warm-up letter on the calendar card
- [ ] Add the `D1`/`D2` badge variant; drop sets don't consume working-set numbers
- [ ] Resolve the ten `== .working` sites behind two named predicates, audited per site

**Phase 4 — instrument, then flatten**
- [ ] Add `setType` to `FatigueObservation`
- [ ] Flatten `setTypeMultiplier`; update the two ordering tests
- [ ] Release note for shifted suggestions on imported Strong/Hevy sessions

**Blocked on a product decision** (see Open questions)
- [ ] Drop sets and PRs
- [ ] Drop sets and volume
- [ ] Rest-timer behaviour between drops
- [ ] Whether `failure` / `amrap` also become selectable

---

## The finding that shapes everything: two incompatible definitions of "a real set"

[SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md) claims the 11 non-warmup, non-partial types are
"identical to `working` everywhere except one fatigue constant." **That is wrong**, and it is the
most important correction in this doc.

The codebase carries two conventions for "does this set count", and they disagree:

| Convention | Used by | A `dropset` is… |
|---|---|---|
| **Denylist** — `!= .warmup && != .partial` | [PRService:738](Repster/Core/Services/PRService.swift:738), [StatsService:205](Repster/Core/Services/StatsService.swift:205), [LoadPrescriptionService:310](Repster/Core/Services/LoadPrescriptionService.swift:310), [FatigueLearningService:169](Repster/Core/Services/FatigueLearningService.swift:169) | **counted** |
| **Allowlist** — `== .working` | [InsightRules:32](Repster/Core/Services/InsightRules.swift:32), [InsightsService:120](Repster/Core/Services/InsightsService.swift:120), [CopyPreviousSheet:178](Repster/Features/Home/Views/CopyPreviousSheet.swift:178), [HomeViewModel:348](Repster/Features/Home/ViewModels/HomeViewModel.swift:348), [ExerciseInfoProvider](Repster/Features/Workout/ViewModels/ExerciseInfoProvider.swift:52) ×6 | **invisible** |

So a set tagged "Drop Set" today counts toward your volume, your PRs and your e1RM baseline, while
simultaneously vanishing from Copy Previous, the Home last-performance card, Insights, and the
estimated-reps default. Nobody chose that. It is the accumulated result of ten call sites each
answering "what's a real set?" independently.

**This must be resolved before drop sets become selectable**, or the first thing a user notices
after tagging a drop set is that their Copy Previous forgot it.

---

## Decision 1 — hide the unbuilt types

**Keep selectable:** `warmup`, `working`, `dropset`. Nothing else.

The picker at [SetRowView.swift:259](Repster/Features/Workout/Views/SetRowView.swift:259) currently
renders `SetType.allCases` — 13 undifferentiated options, twelve of which change nothing a user can
observe. Replace `allCases` with a `SetType.userSelectable` list.

**Three rules keep this safe:**

1. **Nothing is removed from the enum.** Raw values are persisted in SwiftData, written to the JSON
   archive ([ExportService.swift:495](Repster/Core/Services/ExportService.swift:495)), and produced
   by both importers ([ImportService.swift:1001](Repster/Core/Services/ImportService.swift:1001),
   [:1359](Repster/Core/Services/ImportService.swift:1359)). Cutting a case means a migration and
   breaks old archives. No case is worth that.
2. **A set that already has a hidden type keeps it, and the picker shows it.** If an imported set is
   `failure`, the menu lists Warm-up / Working / Drop Set **plus** Failure with its checkmark. The
   user can switch away from it; they just can't newly assign it. Silently showing "Working" for a
   set stored as `failure` would be a lie about their data.
3. **Hidden types still render.** Whatever badge and stats treatment a type gets, it gets whether or
   not it's selectable.

~~**Also narrow the AI template vocabulary.** `TemplateListSheet.swift` hands the model all 13 raw
values, so it can emit types the app can't log. Feed it the same `userSelectable` list.~~
**Moot 2026-09-01** — the AI template helper was deleted
([TEMPLATES_IMPLEMENTATION_PLAN.md](TEMPLATES_IMPLEMENTATION_PLAN.md) P5.1), taking the prompt with it.
No path now feeds `SetType.allCases` to anything outside the app.

**Size:** S. One list, one picker change, one prompt string.

---

## Decision 2 — what "real drop sets" means in this scope

The user-facing ask is: *you can see in history that it wasn't a warm-up and wasn't a normal set.*
That is an **annotation** feature, not the sub-set primitive from
[SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md) Phase 3.

**Recommendation: one row per drop, each tagged `dropset`.** You log 100×8, then 80×6, then 60×5 as
three rows; rows two and three are drop sets. No schema change, no sub-rows, no auto weight-drop
calculation. It ships now and it satisfies the actual complaint.

**What this deliberately does not include** (and should be stated in release notes, not silently
omitted): auto-calculated drop percentages, drops sharing one set number, suppressed rest timer
between drops, volume summed under a parent set. Those need the sub-set primitive, and that
primitive should be designed once against `supersetGroupId` and the dead `pauseDuration` field —
not improvised here.

### The badge

Reuse the 36pt column, exactly as warm-ups already do
([SetNumberBadge.swift](Repster/Features/Workout/Views/Components/SetNumberBadge.swift)).
Add a `dropsetBadge` variant beside `warmupBadge`: **`D1`, `D2`, `D3`** — same italic treatment,
distinct colour. Zero layout change, and the pattern is already established, so it needs no
explanation to existing users.

**Numbering rule:** drop sets number independently within the exercise and **do not consume
working-set numbers**, identical to how warm-ups behave at
[SetTableView.swift:138](Repster/Features/Workout/Views/SetTableView.swift:138). A one-branch change
to that existing closure.

Known limitation: two separate drop sequences in one exercise produce D1–D4 continuous rather than
restarting. Accept it. Fixing it needs a grouping field, which is Phase 3's job. The upgrade path
when that lands is suffixed numbering (`3a`, `3b`) tying each drop to its parent set.

### Where the badge has to appear

The live workout screen is the easy one. History is the actual ask, and it is **three separate
renderers that don't share code**:

| Surface | Today | Needed |
|---|---|---|
| [SetTableView](Repster/Features/Workout/Views/SetTableView.swift:138) (live) | `SetNumberBadge`, W1/W2 | `D1/D2` variant |
| [ExerciseHistoryView:60](Repster/Features/Exercise/Views/ExerciseHistoryView.swift:60) | inline `Text("W")`, own styling | drop-set indicator |
| [CalendarExerciseCard:85](Repster/Features/Calendar/Views/Components/CalendarExerciseCard.swift:85) | `isWarmup` used **only** for 0.45 opacity — no letter at all | drop-set indicator |

**Two pre-existing bugs surface here and should be fixed in the same pass**, because this work
touches exactly the lines that cause them:

- **History numbering counts warm-ups.** Both `ExerciseHistoryView` and `CalendarExerciseCard`
  number with `index + 1` across *all* sets, so after two warm-ups your first working set displays
  as "3". The live workout screen says "1". Same workout, two different numbers.
- **`CalendarExerciseCard` shows no warm-up letter**, only dimming — so a warm-up is
  indistinguishable from a light working set.

Adding a third badge type on top of numbering that's already wrong will make it worse. Extracting a
shared badge/numbering helper across the three renderers is the right move and is most of the work
in this decision.

**Size:** M — three renderers, one shared helper, two latent bugs.

---

## Decision 3 — resolve the allowlist/denylist split

Do **not** blanket-replace the ten `== .working` sites. Some genuinely want straight working sets
only. Introduce two named predicates on `SetType` so each call site states its intent:

- `countsAsPerformedWork` — everything except `warmup` and `partial`. The denylist, named.
- `isStraightWorkingSet` — `working` only. For places that really do mean "an ordinary set".

Then audit all ten. My read on the non-obvious ones:

| Site | Verdict | Why |
|---|---|---|
| [CopyPreviousSheet:178](Repster/Features/Home/Views/CopyPreviousSheet.swift:178) | `countsAsPerformedWork` | You copied a session; the drops were part of it |
| [HomeViewModel:348](Repster/Features/Home/ViewModels/HomeViewModel.swift:348) | `countsAsPerformedWork` | "Last performance" that hides half the session is wrong |
| [InsightRules:32](Repster/Core/Services/InsightRules.swift:32) | **stays** `isStraightWorkingSet` | Rest–rep pair analysis; a drop set's ~0s rest is noise, not signal |
| [ExerciseInfoProvider:52](Repster/Features/Workout/ViewModels/ExerciseInfoProvider.swift:52) | **stays** `isStraightWorkingSet` | Target-reps default from `last(where:)` — a trailing drop set would set a bad default |
| ExerciseInfoProvider ×5 (e1RM/PR reference) | `countsAsPerformedWork` | All use max/best, so a low drop-set e1RM is harmless and excluding it is inconsistent with the baseline logic |

**Size:** S–M. Mechanical, but needs a decision per site and a test per changed one.

---

## Decision 4 — the engine defects, in fix order

Full analysis in the session that produced this doc; summarised here as the build list.

**4a. A drop set replaces your session capability estimate. Fix first.**

`sessionCapabilityPolicy` is `.observed` ([LoadPrescriptionService.swift:127](Repster/Core/Services/LoadPrescriptionService.swift:127)),
and `.observed` returns the observed value outright — no blend, no clamp
([:269](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:269)).
`normalizedObservedCapability` ([:983](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:983))
rejects only warm-ups, partials, and RIR ≥ 3 — and a drop set is none of those, since it's usually
taken to RIR 0. So it sails through and *becomes* the capability figure for every remaining set of
that exercise.

Top set 100 kg × 8 @ RIR 2 → e1RM 133. Drop to 60 kg × 10 @ RIR 0 → 80, about 83 after the fatigue
normaliser. The engine now believes your capacity fell 38% mid-exercise.

Fix: accept only genuine capacity evidence — `working`, `amrap`, `failure`. AMRAP and failure are
the *best* evidence available and must stay. Reject `dropset` and `backoff` (submaximal by
definition), `myo`/`restpause`/`cluster` (fragmented reps, e1RM formulas don't apply), and
`tempo`/`isometric`/`eccentric` (a 5-second isometric "rep" isn't a rep).

⚠️ Add a **separate** predicate. Do not narrow `isCapabilityTrackingSetType`
([:1042](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:1042)) — it also
drives `hasSeenCompletedWorkSet` and the `isFirstSet` freshness bonus
([:944](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:944),
[:961](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:961)), so narrowing it
would let a set *after* a drop set wrongly claim the freshness bonus.

**Size:** S, one function, no schema change.

**4b. Clamp how far one set can pull capability down.**

4a only covers *labelled* sets. The same crater happens when someone just does a light set without
tagging it — the family the 32.5 kg case in
[SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md) belongs to. Make the
`.observed` blend asymmetric: upward moves replace freely, downward moves capped per set. Needs no
new data — the running prior is already in hand. Composes with the floor guardrail rather than
competing with it.

Note the asymmetry worth fixing: the *learning* path has a 20% weight-deviation guard
([FatigueLearningService.swift:203](Repster/Core/Services/FatigueLearningService.swift:203)); the
capability path has none. `SessionSetContext`
([:10](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:10)) carries no
prescribed weight, so mirroring that guard exactly would mean threading new data through the engine.
The clamp gets most of the benefit for far less.

**Size:** S.

**4c. Stop drop sets voting on the learned fatigue rate.**

`FatigueObservation` records no `setType` ([FatigueObservation.swift](Repster/Data/Models/FatigueObservation.swift)) —
only the audit row does. So a drop set's prediction error is laundered into that exercise's fatigue
rate and applied to every set of that exercise regardless of type. The step is **sign-only**
(±0.002 regardless of magnitude, [FatigueLearningService.swift:626](Repster/Core/Services/FatigueLearningService.swift:626))
and `minimumUsedSetsForExerciseLearning = 1`
([:109](Repster/Core/Services/FatigueLearningService.swift:109)), so **one drop set can be the entire
vote for a session** — and with ≥2 used sets it feeds the global rate too.

Fix: give non-capacity types their own audit status alongside `warmupNotTracked`. The enum, the
admin drawer, and the export already render statuses, so it's nearly free and stays visible in
diagnostics.

**Size:** S.

**4d. Then flatten the multipliers and instrument.**

`.dropset` is 1.4× ([:625](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:625)).
At the default rate that's worth ~1.8 pp of e1RM by set 3 and ~4.8 pp at a learned rate of 0.08 —
real, but an order of magnitude smaller than 4a.

Supporting evidence that this is the low-stakes step: `prescribeBatch`
([LoadPrescriptionService.swift:165](Repster/Core/Services/LoadPrescriptionService.swift:165))
already hardcodes `setType: .working` for every pending set, so that entry point behaves *as if*
the multipliers were flattened. Only the live workout screen passes real set types through
([WeightSuggestionData.swift:471](Repster/Features/Workout/Models/WeightSuggestionData.swift:471)).
The two paths disagree today, and flattening makes them agree.

One correction to [SET_TYPES_SCOPING.md](SET_TYPES_SCOPING.md), which treats 1.4 as a wrong number:
it isn't obviously wrong — a drop set genuinely *is* more fatiguing. The problem is that it's
**unfalsifiable** in the current architecture, and 1.0 is equally unvalidated, just a more
conservative prior. **The win in this step is the instrumentation, not the flatten**, which is
precisely why it goes last rather than first. Flattening without 4a would move a set-3 suggestion by
~1 pp while the 38% crater stays — a release note nobody can feel.

**Size:** S. Two ordering assertions at
[ActiveWorkoutViewModelSuggestionRefreshTests.swift:6185](RepsterTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift:6185),
one admin drawer row, one SwiftData field addition.

---

## Explicitly out of scope

The phase-by-phase work list lives in the [Build checklist](#build-checklist) at the top of this
doc — kept in one place so the two can't drift. What this scope deliberately excludes:

- Sub-set rows, auto drop percentages, drops sharing one set number, suppressed inter-drop rest
- Myo-rep, rest-pause, cluster logging flows
- Cutting any enum case

---

## Open questions

1. **Should a drop set count toward PRs?** It's `countsAsPerformedWork` today, so it does. A drop to
   60% won't beat a weight PR, but it could set a *rep* PR at a weight you've never done for that
   many reps. Legitimate or noise? Needs an answer before Phase 3 ships badges implying the app
   knows the difference.
2. **Does a drop set belong in volume?** Currently yes, via
   [StatsService:205](Repster/Core/Services/StatsService.swift:205). Probably right — the reps
   happened — but worth confirming, since it's the one place a drop set materially inflates a
   headline number.
3. **What's the drop-set rest-timer default?** Real drop sets have ~0s rest. The timer currently
   fires as usual, which is wrong, and the fatigue model reads
   `restDurationSeconds` for decay — so a long recorded rest on a drop makes the model *under*-count
   its fatigue. Cheap to special-case; needs a product call on whether to suppress the timer.
4. **Should `failure` and `amrap` also become selectable?** Both are single-row annotations needing
   no new primitive, both are named in the competitor analysis, and `failure` already arrives from
   both importers. Once the badge helper from Phase 3 exists they're nearly free. Deliberately left
   out here to keep the picker at three, but this is the obvious next increment.

## Sequencing note

Phase 1 is independent of every product decision here and should go in regardless — it fixes a live
correctness bug in the app's headline feature. Phases 2–3 are what users notice. Phase 4 wants the
data from Phase 1 in place first.
