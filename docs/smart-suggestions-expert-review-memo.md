# Smart Suggestions Expert Review Memo

## Purpose

This memo is intended for expert review of one specific part of the Smart Suggestions feature: how it chooses a recommended weight when a set has a rep range and a target RIR.

The goal of this memo is not to defend the current implementation or argue from existing documentation. The goal is to surface the actual product/coaching question clearly enough that an expert can evaluate whether the feature is helping users progress toward their fitness goals.

## What Smart Suggestions Is

Smart Suggestions is an in-workout load recommendation feature for weight-based exercises. It appears on the active workout screen and proposes a weight for upcoming sets.

At a high level, the feature does the following:

1. Estimates the user's current exercise capacity from recent performance history.
2. Adjusts that capacity for current-session readiness and fatigue context.
3. Uses the set's target reps, target rep range, target RIR, and available weight increment to propose a rounded load for the next set.
4. Shows diagnostics and nearby alternatives so the user can understand why a given load was suggested.

In practical terms, the feature is trying to answer:

"Given what we know about this user's current capacity, what load should they use for the next set?"

## Current Behavior in Rep-Range Suggestions

The part under review is the logic used when a set has a rep range, for example `6-8 @ RIR 0`.

Current implementation references:

- `Reppo/Core/Services/LoadPrescriptionService.swift`
- `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift`
- `Reppo/Features/Workout/Views/Components/WeightSuggestionCardView.swift`

### Current selection logic

For each rep candidate inside the target range, the system currently:

1. Computes the target total reps as `candidate reps + target RIR`.
2. Reverse-calculates a raw weight from the current effective e1RM and the selected formula.
3. Rounds that raw weight to the configured increment.
4. Recomputes the implied e1RM from the rounded weight.
5. Chooses the rep-and-weight pair whose rounded outcome is closest to the effective e1RM.

This means the system is currently optimizing for:

`the rounded option that most closely preserves the target e1RM`

It is not necessarily optimizing for:

`the heaviest load likely to fail within the rep range`

That distinction is the core issue for expert review.

## Anchor Example

The current example under discussion is:

- Exercise: Incline Smith Barbell Press
- Capacity baseline: `66.5 kg`
- Effective e1RM: `66.5 kg`
- Readiness: `+0.0%`
- Fatigue discount: `1.000`
- Freshness bonus: off
- Target: `6-8 @ RIR 0`
- Weight increment: `1.25 kg`
- Current recommendation: `52.5 kg x 8`

### Alternatives shown by the feature

| Candidate | Raw Weight | Rounded Weight | Implied e1RM | Distance from 66.5 kg |
|----------|------------|----------------|--------------|------------------------|
| 6 reps | 55.42 kg | 55.00 kg | 66.00 kg | -0.5 kg (-0.8%) |
| 7 reps | 53.92 kg | 53.75 kg | 66.29 kg | -0.2 kg (-0.3%) |
| 8 reps | 52.50 kg | 52.50 kg | 66.50 kg | 0.0 kg (0.0%) |

Under the current logic, `52.5 x 8` is chosen because it is the exact rounded e1RM match.

### What the example shows

This example is useful because the recommendation is mathematically coherent, but it raises a coaching question:

- Is the best recommendation the one that exactly matches the current e1RM after rounding?
- Or should the feature prefer the heaviest load that is still expected to land inside the requested rep range?

In this example, those are not the same answer.

## Two Coaching Philosophies in Tension

### Philosophy A: Exact rounded e1RM match

Under this philosophy, the recommendation should preserve the intended training demand as precisely as possible after rounding. The current system is closest to this model.

Potential advantages:

- Clean mathematical consistency
- Predictable behavior across increments
- Usually strong alignment with the displayed diagnostics
- Tends to keep users inside the prescribed range with high confidence

Potential concerns:

- May bias recommendations toward lighter loads if those loads produce a more exact rounded fit
- May favor the top of the range rather than the heaviest in-range option
- May progress more slowly than a coach would want for users explicitly trying to get stronger

### Philosophy B: Heaviest load likely to fail within the prescribed rep range

Under this philosophy, the recommendation should bias toward the heaviest load expected to still land in-range for the requested RIR target.

Potential advantages:

- Better matches the intuition of "progressive overload"
- More consistent with a coaching mindset that uses rep ranges as performance brackets
- Better aligned with the idea that a user trying to get stronger should not default to the easiest successful option

Potential concerns:

- More aggressive recommendations may increase misses
- The system may need a clearer definition of what "likely to land in-range" means
- Rep-range suggestions may become meaningfully different from exact e1RM targeting

## Why This Matters as a Product Question

This is not primarily a question about formula correctness.

The current calculation is mathematically defensible. The question is whether the feature is optimizing the right outcome for the user.

Said differently:

- The current feature can be correct mathematically and still be misaligned behaviorally.
- The right product choice depends on what outcome Smart Suggestions is supposed to optimize for by default.

This memo intentionally treats that as a product and coaching decision, not as a documentation compliance exercise.

## Progression Interpretation Questions

The example also exposes an important progression question: what should count as evidence that a load is now too light?

### Case 1: `52.5 x 8 @ RIR 0`

This is top-of-range performance at true failure.

Possible interpretations:

- The load is still correct, because the user failed within the prescribed `6-8` range.
- The load is becoming too easy if this outcome repeats often, because the user is stuck at the same top-end result.

### Case 2: `52.5 x 8 @ RIR 1`

This suggests the user hit the top of the range but still had another rep available.

Possible interpretation:

- The load is now too light for a target of `6-8 @ RIR 0`, so the next prescription should increase.

### Case 3: `52.5 x 9 @ RIR 0`

This is clear performance above the prescribed range.

Possible interpretation:

- The load is too light and should increase next session.

### Key coaching question

Should `8 @ RIR 1` and `9 @ RIR 0` be treated as equivalent progression signals?

Conceptually, both imply that the user had roughly one more rep than the `8 @ RIR 0` target condition. An expert may agree that they should be treated similarly, or may argue that actual extra reps should carry more weight than subjective RIR.

## Applicability Across Goals

One important product question is whether this issue is strength-specific or whether it generalizes across hypertrophy-focused prescriptions as well.

A plausible argument for generalization is:

- Strength and hypertrophy prescriptions both use rep ranges and target effort.
- In both cases, the user still wants enough load to make the prescription meaningful.
- The training goal is expressed by the rep range and target RIR, while the suggestion engine should then choose an appropriate load inside that prescription.

Under that view:

- Strength work may use lower rep ranges and lower RIR.
- Hypertrophy work may use higher rep ranges and higher target RIR.
- But both still benefit from a load suggestion that supports progression.

An expert may still disagree and argue that hypertrophy work should favor "very likely successful in-range" recommendations more strongly than lower-rep strength work.

## What We Want Evaluated

We are looking for expert judgment on the intended coaching behavior of Smart Suggestions, especially for rep-range prescriptions.

Specific questions for review:

1. For a prescription like `6-8 @ RIR 0`, should the feature prefer the exact rounded e1RM match, or the heaviest load likely to fail inside the range?
2. Is `52.5 x 8` the right recommendation in the anchor example, or is a heavier in-range option more appropriate from a coaching perspective?
3. If a user repeats `8 @ RIR 0` at the same load across multiple sessions, should that be treated as acceptable double progression or as undesirable stagnation?
4. Should `8 @ RIR 1` and `9 @ RIR 0` both trigger a load increase next session?
5. Should the same rep-range philosophy apply across both strength-oriented and hypertrophy-oriented weight-and-reps prescriptions?
6. Is one universal coaching rule appropriate for all weight-and-reps work, or should rep-range selection behavior vary by training context?

## Boundaries for This Review

This memo is intentionally limited in scope:

- It does not recommend code or model changes.
- It does not propose new settings, schemas, or user-facing controls.
- It does not assume the current documentation is the correct product goal.
- It focuses on the behavioral intent of the recommendation engine, not on implementation details unrelated to the coaching question.

## Short Summary

The Smart Suggestions feature currently appears to optimize for the rounded option that best preserves the target e1RM. That is mathematically coherent.

The open question is whether that is the right coaching behavior for users trying to make progress, especially when the prescription is a failure-based rep range such as `6-8 @ RIR 0`.

The core issue for expert review is whether Smart Suggestions should prioritize:

- exact rounded e1RM matching

or

- the heaviest load likely to still satisfy the prescribed rep range and effort target
