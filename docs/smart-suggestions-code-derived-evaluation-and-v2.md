# Smart Suggestions: Code-Derived Evaluation and V2

This document is derived from the current implementation only. It intentionally ignores older prose docs unless they match the code.

Primary source files:

- `Reppo/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift`
- `Reppo/Core/Services/LoadPrescriptionService.swift`
- `Reppo/Features/Workout/Models/WeightSuggestionData.swift`
- `Reppo/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift`
- `Reppo/Features/Workout/Views/SetTableView.swift`
- `Reppo/Core/Services/SetService.swift`
- `Reppo/Features/Workout/ViewModels/ExerciseInfoProvider.swift`

## Summary

Smart Suggestions today is an active-workout, read-only load recommendation feature for weight-based exercises. The current recommendation math is now split into three explicit layers in code:

- `SuggestionEngine`: pure calculation from normalized inputs
- `SuggestionExplainer`: display labels, diagnostics, and alternatives
- `SuggestionCoordinator`: app-model gathering and cache-key helpers

The current behavior is unchanged in intent. The main functional improvement in this pass is that the keyboard wand can now use row-specific suggestions instead of always applying the first pending suggestion.

## System Map

### Inputs used today

#### Completed-session inputs

- Completed non-warmup sets for the current exercise
- Per set:
  - `effectiveWeight ?? weight`
  - `reps`
  - `rir`
  - `completedAt`
  - `completed`

These are normalized into `SessionSetContext`.

#### Pending-set inputs

- Every incomplete non-warmup set for the current exercise
- Per pending set:
  - underlying `WorkoutSet.id`
  - source index in the current set array
  - display set number among non-warmup sets
  - target reps
  - target RIR
  - optional rep range

These are normalized into `SuggestionPendingSetInput`.

#### Global settings used by current logic

- `HealthProfile.prescriptionEnabled`
- `HealthProfile.prescriptionRecencyWeeks`
- `HealthProfile.prescriptionDefaultIncrement`
- `HealthProfile.prescriptionFreshnessBonus`
- `HealthProfile.prescriptionFreshnessBonusPercent`
- `HealthProfile.prescriptionFatigueModelingEnabled`
- `HealthProfile.e1RMFormula`
- `HealthProfile.defaultRestTimeSeconds`

#### Exercise overrides used by current logic

- `Exercise.defaultRestTime`
- `Exercise.weightIncrement`

#### Stored performance inputs used by current logic

- Recent `WorkoutSet.e1RM` snapshots
- `PerformanceRecord` rep-max entries for PR fallback

#### Set semantics used by current logic

- Suggestions exclude only `warmup` sets
- Base-e1RM history excludes `warmup` and `partial`
- Other special set types can still receive suggestions and affect fatigue once completed

### Runtime flow today

1. User edits set rows in `SetTableView`.
2. Incomplete row edits mutate the in-memory `WorkoutSet` immediately.
3. `ActiveWorkoutViewModel.loadWeightSuggestions()` gathers current sets for the selected exercise.
4. `SuggestionCoordinator` derives:
   - completed session context
   - pending set inputs
   - a cache key
5. `LoadPrescriptionService.evaluateSuggestions()` resolves:
   - settings
   - exercise overrides
   - base e1RM estimate
   - normalized `SuggestionEngineInput`
6. `SuggestionEngine` computes one result per pending set.
7. `SuggestionExplainer` converts engine results into `WeightSuggestionData`.
8. `WeightSuggestionModuleView` renders the suggestion card.
9. `SetTableView` asks the data source for a row-specific suggested weight when showing the keyboard wand action.

### Settings and fields that exist but are inert in current logic

- `HealthProfile.prescriptionDefaultRecoveryConstant`
- `Exercise.fatigueRate`
- `Exercise.recoveryConstant`
- `SessionSetContext.completedAt` for fatigue math

They are part of persisted data or cache signatures, but they do not currently change the engine's calculation.

## Behavior Spec From Code

### Engine behavior

#### Base e1RM selection

1. Read the current formula from `HealthProfile.e1RMFormula`.
2. Look back `prescriptionRecencyWeeks` weeks.
3. Fetch recent sets for the exercise.
4. Keep only sets that are:
   - completed
   - not warmup
   - not partial
   - have `e1RM > 0`
5. Group those sets by workout.
6. For each workout, take the best stored `e1RM`.
7. Sort workouts by newest date.
8. Take the top value across the last 3 workouts.
9. If no valid recent history exists, fall back to rep-max PR records and recompute e1RM using the current formula.
10. If no fallback exists either, suggestions are unavailable.

Important:

- There is no current-session base-e1RM override in the current code.
- Historical base e1RM uses stored set snapshots, not fresh RIR-aware recomputation.

#### Fatigue computation

If fatigue modeling is enabled:

1. Keep completed session sets.
2. Process them in current order.
3. Before each set after the first, decay accumulated fatigue by `exp(-restTimerSeconds / 300)`.
4. Each set adds:
   - base fatigue `0.03`
   - plus `max(0, 2 - rir) * 0.02`
   - multiplied by `min(reps / 8, 1.5)`
5. Cap total fatigue at `0.20`.

If fatigue modeling is disabled:

- session fatigue is `0.0`

Important:

- Rest uses configured rest time, not measured rest from timestamps.
- Missing RIR in fatigue math defaults to `2.0`.

#### Freshness application

- Freshness only applies when there are no completed session sets.
- It applies only to the first pending set by source set index.
- When enabled, effective readiness is multiplied by `1 + freshnessPercent`.

#### Readiness clamp

- Start from `baseE1RM * (1 - sessionFatigue)`.
- Apply freshness if eligible.
- Clamp effective e1RM to `95%...105%` of base e1RM.

#### Single-target weight selection

1. Compute `totalReps = max(1, targetReps + Int(targetRIR))`.
2. Compute intensity with `formula.reverseCalculate(e1RM: 1.0, reps: totalReps)`.
3. Floor the intensity to `0.3`.
4. Compute `rawWeight = effectiveE1RM * intensity`.
5. Round to the nearest increment.

#### Rep-range optimization

If `repRange` exists and has more than one rep:

1. Evaluate every rep candidate in the range.
2. For each candidate:
   - compute `totalReps = candidateReps + Int(targetRIR)`
   - reverse-calculate raw load
   - round that load
   - recompute implied e1RM from the rounded load
3. Choose the candidate whose implied e1RM is closest to the effective e1RM.

This means the current system optimizes for:

- closest rounded e1RM match

It does not optimize for:

- heaviest load likely to still land in-range

#### Rounding

- All weight rounding is nearest-increment rounding.
- Increment comes from `Exercise.weightIncrement ?? HealthProfile.prescriptionDefaultIncrement ?? 2.5`.

### View-model shaping

#### Pending set target derivation

For each incomplete non-warmup set:

- Target reps:
  - use `set.reps` if present and positive
  - else midpoint of `targetRepMin/targetRepMax`
  - else `targetRepMin`
  - else `targetRepMax`
  - else `8`
- Target RIR:
  - use `set.rir` if present
  - else `targetRIR`
  - else `2.0`
- Rep range:
  - use `targetRepMin...targetRepMax` only when both exist and `min < max`

#### Cache/reload behavior

The suggestion cache key includes:

- exercise ID
- exercise increment
- exercise `fatigueRate`
- exercise `recoveryConstant`
- relevant profile values
- completed non-warmup set signatures
- pending set signatures

Suggestions reload when:

- current exercise changes
- a set is completed
- a set is uncompleted
- a set is added
- a warmup set is added
- a set is deleted
- a set type is changed

Suggestions do not currently live-recompute on every incomplete-field edit.

### UI/debug display behavior

- `WeightSuggestionCardView` shows all pending set suggestions for the current exercise.
- Expanded details show:
  - base and effective e1RM
  - readiness delta
  - fatigue discount
  - freshness on/off
  - intensity factor
  - raw vs rounded load
  - range choice
  - nearby +/- 1 increment alternatives
- The keyboard wand now uses row-specific lookup by `WorkoutSet.id`.

## Complexity and Drift Audit

### Coupling points

#### Engine vs diagnostics duplication

Previously the view model rebuilt much of the explanation logic directly. This pass moves the active path into:

- `SuggestionEngine`
- `SuggestionExplainer`
- `SuggestionCoordinator`

The remaining complexity is still non-trivial because the engine output and explanation output are both rich.

#### Shared base-e1RM logic with Exercise Info

Exercise Info still depends on the same base-e1RM estimation service. That means changes to Smart Suggestions capacity logic will affect the exercise info cards unless separated further.

#### Keyboard flow vs card flow

Before this pass, the wand action always used the first suggestion. That created inconsistent behavior when multiple pending sets existed. This pass fixes that by mapping suggestions per row.

#### Stale vs live recompute behavior

The set row mutates the in-memory model as the user types, but Smart Suggestions only recomputes on broader lifecycle events. This means a row can contain unsaved pending edits that the suggestion system sees only after an explicit reload path runs.

#### Persisted but ignored settings

The current implementation stores and surfaces settings that do not yet affect engine behavior:

- default recovery constant
- exercise fatigue rate
- exercise recovery constant

These fields increase conceptual surface area without changing current recommendations.

### Behavioral mismatches that matter

- Stored set e1RM snapshots are computed from `effectiveWeight + reps` only. Logged RIR does not affect stored history.
- Current-session completed sets affect fatigue, but not the base e1RM estimate.
- Historical base e1RM uses stored snapshots, while PR fallback uses the currently selected formula.
- Measured rest timestamps are collected in session context but not used by the fatigue model.

## Evaluation Matrix

| Behavior | Current status | V2 stance |
| --- | --- | --- |
| Historical base-e1RM policy | Recent top value across last 3 workouts, PR fallback | `Needs product decision` |
| Session fatigue model | Simple fixed model with configured rest and RIR/reps scaling | `Needs product decision` |
| Rep-range selection policy | Closest rounded e1RM match | `Needs product decision` |
| Freshness bonus | Optional first-pending-set boost | `Needs product decision` |
| Rounding policy | Nearest configured increment | `Keep` |
| Live recompute policy | Reload on events, not every edit | `Likely remove/change in V2` |
| Multi-set/per-row UX | Card is per-set; wand is now per-row | `Keep` |
| Diagnostics depth | Very detailed card diagnostics | `Likely remove/change in V2` |

## V2 Design

### Coaching decisions to make explicitly

#### Base strength signal

Choose one:

- recent best sessions
- current-session override
- blended current + recent

#### Rep-range philosophy

Choose one:

- closest rounded e1RM match
- heaviest likely in-range load
- another explicit policy with a written decision rule

#### Progression interpretation

Define:

- what top-of-range at target RIR means
- what top-of-range below target RIR means
- what above-range performance means
- what repeated same-result sessions mean

#### Fatigue behavior

Choose one:

- keep the current simple model
- simplify it further
- disable by default

#### Rest semantics

Choose one:

- configured rest only
- actual measured rest
- hybrid with fallback

### Target architecture

Implemented direction in this pass:

- `SuggestionEngine`: pure calculation layer
- `SuggestionExplainer`: explanation/display layer
- `SuggestionCoordinator`: app-model gathering and cache-key layer

Remaining V2 direction:

- keep `LoadPrescriptionService` focused on repository-backed normalization and base-e1RM lookup
- make the active-workout view model consume coordinator output, not own suggestion construction logic
- keep row-specific suggestion lookup as the only keyboard integration path
- avoid using UI models as the core calculation contract

### Planned interface changes

Implemented in this pass:

- normalized engine input: `SuggestionEngineInput`
- normalized engine output: `SuggestionEngineResult`
- evaluation bundle: `SuggestionEvaluation`
- row-addressable lookup via `SetTableDataSource.suggestedWeight(for:)`

Still recommended for a fuller V2:

- add a first-class policy enum for rep-range behavior
- add a first-class policy enum for base-strength source selection
- isolate explanation verbosity from default user-facing UI
- decide whether Exercise Info should continue to share the same base-e1RM path

## Validation Plan

Use scenarios plus code audit, not historical replay, as the first evaluation method.

### Base e1RM scenarios

- no history
- recent history only
- PR fallback only
- recent history plus stronger older PR
- formula changed after old sets were saved

### Session adaptation scenarios

- first set with freshness off
- first set with freshness on
- multiple completed hard sets
- multiple easy sets
- same exercise with different configured rest times

### Rep-targeting scenarios

- exact reps, no range
- rep range with coarse increment
- rep range with fine increment
- top-of-range candidate being lighter but mathematically closer
- heavier candidate staying in range but farther from target e1RM

### Set-semantics scenarios

- warmup before working sets
- special set types like dropset, AMRAP, backoff
- incomplete row edited but not saved
- row-specific wand application with multiple pending sets

### UX/state scenarios

- switching exercises
- completing a set
- uncompleting a set
- adding or deleting a set
- changing set type
- suggestion card and wand staying consistent

### Acceptance criteria for a fuller V2

- every scenario has an expected output and rationale
- engine tests cover policy rules without UI dependencies
- view-model tests cover row mapping, cache invalidation, and reload triggers
- UI verification stays limited to display wiring and row-specific application behavior

## Notes On This Pass

This pass does not choose the final coaching policy for V2. It does three narrower things:

1. Captures current behavior from code in one place.
2. Extracts the active logic into explicit engine/coordinator/explainer boundaries.
3. Fixes the row-mapping bug where the keyboard wand used the first suggestion instead of the row's suggestion.
