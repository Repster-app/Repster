---
work_package_id: "WP03"
subtasks:
  - "T011"
  - "T012"
  - "T013"
  - "T014"
  - "T015"
  - "T016"
title: "Import UI — ImportView + ImportViewModel"
phase: "Phase 2 - User Stories"
lane: "done"
assignee: ""
agent: "claude-opus-reviewer"
shell_pid: "997"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01", "WP02"]
history:
  - timestamp: "2026-03-01T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – Import UI — ImportView + ImportViewModel

## Implementation Command

```bash
spec-kitty implement WP03 --base WP02
```

## Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

Build the complete import user experience as a state-machine-driven view:

1. **ImportViewModel** — `@Observable` with state machine (idle → previewing → importing → rebuilding → completed → failed)
2. **ImportView** — multi-state layout: file picker trigger, data preview, progress, results, error
3. Full `.fileImporter` integration with security-scoped resource access
4. AsyncStream consumption for live progress updates

**Success criteria**:
- User opens ImportView, taps "Select CSV File", file picker appears for `.csv` files
- After selection, preview shows first 5 rows + column mapping + total row count
- User taps "Import", progress bar updates in real-time
- After rebuild, summary shows: sets imported, workouts created, exercises created, errors
- On error (invalid file), clear error message with retry option

## Context & Constraints

**Design documents**:
- `kitty-specs/011-csv-import-export/plan.md` — View hierarchy, data flow, ImportViewModel architecture
- `kitty-specs/011-csv-import-export/data-model.md` — ImportProgress enum, ImportResult struct
- `kitty-specs/011-csv-import-export/research.md` — .fileImporter API, security-scoped access, AsyncStream consumption

**Architecture rules**:
- ViewModels use `@Observable` (not ObservableObject)
- Views never call Services directly — always through ViewModel
- Dark mode only — use DesignTokens colors
- No ModelContext in ViewModel
- NavigationStack (not NavigationView)

**Existing patterns to follow**:
- `Reppo/Features/Settings/ViewModels/SettingsViewModel.swift` — @Observable pattern
- `Reppo/Features/Settings/Views/SettingsView.swift` — form styling, dark mode colors
- `Reppo/Features/Settings/Views/RebuildStatsView.swift` — progress/rebuild UI pattern

---

## Subtask T011: Create ImportViewModel with State Machine

**Purpose**: ViewModel that manages the import flow through distinct states, consuming ImportService's AsyncStream for progress.

**File**: `Reppo/Features/Settings/ViewModels/ImportViewModel.swift` (NEW)

**Steps**:

1. Define the state enum and ViewModel:

```swift
import Foundation
import SwiftUI

@Observable
final class ImportViewModel {

    // MARK: - State Machine
    enum ImportState {
        case idle
        case previewing
        case importing
        case rebuilding
        case completed
        case failed
    }

    // MARK: - Published State
    var state: ImportState = .idle
    var showFilePicker = false

    // Preview state
    var previewHeaders: [String] = []
    var previewRows: [[String]] = []
    var estimatedTotalRows: Int = 0

    // Progress state
    var progressFraction: Double = 0
    var progressLabel: String = ""
    var setsInserted: Int = 0
    var totalSets: Int = 0

    // Result state
    var result: ImportResult?

    // Error state
    var errorMessage: String?

    // MARK: - Private
    private let importService: any ImportServiceProtocol
    private var importData: Data?  // Stored after file selection

    init(importService: any ImportServiceProtocol) {
        self.importService = importService
    }
}
```

2. Add file selection handler:

```swift
func handleFileSelected(_ result: Result<URL, Error>) {
    switch result {
    case .failure(let error):
        errorMessage = error.localizedDescription
        state = .failed

    case .success(let url):
        // Security-scoped resource access
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            // MUST read data within security scope — cannot defer to later
            let data = try Data(contentsOf: url)
            self.importData = data

            let preview = try importService.previewCSV(data: data)
            self.previewHeaders = preview.headers
            self.previewRows = preview.sampleRows
            self.estimatedTotalRows = preview.estimatedTotalRows
            self.state = .previewing
        } catch {
            errorMessage = error.localizedDescription
            state = .failed
        }
    }
}
```

**CRITICAL**: `importService.previewCSV(data:)` is NOT async (it's `throws`, not `async throws`). But the ViewModel may need to call it from the MainActor. Check if this needs to be wrapped in a Task. Since CSVParser is a pure function and preview parses only 5 rows, it should be fast enough to call synchronously. If ImportService is an actor, you need `await` — check the protocol signature.

3. Add import confirmation:

```swift
func confirmImport() {
    guard let data = importData else { return }

    state = .importing
    progressFraction = 0
    setsInserted = 0

    Task {
        let stream = await importService.importCSV(data: data)

        for await progress in stream {
            await MainActor.run {
                self.handleProgress(progress)
            }
        }
    }
}

@MainActor
private func handleProgress(_ progress: ImportProgress) {
    switch progress {
    case .parsing:
        progressLabel = "Parsing CSV..."
        progressFraction = 0

    case .validating(let processed, let total):
        progressLabel = "Validating row \(processed) of \(total)..."
        progressFraction = Double(processed) / Double(total) * 0.1  // 10% for validation
        totalSets = total

    case .importing(let inserted, let total):
        state = .importing
        progressLabel = "Importing set \(inserted) of \(total)..."
        progressFraction = 0.1 + (Double(inserted) / Double(total) * 0.7)  // 70% for import
        setsInserted = inserted
        totalSets = total

    case .rebuilding(let phase):
        state = .rebuilding
        progressLabel = phase.rawValue
        progressFraction = 0.8 + (phase == .stats ? 0 : 0.1)  // 80-90% for rebuild

    case .completed(let result):
        self.result = result
        state = .completed
        progressFraction = 1.0

    case .failed(let error):
        errorMessage = error.localizedDescription
        state = .failed
    }
}
```

4. Add reset/retry:

```swift
func reset() {
    state = .idle
    importData = nil
    previewHeaders = []
    previewRows = []
    estimatedTotalRows = 0
    progressFraction = 0
    progressLabel = ""
    setsInserted = 0
    totalSets = 0
    result = nil
    errorMessage = nil
}

func retry() {
    if importData != nil {
        // Re-parse preview from stored data
        state = .idle
        errorMessage = nil
        showFilePicker = true
    } else {
        reset()
        showFilePicker = true
    }
}
```

**Validation**:
- State transitions: idle → (file selected) → previewing → (confirm) → importing → rebuilding → completed
- State transitions: idle → (file selected with error) → failed → (retry) → idle
- Progress fraction ranges from 0.0 to 1.0
- Result is populated in .completed state
- errorMessage is populated in .failed state

---

## Subtask T012: Create ImportView Layout

**Purpose**: The main view that renders different UI based on ImportViewModel.state.

**File**: `Reppo/Features/Settings/Views/ImportView.swift` (NEW)

**Steps**:

1. Create the view with state-driven body:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @State private var viewModel: ImportViewModel

    init(importService: any ImportServiceProtocol) {
        _viewModel = State(initialValue: ImportViewModel(importService: importService))
    }

    var body: some View {
        VStack {
            switch viewModel.state {
            case .idle:
                idleView
            case .previewing:
                previewView
            case .importing:
                progressView
            case .rebuilding:
                rebuildingView
            case .completed:
                completedView
            case .failed:
                failedView
            }
        }
        .navigationTitle("Import Data")
        .background(Color.bg)
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.commaSeparatedText]
        ) { result in
            viewModel.handleFileSelected(result)
        }
    }
}
```

The specific state views (idle, preview, progress, etc.) are implemented in subtasks T013–T016. Stub them initially:

```swift
private var idleView: some View { ... }
private var previewView: some View { ... }
private var progressView: some View { ... }
private var rebuildingView: some View { ... }
private var completedView: some View { ... }
private var failedView: some View { ... }
```

**Validation**:
- View compiles with all state branches
- `.fileImporter` modifier attached with correct content type
- Navigation title "Import Data"
- Dark mode background

---

## Subtask T013: Implement Idle State + File Picker

**Purpose**: The initial state when the user opens ImportView — a button to select a CSV file.

**Steps**:

Add to ImportView:

```swift
private var idleView: some View {
    VStack(spacing: 24) {
        Spacer()

        Image(systemName: "square.and.arrow.down")
            .font(.system(size: 48))
            .foregroundStyle(Color.textSecondary)

        Text("Import Training Data")
            .font(.title2.bold())
            .foregroundStyle(Color.textPrimary)

        Text("Select a CSV file from another training app to import your workout history.")
            .font(.body)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

        Button {
            viewModel.showFilePicker = true
        } label: {
            Label("Select CSV File", systemImage: "doc.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 32)

        Spacer()
    }
}
```

**Note**: Use colors from DesignTokens. Check existing views for the exact color names (`Color.bg`, `Color.textPrimary`, `Color.textSecondary`, etc.).

**Validation**:
- Centered layout with icon, title, description, button
- Button triggers file picker
- Dark mode styling

---

## Subtask T014: Implement Preview State

**Purpose**: Show the user what they're about to import — header mapping, first 5 rows, total count, and Import/Cancel buttons.

**Steps**:

```swift
private var previewView: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            // Header: what will be imported
            Text("Preview")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text("\(viewModel.estimatedTotalRows) rows found")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            // Column mapping summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Column Mapping")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                ForEach(Array(viewModel.previewHeaders.enumerated()), id: \.offset) { index, header in
                    HStack {
                        Text(header)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(columnMapping(for: header))
                            .font(.caption)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
            .padding()
            .background(Color.surfaceSecondary)
            .cornerRadius(12)

            // Sample rows (horizontally scrollable table)
            VStack(alignment: .leading, spacing: 8) {
                Text("Sample Data")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Header row
                        HStack(spacing: 0) {
                            ForEach(viewModel.previewHeaders, id: \.self) { header in
                                Text(header)
                                    .font(.caption2.bold())
                                    .frame(width: 100, alignment: .leading)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }

                        Divider()

                        // Data rows
                        ForEach(Array(viewModel.previewRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 0) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, field in
                                    Text(field.isEmpty ? "—" : field)
                                        .font(.caption2)
                                        .frame(width: 100, alignment: .leading)
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Color.surfaceSecondary)
            .cornerRadius(12)

            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    viewModel.reset()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Import \(viewModel.estimatedTotalRows) Rows") {
                    viewModel.confirmImport()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

// Helper for column mapping display
private func columnMapping(for header: String) -> String {
    switch header {
    case "Date": return "→ Workout date"
    case "Exercise": return "→ Exercise name"
    case "Category": return "→ Primary muscle"
    case "Weight (kg)": return "→ Set weight"
    case "Weight (lbs)": return "→ Ignored"
    case "Reps": return "→ Set reps"
    case "Distance": return "→ Distance (meters)"
    case "Distance Unit": return "→ Unit conversion"
    case "Time": return "→ Duration (seconds)"
    case "Notes": return "→ Set notes"
    case "Kind": return "→ Exercise type"
    default: return "→ Unknown"
    }
}
```

**Validation**:
- Shows row count estimate
- Column mapping table shows all 11 columns with their targets
- "Weight (lbs)" shows "→ Ignored"
- Sample data rows are horizontally scrollable
- Cancel resets to idle, Import starts the process

---

## Subtask T015: Implement Importing + Rebuilding States

**Purpose**: Show real-time progress during import and rebuild phases.

**Steps**:

```swift
private var progressView: some View {
    VStack(spacing: 24) {
        Spacer()

        ProgressView(value: viewModel.progressFraction)
            .progressViewStyle(.linear)
            .padding(.horizontal, 32)

        Text(viewModel.progressLabel)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)

        if viewModel.setsInserted > 0 {
            Text("\(viewModel.setsInserted) of \(viewModel.totalSets) sets processed")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }

        Spacer()
    }
}

private var rebuildingView: some View {
    VStack(spacing: 24) {
        Spacer()

        ProgressView()
            .scaleEffect(1.5)

        Text(viewModel.progressLabel)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)

        Text("This may take a moment for large datasets.")
            .font(.caption)
            .foregroundStyle(Color.textSecondary)

        Spacer()
    }
}
```

**Validation**:
- Importing state: determinate progress bar + label + set count
- Rebuilding state: indeterminate spinner + phase label
- Progress fraction updates smoothly (no jumps)

---

## Subtask T016: Implement Completed + Failed States

**Purpose**: Show import results or error with appropriate actions.

**Steps**:

```swift
@Environment(\.dismiss) private var dismiss

private var completedView: some View {
    VStack(spacing: 20) {
        Spacer()

        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.green)

        Text("Import Complete")
            .font(.title2.bold())
            .foregroundStyle(Color.textPrimary)

        if let result = viewModel.result {
            VStack(spacing: 12) {
                resultRow(label: "Sets Imported", value: "\(result.setsImported)")
                resultRow(label: "Workouts Created", value: "\(result.workoutsCreated)")
                resultRow(label: "Exercises Created", value: "\(result.exercisesCreated)")

                if result.rowsSkipped > 0 {
                    resultRow(label: "Rows Skipped", value: "\(result.rowsSkipped)")
                        .foregroundStyle(.orange)
                }

                Text(String(format: "Completed in %.1f seconds", result.duration))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding()
            .background(Color.surfaceSecondary)
            .cornerRadius(12)

            // Show errors if any
            if !result.errors.isEmpty {
                DisclosureGroup("Skipped Rows (\(result.errors.count))") {
                    ForEach(result.errors) { error in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Row \(error.rowNumber): \(error.reason)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .padding()
                .background(Color.surfaceSecondary)
                .cornerRadius(12)
            }
        }

        Button("Done") {
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)

        Spacer()
    }
    .padding()
}

private func resultRow(label: String, value: String) -> some View {
    HStack {
        Text(label)
            .font(.body)
            .foregroundStyle(Color.textSecondary)
        Spacer()
        Text(value)
            .font(.body.bold())
            .foregroundStyle(Color.textPrimary)
    }
}

private var failedView: some View {
    VStack(spacing: 24) {
        Spacer()

        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.orange)

        Text("Import Failed")
            .font(.title2.bold())
            .foregroundStyle(Color.textPrimary)

        if let error = viewModel.errorMessage {
            Text(error)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }

        HStack(spacing: 16) {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            Button("Try Again") {
                viewModel.retry()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)

        Spacer()
    }
}
```

**Validation**:
- Completed: green checkmark, summary counts, duration, expandable error list, Done button
- Failed: orange warning, error message, Cancel + Try Again buttons
- Done dismisses the view (pops navigation)
- Try Again resets and opens file picker

---

## Definition of Done

- [ ] ImportViewModel has 6 states with correct transitions
- [ ] File picker opens for `.csv` files only
- [ ] Security-scoped resource access: data read within start/stop scope
- [ ] Preview shows first 5 rows + column mapping + total count
- [ ] Import/Cancel buttons on preview
- [ ] Determinate progress bar during import
- [ ] Indeterminate spinner during rebuild
- [ ] Summary shows sets/workouts/exercises created + skipped count
- [ ] Expandable error list for skipped rows
- [ ] Error state shows message + retry option
- [ ] Done button dismisses view
- [ ] Dark mode styling throughout
- [ ] No ModelContext access in ViewModel

## Risks & Edge Cases

| Risk | Mitigation |
|------|-----------|
| Security-scoped resource expires | Read data immediately into `Data`, store it, pass to service later |
| File picker returns non-CSV file | `.fileImporter` restricts to `.commaSeparatedText`, parser validates header |
| Very wide preview table | Horizontal ScrollView for sample data |
| Progress stream on background thread | `await MainActor.run {}` for all UI state updates |
| User navigates away during import | Import continues in background; result is lost (acceptable for v1) |

## Reviewer Guidance

- Verify security-scoped access pattern: `startAccessingSecurityScopedResource()` → read Data → `defer { stop }`
- Verify data is stored as `Data` (not URL) for deferred import
- Verify AsyncStream consumed with `for await` in a `Task`, UI updates on MainActor
- Check that all colors use DesignTokens (not hardcoded)
- Verify `.dismiss()` works correctly with NavigationStack

## Activity Log

- 2026-03-01T10:03:47Z – claude-opus – shell_pid=96580 – lane=doing – Started implementation via workflow command
- 2026-03-01T10:16:46Z – claude-opus – shell_pid=96580 – lane=for_review – Ready for review: ImportViewModel (6-state machine) + ImportView (file picker, preview, progress, results, error). Build succeeds. Dark mode DesignTokens. Security-scoped file access.
- 2026-03-01T10:17:23Z – claude-opus-reviewer – shell_pid=997 – lane=doing – Started review via workflow command
- 2026-03-01T10:18:46Z – claude-opus-reviewer – shell_pid=997 – lane=done – Review passed: All 13 DoD items verified. @Observable @MainActor VM with 6-state machine. Security-scoped file access correct. AsyncStream consumed in Task on MainActor. All colors from DesignTokens. No ModelContext in VM. Build succeeds.
