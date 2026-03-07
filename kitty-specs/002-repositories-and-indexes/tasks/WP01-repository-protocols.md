---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
  - "T005"
  - "T006"
  - "T007"
  - "T008"
  - "T009"
title: "Repository Protocols + SetSortOrder Enum"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: "claude"
agent: "claude"
shell_pid: "0"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: []
history:
  - timestamp: "2026-02-20T12:32:56Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP01 – Repository Protocols + SetSortOrder Enum

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Implementation Command

```bash
spec-kitty implement WP01
```

No dependencies — this is the starting package.

---

## Objectives & Success Criteria

- Create all 8 repository protocol files defining the complete data-access contract for the app
- Create the `SetSortOrder` supporting enum
- All files compile without errors
- No protocol file imports SwiftData — protocols use Foundation types and reference existing @Model types
- Every method signature matches the contracts in `kitty-specs/002-repositories-and-indexes/contracts/`
- All protocols conform to `Sendable`
- All methods are `async throws`

**Success Criteria (from spec)**:
- SC-001: Every SwiftData model has a corresponding repository protocol
- SC-005: All repository methods compile and follow async/await patterns

---

## Context & Constraints

**Architecture**: MVVM with Service + Repository layers. This WP builds the protocol contract that sits between Services and Repositories.

**Key architectural rules**:
- Only the Repository layer touches SwiftData/ModelContext (AGENT_RULES Section 2)
- Protocols define the contract; Services program against protocols, not concrete types
- Protocols are `Sendable` because repository actors will be passed across concurrency boundaries

**Reference documents**:
- `kitty-specs/002-repositories-and-indexes/plan.md` — Full protocol signatures and design decisions
- `kitty-specs/002-repositories-and-indexes/contracts/` — Source of truth for method signatures
- `kitty-specs/002-repositories-and-indexes/data-model.md` — Entity-to-repository mapping
- `.kittify/memory/constitution.md` — Non-negotiable architecture principles

**File location**: All files go in `Reppo/Core/Repositories/Protocols/`

**Import rule**: Protocol files should import `Foundation` only. They reference @Model types (WorkoutSet, Workout, etc.) as parameter/return types. These types are defined in the same module, so Swift resolves them without needing `import SwiftData` in the protocol file. **If the compiler requires `import SwiftData`**, add it with a comment: `// Required for @Model type visibility, not for ModelContext usage`.

---

## Subtasks & Detailed Guidance

### Subtask T001 – Create SetSortOrder Enum

**Purpose**: Define the sort order options used by `SetRepositoryProtocol.fetchSets(for:reps:orderedBy:)`. This enum is needed before the protocol that references it.

**Steps**:
1. Create file `Reppo/Core/Repositories/Protocols/SetSortOrder.swift`
2. Define enum with 3 cases:
   ```swift
   import Foundation

   enum SetSortOrder: Sendable {
       case effectiveWeightDesc
       case dateAsc
       case dateDesc
   }
   ```

**Files**: `Reppo/Core/Repositories/Protocols/SetSortOrder.swift` (new, ~10 lines)
**Parallel?**: Yes — no dependencies.

---

### Subtask T002 – Create SetRepositoryProtocol

**Purpose**: Define the data-access contract for WorkoutSet — the most complex repository with CRUD, workout/exercise queries, and aggregation methods (FR-004, FR-009).

**Steps**:
1. Create file `Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift`
2. Import `Foundation` only
3. Define protocol conforming to `Sendable`
4. Add all method signatures from the contract file `kitty-specs/002-repositories-and-indexes/contracts/SetRepositoryProtocol.swift`

**Required methods** (from contracts + data-model.md):

```swift
protocol SetRepositoryProtocol: Sendable {
    // CRUD
    func save(_ set: WorkoutSet) async throws
    func delete(_ set: WorkoutSet) async throws
    func fetch(byId id: UUID) async throws -> WorkoutSet?

    // Workout queries
    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]

    // Exercise queries (FR-004)
    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet]
    func fetchSets(for exerciseId: UUID, reps: Int, orderedBy: SetSortOrder) async throws -> [WorkoutSet]

    // Aggregation (FR-009)
    func fetchMaxEffectiveWeight(for exerciseId: UUID, reps: Int) async throws -> Double?

    // Note: No fetchTotalVolume — SwiftData has no native SUM.
    // Callers read ExerciseStats.totalVolume (pre-computed at write-time by StatsService).
}
```

**Files**: `Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift` (new, ~30 lines)
**Parallel?**: Yes — depends only on T001 (SetSortOrder), but both are simple and can be created together.
**Notes**: `fetchMaxEffectiveWeight` returns `Double?` (nil if no matching sets). Total volume is read from `ExerciseStats.totalVolume` (pre-computed), not from SetRepository.

---

### Subtask T003 – Create WorkoutRepositoryProtocol

**Purpose**: Define the data-access contract for Workout entity — includes special `fetchInProgress()` method for resuming active workouts at app launch (AGENT_RULES S7.3).

**Steps**:
1. Create file `Reppo/Core/Repositories/Protocols/WorkoutRepositoryProtocol.swift`
2. Define protocol from contract file

**Required methods**:
```swift
protocol WorkoutRepositoryProtocol: Sendable {
    func save(_ workout: Workout) async throws
    func delete(_ workout: Workout) async throws
    func fetch(byId id: UUID) async throws -> Workout?
    func fetchInProgress() async throws -> Workout?
    func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout]
    func fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout]
}
```

**Files**: `Reppo/Core/Repositories/Protocols/WorkoutRepositoryProtocol.swift` (new, ~20 lines)
**Parallel?**: Yes
**Notes**: `fetchInProgress` returns the single active workout (status == .inProgress) or nil. `fetchWorkouts(for dateRange:)` is used by Calendar tab.

---

### Subtask T004 – Create ExerciseRepositoryProtocol

**Purpose**: Define the data-access contract for Exercise entity — includes name search and `hasAssociatedSets` check for trackingType immutability (AGENT_RULES S3.5).

**Steps**:
1. Create file `Reppo/Core/Repositories/Protocols/ExerciseRepositoryProtocol.swift`
2. Define protocol from contract file

**Required methods**:
```swift
protocol ExerciseRepositoryProtocol: Sendable {
    func save(_ exercise: Exercise) async throws
    func delete(_ exercise: Exercise) async throws
    func fetch(byId id: UUID) async throws -> Exercise?
    func fetchAll() async throws -> [Exercise]
    func search(name: String) async throws -> [Exercise]
    func hasAssociatedSets(_ exerciseId: UUID) async throws -> Bool
}
```

**Files**: `Reppo/Core/Repositories/Protocols/ExerciseRepositoryProtocol.swift` (new, ~20 lines)
**Parallel?**: Yes
**Notes**: `hasAssociatedSets` is a cross-entity query (queries WorkoutSet table). Used to prevent changing `trackingType` on exercises that have sets.

---

### Subtask T005 – Create ExerciseStatsRepositoryProtocol

**Purpose**: Define the data-access contract for ExerciseStats — the pre-computed aggregate cache updated at write-time by StatsService.

**Steps**:
1. Create file `Reppo/Core/Repositories/Protocols/ExerciseStatsRepositoryProtocol.swift`
2. Define protocol from contract file

**Required methods**:
```swift
protocol ExerciseStatsRepositoryProtocol: Sendable {
    func save(_ stats: ExerciseStats) async throws
    func delete(_ stats: ExerciseStats) async throws
    func fetch(for exerciseId: UUID) async throws -> ExerciseStats?
    func fetchAll() async throws -> [ExerciseStats]
}
```

**Files**: `Reppo/Core/Repositories/Protocols/ExerciseStatsRepositoryProtocol.swift` (new, ~15 lines)
**Parallel?**: Yes

---

### Subtask T006 – Create PerformanceRecordRepositoryProtocol

**Purpose**: Define the data-access contract for PerformanceRecord — the consolidated PR table. Includes the critical (exerciseId, recordType, reps) lookup used on every set save (FR-005).

**Steps**:
1. Create file `Reppo/Core/Repositories/Protocols/PerformanceRecordRepositoryProtocol.swift`
2. Define protocol from contract file

**Required methods**:
```swift
protocol PerformanceRecordRepositoryProtocol: Sendable {
    func save(_ record: PerformanceRecord) async throws
    func delete(_ record: PerformanceRecord) async throws
    func fetch(exerciseId: UUID, recordType: RecordType, reps: Int?) async throws -> PerformanceRecord?
    func fetchAll(for exerciseId: UUID) async throws -> [PerformanceRecord]
    func fetchAll(for exerciseId: UUID, recordType: RecordType) async throws -> [PerformanceRecord]
}
```

**Files**: `Reppo/Core/Repositories/Protocols/PerformanceRecordRepositoryProtocol.swift` (new, ~20 lines)
**Parallel?**: Yes
**Notes**: `reps` parameter is `Int?` — nil for e1RM and maxVolume record types (they don't have a rep count). The predicate must handle both nil and non-nil reps correctly.

---

### Subtask T007 – Create BodyweightEntryRepositoryProtocol

**Purpose**: Define the data-access contract for BodyweightEntry — includes the `fetchClosest(to:healthProfileId:)` method needed for effectiveWeight calculation (FR-008).

**Steps**:
1. Create file `Reppo/Core/Repositories/Protocols/BodyweightEntryRepositoryProtocol.swift`
2. Define protocol from contract file

**Required methods**:
```swift
protocol BodyweightEntryRepositoryProtocol: Sendable {
    func save(_ entry: BodyweightEntry) async throws
    func delete(_ entry: BodyweightEntry) async throws
    func fetchAll(for healthProfileId: UUID) async throws -> [BodyweightEntry]
    func fetchClosest(to date: Date, healthProfileId: UUID) async throws -> BodyweightEntry?
}
```

**Files**: `Reppo/Core/Repositories/Protocols/BodyweightEntryRepositoryProtocol.swift` (new, ~15 lines)
**Parallel?**: Yes
**Notes**: `fetchClosest` returns the bodyweight entry with the smallest absolute time distance from the target date. Algorithm is in the implementation (WP02), not the protocol.

---

### Subtask T008 – Create HealthProfileRepositoryProtocol

**Purpose**: Define the data-access contract for HealthProfile — single-row local table with user settings. Includes `fetchOrCreate()` for guaranteed retrieval.

**Steps**:
1. Create file `Reppo/Core/Repositories/Protocols/HealthProfileRepositoryProtocol.swift`
2. Define protocol from contract file

**Required methods**:
```swift
protocol HealthProfileRepositoryProtocol: Sendable {
    func save(_ profile: HealthProfile) async throws
    func fetch() async throws -> HealthProfile?
    func fetchOrCreate() async throws -> HealthProfile
}
```

**Files**: `Reppo/Core/Repositories/Protocols/HealthProfileRepositoryProtocol.swift` (new, ~15 lines)
**Parallel?**: Yes
**Notes**: No `delete` method — HealthProfile is a single-row table that should always exist after onboarding. `fetchOrCreate` guarantees a non-nil return by creating with defaults if needed.

---

### Subtask T009 – Create ProgramRepositoryProtocol

**Purpose**: Define the data-access contract for Program — basic CRUD only for v1 (Programs tab is v1.1 empty-state placeholder).

**Steps**:
1. Create file `Reppo/Core/Repositories/Protocols/ProgramRepositoryProtocol.swift`
2. Define protocol from contract file

**Required methods**:
```swift
protocol ProgramRepositoryProtocol: Sendable {
    func save(_ program: Program) async throws
    func delete(_ program: Program) async throws
    func fetch(byId id: UUID) async throws -> Program?
    func fetchAll() async throws -> [Program]
}
```

**Files**: `Reppo/Core/Repositories/Protocols/ProgramRepositoryProtocol.swift` (new, ~15 lines)
**Parallel?**: Yes
**Notes**: Minimal protocol. ProgramExercise, PlannedWorkout, PlannedSet don't have repositories in v1.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| @Model types not visible without `import SwiftData` | Test compilation; add import with explanatory comment if needed |
| Protocol `Sendable` conformance issues | Protocols with only `async throws` methods satisfy `Sendable` requirements |
| Missing methods vs contracts | Cross-reference each protocol against its contract file in `contracts/` |

---

## Definition of Done Checklist

- [ ] All 9 files created in `Reppo/Core/Repositories/Protocols/`
- [ ] All 8 protocols conform to `Sendable`
- [ ] All methods are `async throws`
- [ ] No protocol file imports SwiftData (unless compiler requires it, with comment)
- [ ] Method signatures match contracts in `kitty-specs/002-repositories-and-indexes/contracts/`
- [ ] `SetSortOrder` enum has 3 cases and conforms to `Sendable`
- [ ] Project compiles with zero errors
- [ ] `tasks.md` updated with status change

---

## Review Guidance

- **Primary check**: Compare every method signature against the corresponding contract file in `contracts/`
- **Architecture check**: No SwiftData imports unless absolutely necessary
- **Naming check**: WorkoutSet (not Set), all IDs are UUID
- **Completeness check**: 8 protocols + 1 enum = 9 files total

---

## Activity Log

- 2026-02-20T12:32:56Z – system – lane=planned – Prompt created.
- 2026-02-22T18:00:00Z – claude – lane=doing – Started implementation.
- 2026-02-22T18:30:00Z – claude – lane=for_review – Implementation complete: 9 files created.
- 2026-02-22T19:00:00Z – claude – lane=doing – Started review.
- 2026-02-22T19:30:00Z – claude – lane=done – Review passed: All 8 protocol files + SetSortOrder enum match contracts. Build passed.
- 2026-02-22T20:16:56Z – claude – shell_pid=0 – lane=planned – Reset for proper activity log
- 2026-02-22T20:17:00Z – claude – shell_pid=0 – lane=done – Review passed: All 8 protocols + SetSortOrder enum. Build passed.
