---
work_package_id: "WP02"
subtasks:
  - "T008"
  - "T009"
  - "T010"
  - "T011"
  - "T012"
  - "T013"
  - "T014"
  - "T015"
title: "BodyweightService + WorkoutService"
phase: "Phase 1 - Service Implementation"
lane: "done"
assignee: ""
agent: "claude-opus"
shell_pid: "87407"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-24T13:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP02 – BodyweightService + WorkoutService

## Implementation Command

Depends on WP01:
```bash
spec-kitty implement WP02 --base WP01
```

## Objectives & Success Criteria

- BodyweightService fully implemented: CRUD + closest-weight lookup
- WorkoutService fully implemented: start/finish lifecycle, active workout detection, cascade deletion
- Both services are plain `actor` types with initializer injection
- All methods match their respective protocol contracts
- Project compiles with zero errors

## Context & Constraints

**Feature**: 005-workout-exercise-bodyweight-services
**Architecture**: Services are plain Swift `actor` types (NOT `@ModelActor`). They call repositories for data access. No ModelContext access.
**Constitution**: `.kittify/memory/constitution.md`
**Plan**: `kitty-specs/005-workout-exercise-bodyweight-services/plan.md` — see "Method-by-Method Design" section
**Contracts**: `kitty-specs/005-workout-exercise-bodyweight-services/contracts/WorkoutServiceProtocol.swift` and `contracts/BodyweightServiceProtocol.swift`

**Existing service patterns to follow**:
- `Reppo/Core/Services/SetService.swift` — actor structure, init pattern, repository calling pattern
- `Reppo/Core/Services/PRService.swift` — actor with repository deps
- `Reppo/Core/Services/StatsService.swift` — actor with repository deps

**Key decisions from plan**:
- WorkoutService.startWorkout(): Return existing active workout if one exists (no error, no duplicate)
- Cascade deletion: Bulk delete sets via repository, then PRService.rebuild() + StatsService.rebuild() per affected exercise
- BodyweightService: Thin wrapper, auto-associates entries with HealthProfile
- All weight stored in kg, duration in seconds

## Subtasks & Detailed Guidance

### Subtask T008 – Create BodyweightService actor

**Purpose**: Establish the BodyweightService actor with dependency injection.

**Create** `Reppo/Core/Services/BodyweightService.swift`:

```swift
// BodyweightService.swift
// Bodyweight entry CRUD and closest-weight lookup
// Spec: FR-008, FR-009
// Source: specdoc S6.6; AGENT_RULES S6

import Foundation

actor BodyweightService: BodyweightServiceProtocol {
    private let bodyweightEntryRepo: BodyweightEntryRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol

    init(
        bodyweightEntryRepository: BodyweightEntryRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol
    ) {
        self.bodyweightEntryRepo = bodyweightEntryRepository
        self.healthProfileRepo = healthProfileRepository
    }

    // Methods implemented in T009, T010
}
```

**File**: `Reppo/Core/Services/BodyweightService.swift` (new file)

### Subtask T009 – Implement BodyweightService CRUD

**Purpose**: CRUD operations for bodyweight entries with automatic HealthProfile association.

**Implement 4 methods**:

```swift
func saveEntry(bodyweightKg: Double, date: Date) async throws -> BodyweightEntry {
    let profile = try await healthProfileRepo.fetchOrCreate()
    let entry = BodyweightEntry(
        healthProfileId: profile.id,
        date: date,
        bodyweightKg: bodyweightKg
    )
    try await bodyweightEntryRepo.save(entry)
    return entry
}

func updateEntry(_ entry: BodyweightEntry) async throws {
    entry.updatedAt = Date()
    try await bodyweightEntryRepo.save(entry)
}

func deleteEntry(_ entryId: UUID) async throws {
    guard let entry = try await bodyweightEntryRepo.fetch(byId: entryId) else {
        throw BodyweightServiceError.entryNotFound(entryId)
    }
    try await bodyweightEntryRepo.delete(entry)
}

func fetchAllEntries() async throws -> [BodyweightEntry] {
    let profile = try await healthProfileRepo.fetchOrCreate()
    return try await bodyweightEntryRepo.fetchAll(for: profile.id)
}
```

**Notes**:
- `saveEntry` creates a new BodyweightEntry and associates it with the user's HealthProfile
- `deleteEntry` fetches by ID first (using the new `fetch(byId:)` method from WP01)
- `fetchAllEntries` needs the healthProfileId, obtained via `fetchOrCreate()`

### Subtask T010 – Implement closestBodyweight lookup

**Purpose**: Delegate closest-weight lookup to the repository. Used by SetService (already exists) for effectiveWeight calculation.

```swift
func closestBodyweight(to date: Date) async throws -> BodyweightEntry? {
    let profile = try await healthProfileRepo.fetchOrCreate()
    return try await bodyweightEntryRepo.fetchClosest(to: date, healthProfileId: profile.id)
}
```

**Note**: This is a convenience method. SetService already calls `bodyweightEntryRepo.fetchClosest()` directly for effectiveWeight calculation. This method exists for ViewModel use when displaying bodyweight data.

### Subtask T011 – Create WorkoutService actor

**Purpose**: Establish the WorkoutService actor with 4 dependencies.

**Create** `Reppo/Core/Services/WorkoutService.swift`:

```swift
// WorkoutService.swift
// Workout lifecycle management: create, finish, active detection, cascade deletion
// Spec: FR-001, FR-002, FR-003, FR-004, FR-010
// Source: specdoc S3, S6.2; AGENT_RULES S6, S7.3

import Foundation

actor WorkoutService: WorkoutServiceProtocol {
    private let workoutRepo: WorkoutRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let prService: PRServiceProtocol
    private let statsService: StatsServiceProtocol

    init(
        workoutRepository: WorkoutRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        prService: PRServiceProtocol,
        statsService: StatsServiceProtocol
    ) {
        self.workoutRepo = workoutRepository
        self.setRepo = setRepository
        self.prService = prService
        self.statsService = statsService
    }

    // Methods implemented in T012-T015
}
```

**File**: `Reppo/Core/Services/WorkoutService.swift` (new file)

### Subtask T012 – Implement startWorkout + getActiveWorkout

**Purpose**: Core workout lifecycle — start a new workout or resume existing one.

```swift
// FR-004: Only one active workout at a time
// If one exists, return it (user decision — no error, no duplicate)
func startWorkout() async throws -> Workout {
    // Check for existing active workout
    if let existing = try await workoutRepo.fetchInProgress() {
        return existing
    }

    // Create new workout
    let workout = Workout(
        date: Date(),
        startTime: Date(),
        status: .inProgress
    )
    try await workoutRepo.save(workout)
    return workout
}

// FR-003: Detect and return active workout on app launch
func getActiveWorkout() async throws -> Workout? {
    return try await workoutRepo.fetchInProgress()
}
```

**Key behavior**: `startWorkout()` returns the EXISTING active workout if one is in progress. This is the agreed-upon design decision — no error thrown, just returns the active workout. The ViewModel/UI decides how to present this (navigate to active workout).

**AGENT_RULES S7.3 reference**: "When the app launches and finds a workout with status = inProgress, navigate directly to it."

### Subtask T013 – Implement finishWorkout

**Purpose**: Finish an active workout — set status, endTime, calculate duration.

```swift
func finishWorkout(_ workoutId: UUID) async throws {
    guard let workout = try await workoutRepo.fetch(byId: workoutId) else {
        throw WorkoutServiceError.workoutNotFound(workoutId)
    }

    guard workout.status != .completed else {
        throw WorkoutServiceError.workoutAlreadyCompleted(workoutId)
    }

    workout.status = .completed
    workout.endTime = Date()

    // Calculate duration in seconds (specdoc S6.2)
    if let startTime = workout.startTime, let endTime = workout.endTime {
        workout.duration = Int(endTime.timeIntervalSince(startTime))
    }

    workout.updatedAt = Date()
    try await workoutRepo.save(workout)
}
```

**Notes**:
- Duration is `endTime - startTime` in seconds (matching specdoc S6.2 "duration: int, Duration in seconds")
- Guard against finishing an already-completed workout
- "Finish Workout" is a UI action that flips status — sets are already persisted immediately (FR-012, handled by SetService)

### Subtask T014 – Implement WorkoutService read methods

**Purpose**: Pass-through read methods for ViewModel access.

```swift
func fetchWorkout(_ workoutId: UUID) async throws -> Workout? {
    return try await workoutRepo.fetch(byId: workoutId)
}

func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout] {
    return try await workoutRepo.fetchWorkouts(for: dateRange)
}

func fetchAllWorkouts(limit: Int? = nil, offset: Int? = nil) async throws -> [Workout] {
    return try await workoutRepo.fetchAllWorkouts(limit: limit, offset: offset)
}
```

**Note**: These are thin wrappers. The service layer exists to maintain the architecture (Views→VMs→Services→Repos). Future features may add business logic here (e.g., filtering by program).

### Subtask T015 – Implement deleteWorkout cascade

**Purpose**: Delete a workout with full cascade — bulk delete sets, then rebuild PRs/stats for affected exercises.

This is the most complex method in WorkoutService. Follow the exact pipeline from the plan:

```swift
func deleteWorkout(_ workoutId: UUID) async throws {
    // 1. Fetch workout
    guard let workout = try await workoutRepo.fetch(byId: workoutId) else {
        throw WorkoutServiceError.workoutNotFound(workoutId)
    }

    // 2. Get affected exerciseIds BEFORE deleting sets
    let affectedExerciseIds = try await setRepo.fetchExerciseIds(for: workoutId)

    // 3. Bulk delete all sets for this workout
    try await setRepo.deleteSets(for: workoutId)

    // 4. Delete the workout itself
    try await workoutRepo.delete(workout)

    // 5. Rebuild PRs + stats for each affected exercise
    for exerciseId in affectedExerciseIds {
        try await prService.rebuild(for: exerciseId)
        try await statsService.rebuild(for: exerciseId)
    }
}
```

**Critical ordering**:
1. **Fetch exerciseIds FIRST** — must happen before sets are deleted, otherwise we don't know which exercises to rebuild
2. **Delete sets** — bulk delete via repository (not per-set via SetService, per AGENT_RULES S6)
3. **Delete workout** — after sets are gone
4. **Rebuild** — per affected exercise, using existing `PRService.rebuild(for:)` and `StatsService.rebuild(for:)` methods from features 003/004

**Why not SetService.delete() per set?**: AGENT_RULES S6 says WorkoutService "Does NOT: Handle individual set logic". Calling SetService.delete() 50 times would also be O(n) pipeline calls (PR eval + stats update per set). Bulk delete + rebuild is more efficient and correct for this use case.

## Risks & Mitigations

- **Workout.startTime nil**: If `startTime` is nil when finishing, duration calculation silently skips (no crash). The `if let` guard handles this.
- **Empty workout deletion**: A workout with 0 sets still deletes cleanly — `fetchExerciseIds` returns empty set, loop doesn't execute.
- **Rebuild failure mid-cascade**: If `prService.rebuild()` fails for one exercise, the error propagates. Sets are already deleted at this point. The manual "Rebuild Stats" in Settings can fix any inconsistency.
- **SwiftData @Model objects across actor boundaries**: `startWorkout()` returns a `Workout` object. Ensure this is safe — `@ModelActor` repositories return objects from their context. The calling ViewModel should re-fetch if needed.

## Definition of Done Checklist

- [ ] BodyweightService.swift created with all 5 methods
- [ ] WorkoutService.swift created with all 7 methods
- [ ] Both conform to their respective protocols
- [ ] startWorkout() returns existing active workout (no duplicate creation)
- [ ] finishWorkout() sets status=completed, endTime, duration
- [ ] deleteWorkout() cascade: gets exerciseIds → deletes sets → deletes workout → rebuilds
- [ ] Project compiles with zero errors
- [ ] No existing functionality broken

## Review Guidance

- Verify `startWorkout()` checks for existing active workout FIRST (FR-004)
- Verify `deleteWorkout()` fetches exerciseIds BEFORE deleting sets (ordering critical)
- Verify `deleteWorkout()` calls `prService.rebuild()` and `statsService.rebuild()` (not `rebuildAll()`)
- Verify BodyweightService auto-associates with HealthProfile via `fetchOrCreate()`
- Check that both services use the `actor` keyword (not `class` or `@ModelActor`)
- Verify error handling: workoutNotFound, workoutAlreadyCompleted, entryNotFound

## Activity Log

- 2026-02-24T13:00:00Z – system – lane=planned – Prompt created.
- 2026-02-24T13:33:05Z – claude-opus – shell_pid=86478 – lane=doing – Started implementation via workflow command
- 2026-02-24T13:36:48Z – claude-opus – shell_pid=86478 – lane=for_review – Ready for review: BodyweightService (5 methods) + WorkoutService (7 methods) implemented as plain actors. Cascade deletion follows plan pipeline. Build zero errors.
- 2026-02-24T13:37:49Z – claude-opus – shell_pid=87407 – lane=doing – Started review via workflow command
- 2026-02-24T13:38:25Z – claude-opus – shell_pid=87407 – lane=done – Review passed: BodyweightService (5 methods) and WorkoutService (7 methods) match protocols exactly. Cascade deletion ordering verified (exerciseIds before delete). startWorkout returns existing active workout per FR-004. Build zero errors.
