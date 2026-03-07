---
work_package_id: "WP04"
subtasks:
  - "T013"
  - "T014"
  - "T015"
  - "T016"
title: "Bulk Rebuild + DI Wiring"
phase: "Phase 3 - Rebuild + Integration"
lane: "planned"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
dependencies: ["WP03"]
history:
  - timestamp: "2026-02-22T20:46:52Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP04 – Bulk Rebuild + DI Wiring

## Implementation Command

Depends on WP03:
```bash
spec-kitty implement WP04 --base WP03
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

- Implement `rebuild(for:)` — rebuild PRs for a single exercise from scratch
- Implement `rebuildAll()` — rebuild all PRs across all exercises
- Create a `ServiceContainer` (or similar) for DI wiring of PRService
- Wire PRService into `ReppoApp.swift` alongside existing `RepositoryContainer`
- After rebuild, all PerformanceRecords and cachedPRStatus values are consistent with current settings
- PRService is accessible from SwiftUI views via environment

## Context & Constraints

- **FR-011**: `PRService.rebuildAll()` MUST be available for bulk rebuild after import or settings changes
- **Constitution**: No startup rebuild — rebuildAll is manual-only from Settings or after import
- **Plan**: `kitty-specs/003-pr-service/plan.md` — rebuild strategy: delete all → re-evaluate from scratch
- **Existing code**:
  - `Reppo/App/ReppoApp.swift` — app entry point with existing RepositoryContainer setup
  - `Reppo/Core/Repositories/RepositoryContainer.swift` — existing DI container for repositories
  - All PRService methods from WP01-WP03 are implemented

## Subtasks & Detailed Guidance

### Subtask T013 – Implement rebuild(for:)

- **Purpose**: Rebuild PRs for a single exercise from scratch. Used by `rebuildAll()` and potentially by future features that need to recalculate PRs for one exercise (e.g., after bulk-editing an exercise's sets).
- **Steps**:
  1. Replace the `rebuild(for:)` stub in `PRService.swift`:

     ```swift
     func rebuild(for exerciseId: UUID) async throws {
         let profile = try await healthProfileRepo.fetchOrCreate()
         let excludeWarmups = !profile.includeWarmupsInPRs

         // Step 1: Delete all existing PerformanceRecords for this exercise
         let existingRecords = try await performanceRecordRepo.fetchAll(for: exerciseId)
         for record in existingRecords {
             try await performanceRecordRepo.delete(record)
         }

         // Step 2: Clear cachedPRStatus on ALL sets for this exercise
         let allSets = try await setRepo.fetchSets(for: exerciseId, limit: nil)
         for set in allSets {
             if set.cachedPRStatus != nil {
                 set.cachedPRStatus = nil
                 try await setRepo.save(set)
             }
         }

         // Step 3: Collect unique rep counts from eligible sets
         // Group eligible sets by reps, find best for each rep count
         var repCountsProcessed = Set<Int>()

         for set in allSets {
             guard let reps = set.reps else { continue }
             guard !repCountsProcessed.contains(reps) else { continue }
             repCountsProcessed.insert(reps)

             // Find the best eligible set for this rep count
             let best = try await setRepo.fetchBestEligibleSet(
                 for: exerciseId,
                 reps: reps,
                 excludeWarmups: excludeWarmups,
                 excludingSetId: nil
             )

             guard let winner = best, let ew = winner.effectiveWeight else { continue }

             // Create PerformanceRecord for the winner
             let record = PerformanceRecord(
                 exerciseId: exerciseId,
                 recordType: .repMax,
                 reps: reps,
                 value: ew,
                 setId: winner.id,
                 date: winner.date
             )
             try await performanceRecordRepo.save(record)

             // Set winner status to "current"
             winner.cachedPRStatus = .current
             try await setRepo.save(winner)

             // Step 4: Find matching sets (same weight, different workout)
             // and set their status to "matched"
             let eligibleSetsForReps = try await setRepo.fetchSets(
                 for: exerciseId,
                 reps: reps,
                 orderedBy: .effectiveWeightDesc
             )

             let winnerGrams = UnitConversion.toGrams(ew)
             for otherSet in eligibleSetsForReps {
                 guard otherSet.id != winner.id else { continue }
                 guard let otherEW = otherSet.effectiveWeight else { continue }

                 let otherGrams = UnitConversion.toGrams(otherEW)
                 if otherGrams == winnerGrams && otherSet.workoutId != winner.workoutId {
                     // Check eligibility before granting "matched"
                     guard otherSet.hasData else { continue }
                     guard otherSet.excludeFromPRs != true else { continue }
                     guard otherSet.setType != .partial else { continue }
                     if excludeWarmups && otherSet.setType == .warmup { continue }

                     otherSet.cachedPRStatus = .matched
                     try await setRepo.save(otherSet)
                 }
             }
         }
     }
     ```

  2. **Key principles**:
     - Clean slate: delete all PRs first, then rebuild
     - Use `fetchBestEligibleSet` for finding winners (consistent with evaluate/edit/delete paths)
     - Apply same-workout matching rule: only "matched" if different workout than winner
     - Clear ALL cachedPRStatus first to avoid stale values
     - Use integer grams for match comparison

- **Files**: `Reppo/Core/Services/PRService.swift`
- **Parallel?**: No — T014 depends on this
- **Notes**:
  - Performance: this loads all sets for an exercise. For v1 dataset sizes (≤50k total, maybe 500 per exercise), this is fine. Not a hot path.
  - The same-workout rule applies during rebuild — a matching set in the same workout as the winner gets null, not "matched"
  - Only `repMax` records are handled in this implementation. e1RM and maxVolume are for future features.

### Subtask T014 – Implement rebuildAll()

- **Purpose**: Rebuild all PRs across all exercises. Triggered from Settings when `includeWarmupsInPRs` changes, or after CSV import (FR-011).
- **Steps**:
  1. Replace the `rebuildAll()` stub:

     ```swift
     func rebuildAll() async throws {
         let allExercises = try await exerciseRepo.fetchAll()
         for exercise in allExercises {
             try await rebuild(for: exercise.id)
         }
     }
     ```

  2. That's it — `rebuild(for:)` handles all the per-exercise logic

- **Files**: `Reppo/Core/Services/PRService.swift`
- **Parallel?**: No — sequential by nature (depends on T013)
- **Notes**:
  - This is intentionally simple — all complexity is in `rebuild(for:)`
  - Performance: iterates all exercises sequentially. For v1 (maybe 50-100 exercises), this completes in seconds. Not a UI-blocking operation — called from Settings or import flow.
  - The HealthProfile is read inside `rebuild(for:)` for each exercise. Could be optimized to read once, but simplicity wins for a rare operation.

### Subtask T015 – Create ServiceContainer for DI

- **Purpose**: Establish the service-layer DI container. PRService is the first service — the container should be extensible for SetService, StatsService, etc. (feature 004).
- **Steps**:
  1. Create `Reppo/Core/Services/ServiceContainer.swift`:
     ```swift
     import Foundation

     @Observable
     final class ServiceContainer {
         let prService: PRService

         init(repositoryContainer: RepositoryContainer) {
             self.prService = PRService(
                 performanceRecordRepository: repositoryContainer.performanceRecordRepository,
                 setRepository: repositoryContainer.setRepository,
                 healthProfileRepository: repositoryContainer.healthProfileRepository,
                 exerciseRepository: repositoryContainer.exerciseRepository
             )
         }
     }
     ```

  2. **Design decisions**:
     - `@Observable` to match `RepositoryContainer` pattern
     - Takes `RepositoryContainer` in init — services compose repositories
     - Holds concrete `PRService` type (not protocol) — consistent with how `RepositoryContainer` holds concrete repository types
     - Future services (SetService, StatsService) will be added here

- **Files**: `Reppo/Core/Services/ServiceContainer.swift` (new file)
- **Parallel?**: Yes — independent of T013/T014
- **Notes**:
  - Do NOT import SwiftData — ServiceContainer only references services and RepositoryContainer
  - The `@Observable` macro may require `import Observation` on some Swift versions
  - Keep it simple — no lazy initialization, no protocols for the container itself

### Subtask T016 – Wire PRService into ReppoApp.swift

- **Purpose**: Connect PRService to the app's dependency injection so it's accessible from SwiftUI views and ViewModels.
- **Steps**:
  1. Open `Reppo/App/ReppoApp.swift`
  2. Add a `ServiceContainer` property alongside the existing `RepositoryContainer`:
     ```swift
     @main
     struct ReppoApp: App {
         let container: ModelContainer
         let repositoryContainer: RepositoryContainer
         let serviceContainer: ServiceContainer  // NEW

         init() {
             let container = ModelContainerSetup.createContainer()
             self.container = container
             let repoContainer = RepositoryContainer(modelContainer: container)
             self.repositoryContainer = repoContainer
             self.serviceContainer = ServiceContainer(repositoryContainer: repoContainer)  // NEW
         }

         var body: some Scene {
             WindowGroup {
                 ContentView()
                     .environment(repositoryContainer)
                     .environment(serviceContainer)  // NEW
             }
             .modelContainer(container)
         }
     }
     ```

  3. **Key points**:
     - `ServiceContainer` is created AFTER `RepositoryContainer` (it depends on repos)
     - Injected via `.environment()` — ViewModels will access it via `@Environment(ServiceContainer.self)`
     - Order matters: repos first, then services

  4. Read the existing `ReppoApp.swift` first to understand the current structure — adapt the above to match the actual code style

- **Files**: `Reppo/App/ReppoApp.swift` (existing file, modify)
- **Parallel?**: No — depends on T015 (ServiceContainer must exist)
- **Notes**:
  - The existing code may use slightly different property names or init structure — read the file first and adapt
  - If `@Observable` doesn't work with `.environment()` directly, use a custom `EnvironmentKey` as fallback (same pattern as RepositoryContainer)
  - Verify the project still compiles after wiring

## Risks & Mitigations

- **rebuild(for:) performance**: Loads all sets for an exercise. For v1 datasets (≤500 sets per exercise), this is fine. Not optimized for 10k+ sets per exercise — add pagination if needed later.
- **rebuild(for:) saves per set**: Each set update is a separate `setRepo.save()` call. For bulk operations, this could be slow. Mitigation: acceptable for v1 rare operation. Could be optimized with batch saves if profiling shows issues.
- **ServiceContainer holds concrete types**: If testing requires mocking, this would need protocol-based injection. Per constitution: no automated tests for v1, so concrete types are fine.
- **SwiftUI environment with @Observable**: `@Observable` works with `.environment()` in iOS 17 via `@Environment(Type.self)`. This is the same pattern used by `RepositoryContainer`.

## Definition of Done Checklist

- [ ] `rebuild(for:)` deletes all PRs for exercise, then rebuilds from eligible sets
- [ ] `rebuild(for:)` applies same-workout matching rule during rebuild
- [ ] `rebuild(for:)` uses integer grams for match comparison
- [ ] `rebuildAll()` iterates all exercises and calls rebuild(for:) each
- [ ] `ServiceContainer.swift` exists with PRService dependency
- [ ] `ReppoApp.swift` creates and injects ServiceContainer
- [ ] Project compiles with zero errors
- [ ] PRService is accessible via SwiftUI `@Environment(ServiceContainer.self)`
- [ ] `tasks.md` updated with status change

## Review Guidance

- Verify rebuild clears ALL cachedPRStatus before rebuilding (no stale values)
- Verify rebuild creates PerformanceRecords only for repMax (not e1RM or maxVolume)
- Verify same-workout rule is applied during rebuild
- Verify ServiceContainer takes RepositoryContainer in init
- Verify ReppoApp creates ServiceContainer after RepositoryContainer
- Verify no SwiftData import in ServiceContainer

## Activity Log

- 2026-02-22T20:46:52Z – system – lane=planned – Prompt created.
