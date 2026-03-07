---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
  - "T005"
title: "Value Types + Service Protocols"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "58978"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: []
history:
  - timestamp: "2026-02-23T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
  - timestamp: "2026-02-24T10:00:00Z"
    lane: "doing"
    agent: "claude-opus"
    shell_pid: "58978"
    action: "Implementation started"
  - timestamp: "2026-02-24T10:30:00Z"
    lane: "done"
    agent: "claude"
    shell_pid: ""
    action: "Review passed: approved by Magnus Espensen"
---

# Work Package Prompt: WP01 – Value Types + Service Protocols

## Implementation Command

No dependencies — start from main:
```bash
spec-kitty implement WP01
```

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback, update `review_status: acknowledged`.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- Create `SetAggregateResult` struct (Sendable) for Core Data aggregation results
- Create `StatsUpdateEvent` enum (Sendable) with `.save`, `.edit`, `.delete` cases and associated values
- Create `SetSaveResult` struct (Sendable) for SetService return type
- Create `StatsServiceProtocol` with all method signatures matching `kitty-specs/004-set-and-stats-services/contracts/StatsServiceProtocol.swift`
- Create `SetServiceProtocol` with all method signatures matching `kitty-specs/004-set-and-stats-services/contracts/SetServiceProtocol.swift`
- All new files compile with zero errors
- No SwiftData import in protocol files

## Context & Constraints

- **Plan**: `kitty-specs/004-set-and-stats-services/plan.md` — both services are plain actors composing repositories
- **Contracts**: `kitty-specs/004-set-and-stats-services/contracts/SetServiceProtocol.swift` and `contracts/StatsServiceProtocol.swift` — source of truth for method signatures
- **Data model**: `kitty-specs/004-set-and-stats-services/data-model.md` — entity interaction map
- **Existing code**: `Reppo/Core/Services/Protocols/` directory may already exist from feature 003 (PRServiceProtocol). If not, create it.
- **Cross-reference**: `SetSaveResult` references `PREvaluationResult` from `Reppo/Core/Services/Protocols/PRServiceProtocol.swift` — this type must be accessible (same module, no import needed)
- **Architecture**: Services live in `Reppo/Core/Services/`, protocols in `Reppo/Core/Services/Protocols/`

## Subtasks & Detailed Guidance

### Subtask T001 – Create SetAggregateResult value type

- **Purpose**: Return type for the Core Data `NSExpression` aggregation query used by `StatsService.rebuildAll()`. Contains database-computed totals that avoid loading sets into memory (specdoc S8.6).
- **Steps**:
  1. Create file `Reppo/Core/Services/Protocols/StatsServiceProtocol.swift` (or add to it if it exists)
  2. Define at the top of the file, before the protocol:
     ```swift
     /// Result of Core Data NSExpression aggregation for rebuildAll().
     /// All values computed at the database level — no Swift iteration (specdoc S8.6).
     struct SetAggregateResult: Sendable {
         let totalSets: Int
         let totalReps: Int
         let totalVolume: Double   // SUM(effectiveWeight * reps)
         let maxWeight: Double     // MAX(effectiveWeight)
         let lastPerformedDate: Date?  // MAX(date)
     }
     ```
- **Files**: `Reppo/Core/Services/Protocols/StatsServiceProtocol.swift` (new file)
- **Parallel?**: Yes — independent of T003
- **Notes**: Import `Foundation` only. The struct is intentionally simple — it carries database aggregation results across actor boundaries.

### Subtask T002 – Create StatsUpdateEvent enum

- **Purpose**: Describes what triggered a stats update, carrying the data needed for incremental arithmetic adjustments. The enum's associated values provide all information StatsService needs without querying the database.
- **Steps**:
  1. In the same file as T001 (`Reppo/Core/Services/Protocols/StatsServiceProtocol.swift`), define:
     ```swift
     /// Describes what triggered a stats update, carrying data for incremental adjustments.
     enum StatsUpdateEvent: Sendable {
         /// A new set was saved.
         case save(
             reps: Int,
             effectiveWeight: Double,
             setType: SetType,
             hasData: Bool,
             date: Date,
             workoutId: UUID
         )

         /// A set was edited. Carries old and new values for delta computation.
         case edit(
             oldReps: Int, oldEffectiveWeight: Double, oldSetType: SetType, oldHasData: Bool,
             newReps: Int, newEffectiveWeight: Double, newSetType: SetType, newHasData: Bool,
             date: Date, workoutId: UUID
         )

         /// A set was deleted.
         case delete(
             reps: Int,
             effectiveWeight: Double,
             setType: SetType,
             hasData: Bool,
             date: Date,
             workoutId: UUID
         )
     }
     ```
  2. Note: `SetType` is from `Reppo/Data/Enums/SetType.swift` — no import needed (same module)
- **Files**: `Reppo/Core/Services/Protocols/StatsServiceProtocol.swift` (same file as T001)
- **Parallel?**: Yes — can be written alongside T001
- **Notes**: All associated values are value types (Int, Double, Date, UUID) or Sendable enums (SetType). The whole enum is Sendable.

### Subtask T003 – Create SetSaveResult value type

- **Purpose**: Return type from `SetService.save()` and `SetService.edit()`. Carries the computed effectiveWeight and PR evaluation result back to the caller for UI updates.
- **Steps**:
  1. Create file `Reppo/Core/Services/Protocols/SetServiceProtocol.swift`
  2. Define at the top of the file:
     ```swift
     /// Result of a set save operation.
     /// Contains the computed effectiveWeight and PR evaluation result
     /// so the caller can update UI optimistically.
     struct SetSaveResult: Sendable {
         /// The saved set's ID.
         let setId: UUID
         /// The computed effectiveWeight (specdoc S5.4).
         let effectiveWeight: Double
         /// PR evaluation result from PRService.
         let prResult: PREvaluationResult
     }
     ```
  3. `PREvaluationResult` is defined in `Reppo/Core/Services/Protocols/PRServiceProtocol.swift` — accessible from the same module without import
- **Files**: `Reppo/Core/Services/Protocols/SetServiceProtocol.swift` (new file)
- **Parallel?**: Yes — different file from T001/T002
- **Notes**: If `PRServiceProtocol.swift` does not exist yet (feature 003 not merged), the project won't compile until 003 is available. This is expected — SetSaveResult references PREvaluationResult intentionally.

### Subtask T004 – Create StatsServiceProtocol

- **Purpose**: Define the complete contract for the stats service. All method signatures must match the contract file.
- **Steps**:
  1. In the same file as T001/T002 (`Reppo/Core/Services/Protocols/StatsServiceProtocol.swift`), add the protocol below the type definitions
  2. Copy method signatures from `kitty-specs/004-set-and-stats-services/contracts/StatsServiceProtocol.swift`
  3. Protocol must conform to `Sendable`
  4. All methods must be `async throws`
  5. Methods to include:
     - `updateStats(for exerciseId: UUID, event: StatsUpdateEvent) async throws`
     - `rebuildAll() async throws`
     - `rebuild(for exerciseId: UUID) async throws`
  6. Include documentation comments from the contract file
- **Files**: `Reppo/Core/Services/Protocols/StatsServiceProtocol.swift` (same file as T001/T002)
- **Parallel?**: No — must follow T001/T002 (references their types)
- **Notes**: The protocol references `StatsUpdateEvent` and `SetAggregateResult` which are defined above in the same file. Do NOT import SwiftData.

### Subtask T005 – Create SetServiceProtocol

- **Purpose**: Define the complete contract for the set service. All method signatures must match the contract file.
- **Steps**:
  1. In the same file as T003 (`Reppo/Core/Services/Protocols/SetServiceProtocol.swift`), add the protocol below SetSaveResult
  2. Copy method signatures from `kitty-specs/004-set-and-stats-services/contracts/SetServiceProtocol.swift`
  3. Protocol must conform to `Sendable`
  4. All methods must be `async throws`
  5. Methods to include:
     - `save(_ set: WorkoutSet) async throws -> SetSaveResult`
     - `edit(_ set: WorkoutSet) async throws -> SetSaveResult`
     - `delete(_ set: WorkoutSet) async throws`
  6. Include documentation comments from the contract file
  7. **IMPORTANT**: The protocol methods accept `WorkoutSet` — this is intentional. SetService receives the WorkoutSet from the caller's ModelContext. Since SetService is a plain actor (not @ModelActor), it will need to extract primitive values and re-fetch via repositories internally. The protocol API is clean; the implementation handles the cross-actor concern.
- **Files**: `Reppo/Core/Services/Protocols/SetServiceProtocol.swift` (same file as T003)
- **Parallel?**: No — must follow T003 (references SetSaveResult)
- **Notes**: The protocol references `WorkoutSet` (from `Reppo/Data/Models/`), `SetSaveResult` (from same file), and `PREvaluationResult` (from PRServiceProtocol). All same module — no imports needed beyond Foundation.

## Risks & Mitigations

- **PREvaluationResult dependency**: SetSaveResult references PREvaluationResult from feature 003's PRServiceProtocol. If 003 isn't merged yet, this file won't compile. This is expected and acceptable — feature 004 depends on 003's protocol.
- **File organization**: All value types and protocols for a service go in the same file (e.g., `StatsServiceProtocol.swift` contains SetAggregateResult + StatsUpdateEvent + StatsServiceProtocol). This matches the pattern from feature 003.
- **WorkoutSet in protocol**: Passing @Model objects in protocol methods is a design choice. The implementation will handle actor isolation internally by extracting UUIDs/values. The protocol keeps a clean public API.

## Definition of Done Checklist

- [ ] `Reppo/Core/Services/Protocols/StatsServiceProtocol.swift` exists with SetAggregateResult, StatsUpdateEvent, and StatsServiceProtocol
- [ ] `Reppo/Core/Services/Protocols/SetServiceProtocol.swift` exists with SetSaveResult and SetServiceProtocol
- [ ] All method signatures match contract files in `kitty-specs/004-set-and-stats-services/contracts/`
- [ ] All value types are Sendable
- [ ] Both protocols conform to Sendable
- [ ] Project compiles with zero errors (assuming PRServiceProtocol exists)
- [ ] No SwiftData import in protocol files

## Review Guidance

- Verify StatsServiceProtocol method signatures match the contract file exactly
- Verify SetServiceProtocol method signatures match the contract file exactly
- Verify all value types are Sendable structs/enums
- Verify StatsUpdateEvent cases carry all necessary associated values for incremental computation
- Verify SetSaveResult references PREvaluationResult correctly
- Verify no SwiftData imports in protocol files

## Activity Log

- 2026-02-23T12:00:00Z – system – lane=planned – Prompt created.
- 2026-02-24T09:06:20Z – claude-opus – shell_pid=58162 – lane=doing – Started implementation via workflow command
- 2026-02-24T09:08:18Z – claude-opus – shell_pid=58162 – lane=for_review – Ready for review: StatsServiceProtocol.swift and SetServiceProtocol.swift with all value types and protocols. Build succeeds with zero errors.
- 2026-02-24T09:09:14Z – claude-opus – shell_pid=58978 – lane=doing – Started review via workflow command
- 2026-02-24T09:09:45Z – claude-opus – shell_pid=58978 – lane=done – Review passed: All value types Sendable, method signatures match contracts exactly, zero build errors, no SwiftData imports. Clean implementation.
- 2026-02-24T10:41:02Z – claude – shell_pid=58978 – lane=done – Re-accept: WP01 previously approved by Magnus Espensen
