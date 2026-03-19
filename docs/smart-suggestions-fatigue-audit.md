# Smart Suggestions Fatigue Audit

This document is derived from the current code in:

- `Reppo/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift`
- `Reppo/Core/Services/LoadPrescriptionService.swift`

It describes what the fatigue/readiness model does today. It is not a product proposal.

## Current Inputs

- Fatigue uses completed non-warmup sets from the current exercise only.
- Rest input comes from configured rest only:
  - `exercise.defaultRestTime`
  - fallback `profile.defaultRestTimeSeconds`
- Measured timestamps such as `completedAt` are not used for rest decay.
- If fatigue modeling is disabled, session fatigue is `0.0`.

## Current Model

If fatigue modeling is enabled:

1. Start with `sessionFatigue = 0.0`.
2. Iterate completed sets in order.
3. Before each set after the first, decay accumulated fatigue by:

   `sessionFatigue *= exp(-configuredRestSeconds / 300)`

4. For each completed set, compute set fatigue:

   - base fatigue = `0.03`
   - RIR bonus = `max(0, 2 - rir) * 0.02`
   - reps scale = `min(reps / 8, 1.5)`
   - set fatigue = `(base fatigue + RIR bonus) * reps scale`

5. Add set fatigue to `sessionFatigue`.
6. Cap session fatigue at `0.20`.

Then, for every pending set:

1. Compute fatigue discount:

   `fatigueDiscount = clamp((1 - sessionFatigue) + calibrationOffset, 0...1)`

2. Compute raw readiness e1RM:

   `readinessRaw = baseE1RM * readinessMultiplier * fatigueDiscount`

3. If no sets are completed yet and this is the first pending set, optionally apply freshness:

   `readinessRaw *= (1 + freshnessPercent)`

4. Clamp final effective e1RM to:

   `95% ... 105%` of `baseE1RM`

## Important Consequences

- One `sessionFatigue` value is computed from completed sets and applied to every pending row.
- Later pending rows do not get progressively more fatigued than earlier pending rows.
- Missing RIR on completed sets defaults to `2.0` in the fatigue calculation.
- Configured rest changes fatigue decay; actual elapsed rest does not.
- Freshness only applies when there are zero completed sets.

## Questions For The Next Model Pass

- Should pending sets accumulate additional projected fatigue across the suggestion list?
- Should the per-set fatigue coefficients be lower, higher, or exercise-sensitive?
- Should hard set types like dropsets or AMRAPs contribute differently from ordinary working sets?
- Should missing completed-set RIR still default to `2.0`, or should that be neutralized differently?
- Should the `95% ... 105%` readiness clamp stay this tight?
