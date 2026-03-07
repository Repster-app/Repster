# Feature Plan: Unilateral Exercise Support (L/R Tracking)

## Why

Many exercises are performed one side at a time (dumbbell curls, lunges, single-leg press). Currently all sets record a single reps/RIR value. Users can't track whether their left side is weaker than the right, which is important for:

- Detecting and correcting **strength imbalances**
- Programming **rehab or prehab** work
- Seeing per-side **progress over time**

## Goal

When an exercise is marked as unilateral, each set shows **separate L and R inputs** for reps and RIR. Weight stays shared (same dumbbell), but reps and effort can differ per side. History and charts should surface any imbalance.

---

## What Already Exists

The codebase has **partial infrastructure** that was never wired up:

| What | Where | Status |
|---|---|---|
| `Exercise.unilateral: Bool` | `Exercise.swift` line 13 | Exists, never used in UI |
| `Exercise.bilateralLoadFactor: Double?` | `Exercise.swift` line 14 | Exists, used by LoadPrescriptionService |
| `WorkoutSet.side: Side?` | `WorkoutSet.swift` | Declared, never set or read |
| `Side` enum (`.left`, `.right`, `.both`) | `Side.swift` | Exists |

So the models already know about the concept — but no UI, no service logic, and no display uses it.

---

## Data Model Approach

### Recommended: Add parallel L/R fields to WorkoutSet

```swift
@Model final class WorkoutSet {
    // --- Existing fields (unchanged) ---
    var weight: Double?           // shared — same load both sides
    var reps: Int?                // used for bilateral exercises
    var rir: Double?              // used for bilateral exercises
    var side: Side?               // currently unused

    // --- NEW: unilateral-specific fields ---
    var leftReps: Int?            // reps performed on left side
    var rightReps: Int?           // reps performed on right side
    var leftRIR: Double?          // RIR for left side
    var rightRIR: Double?         // RIR for right side
}
```

### Why NOT separate set records per side

Creating two `WorkoutSet` records (one for L, one for R) would break:
- `orderInExercise` / `orderInWorkout` logic
- Set count in templates ("3 sets" becomes "6 records")
- Deletion (must delete both atomically)
- PR evaluation (double-counted sets)
- Stats (inflated set/rep counts)

### Why NOT a generic `[Side: Int]` dictionary

SwiftData doesn't natively support dictionary-typed properties with custom key types. Explicit fields are simpler and queryable.

### Convention

| Exercise type | Fields used | `side` value |
|---|---|---|
| Bilateral (default) | `reps`, `rir` | `nil` or `.both` |
| Unilateral | `leftReps`, `rightReps`, `leftRIR`, `rightRIR` | `.both` |
| `reps` field on unilateral | Computed: `max(leftReps, rightReps)` for PR purposes | — |

### Computed helpers on WorkoutSet

```swift
extension WorkoutSet {
    /// Total reps across both sides (for volume stats)
    var totalReps: Int {
        if let l = leftReps, let r = rightReps { return l + r }
        return reps ?? 0
    }

    /// Reps used for PR evaluation (stronger side)
    var prReps: Int {
        if let l = leftReps, let r = rightReps { return max(l, r) }
        return reps ?? 0
    }

    /// True if there's a meaningful imbalance between sides
    var hasImbalance: Bool {
        guard let l = leftReps, let r = rightReps, l + r > 0 else { return false }
        let diff = abs(l - r)
        return diff >= 2 || Double(diff) / Double(max(l, r)) > 0.15
    }

    /// "L: 10  R: 8" or "12" for bilateral
    var repsDisplayString: String {
        if let l = leftReps, let r = rightReps {
            return "L: \(l)  R: \(r)"
        }
        return "\(reps ?? 0)"
    }
}
```

---

## UI Changes

### Set Row Layout

**Current (bilateral):**
```
┌─────┬────────┬──────┬─────┬────┬───┐
│ SET │   KG   │ REPS │ RIR │ PR │ ✓ │
├─────┼────────┼──────┼─────┼────┼───┤
│  1  │  50    │  10  │  2  │  ★ │ ● │
└─────┴────────┴──────┴─────┴────┴───┘
```

**New (unilateral):**
```
┌─────┬────────┬───────────┬──────────┬────┬───┐
│ SET │   KG   │   REPS    │   RIR    │ PR │ ✓ │
│     │        │  L  │  R  │  L │  R  │    │   │
├─────┼────────┼─────┼─────┼────┼─────┼────┼───┤
│  1  │  50    │  10 │  8  │  2 │  3  │  ★ │ ● │
│     │        │     │     │    │     │    │   │
│     │        │  ⚠️ imbalance         │    │   │  ← optional warning
└─────┴────────┴───────────┴──────────┴────┴───┘
```

### Files to Modify

| File | Change |
|---|---|
| `SetRowView.swift` | Add conditional L/R column layout when `exercise.unilateral` |
| `SetTableView.swift` header | Add L/R sub-headers when unilateral |
| `SetTableView.swift` SetRowWrapper | Add `@State` bindings for `leftRepsText`, `rightRepsText`, `leftRirValue`, `rightRirValue` |
| `SetTableView.swift` onComplete closure | Pass L/R values to ViewModel |

### Imbalance Indicator

When `hasImbalance` is true, show a small warning below the row:
- Orange text: `"⚠ L-R imbalance: 2 reps"`
- Only for completed sets

---

## Impact on Existing Systems

### 1. PR System — LOW impact (keep it simple)

**Approach:** Use `max(leftReps, rightReps)` as the reps value for PR evaluation. Weight stays the same (both sides use the same dumbbell).

**Why this works:**
- The suffix-max frontier algorithm is unchanged
- `PerformanceRecord` doesn't need a `side` field
- PR badge shows on the set row (not per-side)
- The user's "PR" is their best performance on the stronger side

**What changes in code:**
- `SetService.save()` → when computing effective weight, use `set.prReps` instead of `set.reps` for unilateral exercises
- Everything else stays the same

**Future option:** If users request separate L/R PR tracking, that's a Phase 2 enhancement requiring `side` on `PerformanceRecord` + separate frontier walks.

### 2. Statistics — LOW impact

**Approach:** Use `totalReps` (L + R combined) for volume calculations.

```
volume = weight × totalReps   // = weight × (leftReps + rightReps)
```

**What changes:**
- `StatsService.handleSave()` → use `set.totalReps` instead of `set.reps` for unilateral exercises
- Total sets count stays the same (1 set = 1 record, regardless of sides)

### 3. History Display — MEDIUM impact

**ExerciseHistoryView.setRow():**
- Check if set has L/R data (`leftReps != nil`)
- If yes: show `"L: 10  R: 8"` format instead of plain `"× 10"`
- If imbalance: subtle highlight

**WorkoutSummarySheet:**
- Show L/R format in set breakdown

### 4. E1RM & Weight Suggestions — LOW impact

**Approach:** Use stronger side for e1RM calculation.

- `LoadPrescriptionService`: when computing e1RM, use `prReps` (= max of L, R)
- `E1RMCardView`: shows single e1RM value (no per-side)
- Weight suggestions: single value (same dumbbell both sides)

### 5. Charts — MEDIUM impact (optional enhancement)

**Phase 1:** Aggregate L + R for all chart metrics. No chart changes needed.

**Phase 2 (optional):** Add an "Imbalance" chart metric that shows `(leftReps - rightReps)` over time, to visualize whether the discrepancy is shrinking.

### 6. Exercise Creation — LOW impact

- `CreateEditExerciseSheet`: expose the existing `unilateral` toggle
- When toggled on, maybe suggest common unilateral exercises
- `bilateralLoadFactor` can stay as-is (used by LoadPrescriptionService)

---

## What Could Break (and How to Prevent It)

| Risk | Severity | Prevention |
|---|---|---|
| **Row width overflow on small screens** | Medium | Use compact L/R layout. Sub-columns share reps header. Test on iPhone SE. |
| **SetRowWrapper complexity explosion** | Medium | Keep bilateral path unchanged. Only add L/R bindings behind `if exercise.unilateral` guard. |
| **Completion logic confusion** | Low | A set is "complete" when BOTH sides have data. Check: `leftReps != nil && rightReps != nil` |
| **PR double-counting** | High | Use `prReps = max(L, R)`, NOT `totalReps`. Never create 2 PerformanceRecords per set. |
| **Stats inflation** | Medium | Volume uses `totalReps` (L+R) because you did lift both sides. Set count stays 1. |
| **Template sets** | Low | Template sets don't store reps data, just structure. No L/R needed in templates. |
| **Edit historic workout** | Medium | `EditWorkoutViewModel` uses same `SetTableView`. If the exercise was bilateral when recorded, show bilateral UI even if exercise was later changed to unilateral. Use `leftReps != nil` as the signal, not the exercise flag. |
| **Migration** | Low | All new fields are optional. Existing sets have `nil` for L/R fields → treated as bilateral. Zero migration needed. |
| **Comma decimal on L/R fields** | Low | Reuse `UnitConversion.parseDecimal()` for any numeric L/R input (RIR). Reps are Int, no comma issue. |

---

## Implementation Order

### Phase 1: Core L/R Input (MVP)
1. Add `leftReps`, `rightReps`, `leftRIR`, `rightRIR` to `WorkoutSet` model
2. Add computed helpers (`totalReps`, `prReps`, `hasImbalance`, `repsDisplayString`)
3. Expose `unilateral` toggle in exercise creation/edit UI
4. Update `SetRowView` + `SetTableView` header for L/R columns
5. Update `SetRowWrapper` with L/R state bindings and onComplete
6. Update `ActiveWorkoutViewModel.completeSet()` to pass L/R values

### Phase 2: Service Integration
7. Update `SetService.save()` to use `prReps` for unilateral PR evaluation
8. Update `StatsService` to use `totalReps` for volume
9. Update `ExerciseHistoryView.setRow()` with L/R display
10. Update `WorkoutSummarySheet` with L/R display

### Phase 3: Polish
11. Add imbalance indicator on completed set rows
12. Update `EditWorkoutViewModel` / `EditWorkoutView` for L/R editing
13. Test with comma decimal on RIR fields
14. Test keyboard Done button works for all L/R fields

### Phase 4: Optional Enhancements
15. Add "Imbalance" metric to Charts
16. Show L/R trend in exercise detail
17. Consider separate L/R PR tracking (Phase 2 of PR system)

---

## Testing Plan

| # | Test | Expected |
|---|------|----------|
| 1 | Create exercise with `unilateral` ON | Toggle visible and saves |
| 2 | Start workout with unilateral exercise | Set rows show L/R columns |
| 3 | Enter L: 10, R: 8, weight: 50, tap complete | Set completes, both sides saved |
| 4 | Check History tab | Shows "L: 10  R: 8" format |
| 5 | Imbalance of 2+ reps | Warning indicator appears |
| 6 | PR evaluation | PR uses max(10, 8) = 10 reps @ 50kg |
| 7 | Workout summary | Shows L/R breakdown per set |
| 8 | Complete with only L filled (R empty) | Should NOT complete — both sides required |
| 9 | Volume stats | Volume = 50 × (10 + 8) = 900 kg |
| 10 | Bilateral exercise in same workout | Normal single-column layout |
| 11 | Edit historic bilateral workout | Still shows single column (no L/R) |
| 12 | Chart for unilateral exercise | Aggregate volume shows correctly |
| 13 | E1RM card | Uses stronger side for calculation |
| 14 | Weight suggestion | Single value (same dumbbell both sides) |
| 15 | iPhone SE screen width | L/R columns fit without overflow |
