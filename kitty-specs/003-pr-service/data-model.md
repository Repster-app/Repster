# Data Model: PR Service

**Feature**: 003-pr-service
**Date**: 2026-02-22

## Entity Interaction Map

PRService operates on three existing entities and reads settings from a fourth. No new entities or fields are created.

### Entities Touched by PRService

| Entity | Role in PR Pipeline | Access Pattern | Source |
|--------|-------------------|----------------|--------|
| `PerformanceRecord` | **Primary** — the PR table. Created, updated, deleted by PRService. | Read: O(1) lookup by (exerciseId, recordType, reps). Write: create/update/delete. | specdoc S6.5, S7.1 |
| `WorkoutSet` | **Secondary** — source of set data. PRService reads set properties and writes only `cachedPRStatus`. | Read: fetch by ID, fetch eligible sets for recomputation. Write: `cachedPRStatus` only. | specdoc S6.1, AGENT_RULES S6 |
| `HealthProfile` | **Settings** — read-only. PRService reads `includeWarmupsInPRs` to determine warmup eligibility. | Read: fetchOrCreate() for warmup setting. Never written by PRService. | specdoc S6.7 |
| `Exercise` | **Enumeration** — read-only. Used only by `rebuildAll()` to iterate all exercises. | Read: fetchAll(). Never written by PRService. | specdoc S6.2 |

### Entity: PerformanceRecord

```
PerformanceRecord (@Model)
├── id: UUID (PK)
├── exerciseId: UUID (FK → Exercise)
├── recordType: RecordType (.repMax, .e1RM, .maxVolume)
├── reps: Int? (nil for e1RM and maxVolume)
├── value: Double (effectiveWeight in kg for repMax)
├── setId: UUID (FK → WorkoutSet that owns this PR)
├── date: Date (date of the PR-owning set)
├── createdAt: Date
└── updatedAt: Date

Uniqueness: (exerciseId, recordType, reps) — enforced by PRService logic
Index (iOS 18): #Index<PerformanceRecord>([\.exerciseId, \.recordType, \.reps])
```

**PRService operations on PerformanceRecord**:
- `CREATE`: When first set for an exercise/reps is saved (S7.2 step 3)
- `UPDATE`: When new set beats existing PR (S7.2 step 4), or PR owner is edited (S7.2 edit step 2b)
- `DELETE`: When last set for a rep count is deleted (S7.2 delete, no sets remain)
- `READ`: On every set save — O(1) lookup by (exerciseId, .repMax, reps)

### Entity: WorkoutSet (fields relevant to PR pipeline)

```
WorkoutSet (@Model) — PR-relevant fields only
├── id: UUID
├── workoutId: UUID (for same-workout matching, S7.3)
├── exerciseId: UUID
├── date: Date
├── effectiveWeight: Double? (the comparison value, includes bodyweight)
├── reps: Int?
├── setType: SetType (warmup/partial filtering)
├── completed: Bool (NOT used for PR logic — use hasData)
├── excludeFromPRs: Bool? (user-level exclusion flag)
├── cachedPRStatus: CachedPRStatus? (current/matched/previous/nil)
└── hasData: Bool (computed — true if set has actual values)

Index (iOS 18): #Index<WorkoutSet>([\.exerciseId, \.reps, \.effectiveWeight, \.date])
```

**PRService operations on WorkoutSet**:
- `READ`: Fetch by ID (to get PR-owning set's workoutId, S7.3), fetch eligible sets for recomputation (S7.2 edit/delete)
- `WRITE`: Only `cachedPRStatus` field. PRService MUST NOT modify any other WorkoutSet field. (AGENT_RULES S6, FR-009)

### Entity: HealthProfile (fields relevant to PR pipeline)

```
HealthProfile (@Model) — PR-relevant field only
└── includeWarmupsInPRs: Bool (default: false)
```

**PRService operations on HealthProfile**:
- `READ` only. Fetch via `healthProfileRepo.fetchOrCreate()`.

## Data Flow Diagrams

### On New Set Saved

```
WorkoutSet data (via params) ──→ PRService.evaluate()
                                      │
                                      ├── Eligibility check (hasData, excludeFromPRs, setType, warmup setting)
                                      │     └── HealthProfile.includeWarmupsInPRs
                                      │
                                      ├── PerformanceRecord lookup (exerciseId, .repMax, reps)
                                      │
                                      ├── Integer grams comparison: toGrams(effectiveWeight) vs toGrams(PR.value)
                                      │
                                      ├── If new PR: UPDATE PerformanceRecord, old set → "previous"
                                      ├── If match: check workoutId → "matched" or null
                                      └── If below: → null
```

### On PR-Owning Set Deleted

```
Deleted set info (via params) ──→ PRService.handleDeletion()
                                       │
                                       ├── Only acts if cachedPRStatus == "current"
                                       │
                                       ├── SetRepository.fetchBestEligibleSet() ← NEW METHOD
                                       │     (exerciseId, reps, eligibility filters, excludingSetId)
                                       │
                                       ├── If winner found: UPDATE PerformanceRecord → winner
                                       └── If no sets remain: DELETE PerformanceRecord
```

## Enums Used

| Enum | Values | Usage in PR Pipeline |
|------|--------|---------------------|
| `CachedPRStatus` | `.current`, `.matched`, `.previous` | Set on WorkoutSet by PRService |
| `RecordType` | `.repMax`, `.e1RM`, `.maxVolume` | PR type discriminator in PerformanceRecord. PRService currently handles `.repMax` only. |
| `SetType` | `.warmup`, `.partial`, `.working`, ... | Eligibility filtering. Partial always excluded. Warmup configurable. |

## Value Types Introduced by PRService

| Type | Purpose | Fields |
|------|---------|--------|
| `PREvaluationResult` | Return type from evaluate/edit/delete methods | `setId: UUID`, `newStatus: CachedPRStatus?`, `affectedSetIds: [UUID: CachedPRStatus?]`, `prRecordChanged: Bool` |
| `PRTableEntry` | Display-ready PR record after suffix-max filtering | `reps: Int`, `value: Double`, `setId: UUID`, `date: Date` |

Both are `Sendable` structs — safe to pass across actor boundaries.

## Repository Method Addition

### SetRepositoryProtocol — New Method

```swift
/// Fetch the best eligible set for PR candidacy.
/// Used by PRService during recomputation after edit/delete.
/// Returns the single best set after eligibility filtering.
func fetchBestEligibleSet(
    for exerciseId: UUID,
    reps: Int,
    excludeWarmups: Bool,
    excludingSetId: UUID?
) async throws -> WorkoutSet?
```

**Implementation strategy**: Fetch sets matching (exerciseId, reps) predicate, then filter in Swift for hasData/excludeFromPRs/setType/excludingSetId (SwiftData `#Predicate` limitations), sort by effectiveWeight DESC + date ASC, return first.

No other repository changes required. All existing repository methods are sufficient for the PR pipeline.
