# Research: PR Service

**Feature**: 003-pr-service
**Date**: 2026-02-22
**Status**: Complete

## Research Questions

### 1. PRService Threading Model

**Question**: Should PRService be a `@ModelActor` actor with its own ModelContext, or a plain actor that composes repositories?

**Decision**: Plain Swift `actor` composing `@ModelActor` repositories.

**Rationale**:
- AGENT_RULES Section 6 explicitly states services must NOT access ModelContext directly
- The existing repository layer (feature 002) already provides background-safe data access via `@ModelActor` actors
- specdoc S8.5 requires "background queue/context" — satisfied by repositories being `@ModelActor` actors
- A plain actor provides concurrent-access safety without duplicating ModelContext management

**Alternatives Considered**:
- `@ModelActor` PRService: Would give PRService its own ModelContext, but violates AGENT_RULES S6 ("services must not access ModelContext directly"). Also adds a third ModelContext (main + repo + service) which increases complexity.
- Plain class (non-actor): No concurrent-access protection. If SetService and a rebuild operation call PRService simultaneously, state could be corrupted.

### 2. Cross-Actor Data Flow with SwiftData

**Question**: SwiftData `@Model` objects are not `Sendable` and are bound to their creating `ModelContext`. How should PRService receive set data?

**Decision**: PRService methods accept primitive/value-type parameters (UUIDs, Double, Int, Date, enums) and fetch full objects through its injected repositories.

**Rationale**:
- SwiftData @Model objects cannot cross actor boundaries safely
- Passing UUIDs is explicit and lightweight
- PRService's repositories create objects in their own ModelContext, so all mutations happen within the correct context
- The caller (future SetService) already has the set's properties available

**Alternatives Considered**:
- Pass `PersistentIdentifier`: Works but less explicit than UUID. Ties the API to SwiftData internals.
- Create DTOs/value types: Extra mapping layer for no real benefit — the caller already has the raw values.
- Pass the @Model object anyway: Unsafe. Would cause crashes or data corruption when accessed from a different actor's context.

### 3. Eligible-Set Query for PR Recomputation

**Question**: The specdoc S7.2 edit/delete queries require filtering sets by `hasData = true AND excludeFromPRs = false AND eligible setTypes`. Should this be a repository-level query or service-level filtering?

**Decision**: New repository method `fetchBestEligibleSet()` with DB-level filtering.

**Rationale**:
- Constitution principle: "database aggregation, not Swift iteration" (specdoc S8.6)
- The query already filters by exerciseId + reps (reduces to a small set), then adds eligibility filters, then uses sort+limit(1) to return only the winner
- Keeps PRService focused on business logic, not query construction

**SwiftData `#Predicate` limitation**: Complex predicates (checking setType against an exclusion list, optional `excludingSetId`) may not be expressible in a single `#Predicate` closure. Practical approach:
- Use `exerciseId + reps` predicate to reduce to a small set (typically <100 rows)
- Apply `hasData`, `excludeFromPRs`, setType filters in Swift on the small result
- Sort by effectiveWeight DESC, date ASC and take first
- This is acceptable because the pre-filtered set is small after the exerciseId+reps predicate

### 4. PerformanceRecord Mutation Strategy

**Question**: When updating a PR (new owner), should we mutate the existing record or delete+insert?

**Decision**: Mutate existing record in-place.

**Rationale**:
- specdoc S7.2 explicitly says "UPDATE PerformanceRecord SET value = ?, setId = ?, date = ?"
- SwiftData supports property mutation on @Model objects followed by `modelContext.save()`
- Preserves the record's UUID and createdAt timestamp
- Simpler than delete+insert

### 5. Same-Workout Detection

**Question**: How to determine if two sets are in the same workout for the matching rule (specdoc S7.3)?

**Decision**: Compare `workoutId` property on both sets.

**Rationale**:
- Both WorkoutSet objects have a `workoutId: UUID` field
- Direct UUID comparison is O(1) and unambiguous
- The specdoc says "Is set in same workout as PR-owning set?" — workoutId is the natural key

**Implementation**: When evaluating a match, PRService fetches the PR-owning set via `setRepo.fetch(byId: existingPR.setId)` and compares `owningSet.workoutId == newSet.workoutId`.

### 6. Warmup Eligibility Setting

**Question**: How does PRService access the `includeWarmupsInPRs` setting?

**Decision**: Inject `HealthProfileRepositoryProtocol` and read the setting at evaluation time.

**Rationale**:
- `HealthProfile.includeWarmupsInPRs` is stored in SwiftData via `HealthProfileRepository`
- Reading it per-evaluation ensures the latest setting is always used
- The read is O(1) — HealthProfile is a single-row table with `fetchOrCreate()` pattern

**Optimization**: For `rebuildAll()`, read the setting once at the start and pass it through. No need to re-read per set during bulk operations.

### 7. rebuildAll() Strategy

**Question**: How should bulk rebuild work?

**Decision**: Delete all PerformanceRecords → iterate exercises → re-evaluate all eligible sets per exercise.

**Rationale**:
- specdoc FR-011: "available for bulk rebuild after import or settings changes"
- Clean slate approach is simplest and guarantees consistency
- Performance is acceptable for a rare operation (import, settings toggle)
- No incremental complexity needed

**Algorithm**:
1. Fetch `HealthProfile.includeWarmupsInPRs` once
2. Delete all PerformanceRecords (`performanceRecordRepo.fetchAll()` per exercise, delete each)
3. Clear all `cachedPRStatus` on all sets
4. For each exercise:
   a. Get unique rep counts with eligible sets
   b. For each rep count, find best eligible set
   c. Create PerformanceRecord, set `cachedPRStatus = "current"`
   d. For each non-winning eligible set that matches the PR weight, set `cachedPRStatus = "matched"` (respecting same-workout rule)

**Dependency**: Needs `ExerciseRepositoryProtocol` to enumerate all exercises. Added to PRService init.

### 8. Suffix-Max Algorithm Verification

**Question**: Confirm the suffix-max algorithm from specdoc S7.4 is correctly understood.

**Decision**: Algorithm verified against specdoc example. Pure computation, no DB writes.

**Implementation**:
```
Input: [PerformanceRecord] for exercise where recordType == .repMax
Sort: by reps DESCENDING (highest rep count first)
Iterate: track maxWeightSeen, include only entries where value > maxWeightSeen
Output: [PRTableEntry] — the capability frontier
```

The "suffix-max" name comes from scanning from the high-rep end (suffix of the sorted array) and tracking the running maximum. Any entry whose weight is ≤ the max already seen at higher reps is dominated and hidden.

## Summary

All research questions resolved. No unknowns remain. Key architectural decisions:
- Plain actor + repository composition (not @ModelActor)
- UUID/primitive parameter passing (not @Model objects)
- DB-level eligible-set filtering via new repository method
- In-place mutation of PerformanceRecord
- HealthProfile read per evaluation for warmup settings
- Clean-slate rebuildAll() strategy
