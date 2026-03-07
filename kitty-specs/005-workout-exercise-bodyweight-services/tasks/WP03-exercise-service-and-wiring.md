---
work_package_id: "WP03"
subtasks:
  - "T016"
  - "T017"
  - "T018"
  - "T019"
  - "T020"
  - "T021"
  - "T022"
title: "ExerciseService + ServiceContainer Wiring"
phase: "Phase 2 - Completion"
lane: "doing"
assignee: ""
agent: "claude-opus"
shell_pid: "87685"
review_status: ""
reviewed_by: ""
dependencies: ["WP01", "WP02"]
history:
  - timestamp: "2026-02-24T13:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – ExerciseService + ServiceContainer Wiring

## Implementation Command

Depends on WP01 and WP02:
```bash
spec-kitty implement WP03 --base WP02
```

## Objectives & Success Criteria

- ExerciseService fully implemented with trackingType immutability enforcement and rebuild-required field detection
- ServiceContainer updated to create and expose all 6 services (3 existing + 3 new)
- Project compiles with zero errors — all protocols satisfied
- Feature 005 is complete after this WP

## Context & Constraints

**Feature**: 005-workout-exercise-bodyweight-services
**Architecture**: Services are plain Swift `actor` types (NOT `@ModelActor`). They call repositories for data access.
**Constitution**: `.kittify/memory/constitution.md`
**Plan**: `kitty-specs/005-workout-exercise-bodyweight-services/plan.md` — see "ExerciseService Implementation Design" and "ServiceContainer Update"
**Contract**: `kitty-specs/005-workout-exercise-bodyweight-services/contracts/ExerciseServiceProtocol.swift`

**Existing service patterns**:
- `Reppo/Core/Services/SetService.swift` — actor structure
- `Reppo/Core/Services/ServiceContainer.swift` — DI wiring pattern

**Critical spec references**:
- **specdoc S5.6** — Metadata mutability rules (immutable, rebuild-required, low-risk)
- **AGENT_RULES S3.5** — trackingType is immutable once sets exist
- **specdoc S5.4** — effectiveWeight never recalculated retroactively (rebuild uses stored values)

## Subtasks & Detailed Guidance

### Subtask T016 – Create ExerciseService actor

**Purpose**: Establish ExerciseService with 6 dependencies — the most complex service in this feature.

**Create** `Reppo/Core/Services/ExerciseService.swift`:

```swift
// ExerciseService.swift
// Exercise CRUD, trackingType immutability, metadata mutability enforcement
// Spec: FR-005, FR-006, FR-007, FR-011, FR-012
// Source: specdoc S5, S5.6; AGENT_RULES S3.5, S6

import Foundation

actor ExerciseService: ExerciseServiceProtocol {
    private let exerciseRepo: ExerciseRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let exerciseStatsRepo: ExerciseStatsRepositoryProtocol
    private let performanceRecordRepo: PerformanceRecordRepositoryProtocol
    private let prService: PRServiceProtocol
    private let statsService: StatsServiceProtocol

    init(
        exerciseRepository: ExerciseRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        exerciseStatsRepository: ExerciseStatsRepositoryProtocol,
        performanceRecordRepository: PerformanceRecordRepositoryProtocol,
        prService: PRServiceProtocol,
        statsService: StatsServiceProtocol
    ) {
        self.exerciseRepo = exerciseRepository
        self.setRepo = setRepository
        self.exerciseStatsRepo = exerciseStatsRepository
        self.performanceRecordRepo = performanceRecordRepository
        self.prService = prService
        self.statsService = statsService
    }

    // Methods implemented in T017-T020
}
```

**Why 6 dependencies?**:
- `exerciseRepo` — Exercise CRUD + hasAssociatedSets check
- `setRepo` — Bulk delete sets on exercise deletion
- `exerciseStatsRepo` — Delete ExerciseStats on exercise deletion
- `performanceRecordRepo` — Delete PerformanceRecords on exercise deletion
- `prService` — PR rebuild after calculation-critical field change
- `statsService` — Stats rebuild after calculation-critical field change

**File**: `Reppo/Core/Services/ExerciseService.swift` (new file)

### Subtask T017 – Implement createExercise + read methods

**Purpose**: Basic CRUD operations that wrap the repository.

```swift
func createExercise(_ exercise: Exercise) async throws {
    try await exerciseRepo.save(exercise)
}

func fetchExercise(_ exerciseId: UUID) async throws -> Exercise? {
    return try await exerciseRepo.fetch(byId: exerciseId)
}

func fetchAllExercises() async throws -> [Exercise] {
    return try await exerciseRepo.fetchAll()
}

func searchExercises(name query: String) async throws -> [Exercise] {
    return try await exerciseRepo.search(name: query)
}

func exerciseHasSets(_ exerciseId: UUID) async throws -> Bool {
    return try await exerciseRepo.hasAssociatedSets(exerciseId)
}
```

**Notes**:
- `createExercise` is a simple persist — no validation beyond what the model requires
- `searchExercises` uses `localizedStandardContains` via the repository (case-insensitive, diacritic-insensitive)
- `exerciseHasSets` is exposed for ViewModel use — determines if trackingType should be editable in UI

### Subtask T018 – Implement updateExercise with trackingType immutability

**Purpose**: The core metadata enforcement logic. Prevent trackingType changes when sets exist.

```swift
func updateExercise(_ exercise: Exercise, originalTrackingType: TrackingType) async throws {
    let hasSets = try await exerciseRepo.hasAssociatedSets(exercise.id)

    // FR-005: trackingType immutability (specdoc S5.6)
    if hasSets && exercise.trackingType != originalTrackingType {
        throw ExerciseServiceError.trackingTypeImmutable(exerciseId: exercise.id)
    }

    // Detect rebuild-required field changes (T019 adds this logic)
    var needsRebuild = false
    if hasSets {
        needsRebuild = try await detectRebuildRequired(for: exercise)
    }

    // Persist the update
    exercise.updatedAt = Date()
    try await exerciseRepo.save(exercise)

    // Rebuild if calculation-critical fields changed (FR-006)
    if needsRebuild {
        try await prService.rebuild(for: exercise.id)
        try await statsService.rebuild(for: exercise.id)
    }
}
```

**Key behavior**:
- `originalTrackingType` is passed by the caller (ViewModel snapshots it before the user starts editing). The service compares current vs. original.
- If trackingType changed AND sets exist → throw error immediately (before any persist)
- If rebuild-required fields changed AND sets exist → persist first, then rebuild
- Rebuild uses stored effectiveWeight values on historical sets (NEVER recalculates retroactively)

**The `originalTrackingType` parameter pattern**: This avoids the service needing to fetch the "before" state. The ViewModel already has the original exercise loaded, so passing the original trackingType is natural and avoids an extra repository call for this specific check.

### Subtask T019 – Implement rebuild-required field change detection

**Purpose**: Compare current exercise values against persisted values to detect if a rebuild is needed.

**Add a private helper method**:

```swift
/// Detect if any rebuild-required fields have changed.
/// Must fetch the persisted exercise to compare against.
/// Rebuild-required fields (specdoc S5.6):
///   bodyweightFactor, unilateral, bilateralLoadFactor, equipmentType
private func detectRebuildRequired(for exercise: Exercise) async throws -> Bool {
    guard let persisted = try await exerciseRepo.fetch(byId: exercise.id) else {
        return false // New exercise, no rebuild needed
    }

    return exercise.bodyweightFactor != persisted.bodyweightFactor
        || exercise.unilateral != persisted.unilateral
        || exercise.bilateralLoadFactor != persisted.bilateralLoadFactor
        || exercise.equipmentType != persisted.equipmentType
}
```

**Why fetch persisted?**: The `originalTrackingType` parameter handles the immutability check, but for rebuild detection we need to compare ALL four rebuild-required fields. Rather than passing 4 more "original" parameters, one repository fetch is cleaner and more maintainable.

**Performance note**: This adds one extra `fetch(byId:)` per exercise update. Exercise updates are rare (user editing exercise metadata), not on the hot path (set save). This is acceptable.

**IMPORTANT**: The rebuild does NOT recalculate effectiveWeight on historical sets. It rebuilds ExerciseStats (SUM/MAX/COUNT from stored values) and PerformanceRecords (re-evaluate PRs from stored values). This is consistent with specdoc S5.4: "Store once at save time, never recalculate retroactively."

**Edge case — SwiftData object identity**: When we call `exerciseRepo.fetch(byId: exercise.id)`, SwiftData may return the same in-memory object (already modified by the caller). If this happens, the comparison will always return false.

**Mitigation**: Check if SwiftData returns the same object. If it does, the ViewModel should pass the original values (similar to `originalTrackingType`). The plan notes: "The service fetches the persisted version to detect changes." If SwiftData's context has already applied the mutation, this approach won't work, and the protocol should be updated to accept original values.

**Alternative approach** (safer): Add original field values to the `updateExercise` signature or have the ViewModel pass a diff/changeset. For v1, start with the fetch approach and validate during implementation.

### Subtask T020 – Implement deleteExercise cascade

**Purpose**: Delete an exercise and all its associated data (sets, stats, PRs).

```swift
func deleteExercise(_ exerciseId: UUID) async throws {
    guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else {
        throw ExerciseServiceError.exerciseNotFound(exerciseId)
    }

    // 1. Bulk delete all sets for this exercise
    try await setRepo.deleteSets(forExercise: exerciseId)

    // 2. Delete ExerciseStats (if exists)
    if let stats = try await exerciseStatsRepo.fetch(for: exerciseId) {
        try await exerciseStatsRepo.delete(stats)
    }

    // 3. Delete all PerformanceRecords for this exercise
    try await performanceRecordRepo.deleteAll(for: exerciseId)

    // 4. Delete the exercise itself
    try await exerciseRepo.delete(exercise)
}
```

**Key difference from workout deletion**: Exercise deletion removes EVERYTHING related to this exercise. No rebuild needed — there's nothing left to rebuild. This is simpler than workout deletion where other exercises' data may be affected.

**Ordering matters**:
1. Sets first (they reference exerciseId)
2. Stats and PRs (they reference exerciseId)
3. Exercise last (the parent entity)

If SwiftData had cascade delete rules configured on the relationships, this would be automatic. Since the models use UUID references (not SwiftData relationships), cascade must be manual.

### Subtask T021 – Update ServiceContainer

**Purpose**: Wire all 3 new services into the DI container.

**Edit** `Reppo/Core/Services/ServiceContainer.swift`:

Add 3 new properties and create them in `init(repositoryContainer:)`:

```swift
@Observable
final class ServiceContainer {
    let prService: any PRServiceProtocol
    let statsService: any StatsServiceProtocol
    let setService: any SetServiceProtocol
    let workoutService: any WorkoutServiceProtocol          // NEW
    let exerciseService: any ExerciseServiceProtocol         // NEW
    let bodyweightService: any BodyweightServiceProtocol     // NEW

    init(repositoryContainer: RepositoryContainer) {
        // 1. StatsService — depends on repos only (existing)
        let statsService = StatsService(
            exerciseStatsRepository: repositoryContainer.exerciseStatsRepository,
            setRepository: repositoryContainer.setRepository,
            exerciseRepository: repositoryContainer.exerciseRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository
        )

        // 2. PRService — depends on repos only (existing)
        let prService = PRService(
            performanceRecordRepository: repositoryContainer.performanceRecordRepository,
            setRepository: repositoryContainer.setRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository,
            exerciseRepository: repositoryContainer.exerciseRepository
        )

        // 3. SetService — depends on repos + PRService + StatsService (existing)
        let setService = SetService(
            setRepository: repositoryContainer.setRepository,
            exerciseRepository: repositoryContainer.exerciseRepository,
            bodyweightEntryRepository: repositoryContainer.bodyweightEntryRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository,
            prService: prService,
            statsService: statsService
        )

        // 4. BodyweightService — depends on repos only (NEW)
        let bodyweightService = BodyweightService(
            bodyweightEntryRepository: repositoryContainer.bodyweightEntryRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository
        )

        // 5. WorkoutService — depends on repos + PRService + StatsService (NEW)
        let workoutService = WorkoutService(
            workoutRepository: repositoryContainer.workoutRepository,
            setRepository: repositoryContainer.setRepository,
            prService: prService,
            statsService: statsService
        )

        // 6. ExerciseService — depends on repos + PRService + StatsService (NEW)
        let exerciseService = ExerciseService(
            exerciseRepository: repositoryContainer.exerciseRepository,
            setRepository: repositoryContainer.setRepository,
            exerciseStatsRepository: repositoryContainer.exerciseStatsRepository,
            performanceRecordRepository: repositoryContainer.performanceRecordRepository,
            prService: prService,
            statsService: statsService
        )

        self.prService = prService
        self.statsService = statsService
        self.setService = setService
        self.workoutService = workoutService
        self.exerciseService = exerciseService
        self.bodyweightService = bodyweightService
    }
}
```

**Init order**: StatsService → PRService → SetService → BodyweightService → WorkoutService → ExerciseService. No circular dependencies. BodyweightService, WorkoutService, and ExerciseService all depend on PRService + StatsService (already created earlier in init).

**File**: `Reppo/Core/Services/ServiceContainer.swift` (existing file, modify)

### Subtask T022 – Verify build compiles

**Purpose**: Ensure the entire project compiles with zero errors after all changes.

**Steps**:
1. Build the project: `xcodebuild build -scheme Reppo -destination 'platform=iOS Simulator,name=iPhone 16'` (or whatever scheme/destination is configured)
2. Verify zero errors
3. Verify zero warnings related to new code (existing warnings are acceptable)

**If build fails**:
- Check protocol conformance: all 3 services must implement every method in their protocols
- Check ServiceContainer: all properties must be initialized
- Check repository protocol additions: all new methods must be implemented
- Check type mismatches: `Swift.Set<UUID>` vs other types

## Risks & Mitigations

- **SwiftData object identity in `detectRebuildRequired`**: The fetched "persisted" exercise may be the same in-memory object (already modified). If this is the case, comparison always returns false. Mitigation: During implementation, test by printing object identity. If same object, switch to passing original values from ViewModel.
- **ExerciseService 6 dependencies**: Largest dependency count in the service layer. Acceptable for the scope of responsibility. If it grows, consider splitting cascade deletion into a separate helper.
- **ServiceContainer 6 services**: Growing but still clean. All services are created in a single init with clear ordering.
- **PerformanceRecordRepository.deleteAll()**: Must delete ALL records for the exercise (all recordTypes, all reps). Ensure the predicate only filters on exerciseId.

## Definition of Done Checklist

- [ ] ExerciseService.swift created with all 7 methods (create, update, fetch, fetchAll, search, delete, hasSets)
- [ ] trackingType immutability enforced (throws error when sets exist and trackingType changes)
- [ ] Rebuild-required field detection implemented (bodyweightFactor, unilateral, bilateralLoadFactor, equipmentType)
- [ ] deleteExercise cascade: sets → stats → PRs → exercise (correct ordering)
- [ ] ServiceContainer updated with 3 new services (6 total)
- [ ] Project compiles with zero errors
- [ ] No existing functionality broken

## Review Guidance

- **trackingType immutability**: Verify it throws `ExerciseServiceError.trackingTypeImmutable` when sets exist and trackingType is different from original
- **Rebuild trigger**: Verify `prService.rebuild(for:)` and `statsService.rebuild(for:)` are called when rebuild-required fields change
- **Rebuild does NOT recalculate effectiveWeight**: Confirm no code touches historical set effectiveWeight values
- **deleteExercise ordering**: Sets deleted FIRST, then stats, then PRs, then exercise
- **ServiceContainer**: All 6 services created with correct init parameters. No circular dependencies.
- **Build verification**: Zero errors, all protocols fully satisfied

## Activity Log

- 2026-02-24T13:00:00Z – system – lane=planned – Prompt created.
- 2026-02-24T13:39:59Z – claude-opus – shell_pid=87685 – lane=doing – Started implementation via workflow command
