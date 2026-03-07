---
work_package_id: "WP05"
subtasks:
  - "T023"
  - "T024"
  - "T025"
title: "ServiceContainer + DI Wiring"
phase: "Phase 2 - Integration"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "69158"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP04"]
history:
  - timestamp: "2026-02-23T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP05 – ServiceContainer + DI Wiring

## Implementation Command

Depends on WP04:
```bash
spec-kitty implement WP05 --base WP04
```

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback, update `review_status: acknowledged`.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- Create (or update) `ServiceContainer` to hold PRService, StatsService, and SetService
- Wire `ServiceContainer` into `ReppoApp.swift` via SwiftUI `.environment()`
- Full project builds with zero errors and all protocols satisfied
- Initialization order: StatsService → PRService → SetService (respects dependencies)

## Context & Constraints

- **Plan**: `kitty-specs/004-set-and-stats-services/plan.md` — ServiceContainer design
- **Existing code**:
  - `Reppo/Core/Repositories/RepositoryContainer.swift` — holds all 8 repositories, created from ModelContainer
  - `Reppo/App/ReppoApp.swift` — app entry point, currently wires RepositoryContainer
  - `Reppo/Core/Services/ServiceContainer.swift` — MAY exist from feature 003 (PRService). If so, extend it. If not, create it fresh.
- **Architecture**: `ServiceContainer` is `@Observable final class`. Takes `RepositoryContainer` in init. Injected alongside RepositoryContainer into SwiftUI environment.
- **Feature 003 state**: If 003 is merged, ServiceContainer exists with PRService only — extend it. If not merged, create ServiceContainer from scratch with all three services.

## Subtasks & Detailed Guidance

### Subtask T023 – Create/Update ServiceContainer

- **Purpose**: Central DI container for all services. Takes RepositoryContainer and creates service instances with proper dependency wiring.
- **Steps**:
  1. **Check if `Reppo/Core/Services/ServiceContainer.swift` exists**:
     - If YES (from feature 003): extend it to add StatsService and SetService
     - If NO: create it fresh with all three services

  2. **Create new (or replace existing) ServiceContainer**:
     ```swift
     import Foundation
     import Observation

     @Observable
     final class ServiceContainer {
         let prService: any PRServiceProtocol
         let statsService: any StatsServiceProtocol
         let setService: any SetServiceProtocol

         init(repositoryContainer: RepositoryContainer) {
             // Order matters: SetService depends on PRService and StatsService

             // 1. StatsService — no service dependencies
             let statsService = StatsService(
                 exerciseStatsRepository: repositoryContainer.exerciseStatsRepository,
                 setRepository: repositoryContainer.setRepository,
                 exerciseRepository: repositoryContainer.exerciseRepository,
                 healthProfileRepository: repositoryContainer.healthProfileRepository
             )

             // 2. PRService — no service dependencies
             // NOTE: If feature 003 is not merged, PRService concrete type won't exist.
             // Options:
             // a) If PRService.swift exists: use it
             // b) If not: create a stub/placeholder that conforms to PRServiceProtocol
             //    OR make prService optional/late-initialized
             let prService = PRService(
                 performanceRecordRepository: repositoryContainer.performanceRecordRepository,
                 setRepository: repositoryContainer.setRepository,
                 healthProfileRepository: repositoryContainer.healthProfileRepository,
                 exerciseRepository: repositoryContainer.exerciseRepository
             )

             // 3. SetService — depends on both PRService and StatsService
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

  3. **Protocol-typed properties**: Use `any PRServiceProtocol` etc. for the stored properties. This makes the container testable (can inject mocks) and decouples from concrete implementations.

  4. **If PRService doesn't exist** (003 not merged): You have two options:
     a. **Stub PRService**: Create a minimal `StubPRService` that conforms to `PRServiceProtocol` and returns empty/default results. This lets the app build and run, with PR features disabled until 003 merges.
     b. **Compile-time flag**: Use `#if` to conditionally include PRService. Less clean.

     **Recommended: Option (a)** — create a stub. It's simple and gets removed when 003 merges.

     ```swift
     /// Placeholder PRService used when feature 003 is not yet available.
     /// Returns empty/no-op results for all methods.
     /// Remove when PRService is merged from feature 003.
     actor StubPRService: PRServiceProtocol {
         func evaluate(setId: UUID, exerciseId: UUID, reps: Int, effectiveWeight: Double,
                       workoutId: UUID, setType: SetType, hasData: Bool, excludeFromPRs: Bool,
                       date: Date) async throws -> PREvaluationResult {
             PREvaluationResult(setId: setId, newStatus: nil, affectedSetIds: [:], prRecordChanged: false)
         }

         func evaluateAfterEdit(setId: UUID, exerciseId: UUID, reps: Int, effectiveWeight: Double,
                                workoutId: UUID, setType: SetType, hasData: Bool, excludeFromPRs: Bool,
                                previousCachedPRStatus: CachedPRStatus?, date: Date) async throws -> PREvaluationResult {
             PREvaluationResult(setId: setId, newStatus: nil, affectedSetIds: [:], prRecordChanged: false)
         }

         func handleDeletion(setId: UUID, exerciseId: UUID, reps: Int,
                             cachedPRStatus: CachedPRStatus?) async throws -> PREvaluationResult {
             PREvaluationResult(setId: setId, newStatus: nil, affectedSetIds: [:], prRecordChanged: false)
         }

         func fetchPRTable(for exerciseId: UUID) async throws -> [PRTableEntry] { [] }
         func rebuildAll() async throws {}
         func rebuild(for exerciseId: UUID) async throws {}
     }
     ```

- **Files**: `Reppo/Core/Services/ServiceContainer.swift` (new or existing)
- **Parallel?**: No — must come before T024
- **Notes**: The `@Observable` annotation requires `import Observation`. `RepositoryContainer` stores concrete repository types (not protocols). ServiceContainer can access them directly. The protocol-typed stored properties (`any PRServiceProtocol`) have a small performance cost but are worth it for testability and flexibility.

### Subtask T024 – Wire ServiceContainer into ReppoApp.swift

- **Purpose**: Make all services accessible throughout the SwiftUI view hierarchy via environment injection.
- **Steps**:
  1. Open `Reppo/App/ReppoApp.swift`
  2. Check current structure — it should already create `RepositoryContainer` and inject it
  3. Add `ServiceContainer` creation after `RepositoryContainer`:
     ```swift
     @main
     struct ReppoApp: App {
         let modelContainer: ModelContainer
         let repositoryContainer: RepositoryContainer
         let serviceContainer: ServiceContainer

         init() {
             let container = try! ModelContainerSetup.createContainer()
             self.modelContainer = container
             self.repositoryContainer = RepositoryContainer(modelContainer: container)
             self.serviceContainer = ServiceContainer(repositoryContainer: repositoryContainer)
         }

         var body: some Scene {
             WindowGroup {
                 ContentView()
                     .environment(repositoryContainer)
                     .environment(serviceContainer)
                     .modelContainer(modelContainer)
             }
         }
     }
     ```
  4. **Environment injection**: `.environment(serviceContainer)` makes it accessible via `@Environment(ServiceContainer.self)` in any view.
  5. **Order**: RepositoryContainer first, then ServiceContainer (which takes RepositoryContainer in init).
- **Files**: `Reppo/App/ReppoApp.swift` (existing file, modify)
- **Parallel?**: No — depends on T023
- **Notes**: Read the existing ReppoApp.swift carefully before modifying. Preserve all existing setup (ModelContainer, RepositoryContainer). Only ADD ServiceContainer creation and injection.

### Subtask T025 – Verify full project build

- **Purpose**: Ensure the entire project compiles with zero errors after all feature 004 additions. All protocol conformances must be satisfied.
- **Steps**:
  1. Build the project: `cmd+B` in Xcode or `xcodebuild build`
  2. Check for:
     - All protocol conformances satisfied (StatsService: StatsServiceProtocol, SetService: SetServiceProtocol)
     - All value types Sendable
     - No missing imports
     - No ambiguous references
     - No SwiftData import in service files
  3. Fix any compilation errors
  4. Verify no warnings related to feature 004 code
  5. **If PRServiceProtocol.swift doesn't exist**: The StubPRService from T023 satisfies the protocol. Ensure the stub compiles.
  6. **If feature 003 IS merged**: Remove the StubPRService and use the real PRService in ServiceContainer.
- **Files**: All files in `Reppo/Core/Services/` and modified files
- **Parallel?**: No — final verification step
- **Notes**: This is a gate — the work package is not done until the build succeeds with zero errors.

## Risks & Mitigations

- **Feature 003 merge state**: The biggest variable. If 003 is merged, ServiceContainer extends naturally. If not, the StubPRService approach keeps things compiling. Both paths are documented.
- **@Observable on ServiceContainer**: Requires iOS 17+ (which is our minimum target). The `@Observable` macro generates conformance to the Observable protocol for SwiftUI environment injection.
- **RepositoryContainer stores concrete types**: `RepositoryContainer` exposes `setRepository: SetRepository` (concrete type, not protocol). ServiceContainer passes these as protocol-typed parameters to service inits. Swift's implicit protocol conformance handles this.
- **ReppoApp.swift changes**: This file is small and critical. Read it fully before modifying. Don't break existing RepositoryContainer setup.

## Definition of Done Checklist

- [ ] `ServiceContainer.swift` exists with PRService, StatsService, and SetService
- [ ] ServiceContainer uses protocol-typed properties (`any PRServiceProtocol`, etc.)
- [ ] Initialization order: StatsService → PRService → SetService
- [ ] If PRService doesn't exist: StubPRService created as placeholder
- [ ] `ReppoApp.swift` creates ServiceContainer and injects via `.environment()`
- [ ] Full project builds with zero errors (`xcodebuild build`)
- [ ] No warnings related to feature 004 code
- [ ] ServiceContainer is accessible from SwiftUI views via `@Environment`

## Review Guidance

- Verify ServiceContainer initialization order respects dependencies
- Verify protocol-typed properties for testability
- Verify ReppoApp.swift preserves existing setup (ModelContainer, RepositoryContainer)
- Verify StubPRService returns safe defaults (empty results, no crashes)
- Build the project and confirm zero errors
- Check that ServiceContainer doesn't import SwiftData (it receives repos via RepositoryContainer)

## Activity Log

- 2026-02-23T12:00:00Z – system – lane=planned – Prompt created.
- 2026-02-24T10:38:03Z – claude – lane=for_review – Moved to for_review
- 2026-02-24T10:38:07Z – claude – shell_pid=69158 – lane=doing – Started review via workflow command
- 2026-02-24T10:38:20Z – claude – shell_pid=69158 – lane=done – Review passed: ServiceContainer with correct init order (Stats→PR→Set), existential protocol types (any *Protocol), proper 6-dep injection into SetService. ReppoApp wires both RepositoryContainer and ServiceContainer via .environment(). Clean, minimal.
