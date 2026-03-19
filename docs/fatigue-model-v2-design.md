# Fatigue Model v2 — Design & Implementation Plan

## Context

The current intra-session fatigue model (v1) in `SuggestionEngine` has several known limitations documented in `docs/smart-suggestions-fatigue-audit.md`. The most impactful: all pending sets receive the same flat fatigue discount, configured rest is used instead of actual elapsed time, the ±5% readiness clamp masks the model's output, and set types (AMRAP, dropset, failure) all contribute identical fatigue. The Exercise model already defines `fatigueRate` and `recoveryConstant` fields with v2-intended defaults (0.05, 180) but the engine ignores them.

This plan redesigns the fatigue model grounded in exercise physiology while keeping it practical for a consumer app running on-device.

**Scalability path**: v2 improves the single-accumulator model with better inputs. This is intentional — it's explainable in the diagnostics UI, debuggable when suggestions feel off, and per-exercise fields (`fatigueRate`, `recoveryConstant`) give tuning knobs without engine changes. A dual-component model (peripheral vs central fatigue) is the v3 path once outcome data from v2 provides calibration signal.

---

## Physiological Rationale

**Phosphocreatine recovery** follows mono-exponential kinetics (half-life ~20-35s). At 3 min rest, ~80-95% PCr is replenished. The v1 recovery constant of 300s is too slow — fatigue barely decays between typical 2-3 min rests.

**Peripheral neuromuscular fatigue** (metabolite accumulation: H+, Pi, ADP) has a recovery half-life of 2-4 min depending on intensity and muscle group. A recovery constant of ~180s produces ~63% recovery at 3 min rest, matching empirical rep drop-off data.

**Effort-fatigue relationship**: Sets at RIR 3+ produce similar fatigue; below RIR 2 fatigue increases sharply. The v1 formula only activates below RIR 2 and adds a negligible +0.04 — it needs a wider activation range and stronger scaling.

**Set type demands**: AMRAPs/failure sets generate substantially more peripheral fatigue than controlled working sets. Drop sets involve repeated near-failure bouts with minimal rest. Partial ROM limits metabolic demand. These differences are well-established and should be reflected.

---

## Changes Summary

### 1. Progressive fatigue for pending sets
**Current**: Single `sessionFatigue` from completed sets applied identically to all pending rows.
**Proposed**: Iterate pending sets in order, projecting each set's estimated fatigue contribution (from target reps/RIR/type) before computing the next set's suggestion. Use configured rest for decay between projected sets.

### 2. Rest timer–aware fatigue decay
**Current**: Only `configuredRestSeconds` (exercise or global default) used for decay.
**Proposed**: Use the rest timer's actual total duration — including any manual adjustments the user makes via +30s/-30s/edit buttons — as the decay input. The rest timer already tracks `timerTotalDuration` in memory; we capture this value when the timer completes or is dismissed, and store it per-set so the fatigue engine can use it.

**Important**: We do NOT use `completedAt` timestamps for rest calculation. Users may delay tapping "done" (checking phone, logging notes), so timestamp deltas would overestimate rest. The rest timer is the source of truth — it's what the user explicitly set and watched.

**Implementation**: When a rest timer completes (runs to zero), store `timerTotalDuration` on the completed set (new field on `WorkoutSet`: `restDurationSeconds: Int?`). If the user dismisses the timer early, do NOT capture — fall back to configured rest (the user opted out of timer-based tracking for that rest). The fatigue engine uses `set.restDurationSeconds ?? configuredRestSeconds` for decay. For the first completed set (no prior rest), decay is skipped as before.

**Forward projection**: Projected rest between pending sets always uses configured rest (exercise or global default), not the most recent timer value. Timer adjustments are one-time decisions, not predictions of future behavior.

### 3. Widen readiness clamp
**Current**: ±5% (0.95–1.05).
**Proposed**: 0.88–1.05 (up to 12% reduction). Across 5 hard working sets of squats with 2-min rest, 10-15% performance decline is well-documented. The 5% floor was negating most of the fatigue model's output.

### 4. Set-type fatigue multipliers
**Current**: All non-warmup types contribute identically.
**Proposed**: Hardcoded multipliers on the per-set fatigue contribution:

| SetType | Multiplier | Rationale |
|---------|-----------|-----------|
| working | 1.0 | Reference |
| tempo | 1.1 | Extended TUT |
| backoff | 0.7 | Lighter load, higher RIR |
| cluster | 0.8 | Intra-set rest reduces metabolite buildup |
| restpause | 1.3 | Near-failure repeated bouts, minimal rest |
| myo | 1.3 | Similar to rest-pause |
| dropset | 1.4 | Multiple near-failure efforts without recovery |
| amrap | 1.5 | Maximum peripheral fatigue |
| failure | 1.5 | True muscular failure |
| partial | 0.5 | Reduced ROM, limited metabolic demand |
| isometric | 0.9 | High force, no eccentric damage |
| eccentric | 1.2 | High force, structural stress |
| warmup | 0.0 | Excluded (unchanged) |

### 5. Revised effort scale
**Current**: `rirBonus = max(0, 2 - rir) * 0.02` — only activates below RIR 2, max +0.04.
**Proposed**: `effortScale = 1.0 + max(0, 3.0 - effectiveRIR) * 0.15`
- RIR 3+: 1.0x, RIR 2: 1.15x, RIR 1: 1.30x, RIR 0: 1.45x

### 6. Updated constants
| Constant | v1 | v2 | Why |
|----------|----|----|-----|
| Default recovery constant | 300 | 180 | Matches peripheral fatigue half-life (2-4 min) |
| Default base fatigue rate | 0.03 | 0.04 | More signal with wider clamp |
| Max fatigue cap | 0.20 | 0.25 | Headroom for wider clamp |
| Missing RIR default | 2.0 | 1.0 | Conservative: unknown effort biases lighter |
| Readiness min | 0.95 | 0.88 | Let the model express itself |
| Rep scale floor | 0.0 | 0.6 | Ensures heavy singles/doubles contribute meaningful fatigue (research: 1RM is ~60-80% as fatiguing as a set of 8 for subsequent performance) |
| Rep scale formula | `min(reps/8, 1.5)` | `max(0.6, min(reps/8, 1.5))` | Floor prevents near-zero fatigue on low-rep heavy work |

### 7. Wire per-exercise fields
`exercise.fatigueRate` and `exercise.recoveryConstant` flow through `SuggestionSettingsSnapshot` into the engine. The Exercise model already documents defaults of 0.05 / 180 that align with v2. No manual UI for these fields in v2 — they're designed as auto-calibration targets for a future feedback loop (v3: compare suggested vs realized weights to auto-tune per-exercise fatigue characteristics).

---

## Per-set fatigue formula (v2)

```
setFatigue = baseFatigueRate * typeMultiplier * effortScale * repScale
```

Where:
- `baseFatigueRate` = `exercise.fatigueRate ?? 0.04`
- `typeMultiplier` = from table above
- `effortScale` = `1.0 + max(0, 3.0 - effectiveRIR) * 0.15`
- `repScale` = `max(0.6, min(reps / 8.0, 1.5))` — floor of 0.6 added (see below)

---

## Worked example

Barbell squat, baseE1RM = 140kg, 5×8 @ RIR 2, 150s rest, recovery τ = 210s (squat).
Per-set fatigue: `0.04 * 1.0 * 1.15 * 1.0 = 0.046`. Decay per rest: `exp(-150/210) = 0.489`.

| Set | After Decay | After Adding | Eff. e1RM | %base |
|-----|------------|-------------|-----------|-------|
| 1 (done) | 0 | 0.046 | — | — |
| 2 (done) | 0.023 | 0.069 | — | — |
| 3 (pending) | 0.034 | 0.080 | 135.3 | 96.6% |
| 4 (pending) | 0.039 | 0.085 | 134.5 | 96.1% |
| 5 (pending) | 0.042 | 0.088 | 134.2 | 95.8% |

v1 would show 95.0% (clamped) for all three pending sets.

---

## Data model changes

**`WorkoutSet`** — add `restDurationSeconds: Int?` (captured from rest timer's `timerTotalDuration` when timer completes/is dismissed)
**`SessionSetContext`** — add `setType: SetType`, `restDurationSeconds: Int?`
**`SuggestionPendingSetInput`** — add `setType: SetType`
**`SuggestionSettingsSnapshot`** — add `baseFatigueRate: Double`, `recoveryConstant: Double`
**`SuggestionDecision`** — add `projectedSessionFatigue: Double` (diagnostics)
**`SetSuggestionDiagnostics`** — add `projectedSessionFatigue`, `setTypeFatigueMultiplier`, `restSecondsUsed`, `restSource` ("timer"/"configured")

---

## Files to modify

1. **`Reppo/Data/Models/WorkoutSet.swift`** — add `restDurationSeconds: Int?` field
2. **`Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift`** — capture `timerTotalDuration` onto completed set when rest timer finishes/is dismissed
3. **`Reppo/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift`** — `SuggestionEngine`, `SessionSetContext`, `SuggestionPendingSetInput`, `SuggestionSettingsSnapshot`, `SuggestionDecision`
4. **`Reppo/Core/Services/LoadPrescriptionService.swift`** — wire `fatigueRate` and `recoveryConstant` from exercise/profile into settings snapshot
5. **`Reppo/Features/Workout/Models/WeightSuggestionData.swift`** — `SuggestionCoordinator` (thread `setType` and `restDurationSeconds` through), `SuggestionExplainer` (new diagnostics), `SetSuggestionDiagnostics`
6. **`Reppo/Features/Workout/Views/Components/WeightSuggestionCardView.swift`** — show rest source, type multiplier, per-set fatigue in expanded diagnostics
7. **`ReppoTests/ActiveWorkoutViewModelSuggestionRefreshTests.swift`** — update existing tests, add v2-specific tests

---

## Implementation phases

### Phase 1: Engine constants & simple fixes (no structural changes)
- Update recovery constant 300→180, base fatigue 0.03→0.04, max fatigue 0.20→0.25
- Widen readiness clamp 0.95→0.88
- Change missing RIR default 2.0→1.0
- Update effort scale formula

### Phase 2: Data model threading
- Add `setType` to `SessionSetContext` and `SuggestionPendingSetInput`
- Add `baseFatigueRate` and `recoveryConstant` to `SuggestionSettingsSnapshot`
- Wire exercise/profile values in `LoadPrescriptionService`
- Update `SuggestionCoordinator` to pass set type through

### Phase 3: Set-type multipliers & rest timer integration
- Add `setTypeMultiplier()` function
- Update `computeSessionFatigue` to use type multipliers
- Use `restDurationSeconds` (from rest timer) for decay, fall back to configured rest
- Add `restDurationSeconds: Int?` to `WorkoutSet`
- Capture `timerTotalDuration` onto the most recently completed set when rest timer runs to zero (NOT on early dismissal) in `ActiveWorkoutViewModel`

### Phase 4: Forward projection
- Restructure `evaluate()` to iterate pending sets with progressive fatigue
- Add `estimatePendingSetFatigue()` for projecting from target values
- Add `projectedSessionFatigue` to `SuggestionDecision`

### Phase 5: Diagnostics & UI
- Update `SetSuggestionDiagnostics` with new fields
- Update `WeightSuggestionCardView` expanded details
- Show rest source, type multiplier, per-set projected fatigue

### Phase 6: Tests
- Unit tests for each new formula component
- Forward projection tests (set N+1 fatigue > set N)
- Rest timer duration fallback tests (timer value, configured fallback)
- Regression tests with v1 constants

---

## Verification

1. Build the project (`xcodebuild`)
2. Run existing `ActiveWorkoutViewModelSuggestionRefreshTests` — must pass
3. Run new v2 unit tests
4. Manual test: start a workout with 5+ working sets of a compound lift, verify suggestions decrease progressively across pending sets
5. Manual test: complete a set, adjust the rest timer (+30s), let it finish, verify diagnostics show the adjusted timer duration as "timer" rest source
6. Manual test: add an AMRAP set mid-workout, verify subsequent suggestions drop more than for working sets

---

## Risks & edge cases

- **Supersets**: fatigue is per-exercise only; cross-exercise central fatigue is not modeled. Acceptable for v2; future work could apply a rest reduction when `supersetGroupId` is set.
- **Dismissed/skipped rest timer**: `restDurationSeconds` stays nil, falls back to configured rest. Conservative path.
- **Mid-workout rest time change**: If user changes exercise rest from 120s to 180s mid-workout, use the updated value for all decay calculations (completed sets without a captured timer value use the current configured rest).
- **User adds extreme time** (+30s repeatedly): Captured duration could be large. Physiologically correct — long rest = more recovery = less fatigue.
- **v3 auto-calibration opportunity**: Per-exercise `fatigueRate` and `recoveryConstant` are wired but use defaults. Future work: compare suggested vs realized weights to auto-tune these per exercise (e.g., if user consistently lifts 5% heavier than suggested on bench press, lower its fatigue rate).
- **Backward compatibility**: v1 behavior recoverable with original constants + disabling forward projection. Consider internal `fatigueModelVersion` flag for A/B testing during rollout.
