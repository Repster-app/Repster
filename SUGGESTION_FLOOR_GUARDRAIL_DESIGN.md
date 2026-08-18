# Suggestion Floor Guardrail — Design

**Status:** proposed, not implemented.

Stops Smart Suggestions recommending a weight you have already lifted in this
session with reps to spare. Observed 2026-08-17 on a first session of
"Leg Extension - 1 leg": 20×8 then 35×8, both logged at the top-of-scale RIR chip
`5+`, and the app suggested **32.5 kg** for set 3. Actual capacity that session was
45×10 @ RIR 0 — an e1RM of 60 kg, making ~45 kg the correct call.

## The shape: a floor, not another model change

The engine's arithmetic is not broken. Reproducing it by hand lands on 32.5 exactly,
from a baseline of 44.33 kg and a fatigue discount of 0.957. Three separate defects
feed it — the stored `e1RM` ignores RIR (`SetService.swift:161`), the in-session
capability updater rejects any set at RIR ≥ 3
(`LoadPrescriptionServiceProtocol.swift:986`), and fatigue never decays for the first
pending set (`LoadPrescriptionServiceProtocol.swift:702`) — and fixing all three still
only reaches 37.5 kg. Each is a few percent. None of them makes 32.5 *impossible*;
they make it less likely.

A floor is a different kind of change. It makes a class of answer unreachable no
matter what the model computes, and it composes with all three fixes rather than
competing with them.

It also makes no formula claim. It does not extrapolate, does not pick an e1RM
model, does not trust a fatigue constant. It says only: you lifted this weight,
with reps left over, several minutes ago — so you can lift this weight. That is a
report of something that physically happened, and it is more trustworthy than
anything the model infers from it.

## Decisions

### D1 — The comparison is on total reps, not performed reps

For a completed set, `completedTotal = reps + rir`. For the pending target,
`targetTotal = target.reps + target.rir`. Compare those two.

Comparing performed reps alone gets it wrong in both directions. A set of 35×8 @ RIR 5
demonstrates capacity for 13 reps; a target of "12 reps @ RIR 0" asks for 12, which is
*inside* what was demonstrated, so the floor should still apply even though 12 > 8.

### D2 — The floor activates at a surplus of 3 or more

```
surplus = completedTotal − targetTotal
surplus ≥ 3  → this set contributes a floor
surplus < 3  → it does not
```

Three, and not one, because the surplus has to beat the fatigue the model is entitled
to claim. At an 8-rep target, three reps of reserve is about 8% of load
(`(1+11/30)/(1+8/30) = 1.079`), while accumulated fatigue between two adjacent sets
with normal rest is 2–5%. One rep of reserve is ~2.6% and does not clear that bar.

Three also lands on a useful symmetry. In the common case where the target reps match
what was performed, `surplus` is exactly the completed set's RIR — so the guardrail
activates on precisely the sets `normalizedObservedCapability` currently discards. It
covers the blind spot the RIR gate creates, which is why the two changes are
complementary rather than redundant.

Observed case: `13 − 8 = 5` → floor applies.

### D3 — The floor is the next grid value strictly above the completed weight

```
floor = ceil((completedWeight + ε) / increment) × increment
```

Not `completedWeight`, because a surplus of 3+ means strictly more was possible — the
weight itself is a value we know to be too low. Not an extrapolation of *how much*
more, because that is the model's job and the model is the thing under suspicion here.
One increment above is the smallest statement of "more than this" the app can make.

Expressing it as "next grid value above" rather than "completed weight plus one
increment" also handles an off-grid entry correctly: 33 kg on a 2.5 kg grid floors to
35, not 37.5. Observed case: 35 → **37.5**.

### D4 — Every qualifying completed set contributes; take the maximum

Not just the most recent one. A 40×8 @ RIR 3 earlier in the session bounds the answer
even when the last set was a lighter 35×8 @ RIR 5. Compute a floor per qualifying set
and take the max.

### D5 — Only clean single-effort set types qualify

`.working` and `.backoff` in v1.

Excluded: `.partial` (partial-ROM reps are not comparable to a full-ROM target),
`.dropset` / `.myo` / `.restpause` (reps are not one continuous effort, and the RIR
recorded at the end does not describe the opening weight), `.amrap` / `.failure` (RIR
is definitionally 0, so surplus never clears D2 anyway — excluded for clarity).
`.warmup` never reaches here; `SuggestionCoordinator.completedSessionSets` filters it
out upstream (`WeightSuggestionData.swift:311`).

`.tempo`, `.eccentric`, `.cluster` and `.isometric` would be *safe* floors — a harder
variant at RIR 5 implies the plain version is easier still — but their reps are not
comparable to a normal working target, so they stay out until someone asks.

### D6 — A missing RIR contributes no floor

`SessionSetContext.rir` is optional. The fatigue path substitutes
`missingRIRDefault = 1.0` when it is absent; that constant must not be reused here.
Assuming a reserve nobody reported would let the guardrail invent a floor out of
nothing. No RIR, no floor.

### D7 — The clamp is visible in the explanation, never silent

A clamped suggestion currently still renders "Easing off slightly to manage session
fatigue" (`WeightSuggestionData.swift:848`), which after clamping *upward* is simply
false. Add a `floorApplied` flag to `SuggestionDecision` — or a
`SuggestionSelectionPolicy` case alongside `.firstSetProgressionAboveRecentPeak` — and
give `contextualUserSummary` a branch that outranks the fatigue branch. Copy in the
register of the existing lines: *"Holding above your last set — you had reps left at
35 kg."*

`SetSuggestionDiagnostics` should carry the floor value and the set that produced it,
next to the existing `selectionPolicy` / `selectionReferenceE1RM` pair.

### D8 — No cap on how far the floor may raise the answer

Considered bounding the clamp to some percentage above the model's output. Rejected: a
large gap between the floor and the model *is* the signal that the model is wrong, and
the floor is the better-evidenced of the two. Capping it would reintroduce the same
failure in a quieter form.

### D9 — Applies to every pending set, not only the next one

The argument holds identically for sets 4 and 5: reserve was demonstrated, and the
lower numbers further down the forward projection are the model's claim, not an
observation. This does flatten the projection's decline, which is intended.

## Where it goes

`SuggestionEngine.evaluate`, after `prescribedWeight` is computed and before the
`SuggestionDecision` is constructed — `LoadPrescriptionServiceProtocol.swift:753–787`.
It is a pure function of `input.completedSessionSets`, the pending target, and the
increment, so it stays inside the engine, needs no repository access, and is directly
unit-testable with no SwiftData fixture.

Both sides of the comparison are already in `effectiveWeight` space:
`SessionSetContext.weight` is `effectiveWeight ?? weight`
(`WeightSuggestionData.swift:314`), and `prescribedWeight` descends from an e1RM
computed on `effectiveWeight` (`SetService.swift:161`). The guardrail is therefore
correct for bodyweight-factor exercises without conversion — though what those
exercises should *display* as a suggested load is a separate question worth its own
look.

## Limits

**It reaches one increment above your best demonstrated set, and stops.** In the
observed session that is 37.5 against a true 45. The floor stops the answer being
absurd; it does not find your capacity. Recovering the rest needs the two follow-ups:
reading a top-of-scale `5+` as a lower bound rather than as exactly 5, and a probe
mode that steps up 15–25% per set while the baseline is a single session of
top-of-scale RIR.

**It cannot fire on set 1.** No completed sets, no floor. The first suggestion on a new
exercise stays entirely at the model's mercy — which is where the largest errors are.

**Late-session sets are the overreach risk.** By set 8 the model may legitimately
project 25% fatigue and suggest well below a floor set early in the session. D9 keeps
the floor anyway. This is deliberate for v1: the observed failure is on early sets, and
relaxing the floor as projected fatigue grows adds a tuning constant to a change whose
whole value is that it has none. Revisit if a late-set complaint appears.

**It trusts self-reported RIR in one direction.** Someone who habitually overstates
reserve gets floors that are too high. The error is bounded to one increment above a
weight they genuinely completed — a hard set, not an unattainable one.

**Unilateral targets must use the normalized reps.** `prReps` is `max(L, R)` and
`performanceRIR` is the harder side's (`WorkoutSet.swift:125–156`), both per-side. A
`.totalAcrossSides` target is halved by `normalizedTargetReps`, so the floor must read
`target.reps`, never `target.displayReps`.

## Test cases

1. **Regression.** 20×8 @ RIR 5, 35×8 @ RIR 5, target 8 @ RIR 0, increment 2.5,
   baseline 44.33 → suggestion ≥ 37.5. Currently 32.5.
2. **No surplus.** Last set 35×8 @ RIR 0, target 8 @ RIR 0 → no floor; the model may
   legitimately go lighter.
3. **Below threshold.** 35×8 @ RIR 2, target 8 @ RIR 0 → surplus 2 → no floor.
4. **At threshold.** 35×8 @ RIR 3, target 8 @ RIR 0 → surplus 3 → floor 37.5.
5. **Target harder than demonstrated.** 35×8 @ RIR 5 (13 total), target 15 @ RIR 0
   → surplus −2 → no floor.
6. **Max across sets.** 40×8 @ RIR 3 then 35×8 @ RIR 5, target 8 @ RIR 0 → floors
   42.5 and 37.5 → 42.5 wins.
7. **Reps differ from target.** 35×10 @ RIR 5 (15 total), target 8 @ RIR 0 → surplus 7
   → floor 37.5.
8. **Missing RIR.** 35×8, RIR nil → no floor (D6).
9. **Off-grid weight.** 33 kg completed, increment 2.5 → floor 35, not 37.5.
10. **Excluded types.** Same numbers logged as `.dropset` and as `.partial` → no floor.
11. **Warmup.** 60×8 @ RIR 5 as `.warmup` → no floor; never reaches the engine.
12. **Unilateral, totalAcrossSides.** Target displayed as 16 total reps normalizes to 8
    per side; the floor must compute against 8.
13. **Explanation.** When the floor fires, `userSummary` is the floor line, not the
    fatigue line (D7).
