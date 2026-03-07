---
work_package_id: "WP02"
subtasks:
  - "T005"
  - "T006"
  - "T007"
  - "T008"
  - "T009"
  - "T010"
title: "Import Logic — ImportService Implementation"
phase: "Phase 1 - Foundation"
lane: "done"
assignee: ""
agent: "claude-opus"
shell_pid: "90948"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01"]
history:
  - timestamp: "2026-03-01T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP02 – Import Logic — ImportService Implementation

## Implementation Command

```bash
spec-kitty implement WP02 --base WP01
```

## Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

Build the full ImportService actor that orchestrates CSV import end-to-end:

1. Parse CSV data using CSVParser (from WP01)
2. Validate header and individual rows
3. Map CSV fields to SwiftData entities (Workout, Exercise, WorkoutSet)
4. Perform chunked batch inserts with progress reporting
5. Trigger StatsService + PRService rebuild after import
6. Wire into ServiceContainer

**Success criteria**:
- Given a CSV with 100 rows across 10 dates and 15 exercises: produces 10 Workouts, creates new Exercises as needed, creates 100 WorkoutSets with correct field mapping.
- Kind column `"wr"` infers `trackingType = .weightReps` on new exercises. All sets get `setType = .working`.
- Malformed rows are skipped and collected in the error list.
- Progress stream reports parsing → validating → importing → rebuilding → completed.
- Post-import: StatsService.rebuildAll() and PRService.rebuildAll() are called (NOT per-set pipeline).

## Context & Constraints

**Design documents** (read ALL of these):
- `kitty-specs/011-csv-import-export/plan.md` — architecture, Kind mapping table, import algorithm, component architecture
- `kitty-specs/011-csv-import-export/data-model.md` — full CSV column mapping, defaults for new entities, import algorithm pseudocode, ServiceContainer wiring
- `kitty-specs/011-csv-import-export/research.md` — SwiftData batch insert patterns, @ModelActor, AsyncStream, Date parsing
- `kitty-specs/011-csv-import-export/spec.md` — FR-001 through FR-009, edge cases

**Architecture rules**:
- MVVM: View → ViewModel → Service → Repository → SwiftData
- ImportService is an `actor` conforming to `ImportServiceProtocol`
- NO per-set PR pipeline during import (AGENT_RULES Section 9)
- Store metric only (Weight (kg) column). Ignore Weight (lbs).
- trackingType is IMMUTABLE once an exercise has sets
- effectiveWeight = weight + (closestBodyweight × exercise.bodyweightFactor)
- Integer grams comparison for weight (but only relevant for PR pipeline, which we skip)

**Existing code to understand before implementing**:
- `Reppo/Core/Services/ServiceContainer.swift` — how services are wired (follow same pattern)
- `Reppo/Core/Services/SettingsService.swift` — actor service pattern to follow
- `Reppo/Data/Models/Workout.swift` — Workout model properties and init
- `Reppo/Data/Models/Exercise.swift` — Exercise model properties and init
- `Reppo/Data/Models/WorkoutSet.swift` — WorkoutSet model properties and init
- `Reppo/Data/Enums/TrackingType.swift` — TrackingType enum values
- `Reppo/Data/Enums/SetType.swift` — SetType enum values
- `Reppo/Data/Enums/WorkoutStatus.swift` — WorkoutStatus enum values
- `Reppo/Core/Services/Protocols/WorkoutRepositoryProtocol.swift` (or similar) — repository methods available
- `Reppo/Core/Services/Protocols/ExerciseRepositoryProtocol.swift` — exercise lookup/creation methods
- `Reppo/Core/Services/PRService.swift` — rebuildAll() method signature
- `Reppo/Core/Services/StatsService.swift` — rebuildAll() method signature

**CRITICAL**: Read the existing repository protocols to understand what methods are available. You may need to add a method for case-insensitive exercise name lookup if one doesn't exist.

---

## Subtask T005: Create ImportService Actor Scaffold

**Purpose**: Set up the ImportService actor with all dependencies injected, conforming to ImportServiceProtocol.

**File**: `Reppo/Core/Services/ImportService.swift` (NEW)

**Steps**:

1. Create the actor with dependency injection:

```swift
import Foundation
import SwiftData

actor ImportService: ImportServiceProtocol {

    // MARK: - Dependencies
    private let exerciseRepo: any ExerciseRepositoryProtocol
    private let workoutRepo: any WorkoutRepositoryProtocol
    private let setRepo: any WorkoutSetRepositoryProtocol
    private let bodyweightRepo: any BodyweightEntryRepositoryProtocol
    private let healthProfileRepo: any HealthProfileRepositoryProtocol
    private let prService: any PRServiceProtocol
    private let statsService: any StatsServiceProtocol
    private let modelContainer: ModelContainer

    // MARK: - Constants
    private let batchSize = 500
    private let expectedHeaders = [
        "Date", "Exercise", "Category", "Weight (kg)", "Weight (lbs)",
        "Reps", "Distance", "Distance Unit", "Time", "Notes", "Kind"
    ]

    // MARK: - Date Parsing
    private let dateStyle = Date.ISO8601FormatStyle()
        .year()
        .month()
        .day()
        .dateSeparator(.dash)

    init(
        exerciseRepo: any ExerciseRepositoryProtocol,
        workoutRepo: any WorkoutRepositoryProtocol,
        setRepo: any WorkoutSetRepositoryProtocol,
        bodyweightRepo: any BodyweightEntryRepositoryProtocol,
        healthProfileRepo: any HealthProfileRepositoryProtocol,
        prService: any PRServiceProtocol,
        statsService: any StatsServiceProtocol,
        modelContainer: ModelContainer
    ) {
        self.exerciseRepo = exerciseRepo
        self.workoutRepo = workoutRepo
        self.setRepo = setRepo
        self.bodyweightRepo = bodyweightRepo
        self.healthProfileRepo = healthProfileRepo
        self.prService = prService
        self.statsService = statsService
        self.modelContainer = modelContainer
    }

    // MARK: - ImportServiceProtocol

    func previewCSV(data: Data) throws -> CSVParser.PreviewResult {
        try CSVParser.parsePreview(data: data)
    }

    func importCSV(data: Data) -> AsyncStream<ImportProgress> {
        AsyncStream { continuation in
            Task {
                await self.performImport(data: data, continuation: continuation)
            }
        }
    }

    // MARK: - Private Implementation

    private func performImport(data: Data, continuation: AsyncStream<ImportProgress>.Continuation) {
        // Implementation in subsequent subtasks
        continuation.finish()
    }
}
```

2. Verify the actor compiles with stub `performImport`.

**Note on ModelContainer**: Check if `RepositoryContainer` exposes `modelContainer`. If not, you may need to:
- Add `let modelContainer: ModelContainer` to RepositoryContainer, OR
- Pass ModelContainer separately to ServiceContainer, OR
- Access it from the app's environment

Look at how `RepositoryContainer` is initialized in the app to find the ModelContainer.

**Validation**:
- Actor compiles with all dependencies injected
- Conforms to ImportServiceProtocol
- previewCSV delegates to CSVParser

---

## Subtask T006: Implement CSV Header + Row Validation

**Purpose**: Validate the CSV header matches the expected 11 columns, and validate each row has required fields.

**Steps**:

1. Add header validation method:

```swift
private func validateHeader(_ headers: [String]) throws {
    // Normalize: trim whitespace from headers
    let normalized = headers.map { $0.trimmingCharacters(in: .whitespaces) }

    // Check column count
    guard normalized.count == expectedHeaders.count else {
        throw ImportError.invalidHeader(expected: expectedHeaders, got: normalized)
    }

    // Check column names match (case-insensitive)
    for (expected, actual) in zip(expectedHeaders, normalized) {
        guard expected.lowercased() == actual.lowercased() else {
            throw ImportError.invalidHeader(expected: expectedHeaders, got: normalized)
        }
    }
}
```

2. Add row validation method. Each row is a `[String]` array (field values in column order):

```swift
struct ValidatedRow {
    let date: Date
    let exerciseName: String
    let category: String?
    let weightKg: Double?
    let reps: Int?
    let distance: Double?
    let distanceUnit: String?
    let durationSeconds: Int?
    let notes: String?
    let kind: String?
}

private func validateRow(_ fields: [String], rowNumber: Int) -> Result<ValidatedRow, CSVParser.ValidationError> {
    // Must have correct field count
    guard fields.count == expectedHeaders.count else {
        return .failure(.init(rowNumber: rowNumber, reason: "Expected \(expectedHeaders.count) columns, found \(fields.count)"))
    }

    // Column 0: Date (REQUIRED)
    let dateStr = fields[0].trimmingCharacters(in: .whitespaces)
    guard !dateStr.isEmpty, let date = try? dateStyle.parse(dateStr) else {
        return .failure(.init(rowNumber: rowNumber, reason: "Invalid or missing date: '\(fields[0])'"))
    }

    // Column 1: Exercise (REQUIRED)
    let exerciseName = fields[1].trimmingCharacters(in: .whitespaces)
    guard !exerciseName.isEmpty else {
        return .failure(.init(rowNumber: rowNumber, reason: "Missing exercise name"))
    }

    // Column 2: Category (optional)
    let category = fields[2].trimmingCharacters(in: .whitespaces)

    // Column 3: Weight (kg) (optional)
    let weightStr = fields[3].trimmingCharacters(in: .whitespaces)
    let weightKg = weightStr.isEmpty ? nil : Double(weightStr)

    // Column 4: Weight (lbs) — IGNORED per FR-009

    // Column 5: Reps (optional)
    let repsStr = fields[5].trimmingCharacters(in: .whitespaces)
    let reps = repsStr.isEmpty ? nil : Int(repsStr)

    // Column 6: Distance (optional)
    let distStr = fields[6].trimmingCharacters(in: .whitespaces)
    let distance = distStr.isEmpty ? nil : Double(distStr)

    // Column 7: Distance Unit (optional)
    let distUnit = fields[7].trimmingCharacters(in: .whitespaces)

    // Column 8: Time (optional)
    let timeStr = fields[8].trimmingCharacters(in: .whitespaces)
    let duration = timeStr.isEmpty ? nil : Int(timeStr)

    // Column 9: Notes (optional)
    let notes = fields[9].trimmingCharacters(in: .whitespaces)

    // Column 10: Kind (optional)
    let kind = fields[10].trimmingCharacters(in: .whitespaces)

    // Must have at least one data value (FR-007 + edge case: "empty rows... skip")
    let hasWeight = weightKg != nil && weightKg! > 0
    let hasReps = reps != nil && reps! > 0
    let hasDuration = duration != nil && duration! > 0
    let hasDistance = distance != nil && distance! > 0
    let hasData = (hasWeight && hasReps) || hasDuration || hasDistance

    guard hasData else {
        return .failure(.init(rowNumber: rowNumber, reason: "Row has no data values (need weight+reps, duration, or distance)"))
    }

    return .success(ValidatedRow(
        date: date,
        exerciseName: exerciseName,
        category: category.isEmpty ? nil : category,
        weightKg: weightKg,
        reps: reps,
        distance: distance,
        distanceUnit: distUnit.isEmpty ? nil : distUnit,
        durationSeconds: duration,
        notes: notes.isEmpty ? nil : notes,
        kind: kind.isEmpty ? nil : kind
    ))
}
```

**Validation**:
- Header with wrong column count → throws ImportError.invalidHeader
- Row with empty Date → ValidationError
- Row with empty Exercise → ValidationError
- Row with only Notes and no data → ValidationError (skipped)
- Row with weight+reps → passes validation
- Row with duration only → passes validation

---

## Subtask T007: Implement Kind → trackingType Mapping + Exercise Defaults

**Purpose**: Map the CSV Kind column to Exercise.trackingType for NEW exercises, and define all default values for newly created exercises.

**Steps**:

1. Add Kind mapping method:

```swift
private func inferTrackingType(from kind: String?) -> TrackingType {
    switch kind?.lowercased() {
    case "wr":  return .weightReps
    case "d":   return .duration
    case "wd":  return .weightDistance
    case "wrd": return .weightRepsDuration
    default:    return .weightReps  // Default for unknown kinds
    }
}
```

2. Add exercise creation method:

```swift
private func createExercise(
    name: String,
    category: String?,
    kind: String?,
    in context: ModelContext
) -> Exercise {
    let exercise = Exercise(
        id: UUID(),
        name: name,
        equipmentType: .other,          // Per spec edge cases
        trackingType: inferTrackingType(from: kind),
        primaryMuscle: category,
        secondaryMuscles: [],
        movementPattern: nil,
        unilateral: false,
        bilateralLoadFactor: nil,
        bodyweightFactor: 0.0,          // No bodyweight contribution by default
        weightIncrement: nil,
        defaultRestTime: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
    context.insert(exercise)
    return exercise
}
```

**CRITICAL**: Check the existing `Exercise` model init to match the exact parameter names and order. The example above is a guide — adapt to the actual model.

**CRITICAL**: trackingType inference from Kind ONLY applies to NEWLY CREATED exercises. If an exercise already exists, keep its existing trackingType (it's immutable once sets exist).

**Validation**:
- `"wr"` → `.weightReps`
- `"d"` → `.duration`
- `"wd"` → `.weightDistance`
- `"wrd"` → `.weightRepsDuration`
- `nil` → `.weightReps`
- `"unknown"` → `.weightReps`
- New exercise has `equipmentType = .other`, `bodyweightFactor = 0.0`

---

## Subtask T008: Implement Exercise Matching + Workout Grouping

**Purpose**: Match CSV exercise names to existing exercises (case-insensitive), and group validated rows by date to create Workouts.

**Steps**:

1. Add exercise lookup logic. Check if ExerciseRepository has a case-insensitive fetch method. If not, fetch all exercises and build a local lookup dictionary:

```swift
private func buildExerciseLookup() async throws -> [String: Exercise] {
    let allExercises = try await exerciseRepo.fetchAll()
    var lookup: [String: Exercise] = [:]
    for exercise in allExercises {
        lookup[exercise.name.lowercased()] = exercise
    }
    return lookup
}
```

2. Add workout grouping:

```swift
private func groupByDate(_ rows: [ValidatedRow]) -> [(date: Date, rows: [ValidatedRow])] {
    var groups: [Date: [ValidatedRow]] = [:]
    for row in rows {
        // Normalize to start of day
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: row.date)
        groups[dayStart, default: []].append(row)
    }
    // Sort by date ascending
    return groups.sorted { $0.key < $1.key }.map { (date: $0.key, rows: $0.value) }
}
```

3. Add workout creation check — if a workout already exists for that date, use it (don't duplicate):

```swift
private func findOrCreateWorkout(for date: Date, in context: ModelContext, existingWorkouts: inout [Date: Workout]) -> Workout {
    if let existing = existingWorkouts[date] {
        return existing
    }
    let workout = Workout(
        id: UUID(),
        date: date,
        status: .completed,  // Historical data
        createdAt: Date(),
        updatedAt: Date()
    )
    context.insert(workout)
    existingWorkouts[date] = workout
    return workout
}
```

**CRITICAL**: Adapt to the actual Workout init signature. Check existing Workout model for required parameters.

**CRITICAL**: Also check if workouts already exist for those dates (from previous imports or manual entries). Use `WorkoutRepository` to fetch existing workouts for the date range.

**Validation**:
- 10 rows with 3 unique dates → 3 date groups
- Exercise "Barbell Squat" matches existing "barbell squat" (case-insensitive)
- Unknown exercise "Cable Fly" creates new exercise with defaults

---

## Subtask T009: Implement Chunked Batch Insert + Progress Reporting

**Purpose**: Insert WorkoutSets in chunks with effectiveWeight/e1RM computation, reporting progress via AsyncStream.

**Steps**:

1. Implement the core `performImport` method:

```swift
private func performImport(data: Data, continuation: AsyncStream<ImportProgress>.Continuation) {
    let startTime = Date()

    do {
        // Phase 1: Parse
        continuation.yield(.parsing)
        let parseResult = try CSVParser.parse(data: data)
        try validateHeader(parseResult.headers)

        // Phase 2: Validate rows
        var validRows: [ValidatedRow] = []
        var errors: [CSVParser.ValidationError] = []

        for (index, row) in parseResult.rows.enumerated() {
            continuation.yield(.validating(processed: index + 1, total: parseResult.totalRows))

            switch validateRow(row, rowNumber: index + 2) {  // +2: 1-based + header
            case .success(let validated):
                validRows.append(validated)
            case .failure(let error):
                errors.append(error)
            }
        }

        guard !validRows.isEmpty else {
            continuation.yield(.failed(.noValidRows))
            continuation.finish()
            return
        }

        // Phase 3: Group and insert
        let dateGroups = groupByDate(validRows)
        var exerciseLookup = try await buildExerciseLookup()

        // Fetch closest bodyweight for effectiveWeight computation
        let closestBodyweight = try await bodyweightRepo.fetchLatest()?.weightKg ?? 0.0
        let healthProfile = try await healthProfileRepo.fetchOrCreate()

        // Create a background ModelContext for batch inserts
        let context = ModelContext(modelContainer)
        context.autosave = false

        var setsInserted = 0
        var workoutsCreated = 0
        var exercisesCreated = 0
        var existingWorkouts: [Date: Workout] = [:]
        let totalSets = validRows.count

        // Fetch existing workouts for the date range to avoid duplicates
        // (Adapt this to your WorkoutRepository API)

        for group in dateGroups {
            let workout = findOrCreateWorkout(for: group.date, in: context, existingWorkouts: &existingWorkouts)
            if existingWorkouts.count == workoutsCreated + 1 {
                // New workout was just created
                workoutsCreated += 1  // Only count if we actually created it vs found existing
            }

            var orderInWorkout = 0
            var exerciseOrderCounters: [String: Int] = [:]

            for row in group.rows {
                let lookupKey = row.exerciseName.lowercased()

                // Match or create exercise
                let exercise: Exercise
                if let existing = exerciseLookup[lookupKey] {
                    exercise = existing
                } else {
                    exercise = createExercise(
                        name: row.exerciseName,
                        category: row.category,
                        kind: row.kind,
                        in: context
                    )
                    exerciseLookup[lookupKey] = exercise
                    exercisesCreated += 1
                }

                // Compute effectiveWeight
                let weight = row.weightKg
                let effectiveWeight: Double?
                if let w = weight {
                    effectiveWeight = w + (closestBodyweight * exercise.bodyweightFactor)
                } else {
                    effectiveWeight = nil
                }

                // Compute e1RM (if weight and reps available)
                let e1RM: Double?
                if let w = effectiveWeight, w > 0, let r = row.reps, r > 0, r > 1 {
                    // Epley formula: weight * (1 + reps/30)
                    e1RM = w * (1.0 + Double(r) / 30.0)
                } else if let w = effectiveWeight, let r = row.reps, r == 1 {
                    e1RM = w  // 1RM is the weight itself
                } else {
                    e1RM = nil
                }

                // Handle distance unit conversion
                var distanceMeters = row.distance
                if let dist = distanceMeters, let unit = row.distanceUnit?.lowercased() {
                    if unit == "mi" || unit == "miles" {
                        distanceMeters = dist * 1609.34
                    }
                    // Otherwise assume meters
                }

                // Track order within exercise for this workout
                let exerciseKey = exercise.id.uuidString
                let orderInExercise = exerciseOrderCounters[exerciseKey, default: 0]
                exerciseOrderCounters[exerciseKey] = orderInExercise + 1

                // Create WorkoutSet
                let workoutSet = WorkoutSet(
                    // ... adapt to actual init
                    id: UUID(),
                    workoutId: workout.id,
                    exerciseId: exercise.id,
                    date: row.date,
                    weight: row.weightKg,
                    effectiveWeight: effectiveWeight,
                    reps: row.reps,
                    durationSeconds: row.durationSeconds,
                    distanceMeters: distanceMeters,
                    e1RM: e1RM,
                    e1RMFormulaVersion: healthProfile.e1RMFormula,
                    setType: .working,      // ALL imported sets = working (FR-005)
                    notes: row.notes,
                    orderInWorkout: orderInWorkout,
                    orderInExercise: orderInExercise,
                    completed: true,         // Historical data
                    cachedPRStatus: nil,     // Set by PRService.rebuildAll()
                    createdAt: Date(),
                    updatedAt: Date()
                )
                context.insert(workoutSet)
                orderInWorkout += 1
                setsInserted += 1

                // Batch save
                if setsInserted % batchSize == 0 {
                    try context.save()
                    continuation.yield(.importing(inserted: setsInserted, total: totalSets))
                }
            }
        }

        // Final save for remaining records
        try context.save()
        continuation.yield(.importing(inserted: setsInserted, total: totalSets))

        // Phase 4: Rebuild
        continuation.yield(.rebuilding(phase: .stats))
        try await statsService.rebuildAll()

        continuation.yield(.rebuilding(phase: .prs))
        try await prService.rebuildAll()

        // Done
        let result = ImportResult(
            setsImported: setsInserted,
            workoutsCreated: workoutsCreated,
            exercisesCreated: exercisesCreated,
            rowsSkipped: errors.count,
            errors: errors,
            duration: Date().timeIntervalSince(startTime)
        )
        continuation.yield(.completed(result))
        continuation.finish()

    } catch let error as ImportError {
        continuation.yield(.failed(error))
        continuation.finish()
    } catch {
        continuation.yield(.failed(.insertFailed(error.localizedDescription)))
        continuation.finish()
    }
}
```

**CRITICAL NOTES**:
- The code above is a GUIDE. You MUST adapt to the actual model init signatures by reading the model files first.
- WorkoutSet init likely has different parameter names/order. Read `WorkoutSet.swift` carefully.
- The `fetchLatest()` on bodyweightRepo may not exist — check the actual repository protocol and adapt.
- e1RM formula: check what `healthProfile.e1RMFormula` returns and use the correct formula. The E1RMFormula enum from feature 010 may have a `calculate(weight:reps:)` method.
- If workoutId/exerciseId are relationships (not UUID fields), adapt accordingly. SwiftData may use object references instead of UUID foreign keys.

**Validation**:
- 100-row CSV → 100 WorkoutSets created
- 3 unique dates → 3 Workouts (status: .completed)
- Known exercise "Barbell Squat" matched (not duplicated)
- Unknown exercise created with trackingType from Kind, equipmentType: .other
- All sets have setType: .working
- Progress stream yields: .parsing → .validating → .importing → .rebuilding(.stats) → .rebuilding(.prs) → .completed

---

## Subtask T010: Wire ImportService into ServiceContainer

**Purpose**: Register ImportService in the app's service container so it's available for injection into ViewModels.

**File**: `Reppo/Core/Services/ServiceContainer.swift` (MODIFY)

**Steps**:

1. Add property:
```swift
let importService: any ImportServiceProtocol
```

2. Add initialization (after prService and statsService are initialized, since ImportService depends on both):

```swift
self.importService = ImportService(
    exerciseRepo: repos.exerciseRepository,
    workoutRepo: repos.workoutRepository,
    setRepo: repos.workoutSetRepository,
    bodyweightRepo: repos.bodyweightEntryRepository,
    healthProfileRepo: repos.healthProfileRepository,
    prService: self.prService,
    statsService: self.statsService,
    modelContainer: repos.modelContainer  // Check if this is accessible
)
```

**CRITICAL**: Verify how `RepositoryContainer` is structured. You may need to:
- Expose `modelContainer` from RepositoryContainer if not already public
- Or pass it separately from the app's initialization

3. Verify ServiceContainer compiles without circular dependencies.

**Validation**:
- ServiceContainer initializes without errors
- ImportService is accessible as `serviceContainer.importService`
- No circular dependency introduced

---

## Definition of Done

- [ ] ImportService actor compiles and conforms to ImportServiceProtocol
- [ ] Header validation rejects wrong column count or names
- [ ] Row validation skips rows missing Date, Exercise, or all data values
- [ ] Kind column correctly maps to Exercise.trackingType for new exercises
- [ ] Existing exercises matched case-insensitively (no duplicates)
- [ ] New exercises created with correct defaults (equipmentType: .other, bodyweightFactor: 0.0)
- [ ] WorkoutSets created with setType: .working, completed: true, cachedPRStatus: nil
- [ ] effectiveWeight and e1RM computed correctly
- [ ] Chunked batch inserts (500 per batch)
- [ ] AsyncStream yields progress at each phase
- [ ] StatsService.rebuildAll() called after insert
- [ ] PRService.rebuildAll() called after insert
- [ ] Wired into ServiceContainer
- [ ] Project builds with no errors

## Risks & Edge Cases

| Risk | Mitigation |
|------|-----------|
| WorkoutSet init signature mismatch | Read WorkoutSet.swift FIRST, adapt code to match |
| ModelContainer not accessible from RepositoryContainer | Check RepositoryContainer, add property if needed |
| Exercise with same name but different Kind across rows | Use FIRST occurrence for trackingType (immutable after creation) |
| Existing workout for an import date | Check existing workouts and reuse, don't duplicate |
| No bodyweight entry exists | effectiveWeight = weight (bodyweightFactor * 0 = 0) |
| e1RM formula mismatch | Use E1RMFormula enum's calculate() method if available |
| SwiftData background context propagation | iOS 17.2+ should be fine; test on 17.0 if targeting |

## Reviewer Guidance

- Verify ALL model init calls match the actual Swift model signatures (this is the #1 failure mode)
- Verify Kind → trackingType mapping matches data-model.md table
- Verify setType is ALWAYS .working for imported sets (FR-005)
- Verify NO per-set PR pipeline calls (no PRService.evaluate() calls)
- Verify StatsService.rebuildAll() and PRService.rebuildAll() are called AFTER all inserts
- Verify case-insensitive exercise matching
- Check that Weight (lbs) column (index 4) is completely ignored

## Activity Log

- 2026-03-01T09:24:19Z – claude-opus – shell_pid=90948 – lane=doing – Started implementation via workflow command
- 2026-03-01T10:41:43Z – claude-opus – shell_pid=90948 – lane=done – Already reviewed and approved in earlier session
