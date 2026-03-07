# Implementation Plan: Set + Stats Services

**Branch**: `004-set-and-stats-services` | **Date**: 2026-02-23 | **Spec**: `kitty-specs/004-set-and-stats-services/spec.md`
**Input**: Feature specification from `kitty-specs/004-set-and-stats-services/spec.md`

## Summary

Implement `SetService` and `StatsService` — the two business-logic actors that orchestrate the core write path. SetService owns set save/edit/delete, computes effectiveWeight at save time, and triggers the PR + stats pipeline. StatsService owns ExerciseStats updates — incremental on the hot path, Core Data NSExpression aggregation on the rebuild path.

Both are plain Swift actors (not `@ModelActor`) composing existing repository actors via initializer injection. SetService depends on `PRServiceProtocol` (coded against the protocol, wired when feature 003 merges).

**Prerequisites**: Feature 001 (SwiftData models), Feature 002 (Repositories + Indexes). Feature 003 (PRService) — coded against protocol only; merge not required.

## Technical Context

**Language/Version**: Swift (latest stable, Xcode 16+)
**Primary Dependencies**: SwiftData (via repositories), Core Data (NSFetchRequest + NSExpression for aggregation), Foundation
**Target Platform**: iOS 17.0+, iPhone only
**Architecture**: MVVM with Service + Repository layers. SetService and StatsService are the second and third services (PRService from 003 is first).
**Threading Model**: Both services are plain `actor` types. Repositories are `@ModelActor` actors. All repository calls are `async throws`.
**Testing**: Manual testing for v1. No automated tests.
**Performance Goals**: Entire save pipeline (persist + effectiveWeight + PR + stats) must complete within 100ms (AGENT_RULES S5.5, SC-005).
**Constraints**: No iPad, no cloud sync, dark mode only.

**Key Decisions**:

| Decision | Choice | Source |
|----------|--------|--------|
| SetService type | Plain Swift `actor` (not `@ModelActor`) | Services must not access ModelContext (AGENT_RULES S6). |
| StatsService type | Plain Swift `actor` (not `@ModelActor`) | Same rule. Consistent pattern with PRService. |
| Pipeline execution | Sequential: persist → effectiveWeight → PR eval → stats update | specdoc S4.5: "Synchronous execution acceptable initially. Code should be modular for sync or async dispatch." |
| PRService dependency | Code against `PRServiceProtocol` only | Protocol is stable from 003. Wire real impl when 003 merges. |
| effectiveWeight computation | In SetService at save time | specdoc S5.4, AGENT_RULES S3.3, S6: "calculate effectiveWeight — that's SetService's job". |
| Incremental stats (hot path) | Pure arithmetic on ExerciseStats | specdoc S8.4: "Stats aggregates — Write-time — Avoid scanning history". O(1). |
| rebuildAll() aggregation | Core Data `NSFetchRequest` + `NSExpression` for SQL SUM/MAX/COUNT | specdoc S8.6: "Let the database do aggregation work." Not SwiftData sort+fetchLimit workaround. |
| Settings access | Both services inject `HealthProfileRepositoryProtocol` | Same pattern as PRService. Read includeWarmupsInVolume (stats) and includeWarmupsInPRs (passed through). |
| Cross-actor data flow | UUID/primitive parameter passing | SwiftData @Model not Sendable. Established pattern from PRService. |
| Volume calculation | effectiveWeight × reps | specdoc S8.1: "volume = effectiveWeight × reps". Partial excluded always. Warmup excluded per setting. |
| Historical effectiveWeight | Never recalculated retroactively | specdoc S5.4, FR-010: "Store once at save time, never recalculate retroactively." |
| Concurrent saves | Actor isolation provides natural serialization | Spec edge case: "SetService should handle saves sequentially." Actor does this. |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| Architecture layers (Views→VMs→Services→Repos→SwiftData) | PASS | Both services call Repositories only. No ModelContext access. |
| Only repositories touch ModelContext | PASS | SetService uses SetRepository, ExerciseRepository, BodyweightEntryRepository. StatsService uses ExerciseStatsRepository, SetRepository. Core Data NSExpression calls are in the repository layer. |
| All weight in kg, distance in meters, duration in seconds | PASS | effectiveWeight stored in kg. Volume in kg×reps. No imperial anywhere. |
| WorkoutSet naming (not Set) | PASS | All code references `WorkoutSet`. |
| Integer grams for float comparison | PASS | Delegated to PRService (which uses `UnitConversion.toGrams()`). SetService does not compare weights. |
| Database aggregation, not Swift iteration | PASS | rebuildAll() uses Core Data NSExpression for SUM/MAX/COUNT at SQL level (specdoc S8.6). Incremental path uses pre-computed ExerciseStats (no queries). |
| Write-time PR/stats updates | PASS | SetService triggers both PRService and StatsService on every save/edit/delete. No read-time computation. |
| No startup rebuild | PASS | `rebuildAll()` is Settings-only manual action (AGENT_RULES S5.1). |
| Hard delete only | PASS | SetService.delete() does hard delete. Stats decremented. PRs recomputed from remaining sets. |
| effectiveWeight never retroactively recalculated | PASS | FR-010. Historical sets keep original value. Only computed on new save or when set is actively edited. |
| Sets persist immediately (FR-012) | PASS | SetService.save() persists immediately. "Finish Workout" is UI-only. |
| Do NOT invent fields/tables/enums | PASS | No new models. One new value type (SetAggregateResult) for aggregation return. Two new protocols. |
| Services: single responsibility (AGENT_RULES S6) | PASS | SetService orchestrates pipeline. StatsService owns stats. PRService owns PRs. No overlap. |
| Prefer async/await | PASS | All service methods are `async throws`. |
| No third-party deps | PASS | Pure Swift + Foundation + Core Data (system framework). |
| Memory management (AGENT_RULES S5.3) | PASS | rebuildAll() never loads all sets into memory — uses SQL aggregation. Incremental path touches one ExerciseStats object. |
| Performance: <100ms set save | PASS | All operations are local SwiftData/CoreData. Sequential pipeline well within budget. |

**Post-Phase-1 re-check**: All principles pass. Core Data NSExpression aggregation is a repository-layer concern (touches data layer), consistent with architecture. No constitution violations.

## Project Structure

### Documentation (this feature)

```
kitty-specs/004-set-and-stats-services/
├── spec.md
├── meta.json
├── plan.md                          # This file
├── research.md                      # Phase 0: Research findings
├── data-model.md                    # Phase 1: Entity interaction mapping
├── contracts/                       # Phase 1: Service protocol definitions
│   ├── SetServiceProtocol.swift
│   └── StatsServiceProtocol.swift
├── tasks/                           # Generated by /spec-kitty.tasks
```

### Source Code (repository root)

```
Reppo/Core/Services/
├── Protocols/
│   ├── PRServiceProtocol.swift      (from 003 — dependency)
│   ├── SetServiceProtocol.swift     (NEW)
│   └── StatsServiceProtocol.swift   (NEW)
├── PRService.swift                  (from 003 — dependency)
├── SetService.swift                 (NEW)
├── StatsService.swift               (NEW)
├── ServiceContainer.swift           (UPDATED — add SetService, StatsService)

Reppo/Core/Repositories/
├── Protocols/
│   └── SetRepositoryProtocol.swift  (UPDATED — add aggregation methods)
├── SetRepository.swift              (UPDATED — implement aggregation via Core Data NSExpression)
```

## Phase 0: Research

Research findings consolidated in `kitty-specs/004-set-and-stats-services/research.md`.

### Key Findings

| Topic | Decision | Rationale | Alternatives Considered |
|-------|----------|-----------|------------------------|
| Service threading model | Plain `actor` for both SetService and StatsService | AGENT_RULES S6: services must not access ModelContext. Matches PRService pattern. | `@ModelActor` (violates rules), plain class (no concurrency safety) |
| Pipeline execution order | Sequential: persist → effectiveWeight → PR → stats | specdoc S4.5, FR-002 ("after persisting"), FR-003 ("after PR evaluation") | Parallel PR+stats (violates FR-003 ordering, marginal benefit) |
| effectiveWeight location | Computed in SetService.save()/edit() | AGENT_RULES S6: "calculate effectiveWeight — that's SetService's job" | In SetRepository (wrong layer), in ViewModel (wrong layer) |
| rebuildAll() aggregation | Core Data NSFetchRequest + NSExpression | specdoc S8.6: "Let the database do aggregation work." The bible says SQL aggregation. | SwiftData fetchLimit batching (still loads objects), raw SQLite (too low-level) |
| Incremental stats | Pure arithmetic on ExerciseStats | specdoc S8.4: "Write-time, avoid scanning history." O(1) adjustments. | Re-query totals on each save (violates S8.4, unnecessary IO) |
| PRService dependency | Code against PRServiceProtocol | Protocol stable from 003. Decouples from merge status. | Branch off 003 (merge conflicts), wait for merge (blocks work) |
| Cross-actor data flow | UUID/primitive params, not @Model objects | SwiftData models not Sendable. Established pattern from PRService. | DTOs (extra mapping), PersistentIdentifier (internal API), pass @Model (unsafe) |
| Settings access | HealthProfileRepositoryProtocol injected | Same pattern as PRService. O(1) single-row read. | Global singleton (wrong pattern), pass as param (pushes concern to caller) |
| Concurrent saves | Actor isolation serializes naturally | Spec: "handle saves sequentially." Actor does this without explicit locking. | Serial DispatchQueue (old pattern), explicit mutex (unnecessary with actors) |
| Repository additions | New aggregation methods on SetRepository using Core Data | Repository layer is where ModelContext lives. NSExpression is a Core Data API. Consistent. | New AggregationRepository (unnecessary separation), StatsService touches Core Data directly (violates architecture) |

### Critical Implementation Detail: Core Data NSExpression for Aggregation

SwiftData's `FetchDescriptor` cannot do SUM/AVG/GROUP BY. For `rebuildAll()`, the SetRepository drops to Core Data:

```swift
// In SetRepository (which is @ModelActor with access to modelContext)
// Access underlying NSManagedObjectContext from SwiftData's ModelContext
let nsContext = modelContext.managedObjectContext  // Bridge to Core Data

let request = NSFetchRequest<NSDictionary>(entityName: "WorkoutSet")
request.predicate = NSPredicate(format: "exerciseId == %@", exerciseId as CVarArg)
request.resultType = .dictionaryResultType

let sumVolume = NSExpressionDescription()
sumVolume.name = "totalVolume"
sumVolume.expression = NSExpression(
    forFunction: "sum:",
    arguments: [NSExpression(forKeyPath: "effectiveWeight")]  // Simplified; actual: effectiveWeight * reps
)
sumVolume.expressionResultType = .doubleAttributeType

request.propertiesToFetch = [sumVolume, /* count, max, etc. */]
```

This produces real SQL `SELECT SUM(...), COUNT(...), MAX(...) FROM WorkoutSet WHERE ...` — exactly what the specdoc prescribes.

**Note**: The `modelContext.managedObjectContext` bridge may require `import CoreData` in the repository implementation. This is acceptable — repositories are the data access layer.

### Repository Gap Resolution

**New methods on `SetRepositoryProtocol`**:

```swift
/// Aggregate stats using Core Data NSExpression for database-level SUM/MAX/COUNT.
func fetchAggregateStats(
    for exerciseId: UUID,
    excludeWarmups: Bool,
    excludePartial: Bool
) async throws -> SetAggregateResult

/// Count distinct workouts containing sets for a given exercise.
func fetchWorkoutCount(for exerciseId: UUID) async throws -> Int

/// Fetch the best e1RM value for an exercise using sort DESC + fetchLimit(1).
func fetchBestE1RM(for exerciseId: UUID) async throws -> Double?
```

These are cold-path only (used by `rebuildAll()`). The hot path (incremental) uses pure arithmetic on ExerciseStats.

## Phase 1: Design & Contracts

### SetServiceProtocol

Full contract in `kitty-specs/004-set-and-stats-services/contracts/SetServiceProtocol.swift`.

**Methods**:
- `save(_ set: WorkoutSet) async throws -> SetSaveResult`
- `edit(_ set: WorkoutSet) async throws -> SetSaveResult`
- `delete(_ set: WorkoutSet) async throws`

### StatsServiceProtocol

Full contract in `kitty-specs/004-set-and-stats-services/contracts/StatsServiceProtocol.swift`.

**Methods**:
- `updateStats(for exerciseId: UUID, event: StatsUpdateEvent) async throws`
- `rebuildAll() async throws`
- `rebuild(for exerciseId: UUID) async throws`

### SetService Implementation Design

```swift
actor SetService: SetServiceProtocol {
    private let setRepo: SetRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol
    private let bodyweightEntryRepo: BodyweightEntryRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol
    private let prService: PRServiceProtocol
    private let statsService: StatsServiceProtocol

    init(
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol,
        bodyweightEntryRepository: BodyweightEntryRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol,
        prService: PRServiceProtocol,
        statsService: StatsServiceProtocol
    ) { ... }
}
```

**Dependencies** (6 total):
- `SetRepositoryProtocol` — CRUD for WorkoutSet
- `ExerciseRepositoryProtocol` — read bodyweightFactor for effectiveWeight
- `BodyweightEntryRepositoryProtocol` — read closest bodyweight for effectiveWeight
- `HealthProfileRepositoryProtocol` — read user settings
- `PRServiceProtocol` — PR evaluation (from 003, coded against protocol)
- `StatsServiceProtocol` — stats update (circular ref resolved: SetService holds protocol, StatsService is concrete)

### StatsService Implementation Design

```swift
actor StatsService: StatsServiceProtocol {
    private let exerciseStatsRepo: ExerciseStatsRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol

    init(
        exerciseStatsRepository: ExerciseStatsRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol
    ) { ... }
}
```

**Dependencies** (4 total):
- `ExerciseStatsRepositoryProtocol` — read/write ExerciseStats
- `SetRepositoryProtocol` — aggregation queries for rebuildAll()
- `ExerciseRepositoryProtocol` — enumerate exercises for rebuildAll()
- `HealthProfileRepositoryProtocol` — read includeWarmupsInVolume

### Method-by-Method Pipeline Mapping

#### `SetService.save()` — Save Pipeline (specdoc S4, S5.4, FR-001/002/003/012)

```
Step 1: COMPUTE effectiveWeight (S5.4, AGENT_RULES S3.3)
  - exercise = exerciseRepo.fetch(byId: set.exerciseId)
  - if exercise.bodyweightFactor > 0:
      profile = healthProfileRepo.fetchOrCreate()
      closestBW = bodyweightEntryRepo.fetchClosest(to: set.date, healthProfileId: profile.id)
      if closestBW exists:
        set.effectiveWeight = set.weight + (closestBW.bodyweightKg × exercise.bodyweightFactor)
      else:
        set.effectiveWeight = set.weight  // warn user to log bodyweight
  - if exercise.bodyweightFactor == 0:
      set.effectiveWeight = set.weight

Step 2: PERSIST (FR-012: immediate)
  - setRepo.save(set)

Step 3: PR EVALUATION (FR-002)
  - prResult = prService.evaluate(
      setId: set.id, exerciseId: set.exerciseId, reps: set.reps,
      effectiveWeight: set.effectiveWeight, workoutId: set.workoutId,
      setType: set.setType, hasData: set.hasData,
      excludeFromPRs: set.excludeFromPRs, date: set.date
    )

Step 4: STATS UPDATE (FR-003)
  - statsService.updateStats(for: set.exerciseId, event: .save(
      reps: set.reps, effectiveWeight: set.effectiveWeight,
      setType: set.setType, hasData: set.hasData,
      date: set.date, workoutId: set.workoutId
    ))

Step 5: RETURN
  - return SetSaveResult(setId: set.id, effectiveWeight: set.effectiveWeight, prResult: prResult)
```

#### `SetService.edit()` — Edit Pipeline (specdoc S4.4, FR-004)

```
Step 1: CAPTURE OLD VALUES
  - oldSet = setRepo.fetch(byId: set.id)
  - oldReps = oldSet.reps, oldEffectiveWeight = oldSet.effectiveWeight, etc.

Step 2: RECOMPUTE effectiveWeight
  - Same logic as save Step 1

Step 3: PERSIST
  - setRepo.save(set)

Step 4: PR RE-EVALUATION (FR-004)
  - prResult = prService.evaluateAfterEdit(
      ..., previousCachedPRStatus: oldSet.cachedPRStatus, ...
    )

Step 5: STATS UPDATE (with delta)
  - statsService.updateStats(for: set.exerciseId, event: .edit(
      oldReps:, oldEffectiveWeight:, ..., newReps:, newEffectiveWeight:, ...
    ))
```

#### `SetService.delete()` — Delete Pipeline (specdoc S4.4, FR-005)

```
Step 1: CAPTURE VALUES
  - Capture set.reps, set.effectiveWeight, set.cachedPRStatus, etc. before deletion

Step 2: DELETE
  - setRepo.delete(set)

Step 3: PR RECOMPUTATION (FR-005)
  - prService.handleDeletion(
      setId: set.id, exerciseId: set.exerciseId,
      reps: set.reps, cachedPRStatus: set.cachedPRStatus
    )

Step 4: STATS DECREMENT
  - statsService.updateStats(for: set.exerciseId, event: .delete(
      reps:, effectiveWeight:, setType:, hasData:, date:, workoutId:
    ))
```

#### `StatsService.updateStats()` — Incremental (FR-007, specdoc S8.4)

```
Case .save:
  - stats = exerciseStatsRepo.fetch(for: exerciseId) ?? create new ExerciseStats
  - if hasData AND not excluded (partial always, warmup per setting):
      stats.totalSets += 1
      stats.totalReps += reps
      stats.totalVolume += effectiveWeight × reps
      if effectiveWeight > stats.maxWeight: stats.maxWeight = effectiveWeight
      stats.lastPerformedDate = max(stats.lastPerformedDate, date)
  - exerciseStatsRepo.save(stats)

Case .edit:
  - Compute delta between old and new values
  - Adjust totals by delta
  - If old was counted but new is not (or vice versa), handle inclusion change
  - If maxWeight changed, may need fetchMaxEffectiveWeight() re-query

Case .delete:
  - if was counted:
      stats.totalSets -= 1
      stats.totalReps -= reps
      stats.totalVolume -= effectiveWeight × reps
  - if effectiveWeight == stats.maxWeight:
      stats.maxWeight = setRepo.fetchMaxEffectiveWeight(for: exerciseId, reps: 0) ?? 0
      // Note: fetchMaxEffectiveWeight needs to work across all reps for this
```

#### `StatsService.rebuildAll()` — Full Rebuild (FR-008, specdoc S8.6)

```
1. profile = healthProfileRepo.fetchOrCreate()
2. excludeWarmups = !profile.includeWarmupsInVolume
3. exercises = exerciseRepo.fetchAll()
4. For each exercise:
     rebuild(for: exercise.id)
```

#### `StatsService.rebuild(for:)` — Single Exercise Rebuild

```
1. Delete existing ExerciseStats for this exercise (if exists)
2. aggregateResult = setRepo.fetchAggregateStats(exerciseId, excludeWarmups, excludePartial: true)
     → Core Data NSExpression: SUM(reps), SUM(effectiveWeight*reps), MAX(effectiveWeight), MAX(date), COUNT(*)
3. workoutCount = setRepo.fetchWorkoutCount(for: exerciseId)
4. bestE1RM = setRepo.fetchBestE1RM(for: exerciseId)
5. Create new ExerciseStats(
     exerciseId, totalWorkouts: workoutCount,
     totalSets: aggregateResult.totalSets,
     totalReps: aggregateResult.totalReps,
     totalVolume: aggregateResult.totalVolume,
     maxWeight: aggregateResult.maxWeight,
     bestE1RM: bestE1RM ?? 0,
     lastPerformedDate: aggregateResult.lastPerformedDate,
     ...
   )
6. exerciseStatsRepo.save(newStats)
```

### ServiceContainer Update

```swift
// ServiceContainer.swift (UPDATED)
@Observable
final class ServiceContainer {
    let prService: PRServiceProtocol
    let statsService: StatsServiceProtocol
    let setService: SetServiceProtocol

    init(repositoryContainer: RepositoryContainer) {
        let prService = PRService(
            performanceRecordRepository: repositoryContainer.performanceRecordRepository,
            setRepository: repositoryContainer.setRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository,
            exerciseRepository: repositoryContainer.exerciseRepository
        )

        let statsService = StatsService(
            exerciseStatsRepository: repositoryContainer.exerciseStatsRepository,
            setRepository: repositoryContainer.setRepository,
            exerciseRepository: repositoryContainer.exerciseRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository
        )

        let setService = SetService(
            setRepository: repositoryContainer.setRepository,
            exerciseRepository: repositoryContainer.exerciseRepository,
            bodyweightEntryRepository: repositoryContainer.bodyweightEntryRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository,
            prService: prService,
            statsService: statsService
        )

        self.prService = prService
        self.statsService = statsService
        self.setService = setService
    }
}
```

## Implementation Approach

### Order of Implementation

1. **Value types + protocols** — `SetAggregateResult`, `StatsUpdateEvent`, `SetSaveResult`, `SetServiceProtocol`, `StatsServiceProtocol`
2. **Repository additions** — Core Data aggregation methods on SetRepository (fetchAggregateStats, fetchWorkoutCount, fetchBestE1RM)
3. **StatsService** — incremental updateStats() + rebuild() + rebuildAll() (StatsService has no dependency on SetService, can be built first)
4. **SetService** — save/edit/delete orchestration with effectiveWeight, PR, and stats pipeline
5. **ServiceContainer update** — wire both services into DI container
6. **Verify build** — zero errors, all protocols satisfied

### Scope Boundary

**In scope**: SetService, StatsService, SetServiceProtocol, StatsServiceProtocol, value types (SetAggregateResult, StatsUpdateEvent, SetSaveResult), SetRepository aggregation methods, ServiceContainer wiring.

**Out of scope**: ViewModels, Views, WorkoutService (feature 005), ExerciseService (feature 005), BodyweightService (feature 005), active workout screen (feature 006), CSV import (feature 011). These features will call SetService — that orchestration is their responsibility.

## Complexity Tracking

| Risk | Severity | Mitigation |
|------|----------|------------|
| Core Data NSExpression complexity in SwiftData context | Medium | Bridge via `modelContext.managedObjectContext` (documented). Repository layer is where Core Data lives. Test with real SwiftData ModelContainer. |
| SwiftData `#Predicate` limitations for aggregation filters | Medium | Aggregation uses Core Data NSPredicate directly (not SwiftData #Predicate). No limitation. |
| effectiveWeight for sets where weight is nil | Low | If weight is nil, effectiveWeight = nil. Set won't have hasData=true unless it has actual values. Stats/PR skip sets with hasData=false. |
| maxWeight re-query on delete (hot path) | Low | Only needed when deleted set had maxWeight. fetchMaxEffectiveWeight uses sort+limit(1) — O(1). Rare case. |
| ServiceContainer circular dependency (SetService ↔ StatsService) | None | No circular dependency. SetService holds StatsServiceProtocol. StatsService does not reference SetService. One-directional. |
| Performance: 100ms budget | Low | All operations local SwiftData. Sequential pipeline: ~5ms persist + ~5ms effectiveWeight + ~10ms PR eval + ~5ms stats update = ~25ms. Well within budget. |

No constitution violations. All decisions traceable to specdoc and AGENT_RULES.
