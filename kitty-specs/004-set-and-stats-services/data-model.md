# Data Model: Set + Stats Services

**Feature**: 004-set-and-stats-services
**Date**: 2026-02-23

## Entity Interaction Map

SetService and StatsService operate on existing entities. No new entities are created. One new value type (`SetAggregateResult`) is introduced for the aggregation path. One new protocol (`StatsServiceProtocol`) and one new protocol (`SetServiceProtocol`) are introduced.

### Entities Touched by SetService

| Entity | Role | Access Pattern | Source |
|--------|------|----------------|--------|
| `WorkoutSet` | **Primary** — sets are saved/edited/deleted through SetService. effectiveWeight is computed and stored here. | Read: fetch by ID. Write: save, edit (effectiveWeight, all mutable fields), delete. | specdoc S6.1, AGENT_RULES S6 |
| `Exercise` | **Read-only** — needed for bodyweightFactor to compute effectiveWeight. | Read: fetch by ID. Never written by SetService. | specdoc S5.4 |
| `BodyweightEntry` | **Read-only** — closest bodyweight for effectiveWeight calculation. | Read: fetchClosest(to: date). Never written by SetService. | specdoc S5.4, AGENT_RULES S3.3 |
| `HealthProfile` | **Read-only** — needed for settings (includeWarmupsInPRs passed to PRService context). | Read: fetchOrCreate(). Never written by SetService. | specdoc S6.7 |

### Entities Touched by StatsService

| Entity | Role | Access Pattern | Source |
|--------|------|----------------|--------|
| `ExerciseStats` | **Primary** — the rebuildable cache updated by StatsService. | Read: fetch by exerciseId. Write: create, update (all aggregate fields). Delete during rebuild. | specdoc S6.4, FR-007, FR-008 |
| `WorkoutSet` | **Read-only** — source data for aggregation during rebuildAll(). | Read: aggregate queries via Core Data NSExpression. Never written by StatsService. | specdoc S8.6 |
| `Exercise` | **Read-only** — enumeration for rebuildAll(). | Read: fetchAll(). Never written by StatsService. | specdoc S6.2 |
| `HealthProfile` | **Read-only** — `includeWarmupsInVolume` setting. | Read: fetchOrCreate(). Never written by StatsService. | specdoc S6.7 |

### Entity: WorkoutSet (fields relevant to SetService pipeline)

```
WorkoutSet (@Model) — SetService-relevant fields
├── id: UUID (PK)
├── workoutId: UUID (FK → Workout)
├── exerciseId: UUID (FK → Exercise)
├── date: Date
├── startedAt: Date?
├── completedAt: Date?
├── weight: Double? (raw user-entered weight)
├── effectiveWeight: Double? (computed at save time by SetService)
├── reps: Int?
├── durationSeconds: Int?
├── distanceMeters: Double?
├── e1RM: Double? (snapshot at save time)
├── e1RMFormulaVersion: String?
├── setType: SetType
├── completed: Bool
├── excludeFromPRs: Bool?
├── cachedPRStatus: CachedPRStatus? (written by PRService via evaluate result)
├── hasData: Bool (computed property)
└── volume: Double? (computed: effectiveWeight * reps)

Index (iOS 18): #Index<WorkoutSet>([\.exerciseId, \.reps, \.effectiveWeight, \.date])
```

**SetService operations on WorkoutSet**:
- `SAVE`: Compute effectiveWeight, persist via SetRepository, then trigger PR + stats pipeline
- `EDIT`: Recompute effectiveWeight, persist, re-trigger PR (evaluateAfterEdit) + stats pipeline
- `DELETE`: Delete via SetRepository, trigger PR (handleDeletion) + stats decrement

**SetService writes these fields**:
- `effectiveWeight` — computed at save time (S5.4)
- `e1RM` — optional snapshot at save time (S4.3)
- All user-mutable fields on edit (weight, reps, setType, etc.)

**SetService does NOT write**:
- `cachedPRStatus` — that's PRService's job (AGENT_RULES S6)

### Entity: ExerciseStats (StatsService primary entity)

```
ExerciseStats (@Model)
├── id: UUID (PK)
├── exerciseId: UUID (FK → Exercise, unique)
├── totalWorkouts: Int
├── totalSets: Int
├── totalReps: Int
├── totalVolume: Double (Σ effectiveWeight × reps)
├── maxWeight: Double (best single effectiveWeight)
├── bestE1RM: Double
├── averageIntensity: Double
├── estimated1RMTrendSlope: Double
├── lastPRDate: Date?
├── lastPerformedDate: Date?
├── maxSessionVolume: Double (best per-workout volume)
├── createdAt: Date
└── updatedAt: Date
```

**StatsService operations on ExerciseStats**:
- `INCREMENTAL UPDATE` (hot path): Adjust totals by delta after save/edit/delete. O(1) arithmetic.
- `REBUILD` (cold path): Delete existing ExerciseStats, recompute from raw sets via Core Data aggregation.
- `CREATE`: When first set for an exercise is saved and no ExerciseStats exists yet.

### Entity: Exercise (fields relevant to effectiveWeight)

```
Exercise (@Model) — SetService-relevant fields only
├── exerciseId: UUID
├── bodyweightFactor: Double (0.0 to 1.0)
└── trackingType: TrackingType
```

### Entity: BodyweightEntry (fields relevant to effectiveWeight)

```
BodyweightEntry (@Model) — SetService-relevant fields only
├── healthProfileId: UUID
├── date: Date
└── bodyweightKg: Double
```

**SetService reads**: `bodyweightEntryRepo.fetchClosest(to: set.date, healthProfileId:)` to get closest bodyweight for effectiveWeight calculation. If none exists, effectiveWeight = weight (warn user).

## Data Flow Diagrams

### Save Pipeline (specdoc S4, S5.4, S8)

```
SetService.save(set)
  │
  ├── 1. COMPUTE effectiveWeight
  │     ├── exerciseRepo.fetch(byId: exerciseId) → bodyweightFactor
  │     ├── if bodyweightFactor > 0:
  │     │     bodyweightEntryRepo.fetchClosest(to: date) → closestBodyweight
  │     │     effectiveWeight = weight + (closestBodyweight × bodyweightFactor)
  │     └── if bodyweightFactor == 0 OR no bodyweight entry:
  │           effectiveWeight = weight
  │
  ├── 2. PERSIST set (with effectiveWeight stored)
  │     └── setRepo.save(set)
  │
  ├── 3. PR EVALUATION (specdoc S7.2)
  │     └── prService.evaluate(setId, exerciseId, reps, effectiveWeight, ...)
  │           → PREvaluationResult (newStatus, affectedSetIds, prRecordChanged)
  │
  └── 4. STATS UPDATE (FR-003)
        └── statsService.updateStats(for: exerciseId, event: .save(set details))
              → ExerciseStats incremented
```

### Edit Pipeline (specdoc S4.4)

```
SetService.edit(set)
  │
  ├── 1. CAPTURE old values (for incremental stats delta)
  │
  ├── 2. RECOMPUTE effectiveWeight with new values
  │
  ├── 3. PERSIST updated set
  │     └── setRepo.save(set)
  │
  ├── 4. PR RE-EVALUATION (specdoc S4.4 "On Set Edit")
  │     └── prService.evaluateAfterEdit(setId, exerciseId, ..., previousCachedPRStatus)
  │
  └── 5. STATS UPDATE (with old → new delta)
        └── statsService.updateStats(for: exerciseId, event: .edit(old, new))
```

### Delete Pipeline (specdoc S4.4)

```
SetService.delete(set)
  │
  ├── 1. CAPTURE set values (for stats decrement and PR handling)
  │
  ├── 2. DELETE set
  │     └── setRepo.delete(set)
  │
  ├── 3. PR RECOMPUTATION (specdoc S4.4 "On Set Delete")
  │     └── prService.handleDeletion(setId, exerciseId, reps, cachedPRStatus)
  │
  └── 4. STATS DECREMENT
        └── statsService.updateStats(for: exerciseId, event: .delete(set details))
```

### Stats Rebuild Pipeline (FR-008, specdoc S8.6)

```
StatsService.rebuildAll()
  │
  ├── 1. Fetch HealthProfile (includeWarmupsInVolume)
  │
  ├── 2. Fetch all exercises
  │
  └── 3. For each exercise:
        ├── Delete existing ExerciseStats
        ├── setRepo.fetchAggregateStats(exerciseId, excludeWarmups, excludePartial: true)
        │     └── Core Data NSFetchRequest + NSExpression
        │         SELECT COUNT(*), SUM(reps), SUM(effectiveWeight * reps), MAX(effectiveWeight), MAX(date)
        │         FROM WorkoutSet WHERE exerciseId = ? [AND setType filters]
        ├── setRepo.fetchBestE1RM(for: exerciseId)
        ├── setRepo.fetchWorkoutCount(for: exerciseId)
        └── Create new ExerciseStats with aggregated values
```

## Value Types Introduced

| Type | Purpose | Fields |
|------|---------|--------|
| `SetAggregateResult` | Return type from Core Data aggregation query | `totalSets: Int`, `totalReps: Int`, `totalVolume: Double`, `maxWeight: Double`, `lastPerformedDate: Date?` |
| `StatsUpdateEvent` | Enum describing what triggered the stats update | `.save(reps:, effectiveWeight:, setType:, hasData:, date:, workoutId:)`, `.edit(old:, new:)`, `.delete(reps:, effectiveWeight:, setType:, hasData:, date:, workoutId:)` |
| `SetSaveResult` | Return type from SetService.save() | `set: WorkoutSet ID`, `prResult: PREvaluationResult`, `effectiveWeight: Double` |

All are `Sendable` structs/enums — safe to pass across actor boundaries.

## Repository Additions

### SetRepositoryProtocol — New Methods

```swift
/// Aggregate stats using Core Data NSExpression for database-level SUM/MAX/COUNT.
/// Used by StatsService.rebuildAll() — not for hot-path incremental updates.
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

### Existing Methods Used (no changes needed)

- `SetRepositoryProtocol.save()` — set persistence
- `SetRepositoryProtocol.delete()` — set deletion
- `SetRepositoryProtocol.fetch(byId:)` — fetch set for edit/delete capture
- `SetRepositoryProtocol.fetchMaxEffectiveWeight(for:reps:)` — re-query maxWeight on delete
- `ExerciseStatsRepositoryProtocol.save()` — persist updated stats
- `ExerciseStatsRepositoryProtocol.fetch(for:)` — get current stats for incremental update
- `ExerciseStatsRepositoryProtocol.fetchAll()` — used in rebuildAll()
- `ExerciseRepositoryProtocol.fetch(byId:)` — get bodyweightFactor
- `ExerciseRepositoryProtocol.fetchAll()` — enumerate exercises for rebuild
- `BodyweightEntryRepositoryProtocol.fetchClosest(to:healthProfileId:)` — closest bodyweight
- `HealthProfileRepositoryProtocol.fetchOrCreate()` — settings access

## Enums Used

| Enum | Values | Usage |
|------|--------|-------|
| `SetType` | `.warmup`, `.partial`, `.working`, ... | Eligibility filtering for stats (excludePartial always, excludeWarmup configurable) |
| `CachedPRStatus` | `.current`, `.matched`, `.previous` | Read by SetService from PREvaluationResult, not directly written |
| `TrackingType` | `.weightReps`, `.duration`, ... | Determines if volume calculation applies (weight-based only) |
