# Default Rep Range — Technical Scope

**Date:** 2026-09-13  
**Status:** Scoping only — no implementation  
**Proposed default:** 8–12 reps  
**Primary feature area:** Smart Suggestions

> **Superseded in part.** [DEFAULT_REP_RANGE_SCOPING.md](DEFAULT_REP_RANGE_SCOPING.md) supersedes this
> for the 8 → 8–12 default as a shippable piece, and [PROGRESSION_LADDER_SCOPING.md](PROGRESSION_LADDER_SCOPING.md) supersedes §10
> Strategy 3 and §15's ladder estimate. This doc stays the source for Strategy 2 (stable adaptive
> range), §11 (materializing guidance onto completed sets) and §12 (import/export compatibility).

## 1. Summary

Repster already supports rep ranges at the set, template, editor, and suggestion-engine levels. The
remaining single-value path is the profile-wide Smart Suggestions fallback:
`HealthProfile.prescriptionDefaultTargetReps`, currently defaulting to `8`.

The proposed change is to replace that fallback with a profile-wide default rep range, initially
`8...12`, used whenever a pending set has no explicit or template-provided reps guidance.

This is not primarily a data-model project. Most of the range plumbing already exists. The central
technical and product risk is that the current engine interprets a range as a per-set optimization
space, not as a traditional double-progression ladder. Making ranges the default would expose that
behavior to nearly every ad-hoc workout.

The recommended boundary is:

- Replace the global fallback target with a global fallback range.
- Keep actual performed reps as one integer.
- Keep explicit fixed targets valid for schemes such as 5×5.
- Preserve the existing precedence of manual target, template target, then global fallback.
- Do not add exercise-specific defaults as part of this change.
- Do not claim double progression unless separate progression work is implemented.

## 2. Terminology

The implementation needs to keep three concepts separate:

| Concept | Example | Meaning |
|---|---|---|
| Target range | 8–12 reps | The allowed or intended training band |
| Prescribed reps | 10 reps | The concrete rep count used to calculate a suggested weight |
| Performed reps | 11 reps | What the user actually completed and records in history |

The target range must not replace the performed-reps field. A completed set still records one rep
count, while Smart Suggestions may calculate a concrete prescription inside a wider target range.

## 3. Current architecture

### 3.1 Persisted set targets already support ranges

`WorkoutSet` stores both inherited/template targets and workout-local overrides:

- `targetRepMin`
- `targetRepMax`
- `overrideTargetRepMin`
- `overrideTargetRepMax`

See `Repster/Data/Models/WorkoutSet.swift`.

`TemplateSet` stores:

- `targetRepMin`
- `targetRepMax`

See `Repster/Data/Models/TemplateSet.swift`.

No new fields are required on either set model for the basic default-range change.

### 3.2 Template authoring already uses two bounds

`TemplateSetRow` presents separate minimum and maximum rep inputs and writes them to the editor
model. A fixed target remains possible by deliberately entering the same number in both fields.

See `Repster/Features/Templates/Views/CreateEditTemplateView.swift`.

### 3.3 Active-workout authoring already accepts ranges

`RepsTargetInputParser` recognizes:

- an empty value;
- a single positive integer;
- an ascending range such as `8-12`;
- invalid input.

`CustomRepRangeCommitter` writes a valid range to the workout-set override fields. The range editor
also supports removing a target and intentionally creating a fixed target.

See `Repster/Features/Workout/Views/SetTableView.swift`.

### 3.4 The global fallback is still one integer

`HealthProfile` currently stores:

```swift
var prescriptionDefaultTargetReps: Int?
```

It defaults to `8`, is exposed through `HealthProfileSnapshot`, and is edited with a single Stepper
in `SmartSuggestionsAdvancedSections`.

Relevant files:

- `Repster/Data/Models/HealthProfile.swift`
- `Repster/Core/Services/ChartSetData.swift`
- `Repster/Features/Settings/Views/PrescriptionSettingsView.swift`
- `Repster/Core/Services/SettingsService.swift`
- `Repster/Core/Services/Protocols/SettingsServiceProtocol.swift`

### 3.5 Target resolution

`SuggestionCoordinator.resolveTarget` currently resolves reps in this order:

1. Valid workout-local override range.
2. Fixed or one-sided workout-local override.
3. Reps already entered on the pending set.
4. Template target bounds.
5. Profile-wide `prescriptionDefaultTargetReps`.

It resolves RIR independently:

1. RIR entered on the set.
2. Template target RIR.
3. Profile-wide default target RIR.

The current profile fallback supplies one rep count and deliberately leaves `displayRepRange` nil.
Consequently, an ad-hoc set with no target enters the fixed-rep engine path.

See `Repster/Features/Workout/Models/WeightSuggestionData.swift`.

### 3.6 Range evaluation

When `SuggestionPendingSetInput.repRange` is non-nil and has distinct bounds, the engine:

1. Generates one candidate for every rep count in the range.
2. Calculates a raw weight for each candidate.
3. Rounds each weight to the configured increment.
4. Calculates the implied e1RM of each rounded candidate.
5. Selects the candidate closest to effective e1RM.
6. On the first set with a recent-performance baseline, it may instead select the smallest implied
   e1RM increase above the recent baseline.

See `SuggestionEngine.evaluate`, `repRangeCandidates`, `chooseRepRangeCandidate`, and
`bestProgressedCandidate` in
`Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift`.

This is adaptive candidate selection, not conventional double progression.

## 4. Proposed behavior contract

### 4.1 Default

New profiles should resolve to:

```text
Default rep range: 8–12
Default target RIR: 2
```

The supported numeric domain should remain `1...30`.

For a standard range, both bounds are required and must satisfy:

```text
1 <= minimum < maximum <= 30
```

### 4.2 Resolution precedence

The precedence should remain:

```text
workout-local target > entered pending reps > template target > profile default range
```

This preserves current user intent:

- Typing `10` creates an explicit fixed target for that set.
- Entering `6-8` creates an explicit range for that set.
- Starting from a template keeps the template's target.
- Only a set with no reps guidance receives the global range.

### 4.3 Presentation

The main suggestion strip should continue to display a concrete prescription:

```text
Set 1 · 60 kg for 10 reps
```

The explanation/detail surface should identify the underlying target:

```text
8–12 reps @ RIR 2 · from Smart Suggestions default
```

Displaying only `60 kg for 8–12 reps` would be ambiguous because the suggested weight is calculated
for a specific rep count.

### 4.4 Non-goals

The initial feature should not:

- Replace performed reps with a range.
- Remove support for fixed rep targets.
- Rewrite existing template or workout-set target fields.
- Convert fixed bundled programs such as 5×5 into ranges.
- Add per-exercise default ranges.
- Infer ranges from workout history.
- Change PR, volume, e1RM, chart, or set-completion semantics.
- Advertise double progression without implementing its state and rules.

## 5. Data model changes

### 5.1 New fields

Add two optional properties to `HealthProfile`:

```swift
var prescriptionDefaultTargetRepMin: Int?
var prescriptionDefaultTargetRepMax: Int?
```

Add matching fields to `HealthProfileSnapshot` and copy them in `init(from:)`.

The properties should remain optional because the project currently uses SwiftData implicit
lightweight migration for newly added optional fields. The migration plan in
`Repster/Data/Persistence/RepsterMigrationPlan.swift` is intentionally not wired into the container.

### 5.2 Legacy property

Retain:

```swift
var prescriptionDefaultTargetReps: Int?
```

It should be marked as a legacy compatibility field. It should not be renamed or removed as part of
this feature.

The runtime resolver should prefer valid new range fields and consult the legacy field only when a
new range has not been established.

### 5.3 New-profile initialization

`HealthProfile.init` should initialize the new fields to 8 and 12. The legacy field may remain 8 for
schema compatibility, but new application logic should not treat it as authoritative when a valid
range exists.

### 5.4 Snapshot boundary

`HealthProfileSnapshot` is the actor-safe value passed into Smart Suggestions. Both bounds must be
included there; reading the live `HealthProfile` from the workout UI would violate the project's
current SwiftData concurrency boundary.

`SwiftDataSnapshotBoundaryTests.testHealthProfileSnapshotCoversEveryStoredProperty` will fail until
the snapshot contains both new fields, providing an existing drift guard.

## 6. Migration and backfill

### 6.1 Store migration

Adding optional scalar fields should remain compatible with the current implicit lightweight
migration setup. A real-device or copied-store upgrade test is still required because this is a
persisted model change.

No explicit `SchemaMigrationPlan` should be introduced solely for these fields unless the project's
broader migration architecture is rebuilt with genuinely frozen schema versions.

### 6.2 Existing-user policy

The handling of existing `prescriptionDefaultTargetReps` values must be decided before coding.

#### Option A — universal 8–12

Backfill every old profile to 8–12.

Advantages:

- Immediate, consistent adoption.
- Simplest user-facing model.

Disadvantages:

- Silently overwrites deliberately customized rep targets.
- Changes suggestions on upgrade without preserving prior intent.

#### Option B — migrate the old default, preserve custom values

If the legacy value is nil or 8, backfill 8–12. If it differs from 8, preserve it through the legacy
fixed-target fallback until the user selects a range.

Advantages:

- Most existing users receive the new default.
- Custom configurations are not silently rewritten.

Disadvantages:

- Some upgraded users remain on fixed-target behavior.
- Settings needs a representation for a retained legacy exact target or an explicit conversion
  prompt.

#### Option C — compatibility first

Give only new profiles 8–12 and leave all upgraded profiles on their legacy exact target until they
edit Settings.

Advantages:

- No unexpected training-prescription change on upgrade.

Disadvantages:

- Slow feature adoption.
- Two default behaviors coexist for an extended period.

### 6.3 Recommendation

Use Option B. Treat legacy 8 as the application default and migrate it to 8–12, while preserving
non-default custom values until the user deliberately chooses a range.

The repository backfill must be idempotent: once new bounds exist, later reads must never derive them
again from the legacy value.

## 7. Settings service and UI

### 7.1 Atomic service API

Add one atomic protocol operation:

```swift
func updatePrescriptionDefaultRepRange(
    min: Int,
    max: Int
) async throws -> HealthProfileSnapshot
```

The service should validate the relation between both values in one repository mutation. Separate
`updateMin` and `updateMax` calls would permit temporary invalid states and introduce ordering risk
when SwiftUI creates asynchronous Tasks for rapid control changes.

The existing `updatePrescriptionDefaultTargetReps` method can remain temporarily for legacy callers,
but production code should migrate away from it.

### 7.2 Validation policy

UI controls should prevent invalid values. The service remains authoritative and should either:

- reject invalid ranges with a typed error; or
- normalize them according to a documented rule.

Rejecting is preferable to silently swapping or widening bounds. A saved range should always reflect
exactly what the user selected.

### 7.3 UI options

Two viable controls:

#### Two constrained numeric controls

- Minimum constrained to `1...(max - 1)`.
- Maximum constrained to `(min + 1)...30`.
- Direct and consistent with the template editor.

#### Preset menu plus Custom

Suggested presets:

- 3–5
- 5–8
- 6–10
- 8–12
- 10–15
- 12–20

This better communicates standard programming ranges and is faster to edit. A Custom option can
open the two-bound editor.

### 7.4 Onboarding

Onboarding no longer asks for a rep target but still writes `defaultTargetReps = 8` when finishing.
Either:

- replace that state and write with default range bounds; or
- remove the redundant reps write and let `HealthProfile` creation own the default.

The second option is cleaner. Onboarding can continue writing its default RIR if that behavior is
intentionally retained.

## 8. Suggestion resolution changes

### 8.1 Default range normalization

Replace `normalizedDefaultTargetReps` with a resolver that can return either:

- a valid new default range;
- a valid legacy fixed target;
- no target.

A useful internal result shape would keep the distinction explicit:

```swift
enum DefaultRepGuidance {
    case range(ClosedRange<Int>)
    case fixed(Int)
}
```

This avoids flattening the range to a midpoint before the engine input is constructed.

### 8.2 Building `SuggestionTarget`

For an 8–12 profile fallback:

```text
displayReps       = 10
displayRepRange   = 8...12
reps              = normalized midpoint
repRange          = normalized range
repsSource        = .smartDefault
```

The midpoint remains an anchor for tie-breaking and code paths that require one target rep count. It
must not erase the range before `SuggestionTarget` is built.

### 8.3 Cache identity

The suggestion cache key currently includes the single profile default. It must instead include:

```text
defaultRepMin
defaultRepMax
legacyDefaultReps, when it is the active fallback
```

Changing either bound must force a new suggestion evaluation.

### 8.4 Unilateral normalization

For `.perSide`, the displayed and engine ranges are the same.

For `.totalAcrossSides`, both displayed bounds are normalized into per-side engine space with the
existing ceiling-based conversion. Some narrow display ranges can collapse:

```text
9–10 total -> 5–5 per side
```

The system must define whether this:

- intentionally enters the fixed-target engine path;
- expands to preserve a range; or
- evaluates unique normalized candidates rather than requiring distinct normalized bounds.

The first option preserves current behavior but should be explicitly tested and explained.

## 9. Engine behavior exposed by making ranges the default

### 9.1 Rep and weight wandering

The optimizer chooses each pending set independently. Rounding can therefore cause later sets to
select different rep counts and can make a later weight rise despite higher projected fatigue.

The checked-in golden master contains this example for a 5–8 target:

```text
set 1: 77.5 kg × 7
set 2: 72.5 kg × 8
set 3: 75.0 kg × 6
set 4: 72.5 kg × 7
```

See `RepsterTests/Fixtures/SuggestionEngineGoldenMaster.txt`.

This is existing behavior, but changing the global fallback would make it common rather than
exceptional.

### 9.2 First-set progression policy

`bestProgressedCandidate` selects the candidate with the smallest implied e1RM delta above the recent
baseline. It does not require the bar weight to increase. A lighter weight for more reps can therefore
be labeled as progression.

This is mathematically defensible but may not match the user's understanding of progression.

### 9.3 Only the first set receives progression bias

The progression candidate path is gated by `isFirstSet`. Later pending sets use closest-match
selection only. This can create inconsistent intent across the same exercise.

### 9.4 Projected-fatigue mismatch

For later pending sets, projected fatigue currently uses the prior input's `targetReps`, which is the
range midpoint. It does not use the concrete `bestReps` selected for the preceding suggestion.

If a card prescribes 7 reps while fatigue is projected from 8 or 10, the engine is no longer
projecting the workload it presented to the user.

If the optimizer is retained, projected fatigue should use:

```text
previous decision.bestReps ?? previous decision.targetReps
```

### 9.5 Suggestion-floor mismatch

The suggestion floor compares completed-set capacity against `SuggestionTarget.reps`, which is the
range anchor. By the time the floor is applied, the range winner has already been selected, so floor
eligibility should be assessed against the chosen prescription rather than an unrelated midpoint.

### 9.6 Push option

The push option intentionally uses the upper range bound at RIR 0. That behavior should remain, but it
needs regression coverage once default ranges become common.

## 10. Progression strategies

The range plumbing can support three different product behaviors. One must be chosen explicitly.

### Strategy 1 — retain the current optimizer

The range remains a search space. The engine picks whatever rep count best survives weight rounding
for each set.

Required hardening before universal adoption:

- Use chosen reps for subsequent fatigue projection.
- Use chosen reps for suggestion-floor comparisons.
- Decide whether weight may rise on later sets.
- Add deterministic tie-breaking and multi-set regression coverage.
- Ensure the explanation distinguishes a mathematical e1RM progression from adding load.

This is the smallest implementation but has the least familiar gym-floor behavior.

### Strategy 2 — stable adaptive range

Choose one concrete rep target for the exercise/session, then calculate each set's weight against that
same rep count. The range remains the allowed band, but reps no longer jump between sets.

Possible rules for selecting the session rep count:

- midpoint;
- prior top-set reps clamped into the range;
- lower bound for a new exercise;
- a progression-derived value.

This is safer than per-set optimization but still requires a cross-session progression rule if the
feature is expected to tell the user when to add reps or weight.

### Strategy 3 — double progression

Interpret 8–12 conventionally:

1. Hold load across sessions.
2. Add reps until the upper bound is cleared.
3. Add one weight increment.
4. Reset prescribed reps to the lower bound.

This requires decisions that are outside the simple default-range plumbing:

- Which completed set governs progression: first set, top set, or all working sets?
- Does clearing require target RIR, or reps alone?
- What happens when RIR was not logged?
- What happens when the user ignores the suggestion?
- When does repeated failure trigger a load reduction?
- Does the ladder govern all sets or only the first/top set?
- How does fatigue modify later sets without fighting the ladder?
- Is progression scoped by exercise globally or by template/program context?
- Can ladder position be derived reliably from history, or must it be persisted?

This is a separate progression feature even though it uses the same range fields.

## 11. Persisting effective default guidance

The current profile default is resolved at suggestion time and is not copied onto `WorkoutSet`.
Keeping that behavior is the minimal scope, but it has consequences:

- A completed ad-hoc set does not permanently record which global range guided it.
- Changing Settings later changes how an old incomplete set resolves.
- `TargetAdherenceInsightRule` cannot count ad-hoc sets that only used the profile fallback.
- Creating a template from a completed ad-hoc workout cannot recover the original fallback range from
  the set itself.

Two options are available.

### Resolve only

Keep the default on `HealthProfile` and resolve it dynamically.

Advantages:

- Smallest change.
- Matches current global-target behavior.

Disadvantages:

- Historical target intent is not retained.
- Adherence analysis remains incomplete.

### Materialize on completion

When completing a set that used profile default guidance, copy the resolved range into the set's
target fields or a dedicated suggestion snapshot.

Advantages:

- Historical behavior remains stable.
- Target adherence can include ad-hoc workouts.
- Later template creation can preserve the prescription.

Disadvantages:

- Broadens the completion write path.
- Requires care not to overwrite explicit/template targets.
- Requires workout backup/restore regression coverage.

Recommendation: materialize the effective target, but implement it as a distinct second phase so the
global-default change and the history semantics can be reviewed independently.

## 12. Import, export, and backup compatibility

### 12.1 Template archives

Template import/export already carries `targetRepMin` and `targetRepMax`. No format change is required
for the global profile fallback.

Fixed imported targets must remain accepted.

### 12.2 Workout-history backup

The workout archive already carries workout-set target bounds. If the default range remains profile
only, no archive change is required because the existing single profile default is not backed up
either.

If resolved global guidance is materialized onto completed sets, existing workout-set serialization
should carry those fields, but round-trip tests must prove it.

### 12.3 Settings backup

Backing up the new profile range would be a broader settings-backup feature. It is not required for
parity with the current archive behavior.

## 13. Expected production-file impact

### Required for the global default range

| File | Change |
|---|---|
| `Repster/Data/Models/HealthProfile.swift` | Add min/max fields, defaults, legacy documentation |
| `Repster/Core/Services/ChartSetData.swift` | Mirror min/max into `HealthProfileSnapshot` |
| `Repster/Core/Repositories/HealthProfileRepository.swift` | Idempotent legacy backfill |
| `Repster/Core/Services/Protocols/SettingsServiceProtocol.swift` | Add atomic range update API |
| `Repster/Core/Services/SettingsService.swift` | Validate and persist range atomically |
| `Repster/Features/Settings/Views/PrescriptionSettingsView.swift` | Replace single Stepper with range control |
| `Repster/Features/Onboarding/ViewModels/OnboardingViewModel.swift` | Stop writing legacy target or write range |
| `Repster/Features/Workout/Models/WeightSuggestionData.swift` | Resolve default range and update cache key |

### Conditional engine hardening

| File | Change |
|---|---|
| `Repster/Core/Services/Protocols/LoadPrescriptionServiceProtocol.swift` | Rep stability, chosen-rep fatigue/floor consistency, or double progression |
| `Repster/Features/Workout/Views/Components/WeightSuggestionCardView.swift` | Copy changes only if prescription semantics change |
| `Repster/Features/Workout/Views/Components/SuggestionExplainerSheet.swift` | Explain range source and progression policy |

### Conditional target materialization

Likely touch points:

- `Repster/Features/Workout/ViewModels/ActiveWorkoutViewModel.swift`
- `Repster/Core/Services/SetService.swift`
- `Repster/Core/Repositories/SetRepository.swift`
- corresponding service/repository protocols

## 14. Test plan

### 14.1 Model and migration tests

- New `HealthProfile` initializes to 8–12.
- `HealthProfileSnapshot` carries both bounds.
- Existing profile with legacy 8 migrates according to the selected policy.
- Existing profile with a custom legacy value follows the selected compatibility policy.
- Existing valid new bounds are never overwritten by backfill.
- A copied pre-change store opens successfully and persists the new fields.

### 14.2 Settings-service tests

- Valid range persists atomically.
- Lower bound below 1 is rejected.
- Upper bound above 30 is rejected.
- Equal bounds are rejected for the standard default range.
- Reversed bounds are rejected.
- `updatedAt` changes after a successful update.
- Failure leaves both previous bounds intact.

### 14.3 Target-resolution tests

- Missing guidance resolves to 8–12 with source `.smartDefault`.
- The range midpoint/anchor is deterministic.
- Explicit fixed reps beat the profile range.
- Explicit workout range beats the profile range.
- Template fixed target beats the profile range.
- Template range beats the profile range.
- Default RIR still fills only the missing RIR component.
- Invalid new profile bounds use the documented legacy or missing-target fallback.
- Changing either default bound changes the suggestion cache key.

### 14.4 Unilateral tests

- Per-side exercise retains 8–12 as 8–12.
- Total-across-sides exercise displays total reps and receives normalized engine bounds.
- Odd bounds normalize consistently.
- A range that collapses after normalization follows the selected fixed/candidate policy.
- Suggested and displayed reps map back into the original display range.

### 14.5 Engine tests

If the current optimizer is retained:

- Later-set fatigue uses the prior chosen reps.
- Suggestion-floor comparisons use the chosen prescription.
- Rep and weight behavior across multiple sets matches the chosen stability rule.
- First-set progression cannot be mislabeled as load progression.
- Range candidate tie-breaking is stable.
- Push options remain within the display range.

If double progression is selected:

- New exercise initialization.
- One-rep advancement.
- Upper-bound clearance.
- Weight increment and reset to lower bound.
- Miss and repeated-miss handling.
- Missing-RIR behavior.
- User override behavior.
- Multiple working sets.
- Template-context versus global exercise history.
- Deload, excluded-workout, and stale-history behavior.

### 14.6 UI and accessibility tests

- Settings displays the saved range.
- Controls cannot construct invalid bounds.
- VoiceOver reads “Default rep range, 8 to 12.”
- Suggestion strip reads the concrete prescribed reps.
- Explanation identifies the underlying range and source.
- Fixed targets remain distinguishable from ranges.
- Narrow-screen layout supports the largest two-digit values.

### 14.7 Regression suites

Focused suites likely to require updates or execution:

- `ActiveWorkoutViewModelSuggestionRefreshTests`
- `SmartSuggestionBehaviorScenarioTests`
- `SuggestionEngineGoldenMasterTests`
- `OnboardingCompletionTests`
- `LiveModelRaceReproTests`
- `WorkoutHistoryBackupTests`
- `TemplateServiceTests`
- `TemplateImportExportTests`
- `WorkoutJourneyTests`

All `SettingsServiceProtocol` test doubles must compile with the new atomic API.

## 15. Delivery options and estimate

| Delivery | Included | Relative size |
|---|---|---|
| Plumbing only | Profile fields, migration, Settings, resolver, cache, tests | 2–4 engineering days |
| Safe adaptive default | Plumbing plus chosen-rep consistency and stable multi-set behavior | 5–8 engineering days |
| True double progression | Plumbing plus cross-session ladder rules, state/history logic, explanations, broader QA | Approximately 2–3 weeks after decisions |

These are implementation estimates, not calendar commitments. Real-store migration QA and any
decision to persist effective targets can expand them.

## 16. Recommended sequence

1. Lock the default at 8–12 and choose the existing-user migration policy.
2. Decide whether the range means current adaptive search, stable within-session guidance, or true
   double progression.
3. If retaining adaptive search, fix chosen-rep fatigue/floor consistency and define a stability rule
   before making the range universal.
4. Add optional profile fields and snapshot plumbing.
5. Add the atomic Settings service operation and range UI.
6. Update target resolution, unilateral normalization, and cache identity.
7. Add migration, precedence, display, and engine regression tests.
8. Decide separately whether resolved profile guidance should be materialized onto completed sets.
9. Run a copied-store upgrade test and focused workout-journey QA.

## 17. Decisions required before implementation

1. Is the new default exactly 8–12?
2. How should custom legacy exact targets migrate?
3. Does “rep range” mean adaptive candidate selection or double progression?
4. Must reps remain stable across all sets in one exercise session?
5. May a later suggested weight rise because the selected rep count changed?
6. Should a mathematically higher e1RM at lower load be described as progression?
7. What should happen when total-across-sides normalization collapses a narrow range?
8. Should completed ad-hoc sets persist the effective default range?
9. Should the empty reps field display the profile range as a placeholder?
10. If double progression is selected, which set governs advancement and how is missing RIR handled?

## 18. Recommended decision set

For a safe first release:

- Default: 8–12.
- Migration: convert legacy default 8; preserve customized legacy targets until edited.
- Keep intentional fixed targets.
- Keep the card's concrete rep prescription and show the range in details.
- Stabilize rep selection within an exercise session.
- Use chosen reps consistently for fatigue and floor logic.
- Prevent later-set weight increases caused solely by range candidate switching.
- Materialize resolved default guidance in a follow-up phase.
- Treat genuine double progression as a separately designed progression feature.

This produces a real default-range feature without silently promising ladder behavior the current
engine does not provide.
