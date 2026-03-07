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
title: "Protocols, Error Types + Repository Additions"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: ""
agent: "claude-opus"
shell_pid: "84025"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: []
history:
  - timestamp: "2026-02-24T13:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP01 – Protocols, Error Types + Repository Additions

## Implementation Command

No dependencies — start from main:
```bash
spec-kitty implement WP01
```

## Objectives & Success Criteria

- All 3 service protocols created with complete method signatures matching contracts
- All 3 error enums created
- 5 new repository methods added (3 on SetRepository, 1 on PerformanceRecordRepository, 1 on BodyweightEntryRepository)
- Project compiles with zero errors
- No existing functionality broken

## Context & Constraints

**Feature**: 005-workout-exercise-bodyweight-services
**Architecture**: MVVM with Service + Repository layers. Services are `actor` types, repositories are `@ModelActor` types.
**Constitution**: `.kittify/memory/constitution.md` — all code must comply
**Plan**: `kitty-specs/005-workout-exercise-bodyweight-services/plan.md`
**Contracts**: `kitty-specs/005-workout-exercise-bodyweight-services/contracts/` (3 Swift protocol files)

**Key constraint**: Repositories are the only layer that touches SwiftData `ModelContext`. Service protocols define `async throws` methods. All types crossing actor boundaries must be `Sendable`.

**Naming rule**: Use `Swift.Set<UUID>` when returning a set of UUIDs to avoid collision with `WorkoutSet`.

## Subtasks & Detailed Guidance

### Subtask T001 – Add 3 new methods to SetRepositoryProtocol + SetRepository

**Purpose**: Enable cascade deletion for WorkoutService and ExerciseService. These methods allow bulk deletion of sets by workout or exercise, and fetching affected exerciseIds before deletion.

**Protocol additions** (`Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift`):

```swift
/// Bulk delete all sets for a workout. Used by WorkoutService cascade deletion.
func deleteSets(for workoutId: UUID) async throws

/// Bulk delete all sets for an exercise. Used by ExerciseService cascade deletion.
func deleteSets(forExercise exerciseId: UUID) async throws

/// Fetch unique exerciseIds for sets in a workout.
/// Used before cascade deletion to know which exercises need rebuild.
func fetchExerciseIds(for workoutId: UUID) async throws -> Swift.Set<UUID>
```

**Implementation** (`Reppo/Core/Repositories/SetRepository.swift`):

```swift
func deleteSets(for workoutId: UUID) throws {
    let descriptor = FetchDescriptor<WorkoutSet>(
        predicate: #Predicate { $0.workoutId == workoutId }
    )
    let sets = try modelContext.fetch(descriptor)
    for set in sets {
        modelContext.delete(set)
    }
    try modelContext.save()
}

func deleteSets(forExercise exerciseId: UUID) throws {
    let descriptor = FetchDescriptor<WorkoutSet>(
        predicate: #Predicate { $0.exerciseId == exerciseId }
    )
    let sets = try modelContext.fetch(descriptor)
    for set in sets {
        modelContext.delete(set)
    }
    try modelContext.save()
}

func fetchExerciseIds(for workoutId: UUID) throws -> Swift.Set<UUID> {
    let descriptor = FetchDescriptor<WorkoutSet>(
        predicate: #Predicate { $0.workoutId == workoutId }
    )
    let sets = try modelContext.fetch(descriptor)
    return Swift.Set(sets.map(\.exerciseId))
}
```

**Note**: The repository methods are synchronous (`throws`, not `async throws`) because `@ModelActor` repositories in this project use synchronous signatures. The protocol declares them as `async throws` for the actor boundary crossing. Check existing repo methods for the correct pattern — if existing methods are synchronous in the implementation, follow that pattern.

**Files**:
- `Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift` (add 3 method signatures)
- `Reppo/Core/Repositories/SetRepository.swift` (add 3 implementations)

### Subtask T002 – Add deleteAll to PerformanceRecordRepositoryProtocol + PerformanceRecordRepository

**Purpose**: Enable ExerciseService to delete all PRs when an exercise is deleted.

**Protocol addition** (`Reppo/Core/Repositories/Protocols/PerformanceRecordRepositoryProtocol.swift`):

```swift
/// Delete all PerformanceRecords for an exercise.
/// Used by ExerciseService cascade deletion.
func deleteAll(for exerciseId: UUID) async throws
```

**Implementation** (`Reppo/Core/Repositories/PerformanceRecordRepository.swift`):

```swift
func deleteAll(for exerciseId: UUID) throws {
    let descriptor = FetchDescriptor<PerformanceRecord>(
        predicate: #Predicate { $0.exerciseId == exerciseId }
    )
    let records = try modelContext.fetch(descriptor)
    for record in records {
        modelContext.delete(record)
    }
    try modelContext.save()
}
```

**Files**:
- `Reppo/Core/Repositories/Protocols/PerformanceRecordRepositoryProtocol.swift` (add 1 method)
- `Reppo/Core/Repositories/PerformanceRecordRepository.swift` (add 1 implementation)

### Subtask T003 – Add fetch(byId:) to BodyweightEntryRepositoryProtocol + BodyweightEntryRepository

**Purpose**: Enable BodyweightService to fetch a specific entry for update/delete operations.

**Protocol addition** (`Reppo/Core/Repositories/Protocols/BodyweightEntryRepositoryProtocol.swift`):

```swift
/// Fetch a bodyweight entry by ID.
func fetch(byId id: UUID) async throws -> BodyweightEntry?
```

**Implementation** (`Reppo/Core/Repositories/BodyweightEntryRepository.swift`):

```swift
func fetch(byId id: UUID) throws -> BodyweightEntry? {
    let descriptor = FetchDescriptor<BodyweightEntry>(
        predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
}
```

**Files**:
- `Reppo/Core/Repositories/Protocols/BodyweightEntryRepositoryProtocol.swift` (add 1 method)
- `Reppo/Core/Repositories/BodyweightEntryRepository.swift` (add 1 implementation)

### Subtask T004 – Create 3 service error enums

**Purpose**: Define error types for the three new services.

**Create in the respective service protocol files** (or a shared file if the project uses that pattern — check existing services):

```swift
// In WorkoutServiceProtocol.swift
enum WorkoutServiceError: Error {
    case workoutNotFound(UUID)
    case workoutAlreadyCompleted(UUID)
}

// In ExerciseServiceProtocol.swift
enum ExerciseServiceError: Error {
    case exerciseNotFound(UUID)
    case trackingTypeImmutable(exerciseId: UUID)
}

// In BodyweightServiceProtocol.swift
enum BodyweightServiceError: Error {
    case entryNotFound(UUID)
}
```

**Check where existing errors live**: Look at `SetServiceError` in `Reppo/Core/Services/SetService.swift` — it's defined at the top of the implementation file, not the protocol file. Follow the same pattern.

**Files**: 3 protocol files or 3 implementation files (match existing pattern)

### Subtask T005 – Create WorkoutServiceProtocol

**Purpose**: Define the contract for workout lifecycle management.

**Source of truth**: `kitty-specs/005-workout-exercise-bodyweight-services/contracts/WorkoutServiceProtocol.swift`

**Create** `Reppo/Core/Services/Protocols/WorkoutServiceProtocol.swift` with:
- `protocol WorkoutServiceProtocol: Sendable`
- Methods: `startWorkout()`, `finishWorkout(_:)`, `getActiveWorkout()`, `fetchWorkout(_:)`, `fetchWorkouts(for:)`, `fetchAllWorkouts(limit:offset:)`, `deleteWorkout(_:)`
- All methods are `async throws`
- Include doc comments matching the contract file

**File**: `Reppo/Core/Services/Protocols/WorkoutServiceProtocol.swift` (new file)

### Subtask T006 – Create ExerciseServiceProtocol

**Purpose**: Define the contract for exercise CRUD with metadata mutability enforcement.

**Source of truth**: `kitty-specs/005-workout-exercise-bodyweight-services/contracts/ExerciseServiceProtocol.swift`

**Create** `Reppo/Core/Services/Protocols/ExerciseServiceProtocol.swift` with:
- `protocol ExerciseServiceProtocol: Sendable`
- Methods: `createExercise(_:)`, `updateExercise(_:originalTrackingType:)`, `fetchExercise(_:)`, `fetchAllExercises()`, `searchExercises(name:)`, `deleteExercise(_:)`, `exerciseHasSets(_:)`
- All methods are `async throws`
- Include doc comments about trackingType immutability (specdoc S5.6) and rebuild-required fields

**File**: `Reppo/Core/Services/Protocols/ExerciseServiceProtocol.swift` (new file)

### Subtask T007 – Create BodyweightServiceProtocol

**Purpose**: Define the contract for bodyweight entry CRUD and closest-weight lookup.

**Source of truth**: `kitty-specs/005-workout-exercise-bodyweight-services/contracts/BodyweightServiceProtocol.swift`

**Create** `Reppo/Core/Services/Protocols/BodyweightServiceProtocol.swift` with:
- `protocol BodyweightServiceProtocol: Sendable`
- Methods: `saveEntry(bodyweightKg:date:)`, `updateEntry(_:)`, `deleteEntry(_:)`, `fetchAllEntries()`, `closestBodyweight(to:)`
- All methods are `async throws`

**File**: `Reppo/Core/Services/Protocols/BodyweightServiceProtocol.swift` (new file)

## Risks & Mitigations

- **SwiftData batch delete**: SwiftData doesn't have a `batchDelete` API like Core Data. The pattern is fetch-all-matching + delete-each + single save. This is acceptable for cascade deletion (rare operation).
- **`Swift.Set<UUID>` naming**: Must use `Swift.Set` explicitly to avoid collision with `WorkoutSet`. The compiler would catch this but the explicit qualification is clearer.
- **Protocol method sync vs async**: Repository protocols declare `async throws` but `@ModelActor` implementations use `throws` (the actor boundary handles the async). Follow existing patterns exactly.

## Definition of Done Checklist

- [ ] 3 new methods on SetRepositoryProtocol + SetRepository
- [ ] 1 new method on PerformanceRecordRepositoryProtocol + PerformanceRecordRepository
- [ ] 1 new method on BodyweightEntryRepositoryProtocol + BodyweightEntryRepository
- [ ] 3 error enums created (matching existing error pattern)
- [ ] WorkoutServiceProtocol created with all methods
- [ ] ExerciseServiceProtocol created with all methods
- [ ] BodyweightServiceProtocol created with all methods
- [ ] Project compiles with zero errors
- [ ] No existing tests or functionality broken

## Review Guidance

- Verify repository method signatures match the protocol declarations
- Verify error enums follow the same pattern as `SetServiceError`
- Verify service protocols match the contracts in `kitty-specs/005-workout-exercise-bodyweight-services/contracts/`
- Verify `Swift.Set<UUID>` is used (not bare `Set<UUID>`)
- Check that all new types are `Sendable` where needed

## Activity Log

- 2026-02-24T13:00:00Z – system – lane=planned – Prompt created.
- 2026-02-24T13:19:02Z – claude-opus – shell_pid=84025 – lane=doing – Started implementation via workflow command
- 2026-02-24T13:32:35Z – claude-opus – shell_pid=84025 – lane=done – Review passed: All 7 subtasks verified. 3 service protocols match contracts exactly (19 methods total). 5 repository additions correct with proper Swift.Set<UUID> usage. 3 error enums created. Build compiles zero errors.
