# Implementation Plan: Workout + Exercise + Bodyweight Services

**Branch**: `005-workout-exercise-bodyweight-services` | **Date**: 2026-02-24 | **Spec**: `kitty-specs/005-workout-exercise-bodyweight-services/spec.md`
**Input**: Feature specification from `kitty-specs/005-workout-exercise-bodyweight-services/spec.md`

## Summary

Implement `WorkoutService`, `ExerciseService`, and `BodyweightService` — three business-logic actors that complete the service layer. WorkoutService owns the workout lifecycle (start, finish, active detection, cascade deletion). ExerciseService owns exercise CRUD with trackingType immutability enforcement and metadata mutability rules. BodyweightService wraps bodyweight entry CRUD with closest-weight lookup.

All three are plain Swift actors (not `@ModelActor`) composing existing repository actors via initializer injection. Cascade deletion uses bulk repository operations + rebuild (not per-set SetService calls), per AGENT_RULES S6.

**Prerequisites**: Feature 001 (SwiftData models), Feature 002 (Repositories + Indexes), Feature 003 (PRService), Feature 004 (SetService + StatsService). All are merged to main.

## Technical Context

**Language/Version**: Swift (latest stable, Xcode 16+)
**Primary Dependencies**: SwiftData (via repositories), Foundation
**Target Platform**: iOS 17.0+, iPhone only
**Architecture**: MVVM with Service + Repository layers. These three services join PRService, SetService, and StatsService to complete the service layer.
**Threading Model**: All services are plain `actor` types. Repositories are `@ModelActor` actors. All repository calls are `async throws`.
**Testing**: Manual testing for v1. No automated tests.
**Constraints**: No iPad, no cloud sync, dark mode only.

**Key Decisions**:

| Decision | Choice | Source |
|----------|--------|--------|
| Service type | Plain Swift `actor` (not `@ModelActor`) | Services must not access ModelContext (AGENT_RULES S6). Matches PRService/SetService/StatsService. |
| Cascade deletion | Bulk delete sets via repository, then rebuild per affected exercise | AGENT_RULES S6: WorkoutService "Does NOT handle individual set logic". specdoc S10: rebuild as fallback for batch ops. |
| Active workout on start | Return existing if one is inProgress (no error, no duplicate) | User preference. Spec edge cases: "block or warn". |
| trackingType immutability | Check `exerciseRepo.hasAssociatedSets()` before allowing change | specdoc S5.6. Method exists from feature 002. |
| bodyweightFactor change | Rebuild stats/PRs using existing stored effectiveWeight. Never recalculate historical effectiveWeight. | specdoc S5.4: "Store once at save time, never recalculate retroactively." |
| BodyweightService scope | Thin wrapper: CRUD + closest-weight lookup + auto HealthProfile association | AGENT_RULES S6. Repository does the heavy lifting. |
| Workout duration | `endTime - startTime` in seconds, computed in `finishWorkout()` | specdoc S6.2: duration is "Duration in seconds". |
| DI wiring | Add 3 services to ServiceContainer. No circular deps. | Established pattern. |
| Cross-actor data flow | UUID/primitive params | SwiftData @Model not Sendable. Established pattern. |
| Exercise deletion cascade | Delete sets + ExerciseStats + PerformanceRecords + Exercise. No rebuild needed. | Everything for this exercise is removed. |
| Workout deletion cascade | Delete sets + workout. Rebuild PRs/stats per affected exercise. | Other exercises' data affected by shared sets. |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| Architecture layers (Views→VMs→Services→Repos→SwiftData) | PASS | All three services call Repositories only. No ModelContext access. |
| Only repositories touch ModelContext | PASS | WorkoutService uses WorkoutRepo, SetRepo. ExerciseService uses ExerciseRepo, SetRepo, ExerciseStatsRepo, PerformanceRecordRepo. BodyweightService uses BodyweightEntryRepo, HealthProfileRepo. |
| All weight in kg, distance in meters, duration in seconds | PASS | Bodyweight stored in kg. Duration in seconds. No imperial anywhere. |
| WorkoutSet naming (not Set) | PASS | All code references `WorkoutSet`. |
| Integer grams for float comparison | N/A | No weight comparisons in these services. PR comparison delegated to PRService. |
| Database aggregation, not Swift iteration | PASS | Cascade deletion uses bulk repository ops. No iteration over large collections. |
| Write-time PR/stats updates | PASS | Rebuild triggered after cascade ops. Normal set operations go through SetService (features 003/004). |
| No startup rebuild | PASS | `getActiveWorkout()` is a single-row fetch, not a rebuild. |
| Hard delete only | PASS | All deletions are hard deletes. No soft delete. |
| effectiveWeight never retroactively recalculated | PASS | bodyweightFactor change triggers stats/PR rebuild from stored values only. |
| Sets persist immediately (FR-012) | N/A | Set persistence is SetService's responsibility (feature 004). |
| Do NOT invent fields/tables/enums | PASS | No new models. Three new error enums. Three new protocols. Five new repository methods. |
| Services: single responsibility (AGENT_RULES S6) | PASS | WorkoutService=workout lifecycle. ExerciseService=exercise metadata. BodyweightService=bodyweight entries. No overlap. |
| Prefer async/await | PASS | All service methods are `async throws`. |
| No third-party deps | PASS | Pure Swift + Foundation. |
| Memory management (AGENT_RULES S5.3) | PASS | No large collections loaded. Bulk delete at DB level. fetchExerciseIds returns bounded set. |

**Post-Phase-1 re-check**: All principles pass. No constitution violations.

## Project Structure

### Documentation (this feature)

```
kitty-specs/005-workout-exercise-bodyweight-services/
├── spec.md
├── meta.json
├── plan.md                                    # This file
├── research.md                                # Phase 0: Research findings
├── data-model.md                              # Phase 1: Entity interaction mapping
├── contracts/                                 # Phase 1: Service protocol definitions
│   ├── WorkoutServiceProtocol.swift
│   ├── ExerciseServiceProtocol.swift
│   └── BodyweightServiceProtocol.swift
├── tasks/                                     # Generated by /spec-kitty.tasks
```

### Source Code (repository root)

```
Reppo/Core/Services/
├── Protocols/
│   ├── PRServiceProtocol.swift                (from 003)
│   ├── SetServiceProtocol.swift               (from 004)
│   ├── StatsServiceProtocol.swift             (from 004)
│   ├── WorkoutServiceProtocol.swift           (NEW)
│   ├── ExerciseServiceProtocol.swift          (NEW)
│   └── BodyweightServiceProtocol.swift        (NEW)
├── PRService.swift                            (from 003)
├── SetService.swift                           (from 004)
├── StatsService.swift                         (from 004)
├── WorkoutService.swift                       (NEW)
├── ExerciseService.swift                      (NEW)
├── BodyweightService.swift                    (NEW)
├── ServiceContainer.swift                     (UPDATED — add 3 new services)

Reppo/Core/Repositories/
├── Protocols/
│   ├── SetRepositoryProtocol.swift            (UPDATED — add bulk delete + fetchExerciseIds)
│   ├── PerformanceRecordRepositoryProtocol.swift  (UPDATED — add deleteAll)
│   ├── BodyweightEntryRepositoryProtocol.swift    (UPDATED — add fetch byId)
├── SetRepository.swift                        (UPDATED — implement new methods)
├── PerformanceRecordRepository.swift          (UPDATED — implement deleteAll)
├── BodyweightEntryRepository.swift            (UPDATED — implement fetch byId)
```

## Phase 0: Research

Research findings consolidated in `kitty-specs/005-workout-exercise-bodyweight-services/research.md`.

### Key Findings

| Topic | Decision | Rationale |
|-------|----------|-----------|
| Service threading model | Plain `actor` | AGENT_RULES S6, matches 003/004 pattern |
| Cascade deletion | Bulk delete + rebuild per exercise | AGENT_RULES S6, specdoc S10 |
| Active workout enforcement | Return existing (no error) | User preference, safest approach |
| trackingType guard | `exerciseRepo.hasAssociatedSets()` | Method exists, specdoc S5.6 |
| bodyweightFactor change | Rebuild from stored values, never recalculate historical | specdoc S5.4, constitution |
| New repo methods needed | 5 total (3 on SetRepo, 1 on PRRepo, 1 on BWRepo) | Gap analysis in research.md |

## Phase 1: Design & Contracts

### WorkoutServiceProtocol

Full contract in `kitty-specs/005-workout-exercise-bodyweight-services/contracts/WorkoutServiceProtocol.swift`.

**Methods**:
- `startWorkout() async throws -> Workout`
- `finishWorkout(_ workoutId: UUID) async throws`
- `getActiveWorkout() async throws -> Workout?`
- `fetchWorkout(_ workoutId: UUID) async throws -> Workout?`
- `fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout]`
- `fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout]`
- `deleteWorkout(_ workoutId: UUID) async throws`

### ExerciseServiceProtocol

Full contract in `kitty-specs/005-workout-exercise-bodyweight-services/contracts/ExerciseServiceProtocol.swift`.

**Methods**:
- `createExercise(_ exercise: Exercise) async throws`
- `updateExercise(_ exercise: Exercise, originalTrackingType: TrackingType) async throws`
- `fetchExercise(_ exerciseId: UUID) async throws -> Exercise?`
- `fetchAllExercises() async throws -> [Exercise]`
- `searchExercises(name query: String) async throws -> [Exercise]`
- `deleteExercise(_ exerciseId: UUID) async throws`
- `exerciseHasSets(_ exerciseId: UUID) async throws -> Bool`

### BodyweightServiceProtocol

Full contract in `kitty-specs/005-workout-exercise-bodyweight-services/contracts/BodyweightServiceProtocol.swift`.

**Methods**:
- `saveEntry(bodyweightKg: Double, date: Date) async throws -> BodyweightEntry`
- `updateEntry(_ entry: BodyweightEntry) async throws`
- `deleteEntry(_ entryId: UUID) async throws`
- `fetchAllEntries() async throws -> [BodyweightEntry]`
- `closestBodyweight(to date: Date) async throws -> BodyweightEntry?`

### WorkoutService Implementation Design

```swift
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
    ) { ... }
}
```

**Dependencies** (4 total):
- `WorkoutRepositoryProtocol` — Workout CRUD
- `SetRepositoryProtocol` — Bulk set deletion + exerciseId lookup for cascade
- `PRServiceProtocol` — PR rebuild per affected exercise after cascade delete
- `StatsServiceProtocol` — Stats rebuild per affected exercise after cascade delete

### ExerciseService Implementation Design

```swift
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
    ) { ... }
}
```

**Dependencies** (6 total):
- `ExerciseRepositoryProtocol` — Exercise CRUD + hasAssociatedSets check
- `SetRepositoryProtocol` — Bulk set deletion for cascade
- `ExerciseStatsRepositoryProtocol` — Delete stats on exercise deletion
- `PerformanceRecordRepositoryProtocol` — Delete PRs on exercise deletion
- `PRServiceProtocol` — PR rebuild after calculation-critical field change
- `StatsServiceProtocol` — Stats rebuild after calculation-critical field change

### BodyweightService Implementation Design

```swift
actor BodyweightService: BodyweightServiceProtocol {
    private let bodyweightEntryRepo: BodyweightEntryRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol

    init(
        bodyweightEntryRepository: BodyweightEntryRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol
    ) { ... }
}
```

**Dependencies** (2 total):
- `BodyweightEntryRepositoryProtocol` — Entry CRUD + closest lookup
- `HealthProfileRepositoryProtocol` — Auto-associate entries with health profile

### Method-by-Method Design

#### `WorkoutService.startWorkout()` — FR-001, FR-004

```
Step 1: CHECK FOR ACTIVE WORKOUT
  - existing = workoutRepo.fetchInProgress()
  - if existing != nil: return existing (FR-004: single active workout)

Step 2: CREATE NEW WORKOUT
  - workout = Workout(
      status: .inProgress,
      startTime: Date(),
      date: Date()  // today
    )
  - workoutRepo.save(workout)
  - return workout
```

#### `WorkoutService.finishWorkout()` — FR-002

```
Step 1: FETCH AND VALIDATE
  - workout = workoutRepo.fetch(byId: workoutId)
  - guard workout != nil else: throw WorkoutServiceError.workoutNotFound
  - guard workout.status != .completed else: throw WorkoutServiceError.workoutAlreadyCompleted

Step 2: UPDATE STATUS
  - workout.status = .completed
  - workout.endTime = Date()
  - workout.duration = Int(workout.endTime!.timeIntervalSince(workout.startTime!))
  - workout.updatedAt = Date()
  - workoutRepo.save(workout)
```

#### `WorkoutService.deleteWorkout()` — FR-010

```
Step 1: FETCH WORKOUT
  - workout = workoutRepo.fetch(byId: workoutId)
  - guard workout != nil

Step 2: GET AFFECTED EXERCISES
  - affectedExerciseIds = setRepo.fetchExerciseIds(for: workoutId)

Step 3: BULK DELETE SETS
  - setRepo.deleteSets(for: workoutId)

Step 4: DELETE WORKOUT
  - workoutRepo.delete(workout)

Step 5: REBUILD PER AFFECTED EXERCISE
  - for exerciseId in affectedExerciseIds:
      prService.rebuild(for: exerciseId)
      statsService.rebuild(for: exerciseId)
```

#### `ExerciseService.updateExercise()` — FR-005, FR-006

```
Step 1: CHECK TRACKINGTYPE IMMUTABILITY
  - hasSets = exerciseRepo.hasAssociatedSets(exercise.id)
  - if hasSets AND exercise.trackingType != originalTrackingType:
      throw ExerciseServiceError.trackingTypeImmutable(exerciseId: exercise.id)

Step 2: DETECT REBUILD-REQUIRED CHANGES
  - needsRebuild = hasSets AND any of these changed:
    (bodyweightFactor, unilateral, bilateralLoadFactor, equipmentType)
  Note: detecting "changed" requires comparing against fetched original.
  The caller passes originalTrackingType; for rebuild fields, the service
  fetches the current persisted exercise to compare.

Step 3: PERSIST
  - exercise.updatedAt = Date()
  - exerciseRepo.save(exercise)

Step 4: REBUILD IF NEEDED
  - if needsRebuild:
      prService.rebuild(for: exercise.id)
      statsService.rebuild(for: exercise.id)
```

#### `ExerciseService.deleteExercise()` — FR-011

```
Step 1: FETCH EXERCISE
  - exercise = exerciseRepo.fetch(byId: exerciseId)
  - guard exercise != nil

Step 2: DELETE ALL SETS
  - setRepo.deleteSets(forExercise: exerciseId)

Step 3: DELETE EXERCISESTATS
  - stats = exerciseStatsRepo.fetch(for: exerciseId)
  - if stats != nil: exerciseStatsRepo.delete(stats)

Step 4: DELETE ALL PERFORMANCERECORDS
  - performanceRecordRepo.deleteAll(for: exerciseId)

Step 5: DELETE EXERCISE
  - exerciseRepo.delete(exercise)
```

#### `BodyweightService.saveEntry()` — FR-008

```
Step 1: GET HEALTH PROFILE
  - profile = healthProfileRepo.fetchOrCreate()

Step 2: CREATE AND PERSIST
  - entry = BodyweightEntry(
      healthProfileId: profile.id,
      date: date,
      bodyweightKg: bodyweightKg
    )
  - bodyweightEntryRepo.save(entry)
  - return entry
```

### ServiceContainer Update

```swift
// ServiceContainer.swift (UPDATED)
@Observable
final class ServiceContainer {
    let prService: any PRServiceProtocol
    let statsService: any StatsServiceProtocol
    let setService: any SetServiceProtocol
    let workoutService: any WorkoutServiceProtocol      // NEW
    let exerciseService: any ExerciseServiceProtocol     // NEW
    let bodyweightService: any BodyweightServiceProtocol // NEW

    init(repositoryContainer: RepositoryContainer) {
        // 1. StatsService — depends on repos only
        let statsService = StatsService(...)

        // 2. PRService — depends on repos only
        let prService = PRService(...)

        // 3. SetService — depends on repos + PRService + StatsService
        let setService = SetService(...)

        // 4. BodyweightService — depends on repos only (simplest)
        let bodyweightService = BodyweightService(
            bodyweightEntryRepository: repositoryContainer.bodyweightEntryRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository
        )

        // 5. WorkoutService — depends on repos + PRService + StatsService
        let workoutService = WorkoutService(
            workoutRepository: repositoryContainer.workoutRepository,
            setRepository: repositoryContainer.setRepository,
            prService: prService,
            statsService: statsService
        )

        // 6. ExerciseService — depends on repos + PRService + StatsService
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

## Implementation Approach

### Order of Implementation

1. **Repository additions** — New methods on SetRepository (3), PerformanceRecordRepository (1), BodyweightEntryRepository (1). Protocol updates + implementations.
2. **Error types + protocols** — `WorkoutServiceError`, `ExerciseServiceError`, `BodyweightServiceError`, three service protocols.
3. **BodyweightService** — Simplest service, no dependencies on other services. CRUD + closest lookup wrapper.
4. **WorkoutService** — Workout lifecycle + cascade deletion with rebuild.
5. **ExerciseService** — Exercise CRUD + trackingType immutability + metadata mutability + cascade deletion.
6. **ServiceContainer update** — Wire all three services into DI container.
7. **Verify build** — Zero errors, all protocols satisfied.

### Scope Boundary

**In scope**: WorkoutService, ExerciseService, BodyweightService, three protocols, three error enums, 5 new repository methods, ServiceContainer wiring.

**Out of scope**: ViewModels, Views, active workout screen (feature 006), exercise list UI (feature 007), CSV import (feature 011), seed data (feature 012). These features will call these services — that orchestration is their responsibility.

## Complexity Tracking

| Risk | Severity | Mitigation |
|------|----------|------------|
| Cascade deletion correctness (orphaned data) | Medium | Clear step-by-step: get exerciseIds → delete sets → delete parent → rebuild. Exercise deletion is simpler (delete everything). |
| Rebuild-required field detection in ExerciseService | Medium | Fetch persisted exercise before save to compare. Pass originalTrackingType explicitly. |
| WorkoutService + ExerciseService both depend on PRService + StatsService | Low | No circular deps. Both use rebuild() which is an existing method. |
| Bulk delete methods on repository | Low | Standard SwiftData batch delete with predicate. Well-understood pattern. |
| BodyweightService simplicity | None | Thin wrapper. Repository already has all the query logic. |
| ServiceContainer growing (6 services) | Low | Still clean initializer injection. No DI framework needed. |

No constitution violations. All decisions traceable to specdoc and AGENT_RULES.
