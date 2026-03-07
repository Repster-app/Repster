# Weight Prescription Feature — Technical Documentation

## Table of Contents
1. [e1RM Estimation](#e1rm-estimation)
2. [Rest Time Between Sets](#rest-time-between-sets)
3. [Exercise Settings Sheet](#exercise-settings-sheet)

---

## e1RM Estimation

### What is e1RM?
Estimated 1 Rep Max (e1RM) is the theoretical maximum weight a user could lift for a single repetition. It's calculated from actual multi-rep performance using the **Brzycki formula**.

### Brzycki Formula
```
e1RM = weight / (1.0278 − 0.0278 × totalReps)
```
Where `totalReps = actual_reps + RIR` (Reps In Reserve).

**Example:** 80 kg × 9 reps @ RIR 0 → `80 / (1.0278 − 0.0278 × 9) = 80 / 0.7776 = 101.3 kg`

### How e1RM is determined (priority order)

#### 1. In-Session Override (highest priority)
If the user has completed any working sets in the **current session**, the engine computes e1RM from the **best completed set** (highest implied e1RM) and uses it as the base. This overrides historical data entirely.

- **Overperformance:** Target was 6 reps, user did 10 → higher e1RM → next sets get heavier
- **Underperformance:** Target was 8 reps, user only did 5 → lower e1RM → next sets get lighter

This happens automatically when Smart Weights is toggled ON and a set is completed.

**Code location:** `LoadPrescriptionService.prescribeBatch()` — section "3a. In-session override"

#### 2. Historical: Top 1 from Most Recent Workout
If no in-session data exists, the engine looks at the user's workout history within the **recency window** (default: 6 weeks) and finds:
- The **most recent workout** containing this exercise
- The **single heaviest non-warmup set** from that workout
- Computes e1RM using Brzycki

This avoids the old problem where warmup sets (e.g., 40 kg) would drag down the average.

**Code location:** `LoadPrescriptionService.estimateBaseE1RM()`

#### 3. Fallback: PR Table
If no recent sets exist within the recency window, the engine falls back to the `PerformanceRecord` table (all-time PRs) and finds the PR that gives the highest e1RM estimate.

**Code location:** `LoadPrescriptionService.estimateFromPRTable()`

### RIR Handling
- **RIR recorded:** Used directly in Brzycki. E.g., 80 kg × 7 @ RIR 2 → totalReps = 9 → e1RM = 101.3
- **RIR not recorded:** Assumes **RIR 0** (conservative). This means the engine treats the actual reps as the maximum. This gives the lowest possible e1RM, resulting in lighter prescribed weights (safe default).
- Console warning: `⚠️ No RIR (assumed 0, conservative)`

### From e1RM to Prescribed Weight

Once e1RM is determined:

```
1. Apply fatigue discount:    effective_e1RM = base_e1RM × exp(−session_fatigue)
2. Apply intensity factor:    intensity = 1 − 0.025 × target_reps − 0.02 × target_RIR
3. Raw weight:                raw = effective_e1RM × intensity
4. Round to increment:        prescribed = round(raw / increment) × increment
```

**Intensity factor examples:**
| Target Reps | Target RIR | Intensity Factor | Meaning       |
| ----------- | ---------- | ---------------- | ------------- |
| 5           | 0          | 0.875            | 87.5% of e1RM |
| 8           | 2          | 0.760            | 76.0% of e1RM |
| 10          | 3          | 0.690            | 69.0% of e1RM |
| 12          | 2          | 0.660            | 66.0% of e1RM |

### Session Fatigue Model (optional, enabled by default)
Fatigue accumulates across completed sets:
```
set_stress = (reps / 10) × max(0, 1 + (1 − RIR))
session_fatigue += fatigue_rate × set_stress
```
Between sets, fatigue decays based on rest time:
```
session_fatigue *= exp(−rest_seconds / recovery_constant)
```
The fatigue discount `exp(−session_fatigue)` reduces the effective e1RM for later sets.

### Console Logging
When Smart Weights triggers, the Xcode console shows:
```
[Prescription] ── Exercise: Bench Press ──
[Prescription] Historical e1RM from best set: 80.0 kg × 9 reps @ RIR unknown→0 → e1RM = 101.3 kg ⚠️ No RIR (assumed 0, conservative)
[Prescription] Base e1RM: 101.3 kg
[Prescription] Fatigue discount: 1.000
[Prescription] Effective e1RM: 101.3 kg
[Prescription] Set 1: 8 reps @ RIR 2
  intensity_factor = 0.760
  101.3 × 0.760 = 77.0 → rounded to 77.5 kg
```

---

## Rest Time Between Sets

### What it shows
A small label appears **between consecutive completed set rows** in the set table, showing the actual rest duration:
```
Set 1:  80kg × 8 @ RIR 1  ✓
        ⏱ 2:45
Set 2:  77.5kg × 7 @ RIR 1  ✓
        ⏱ 3:10
Set 3:  ___  × ___ @ RIR _  □
```

### How it works
- **Data source:** Uses `WorkoutSet.completedAt` timestamps (already stored when the user taps the completion checkbox)
- **Calculation:** `restDuration = currentSet.completedAt − previousSet.completedAt`
  - If `currentSet.startedAt` is available, uses that instead (more accurate — represents when the user actually started the set vs when they finished it)
- **Display rules:**
  - Only shows between two sets where the previous set has `completedAt`
  - Only shows if rest duration is positive and < 30 minutes (1800 seconds)
  - If timestamps are missing, the label is hidden (no gap shown)
- **Format:** `m:ss` (e.g., "2:45") or `h:mm:ss` for very long rests

### Visual style
- Timer icon (`timer` SF Symbol) at 9pt + duration text at 10pt
- Color: `textTertiary` at 60% opacity
- Height: 20pt, centered horizontally
- Pure display component — no persistence, no tap actions

### Integration with fatigue model
The rest times computed from `completedAt` timestamps are also used by the `LoadPrescriptionService` for fatigue decay calculations. Longer rest = more fatigue recovery = less weight reduction on subsequent sets.

**Code location:** `Reppo/Features/Workout/Views/Components/RestTimeLabelView.swift`

---

## Exercise Settings Sheet

### What it is
A compact sheet for configuring **per-exercise settings** that affect the rest timer and weight prescription. It overrides global defaults for the specific exercise.

### How to access it
- **Active Workout:** Tap the ⚙️ gear icon next to the sub-tab picker ([Sets | History | PRs | Charts] ⚙️)
- The sheet presents at `.medium` detent (half-screen)

### Settings available

#### 1. Default Rest Time
- **What:** How long the rest timer counts down after completing a set of this exercise
- **Options:** Not Set, 30s, 45s, 60s, 90s, 2m, 2m30s, 3m, 3m30s, 4m, 5m
- **Default:** Not Set (falls back to global default from Settings → Workout Preferences)
- **Behavior:** When a set is completed and this exercise has a rest time set, the rest timer automatically starts
- **Stored on:** `Exercise.defaultRestTime: Int?` (seconds, nil = use global)

#### 2. Weight Increment
- **What:** The rounding increment for prescribed weights
- **Options:** 0.5 kg, 1.0 kg, 1.25 kg, 2.0 kg, 2.5 kg, 5.0 kg, 10.0 kg
- **Default:** 2.5 kg (falls back to global default from Settings → Weight Prescription)
- **Behavior:** When Smart Weights prescribes a weight, it rounds to the nearest multiple of this increment. E.g., with 2.5 kg increment: 81.3 kg → 82.5 kg
- **Stored on:** `Exercise.weightIncrement: Double?` (kg, nil = use global)

### How it saves
- Tapping "Save" updates the `Exercise` model directly via `ExerciseService.updateExercise()`
- Changes take effect immediately for the next prescription calculation
- The `originalTrackingType` is passed as the same value (since we're not changing tracking type, just metadata)

### Settings hierarchy
```
Per-Exercise (Exercise.defaultRestTime, Exercise.weightIncrement)
    ↓ falls back to
Global Defaults (HealthProfile.defaultRestTimeSeconds, HealthProfile.prescriptionDefaultIncrement)
    ↓ falls back to  
Hardcoded Defaults (nil → 2.5 kg increment, no rest timer)
```

### Additional exercise-level fields (for future use)
The Exercise model also has:
- `fatigueRate: Double?` — Per-exercise fatigue rate (nil = global default 0.05)
- `recoveryConstant: Double?` — Per-exercise recovery constant (nil = global default 180s)

These are not yet exposed in the UI but can be added to the settings sheet later for power users.

**Code location:** `Reppo/Features/Workout/Views/Components/ExerciseSettingsSheet.swift`
