# Research: Exercise Info in Active Workout

**Feature**: 014-exercise-info-active-workout
**Date**: 2026-03-01

## Research Tasks

### R1: Reverse E1RM Calculation (Weight from E1RM + Target Reps)

**Decision**: Add `reverseCalculate(e1RM:reps:)` method to the existing `E1RMFormula` enum.

**Rationale**: The "Est. for N reps" card needs to display a suggested weight given a target rep count and the user's best e1RM. The forward formulas are already implemented but no reverse method exists.

**Implementation**:

| Formula | Forward: e1RM = f(weight, reps) | Reverse: weight = f(e1RM, reps) |
|---------|--------------------------------|--------------------------------|
| Epley | `weight × (1 + reps/30)` | `e1RM / (1 + reps/30)` |
| Brzycki | `weight × 36 / (37 - reps)` | `e1RM × (37 - reps) / 36` |
| Lombardi | `weight × reps^0.10` | `e1RM / reps^0.10` |

Guard clause: `reps <= 1` returns `e1RM` unchanged (1RM = e1RM by definition).

**Alternatives considered**:
- Lookup table of percentage-based estimates → Rejected: less accurate, not personalized to formula choice
- Always use Epley reverse → Rejected: inconsistent with user's selected formula in HealthProfile

**File to modify**: `Reppo/Data/Enums/E1RMFormula.swift`

---

### R2: Historical E1RM Comparison (~4 Weeks Ago)

**Decision**: Compute the comparison from exercise history sets already fetched for the Exercise Info provider. Filter sets by date, find best e1RM near the 28-day mark, compute delta.

**Rationale**: The e1RM card must show "vs 4wk ago: +X.X kg" or "−X.X kg". The chart infrastructure (`ChartDataService`) already computes per-session e1RM trend points with dates, but we should compute this independently within `ExerciseInfoProvider` to avoid coupling to chart loading.

**Algorithm**:
1. From all exercise sets (already fetched), filter to those with `hasData && e1RM != nil`
2. Exclude current workout's sets
3. Find the set with the best e1RM closest to 28 days ago (window: 21–35 days)
4. If no match in window, use the nearest available historical e1RM before today
5. Delta = `currentBestE1RM - historicalE1RM`
6. Display: positive → green (`Color.success`), negative → red (`Color.danger`)
7. Use `toGrams()` for comparison precision (per constitution)

**Data source**: `SetService.fetchSets(for: exerciseId, limit: nil)` — same call used by history sub-tab, can be shared/cached.

**Alternatives considered**:
- Reuse `ChartDataService.fetchExerciseDetailCharts()` → Rejected: creates coupling to charts module; chart data aggregates per-session max which is correct, but loading an entire chart service for one comparison is over-engineered
- Store "4 weeks ago e1RM" in `ExerciseStats` → Rejected: over-engineering a write-time field for a display-only need that varies by date

---

### R3: Last Workout Top Sets Extraction

**Decision**: Reuse the history grouping pattern from `loadHistoryForCurrentExercise()`. Group sets by `workoutId`, sort groups by date descending, take the first group that isn't the current workout. Filter to working sets with `hasData`, sort by `effectiveWeight` descending, take top 2–3 sets.

**Rationale**: The "Last Workout" card shows the most recent previous session's top working sets with a relative time label.

**Algorithm**:
1. From fetched exercise sets, group by `workoutId`
2. Exclude the current active workout's `workoutId`
3. Sort groups by date descending → first group = last workout
4. Filter group's sets: `setType == .working && hasData == true`
5. Sort by `effectiveWeight` descending
6. Take top 2 sets for compact display (e.g., "85×8, 45×8")
7. Compute relative time: `RelativeDateTimeFormatter` for "N days ago"

**Alternatives considered**:
- Fetch only the last workout's sets via a dedicated query → Rejected: we're already fetching all sets for the comparison calculation, reuse is more efficient
- Show all working sets from last workout → Rejected: too much data for a compact card; top 2 is sufficient for "at a glance" context

---

### R4: Insertion Point in ActiveWorkoutView

**Decision**: Insert `ExerciseInfoSectionView` inside the `.sets` sub-tab's `ScrollView`, **after** `SetTableView`, not inside it.

**Rationale**: `SetTableView` is a self-contained card (bgCard + 12pt radius). Exercise Info is a separate visual section with its own cards, not part of the set table. Placing it after `SetTableView` in the parent `ScrollView` maintains clean separation.

**Insertion point** (in `ActiveWorkoutView.swift`, inside the `.sets` case):
```swift
ScrollView {
    SetTableView(viewModel: viewModel)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    // ← INSERT HERE
    ExerciseInfoSectionView(data: viewModel.exerciseInfoData, unitPreference: ...)
        .padding(.horizontal, 20)
        .padding(.top, 16)
}
```

**Alternatives considered**:
- Inside `SetTableView` after `addButtons()` → Rejected: breaks separation of concerns; Exercise Info is not part of the set table's logical unit
- As a separate overlay or sheet → Rejected: spec requires inline display below the set table within the scroll flow

---

### R5: Data Sharing and Caching Strategy

**Decision**: `ExerciseInfoProvider` fetches exercise sets once via `SetService.fetchSets(for: exerciseId, limit: nil)` and derives all three cards' data from that single fetch. Cache by `exerciseInfoLoadedForExerciseId` (matching existing pattern). Clear on exercise switch.

**Rationale**: All three cards need overlapping data (current session sets, historical sets, e1RM values). One fetch serves all computations.

**Data flow**:
```
Exercise tab switch → clearSubTabCache() (extended to clear exerciseInfo)
                    → .sets tab visible
                    → loadExerciseInfo()
                        → ExerciseInfoProvider.compute(
                            currentSets: currentSets,          // already in memory
                            exerciseId: exerciseId,
                            currentWorkoutId: workout.id,
                            setService: setService,
                            healthProfileRepo: healthProfileRepo
                          )
                        → returns ExerciseInfoData
                    → viewModel.exerciseInfoData = result
```

**Performance**: Single DB query for history sets. Current sets are already in memory (`setsByExercise[exerciseId]`). No redundant fetches. Target: < 500ms total.

**Alternatives considered**:
- Separate fetch per card → Rejected: 3 DB queries instead of 1; redundant data fetching
- Reuse `subTabHistory` data → Rejected: would couple Exercise Info loading to History tab being loaded first; Exercise Info must load independently

---

### R6: Unit Display Formatting

**Decision**: Use existing `UnitConversion` utilities with `HealthProfile.unitPreference`. Display weights via a helper that converts kg → lbs when imperial is selected.

**Rationale**: Constitution mandates "store metric, convert in UI". The conversion utility exists at `Reppo/Core/Extensions/UnitConversion.swift`. All Exercise Info values are computed in kg internally.

**Display format**:
- e1RM value: "105.5 kg" or "232.6 lbs" (1 decimal)
- Weight in best today: "85 × 8" (integer if whole, 1 decimal otherwise)
- Delta: "+2.3 kg" / "−1.1 kg" (1 decimal, always show sign)
- Estimated weight: "85 kg" (rounded to nearest increment)

**Rounding**: Use `Exercise.weightIncrement` if available to snap estimated weight to practical plate values. Default to 2.5 kg / 5 lbs increments if not set.

---

### R7: Duration-Based Exercise Handling

**Decision**: When `exercise.trackingType == .duration` (or other non-weight tracking types), hide the e1RM card and Est. for N reps card. Show only the Last Workout card adapted to display duration values.

**Rationale**: e1RM is meaningless for duration-only exercises (no weight/reps data). The spec explicitly requires adaptation: "Duration-based exercises MUST hide or adapt cards that require weight/rep data."

**TrackingType behavior**:
| TrackingType | e1RM Card | Last Workout Card | Est. for N Reps |
|-------------|-----------|-------------------|-----------------|
| `weightReps` | ✅ Show | ✅ Show (weight × reps) | ✅ Show |
| `duration` | ❌ Hide | ✅ Show (duration) | ❌ Hide |
| `weightDistance` | ❌ Hide | ✅ Show (weight × distance) | ❌ Hide |
| `weightRepsDuration` | ✅ Show | ✅ Show (weight × reps) | ✅ Show |
| `custom` | Conditional | ✅ Show | Conditional |

For types where e1RM is hidden, the Last Workout card can span full width.

---

## Summary

All unknowns resolved. No NEEDS CLARIFICATION markers remain.

| # | Unknown | Resolution |
|---|---------|------------|
| R1 | Reverse e1RM calculation | Add `reverseCalculate(e1RM:reps:)` to `E1RMFormula` |
| R2 | 4-week historical comparison | Filter fetched sets by date, find best e1RM in 21–35 day window |
| R3 | Last workout top sets | Group by workoutId, exclude current, take top 2 working sets |
| R4 | View insertion point | After `SetTableView` in ScrollView, not inside it |
| R5 | Caching strategy | Single fetch, cache by exerciseId, clear on switch |
| R6 | Unit formatting | Existing `UnitConversion` + `HealthProfile.unitPreference` |
| R7 | Duration exercises | Hide weight-dependent cards, adapt Last Workout |
