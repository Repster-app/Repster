---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
title: "Foundation — Data Models & Provider Logic"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: "claude-opus"
agent: "claude-opus"
shell_pid: "80100"
review_status: "approved"
reviewed_by: "claude-opus"
dependencies: []
history:
  - timestamp: "2026-03-01T19:53:31Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-03-01T20:03:34Z"
    lane: "doing"
    agent: "claude-opus"
    shell_pid: "76595"
    action: "Started implementation via workflow command"
  - timestamp: "2026-03-01T20:11:19Z"
    lane: "for_review"
    agent: "claude-opus"
    shell_pid: "76595"
    action: "Ready for review"
  - timestamp: "2026-03-01T20:27:35Z"
    lane: "done"
    agent: "claude-opus"
    shell_pid: "80100"
    action: "Review passed"
---

# Work Package Prompt: WP01 – Foundation — Data Models & Provider Logic

## Implementation Command

```bash
spec-kitty implement WP01
```

## Objectives & Success Criteria

- Create all value type structs that power the Exercise Info section display
- Add a reverse e1RM calculation method to the existing `E1RMFormula` enum
- Implement the `ExerciseInfoProvider` computation engine that derives all three card models from a single data fetch
- **Success**: `ExerciseInfoProvider.compute()` returns a fully-populated `ExerciseInfoData` for all tracking types, empty states, and edge cases

## Context & Constraints

**Architecture**: MVVM with Service/Repository layers (View → ViewModel → Service → Repository).
**Constitution**: `.kittify/memory/constitution.md` — no new `@Model` classes, use `effectiveWeight`, `hasData` for filtering, `toGrams()` for float comparison, store metric/convert in UI.
**Plan**: `kitty-specs/014-exercise-info-active-workout/plan.md`
**Data model**: `kitty-specs/014-exercise-info-active-workout/data-model.md`
**Provider contract**: `kitty-specs/014-exercise-info-active-workout/contracts/exercise-info-provider.md`
**Research**: `kitty-specs/014-exercise-info-active-workout/research.md` (R1–R7)

**Key constraint**: No new service or repository interfaces. Use only existing `SetService.fetchSets()`, `StatsService.fetchStats()`, and `HealthProfileRepository.fetchOrCreate()`.

## Subtasks & Detailed Guidance

### Subtask T001 – Create ExerciseInfoData.swift

- **Purpose**: Define all transient value types used to pass computed Exercise Info data from the provider to the views. These are NOT SwiftData `@Model` classes — they are plain Swift structs.
- **File**: `Reppo/Features/Workout/Models/ExerciseInfoData.swift` (NEW)
- **Parallel?**: Yes — no dependencies on other subtasks.

**Steps**:

1. Create the file at the path above.

2. Define the `Trend` enum:
   ```swift
   enum Trend: String, Sendable {
       case positive
       case negative
       case neutral
   }
   ```

3. Define `TopSet` struct:
   ```swift
   struct TopSet: Identifiable, Sendable {
       let id = UUID()
       let weight: Double          // effectiveWeight in kg
       let reps: Int?              // nil for duration-based
       let durationSeconds: Int?   // nil for weight/reps-based
       let formattedLabel: String  // Pre-formatted: "85×8" or "2:30"
   }
   ```

4. Define `E1RMInfo` struct:
   ```swift
   struct E1RMInfo: Sendable {
       let currentE1RM: Double     // Today's best e1RM in kg
       let bestSetWeight: Double   // effectiveWeight of today's best set (kg)
       let bestSetReps: Int        // Reps of today's best set
       let historicalE1RM: Double? // e1RM from ~4 weeks ago (nil if no history)
       let historicalWeeksAgo: Int? // Actual weeks ago (e.g., 4)
       let delta: Double?          // currentE1RM - historicalE1RM (nil if no history)
       let trend: Trend?           // .positive/.negative/.neutral (nil if no history)
   }
   ```

5. Define `LastWorkoutInfo` struct:
   ```swift
   struct LastWorkoutInfo: Sendable {
       let topSets: [TopSet]       // Top 2 working sets, sorted by effectiveWeight desc
       let daysAgo: Int            // Days since last session
       let relativeTimeLabel: String // "9 days ago"
   }
   ```

6. Define `EstimatedRepsInfo` struct:
   ```swift
   struct EstimatedRepsInfo: Sendable {
       let targetReps: Int         // Rep count being estimated for
       let estimatedWeight: Double // Reverse-calculated weight in kg
       let sourceLabel: String     // "Based on recent data"
   }
   ```

7. Define the top-level `ExerciseInfoData` struct:
   ```swift
   struct ExerciseInfoData: Sendable {
       let e1RMInfo: E1RMInfo?              // nil for duration/distance tracking
       let lastWorkoutInfo: LastWorkoutInfo? // nil if no previous session
       let estimatedRepsInfo: EstimatedRepsInfo? // nil if insufficient data
       let trackingType: TrackingType        // Determines card visibility
   }
   ```

**Validation**:
- [ ] All structs conform to `Sendable`
- [ ] No imports of SwiftData — these are pure value types
- [ ] `TopSet` conforms to `Identifiable`
- [ ] All properties are `let` (immutable value types)

---

### Subtask T002 – Add reverseCalculate to E1RMFormula

- **Purpose**: Enable the "Est. for N reps" card to compute an estimated weight given an e1RM value and a target rep count. The forward formulas exist but no reverse method is implemented.
- **File**: `Reppo/Data/Enums/E1RMFormula.swift` (MODIFY)
- **Parallel?**: Yes — independent file, no dependencies.

**Steps**:

1. Open `Reppo/Data/Enums/E1RMFormula.swift` and read the existing `calculate(weight:reps:)` method.

2. Add a new method to the `E1RMFormula` enum:
   ```swift
   /// Reverse-calculates estimated weight for a given rep count from an e1RM value.
   /// For reps <= 1, returns the e1RM unchanged (1RM = e1RM by definition).
   func reverseCalculate(e1RM: Double, reps: Int) -> Double {
       guard reps > 1 else { return e1RM }
       let r = Double(reps)
       switch self {
       case .epley:
           return e1RM / (1.0 + r / 30.0)
       case .brzycki:
           return e1RM * (37.0 - r) / 36.0
       case .lombardi:
           return e1RM / pow(r, 0.10)
       }
   }
   ```

3. Verify the math is correct by cross-referencing with the forward formulas:
   - Epley forward: `weight × (1 + reps/30)` → reverse: `e1RM / (1 + reps/30)` ✓
   - Brzycki forward: `weight × 36 / (37 - reps)` → reverse: `e1RM × (37 - reps) / 36` ✓
   - Lombardi forward: `weight × reps^0.10` → reverse: `e1RM / reps^0.10` ✓

**Edge cases**:
- `reps = 0` → returns `e1RM` (guard clause)
- `reps = 1` → returns `e1RM` (1RM = e1RM)
- `reps = 37` with Brzycki → returns `e1RM × 0 / 36 = 0` (this is mathematically correct — Brzycki formula breaks down at very high rep counts; this is a known limitation)

**Validation**:
- [ ] `reverseCalculate(e1RM: 100, reps: 1)` returns `100.0` for all formulas
- [ ] For Epley: `reverseCalculate(e1RM: 126.67, reps: 8)` ≈ `100.0` (matching forward: `100 × (1 + 8/30) = 126.67`)
- [ ] Method exists on all three enum cases

---

### Subtask T003 – Create ExerciseInfoProvider.swift

- **Purpose**: Implement the computation engine that fetches exercise history once and derives all three card models. This is the core business logic of the feature.
- **File**: `Reppo/Features/Workout/ViewModels/ExerciseInfoProvider.swift` (NEW)
- **Parallel?**: No — depends on T001 (data types) and T002 (reverse formula).

**Steps**:

1. Create the file. Define `ExerciseInfoProvider` as an enum with static methods (no instances needed):

   ```swift
   import Foundation

   enum ExerciseInfoProvider {
       static func compute(
           currentSets: [WorkoutSet],
           exerciseId: UUID,
           currentWorkoutId: UUID,
           trackingType: TrackingType,
           weightIncrement: Double?,
           setService: SetService,
           statsService: StatsService,
           healthProfileRepo: HealthProfileRepository
       ) async throws -> ExerciseInfoData
   }
   ```

2. **Inside `compute()`** — Step 1: Fetch and prepare data:
   - Call `setService.fetchSets(for: exerciseId, limit: nil)` to get ALL historical sets (single DB query).
   - Filter to `historicalSets = allSets.filter { $0.workoutId != currentWorkoutId }`.
   - Fetch health profile: `let profile = try healthProfileRepo.fetchOrCreate()`.
   - Resolve formula: `let formula = E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley`.

3. **Step 2: Determine tracking type visibility**:
   - `let supportsE1RM = trackingType == .weightReps || trackingType == .weightRepsDuration`
   - If `!supportsE1RM`, set `e1RMInfo = nil` and `estimatedRepsInfo = nil`.

4. **Step 3: Compute E1RM info** (only if `supportsE1RM`):
   - Filter today's working sets: `currentSets.filter { $0.setType == .working && $0.hasData && $0.e1RM != nil }`.
   - Find best today: `.max(by: { ($0.e1RM ?? 0) < ($1.e1RM ?? 0) })`.
   - If no best today, fallback: `try await statsService.fetchStats(for: exerciseId)?.bestE1RM`.
   - If still nil, `e1RMInfo = nil`.
   - **Historical comparison**: Find the best e1RM from ~4 weeks ago:
     - Target date = `Calendar.current.date(byAdding: .day, value: -28, to: Date())!`
     - Window: filter historical sets where `date` is between `target - 7 days` and `target + 7 days` (21–35 days ago).
     - Take `max e1RM` from that window.
     - If window empty, fall back to nearest available historical e1RM (closest date before today, excluding current workout).
     - Compute delta using `toGrams()` for precision:
       ```swift
       let deltaGrams = UnitConversion.toGrams(currentE1RM) - UnitConversion.toGrams(historicalE1RM)
       let delta = Double(deltaGrams) / 1000.0
       let trend: Trend = deltaGrams > 0 ? .positive : deltaGrams < 0 ? .negative : .neutral
       ```
     - Compute `historicalWeeksAgo`: `Calendar.current.dateComponents([.weekOfYear], from: historicalDate, to: Date()).weekOfYear ?? 4`.

5. **Step 4: Compute Last Workout info**:
   - Group `historicalSets` by `workoutId`: `Dictionary(grouping: historicalSets) { $0.workoutId }`.
   - Sort groups by date descending (use first set's date in each group).
   - Take the first group = last workout.
   - If no groups exist → `lastWorkoutInfo = nil`.
   - Filter that group's sets: `setType == .working && hasData`.
   - Sort by `effectiveWeight` descending, take top 2.
   - Format each as `TopSet`:
     - For weight/reps: `"\(formatWeight(set.effectiveWeight!))×\(set.reps!)"`.
     - For duration: `UnitConversion.formatDuration(set.durationSeconds!)`.
   - Compute `daysAgo` and `relativeTimeLabel`:
     ```swift
     let daysAgo = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
     let formatter = RelativeDateTimeFormatter()
     formatter.unitsStyle = .full
     let relativeTimeLabel = formatter.localizedString(for: lastDate, relativeTo: Date())
     ```

6. **Step 5: Compute Estimated Reps info** (only if `supportsE1RM`):
   - Find the most recent working set's rep count: `currentSets.last(where: { $0.setType == .working && $0.hasData })?.reps ?? 8`.
   - Use best available e1RM (current session or ExerciseStats fallback).
   - If no e1RM available → `estimatedRepsInfo = nil`.
   - Reverse calculate: `formula.reverseCalculate(e1RM: bestE1RM, reps: targetReps)`.
   - Snap to nearest increment: `snap(estimatedWeight, to: weightIncrement ?? 2.5)`.
   - Implement snap helper:
     ```swift
     private static func snap(_ value: Double, to increment: Double) -> Double {
         guard increment > 0 else { return value }
         return (value / increment).rounded() * increment
     }
     ```

7. **Step 6: Assemble and return** `ExerciseInfoData`:
   ```swift
   return ExerciseInfoData(
       e1RMInfo: e1RMInfo,
       lastWorkoutInfo: lastWorkoutInfo,
       estimatedRepsInfo: estimatedRepsInfo,
       trackingType: trackingType
   )
   ```

**Edge cases to handle**:
- No completed sets in current workout → e1RM falls back to `ExerciseStats.bestE1RM`
- No historical data at all → all optional fields are `nil`
- Duration-based exercise → `e1RMInfo = nil`, `estimatedRepsInfo = nil`
- Exercise performed only once (current session is the first) → Last Workout = nil
- Bodyweight exercises → `effectiveWeight` already includes bodyweight factor (no special handling needed)

**Validation**:
- [ ] Single `fetchSets` call for all computation (performance: < 500ms)
- [ ] Weight comparisons use `toGrams()` per constitution
- [ ] Working sets only (`setType == .working && hasData`) for all calculations
- [ ] Duration exercises return `nil` for e1RM and estimated reps
- [ ] Empty states handled gracefully (no crashes on nil data)

## Risks & Mitigations

- **Risk**: `fetchSets` returns thousands of sets for popular exercises → **Mitigation**: In-memory filtering is fast (< 10ms). The bottleneck is the DB query (~50-200ms), which is within the 500ms budget.
- **Risk**: `RelativeDateTimeFormatter` output varies by locale → **Mitigation**: Acceptable — iOS handles localization automatically.
- **Risk**: Calendar date math edge cases (DST, timezone) → **Mitigation**: Use `Calendar.current` consistently; comparison window (±7 days) is wide enough to absorb day-boundary issues.

## Definition of Done Checklist

- [ ] `ExerciseInfoData.swift` created with all value types
- [ ] `E1RMFormula.reverseCalculate(e1RM:reps:)` added and correct
- [ ] `ExerciseInfoProvider.compute()` handles all tracking types
- [ ] Empty states return `nil` gracefully (no crashes)
- [ ] Historical comparison uses `toGrams()` precision
- [ ] Single `fetchSets` call powers all three cards
- [ ] Duration exercises hide e1RM and estimated reps data

## Review Guidance

- Verify `ExerciseInfoProvider.compute()` makes exactly ONE `fetchSets` call (performance).
- Verify all weight comparisons go through `toGrams()` (constitution compliance).
- Verify `setType == .working && hasData` filtering is applied everywhere.
- Verify `trackingType` correctly gates e1RM and estimated reps data.
- Check that `snap()` rounds correctly to `weightIncrement`.

## Activity Log

- 2026-03-01T19:53:31Z – system – lane=planned – Prompt created.
- 2026-03-01T20:03:34Z – claude_opus –shell_pid=76595 – lane=doing – Started implementation via workflow command
- 2026-03-01T20:11:19Z – claude_opus –shell_pid=76595 – lane=for_review – Ready for review: ExerciseInfoData value types, E1RMFormula.reverseCalculate, ExerciseInfoProvider compute engine. Build succeeds cleanly.
- 2026-03-01T20:23:26Z – claude_opus –shell_pid=80100 – lane=doing – Started review via workflow command
- 2026-03-01T20:27:35Z – claude_opus –shell_pid=80100 – lane=done – Review passed: All 3 files match spec exactly. ExerciseInfoData value types are correct (Sendable, Identifiable, pure structs). reverseCalculate math verified against forward formulas. ExerciseInfoProvider uses single fetchSets call, toGrams() for weight comparison, working+hasData filtering everywhere, correct tracking type gating. Build clean.
