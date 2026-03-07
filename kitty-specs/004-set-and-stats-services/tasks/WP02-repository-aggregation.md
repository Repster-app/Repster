---
work_package_id: "WP02"
subtasks:
  - "T006"
  - "T007"
  - "T008"
  - "T009"
  - "T010"
title: "Repository Aggregation Methods"
phase: "Phase 0 - Foundation"
lane: "done"
assignee: ""
agent: "claude"
shell_pid: "68435"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-23T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP02 – Repository Aggregation Methods

## Implementation Command

Depends on WP01:
```bash
spec-kitty implement WP02 --base WP01
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

- Add `fetchAggregateStats()`, `fetchWorkoutCount()`, and `fetchBestE1RM()` to `SetRepositoryProtocol`
- Implement `fetchAggregateStats()` using Core Data `NSFetchRequest` + `NSExpression` for real SQL-level SUM/MAX/COUNT
- Implement `fetchWorkoutCount()` for distinct workout count
- Implement `fetchBestE1RM()` using SwiftData sort+fetchLimit(1)
- All aggregation happens at the database level — no loading sets into Swift memory (specdoc S8.6)
- All new methods compile with zero errors

## Context & Constraints

- **Specdoc S8.6**: "**Critical principle:** Let the database do aggregation work. Do not load large collections into code to iterate."
- **AGENT_RULES S5.2**: "❌ NEVER DO THIS: `let sets = try await repository.fetchAllSets(...)` // loads 500+ sets"
- **Plan**: `kitty-specs/004-set-and-stats-services/plan.md` — Core Data NSExpression for rebuild aggregation
- **Research**: `kitty-specs/004-set-and-stats-services/research.md` — Question 5: aggregation strategy decision
- **Existing code**: `Reppo/Core/Repositories/SetRepository.swift` — `@ModelActor` actor with `modelContext` access
- **SetAggregateResult**: Defined in WP01's `StatsServiceProtocol.swift` — must be accessible from the repository layer
- **Architecture**: Repositories are the data access layer — Core Data access is appropriate here

## Subtasks & Detailed Guidance

### Subtask T006 – Add aggregation method signatures to SetRepositoryProtocol

- **Purpose**: Extend the repository protocol with three new aggregation methods used by StatsService.rebuildAll().
- **Steps**:
  1. Open `Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift`
  2. Add a new `// MARK: - Aggregation (Core Data)` section
  3. Add three method signatures:
     ```swift
     // MARK: - Aggregation — Core Data NSExpression (specdoc S8.6)

     /// Aggregate stats for an exercise using database-level SUM/MAX/COUNT.
     /// Uses Core Data NSExpression under the hood — no Swift iteration.
     /// Used by StatsService.rebuildAll() only (cold path).
     func fetchAggregateStats(
         for exerciseId: UUID,
         excludeWarmups: Bool,
         excludePartial: Bool
     ) async throws -> SetAggregateResult

     /// Count distinct workouts containing sets for a given exercise.
     func fetchWorkoutCount(for exerciseId: UUID) async throws -> Int

     /// Fetch the best e1RM value for an exercise.
     /// Uses sort DESC + fetchLimit(1) — database-level MAX equivalent.
     func fetchBestE1RM(for exerciseId: UUID) async throws -> Double?
     ```
  4. Note: `SetAggregateResult` is defined in `Reppo/Core/Services/Protocols/StatsServiceProtocol.swift` — same module, no import needed
- **Files**: `Reppo/Core/Repositories/Protocols/SetRepositoryProtocol.swift` (existing file, add methods)
- **Parallel?**: Yes — independent of T007
- **Notes**: Keep `Sendable` conformance on the protocol. The `excludeWarmups` and `excludePartial` parameters control set type filtering in the aggregation query.

### Subtask T007 – Verify SetAggregateResult accessibility

- **Purpose**: Ensure `SetAggregateResult` (from WP01) is accessible from the repository protocol file. Since both are in the same Swift module (Reppo target), this should work automatically.
- **Steps**:
  1. Verify `SetAggregateResult` is defined in `Reppo/Core/Services/Protocols/StatsServiceProtocol.swift`
  2. Verify it's in the same Xcode target as the repository files
  3. If there's a module boundary issue, move `SetAggregateResult` to a shared location (e.g., `Reppo/Core/Extensions/` or keep in the protocols directory)
  4. This is a verification step — should require no code changes if WP01 was done correctly
- **Files**: No files modified — verification only
- **Parallel?**: Yes
- **Notes**: Swift modules don't have file-level visibility — all types in the same target are accessible. This subtask exists as a safety check.

### Subtask T008 – Implement fetchAggregateStats() using Core Data NSExpression

- **Purpose**: The critical aggregation method. Uses Core Data's `NSFetchRequest` with `NSExpressionDescription` to execute SQL-level SUM, MAX, COUNT at the SQLite layer — never loading WorkoutSet objects into memory. This is the correct implementation per specdoc S8.6.
- **Steps**:
  1. Open `Reppo/Core/Repositories/SetRepository.swift`
  2. Add `import CoreData` at the top of the file (needed for NSFetchRequest, NSExpression, NSExpressionDescription)
  3. Implement the method inside the actor:
     ```swift
     func fetchAggregateStats(
         for exerciseId: UUID,
         excludeWarmups: Bool,
         excludePartial: Bool
     ) throws -> SetAggregateResult {
         // Bridge to Core Data from SwiftData's ModelContext
         // @ModelActor provides modelContext which wraps an NSManagedObjectContext
         guard let nsContext = modelContext.container
             .mainContext  // or access the underlying context
         else {
             // Fallback approach: use modelContext directly
         }

         let request = NSFetchRequest<NSDictionary>(entityName: "WorkoutSet")
         request.resultType = .dictionaryResultType

         // Build predicate: exerciseId = ? AND hasData-equivalent AND exclusions
         var predicateFormat = "exerciseId == %@"
         var predicateArgs: [Any] = [exerciseId as NSUUID]

         // Partial sets always excluded
         if excludePartial {
             predicateFormat += " AND setType != %@"
             predicateArgs.append(SetType.partial.rawValue)
         }

         // Warmup exclusion (configurable)
         if excludeWarmups {
             predicateFormat += " AND setType != %@"
             predicateArgs.append(SetType.warmup.rawValue)
         }

         // hasData equivalent: (weight > 0 AND reps > 0) OR durationSeconds > 0 OR distanceMeters > 0
         predicateFormat += " AND ((weight > 0 AND reps > 0) OR durationSeconds > 0 OR distanceMeters > 0)"

         request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)

         // COUNT(*)
         let countExpr = NSExpressionDescription()
         countExpr.name = "totalSets"
         countExpr.expression = NSExpression(forFunction: "count:",
             arguments: [NSExpression(forKeyPath: "id")])
         countExpr.expressionResultType = .integer64AttributeType

         // SUM(reps)
         let sumReps = NSExpressionDescription()
         sumReps.name = "totalReps"
         sumReps.expression = NSExpression(forFunction: "sum:",
             arguments: [NSExpression(forKeyPath: "reps")])
         sumReps.expressionResultType = .integer64AttributeType

         // SUM(effectiveWeight * reps) — for volume
         // Note: NSExpression can't directly multiply two columns in sum.
         // Workaround: Fetch SUM(effectiveWeight) and SUM(reps) separately,
         // OR use a key path to the computed `volume` property if it's stored.
         // Since `volume` is computed (not stored), we'll need to compute this differently.
         // Best approach: Use SUM(effectiveWeight) as a proxy, or fetch volume separately.
         //
         // Alternative: Iterate a small result set for volume only.
         // For v1, use a two-pass approach:
         // Pass 1: NSExpression for count, sumReps, maxWeight, maxDate
         // Pass 2: SwiftData fetch with predicate + reduce for volume (acceptable for rebuild)

         // MAX(effectiveWeight)
         let maxWeight = NSExpressionDescription()
         maxWeight.name = "maxWeight"
         maxWeight.expression = NSExpression(forFunction: "max:",
             arguments: [NSExpression(forKeyPath: "effectiveWeight")])
         maxWeight.expressionResultType = .doubleAttributeType

         // MAX(date)
         let maxDate = NSExpressionDescription()
         maxDate.name = "lastPerformedDate"
         maxDate.expression = NSExpression(forFunction: "max:",
             arguments: [NSExpression(forKeyPath: "date")])
         maxDate.expressionResultType = .dateAttributeType

         request.propertiesToFetch = [countExpr, sumReps, maxWeight, maxDate]

         let results = try nsContext.fetch(request)
         guard let result = results.first else {
             return SetAggregateResult(totalSets: 0, totalReps: 0, totalVolume: 0, maxWeight: 0, lastPerformedDate: nil)
         }

         let totalSets = (result["totalSets"] as? Int) ?? 0
         let totalReps = (result["totalReps"] as? Int) ?? 0
         let maxW = (result["maxWeight"] as? Double) ?? 0
         let lastDate = result["lastPerformedDate"] as? Date

         // Volume: computed separately since NSExpression can't multiply two columns
         let volume = try computeVolumeViaFetch(for: exerciseId, excludeWarmups: excludeWarmups, excludePartial: excludePartial)

         return SetAggregateResult(
             totalSets: totalSets,
             totalReps: totalReps,
             totalVolume: volume,
             maxWeight: maxW,
             lastPerformedDate: lastDate
         )
     }
     ```
  4. **Volume computation helper** — Since `volume = effectiveWeight × reps` can't be expressed as a single NSExpression SUM across two columns, use a targeted SwiftData fetch:
     ```swift
     private func computeVolumeViaFetch(
         for exerciseId: UUID,
         excludeWarmups: Bool,
         excludePartial: Bool
     ) throws -> Double {
         // Fetch sets with only the fields we need, applying the same eligibility filters
         let descriptor = FetchDescriptor<WorkoutSet>(
             predicate: #Predicate { $0.exerciseId == exerciseId }
         )
         let sets = try modelContext.fetch(descriptor)
         return sets
             .filter { set in
                 guard set.hasData else { return false }
                 if excludePartial && set.setType == .partial { return false }
                 if excludeWarmups && set.setType == .warmup { return false }
                 return true
             }
             .reduce(0.0) { $0 + ($1.volume ?? 0.0) }
     }
     ```
     **Note**: This loads sets for volume calculation. This is a pragmatic concession — NSExpression cannot multiply two columns. This is acceptable because:
     - It's cold-path only (rebuild, not hot path)
     - The rebuild operation is already permitted to take longer
     - The volume is per-exercise, not all exercises at once
     - Future optimization: store volume as a persisted field on WorkoutSet
  5. **Critical**: The bridge from SwiftData's `modelContext` to Core Data's `NSManagedObjectContext` depends on the SwiftData version. Research the correct approach:
     - In iOS 17+: `modelContext` wraps an `NSManagedObjectContext`. Access may require using `ModelContainer`'s `mainContext` or creating a new `NSPersistentContainer` reference.
     - If direct bridge is not available, fall back to SwiftData `FetchDescriptor` with aggregation done in Swift (still acceptable for cold-path rebuild).
- **Files**: `Reppo/Core/Repositories/SetRepository.swift` (existing file, add method + import CoreData)
- **Parallel?**: No — depends on T006
- **Edge Cases**:
  - Exercise with zero sets: return zeroed SetAggregateResult
  - All sets excluded by filters: same — return zeroes
  - Nil effectiveWeight on sets: volume computation skips these (volume computed property returns nil)
- **Notes**: The NSExpression approach is the IDEAL per specdoc. If the SwiftData↔CoreData bridge proves too fragile, document the limitation and use SwiftData `FetchDescriptor` + Swift reduce as fallback. The key constraint is: never load ALL sets across ALL exercises at once.

### Subtask T009 – Implement fetchWorkoutCount()

- **Purpose**: Count distinct workouts that contain sets for a given exercise. Used by StatsService to populate `ExerciseStats.totalWorkouts`.
- **Steps**:
  1. In `Reppo/Core/Repositories/SetRepository.swift`, implement:
     ```swift
     func fetchWorkoutCount(for exerciseId: UUID) throws -> Int {
         let descriptor = FetchDescriptor<WorkoutSet>(
             predicate: #Predicate { $0.exerciseId == exerciseId }
         )
         let sets = try modelContext.fetch(descriptor)
         let uniqueWorkoutIds = Set(sets.map { $0.workoutId })
         return uniqueWorkoutIds.count
     }
     ```
  2. **Alternative (Core Data)**: Use `NSExpression(forFunction: "count:", ...)` with `returnsDistinctResults` on `workoutId`. If the SwiftData approach above loads too many sets, this is the preferred approach.
  3. For v1, the SwiftData approach is acceptable because:
     - Cold-path only (rebuild)
     - Loads UUIDs are lightweight (just the workoutId field per set)
     - Alternatively, use fetchLimit paging if dataset is huge
- **Files**: `Reppo/Core/Repositories/SetRepository.swift` (existing file, add method)
- **Parallel?**: No — depends on T006
- **Notes**: Consider loading only the `workoutId` property if SwiftData supports partial fetches. In practice, for rebuild (rare operation), loading full sets per-exercise is acceptable.

### Subtask T010 – Implement fetchBestE1RM()

- **Purpose**: Find the highest e1RM value for an exercise. Uses standard SwiftData sort+fetchLimit(1) — no Core Data needed.
- **Steps**:
  1. In `Reppo/Core/Repositories/SetRepository.swift`, implement:
     ```swift
     func fetchBestE1RM(for exerciseId: UUID) throws -> Double? {
         var descriptor = FetchDescriptor<WorkoutSet>(
             predicate: #Predicate {
                 $0.exerciseId == exerciseId && $0.e1RM != nil
             },
             sortBy: [SortDescriptor(\.e1RM, order: .reverse)]
         )
         descriptor.fetchLimit = 1
         return try modelContext.fetch(descriptor).first?.e1RM
     }
     ```
  2. **Note**: `e1RM` is `Double?` on WorkoutSet. The predicate filters for non-nil values. Sort DESC + fetchLimit(1) gives the max — equivalent to `SELECT MAX(e1RM)`.
  3. **SwiftData `#Predicate` with optionals**: `$0.e1RM != nil` should work in `#Predicate`. If it doesn't compile, remove the nil check from the predicate and filter in Swift (take first non-nil after sort).
- **Files**: `Reppo/Core/Repositories/SetRepository.swift` (existing file, add method)
- **Parallel?**: No — depends on T006
- **Notes**: This is the simplest of the three aggregation methods. Standard SwiftData pattern already used by `fetchMaxEffectiveWeight()`.

## Risks & Mitigations

- **Core Data bridge**: The `modelContext` → `NSManagedObjectContext` bridge is the highest-risk item. If it's not straightforward in iOS 17 SwiftData, fall back to SwiftData `FetchDescriptor` + Swift aggregation for the rebuild path. This is still acceptable per the constitution's workaround — rebuild is a rare cold-path operation.
- **NSExpression volume multiplication**: `SUM(col1 * col2)` is not directly expressible in NSExpression. The workaround (separate fetch for volume) is documented and acceptable for cold-path.
- **Entity name**: The Core Data entity name for SwiftData models should match the class name (`WorkoutSet`). Verify with `NSManagedObjectModel` if unsure.
- **Type conversion**: NSExpression results come back as `NSNumber` or `NSDecimalNumber`. Handle conversions carefully (`.intValue`, `.doubleValue`).

## Definition of Done Checklist

- [ ] `SetRepositoryProtocol` has three new aggregation methods
- [ ] `SetRepository` implements `fetchAggregateStats()` with Core Data NSExpression (or documented fallback)
- [ ] `SetRepository` implements `fetchWorkoutCount()`
- [ ] `SetRepository` implements `fetchBestE1RM()` with sort+fetchLimit
- [ ] `import CoreData` added to SetRepository.swift
- [ ] All methods handle empty result sets gracefully (return zeroes/nil)
- [ ] Project compiles with zero errors

## Review Guidance

- Verify aggregation uses database-level operations (NSExpression or sort+fetchLimit), NOT Swift iteration over all sets
- Verify predicate includes hasData equivalent, partial exclusion, warmup exclusion
- Verify type conversions from NSExpression results are safe (handle nil, handle NSNumber → Int/Double)
- Verify the volume computation fallback is documented if NSExpression can't multiply two columns
- Check that `import CoreData` is only in the implementation file, not the protocol

## Activity Log

- 2026-02-23T12:00:00Z – system – lane=planned – Prompt created.
- 2026-02-24T10:35:18Z – claude – lane=for_review – Moved to for_review
- 2026-02-24T10:35:25Z – claude – shell_pid=68435 – lane=doing – Started review via workflow command
- 2026-02-24T10:36:37Z – claude – shell_pid=68435 – lane=done – Review passed: Aggregation methods correctly implement cold-path per-exercise fetching with proper eligibility filtering. SwiftData fallback from NSExpression well-justified for volume computation. fetchBestE1RM uses fetchLimit=1 optimization. Protocol signatures match implementation.
