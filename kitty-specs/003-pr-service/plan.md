# Implementation Plan: PR Service

**Branch**: `003-pr-service` | **Date**: 2026-02-22 | **Spec**: `kitty-specs/003-pr-service/spec.md`
**Input**: Feature specification from `kitty-specs/003-pr-service/spec.md`

## Summary

Implement `PRService` — the business-logic actor that owns all Personal Record evaluation, update, and recomputation. PRService is a plain Swift actor (not `@ModelActor`) that composes existing repository actors via initializer injection. It implements the complete PR pipeline from specdoc Section 7.2: evaluate on save, recompute on edit/delete, eligibility filtering, integer grams comparison, same-workout matching, suffix-max display filtering, and bulk rebuild.

PRService is the first service in the project. It establishes the service-layer pattern: services contain business logic, call repositories for data access, and never touch `ModelContext` directly.

**Prerequisite**: Feature 002 (Repositories + Indexes) — all 8 repository actors and protocols must exist in `Reppo/Core/Repositories/`.

## Technical Context

**Language/Version**: Swift (latest stable, Xcode 16+)
**Primary Dependencies**: SwiftData (via repositories only), Foundation
**Target Platform**: iOS 17.0+, iPhone only
**Architecture**: MVVM with Service + Repository layers (this feature builds the first Service)
**Threading Model**: PRService is a plain `actor`. Repositories are `@ModelActor` actors that provide background-safe data access. All repository calls are `async throws`.
**Testing**: Manual testing for v1. No automated tests.
**Performance Goals**: PR evaluation must complete within the 100ms set-save budget (SC-001).
**Constraints**: No iPad, no cloud sync, dark mode only.

**Key Decisions**:

| Decision | Choice | Source |
|----------|--------|--------|
| PRService type | Plain Swift `actor` (not `@ModelActor`) | Services must not access ModelContext (AGENT_RULES S6). Repositories handle all data access. |
| Dependency injection | Initializer injection of repository protocols | Matches existing `RepositoryContainer` DI pattern from feature 002. |
| Background execution | Inherited from repositories | Repositories are `@ModelActor` actors on background executors. PRService awaits them. Satisfies specdoc S8.5. |
| Weight comparison | `UnitConversion.toGrams()` — integer grams | specdoc S8.3, AGENT_RULES S3.4. Already implemented in `Reppo/Core/Extensions/UnitConversion.swift`. |
| PR ownership | Earliest occurrence wins for ties | specdoc S4.2, spec FR-004. |
| Same-workout matching | Store `cachedPRStatus = "matched"` in DB; UI hides badge if same workout | specdoc S7.3, spec FR-005. PRService stores "matched" — UI-layer logic to hide is separate. |
| Set eligibility | PRService checks `hasData`, `excludeFromPRs`, `setType`, warmup setting | specdoc S7.2 step 1, spec FR-003. |
| Suffix-max filtering | Pure computation on fetched PerformanceRecord arrays | specdoc S7.4, spec FR-008. No DB write — display-only filtering. |
| Partial sets | Always excluded from PRs regardless of settings | specdoc S7.2, spec FR-003. |
| PerformanceRecord update | Mutate existing record fields (value, setId, date) rather than delete+insert | specdoc S7.2 step 4: "UPDATE PerformanceRecord SET value = ?, setId = ?, date = ?" |

**Identified Gap — Repository Method**: The specdoc Section 7.2 edit/delete queries require filtering by `hasData = true AND excludeFromPRs = false` and excluding warmup/partial set types. The existing `SetRepository.fetchSets(for:reps:orderedBy:)` does not filter by eligibility. Two options:

1. **Add a specialized repository method** `fetchBestEligibleSet(for:reps:excludeWarmups:excludingSetId:)` that includes the eligibility predicate.
2. **Filter in PRService** — fetch all sets for exercise+reps from the repository, then filter in Swift.

**Decision**: Option 1 — add a specialized repository method. This follows the constitution principle of "database aggregation, not Swift iteration" (specdoc S8.6). The query filters at the database level and uses `sort DESC + fetchLimit(1)` to return only the winner. This is a small addition to `SetRepositoryProtocol` and `SetRepository`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| Architecture layers (Views→VMs→Services→Repos→SwiftData) | PASS | PRService is a Service. It calls Repositories only. No ModelContext access. |
| Only repositories touch ModelContext | PASS | PRService uses `PerformanceRecordRepository`, `SetRepository`, `HealthProfileRepository` — never imports SwiftData. |
| All weight in kg, distance in meters, duration in seconds | PASS | PRService stores/compares in kg. Uses `toGrams()` for integer comparison only. |
| WorkoutSet naming (not Set) | PASS | All code references `WorkoutSet`. |
| Integer grams for float comparison | PASS | All PR comparisons use `UnitConversion.toGrams()`. Never raw float `==` or `>`. (specdoc S8.3, FR-002) |
| Database aggregation, not Swift iteration | PASS | PR lookup via PerformanceRecord (O(1)). Recomputation uses indexed sort+limit query. New eligible-set query filters at DB level. |
| Write-time PR updates | PASS | `PRService.evaluate(set)` runs at write-time after set save. No startup rebuild. (specdoc S8.4, FR-001) |
| No startup rebuild | PASS | `rebuildAll()` is manual-only, triggered from Settings or after import. (FR-011) |
| Hard delete only | PASS | When PerformanceRecord has no remaining sets, the record is deleted. No soft delete. |
| Single PerformanceRecord table | PASS | All PR types (repMax, e1RM, maxVolume) in one table. Uniqueness: (exerciseId, recordType, reps). |
| PR ownership: earliest wins | PASS | Matches never update PerformanceRecord. Sort by effectiveWeight DESC, date ASC ensures earliest wins. |
| Do NOT invent fields/tables/enums | PASS | PRService uses only existing models, enums, and repository methods (plus one new eligible-set query). |
| PRService only modifies cachedPRStatus | PASS | Per AGENT_RULES S6: PRService does NOT modify sets beyond cachedPRStatus. (FR-009) |
| Prefer async/await | PASS | All service methods are `async throws`. |
| No third-party deps | PASS | Pure Swift + Foundation. |

**Post-Phase-1 re-check**: All principles pass. New eligible-set repository method follows existing patterns. No constitution violations.

## Project Structure

### Documentation (this feature)

```
kitty-specs/003-pr-service/
├── spec.md
├── meta.json
├── plan.md              # This file
├── research.md          # Phase 0: Research findings
├── data-model.md        # Phase 1: Entity interaction mapping
├── contracts/           # Phase 1: Service protocol definition
│   └── PRServiceProtocol.swift
├── tasks/               # Generated by /spec-kitty.tasks
```

### Source Code (repository root)

```
Reppo/Core/Services/
├── Protocols/
│   └── PRServiceProtocol.swift
├── PRService.swift

Reppo/Core/Repositories/
├── Protocols/
│   └── SetRepositoryProtocol.swift  (updated — add fetchBestEligibleSet)
├── SetRepository.swift              (updated — implement fetchBestEligibleSet)
```

## Phase 0: Research

Research findings consolidated in `kitty-specs/003-pr-service/research.md`.

### Key Findings

| Topic | Decision | Rationale | Alternatives Considered |
|-------|----------|-----------|------------------------|
| PRService threading model | Plain Swift `actor` composing `@ModelActor` repositories | Services must not access ModelContext (AGENT_RULES S6). Repos already run on background executors, satisfying S8.5. | `@ModelActor` PRService with own context (violates service-layer rule), plain class (no actor isolation for concurrent callers) |
| Eligible-set query | New `fetchBestEligibleSet()` on SetRepository with DB-level filtering | specdoc S8.6: "database aggregation, not Swift iteration". The query includes `hasData`, `excludeFromPRs`, setType filters + sort DESC + fetchLimit(1). | Filter in PRService after fetching all sets (violates aggregation principle, loads unnecessary data) |
| PerformanceRecord mutation | Update existing record in-place (mutate fields) | specdoc S7.2 says "UPDATE PerformanceRecord SET ...". SwiftData supports mutating @Model properties then calling `modelContext.save()`. | Delete + re-insert (unnecessary, creates new UUID) |
| Same-workout detection | Compare `workoutId` on new set vs PR-owning set | specdoc S7.3: "Is set in same workout as PR-owning set?" Both WorkoutSet objects have `workoutId`. | Compare dates or workout references (less direct) |
| Warmup eligibility | Read `HealthProfile.includeWarmupsInPRs` setting | specdoc S7.2 step 1: warmup exclusion is configurable. Partial sets always excluded regardless. | Hardcode warmup exclusion (wrong — setting exists) |
| `rebuildAll()` strategy | Delete all PerformanceRecords, iterate exercises, re-evaluate all eligible sets | FR-011: needed for import and settings changes. Rare operation — does not need to be fast. | Incremental rebuild (complex, error-prone for a rare operation) |
| Suffix-max implementation | Pure function on `[PerformanceRecord]` array | specdoc S7.4: algorithm is stateless iteration over sorted records. No DB writes — display-only. | Store filtered flag on PerformanceRecord (adds field not in specdoc — violates "do not invent") |
| SwiftData cross-actor model access | PRService receives UUIDs/value types from callers, fetches full models via repositories | SwiftData @Model objects are not Sendable. PRService cannot receive WorkoutSet directly from a different ModelContext. | Pass PersistentIdentifier (works but less explicit than UUID) |

### Critical Implementation Detail: Cross-Actor Data Flow

SwiftData `@Model` objects are bound to the `ModelContext` that created them. They are **not Sendable** and cannot be passed between actors. PRService must work around this:

**Pattern**: PRService methods accept identifying data (UUIDs, weight values, rep counts) rather than full `@Model` objects. Internally, PRService fetches the needed objects through its injected repositories (which create them in their own ModelContext).

```
Caller (SetService/ViewModel)              PRService                    Repositories
         |                                     |                            |
         |-- evaluate(setId, exerciseId,  ---->|                            |
         |   reps, effectiveWeight, ...)       |                            |
         |                                     |-- fetch PR record -------->|
         |                                     |<-- PerformanceRecord? -----|
         |                                     |                            |
         |                                     |-- fetch old PR set ------->|
         |                                     |<-- WorkoutSet? ------------|
         |                                     |                            |
         |                                     |-- update/save ------------>|
         |<-- EvaluationResult --------------- |                            |
```

**EvaluationResult**: PRService returns a lightweight value type containing the outcome (new cachedPRStatus, whether PR was updated, etc.) so the caller can update UI optimistically.

### Repository Gap Resolution

The specdoc Section 7.2 queries for PR recomputation require:

```sql
SELECT id, effectiveWeight FROM Set
WHERE exerciseId = ? AND reps = ?
  AND hasData = true AND excludeFromPRs = false
  -- AND setType NOT IN ('warmup', 'partial') when settings exclude them
ORDER BY effectiveWeight DESC, date ASC
LIMIT 1
```

**New method on `SetRepositoryProtocol`**:

```swift
/// Fetch the best eligible set for PR candidacy.
/// Filters: hasData = true, excludeFromPRs = false, eligible setTypes.
/// Sorted by effectiveWeight DESC, date ASC (earliest-highest wins).
/// Optional excludingSetId to skip the deleted/edited set.
func fetchBestEligibleSet(
    for exerciseId: UUID,
    reps: Int,
    excludeWarmups: Bool,
    excludingSetId: UUID?
) async throws -> WorkoutSet?
```

**SwiftData predicate note**: `#Predicate` closures in SwiftData have limited expressiveness (no array `.contains`, no complex conditionals). The `excludeWarmups` flag and `excludingSetId` filter may need to be applied as a post-fetch filter on a small result set, or handled via multiple predicate variants. The implementation will determine the most practical approach within SwiftData's `#Predicate` limitations.

## Phase 1: Design & Contracts

### PRServiceProtocol

```swift
import Foundation

/// Result of evaluating a set for PR status.
/// Returned to callers so they can update UI optimistically.
struct PREvaluationResult: Sendable {
    let setId: UUID
    let newStatus: CachedPRStatus?
    /// Set IDs whose cachedPRStatus changed (e.g., old PR owner → "previous")
    let affectedSetIds: [UUID: CachedPRStatus?]
    /// Whether the PerformanceRecord was created or updated
    let prRecordChanged: Bool
}

/// Filtered PR records for display, with dominated entries removed.
struct PRTableEntry: Sendable {
    let reps: Int
    let value: Double
    let setId: UUID
    let date: Date
}

protocol PRServiceProtocol: Sendable {

    // MARK: - Core Pipeline (FR-001, specdoc S7.2)

    /// Evaluate a newly saved set for PR status.
    /// Called at write-time after every set save.
    /// Returns the evaluation result for UI updates.
    func evaluate(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        effectiveWeight: Double,
        workoutId: UUID,
        setType: SetType,
        hasData: Bool,
        excludeFromPRs: Bool,
        date: Date
    ) async throws -> PREvaluationResult

    /// Re-evaluate PR after a set is edited.
    /// Handles both cases: edited set was/wasn't the PR owner.
    func evaluateAfterEdit(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        effectiveWeight: Double,
        workoutId: UUID,
        setType: SetType,
        hasData: Bool,
        excludeFromPRs: Bool,
        previousCachedPRStatus: CachedPRStatus?,
        date: Date
    ) async throws -> PREvaluationResult

    /// Handle PR recomputation after a set is deleted.
    /// Only does work if the deleted set was the PR owner.
    func handleDeletion(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        cachedPRStatus: CachedPRStatus?
    ) async throws -> PREvaluationResult

    // MARK: - Display (FR-008, specdoc S7.4)

    /// Fetch the suffix-max filtered PR table for an exercise.
    /// Returns only the capability frontier entries.
    func fetchPRTable(for exerciseId: UUID) async throws -> [PRTableEntry]

    // MARK: - Bulk Operations (FR-011)

    /// Rebuild all PRs from scratch.
    /// Used after import or settings changes (includeWarmupsInPRs toggled).
    func rebuildAll() async throws

    /// Rebuild PRs for a single exercise.
    func rebuild(for exerciseId: UUID) async throws
}
```

### PRService Implementation Design

See **Updated PRService Init** below (4 dependencies including exerciseRepo for rebuildAll).

### Method-by-Method Pipeline Mapping

#### `evaluate()` — On New Set Saved (specdoc S7.2)

```
Step 1: ELIGIBILITY CHECK
  - hasData == false → return status=nil
  - excludeFromPRs == true → return status=nil
  - setType == .partial → return status=nil (always excluded)
  - setType == .warmup → check HealthProfile.includeWarmupsInPRs
    - if false → return status=nil

Step 2: LOOKUP CURRENT PR
  - performanceRecordRepo.fetch(exerciseId, .repMax, reps)

Step 3: NO EXISTING PR
  - Create new PerformanceRecord(exerciseId, .repMax, reps, effectiveWeight, setId, date)
  - performanceRecordRepo.save(record)
  - return status="current", prRecordChanged=true

Step 4: NEW SET BEATS PR (toGrams(effectiveWeight) > toGrams(existingPR.value))
  - Fetch old PR-owning set: setRepo.fetch(byId: existingPR.setId)
  - Update old set: cachedPRStatus = "previous" → setRepo.save(oldSet)
  - Update PR record: value=effectiveWeight, setId=newSetId, date=newDate
  - performanceRecordRepo.save(existingPR)
  - return status="current", affectedSets={oldSetId: "previous"}, prRecordChanged=true

Step 5: EXACT MATCH (toGrams(effectiveWeight) == toGrams(existingPR.value))
  - Always return status="matched" (specdoc S7.3: store "matched" in DB)
  - UI layer hides the badge if set is in same workout as PR owner (not PRService's concern)
  - Do NOT update PerformanceRecord (earliest wins)

Step 6: BELOW PR (toGrams(effectiveWeight) < toGrams(existingPR.value))
  - return status=nil
```

#### `evaluateAfterEdit()` — On Set Edited (specdoc S7.2)

```
If previousCachedPRStatus != "current":
  → Run evaluate() logic with new values (re-evaluate from scratch)

If previousCachedPRStatus == "current":
  a. Fetch PerformanceRecord for this exercise/reps
  b. If toGrams(newEffectiveWeight) >= toGrams(PR.value):
     → Update PR record with new value
     → return status="current"
  c. If toGrams(newEffectiveWeight) < toGrams(PR.value):
     → Find new best: setRepo.fetchBestEligibleSet(exerciseId, reps, excludeWarmups, excludingSetId: nil)
     → If winner != this set:
       - Update PR to point to winner
       - winner.cachedPRStatus = "current"
       - Re-evaluate this set against new PR
     → If this set still wins (or no other sets):
       - Update PR with new lower value
       - Keep status="current"
```

#### `handleDeletion()` — On Set Deleted (specdoc S7.2)

```
If cachedPRStatus != "current":
  → return empty result (no PR changes needed)

If cachedPRStatus == "current":
  → fetchBestEligibleSet(exerciseId, reps, excludeWarmups, excludingSetId: deletedSetId)
  → If new winner found:
    - Update PR to point to winner
    - winner.cachedPRStatus = "current"
    - return affectedSets={winnerId: "current"}, prRecordChanged=true
  → If no sets remain:
    - Delete the PerformanceRecord
    - return prRecordChanged=true (record deleted)
```

#### `fetchPRTable()` — Suffix-Max Filtering (specdoc S7.4)

```
1. performanceRecordRepo.fetchAll(for: exerciseId, recordType: .repMax)
2. Sort by reps DESC
3. Iterate with maxWeightSeen tracking
4. Return only entries where value > maxWeightSeen
```

#### `rebuildAll()` — Bulk Rebuild (FR-011)

```
1. Fetch HealthProfile for warmup setting
2. Fetch all exercises (exerciseRepo.fetchAll())
3. For each exercise: rebuild(for: exerciseId)
```

#### `rebuild(for:)` — Single Exercise Rebuild

```
1. Delete all PerformanceRecords for this exercise
2. Fetch all eligible sets grouped by reps
3. For each rep count, find the best eligible set
4. Create PerformanceRecord for the winner
5. Update cachedPRStatus on all affected sets
```

**Note on rebuildAll() dependency**: `rebuildAll()` needs `ExerciseRepository` to fetch all exercises. This is an additional dependency. PRService will accept `ExerciseRepositoryProtocol` in its initializer for this purpose.

### Updated PRService Init

```swift
actor PRService: PRServiceProtocol {
    private let performanceRecordRepo: PerformanceRecordRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol  // for rebuildAll()

    init(
        performanceRecordRepository: PerformanceRecordRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol
    ) { ... }
}
```

## Implementation Approach

### Order of Implementation

1. **PRServiceProtocol + value types** — protocol, `PREvaluationResult`, `PRTableEntry` in `Reppo/Core/Services/Protocols/`
2. **SetRepository update** — add `fetchBestEligibleSet()` to protocol and implementation
3. **PRService core** — `evaluate()`, `evaluateAfterEdit()`, `handleDeletion()` following specdoc S7.2 exactly
4. **PRService display** — `fetchPRTable()` with suffix-max algorithm from specdoc S7.4
5. **PRService rebuild** — `rebuildAll()` and `rebuild(for:)` per FR-011
6. **DI wiring** — add PRService to app setup (ServiceContainer or similar)
7. **Verify build** — zero errors, all protocols satisfied

### Scope Boundary

**In scope**: PRService implementation, PRServiceProtocol, PREvaluationResult, PRTableEntry, SetRepository eligible-set query addition, DI wiring for PRService.

**Out of scope**: SetService (feature 004), StatsService (feature 004), ViewModels, Views, UI badges, PR celebration animations. SetService will call `PRService.evaluate()` — that orchestration is feature 004's responsibility.

## Complexity Tracking

| Risk | Severity | Mitigation |
|------|----------|------------|
| SwiftData `#Predicate` limitations for eligible-set query | Medium | May need post-fetch filtering for complex conditions (setType exclusion). Impact is minimal — query returns few rows after exerciseId+reps predicate. |
| Cross-actor model passing (SwiftData models not Sendable) | Medium | PRService accepts UUIDs/primitives, fetches models internally via repositories. All data stays within each actor's ModelContext. |
| Performance: evaluate() must complete within 100ms budget | Low | PerformanceRecord lookup is O(1). Set fetch by ID is O(1). Only recomputation (rare) queries the Set table. |
| rebuildAll() performance for large datasets | Low | Rare operation (import/settings change only). Acceptable to take seconds. No UI responsiveness requirement. |
| PerformanceRecord mutation vs insert | Low | SwiftData supports in-place mutation of @Model properties. Standard pattern used by repositories. |

No constitution violations. All decisions traceable to specdoc Section 7 and AGENT_RULES.
