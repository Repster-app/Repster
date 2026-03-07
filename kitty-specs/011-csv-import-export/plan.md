# Implementation Plan: CSV Import + Export

**Branch**: `011-csv-import-export` | **Date**: 2026-03-01 | **Spec**: `kitty-specs/011-csv-import-export/spec.md`
**Input**: Feature specification from `kitty-specs/011-csv-import-export/spec.md`

## Summary

Build CSV import and export for the workout app. Import parses a fixed 11-column CSV from a competitor app (~12,000 rows), groups rows by date into Workouts, creates Exercises for unknown names, maps fields to WorkoutSets, then runs bulk `StatsService.rebuildAll()` + `PRService.rebuildAll()` (no per-set PR pipeline). The Kind column infers `Exercise.trackingType` (e.g. `"wr"` → `.weightReps`); all imported sets default to `setType = .working`. Export generates CSV of all data and shares via share sheet. Both are accessible from Settings → DATA section. A preview screen shows data mapping before committing. Progress indicator for large imports. Hand-rolled RFC 4180 CSV parser — no third-party dependencies.

## Technical Context

**Language/Version**: Swift (latest stable), iOS 17.0+
**Primary Dependencies**: SwiftUI, SwiftData, UniformTypeIdentifiers (for `.fileImporter` / `ShareLink`)
**Storage**: SwiftData — creates Workout, Exercise, WorkoutSet records; triggers rebuild of ExerciseStats + PerformanceRecord
**Testing**: Manual testing for v1 (per constitution)
**Target Platform**: iOS 17.0+, iPhone only
**Project Type**: Mobile (single platform)
**Performance Goals**: Import 12,000 rows within 60 seconds (SC-001), export round-trips with no data loss (SC-004)
**Constraints**: Dark mode only, no third-party libs, MVVM architecture, no per-set PR pipeline during import, store metric only
**Scale/Scope**: ~12,000 CSV rows → ~12,000 WorkoutSets, ~300-500 unique dates (Workouts), ~50-100 unique exercises

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| SwiftUI primary, UIKit only if needed | PASS | All views in SwiftUI. `.fileImporter` (SwiftUI native) for document picker. `ShareLink` (SwiftUI native) for export sharing. |
| MVVM: View → ViewModel → Service → Repository → SwiftData | PASS | ImportView → ImportViewModel → ImportService → WorkoutRepository/ExerciseRepository/SetRepository |
| @Observable for ViewModels (not ObservableObject) | PASS | ImportViewModel and ExportViewModel use @Observable |
| No third-party UI libraries | PASS | Hand-rolled CSV parser, all native frameworks |
| No ModelContext in ViewModel | PASS | All data access via ImportService/ExportService which use Repositories |
| NavigationStack (not NavigationView) | PASS | Settings already uses NavigationStack; import/export are pushed views or sheets |
| Dark mode only | PASS | All colors from DesignTokens.swift |
| Database aggregation over Swift iteration | N/A | Import is a write-heavy operation. Post-import rebuild uses existing StatsService/PRService which already use DB aggregation. |
| Do not invent schema | PASS | No new models or schema changes. Uses existing Workout, Exercise, WorkoutSet, ExerciseStats, PerformanceRecord. |
| SF Symbols for icons | PASS | Import uses `square.and.arrow.down`, Export uses `square.and.arrow.up` (already stubbed in Settings) |
| Minimum 44x44pt tap targets | PASS | Buttons and list rows meet minimum |
| Store metric, convert in UI | PASS | Import reads `Weight (kg)` column only, ignores `Weight (lbs)`. Export outputs kg. |
| No startup rebuild (constitution) | PASS | Rebuild triggered explicitly after import completes, not at startup. |
| No per-set PR pipeline during import (AGENT_RULES S9) | PASS | Import all sets first → StatsService.rebuildAll() → PRService.rebuildAll() |
| trackingType immutable once sets exist | PASS | ImportService checks existing exercises before setting trackingType. Only sets trackingType on newly created exercises. |

**Post-Phase 1 re-check**: No violations. ImportService is a new service that orchestrates bulk writes through existing repositories and delegates rebuild to existing PRService/StatsService. CSVParser is a pure utility with no SwiftData dependency. ExportService queries via repositories and formats output — no business logic.

## Project Structure

### Documentation (this feature)

```
kitty-specs/011-csv-import-export/
├── plan.md              # This file
├── research.md          # Phase 0 output — CSV parsing, file picker patterns, batch insert strategies
├── data-model.md        # Phase 1 output — ImportService/ExportService contracts, CSV mapping, Kind mapping table
├── quickstart.md        # Phase 1 output — file structure, verification checklist
└── tasks.md             # Phase 2 output (NOT created by /spec-kitty.plan)
```

### Source Code (repository root)

```
Reppo/
├── Core/
│   ├── Services/
│   │   ├── ImportService.swift                  # NEW: CSV import orchestration, bulk insert, rebuild trigger
│   │   ├── ExportService.swift                  # NEW: CSV export generation
│   │   └── Protocols/
│   │       ├── ImportServiceProtocol.swift       # NEW: protocol
│   │       └── ExportServiceProtocol.swift       # NEW: protocol
│   │
│   ├── Utilities/
│   │   └── CSVParser.swift                      # NEW: RFC 4180 parser (pure Swift, no dependencies)
│   │
│   └── ServiceContainer.swift                   # MODIFY: add importService + exportService
│
├── Features/
│   └── Settings/
│       ├── Views/
│       │   ├── SettingsView.swift                # MODIFY: replace "Coming Soon" stubs with real navigation
│       │   ├── ImportView.swift                  # NEW: file picker + preview + progress + results
│       │   └── ExportView.swift                  # NEW: export trigger + share sheet
│       └── ViewModels/
│           ├── ImportViewModel.swift             # NEW: @Observable, import state machine
│           └── ExportViewModel.swift             # NEW: @Observable, export state
│
├── Features/
│   └── Onboarding/
│       └── Views/
│           └── ImportStepView.swift              # NO CHANGES — keep stub per Engineering Alignment decision #11
│
└── Reppo.xcodeproj/
    └── project.pbxproj                          # MODIFY: add all new file references
```

**Structure Decision**: ImportService and ExportService follow the existing `actor XxxService: XxxServiceProtocol` convention in `Core/Services/`. CSVParser is a standalone utility in `Core/Utilities/` — pure parsing, no SwiftData dependency. Import/Export UI lives under `Features/Settings/` since both are accessed from the Settings DATA section.

## Engineering Alignment (Planning Decisions)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | CSV parsing | Hand-rolled RFC 4180 parser | No third-party deps (constitution). Fixed column format is well-known. Must handle quoted fields (Notes column may contain commas). |
| 2 | Kind → trackingType mapping | `"wr"` → `.weightReps`, `"d"` → `.duration`, `"wd"` → `.weightDistance`, `"wrd"` → `.weightRepsDuration`, unknown → `.weightReps` | Per FR-005: Kind infers Exercise.trackingType, NOT Set.setType. All imported sets get `setType = .working`. |
| 3 | File picker | SwiftUI `.fileImporter(isPresented:allowedContentTypes:)` | Native SwiftUI API, no UIKit wrapper needed. `UTType.commaSeparatedText` for CSV. |
| 4 | Share sheet | SwiftUI `ShareLink` | Native SwiftUI, simpler than `UIActivityViewController` wrapper. Shares a temporary CSV file URL. |
| 5 | Batch insert strategy | Chunked inserts (500 rows per batch) with `ModelContext.save()` per chunk | Prevents memory spikes with 12k rows. Allows progress reporting between chunks. |
| 6 | Progress reporting | `ImportViewModel` observes `ImportService` progress via `AsyncStream<ImportProgress>` | Decouples service from UI. ViewModel updates `@Observable` properties from stream. |
| 7 | Import preview | Show first 5 rows + column mapping summary before committing | Per acceptance scenario 2. User sees data shape before actual import. Lightweight — parse header + 5 rows only. |
| 8 | Exercise matching | Case-insensitive name match via `ExerciseRepository` | Per edge case spec: "match existing exercises by name (case-insensitive)". |
| 9 | effectiveWeight computation | `weight + (closestBodyweight × exercise.bodyweightFactor)` | Per constitution. For most imported exercises (barbell/dumbbell), bodyweightFactor = 0, so effectiveWeight = weight. |
| 10 | Import state machine | idle → selecting → previewing → importing → rebuilding → completed/failed | Clear state transitions for UI. Each state shows appropriate UI (file picker, preview, progress bar, results). |
| 11 | Onboarding ImportStepView | Keep as informational stub pointing to Settings → Import | Onboarding runs before data exists. Import is a post-setup action. |

## Component Architecture

### CSVParser (struct, no dependencies)

```
Responsibilities:
├── parse(data: Data, encoding: String.Encoding) -> CSVParseResult
│   ├── Detects encoding (UTF-8 primary, fallback to Latin-1)
│   ├── RFC 4180: handles quoted fields, embedded commas, embedded newlines
│   └── Returns: header row + array of [String] rows (ImportService validates header column names)
│
├── parsePreview(data: Data, maxRows: Int) -> CSVPreviewResult
│   ├── Same parsing but stops after maxRows
│   └── Returns header + limited rows + total line count estimate
│
└── No SwiftData dependency — pure data transformation
```

### ImportService (actor)

```
Responsibilities:
├── importCSV(data: Data) -> AsyncStream<ImportProgress>
│   ├── 1. Parse CSV via CSVParser (caller reads file and passes Data)
│   ├── 3. Validate rows (reject malformed, collect errors)
│   ├── 4. Group valid rows by Date → Workout creation plan
│   ├── 5. Match/create Exercises (case-insensitive name lookup)
│   ├── 6. Bulk insert in chunks:
│   │   ├── Create Workouts (status: .completed)
│   │   ├── Create new Exercises (trackingType from Kind, equipmentType: .other)
│   │   ├── Create WorkoutSets (setType: .working, compute effectiveWeight)
│   │   └── Emit progress after each chunk
│   ├── 7. Run StatsService.rebuildAll()
│   ├── 8. Run PRService.rebuildAll()
│   └── 9. Emit final ImportResult (sets imported, workouts created, exercises created, errors)
│
├── previewCSV(data: Data) -> CSVPreviewResult
│   └── Parse header + first 5 rows for preview display
│
└── Dependencies (injected):
    ├── WorkoutRepository
    ├── ExerciseRepository
    ├── SetRepository (WorkoutSetRepository)
    ├── BodyweightEntryRepository (for effectiveWeight computation)
    ├── HealthProfileRepository (for bodyweightFactor lookup)
    ├── PRService (rebuildAll)
    └── StatsService (rebuildAll)
```

### ExportService (actor)

```
Responsibilities:
├── exportCSV() async throws -> Data
│   ├── 1. Fetch all WorkoutSets with related Workout + Exercise data
│   ├── 2. Sort by date ASC, then exercise name, then orderInWorkout
│   ├── 3. Format as CSV with header row matching import format
│   └── 4. Return UTF-8 encoded CSV Data (caller wraps in CSVFile Transferable for ShareLink)
│
└── Dependencies (injected):
    ├── WorkoutRepository
    ├── ExerciseRepository
    └── SetRepository
```

### ImportViewModel (@Observable)

```
Responsibilities:
├── state: ImportState = .idle           # State machine
├── previewData: CSVPreviewResult?       # First 5 rows for preview
├── progress: ImportProgress?            # Current progress during import
├── result: ImportResult?                # Final result (counts + errors)
├── errorMessage: String?               # User-facing error
│
├── selectFile()                         # Triggers .fileImporter
├── handleFileSelected(url: URL)         # Parse preview, transition to .previewing
├── confirmImport()                      # Start import, transition to .importing
├── cancel()                             # Reset to .idle
│
├── ImportState enum:
│   ├── idle        → Show "Select CSV File" button
│   ├── previewing  → Show preview table + "Import" / "Cancel"
│   ├── importing   → Show progress bar + counts
│   ├── rebuilding  → Show "Rebuilding stats..." indicator
│   ├── completed   → Show result summary
│   └── failed      → Show error + "Try Again"
│
└── Dependencies (injected):
    └── ImportService
```

### ExportViewModel (@Observable)

```
Responsibilities:
├── isExporting: Bool = false
├── exportData: Data?                    # For CSVFile Transferable + ShareLink
├── errorMessage: String?
│
├── generateExport()                    # Creates CSV, sets exportData
│
└── Dependencies (injected):
    └── ExportService
```

### View Hierarchy

```
Settings Tab (existing NavigationStack)
├── SettingsView
│   ├── DATA section
│   │   ├── "Import Data (CSV)" → NavigationLink { ImportView }
│   │   │   ├── State: .idle
│   │   │   │   └── [Select CSV File] button → .fileImporter sheet
│   │   │   ├── State: .previewing
│   │   │   │   ├── Column mapping summary (11 columns → field names)
│   │   │   │   ├── First 5 rows in a preview table
│   │   │   │   ├── Total row count
│   │   │   │   └── [Import] [Cancel] buttons
│   │   │   ├── State: .importing
│   │   │   │   ├── ProgressView (determinate: rowsProcessed / totalRows)
│   │   │   │   ├── "Processing row X of Y..."
│   │   │   │   └── Running counts (workouts, exercises, sets created)
│   │   │   ├── State: .rebuilding
│   │   │   │   └── "Rebuilding stats and PRs..." with indeterminate spinner
│   │   │   ├── State: .completed
│   │   │   │   ├── Summary card: sets imported, workouts created, exercises created
│   │   │   │   ├── Errors/skipped row count (if any)
│   │   │   │   └── [Done] button → dismiss
│   │   │   └── State: .failed
│   │   │       ├── Error message
│   │   │       └── [Try Again] [Cancel] buttons
│   │   │
│   │   ├── "Export Data (CSV)" → NavigationLink { ExportView }
│   │   │   ├── Export description text
│   │   │   ├── [Export] button → generates CSV
│   │   │   ├── ProgressView while generating
│   │   │   └── ShareLink(item: exportURL) when ready
│   │   │
│   │   └── "Rebuild Stats" → existing NavigationLink { RebuildStatsView }
```

### Data Flow

```
Import Flow:
  → User taps "Import Data (CSV)" in Settings
  → NavigationLink pushes ImportView
  → ImportViewModel.state = .idle
  → User taps "Select CSV File"
  → .fileImporter presents system file picker (UTType.commaSeparatedText)
  → User picks file → handleFileSelected(url:)
    → Read Data from URL (security-scoped access, store as Data)
    → ImportService.previewCSV(data:) → CSVParser.parsePreview()
    → state = .previewing, previewData populated
  → User reviews preview, taps "Import"
  → ImportViewModel.confirmImport()
    → ImportService.importCSV(data:) returns AsyncStream<ImportProgress>
    → state = .importing
    → ViewModel consumes stream, updates progress
    → Chunks: parse → validate → group by date → create Workouts → match/create Exercises → create WorkoutSets
    → state = .rebuilding
    → StatsService.rebuildAll() + PRService.rebuildAll()
    → state = .completed, result populated
  → User sees summary, taps "Done" → pops back to Settings

Export Flow:
  → User taps "Export Data (CSV)" in Settings
  → NavigationLink pushes ExportView
  → User taps "Export"
  → ExportViewModel.generateExport()
    → ExportService.exportCSV() → queries all data → returns CSV Data
    → exportData set → CSVFile Transferable wraps Data → ShareLink becomes active
  → User shares file via system share sheet
```

## Kind Column Mapping Table

The CSV `Kind` column maps to `Exercise.trackingType` inference (NOT `Set.setType`). All imported sets get `setType = .working` regardless of Kind value.

| Kind Value | Meaning | Inferred trackingType |
|------------|---------|----------------------|
| `wr` | Weight + Reps | `.weightReps` |
| `d` | Duration only | `.duration` |
| `wd` | Weight + Distance | `.weightDistance` |
| `wrd` | Weight + Reps + Duration | `.weightRepsDuration` |
| (empty/unknown) | Default | `.weightReps` |

**Note**: The competitor app's CSV appears to primarily contain `"wr"` rows based on the sample data. If unknown Kind values are encountered, default to `.weightReps` (the most common tracking type for strength training).

**Exercise-level inference**: If the same exercise appears with multiple Kind values across rows, use the FIRST occurrence to set trackingType (since trackingType is immutable once an exercise has sets).

## Import Validation Rules

| Rule | Action on Failure |
|------|-------------------|
| Header must contain all 11 expected columns | Reject entire file with clear error |
| Date column must parse to valid date | Skip row, add to error report |
| Exercise column must be non-empty | Skip row, add to error report |
| Weight (kg) must be valid number if present | Skip row, add to error report |
| Reps must be valid integer if present | Skip row, add to error report |
| Row must have at least one data value (weight+reps, duration, or distance) | Skip row (empty row) |
| Rows with only Notes and no data values | Skip row |
| Duplicate exercise names | Match existing (case-insensitive), don't create duplicate |
| Weight (lbs) column | Always ignored |

## Complexity Tracking

| Decision | Justification |
|----------|---------------|
| Hand-rolled CSV parser vs library | Known fixed format. RFC 4180 handling is ~50 lines. Avoids dependency for a well-scoped problem. |
| Single ImportService (not Import + Mapper + Validator) | Feature scope doesn't justify 3 separate services. ImportService orchestrates internally. |
| Chunked inserts (500/batch) vs single transaction | 12k rows in one transaction risks memory pressure. Chunks allow progress reporting + bounded memory. |
| AsyncStream for progress vs callback | Cleaner Swift concurrency pattern. ViewModel consumes naturally with `for await`. |
| NavigationLink vs sheet for import/export | Import has a multi-step flow (select → preview → import → results) better suited to a pushed view than a sheet. |
| No undo for import | Constitution says hard delete only, everything rebuildable. User can delete workouts manually or re-import. |

## Parallel Work Analysis

### Dependency Graph

```
WP01: Foundation (CSVParser, ImportService/ExportService protocols, ServiceContainer wiring)
  → WP02: Import Logic (ImportService implementation, validation, mapping, chunked insert, rebuild trigger)
  → WP03: Import UI (ImportView, ImportViewModel, file picker, preview, progress, results)
  → WP04: Export (ExportService, ExportView, ExportViewModel, ShareLink, Settings wiring)
  → WP05: Integration (SettingsView update, build verification, edge case testing)
```

WP01 must complete first (provides CSVParser and service protocols). WP02 must precede WP03 (UI needs service). WP04 (Export) depends on WP01 for the service protocol pattern but is otherwise independent of WP02/WP03. WP05 integrates everything and replaces the "Coming Soon" stubs.
