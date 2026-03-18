# Adaptive Fatigue Learning — Design Document

This document describes a future enhancement to the fatigue model that personalizes
recovery and fatigue rates per user (and per exercise) based on actual training data.

The fixed model (shipped first) uses research-calibrated constants. This layer
learns from the gap between predicted and actual performance to refine those constants
over time.

---

## 1. What We're Learning

Two parameters that vary between individuals:

### Recovery speed (personal τ)
- Fixed default: τ = 300s
- Some people recover faster (τ = 200-250s) — e.g., well-conditioned athletes
- Some recover slower (τ = 350-400s) — e.g., beginners, older trainees, poor sleep

### Fatigue sensitivity (personal base fatigue %)
- Fixed default: 3% base per set
- Some people accumulate less fatigue per set (2%)
- Some accumulate more (4-5%)

Both can also vary **per exercise** (squats are more fatiguing than curls).

---

## 2. Signal: Predicted vs Actual Performance

After each completed set (beyond set 1), we have a natural experiment:

```
Prediction: "Use 95 kg for 8 reps @ RIR 2" (accounting for X% fatigue)
Actual:     User did 95 kg × 8 reps @ RIR 0
```

The model predicted this would feel like RIR 2, but the user found it to be RIR 0.
The model was too optimistic — it underestimated fatigue.

### Computing the error

For each completed set after set 1:

```
predicted_effective_e1RM = base_e1RM × (1 - predicted_fatigue)
actual_e1RM = formula.calculate(weight: actual_weight, reps: actual_reps + actual_RIR)
error = predicted_effective_e1RM - actual_e1RM
```

- **error > 0**: Model overestimated capacity → user fatigues more than predicted
- **error < 0**: Model underestimated capacity → user recovers better than predicted
- **error ≈ 0**: Model is well-calibrated

### Handling user weight changes

If the user changed the weight from the suggestion (e.g., used 90 kg instead of 95 kg),
we can still compute their actual e1RM from the set data and compare to the predicted
effective e1RM. The comparison works regardless of whether they followed the suggestion.

---

## 3. Learning Algorithm

### Per-session update

After each session, compute the average prediction error across all sets (excluding set 1):

```
session_errors = [error for each set 2, 3, 4, ...]
avg_error = mean(session_errors)
```

### Adjusting τ (recovery speed)

```
// Positive error = model too optimistic = recovery too fast = increase τ
// Negative error = model too pessimistic = recovery too slow = decrease τ
τ_adjustment = learning_rate × avg_error / base_e1RM  // normalize by strength
exercise.personalRecoveryConstant += τ_adjustment
```

Constraints:
- τ bounded to [150, 600] (half a minute to 10 minutes)
- Learning rate: small (e.g., 5-10 seconds per session) to avoid oscillation
- Only adjust after minimum 3 sessions with the exercise

### Adjusting base fatigue %

Similar approach but adjusting the per-set contribution:

```
// If sets consistently feel harder/easier than predicted
fatigue_adjustment = learning_rate × avg_error / base_e1RM
exercise.personalBaseFatigue += fatigue_adjustment
```

Constraints:
- Base fatigue bounded to [0.01, 0.08] (1-8% per set)
- Very slow learning rate (changes by ~0.002 per session)

---

## 4. Data Requirements

### Minimum data before adjusting
- At least **5 sessions** for an exercise before any personalization
- Each session must have at least **3 completed sets** with RIR logged
- Ignore sessions where user skipped RIR logging (can't compute actual e1RM accurately)

### Quality filters
- Ignore sets where weight was dramatically different from suggestion (>20% off)
  — user likely changed exercise intention
- Ignore warmup and partial sets
- Ignore sessions with very irregular rest patterns (e.g., long phone breaks)

### Confidence / convergence
- Track running variance of errors
- If variance is high, learning rate should be lower (noisy signal)
- If variance is low and errors are consistently in one direction, learning rate can be higher
- After ~20 sessions, the personal parameters should be fairly stable

---

## 5. Storage

### Per-exercise personalization
```swift
// On Exercise model (new optional properties):
var personalRecoveryConstant: Double?  // nil = use global default (300s)
var personalBaseFatigue: Double?       // nil = use global default (0.03)
var fatigueLearningSessionCount: Int?  // number of sessions used for learning
```

### Global user personalization
```swift
// On HealthProfile (new optional properties):
var personalRecoveryConstant: Double?  // user-level default override
var personalBaseFatigue: Double?       // user-level default override
```

Resolution order: exercise-specific > user-level > fixed default

---

## 6. UI Considerations

- No UI needed initially — learning happens silently in the background
- Optional future: show a "model confidence" indicator on the suggestion card
  (e.g., "high confidence" after 20+ sessions, "learning" for < 5 sessions)
- Optional: settings toggle to enable/disable adaptive learning
- Optional: "reset learning" button per exercise if user wants to start fresh

---

## 7. Implementation Order

1. **Phase 1** (current): Ship fixed model with research-calibrated constants
2. **Phase 2**: Add error tracking — compute and store prediction errors per session
   (no adjustments yet, just data collection)
3. **Phase 3**: Implement τ learning with conservative bounds
4. **Phase 4**: Add base fatigue learning
5. **Phase 5**: Add confidence indicators to UI

Each phase can be shipped independently.

---

## 8. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Overfitting to noisy data | Slow learning rate, minimum session count, bounded parameters |
| Bad day skewing results | Use median instead of mean for session errors |
| User changes training style | Recency weighting on errors (recent sessions weighted more) |
| Oscillation (bouncing between too high/too low) | Momentum term or exponential moving average |
| User never logs RIR | Can't learn from those sessions; fall back to fixed model |

---

# End of Document
