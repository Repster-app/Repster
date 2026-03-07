# Research: Repositories + Indexes

**Feature**: 002-repositories-and-indexes
**Date**: 2026-02-20
**Status**: Complete

## Research Topics

### 1. SwiftData Threading Model for Repositories

**Question**: How should repository implementations handle SwiftData's thread safety requirements?

**Decision**: Use `@ModelActor` actor per repository.

**Rationale**:
- `@ModelActor` is Apple's recommended pattern for background SwiftData work (iOS 17+)
- The macro auto-generates a `DefaultSerialModelExecutor` binding the actor to a private `ModelContext`
- All operations execute serially on a background thread, never blocking the main thread
- Satisfies specdoc S8.5 ("PR pipeline runs on background queue/context") and AGENT_RULES S4.1 ("This runs on a background context")
- `ModelContainer` is `Sendable` and safe to pass; `ModelContext` is not

**Alternatives considered**:
- **`@MainActor` repositories**: Simpler, but risks blocking UI during PR pipeline (set save < 100ms target). Rejected.
- **Hybrid `@MainActor` reads + background writes**: Adds complexity with two contexts. Unnecessary given `@ModelActor` handles both. Rejected.

**Implementation details**:
- Create one actor instance per `ModelContainer` at app launch
- Inject via SwiftUI `.environment` or initializer injection
- SwiftData @Model objects are NOT `Sendable` — use `PersistentIdentifier` or value type DTOs when crossing actor boundaries
- Actor methods are synchronous internally; Swift bridges them to `async` at call sites automatically

**Sources**: Apple WWDC24 "What's New in SwiftData", Fat Bob Man "Concurrent Programming in SwiftData", Use Your Loaf "SwiftData Background Tasks"

---

### 2. SwiftData Aggregation Capabilities

**Question**: Does SwiftData support SQL-level aggregation (SUM, MAX, AVG, GROUP BY)?

**Decision**: No. SwiftData's `FetchDescriptor` does not support aggregation. Use alternative strategies.

**Rationale**:
- `FetchDescriptor` supports predicates (`#Predicate`), sort descriptors (`SortDescriptor`), fetch limits, and fetch offsets — but NO aggregation functions
- The `#Expression` macro (iOS 18) supports predicate evaluation only, not aggregation
- There is no SwiftData equivalent to Core Data's `NSExpressionDescription` with `dictionaryResultType`
- Accessing Core Data's `NSManagedObjectContext` via private `_nsContext` property is fragile and broke after WWDC 2024

**Strategy by query type**:

| Query | Strategy | Rationale |
|-------|----------|-----------|
| Total volume per exercise | Read `ExerciseStats.totalVolume` (write-time computed) | specdoc S8.6: "BEST: Pre-computed value" |
| Max effective weight for reps | `FetchDescriptor` sort DESC + `fetchLimit = 1` | Returns 1 row; O(1) with index, fast without |
| Sum for rebuild | Fetch all sets + reduce in Swift | Rare operation (import, repair only) |
| PR lookup | Direct predicate on `PerformanceRecord` | Sparse table, O(1) lookup |
| Count of sets per exercise | Fetch with predicate + `.count` on result array | Acceptable for bounded result sets |

**Key implication for spec FR-009** ("Repository methods MUST use database-level aggregation for totals/maximums, never load-and-iterate"):
- **MAX**: Achievable via sort+fetchLimit(1) — SQLite evaluates this at the database level with or without an index
- **SUM/Totals**: Not achievable purely at database level in SwiftData. The spec's intent is satisfied by using pre-computed `ExerciseStats` (which IS computed at write-time per specdoc S8.6). No `fetchTotalVolume` on SetRepository — callers read `ExerciseStats.totalVolume`. If a rebuild is needed, that logic lives in StatsService.

**Sources**: Fat Bob Man "Key Considerations Before Using SwiftData", Use Your Loaf "SwiftData Expressions", bigmountainstudio SwiftData aggregation gist

---

### 3. Compound Indexes in SwiftData

**Question**: Can compound indexes be configured for iOS 17 targets?

**Decision**: No. The `#Index` macro requires iOS 18+. Ship v1 without explicit compound indexes.

**Rationale**:
- The `#Index<Model>([\.field1, \.field2])` macro was introduced at WWDC 2024 and requires iOS 18 minimum deployment target
- There is no SwiftData API for configuring indexes on iOS 17
- `@Attribute(.unique)` exists but only for single-field uniqueness, not compound indexes
- Accessing the underlying Core Data `NSEntityDescription` to add indexes programmatically is private API and fragile

**Impact analysis**:

| Index | Spec Reference | Impact Without Index |
|-------|---------------|---------------------|
| `PerformanceRecord(exerciseId, recordType, reps)` | AGENT_RULES S5.4, specdoc S7.6 | Minimal. PerformanceRecord is sparse (~50 rows per exercise, ~15,000 total at 50k sets). Predicate queries are sub-millisecond even with full scan. |
| `WorkoutSet(exerciseId, reps, effectiveWeight, date)` | AGENT_RULES S5.4, specdoc S7.6 | Low-medium. Used only for PR recomputation (set edit/delete of PR owner — rare). Sort+fetchLimit(1) on 50,000 rows without index: ~5-10ms on modern iPhone. Within 100ms target. |

**Upgrade path**:
1. Ship v1 on iOS 17 without explicit indexes
2. Profile with Instruments on 12,000-set imported dataset
3. When raising minimum deployment target to iOS 18, add `#Index` declarations (lightweight migration handles this automatically)
4. Document exact `#Index` syntax in `data-model.md` for future reference

**`#Index` syntax for future use (iOS 18+)**:
```swift
@Model
final class PerformanceRecord {
    #Index<PerformanceRecord>([\.exerciseId, \.recordType, \.reps])
    // ... fields
}

@Model
final class WorkoutSet {
    #Index<WorkoutSet>(
        [\.exerciseId, \.reps, \.effectiveWeight, \.date],
        [\.workoutId],
        [\.exerciseId]
    )
    // ... fields
}
```

**Sources**: Apple Developer Documentation "#Index macro", Use Your Loaf "SwiftData Indexes", Yaacoub "SwiftData's new Index and Unique macros"

---

### 4. Repository Protocol Design with @ModelActor

**Question**: How should protocol conformance work with `@ModelActor` actors?

**Decision**: Protocols declare `async throws` methods. Actor implementations can omit `async` on method bodies.

**Rationale**:
- An `actor` type implicitly makes all its methods `async` when called from outside the actor's isolation domain
- Protocols must declare methods as `async throws` since callers (Services) will always cross the actor boundary
- Inside the actor, methods execute synchronously on the serial executor — no need for internal `async` keyword
- Protocols should conform to `Sendable` so repository references can be passed across concurrency domains

**Pattern**:
```swift
// Protocol (no SwiftData import)
protocol SetRepositoryProtocol: Sendable {
    func save(_ set: WorkoutSet) async throws
}

// Implementation
@ModelActor
actor SetRepository: SetRepositoryProtocol {
    func save(_ set: WorkoutSet) throws {  // Note: no 'async' needed internally
        modelContext.insert(set)
        try modelContext.save()
    }
}
```

**Sources**: Massicotte "ModelActor is Just Weird", BrightDigit "Using ModelActor in SwiftData"

---

### 5. Cross-Actor Data Passing

**Question**: How to pass SwiftData model objects between actors (e.g., from repository to service)?

**Decision**: Use `PersistentIdentifier` for cross-context lookups, or return model objects directly when staying within the same actor context.

**Rationale**:
- SwiftData @Model objects are not `Sendable` — they're bound to their `ModelContext`
- `PersistentIdentifier` IS `Sendable` and can identify an object across contexts
- Within a single `@ModelActor`, all operations share the same `ModelContext`, so returning model objects from repository methods is safe
- When Services need to pass objects between repositories (rare), they should pass UUIDs or `PersistentIdentifier`

**For this feature**: Since each repository is a separate `@ModelActor` with its own context, Services that orchestrate across repositories should:
1. Fetch from one repository (gets object in that context)
2. Extract needed values (UUIDs, primitive fields)
3. Use those values to query/update in another repository

**Alternative considered**: Single "DataHandler" actor that contains all repository logic. Rejected because it would create a god-object and prevent independent repository testing/replacement.

---

## Summary of All Research Decisions

| # | Topic | Decision | Risk Level |
|---|-------|----------|-----------|
| 1 | Threading | `@ModelActor` per repository | Low |
| 2 | Aggregation | Pre-computed stats + sort+fetchLimit for MAX | Low |
| 3 | Compound indexes | Ship without on iOS 17; add with `#Index` on iOS 18 | Medium (monitor performance) |
| 4 | Protocol design | `async throws` protocols, `Sendable` conformance | Low |
| 5 | Cross-actor data | `PersistentIdentifier` or extract primitive values | Low |
