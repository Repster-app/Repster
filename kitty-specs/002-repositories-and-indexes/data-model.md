# Data Model: Repositories + Indexes

**Feature**: 002-repositories-and-indexes
**Date**: 2026-02-20

## Entity-Repository Mapping

Each SwiftData @Model entity (defined in feature 001) maps to exactly one repository protocol and one `@ModelActor` implementation.

| Entity (Data/Models/) | Repository Protocol | Implementation | Key Methods Beyond CRUD |
|----------------------|-------------------|----------------|------------------------|
| WorkoutSet | SetRepositoryProtocol | SetRepository | fetchSets(for exerciseId, reps, orderedBy), fetchMaxEffectiveWeight(for:reps:) |
| Workout | WorkoutRepositoryProtocol | WorkoutRepository | fetchInProgress(), fetchWorkouts(for dateRange:) |
| Exercise | ExerciseRepositoryProtocol | ExerciseRepository | search(name:), hasAssociatedSets(_:) |
| ExerciseStats | ExerciseStatsRepositoryProtocol | ExerciseStatsRepository | fetch(for exerciseId:) |
| PerformanceRecord | PerformanceRecordRepositoryProtocol | PerformanceRecordRepository | fetch(exerciseId:recordType:reps:), fetchAll(for exerciseId:) |
| BodyweightEntry | BodyweightEntryRepositoryProtocol | BodyweightEntryRepository | fetchClosest(to date:healthProfileId:) |
| HealthProfile | HealthProfileRepositoryProtocol | HealthProfileRepository | fetchOrCreate() |
| Program | ProgramRepositoryProtocol | ProgramRepository | (CRUD only for v1) |

**Note**: ProgramExercise, PlannedWorkout, and PlannedSet do not have dedicated repositories in v1. They are schema-only (Programs tab is v1.1). If needed, they can be accessed through ProgramRepository or get their own repositories in feature 001.1.

## Repository Layer Rules

### What Repositories DO

- Import SwiftData and access `ModelContext` (the ONLY layer that does this)
- Execute `FetchDescriptor` queries with predicates, sort descriptors, and fetch limits
- Insert, update, and delete @Model objects
- Call `modelContext.save()` after mutations
- Return @Model objects or primitive values (Double, Int, Bool, UUID)

### What Repositories DO NOT

- Contain business logic (that's Services)
- Compute effectiveWeight, PRs, or stats (that's Services)
- Validate data beyond what SwiftData enforces (that's Services)
- Access UI state or call ViewModels
- Import SwiftUI

### Threading Model

```
┌──────────────────────────────────────────────┐
│  @MainActor (UI Thread)                      │
│  Views → ViewModels → Services               │
│           │                                   │
│           │ await repository.method()         │
│           ▼                                   │
│  ┌────────────────────────────────────────┐  │
│  │  @ModelActor (Background Serial Queue) │  │
│  │  Repository Actor                      │  │
│  │  ├── Own ModelContext                   │  │
│  │  ├── DefaultSerialModelExecutor        │  │
│  │  └── All DB operations execute here    │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

- Each `@ModelActor` repository owns a private `ModelContext` created from the shared `ModelContainer`
- All operations within a repository execute serially (no concurrent access to the same context)
- Calls from Services cross the actor boundary and are implicitly `async`
- `ModelContainer` is `Sendable`; `ModelContext` and @Model objects are NOT

## Detailed Repository Specifications

### SetRepository

**Source entity**: WorkoutSet (specdoc S6.1, 28 stored fields + 2 computed)

| Method | Signature | Query Strategy | Spec Reference |
|--------|-----------|---------------|----------------|
| save | `save(_ set: WorkoutSet) throws` | `modelContext.insert()` + `save()` | — |
| delete | `delete(_ set: WorkoutSet) throws` | `modelContext.delete()` + `save()` | — |
| fetch by ID | `fetch(byId: UUID) throws -> WorkoutSet?` | Predicate on `id` | — |
| fetch by workout | `fetchSets(for workoutId: UUID) throws -> [WorkoutSet]` | Predicate on `workoutId`, sort by `orderInWorkout` | FR-004 |
| fetch by exercise | `fetchSets(for exerciseId: UUID, limit: Int?) throws -> [WorkoutSet]` | Predicate on `exerciseId`, sort by `date DESC` | FR-004 |
| fetch by exercise+reps | `fetchSets(for exerciseId: UUID, reps: Int, orderedBy: SetSortOrder) throws -> [WorkoutSet]` | Predicate on `exerciseId` + `reps`, sort by specified order | FR-004 |
| max effective weight | `fetchMaxEffectiveWeight(for exerciseId: UUID, reps: Int) throws -> Double?` | Sort by `effectiveWeight DESC`, `fetchLimit = 1` | FR-009 |

**Aggregation notes**:
- `fetchMaxEffectiveWeight`: Uses sort+fetchLimit(1) — SQLite resolves this efficiently. This is the database-level equivalent of MAX.
- **Total volume**: No `fetchTotalVolume` on SetRepository. SwiftData has no native SUM. Callers read `ExerciseStats.totalVolume` (pre-computed at write-time by StatsService).

### PerformanceRecordRepository

**Source entity**: PerformanceRecord (specdoc S6.5)
**Uniqueness**: `(exerciseId, recordType, reps)` — enforced in PRService, not at DB level (SwiftData iOS 17 has no compound unique constraint)

| Method | Signature | Query Strategy | Spec Reference |
|--------|-----------|---------------|----------------|
| save | `save(_ record: PerformanceRecord) throws` | Insert + save | — |
| delete | `delete(_ record: PerformanceRecord) throws` | Delete + save | — |
| lookup | `fetch(exerciseId: UUID, recordType: RecordType, reps: Int?) throws -> PerformanceRecord?` | Predicate on 3 fields, fetchLimit 1 | FR-005 |
| bulk fetch | `fetchAll(for exerciseId: UUID) throws -> [PerformanceRecord]` | Predicate on exerciseId | FR-005 |
| fetch by type | `fetchAll(for exerciseId: UUID, recordType: RecordType) throws -> [PerformanceRecord]` | Predicate on exerciseId + recordType | FR-005 |

### BodyweightEntryRepository

**Source entity**: BodyweightEntry (specdoc S6.6)

| Method | Signature | Query Strategy | Spec Reference |
|--------|-----------|---------------|----------------|
| save | `save(_ entry: BodyweightEntry) throws` | Insert + save | — |
| delete | `delete(_ entry: BodyweightEntry) throws` | Delete + save | — |
| fetch all | `fetchAll(for healthProfileId: UUID) throws -> [BodyweightEntry]` | Predicate on healthProfileId, sort by date DESC | — |
| closest by date | `fetchClosest(to date: Date, healthProfileId: UUID) throws -> BodyweightEntry?` | Two queries: nearest before + nearest after date, compare absolute distance | FR-008 |

**Closest-weight algorithm**: Find the entry with the smallest absolute time distance from the target date. Implementation: query entries ≤ date (sort DESC, limit 1) and entries ≥ date (sort ASC, limit 1), return whichever is closer.

### WorkoutRepository

**Source entity**: Workout (specdoc S6.2 + AGENT_RULES S7.3 status field)

| Method | Signature | Query Strategy | Spec Reference |
|--------|-----------|---------------|----------------|
| save | `save(_ workout: Workout) throws` | Insert + save | — |
| delete | `delete(_ workout: Workout) throws` | Delete + save | — |
| fetch by ID | `fetch(byId: UUID) throws -> Workout?` | Predicate on id | — |
| fetch in progress | `fetchInProgress() throws -> Workout?` | Predicate `status == .inProgress`, fetchLimit 1 | AGENT_RULES S7.3 |
| fetch by date range | `fetchWorkouts(for dateRange: ClosedRange<Date>) throws -> [Workout]` | Predicate on date range, sort by date DESC | — |
| fetch all | `fetchAllWorkouts(limit: Int?, offset: Int?) throws -> [Workout]` | Sort by date DESC with pagination | — |

### ExerciseRepository

**Source entity**: Exercise (specdoc S6.3)

| Method | Signature | Query Strategy | Spec Reference |
|--------|-----------|---------------|----------------|
| save | `save(_ exercise: Exercise) throws` | Insert + save | — |
| delete | `delete(_ exercise: Exercise) throws` | Delete + save | — |
| fetch by ID | `fetch(byId: UUID) throws -> Exercise?` | Predicate on id | — |
| fetch all | `fetchAll() throws -> [Exercise]` | Sort by name ASC | — |
| search by name | `search(name: String) throws -> [Exercise]` | Predicate with `localizedStandardContains` | — |
| has sets | `hasAssociatedSets(_ exerciseId: UUID) throws -> Bool` | Query WorkoutSet with predicate on exerciseId, fetchLimit 1, check non-empty | AGENT_RULES S3.5 |

### ExerciseStatsRepository

**Source entity**: ExerciseStats (specdoc S6.4)

| Method | Signature | Query Strategy | Spec Reference |
|--------|-----------|---------------|----------------|
| save | `save(_ stats: ExerciseStats) throws` | Insert + save | — |
| delete | `delete(_ stats: ExerciseStats) throws` | Delete + save | — |
| fetch for exercise | `fetch(for exerciseId: UUID) throws -> ExerciseStats?` | Predicate on exerciseId | — |
| fetch all | `fetchAll() throws -> [ExerciseStats]` | No predicate | — |

### HealthProfileRepository

**Source entity**: HealthProfile (specdoc S6.7 + AGENT_RULES S8)
**Cardinality**: Single-row table (one profile per app)

| Method | Signature | Query Strategy | Spec Reference |
|--------|-----------|---------------|----------------|
| save | `save(_ profile: HealthProfile) throws` | Insert + save | — |
| fetch | `fetch() throws -> HealthProfile?` | No predicate, fetchLimit 1 | — |
| fetch or create | `fetchOrCreate() throws -> HealthProfile` | Fetch first; if nil, create with defaults and save | — |

### ProgramRepository

**Source entity**: Program (specdoc S6.8)
**Note**: v1 Programs tab is empty-state placeholder. Basic CRUD only.

| Method | Signature | Query Strategy | Spec Reference |
|--------|-----------|---------------|----------------|
| save | `save(_ program: Program) throws` | Insert + save | — |
| delete | `delete(_ program: Program) throws` | Delete + save | — |
| fetch by ID | `fetch(byId: UUID) throws -> Program?` | Predicate on id | — |
| fetch all | `fetchAll() throws -> [Program]` | Sort by name ASC | — |

## Index Specifications

### Required Indexes (AGENT_RULES S5.4, specdoc S7.6)

| Index | Columns | Purpose | iOS 17 Status |
|-------|---------|---------|---------------|
| `idx_performance_record` | `PerformanceRecord(exerciseId, recordType, reps)` | Fast PR lookup on every set save | NOT CONFIGURABLE — `#Index` requires iOS 18 |
| `idx_set_pr_lookup` | `WorkoutSet(exerciseId, reps, effectiveWeight DESC, date ASC)` | Fast set query for PR recomputation | NOT CONFIGURABLE — `#Index` requires iOS 18 |

### Implicit Indexes (provided by SwiftData/SQLite)

| Index | Source |
|-------|--------|
| Primary key on `id` (all models) | SwiftData auto-creates for `@Attribute(.unique)` or primary key |

### iOS 18 Index Declarations (for future upgrade)

```swift
// PerformanceRecord.swift
@Model final class PerformanceRecord {
    #Index<PerformanceRecord>([\.exerciseId, \.recordType, \.reps])
    // ...
}

// WorkoutSet.swift
@Model final class WorkoutSet {
    #Index<WorkoutSet>(
        [\.exerciseId, \.reps, \.effectiveWeight, \.date],
        [\.workoutId],
        [\.exerciseId]
    )
    // ...
}
```
