---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
title: "PRService Protocol + Repository Update"
phase: "Phase 0 - Foundation"
lane: "planned"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
dependencies: []
history:
  - timestamp: "2026-02-22T20:46:52Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP01 – PRService Protocol + Repository Update

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

- Create `PRServiceProtocol` with all method signatures matching the contract in `kitty-specs/003-pr-service/contracts/PRServiceProtocol.swift`
- Create `PREvaluationResult` and `PRTableEntry` as `Sendable` structs
- Add `fetchBestEligibleSet()` to `SetRepositoryProtocol` and implement it in `SetRepository`
- All new files compile with zero errors
- No SwiftData import in the protocol file

## Context & Constraints

- **Constitution**: `.kittify/memory/constitution.md` — services never access ModelContext directly; repositories are the data access layer
- **Plan**: `kitty-specs/003-pr-service/plan.md` — PRService is a plain actor composing repositories
- **Contract**: `kitty-specs/003-pr-service/contracts/PRServiceProtocol.swift` — source of truth for method signatures
- **Data model**: `kitty-specs/003-pr-service/data-model.md` — entity interaction map
- **Existing code**: `Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift` and `Reppo/Core/Repositories/SetRepository.swift` — to be updated
- **Architecture**: Services live in `Reppo/Core/Services/`, protocols in `Reppo/Core/Services/Protocols/`

## Subtasks & Detailed Guidance

### Subtask T001 – Create PREvaluationResult and PRTableEntry value types

- **Purpose**: Define the lightweight value types returned by PRService methods. These are `Sendable` structs that safely cross actor boundaries, carrying evaluation results back to callers.
- **Steps**:
  1. Create directory `Reppo/Core/Services/Protocols/` if it doesn't exist
  2. Create file `Reppo/Core/Services/Protocols/PRServiceProtocol.swift`
  3. Define `PREvaluationResult` struct:
     ```swift
     struct PREvaluationResult: Sendable {
         let setId: UUID
         let newStatus: CachedPRStatus?
         let affectedSetIds: [UUID: CachedPRStatus?]
         let prRecordChanged: Bool
     }
     ```
  4. Define `PRTableEntry` struct:
     ```swift
     struct PRTableEntry: Sendable {
         let reps: Int
         let value: Double
         let setId: UUID
         let date: Date
     }
     ```
- **Files**: `Reppo/Core/Services/Protocols/PRServiceProtocol.swift` (new file)
- **Parallel?**: Yes — independent of T003/T004
- **Notes**: Import `Foundation` only. Reference `CachedPRStatus` from `Reppo/Data/Enums/`. Both structs must be `Sendable`.

### Subtask T002 – Create PRServiceProtocol

- **Purpose**: Define the complete contract for the PR service. All method signatures must match the contract file exactly.
- **Steps**:
  1. In the same file as T001 (`Reppo/Core/Services/Protocols/PRServiceProtocol.swift`), add the protocol below the struct definitions
  2. Copy method signatures from `kitty-specs/003-pr-service/contracts/PRServiceProtocol.swift`
  3. Protocol must conform to `Sendable`
  4. All methods must be `async throws`
  5. Methods to include:
     - `evaluate(setId:exerciseId:reps:effectiveWeight:workoutId:setType:hasData:excludeFromPRs:date:)` → `PREvaluationResult`
     - `evaluateAfterEdit(setId:exerciseId:reps:effectiveWeight:workoutId:setType:hasData:excludeFromPRs:previousCachedPRStatus:date:)` → `PREvaluationResult`
     - `handleDeletion(setId:exerciseId:reps:cachedPRStatus:)` → `PREvaluationResult`
     - `fetchPRTable(for exerciseId:)` → `[PRTableEntry]`
     - `rebuildAll()` → Void
     - `rebuild(for exerciseId:)` → Void
- **Files**: `Reppo/Core/Services/Protocols/PRServiceProtocol.swift` (same file as T001)
- **Parallel?**: Yes — same file as T001 but logically independent
- **Notes**: The contract file has full documentation comments — include them in the protocol. Reference types: `UUID`, `Double`, `Int`, `Date`, `SetType`, `CachedPRStatus`, `PREvaluationResult`, `PRTableEntry`. Do NOT import SwiftData.

### Subtask T003 – Add fetchBestEligibleSet to SetRepositoryProtocol

- **Purpose**: The PR pipeline needs to find the best eligible set for an exercise/reps combination during recomputation (specdoc S7.2 edit/delete paths). This method filters by eligibility criteria at the repository level.
- **Steps**:
  1. Open `Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift`
  2. Add new method to the protocol:
     ```swift
     /// Fetch the best eligible set for PR candidacy.
     /// Filters: hasData = true, excludeFromPRs = false, eligible setTypes.
     /// Sorted by effectiveWeight DESC, date ASC (earliest-highest wins).
     /// Optional excludingSetId to skip the deleted/edited set.
     func fetchBestEligibleSet(
         for exerciseId: UUID,
         reps: Int,
         excludeWarmups: Bool,
         excludingSetId: UUID?
     ) async throws -> WorkoutSet?
     ```
  3. Add documentation comment explaining the purpose (PR recomputation after edit/delete)
- **Files**: `Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift` (existing file, add method)
- **Parallel?**: Yes — independent of T001/T002
- **Notes**: Keep `Sendable` conformance on the protocol. The `excludeWarmups` parameter is needed because warmup eligibility depends on the `includeWarmupsInPRs` setting which PRService reads.

### Subtask T004 – Implement fetchBestEligibleSet in SetRepository

- **Purpose**: Implement the eligible-set query that the PR pipeline uses for recomputation. Due to SwiftData `#Predicate` limitations with complex conditionals, use a two-step approach: database predicate for exerciseId+reps, then Swift filtering for eligibility.
- **Steps**:
  1. Open `Reppo/Core/Repositories/SetRepository.swift`
  2. Implement `fetchBestEligibleSet()`:
     ```swift
     func fetchBestEligibleSet(
         for exerciseId: UUID,
         reps: Int,
         excludeWarmups: Bool,
         excludingSetId: UUID?
     ) throws -> WorkoutSet? {
         // Step 1: Fetch all sets for exerciseId + reps (database-level filter)
         let descriptor = FetchDescriptor<WorkoutSet>(
             predicate: #Predicate {
                 $0.exerciseId == exerciseId && $0.reps == reps
             },
             sortBy: [
                 SortDescriptor(\.effectiveWeight, order: .reverse),
                 SortDescriptor(\.date, order: .forward)
             ]
         )
         let sets = try modelContext.fetch(descriptor)

         // Step 2: Filter in Swift for eligibility (Predicate limitations)
         return sets.first { set in
             // Must have data
             guard set.hasData else { return false }
             // Must not be explicitly excluded
             guard set.excludeFromPRs != true else { return false }
             // Partial sets always excluded
             guard set.setType != .partial else { return false }
             // Warmup exclusion (configurable)
             if excludeWarmups && set.setType == .warmup { return false }
             // Exclude specific set (deleted/edited)
             if let excludeId = excludingSetId, set.id == excludeId { return false }
             return true
         }
     }
     ```
  3. Note: Inside the actor, the method omits `async` — Swift bridges it to async at the call site
  4. The sort order (effectiveWeight DESC, date ASC) ensures earliest-highest wins per specdoc S4.2
- **Files**: `Reppo/Core/Repositories/SetRepository.swift` (existing file, add method)
- **Parallel?**: No — depends on T003 (protocol method must exist)
- **Notes**:
  - The post-fetch filter is acceptable because the exerciseId+reps predicate already reduces to a small set (typically <100 rows for any given exercise/rep count)
  - SwiftData `#Predicate` does not support `!= true` for optionals easily — the Swift filter handles this cleanly
  - `hasData` is a computed property on WorkoutSet — it works in Swift filtering but NOT in `#Predicate` (computed properties can't be used in SwiftData predicates)

## Risks & Mitigations

- **`#Predicate` limitation**: Complex eligibility filters can't all go in the database predicate. Mitigation: two-step approach (database for exerciseId+reps, Swift for eligibility). The pre-filtered set is small.
- **`hasData` is computed**: SwiftData predicates don't support computed properties. Mitigation: filter in Swift after fetch. The computation is trivial (check a few optional fields).
- **Protocol file location**: `Reppo/Core/Services/Protocols/` directory may not exist. Create it.

## Definition of Done Checklist

- [ ] `Reppo/Core/Services/Protocols/PRServiceProtocol.swift` exists with PREvaluationResult, PRTableEntry, and PRServiceProtocol
- [ ] All method signatures match `kitty-specs/003-pr-service/contracts/PRServiceProtocol.swift`
- [ ] `SetRepositoryProtocol` has `fetchBestEligibleSet()` method
- [ ] `SetRepository` implements `fetchBestEligibleSet()` with correct filtering and sorting
- [ ] Project compiles with zero errors
- [ ] No SwiftData import in the protocol file
- [ ] `tasks.md` updated with status change

## Review Guidance

- Verify PRServiceProtocol method signatures match the contract file exactly
- Verify PREvaluationResult and PRTableEntry are Sendable
- Verify fetchBestEligibleSet sort order: effectiveWeight DESC, date ASC (earliest-highest wins)
- Verify eligibility filtering: hasData, excludeFromPRs, partial (always), warmup (configurable)
- Verify excludingSetId is respected in the filter

## Activity Log

- 2026-02-22T20:46:52Z – system – lane=planned – Prompt created.
