# Research: Set + Stats Services

**Feature**: 004-set-and-stats-services
**Date**: 2026-02-23
**Status**: Complete

## Research Questions

### 1. SetService Threading Model

**Question**: Should SetService be a `@ModelActor` or a plain Swift `actor`?

**Decision**: Plain Swift `actor` composing repository and service protocols via initializer injection.

**Rationale**:
- AGENT_RULES Section 6 explicitly states: SetService "does NOT access ModelContext directly"
- Matches the established pattern from PRService (feature 003) — plain actor composing `@ModelActor` repositories
- specdoc S8.5: "PR pipeline runs on background queue/context" — satisfied by repositories being `@ModelActor` actors
- Concurrency isolation without duplicating ModelContext management

**Alternatives Considered**:
- `@ModelActor` SetService: Would give direct ModelContext access, but violates AGENT_RULES S6 architecture rule. Services call repositories, period.
- Plain class (non-actor): No concurrent-access protection. specdoc edge case notes "concurrent saves: SetService should handle saves sequentially" — actor provides this naturally.

### 2. StatsService Threading Model

**Question**: Same question for StatsService.

**Decision**: Plain Swift `actor`, same pattern as PRService and SetService.

**Rationale**:
- Same AGENT_RULES S6 constraint: StatsService "does NOT own PR logic" and accesses data through repositories only
- Called by SetService after PR evaluation — the actor boundary naturally serializes stats updates
- Consistent service-layer pattern across the entire project

### 3. SetService Pipeline Order

**Question**: What is the exact orchestration order for set save?

**Decision**: Sequential pipeline: persist → effectiveWeight → PRService.evaluate → StatsService.updateStats

**Rationale**:
- specdoc S4.5: "PR/stat computation runs as a bounded, cheap work unit after set save. Synchronous execution acceptable initially."
- specdoc S8.5: "Code should be modular for sync or async dispatch"
- spec FR-002: "SetService.save(set) MUST call PRService.evaluate(set) after persisting"
- spec FR-003: "SetService.save(set) MUST call StatsService.updateStats(for: exerciseId) after PR evaluation"
- The ordering is explicit: persist first, then PR, then stats. Sequential.

**Alternatives Considered**:
- Parallel PR + stats after persist: Saves ~10ms but specdoc mandates stats update "after PR evaluation" (FR-003), and the 100ms budget is easily met sequentially with local SwiftData operations.

### 4. effectiveWeight Computation Location

**Question**: Where exactly does effectiveWeight get computed?

**Decision**: Inside SetService.save() and SetService.edit(), before persisting the set.

**Rationale**:
- specdoc S5.4: "At set save time, compute and store" effectiveWeight
- AGENT_RULES S3.3: "Every time a set is saved, compute and store effectiveWeight"
- AGENT_RULES S6: SetService "Save/edit/delete sets, orchestrate PR + stats pipeline" — effectiveWeight is part of set save orchestration
- BodyweightService's responsibility is "CRUD for bodyweight entries, closest-weight lookup" but NOT "calculate effectiveWeight (that's SetService's job)" per AGENT_RULES S6

**Implementation**:
- SetService calls `bodyweightEntryRepo.fetchClosest(to: set.date, healthProfileId:)` to get nearest bodyweight
- SetService calls `exerciseRepo.fetch(byId: set.exerciseId)` to get bodyweightFactor
- SetService computes: `effectiveWeight = weight + (closestBodyweight × bodyweightFactor)`
- Stores on the set before persisting

### 5. StatsService rebuildAll() Aggregation Strategy

**Question**: SwiftData has no native SUM/AVG/GROUP BY. How does `rebuildAll()` achieve database-level aggregation as mandated by specdoc S8.6?

**Decision**: Drop to Core Data's `NSFetchRequest` with `NSExpression` for real SQL SUM/MAX/COUNT/GROUP BY at the SQLite level.

**Rationale**:
- specdoc S8.6 is explicit: "**Critical principle:** Let the database do aggregation work. Do not load large collections into code to iterate."
- specdoc shows the correct pattern: `SELECT SUM(effectiveWeight * reps) FROM WorkoutSet WHERE exerciseId = ?`
- AGENT_RULES S5.2: "❌ NEVER DO THIS: `let sets = try await repository.fetchAllSets(...)` // loads 500+ sets"
- The constitution's workaround ("use pre-computed ExerciseStats") applies to the hot path (incremental updates). But `rebuildAll()` IS the recomputation path — it must derive from raw data using database aggregation.
- SwiftData sits on Core Data. `NSFetchRequest` with `NSExpression` for `sum:`, `max:`, `count:` is available via the underlying Core Data store.

**Implementation approach**:
- Add aggregation methods to `SetRepository` that use `NSFetchRequest` + `NSExpressionDescription` under the hood
- Methods: `fetchAggregateStats(for exerciseId:, excludeWarmups:, excludePartial:) -> AggregateResult`
- AggregateResult contains: totalSets, totalReps, totalVolume, maxWeight, maxSessionVolume, lastPerformedDate
- This is a repository-level concern (it touches the data layer), consistent with architecture rules
- StatsService calls this single method, receives all aggregates in one result

**Alternatives Considered**:
- Batch per-exercise with SwiftData fetchLimit: Still loads objects into Swift memory. Not true database aggregation. Violates the specdoc's stated principle even if the per-exercise batch is small.
- Raw SQLite queries: Too low-level. Core Data's NSExpression API gives the same SQL-level aggregation without dropping below the Core Data abstraction.

### 6. Incremental Stats Update Strategy

**Question**: How does StatsService handle incremental updates on the hot path (FR-007)?

**Decision**: Pure arithmetic on the existing ExerciseStats object. No database queries.

**Rationale**:
- specdoc S8.4: "Stats aggregates — Write-time — Avoid scanning history"
- The hot path (save/edit/delete) must complete in <100ms total (FR-011/SC-005)
- For a new set: `stats.totalSets += 1`, `stats.totalReps += reps`, `stats.totalVolume += effectiveWeight * reps`, etc.
- For edit: compute delta (new - old) and adjust
- For delete: decrement
- No DB aggregation needed — we adjust the cached values directly

**Edge cases**:
- `maxWeight` changes on delete: If deleted set had maxWeight, must query for new max. Use `setRepo.fetchMaxEffectiveWeight(for:reps:)` — sort+limit(1), O(1).
- `bestE1RM` changes: Same approach — sort+limit(1) query for new best.
- `totalWorkouts` on delete: Must check if any remaining sets exist for this exercise in the deleted set's workout. Requires one query.

### 7. Cross-Actor Data Flow Pattern

**Question**: How does SetService pass data to PRService and StatsService?

**Decision**: Same pattern as PRService: pass primitive/value-type parameters (UUIDs, Double, Int, Date, enums), not @Model objects.

**Rationale**:
- SwiftData @Model objects are not Sendable and bound to their creating ModelContext
- PRService already establishes this pattern — evaluate() accepts (setId, exerciseId, reps, effectiveWeight, ...)
- StatsService will accept similar primitives for incremental updates
- SetService has all these values available after computing effectiveWeight

### 8. PRService Dependency — Coding Against Protocol

**Question**: PRService is implemented on feature 003 branches but not merged to master. How does feature 004 depend on it?

**Decision**: Code against `PRServiceProtocol` only. Wire the real implementation when 003 merges.

**Rationale**:
- `PRServiceProtocol` is fully defined and stable (confirmed across all 4 WPs of feature 003)
- SetService depends on the protocol abstraction, not the concrete PRService
- This keeps 004 independent of 003's merge status
- When 003 merges, the real PRService gets injected via ServiceContainer — zero code changes in 004
- Follows constitution principle: depend on abstractions, not implementations

### 9. HealthProfile Settings Access in StatsService

**Question**: How does StatsService access `includeWarmupsInVolume`?

**Decision**: Inject `HealthProfileRepositoryProtocol`, same pattern as PRService.

**Rationale**:
- PRService already takes `HealthProfileRepositoryProtocol` to read `includeWarmupsInPRs`
- StatsService needs `includeWarmupsInVolume` for the same reason — configurable warmup exclusion
- Read is O(1) — single-row table with fetchOrCreate()
- Consistent dependency injection pattern across all services

### 10. Repository Additions Needed

**Question**: What new repository methods does feature 004 require?

**Decision**: Add Core Data aggregation methods to SetRepository.

**New methods on SetRepositoryProtocol**:

```swift
/// Aggregate stats for an exercise using database-level aggregation (Core Data NSExpression).
/// Used by StatsService.rebuildAll() — not for hot-path incremental updates.
/// Returns: totalSets, totalReps, totalVolume, maxWeight, lastPerformedDate, etc.
func fetchAggregateStats(
    for exerciseId: UUID,
    excludeWarmups: Bool,
    excludePartial: Bool
) async throws -> SetAggregateResult

/// Count distinct workouts containing sets for a given exercise.
/// Used by StatsService for totalWorkouts calculation during rebuild.
func fetchWorkoutCount(for exerciseId: UUID) async throws -> Int

/// Fetch the best e1RM for an exercise.
/// Uses sort DESC + fetchLimit(1).
func fetchBestE1RM(for exerciseId: UUID) async throws -> Double?
```

**Value type**:
```swift
struct SetAggregateResult: Sendable {
    let totalSets: Int
    let totalReps: Int
    let totalVolume: Double
    let maxWeight: Double
    let lastPerformedDate: Date?
}
```

**Existing methods sufficient for hot path**:
- `fetchMaxEffectiveWeight(for:reps:)` — already exists, used for maxWeight re-query on delete
- `fetchTotalVolume(for:)` — already exists but uses Swift iteration; will be replaced by Core Data aggregation version for rebuild

## Summary

All research questions resolved. No unknowns remain. Key architectural decisions:
- Plain actor + repository composition for both SetService and StatsService (not @ModelActor)
- Sequential save pipeline: persist → effectiveWeight → PR eval → stats update (specdoc S4.5)
- effectiveWeight computed in SetService at save time (AGENT_RULES S6)
- Core Data `NSFetchRequest` + `NSExpression` for rebuildAll() aggregation (specdoc S8.6)
- Pure arithmetic incremental updates on hot path (specdoc S8.4)
- Code against PRServiceProtocol only — independent of 003 merge status
- UUID/primitive parameter passing across actor boundaries (established pattern)
