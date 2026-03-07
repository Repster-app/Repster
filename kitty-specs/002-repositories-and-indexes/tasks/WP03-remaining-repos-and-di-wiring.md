---
work_package_id: "WP03"
subtasks:
  - "T013"
  - "T014"
  - "T015"
  - "T016"
  - "T017"
  - "T018"
  - "T019"
title: "Remaining Repositories + DI Wiring"
phase: "Phase 1 - User Story 1 (Repository Protocols) + User Story 2 (Indexes)"
lane: "done"
assignee: "claude"
agent: "claude"
shell_pid: "95869"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01", "WP02"]
history:
  - timestamp: "2026-02-20T12:32:56Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – Remaining Repositories + DI Wiring

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Implementation Command

```bash
spec-kitty implement WP03 --base WP02
```

Depends on WP01 (protocols) and WP02 (core implementations for DI wiring completeness).

---

## Objectives & Success Criteria

- Implement 5 remaining `@ModelActor` repository actors: WorkoutRepository, ExerciseRepository, ExerciseStatsRepository, HealthProfileRepository, ProgramRepository
- Wire all 8 repositories into the app via dependency injection in ReppoApp.swift
- Add iOS 18 `#Index` upgrade documentation as code comments in model files
- All actors conform to their protocols
- Project builds with zero errors
- Complete repository layer: all 8 repositories implemented and available via DI

**Success Criteria (from spec)**:
- SC-001: Every SwiftData model has a corresponding repository protocol AND implementation
- SC-002: No service or ViewModel imports SwiftData or references ModelContext (verified by architecture review)
- SC-003: Index documentation present (actual `#Index` requires iOS 18 — documented with upgrade path)
- SC-005: All repository methods compile and follow async/await patterns

---

## Context & Constraints

**Pattern**: Same `@ModelActor` pattern as WP02. All repositories import SwiftData, use `modelContext`, implement CRUD + specialized queries.

**DI approach**: Manual/simple DI via SwiftUI environment (constitution: "No DI frameworks"). Create all repositories once in `ReppoApp.init()` from the shared `ModelContainer`, then inject into the view hierarchy.

**SwiftUI environment for actors**: `@ModelActor` actors are reference types. They can be injected via:
1. Custom `EnvironmentKey` — define a key for each protocol type
2. Direct property on a container object passed via `.environment`
3. Simple initializer injection from App to root view

Use the simplest approach that compiles. If custom `EnvironmentKey` is too verbose, create a lightweight `RepositoryContainer` class that holds all 8 repositories and inject that.

**Reference documents**:
- `kitty-specs/002-repositories-and-indexes/plan.md` — DI wiring example and implementation order
- `kitty-specs/002-repositories-and-indexes/data-model.md` — Method specs for each repository
- `kitty-specs/002-repositories-and-indexes/research.md` — iOS 18 `#Index` syntax

---

## Subtasks & Detailed Guidance

### Subtask T013 – Create WorkoutRepository

**Purpose**: Implement CRUD + specialized queries for Workout entity. The `fetchInProgress()` method is critical — it's called at app launch to resume an active workout (AGENT_RULES S7.3).

**Steps**:

1. Create file `Reppo/Core/Repositories/WorkoutRepository.swift`
2. Define `@ModelActor actor WorkoutRepository: WorkoutRepositoryProtocol`
3. Implement all methods:

```swift
import SwiftData
import Foundation

@ModelActor
actor WorkoutRepository: WorkoutRepositoryProtocol {

    func save(_ workout: Workout) throws {
        modelContext.insert(workout)
        try modelContext.save()
    }

    func delete(_ workout: Workout) throws {
        modelContext.delete(workout)
        try modelContext.save()
    }

    func fetch(byId id: UUID) throws -> Workout? {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchInProgress() throws -> Workout? {
        let inProgress = WorkoutStatus.inProgress
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.status == inProgress }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchWorkouts(for dateRange: ClosedRange<Date>) throws -> [Workout] {
        let start = dateRange.lowerBound
        let end = dateRange.upperBound
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate {
                $0.date >= start && $0.date <= end
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAllWorkouts(limit: Int? = nil, offset: Int? = nil) throws -> [Workout] {
        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        if let offset { descriptor.fetchOffset = offset }
        return try modelContext.fetch(descriptor)
    }
}
```

**Files**: `Reppo/Core/Repositories/WorkoutRepository.swift` (new, ~55 lines)
**Parallel?**: Yes

**Notes on `fetchInProgress`**:
- `#Predicate` with enum comparison: capture the enum value in a local variable before the predicate closure. `#Predicate` closures have limitations on what they can capture — test this pattern.
- Should return at most 1 workout. If multiple `inProgress` workouts exist (data corruption), fetchLimit 1 returns the first found.

---

### Subtask T014 – Create ExerciseRepository

**Purpose**: Implement CRUD + name search + `hasAssociatedSets` check. The `hasAssociatedSets` method is a cross-entity query (queries WorkoutSet table) needed to enforce trackingType immutability (AGENT_RULES S3.5).

**Steps**:

1. Create file `Reppo/Core/Repositories/ExerciseRepository.swift`
2. Define `@ModelActor actor ExerciseRepository: ExerciseRepositoryProtocol`
3. Implement all methods:

```swift
@ModelActor
actor ExerciseRepository: ExerciseRepositoryProtocol {

    func save(_ exercise: Exercise) throws {
        modelContext.insert(exercise)
        try modelContext.save()
    }

    func delete(_ exercise: Exercise) throws {
        modelContext.delete(exercise)
        try modelContext.save()
    }

    func fetch(byId id: UUID) throws -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchAll() throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func search(name: String) throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate {
                $0.name.localizedStandardContains(name)
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func hasAssociatedSets(_ exerciseId: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }
}
```

**Files**: `Reppo/Core/Repositories/ExerciseRepository.swift` (new, ~50 lines)
**Parallel?**: Yes

**Notes**:
- `search(name:)` uses `localizedStandardContains` for case-insensitive, diacritics-insensitive search. Verify this works in `#Predicate` — if not, fall back to `contains` with `.caseInsensitive`.
- `hasAssociatedSets` queries `WorkoutSet` (a different entity) using the same `modelContext`. This is valid since `@ModelActor` context has access to all models in the container.
- Uses `fetchLimit = 1` to avoid loading all sets — efficient existence check.

---

### Subtask T015 – Create ExerciseStatsRepository

**Purpose**: Implement basic CRUD for ExerciseStats — the pre-computed aggregate cache. StatsService handles the computation logic; this repository just stores/retrieves.

**Steps**:

1. Create file `Reppo/Core/Repositories/ExerciseStatsRepository.swift`
2. Define `@ModelActor actor ExerciseStatsRepository: ExerciseStatsRepositoryProtocol`
3. Implement all methods:

```swift
@ModelActor
actor ExerciseStatsRepository: ExerciseStatsRepositoryProtocol {

    func save(_ stats: ExerciseStats) throws {
        modelContext.insert(stats)
        try modelContext.save()
    }

    func delete(_ stats: ExerciseStats) throws {
        modelContext.delete(stats)
        try modelContext.save()
    }

    func fetch(for exerciseId: UUID) throws -> ExerciseStats? {
        let descriptor = FetchDescriptor<ExerciseStats>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchAll() throws -> [ExerciseStats] {
        let descriptor = FetchDescriptor<ExerciseStats>()
        return try modelContext.fetch(descriptor)
    }
}
```

**Files**: `Reppo/Core/Repositories/ExerciseStatsRepository.swift` (new, ~30 lines)
**Parallel?**: Yes

---

### Subtask T016 – Create HealthProfileRepository

**Purpose**: Implement CRUD for HealthProfile (single-row table) with `fetchOrCreate()` that guarantees a non-nil return by creating with defaults if no profile exists.

**Steps**:

1. Create file `Reppo/Core/Repositories/HealthProfileRepository.swift`
2. Define `@ModelActor actor HealthProfileRepository: HealthProfileRepositoryProtocol`
3. Implement all methods:

```swift
@ModelActor
actor HealthProfileRepository: HealthProfileRepositoryProtocol {

    func save(_ profile: HealthProfile) throws {
        modelContext.insert(profile)
        try modelContext.save()
    }

    func fetch() throws -> HealthProfile? {
        var descriptor = FetchDescriptor<HealthProfile>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchOrCreate() throws -> HealthProfile {
        if let existing = try fetch() {
            return existing
        }
        // Create with defaults per AGENT_RULES S8
        let profile = HealthProfile(
            unitPreference: .metric,
            includeWarmupsInVolume: false,
            includeWarmupsInPRs: false,
            e1RMFormula: "epley"
        )
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }
}
```

**Files**: `Reppo/Core/Repositories/HealthProfileRepository.swift` (new, ~35 lines)
**Parallel?**: Yes

**Notes**:
- `fetchOrCreate` is the primary access method — ensures a profile always exists after first call
- Default values match AGENT_RULES Section 8: metric, no warmups in volume/PRs, Epley formula
- No `delete` method on the protocol — HealthProfile should always exist
- The `HealthProfile` initializer depends on what feature 001 defined. Verify parameter names match the @Model class.

---

### Subtask T017 – Create ProgramRepository

**Purpose**: Implement basic CRUD for Program. Minimal — Programs tab is v1.1 empty-state placeholder.

**Steps**:

1. Create file `Reppo/Core/Repositories/ProgramRepository.swift`
2. Define `@ModelActor actor ProgramRepository: ProgramRepositoryProtocol`
3. Implement all methods:

```swift
@ModelActor
actor ProgramRepository: ProgramRepositoryProtocol {

    func save(_ program: Program) throws {
        modelContext.insert(program)
        try modelContext.save()
    }

    func delete(_ program: Program) throws {
        modelContext.delete(program)
        try modelContext.save()
    }

    func fetch(byId id: UUID) throws -> Program? {
        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchAll() throws -> [Program] {
        let descriptor = FetchDescriptor<Program>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
}
```

**Files**: `Reppo/Core/Repositories/ProgramRepository.swift` (new, ~30 lines)
**Parallel?**: Yes

---

### Subtask T018 – Wire All 8 Repositories in ReppoApp.swift (DI Wiring)

**Purpose**: Instantiate all 8 repository actors from the shared ModelContainer at app launch and make them available to the view hierarchy via dependency injection. This completes the repository layer and makes it usable by future Service implementations (features 003-005).

**Steps**:

1. Open `Reppo/App/ReppoApp.swift` (exists from feature 001)
2. Create a `RepositoryContainer` class to hold all repositories:

```swift
import SwiftData

/// Lightweight container holding all repository actors.
/// Created once at app launch, passed to views via SwiftUI environment.
@Observable
final class RepositoryContainer {
    let setRepository: SetRepository
    let workoutRepository: WorkoutRepository
    let exerciseRepository: ExerciseRepository
    let exerciseStatsRepository: ExerciseStatsRepository
    let performanceRecordRepository: PerformanceRecordRepository
    let bodyweightEntryRepository: BodyweightEntryRepository
    let healthProfileRepository: HealthProfileRepository
    let programRepository: ProgramRepository

    init(modelContainer: ModelContainer) {
        self.setRepository = SetRepository(modelContainer: modelContainer)
        self.workoutRepository = WorkoutRepository(modelContainer: modelContainer)
        self.exerciseRepository = ExerciseRepository(modelContainer: modelContainer)
        self.exerciseStatsRepository = ExerciseStatsRepository(modelContainer: modelContainer)
        self.performanceRecordRepository = PerformanceRecordRepository(modelContainer: modelContainer)
        self.bodyweightEntryRepository = BodyweightEntryRepository(modelContainer: modelContainer)
        self.healthProfileRepository = HealthProfileRepository(modelContainer: modelContainer)
        self.programRepository = ProgramRepository(modelContainer: modelContainer)
    }
}
```

3. Instantiate in ReppoApp and inject:

```swift
@main
struct ReppoApp: App {
    let modelContainer: ModelContainer
    let repositories: RepositoryContainer

    init() {
        let container = try! ModelContainer(for:
            WorkoutSet.self,
            Workout.self,
            Exercise.self,
            ExerciseStats.self,
            PerformanceRecord.self,
            BodyweightEntry.self,
            HealthProfile.self,
            Program.self,
            ProgramExercise.self,
            PlannedWorkout.self,
            PlannedSet.self
        )
        self.modelContainer = container
        self.repositories = RepositoryContainer(modelContainer: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(repositories)
        }
        .modelContainer(modelContainer)
    }
}
```

**Files**: `Reppo/App/ReppoApp.swift` (modify existing), optionally `Reppo/Core/Repositories/RepositoryContainer.swift` (new)
**Parallel?**: No — depends on all repositories existing

**Notes**:
- `RepositoryContainer` uses `@Observable` so SwiftUI can detect it in the environment
- Each repository gets its own `ModelContext` (created by `@ModelActor` init)
- All share the same `ModelContainer` (thread-safe, `Sendable`)
- `try!` on ModelContainer creation is acceptable for app launch — if this fails, the app can't function
- The `RepositoryContainer` can live in its own file or in ReppoApp.swift — keep it clean

**Alternative approach** if `@Observable` doesn't work with actor properties: Use separate `EnvironmentKey` per repository, or pass as init parameters to the root ViewModel.

---

### Subtask T019 – Add iOS 18 Index Comments to Model Files

**Purpose**: Document the required compound indexes as code comments in the model files, with exact `#Index` syntax for when the deployment target is raised to iOS 18. This satisfies spec FR-006/FR-007 documentation requirements even though the indexes can't be configured on iOS 17.

**Steps**:

1. Open `Reppo/Data/Models/PerformanceRecord.swift`
2. Add comment block inside the `@Model` class:
   ```swift
   // MARK: - Indexes (iOS 18+)
   // When minimum deployment target is raised to iOS 18, uncomment:
   // #Index<PerformanceRecord>([\.exerciseId, \.recordType, \.reps])
   // This index optimizes the PR lookup query used on every set save.
   // See: AGENT_RULES Section 5.4, specdoc Section 7.6
   ```

3. Open `Reppo/Data/Models/WorkoutSet.swift`
4. Add comment block inside the `@Model` class:
   ```swift
   // MARK: - Indexes (iOS 18+)
   // When minimum deployment target is raised to iOS 18, uncomment:
   // #Index<WorkoutSet>(
   //     [\.exerciseId, \.reps, \.effectiveWeight, \.date],
   //     [\.workoutId],
   //     [\.exerciseId]
   // )
   // Compound index optimizes PR recomputation queries.
   // Single-column indexes optimize workout and exercise lookups.
   // See: AGENT_RULES Section 5.4, specdoc Section 7.6
   ```

**Files**: `Reppo/Data/Models/PerformanceRecord.swift` (modify), `Reppo/Data/Models/WorkoutSet.swift` (modify)
**Parallel?**: Yes — independent of other subtasks

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| `#Predicate` with enum comparison fails for `WorkoutStatus` | Medium | Capture enum value in local `let` variable before predicate closure. If still fails, compare raw string values. |
| `localizedStandardContains` not supported in `#Predicate` | Medium | Fall back to `contains` or `localizedCaseInsensitiveContains` |
| SwiftUI `.environment` injection for `@Observable` with actor properties | Low | `@Observable` should work since properties are `let` (immutable references). If not, use separate `EnvironmentKey` definitions. |
| `HealthProfile` initializer mismatch with feature 001 | Low | Check feature 001 model definition; match parameter names exactly. |

---

## Definition of Done Checklist

- [ ] `WorkoutRepository.swift` created with all 6 methods
- [ ] `ExerciseRepository.swift` created with all 6 methods including `hasAssociatedSets`
- [ ] `ExerciseStatsRepository.swift` created with all 4 methods
- [ ] `HealthProfileRepository.swift` created with all 3 methods including `fetchOrCreate`
- [ ] `ProgramRepository.swift` created with all 4 methods
- [ ] All 5 actors use `@ModelActor` macro and conform to protocols
- [ ] `RepositoryContainer` created and injected in `ReppoApp.swift`
- [ ] iOS 18 `#Index` comments added to `PerformanceRecord.swift` and `WorkoutSet.swift`
- [ ] Project builds with zero errors
- [ ] All 8 repositories are accessible via the container
- [ ] `tasks.md` updated with status change

---

## Review Guidance

- **Completeness check**: All 8 repositories exist (3 from WP02 + 5 from this WP)
- **DI check**: `RepositoryContainer` creates all 8 from shared `ModelContainer`. Injected into SwiftUI environment.
- **Architecture check**: Only repository files import SwiftData. ReppoApp imports SwiftData for ModelContainer only.
- **Index check**: Both model files have `#Index` comment blocks with correct syntax.
- **Build check**: Project compiles with zero errors, zero warnings.
- **Protocol conformance**: Every repository actor conforms to its protocol.

---

## Activity Log

- 2026-02-20T12:32:56Z – system – lane=planned – Prompt created.
- 2026-02-22T20:09:06Z – unknown – lane=for_review – Ready for review: 5 repositories + RepositoryContainer + DI wiring + iOS 18 index comments + Xcode project registration. Build succeeds.
- 2026-02-22T20:09:53Z – claude – shell_pid=95869 – lane=doing – Started review via workflow command
- 2026-02-22T20:11:14Z – claude – shell_pid=95869 – lane=done – Review passed: All 5 repositories match protocol contracts (23/23 methods). RepositoryContainer wires all 8 repos via @Observable + .environment(). iOS 18 #Index comments correct for both model files. Build succeeds with zero errors/warnings. Xcode project correctly registers all 18 WP01-WP03 files.
- 2026-02-22T20:17:12Z – claude – shell_pid=95869 – lane=planned – Reset for proper activity log
- 2026-02-22T20:17:12Z – claude – shell_pid=95869 – lane=done – Review passed: All 5 repos + DI wiring + index comments. Build passed.
