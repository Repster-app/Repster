# Data Model & Contracts: CSV Import + Export

**Feature**: 011-csv-import-export | **Date**: 2026-03-01

## Schema Changes

**None.** This feature uses existing models only:
- `Workout` — one per unique CSV date
- `Exercise` — created for unknown names, matched for existing
- `WorkoutSet` — one per CSV row
- `ExerciseStats` — rebuilt by `StatsService.rebuildAll()`
- `PerformanceRecord` — rebuilt by `PRService.rebuildAll()`

No new `@Model` classes. No modifications to existing model properties.

## New Types

### CSVParser (struct)

**File**: `Reppo/Core/Utilities/CSVParser.swift`

```swift
struct CSVParser {
    struct ParseResult {
        let headers: [String]
        let rows: [[String]]
        let totalRows: Int
    }

    struct PreviewResult {
        let headers: [String]
        let sampleRows: [[String]]     // First N rows
        let estimatedTotalRows: Int
    }

    struct ValidationError: Identifiable, Sendable {
        let id = UUID()
        let rowNumber: Int
        let reason: String
        let rawLine: String?
    }

    // Full parse
    static func parse(data: Data, encoding: String.Encoding = .utf8) throws -> ParseResult

    // Preview (first N rows + line count estimate)
    static func parsePreview(data: Data, maxRows: Int = 5) throws -> PreviewResult
}
```

### ImportProgress (enum)

**File**: `Reppo/Core/Services/ImportService.swift` (nested or in own file)

```swift
enum ImportProgress: Sendable {
    case parsing
    case validating(processed: Int, total: Int)
    case importing(inserted: Int, total: Int)
    case rebuilding(phase: RebuildPhase)
    case completed(ImportResult)
    case failed(ImportError)

    enum RebuildPhase: Sendable {
        case stats
        case prs
    }
}
```

### ImportResult (struct)

```swift
struct ImportResult: Sendable {
    let setsImported: Int
    let workoutsCreated: Int
    let exercisesCreated: Int
    let rowsSkipped: Int
    let errors: [CSVParser.ValidationError]
    let duration: TimeInterval
}
```

### ImportError (enum)

```swift
enum ImportError: Error, LocalizedError, Sendable {
    case fileReadFailed(String)
    case invalidEncoding
    case invalidHeader(expected: [String], got: [String])
    case noValidRows
    case insertFailed(String)
    case cancelled

    var errorDescription: String? { ... }
}
```

### CSVFile (Transferable, for export)

**File**: `Reppo/Features/Settings/Views/ExportView.swift` (local to view)

```swift
struct CSVFile: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { csv in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(csv.filename)
            try csv.data.write(to: url)
            return SentTransferredFile(url)
        }
        ProxyRepresentation { csv in csv.data }  // iOS 17 Files app fallback
    }
}
```

## Service Contracts

### ImportServiceProtocol

**File**: `Reppo/Core/Services/Protocols/ImportServiceProtocol.swift`

```swift
protocol ImportServiceProtocol: Sendable {

    // MARK: - Preview
    /// Parse first N rows for preview display. Does NOT modify any data.
    func previewCSV(data: Data) throws -> CSVParser.PreviewResult

    // MARK: - Import
    /// Run full import. Returns an AsyncStream of progress updates.
    /// Caller must consume the stream to completion.
    func importCSV(data: Data) -> AsyncStream<ImportProgress>
}
```

### ExportServiceProtocol

**File**: `Reppo/Core/Services/Protocols/ExportServiceProtocol.swift`

```swift
protocol ExportServiceProtocol: Sendable {

    // MARK: - Export
    /// Generate CSV data for all workouts/exercises/sets.
    func exportCSV() async throws -> Data
}
```

### ImportService (actor)

**File**: `Reppo/Core/Services/ImportService.swift`

```swift
actor ImportService: ImportServiceProtocol {

    // Dependencies (injected)
    private let workoutRepo: any WorkoutRepositoryProtocol
    private let exerciseRepo: any ExerciseRepositoryProtocol
    private let setRepo: any WorkoutSetRepositoryProtocol
    private let bodyweightRepo: any BodyweightEntryRepositoryProtocol
    private let healthProfileRepo: any HealthProfileRepositoryProtocol
    private let prService: any PRServiceProtocol
    private let statsService: any StatsServiceProtocol
    private let modelContainer: ModelContainer  // For @ModelActor batch inserts

    init(
        workoutRepo: any WorkoutRepositoryProtocol,
        exerciseRepo: any ExerciseRepositoryProtocol,
        setRepo: any WorkoutSetRepositoryProtocol,
        bodyweightRepo: any BodyweightEntryRepositoryProtocol,
        healthProfileRepo: any HealthProfileRepositoryProtocol,
        prService: any PRServiceProtocol,
        statsService: any StatsServiceProtocol,
        modelContainer: ModelContainer
    )
}
```

### ExportService (actor)

**File**: `Reppo/Core/Services/ExportService.swift`

```swift
actor ExportService: ExportServiceProtocol {

    // Dependencies (injected)
    private let workoutRepo: any WorkoutRepositoryProtocol
    private let exerciseRepo: any ExerciseRepositoryProtocol
    private let setRepo: any WorkoutSetRepositoryProtocol

    init(
        workoutRepo: any WorkoutRepositoryProtocol,
        exerciseRepo: any ExerciseRepositoryProtocol,
        setRepo: any WorkoutSetRepositoryProtocol
    )
}
```

## CSV Column Mapping

### Import Mapping (CSV → SwiftData)

| # | CSV Column | Target | Type | Required | Notes |
|---|-----------|--------|------|----------|-------|
| 0 | Date | `Workout.date`, `WorkoutSet.date` | Date | YES | Format: "yyyy-MM-dd". Group by date → one Workout per unique date. |
| 1 | Exercise | `Exercise.name` | String | YES | Case-insensitive match. Create if not exists. |
| 2 | Category | `Exercise.primaryMuscle` | String? | NO | Only set on newly created exercises. |
| 3 | Weight (kg) | `WorkoutSet.weight` | Double? | NO | Stored as-is (metric). |
| 4 | Weight (lbs) | IGNORED | — | — | Derived value, not authoritative. |
| 5 | Reps | `WorkoutSet.reps` | Int? | NO | |
| 6 | Distance | `WorkoutSet.distanceMeters` | Double? | NO | |
| 7 | Distance Unit | Used for conversion | String? | NO | If "mi" or "miles", convert distance to meters. Otherwise assume meters. |
| 8 | Time | `WorkoutSet.durationSeconds` | Int? | NO | Parse as seconds. |
| 9 | Notes | `WorkoutSet.notes` | String? | NO | May contain commas (quoted field). |
| 10 | Kind | `Exercise.trackingType` (inferred) | String? | NO | See Kind Mapping Table below. |

### Kind → trackingType Mapping

| Kind Value | Meaning | Inferred `Exercise.trackingType` |
|------------|---------|----------------------------------|
| `wr` | Weight + Reps | `.weightReps` |
| `d` | Duration only | `.duration` |
| `wd` | Weight + Distance | `.weightDistance` |
| `wrd` | Weight + Reps + Duration | `.weightRepsDuration` |
| (empty/unknown) | Default | `.weightReps` |

**Rules**:
- Kind infers `Exercise.trackingType` — NOT `WorkoutSet.setType`
- ALL imported sets get `setType = .working` regardless of Kind
- If same exercise has multiple Kind values across rows, use the FIRST occurrence (trackingType is immutable once sets exist)
- Only applies to newly created exercises. Existing exercises keep their trackingType.

### Export Mapping (SwiftData → CSV)

Output header: `Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind`

| # | CSV Column | Source | Notes |
|---|-----------|--------|-------|
| 0 | Date | `WorkoutSet.date` | Format: "yyyy-MM-dd" |
| 1 | Exercise | `Exercise.name` | Via exercise relationship |
| 2 | Category | `Exercise.primaryMuscle` | Empty string if nil |
| 3 | Weight (kg) | `WorkoutSet.weight` | Empty if nil |
| 4 | Weight (lbs) | Computed: `weight * 2.20462` | Empty if weight is nil |
| 5 | Reps | `WorkoutSet.reps` | Empty if nil |
| 6 | Distance | `WorkoutSet.distanceMeters` | Empty if nil |
| 7 | Distance Unit | `"m"` if distanceMeters present | Empty otherwise |
| 8 | Time | `WorkoutSet.durationSeconds` | Empty if nil |
| 9 | Notes | `WorkoutSet.notes` | Quoted if contains commas |
| 10 | Kind | Reverse-map from `Exercise.trackingType` | `weightReps` → `wr`, etc. |

## Defaults for Newly Created Exercises

When the import encounters an exercise name not in the database:

| Property | Default Value | Notes |
|----------|---------------|-------|
| `name` | From CSV `Exercise` column | Exact string (trimmed) |
| `trackingType` | Inferred from Kind column | See mapping table above |
| `equipmentType` | `.other` | Per spec edge cases |
| `primaryMuscle` | From CSV `Category` column | nil if empty |
| `secondaryMuscles` | `[]` | |
| `movementPattern` | `nil` | |
| `unilateral` | `false` | |
| `bilateralLoadFactor` | `nil` | |
| `bodyweightFactor` | `0.0` | No bodyweight contribution by default |
| `weightIncrement` | `nil` | |
| `defaultRestTime` | `nil` | |

## Defaults for Imported WorkoutSets

| Property | Value | Notes |
|----------|-------|-------|
| `setType` | `.working` | ALL imported sets, regardless of Kind |
| `completed` | `true` | Historical data — already performed |
| `effectiveWeight` | `weight + (bodyweight × exercise.bodyweightFactor)` | For bodyweightFactor=0 (default), effectiveWeight = weight |
| `e1RM` | Computed: Epley formula from weight+reps | Only if weight > 0 and reps > 0 |
| `e1RMFormulaVersion` | Current formula from HealthProfile | |
| `orderInWorkout` | Sequential per date | Assigned during grouping |
| `orderInExercise` | Sequential per exercise within date | Assigned during grouping |
| `cachedPRStatus` | `nil` | Set by PRService.rebuildAll() after import |
| `excludeFromPRs` | `nil` (false) | |
| `rpe` / `rir` | `nil` | Not in CSV |
| `side` | `nil` | Not in CSV |
| `supersetGroupId` | `nil` | Not in CSV |
| `startedAt` / `completedAt` | `nil` | Not in CSV |
| `pauseDuration` | `nil` | Not in CSV |

## Defaults for Imported Workouts

| Property | Value | Notes |
|----------|-------|-------|
| `date` | From CSV Date column | One workout per unique date |
| `status` | `.completed` | Historical data |
| `startTime` | `nil` | Not in CSV |
| `endTime` | `nil` | Not in CSV |
| `duration` | `nil` | Not in CSV |
| `perceivedEffort` | `nil` | Not in CSV |
| `notes` | `nil` | Not in CSV |
| `programId` | `nil` | Not in CSV |

## Import Algorithm (Pseudocode)

```
1. READ file data (security-scoped)
2. PARSE CSV via CSVParser → headers + rows
3. VALIDATE header matches expected 11 columns
4. FOR EACH row:
   a. VALIDATE required fields (Date, Exercise non-empty)
   b. VALIDATE at least one data value (weight+reps, duration, or distance)
   c. SKIP invalid rows → collect in error list
5. GROUP valid rows by Date → { Date: [Row] }
6. FETCH all existing exercises (name → Exercise lookup, case-insensitive)
7. FETCH closest bodyweight entry (for effectiveWeight)
8. FETCH HealthProfile (for e1RM formula)
9. FOR EACH date group (chunked):
   a. CREATE Workout if not exists for that date
   b. FOR EACH row in group:
      i.   MATCH or CREATE Exercise (case-insensitive name)
      ii.  For new exercise: set trackingType from Kind, equipmentType=.other
      iii. CREATE WorkoutSet with mapped fields + defaults
      iv.  COMPUTE effectiveWeight, e1RM
      v.   ASSIGN orderInWorkout, orderInExercise
   c. SAVE batch (every ~500 sets)
   d. YIELD progress
10. RUN StatsService.rebuildAll()
11. RUN PRService.rebuildAll()
12. YIELD completed result
```

## ServiceContainer Wiring

Add to `Reppo/Core/Services/ServiceContainer.swift`:

```swift
let importService: any ImportServiceProtocol
let exportService: any ExportServiceProtocol
```

Initialize after existing services:

```swift
self.importService = ImportService(
    workoutRepo: repos.workoutRepository,
    exerciseRepo: repos.exerciseRepository,
    setRepo: repos.workoutSetRepository,
    bodyweightRepo: repos.bodyweightEntryRepository,
    healthProfileRepo: repos.healthProfileRepository,
    prService: self.prService,
    statsService: self.statsService,
    modelContainer: repos.modelContainer  // Need to expose ModelContainer from RepositoryContainer
)

self.exportService = ExportService(
    workoutRepo: repos.workoutRepository,
    exerciseRepo: repos.exerciseRepository,
    setRepo: repos.workoutSetRepository
)
```

**Note**: `RepositoryContainer` may need to expose `modelContainer` for the `@ModelActor` pattern. Check existing code — if `modelContainer` is not publicly accessible, add a property.
