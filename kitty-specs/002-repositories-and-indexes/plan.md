# Implementation Plan: Repositories + Indexes

**Branch**: `002-repositories-and-indexes` | **Date**: 2026-02-20 | **Spec**: `kitty-specs/002-repositories-and-indexes/spec.md`
**Input**: Feature specification from `kitty-specs/002-repositories-and-indexes/spec.md`

## Summary

Implement protocol-based repository abstractions for all 8 SwiftData entities, configure the two required database indexes, and add aggregation query methods on SetRepository. Repositories are the sole data-access layer — no service or ViewModel may import SwiftData or touch ModelContext. All repository implementations use `@ModelActor` for background-safe, serial-executor-bound SwiftData access. All methods follow `async throws` patterns per FR-003.

**Critical discovery during research:** SwiftData's `#Index` macro requires iOS 18+. This project targets iOS 17. The plan addresses this with a pragmatic strategy (see Research and Technical Context).

## Technical Context

**Language/Version**: Swift (latest stable, Xcode 16+)
**Primary Dependencies**: SwiftData (no third-party deps)
**Target Platform**: iOS 17.0+, iPhone only
**Architecture**: MVVM with Service + Repository layers (this feature builds the Repository layer)
**Threading Model**: `@ModelActor` — each repository actor owns a private `ModelContext` on a serial executor (background thread)
**Testing**: Manual testing for v1. No automated tests.
**Performance Goals**: Set save (including PR pipeline) < 100ms, PR lookup O(1) via PerformanceRecord
**Constraints**: No iPad, no cloud sync, dark mode only

**Prerequisite**: Feature 001 (Xcode Project + SwiftData Models) — all 11 @Model classes and 9 enums must exist in `Reppo/Data/Models/` and `Reppo/Data/Enums/`.

**Key Decisions**:

| Decision | Choice | Source |
|----------|--------|--------|
| Repository threading | `@ModelActor` actors | specdoc S8.5 ("background context"), AGENT_RULES S4.1 ("background context"), research |
| Repository protocols location | `Reppo/Core/Repositories/` | AGENT_RULES S2, spec FR-001 |
| Aggregation strategy | Write-time pre-computation (ExerciseStats) + sort-limit-1 for MAX queries | specdoc S8.6, AGENT_RULES S5.2 |
| Index mechanism | Ship without `#Index` on iOS 17; document for iOS 18 upgrade | Research: `#Index` macro is iOS 18+ only |
| Async pattern | `async throws` on all protocol methods | spec FR-003, AGENT_RULES S13 |
| Cross-actor data | Use `PersistentIdentifier` or value types/DTOs | Research: SwiftData models are not Sendable |
| Actor lifecycle | One instance per ModelContainer, injected via environment | Research: avoids context-switching crashes |
| SwiftData aggregation | No native SUM/AVG/GROUP BY — use sort+fetchLimit for MAX, pre-computed ExerciseStats for totals | Research: SwiftData FetchDescriptor has no aggregation API |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| Architecture layers (Views→VMs→Services→Repos→SwiftData) | PASS | This feature builds the Repository layer. Only repositories import SwiftData and access ModelContext. Services use repository protocols. |
| Only repositories touch ModelContext | PASS | FR-002 + SC-002: No service or ViewModel imports SwiftData or references ModelContext. |
| All weight in kg, distance in meters, duration in seconds | N/A | Repositories pass through stored values. No unit conversion at this layer. |
| WorkoutSet naming (not Set) | PASS | All repository types reference `WorkoutSet`, not `Set`. |
| Database aggregation, not Swift iteration | PASS | MAX queries use sort+fetchLimit(1). Totals read from pre-computed ExerciseStats (write-time updated). No load-and-iterate methods in repository layer. SwiftData SUM limitation documented in constitution. |
| Required database indexes | PARTIAL | `#Index` macro requires iOS 18+. Project targets iOS 17. Indexes cannot be configured via SwiftData API on iOS 17. Documented as known limitation with upgrade path. |
| Hard delete only | PASS | Repository delete methods perform hard delete via `modelContext.delete()`. |
| UUIDs for all IDs | PASS | All repository methods use UUID parameters. |
| No fields/tables not in specdoc | PASS | Repositories map 1:1 to entities defined in specdoc Section 6. |
| Prefer async/await | PASS | All repository methods are `async throws`. |
| No startup rebuild | N/A | Repositories provide data access, not startup logic. |
| Write-time PR/stats updates | N/A | Handled by Services (features 003-004), not repositories. |

**Post-Phase-1 re-check**: Index limitation documented. All other principles pass. No new violations.

**Index Limitation Detail**: The spec requires indexes on `PerformanceRecord(exerciseId, recordType, reps)` and `WorkoutSet(exerciseId, reps, effectiveWeight, date)` per AGENT_RULES S5.4 and specdoc S7.6. The SwiftData `#Index` macro is only available on iOS 18+. On iOS 17, SwiftData provides no API for compound indexes. The practical impact is minimal for v1 because:
1. `PerformanceRecord` is a sparse table (~50 rows per exercise max) — full scans are sub-millisecond
2. MAX queries use sort+fetchLimit(1), which SQLite optimizes well even without explicit indexes
3. The dataset (12,000-50,000 sets) is within SQLite's comfortable range for non-indexed queries with good predicates

**Recommended path**: Ship v1 on iOS 17 without explicit compound indexes. Monitor query performance with Instruments on the imported 12,000-set dataset. When the minimum deployment target is raised to iOS 18, add `#Index` declarations to the @Model classes. Document the `#Index` declarations in `data-model.md` as "iOS 18 upgrade" items.

## Project Structure

### Documentation (this feature)

```
kitty-specs/002-repositories-and-indexes/
├── spec.md
├── meta.json
├── plan.md              # This file
├── research.md          # Phase 0: SwiftData research findings
├── data-model.md        # Phase 1: repository-entity mapping
├── contracts/           # Phase 1: repository protocol definitions
│   ├── SetRepositoryProtocol.swift
│   ├── WorkoutRepositoryProtocol.swift
│   ├── ExerciseRepositoryProtocol.swift
│   ├── ExerciseStatsRepositoryProtocol.swift
│   ├── PerformanceRecordRepositoryProtocol.swift
│   ├── BodyweightEntryRepositoryProtocol.swift
│   ├── HealthProfileRepositoryProtocol.swift
│   └── ProgramRepositoryProtocol.swift
├── tasks/               # Generated by /spec-kitty.tasks
```

### Source Code (repository root)

```
Reppo/Core/Repositories/
├── Protocols/
│   ├── SetRepositoryProtocol.swift
│   ├── WorkoutRepositoryProtocol.swift
│   ├── ExerciseRepositoryProtocol.swift
│   ├── ExerciseStatsRepositoryProtocol.swift
│   ├── PerformanceRecordRepositoryProtocol.swift
│   ├── BodyweightEntryRepositoryProtocol.swift
│   ├── HealthProfileRepositoryProtocol.swift
│   └── ProgramRepositoryProtocol.swift
├── SetRepository.swift
├── WorkoutRepository.swift
├── ExerciseRepository.swift
├── ExerciseStatsRepository.swift
├── PerformanceRecordRepository.swift
├── BodyweightEntryRepository.swift
├── HealthProfileRepository.swift
└── ProgramRepository.swift
```

**Structure Decision**: Protocol files live in `Protocols/` subdirectory to keep the Repositories folder clean. Protocols do NOT import SwiftData — they use Foundation types only (UUID, Date, etc.) and the @Model types from `Data/Models/`. Implementations import SwiftData and use `@ModelActor`.

## Phase 0: Research

Research findings consolidated in `kitty-specs/002-repositories-and-indexes/research.md`.

### Key Findings

| Topic | Decision | Rationale | Alternatives Considered |
|-------|----------|-----------|------------------------|
| Repository threading | `@ModelActor` actor per repository | Apple-recommended; serial executor ensures thread safety; background ModelContext avoids main thread blocking | `@MainActor` repositories (risk blocking UI during PR pipeline), hybrid MainActor+background (unnecessary complexity) |
| SwiftData aggregation | No native SUM/AVG/GROUP BY | SwiftData `FetchDescriptor` only supports predicates and sort descriptors. No `NSExpressionDescription` equivalent. | Drop to Core Data `NSFetchRequest` (fragile, uses private `_nsContext` API), fetch-and-reduce in Swift |
| MAX query pattern | `FetchDescriptor` with sort DESC + `fetchLimit = 1` | Returns 1 row from SQLite, efficient even without compound index | Load all and iterate (anti-pattern per AGENT_RULES S5.2) |
| Compound indexes | Cannot use `#Index` on iOS 17 | `#Index` macro requires iOS 18+. No SwiftData API for indexes on iOS 17. | Raise deployment target to iOS 18 (reduces device coverage), access Core Data internals (fragile private API) |
| Cross-actor model passing | `PersistentIdentifier` or value type DTOs | SwiftData @Model objects are not `Sendable`. Cannot pass between actors. | Re-fetch by UUID (works but less efficient than PersistentIdentifier) |
| Actor lifecycle | Single instance created at app init, shared via DI | Multiple actor instances can cause context-switching crashes | Create per-call (wasteful, risks crashes) |
| Protocol conformance with actors | Protocol methods are `async throws`; actor methods can omit `async` internally | Swift automatically bridges actor-isolated sync methods to async at call site | Mark all implementations async explicitly (unnecessary) |

### Aggregation Strategy by Query Type

| Query | Strategy | Where Used |
|-------|----------|-----------|
| Total volume per exercise | Read from `ExerciseStats.totalVolume` (write-time computed) | Charts, exercise detail |
| Max effective weight per exercise/reps | `FetchDescriptor` sort by effectiveWeight DESC, fetchLimit 1 | PR recomputation (rare) |
| PR lookup by (exerciseId, recordType, reps) | Direct `FetchDescriptor` predicate on `PerformanceRecord` | Every set save |
| Sets for a workout | `FetchDescriptor` predicate on workoutId | Active workout screen |
| Sets for an exercise | `FetchDescriptor` predicate on exerciseId with pagination | Exercise history |
| Closest bodyweight by date | `FetchDescriptor` with date-range predicate, sort by date, fetchLimit 1 | effectiveWeight calculation |

## Phase 1: Design & Contracts

### Repository Protocol Design

Each repository protocol follows this pattern:
- Import `Foundation` only (no SwiftData)
- Reference @Model types from `Data/Models/` (these are available without importing SwiftData at the protocol level since protocols only declare method signatures)
- All methods are `async throws`
- CRUD operations: save, fetch, delete
- Specialized queries as needed per entity
- Return types are the @Model types or primitive values (Double, Int, etc.)

**Note on protocol and SwiftData imports**: The protocol files reference @Model types (e.g., `WorkoutSet`) as parameter/return types. These types are defined with `import SwiftData` in their own files, but the *protocol file* does not need to import SwiftData — it only needs to see the type declaration, which Swift resolves through the module. If the compiler requires it, the protocol file may need `import SwiftData` for the @Model types to be visible, but the protocol itself does not use ModelContext or any SwiftData API.

### 1. SetRepositoryProtocol

```swift
protocol SetRepositoryProtocol: Sendable {
    // CRUD
    func save(_ set: WorkoutSet) async throws
    func delete(_ set: WorkoutSet) async throws
    func fetch(byId id: UUID) async throws -> WorkoutSet?

    // Workout queries
    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet]

    // Exercise queries (FR-004)
    func fetchSets(for exerciseId: UUID, reps: Int, orderedBy: SetSortOrder) async throws -> [WorkoutSet]
    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet]

    // Aggregation (FR-009) — sort+limit pattern for MAX
    func fetchMaxEffectiveWeight(for exerciseId: UUID, reps: Int) async throws -> Double?
}

enum SetSortOrder {
    case effectiveWeightDesc
    case dateAsc
    case dateDesc
}
```

### 2. WorkoutRepositoryProtocol

```swift
protocol WorkoutRepositoryProtocol: Sendable {
    func save(_ workout: Workout) async throws
    func delete(_ workout: Workout) async throws
    func fetch(byId id: UUID) async throws -> Workout?
    func fetchInProgress() async throws -> Workout?
    func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout]
    func fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout]
}
```

### 3. ExerciseRepositoryProtocol

```swift
protocol ExerciseRepositoryProtocol: Sendable {
    func save(_ exercise: Exercise) async throws
    func delete(_ exercise: Exercise) async throws
    func fetch(byId id: UUID) async throws -> Exercise?
    func fetchAll() async throws -> [Exercise]
    func search(name: String) async throws -> [Exercise]
    func hasAssociatedSets(_ exerciseId: UUID) async throws -> Bool
}
```

### 4. ExerciseStatsRepositoryProtocol

```swift
protocol ExerciseStatsRepositoryProtocol: Sendable {
    func save(_ stats: ExerciseStats) async throws
    func delete(_ stats: ExerciseStats) async throws
    func fetch(for exerciseId: UUID) async throws -> ExerciseStats?
    func fetchAll() async throws -> [ExerciseStats]
}
```

### 5. PerformanceRecordRepositoryProtocol

```swift
protocol PerformanceRecordRepositoryProtocol: Sendable {
    func save(_ record: PerformanceRecord) async throws
    func delete(_ record: PerformanceRecord) async throws

    // FR-005: lookup by (exerciseId, recordType, reps)
    func fetch(exerciseId: UUID, recordType: RecordType, reps: Int?) async throws -> PerformanceRecord?

    // FR-005: bulk fetch by exerciseId
    func fetchAll(for exerciseId: UUID) async throws -> [PerformanceRecord]
    func fetchAll(for exerciseId: UUID, recordType: RecordType) async throws -> [PerformanceRecord]
}
```

### 6. BodyweightEntryRepositoryProtocol

```swift
protocol BodyweightEntryRepositoryProtocol: Sendable {
    func save(_ entry: BodyweightEntry) async throws
    func delete(_ entry: BodyweightEntry) async throws
    func fetchAll(for healthProfileId: UUID) async throws -> [BodyweightEntry]

    // FR-008: closest-weight lookup by date
    func fetchClosest(to date: Date, healthProfileId: UUID) async throws -> BodyweightEntry?
}
```

### 7. HealthProfileRepositoryProtocol

```swift
protocol HealthProfileRepositoryProtocol: Sendable {
    func save(_ profile: HealthProfile) async throws
    func fetch() async throws -> HealthProfile?
    func fetchOrCreate() async throws -> HealthProfile
}
```

### 8. ProgramRepositoryProtocol

```swift
protocol ProgramRepositoryProtocol: Sendable {
    func save(_ program: Program) async throws
    func delete(_ program: Program) async throws
    func fetch(byId id: UUID) async throws -> Program?
    func fetchAll() async throws -> [Program]
}
```

### Implementation Pattern

All implementations follow this `@ModelActor` pattern:

```swift
import SwiftData
import Foundation

@ModelActor
actor SetRepository: SetRepositoryProtocol {

    func save(_ set: WorkoutSet) throws {
        modelContext.insert(set)
        try modelContext.save()
    }

    func delete(_ set: WorkoutSet) throws {
        modelContext.delete(set)
        try modelContext.save()
    }

    func fetch(byId id: UUID) throws -> WorkoutSet? {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchMaxEffectiveWeight(for exerciseId: UUID, reps: Int) throws -> Double? {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate {
                $0.exerciseId == exerciseId && $0.reps == reps
            },
            sortBy: [SortDescriptor(\.effectiveWeight, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.effectiveWeight
    }

    // ... remaining methods
}
```

**Note on `async` keyword**: Inside the actor, methods are synchronous (they execute on the actor's serial executor). Swift automatically makes them `async` at the call site because they cross an actor boundary. The protocol declares `async throws`; the implementation can omit `async` if the body is synchronous within the actor.

### Index Configuration (iOS 18 Upgrade Path)

When the deployment target is raised to iOS 18, add to the @Model classes in `Reppo/Data/Models/`:

```swift
// PerformanceRecord.swift — add inside @Model class
#Index<PerformanceRecord>([\.exerciseId, \.recordType, \.reps])

// WorkoutSet.swift — add inside @Model class
#Index<WorkoutSet>(
    [\.exerciseId, \.reps, \.effectiveWeight, \.date],
    [\.workoutId],
    [\.exerciseId]
)
```

### DI Wiring (App Entry Point)

Repositories are instantiated once at app launch and injected via SwiftUI environment:

```swift
// In ReppoApp.swift
@main
struct ReppoApp: App {
    let container: ModelContainer
    let setRepository: SetRepository
    let workoutRepository: WorkoutRepository
    // ... all 8 repositories

    init() {
        let container = try! ModelContainer(for: /* all model types */)
        self.container = container
        self.setRepository = SetRepository(modelContainer: container)
        self.workoutRepository = WorkoutRepository(modelContainer: container)
        // ... initialize all repositories
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        // Inject repositories into environment for Services to use
    }
}
```

## Implementation Approach

### Order of Implementation

1. **Protocols first** — all 8 protocol files in `Core/Repositories/Protocols/` (no SwiftData dependency)
2. **SetRepository** — most complex, has aggregation methods (FR-004, FR-009)
3. **PerformanceRecordRepository** — PR lookup methods (FR-005)
4. **BodyweightEntryRepository** — closest-weight lookup (FR-008)
5. **Remaining repositories** — WorkoutRepository, ExerciseRepository, ExerciseStatsRepository, HealthProfileRepository, ProgramRepository (straightforward CRUD)
6. **DI wiring** — instantiate in ReppoApp.swift, inject into environment
7. **Verify build** — zero errors, all protocols satisfied

### Key Decisions

- **No explicit indexes on iOS 17**: `#Index` is iOS 18+ only. Ship without compound indexes; performance is acceptable for v1 dataset sizes. Document upgrade path.
- **`@ModelActor` for all repositories**: Background-safe, serial execution, Apple-recommended. Satisfies specdoc S8.5 and AGENT_RULES S4.1 requirements for background context.
- **No Core Data escape hatch**: Avoid accessing private `_nsContext` API for aggregation. Use sort+fetchLimit for MAX, pre-computed ExerciseStats for totals.
- **Protocols are `Sendable`**: Enables repositories to be passed across concurrency boundaries (from App init to SwiftUI environment to Services).
- **No `fetchTotalVolume` on SetRepository**: SwiftData has no native SUM. Total volume is read from `ExerciseStats.totalVolume` (pre-computed at write-time by StatsService). If a full rebuild is needed, that logic lives in StatsService, not in the repository layer.

## Complexity Tracking

| Risk | Severity | Mitigation |
|------|----------|------------|
| `#Index` unavailable on iOS 17 | Medium | PerformanceRecord is sparse (~50 rows/exercise); sort+limit queries fast without index. Monitor with Instruments. |
| SwiftData no native aggregation | Low | Pre-computed ExerciseStats handles common case. sort+fetchLimit(1) for MAX. |
| `@ModelActor` lifecycle | Low | Single instance per container, created at app init. Well-documented Apple pattern. |
| Cross-actor model passing | Low | Use PersistentIdentifier or re-fetch by UUID. Document in contracts. |

No constitution violations. Index limitation documented with upgrade path.
