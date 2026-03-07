---
work_package_id: "WP04"
subtasks:
  - "T017"
  - "T018"
  - "T019"
  - "T020"
  - "T021"
title: "Export — ExportService + UI"
phase: "Phase 2 - User Stories"
lane: "done"
assignee: ""
agent: "claude-opus-reviewer"
shell_pid: "4783"
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

# Work Package Prompt: WP04 – Export — ExportService + UI

## Implementation Command

```bash
spec-kitty implement WP04 --base WP01
```

## Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

Build CSV export: service generates CSV data from all workouts/exercises/sets, view provides trigger + share sheet.

1. **ExportService** — actor that queries all data and generates RFC 4180 compliant CSV
2. **ExportViewModel** — `@Observable` with export state
3. **ExportView** — export trigger, progress, ShareLink for sharing
4. Wire ExportService into ServiceContainer

**Success criteria**:
- Export generates CSV with correct 11-column header matching import format
- All WorkoutSets included, sorted by date → exercise → order
- Weight values in kg. Weight (lbs) column is computed (kg × 2.20462).
- Fields with commas/quotes are properly quoted
- ShareLink presents system share sheet with `.csv` file
- Exported CSV can be re-imported (SC-004 round-trip)

## Context & Constraints

**Design documents**:
- `kitty-specs/011-csv-import-export/plan.md` — ExportService architecture, reverse Kind mapping
- `kitty-specs/011-csv-import-export/data-model.md` — Export mapping table (SwiftData → CSV)
- `kitty-specs/011-csv-import-export/research.md` — ShareLink API, Transferable, FileRepresentation, iOS 17 bug

**Architecture rules**:
- ExportService is an `actor` conforming to `ExportServiceProtocol`
- ViewModels use `@Observable`
- All data via repositories (no ModelContext in ViewModel/Service)
- Dark mode only

**Existing code to reference**:
- `Reppo/Data/Models/WorkoutSet.swift` — fields to export
- `Reppo/Data/Models/Exercise.swift` — name, primaryMuscle, trackingType
- `Reppo/Data/Models/Workout.swift` — date
- `Reppo/Data/Enums/TrackingType.swift` — enum values for reverse Kind mapping
- Repository protocols — fetch methods available

---

## Subtask T017: Create ExportService Actor

**Purpose**: Service that generates CSV data from all workouts/exercises/sets.

**File**: `Reppo/Core/Services/ExportService.swift` (NEW)

**Steps**:

1. Create the actor with dependency injection:

```swift
import Foundation
import SwiftData

actor ExportService: ExportServiceProtocol {

    private let workoutRepo: any WorkoutRepositoryProtocol
    private let exerciseRepo: any ExerciseRepositoryProtocol
    private let setRepo: any WorkoutSetRepositoryProtocol

    init(
        workoutRepo: any WorkoutRepositoryProtocol,
        exerciseRepo: any ExerciseRepositoryProtocol,
        setRepo: any WorkoutSetRepositoryProtocol
    ) {
        self.workoutRepo = workoutRepo
        self.exerciseRepo = exerciseRepo
        self.setRepo = setRepo
    }

    func exportCSV() async throws -> Data {
        // Implementation in T018
        fatalError("Not implemented")
    }
}
```

**Validation**:
- Actor compiles with correct dependencies
- Conforms to ExportServiceProtocol

---

## Subtask T018: Implement CSV Generation

**Purpose**: Query all data and format as CSV with proper escaping.

**Steps**:

1. Implement `exportCSV()`:

```swift
func exportCSV() async throws -> Data {
    // 1. Fetch all data
    let exercises = try await exerciseRepo.fetchAll()
    let exerciseLookup = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

    // 2. Fetch all sets, sorted by date ASC
    let allSets = try await setRepo.fetchAll()  // Check actual method name
    let sortedSets = allSets.sorted { a, b in
        if a.date != b.date { return a.date < b.date }
        return a.orderInWorkout < b.orderInWorkout
    }

    // 3. Build CSV
    var csv = ""

    // Header
    let header = "Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind"
    csv += header + "\n"

    // Date formatter
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")

    // Rows
    for set in sortedSets {
        let exercise = exerciseLookup[set.exerciseId]

        let dateStr = dateFormatter.string(from: set.date)
        let exerciseName = escapeCSVField(exercise?.name ?? "Unknown")
        let category = escapeCSVField(exercise?.primaryMuscle ?? "")

        let weightKg: String
        if let w = set.weight {
            weightKg = String(format: "%.2f", w)
        } else {
            weightKg = ""
        }

        let weightLbs: String
        if let w = set.weight {
            weightLbs = String(format: "%.2f", w * 2.20462)
        } else {
            weightLbs = ""
        }

        let reps = set.reps.map { String($0) } ?? ""
        let distance = set.distanceMeters.map { String(format: "%.2f", $0) } ?? ""
        let distanceUnit = set.distanceMeters != nil ? "m" : ""
        let time = set.durationSeconds.map { String($0) } ?? ""
        let notes = escapeCSVField(set.notes ?? "")
        let kind = reverseKindMapping(exercise?.trackingType)

        let row = [dateStr, exerciseName, category, weightKg, weightLbs,
                    reps, distance, distanceUnit, time, notes, kind]
        csv += row.joined(separator: ",") + "\n"
    }

    guard let data = csv.data(using: .utf8) else {
        throw ExportError.encodingFailed
    }
    return data
}
```

2. Add CSV field escaping (RFC 4180):

```swift
private func escapeCSVField(_ field: String) -> String {
    // If field contains comma, quote, or newline — wrap in quotes and escape internal quotes
    if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
    return field
}
```

3. Add error type:

```swift
enum ExportError: Error, LocalizedError {
    case noData
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noData: return "No workout data to export."
        case .encodingFailed: return "Failed to encode CSV data."
        }
    }
}
```

**CRITICAL**: Adapt the data fetching to actual repository methods. Key things to check:
- How to fetch ALL sets — is there a `fetchAll()` method or do you need to query with no filters?
- How sets relate to exercises — is `exerciseId` a UUID property or is there a relationship object?
- How to access `set.date`, `set.weight`, `set.reps`, etc. — match actual property names.

**Validation**:
- Empty database → throws ExportError.noData (or returns header-only CSV, choose behavior)
- 10 sets → CSV with header + 10 rows
- Weight "50.0 kg" → "50.00" in kg column, "110.23" in lbs column
- Notes with comma → quoted field: `"note, with comma"`
- Field with quotes → escaped: `"say ""hello"""`

---

## Subtask T019: Implement Reverse Kind Mapping

**Purpose**: Map Exercise.trackingType back to the CSV Kind column value for export.

**Steps**:

```swift
private func reverseKindMapping(_ trackingType: TrackingType?) -> String {
    switch trackingType {
    case .weightReps:         return "wr"
    case .duration:           return "d"
    case .weightDistance:     return "wd"
    case .weightRepsDuration: return "wrd"
    case .custom:             return "wr"  // Default
    case nil:                 return "wr"  // Default
    }
}
```

**Validation**:
- `.weightReps` → `"wr"`
- `.duration` → `"d"`
- `.weightDistance` → `"wd"`
- `.weightRepsDuration` → `"wrd"`
- `.custom` → `"wr"` (safe default)
- `nil` → `"wr"`

---

## Subtask T020: Create ExportViewModel

**Purpose**: Simple ViewModel managing export state.

**File**: `Reppo/Features/Settings/ViewModels/ExportViewModel.swift` (NEW)

**Steps**:

```swift
import Foundation

@Observable
final class ExportViewModel {

    var isExporting = false
    var exportData: Data?
    var errorMessage: String?
    var showShareSheet = false

    private let exportService: any ExportServiceProtocol

    init(exportService: any ExportServiceProtocol) {
        self.exportService = exportService
    }

    func generateExport() {
        isExporting = true
        errorMessage = nil

        Task {
            do {
                let data = try await exportService.exportCSV()
                await MainActor.run {
                    self.exportData = data
                    self.isExporting = false
                    self.showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isExporting = false
                }
            }
        }
    }
}
```

**Validation**:
- isExporting becomes true during export, false when done
- exportData populated on success
- errorMessage populated on failure

---

## Subtask T021: Create ExportView with ShareLink

**Purpose**: View with export button, progress, and share sheet for the generated CSV file.

**File**: `Reppo/Features/Settings/Views/ExportView.swift` (NEW)

**Steps**:

1. Define `CSVFile` Transferable:

```swift
import SwiftUI
import UniformTypeIdentifiers

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
        // ProxyRepresentation fallback — fixes iOS 17 Files app issue
        ProxyRepresentation { csv in csv.data }
    }
}
```

2. Create the view:

```swift
struct ExportView: View {
    @State private var viewModel: ExportViewModel

    init(exportService: any ExportServiceProtocol) {
        _viewModel = State(initialValue: ExportViewModel(exportService: exportService))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)

            Text("Export Training Data")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text("Export all your workouts, exercises, and sets as a CSV file. Weights are exported in kilograms.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if viewModel.isExporting {
                ProgressView("Generating CSV...")
            } else if let data = viewModel.exportData {
                let file = CSVFile(data: data, filename: "workouts-export.csv")
                ShareLink(item: file, preview: SharePreview("workouts-export.csv", image: Image(systemName: "doc.text"))) {
                    Label("Share CSV", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            } else {
                Button {
                    viewModel.generateExport()
                } label: {
                    Label("Export", systemImage: "arrow.down.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .navigationTitle("Export Data")
        .background(Color.bg)
    }
}
```

3. Wire ExportService into ServiceContainer:

Add to `ServiceContainer.swift`:
```swift
let exportService: any ExportServiceProtocol
```

Initialize:
```swift
self.exportService = ExportService(
    workoutRepo: repos.workoutRepository,
    exerciseRepo: repos.exerciseRepository,
    setRepo: repos.workoutSetRepository
)
```

**Validation**:
- Export button triggers CSV generation
- ProgressView shown during export
- ShareLink appears with correct filename
- Error message shown if export fails
- Dark mode styling
- ServiceContainer wires ExportService correctly

---

## Definition of Done

- [ ] ExportService generates CSV with correct 11-column header
- [ ] All WorkoutSets exported, sorted by date → order
- [ ] Weight (kg) exported as-is, Weight (lbs) computed from kg
- [ ] Fields with commas/quotes properly escaped (RFC 4180)
- [ ] Reverse Kind mapping: trackingType → Kind value
- [ ] ExportViewModel manages export state
- [ ] ExportView has export button → progress → ShareLink flow
- [ ] CSVFile Transferable with FileRepresentation + ProxyRepresentation
- [ ] ExportService wired into ServiceContainer
- [ ] Project builds with no errors

## Risks & Edge Cases

| Risk | Mitigation |
|------|-----------|
| Empty database | Show appropriate message or header-only CSV |
| Very large export (12k+ rows) | ~2-5MB in memory, acceptable. No streaming needed. |
| iOS 17 Files app ShareLink bug | ProxyRepresentation fallback handles it |
| Notes with newlines | escapeCSVField wraps in quotes |
| Date timezone issues | Use UTC DateFormatter, consistent with import |

## Reviewer Guidance

- Verify CSV header exactly matches: `Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind`
- Verify Weight (lbs) is computed (not stored value)
- Verify field escaping handles commas, quotes, and newlines
- Verify CSVFile has BOTH FileRepresentation AND ProxyRepresentation
- Verify the exported CSV matches the import format (SC-004 round-trip)

## Activity Log

- 2026-03-01T10:19:14Z – claude-opus – shell_pid=1981 – lane=doing – Started implementation via workflow command
- 2026-03-01T10:26:47Z – claude-opus – shell_pid=1981 – lane=for_review – Ready for review: ExportService actor with RFC 4180 CSV generation, ExportViewModel, ExportView with CSVFile Transferable + ShareLink, wired into ServiceContainer. Build passes.
- 2026-03-01T10:27:52Z – claude-opus-reviewer – shell_pid=4783 – lane=doing – Started review via workflow command
- 2026-03-01T10:30:22Z – claude-opus-reviewer – shell_pid=4783 – lane=done – Review passed: All 10 DoD items verified. CSV header matches spec, RFC 4180 escaping correct, reverse Kind mapping covers all TrackingType cases, CSVFile has both FileRepresentation + ProxyRepresentation, ServiceContainer wiring correct, build passes. DesignTokens colors used consistently.
