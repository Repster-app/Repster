# Suggestion progression — diagnosis & design

> **Superseded in part, 2026-08-27.** P1 shipped. The O4 ladder analysis below is retained for its
> reasoning, but its framing is corrected in
> [SUGGESTION_OPEN_QUESTIONS.md](SUGGESTION_OPEN_QUESTIONS.md) §1: "a fixed target can never
> progress" is wrong — capacity is the peak of the last 3 workouts and *does* rise when performance
> does, so the plateau is a feedback loop created by the card anchoring the lifter to an exact rep
> count. O2's attribution of the 32.5 kg case to the censored "5+" chip is also wrong; see the
> behaviour audit §2.1. Start from the open-questions doc.

**Date:** 2026-08-26 · **Branch:** NewMain
**Status:** P1 fixed and shipped to the branch. P2 open. O2/O3/O4 undecided.

Field report, 2026-08-26, T-Bar Row. The lifter had done **60 kg × 8 @ RIR 0 in two
consecutive sessions** against a fixed target of 8 reps @ RIR 0, and the card kept saying
60 kg. Wanting to progress, they widened the set's rep target to **6-10** — and the card
then said **58.75 kg**, lower than the weight they had just done twice, with no indication
of what rep count it wanted.

Their own read: *"there might be two different things in this message."* There are.

---

## P1 — The card named the range, not the rep count it priced · FIXED

58.75 kg was never a step down. The engine priced **9 reps**.

With a rep range the engine evaluates every rep count in it, rounds each to the weight
increment, and compares the implied e1RM against the baseline. Baseline here is Epley from
60 × 8 = **76.0 kg**, increment 1.25 kg:

| reps | raw | rounded | implied e1RM | vs 76.0 |
|---|---|---|---|---|
| 6 | 63.33 | 63.75 | 76.500 | +0.50 |
| 7 | 61.62 | 61.25 | 75.542 | −0.46 |
| 8 | 60.00 | 60.00 | 76.000 | +0.00 |
| **9** | 58.46 | **58.75** | **76.375** | **+0.375** |
| 10 | 57.00 | 57.50 | 76.667 | +0.67 |

Because this was the first working set and the baseline came from recent performance,
`chooseRepRangeCandidate`
([:829](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:829))
rejected the closest match (8 @ 60.0, dead flat) and switched to `bestProgressedCandidate`
([:894](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:894)), which
returned **9 reps at 58.75 kg**. That is a real progression: 76.375 > 76.0.

**The defect was in the display.** The card printed `targetDisplayLabel`, which is the
user's own target range echoed back. The chosen rep count (`bestReps`) was computed,
resolved into display space, and then surfaced only as `diagnostics.chosenReps` — admin
mode. So the card read *"58.75 kg for 6-10 reps"*, and at 6, 7, or 8 reps that weight
genuinely would be a regression. The lifter's reading was correct given what was on screen.

### What shipped

- `SuggestionTarget.displayLabel(forReps:)`
  ([:98](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:98)) — names
  a single rep count in the same wording as the range label, so unilateral "each side" /
  "total reps" phrasing survives.
- `SetSuggestion.prescribedDisplayLabel`
  ([:121](Repster/Features/Workout/Models/WeightSuggestionData.swift:121)), populated from
  the already-computed `chosenDisplayReps`
  ([:787](Repster/Features/Workout/Models/WeightSuggestionData.swift:787)).
- User strip ([:182](Repster/Features/Workout/Views/Components/WeightSuggestionCardView.swift:182))
  and admin strip ([:220](Repster/Features/Workout/Views/Components/WeightSuggestionCardView.swift:220))
  now render it.

The card now reads **"Set 1 · 58.75 kg for 9 reps"**. Fixed targets are unchanged.

Covered by four tests in `WeightSuggestionDataRowStateTests`, including
`testFirstSetRepRangeProgressionPricesNineRepsNotEight`, which drives the real
`SuggestionEngine.evaluate` and asserts 58.75 / 9 reps /
`.firstSetProgressionAboveRecentPeak` — the reported scenario, locked.

---

## P2 — A fixed rep target can never progress · OPEN

This is the bigger one, and it is what the lifter was actually complaining about.

When reps is a single number rather than a range, evaluation falls to the `else` branch
([:762](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:762)):

```
weight = effectiveE1RM × intensityFactor(targetReps + targetRIR)
```

That intensity factor is the exact algebraic inverse of the formula that derived the e1RM
from 60 × 8 in the first place. It returns **60.0 kg exactly, every session, indefinitely.**

There is no progression term on that path at all. `firstSetProgressionAboveRecentPeak` is
unreachable unless `range.lowerBound < range.upperBound`. The only thing that could nudge a
fixed target is the freshness bonus, and that defaults to `false`
([LoadPrescriptionService.swift:92](Repster/Core/Services/LoadPrescriptionService.swift:92)) —
which is exactly why the fixed-target card said *"Based on your recent performance for this
rep target"* while the range card said *"Nudging up from your last workout's peak."*

At a fixed target the app is a mirror. It hands back your last performance forever and never
asks for more.

### Two secondary weaknesses in the range path

Even when progression does fire, it is minimal by construction. `bestProgressedCandidate`
takes the `.min` delta above baseline — it optimises for *barely clearing an epsilon*. Here
that was +0.375 kg of implied e1RM, about +0.5%. And because it compares e1RM only and never
bar weight, it will drop the load to buy that increase.

Progression is also gated on `isFirstSet`
([:752](Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift:752)). Sets 2+
in a range get pure closest-match, so no progression at all.

---

## The mismatch underneath both

The app has a **prediction** engine — *what can you lift right now* — and the lifter is
asking for a **prescription** — *what should I lift to get better*. The code only answers
the first question.

That also explains why setting 6-10 felt like it should work and didn't. To a lifter a rep
range is a **ladder across sessions**: work 6 → 10, then add weight and drop back to 6. To
the engine it is a **search space to solve for weight in this instant**. Same notation,
opposite meaning — hence an answer that satisfies the model exactly and reads as nonsense on
the gym floor.

---

## Options

### O1 — Show the prescribed rep count · DONE

See P1 above. Cheapest fix, largest share of the confusion.

### O2 — Load floor · DEPRIORITIZED

*Never suggest below a weight completed at equal-or-fewer total reps recently.* Proposed
before P1 was understood.

**Fixing the label undercut the argument for it.** The 58.75 case was never a floor
violation — the engine was progressing correctly and the UI was misreporting it. The
remaining evidence for a floor is the Leg Extension session of 2026-08-17 (32.5 kg suggested
against a demonstrated capacity of ~45 kg), and that is a different failure: within-session,
driven by the RIR chip topping out at "5+" so the engine reads a censored lower bound as a
point estimate. A floor would paper over that rather than fix it.

Design already written up in
[SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md); leave it
parked there.

### O3 — Larger progression step · SUBSUMED BY O4

Replace `.min`-above-baseline with a target increment (~+2% e1RM). Worth doing only if O4 is
rejected — if progression happens in whole reps, there is no fractional-e1RM step size left
to tune.

### O4 — Double progression · PROPOSED

Hold the weight and add **reps** session to session until you hit the top of the range at
target RIR, then add one weight increment and reset to the bottom. Two variables advancing
alternately.

The T-Bar Row case would run:

| session | prescription |
|---|---|
| now | 60 × 8 @ RIR 0 |
| next | 60 × 9 |
| then | 60 × 10 ← top of range cleared |
| then | 61.25 × 6 ← +1 increment, reset |
| then | 61.25 × 7 … |

**Why it fits.** It answers "what do I do next" without requiring the e1RM model to be
right, and it progresses in whole reps the lifter can execute — not 0.375 kg of implied
e1RM. It is also what the lifter already meant when they typed 6-10.

**What changes structurally.** Today the engine re-solves the range from scratch every
session with no memory of position within it. Double progression treats the range as a
position you occupy and advance through — new state: *where in the range were you last time,
and did you clear it.* Mechanically that is a third `SuggestionSelectionPolicy` alongside
`closestMatch` and `firstSetProgressionAboveRecentPeak`, not a new model. The e1RM engine
stays responsible for first exposure to an exercise (no ladder position yet) and for fatigue
on sets 2+.

**Copy gets easier too.** *"You hit 8 @ RIR 0 last time — adding 1.25 kg"* is actionable.
*"Nudging up from your last workout's peak"* is not.

#### Open decisions

- **D1 — Which set governs the ladder?** Top set only, or must every working set clear the
  top of the range? Per-set ladders get incoherent across 4-5 sets; gating on set 1 or the
  top set is the common answer.
- **D2 — What counts as cleared?** `reps >= max && rir <= target`. Needs a fallback for
  blank RIR — and given the censored-"5+" problem, RIR is the least trustworthy input in the
  system.
- **D3 — Failure rule.** Miss the bottom of the range twice running → drop the weight?
  Without this, one bad week strands the lifter at a load they cannot clear.
- **D4 — What if the lifter doesn't follow it?** They log 65 × 5 when the app said
  61.25 × 6. Does the ladder reset to actual performance or hold its plan? Following actual
  performance is more forgiving — but then it collapses into "last session + 1 rep", which is
  simpler and possibly just better.
- **D5 — Interaction with fatigue.** Presumably the ladder sets set 1 and the fatigue-adjusted
  e1RM handles sets 2+. Needs confirming against the within-session bounce in
  [SMART_SUGGESTIONS_BEHAVIOR_AUDIT.md](SMART_SUGGESTIONS_BEHAVIOR_AUDIT.md) §2.
- **D6 — Opt-in or default?** This is a prescription philosophy, not a calculation. Some
  users want the predictor. A setting is honest but is also a way of not deciding.

---

## Recommendation

Start with the **degenerate single-rep case**: fixed target, cleared at target RIR → next
session prescribes one increment more. It fixes the plateau the lifter is actually training
in, needs almost no new state, and the explanation copy writes itself. Then extend the same
rule to ranges and take D1-D6 properly.

---

## Related documents

- [SMART_SUGGESTIONS_BEHAVIOR_AUDIT.md](SMART_SUGGESTIONS_BEHAVIOR_AUDIT.md) — §2 covers the
  sibling problem: rep-range picks bouncing *within* a session. This document covers the
  *cross-session* progression path. A stickiness rule for §2 and a ladder for O4 should be
  designed together.
- [SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md](SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md) — the floor,
  parked per O2.
