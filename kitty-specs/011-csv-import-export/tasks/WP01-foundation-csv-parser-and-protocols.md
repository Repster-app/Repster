---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
title: "Foundation — CSVParser + Service Protocols"
phase: "Phase 1 - Foundation"
lane: "done"
assignee: ""
agent: "claude-opus"
shell_pid: "87128"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: []
history:
  - timestamp: "2026-03-01T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP01 – Foundation — CSVParser + Service Protocols

## Implementation Command

```bash
spec-kitty implement WP01
```

## Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

This work package creates the foundation that all subsequent WPs depend on:

1. A **CSVParser** utility that correctly parses RFC 4180 CSV data, handling quoted fields with embedded commas, newlines, and escaped quotes.
2. **ImportServiceProtocol** with all supporting types (ImportProgress, ImportResult, ImportError).
3. **ExportServiceProtocol** for CSV export.
4. All new files added to the Xcode project and compiling.

**Success criteria**:
- CSVParser.parse() correctly handles: simple rows, quoted fields with commas, quoted fields with embedded newlines, escaped quotes (`""`), trailing newline, empty fields.
- All types are `Sendable` (required for actor isolation).
- Protocols compile with no errors.
- Project builds successfully.

## Context & Constraints

**Design documents** (read these for full context):
- `kitty-specs/011-csv-import-export/plan.md` — architecture, component details, Kind mapping
- `kitty-specs/011-csv-import-export/data-model.md` — types, service contracts, CSV column mapping
- `kitty-specs/011-csv-import-export/research.md` — RFC 4180 algorithm, date parsing, AsyncStream patterns

**Architecture rules**:
- MVVM: View → ViewModel → Service → Repository → SwiftData
- All services are `actor` types for thread safety
- Protocol-first: create protocol, then implementation
- No third-party dependencies (constitution)
- All types crossing actor boundaries must be `Sendable`

**Existing code references**:
- `Reppo/Core/Services/Protocols/SettingsServiceProtocol.swift` — protocol pattern to follow
- `Reppo/Data/Enums/TrackingType.swift` — TrackingType enum used by ImportProgress types
- `Reppo/Data/Enums/SetType.swift` — SetType enum referenced by import types

---

## Subtask T001: Create CSVParser Utility with RFC 4180 State Machine

**Purpose**: Parse CSV data into structured rows, handling all RFC 4180 edge cases. This is the core parsing engine used by both ImportService (full parse + preview) and potentially validation logic.

**File**: `Reppo/Core/Utilities/CSVParser.swift` (NEW — create `Utilities/` directory if it doesn't exist)

**Steps**:

1. Create the `CSVParser` struct with nested types:

```swift
struct CSVParser {
    struct ParseResult {
        let headers: [String]
        let rows: [[String]]        // Each inner array is one row of field values
        let totalRows: Int           // rows.count (convenience)
    }

    struct PreviewResult {
        let headers: [String]
        let sampleRows: [[String]]   // First N rows only
        let estimatedTotalRows: Int  // Approximate total from line count
    }

    struct ValidationError: Identifiable, Sendable {
        let id: UUID
        let rowNumber: Int           // 1-based row number in CSV
        let reason: String           // Human-readable error description
        let rawLine: String?         // Original CSV line (truncated if very long)

        init(rowNumber: Int, reason: String, rawLine: String? = nil) {
            self.id = UUID()
            self.rowNumber = rowNumber
            self.reason = reason
            self.rawLine = rawLine
        }
    }
}
```

2. Implement the core state machine parser as a `private static` method:

```
parseFields(from text: String) -> [[String]]
```

Algorithm (character-by-character):
- Maintain: `inQuotes: Bool`, `currentField: String`, `currentRow: [String]`, `rows: [[String]]`
- Normalize input: replace `\r\n` with `\n`, strip trailing `\r`
- Iterate characters:
  - **Inside quotes** (`inQuotes == true`):
    - `"` → peek next char: if also `"` → append literal `"`, skip both. Otherwise → close quotes (`inQuotes = false`)
    - Any other char (including `,` and `\n`) → append to `currentField`
  - **Outside quotes** (`inQuotes == false`):
    - `"` → open quotes (`inQuotes = true`)
    - `,` → end field: append `currentField` to `currentRow`, reset `currentField`
    - `\n` → end row: append `currentField` to `currentRow`, append `currentRow` to `rows`, reset both
    - `\r` → skip (already normalized, but be safe)
    - Any other char → append to `currentField`
- After loop: flush remaining `currentField`/`currentRow` if non-empty (handle no-trailing-newline case)
- Guard against spurious empty final row (single empty string)

3. Implement public `parse` method:

```swift
static func parse(data: Data, encoding: String.Encoding = .utf8) throws -> ParseResult {
    guard let text = String(data: data, encoding: encoding) else {
        // Try Latin-1 fallback
        guard let fallback = String(data: data, encoding: .isoLatin1) else {
            throw CSVParserError.invalidEncoding
        }
        return try parseText(fallback)
    }
    return try parseText(text)
}

private static func parseText(_ text: String) throws -> ParseResult {
    let allRows = parseFields(from: text)
    guard let headers = allRows.first, !headers.isEmpty else {
        throw CSVParserError.emptyFile
    }
    let dataRows = Array(allRows.dropFirst())
    return ParseResult(headers: headers, rows: dataRows, totalRows: dataRows.count)
}
```

4. Implement `parsePreview` method:

```swift
static func parsePreview(data: Data, maxRows: Int = 5, encoding: String.Encoding = .utf8) throws -> PreviewResult {
    guard let text = String(data: data, encoding: encoding) ??
          String(data: data, encoding: .isoLatin1) else {
        throw CSVParserError.invalidEncoding
    }

    // Count total lines (approximate — doesn't account for quoted newlines, but good enough for preview)
    let estimatedLines = text.components(separatedBy: "\n").count - 1  // -1 for header

    let allRows = parseFields(from: text)
    guard let headers = allRows.first else {
        throw CSVParserError.emptyFile
    }
    let sampleRows = Array(allRows.dropFirst().prefix(maxRows))
    return PreviewResult(headers: headers, sampleRows: sampleRows, estimatedTotalRows: max(estimatedLines, sampleRows.count))
}
```

5. Add `CSVParserError` enum:

```swift
enum CSVParserError: Error, LocalizedError {
    case invalidEncoding
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "Unable to read file encoding. Please ensure the file is UTF-8 encoded."
        case .emptyFile: return "The CSV file is empty or has no header row."
        }
    }
}
```

**Validation**:
- Parse `"a,b,c\n1,2,3\n"` → headers `["a","b","c"]`, 1 row `["1","2","3"]`
- Parse `"a,b\n\"hello, world\",2\n"` → row `["hello, world", "2"]` (comma inside quotes)
- Parse `"a,b\n\"line1\nline2\",2\n"` → row `["line1\nline2", "2"]` (newline inside quotes)
- Parse `"a,b\n\"say \"\"hi\"\"\",2\n"` → row `["say \"hi\"", "2"]` (escaped quotes)
- Parse `"a,b\n1,2\n"` (trailing newline) → 1 row, not 2
- Parse `"a,b\n1,\n"` → row `["1", ""]` (empty field)

---

## Subtask T002: Create ImportServiceProtocol + Supporting Types

**Purpose**: Define the contract for ImportService and all types that flow through the import pipeline. These types are consumed by both the service (WP02) and the UI (WP03).

**File**: `Reppo/Core/Services/Protocols/ImportServiceProtocol.swift` (NEW)

**Steps**:

1. Define `ImportProgress` enum (must be `Sendable`):

```swift
enum ImportProgress: Sendable {
    case parsing
    case validating(processed: Int, total: Int)
    case importing(inserted: Int, total: Int)
    case rebuilding(phase: RebuildPhase)
    case completed(ImportResult)
    case failed(ImportError)

    enum RebuildPhase: String, Sendable {
        case stats = "Rebuilding statistics..."
        case prs = "Rebuilding personal records..."
    }
}
```

2. Define `ImportResult` struct:

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

3. Define `ImportError` enum:

```swift
enum ImportError: Error, LocalizedError, Sendable {
    case fileReadFailed(String)
    case invalidEncoding
    case invalidHeader(expected: [String], got: [String])
    case noValidRows
    case insertFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let msg): return "Failed to read file: \(msg)"
        case .invalidEncoding: return "Unable to read file. Please ensure it is UTF-8 encoded."
        case .invalidHeader(let expected, let got):
            return "CSV header mismatch. Expected \(expected.count) columns, found \(got.count)."
        case .noValidRows: return "No valid data rows found in the CSV file."
        case .insertFailed(let msg): return "Database insert failed: \(msg)"
        case .cancelled: return "Import was cancelled."
        }
    }
}
```

4. Define the protocol:

```swift
protocol ImportServiceProtocol: Sendable {
    /// Parse first N rows for preview display. Does NOT modify any data.
    func previewCSV(data: Data) throws -> CSVParser.PreviewResult

    /// Run full import. Returns an AsyncStream of progress updates.
    /// Caller MUST consume the stream to completion.
    func importCSV(data: Data) -> AsyncStream<ImportProgress>
}
```

**Validation**:
- All types compile with `Sendable` conformance
- Protocol methods match data-model.md contracts
- ImportProgress covers all states needed by ImportViewModel (idle is ViewModel-only)

---

## Subtask T003: Create ExportServiceProtocol

**Purpose**: Define the contract for ExportService. Simple — single method returning CSV data.

**File**: `Reppo/Core/Services/Protocols/ExportServiceProtocol.swift` (NEW)

**Steps**:

1. Define the protocol:

```swift
protocol ExportServiceProtocol: Sendable {
    /// Generate CSV data for all workouts, exercises, and sets.
    /// Returns UTF-8 encoded CSV data ready for file sharing.
    func exportCSV() async throws -> Data
}
```

**Validation**:
- Protocol compiles
- Method signature matches data-model.md contract

---

## Subtask T004: Add New Files to Xcode Project + Verify Build

**Purpose**: Ensure all new files are added to the Xcode project and the project compiles successfully.

**Steps**:

1. Verify directory structure exists:
   - `Reppo/Core/Utilities/` — create if needed
   - `Reppo/Core/Services/Protocols/` — already exists

2. Add file references to `Reppo.xcodeproj/project.pbxproj`:
   - `Reppo/Core/Utilities/CSVParser.swift`
   - `Reppo/Core/Services/Protocols/ImportServiceProtocol.swift`
   - `Reppo/Core/Services/Protocols/ExportServiceProtocol.swift`

3. Build the project to verify no compile errors:
   ```bash
   xcodebuild -project Reppo.xcodeproj -scheme Reppo -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
   ```

**Validation**:
- [ ] `Reppo/Core/Utilities/CSVParser.swift` exists and is in Xcode project
- [ ] `Reppo/Core/Services/Protocols/ImportServiceProtocol.swift` exists and is in Xcode project
- [ ] `Reppo/Core/Services/Protocols/ExportServiceProtocol.swift` exists and is in Xcode project
- [ ] Project builds with no errors

---

## Definition of Done

- [ ] CSVParser parses RFC 4180 CSV correctly (quoted fields, embedded commas, embedded newlines, escaped quotes)
- [ ] CSVParser.parsePreview returns first N rows + estimated total
- [ ] ImportProgress, ImportResult, ImportError are all Sendable
- [ ] ImportServiceProtocol has previewCSV and importCSV methods
- [ ] ExportServiceProtocol has exportCSV method
- [ ] All files added to Xcode project
- [ ] Project builds with no errors
- [ ] No third-party dependencies introduced

## Risks & Edge Cases

| Risk | Mitigation |
|------|-----------|
| CSV with mixed line endings (\r\n, \n, \r) | Normalize \r\n → \n and skip bare \r before parsing |
| Trailing newline produces empty final row | Guard in flush: skip row if it's a single empty string |
| Very large file (>100MB) | Not a concern for 12k rows (~2MB). No streaming needed. |
| Non-UTF-8 encoding | Try UTF-8 first, fallback to Latin-1 |

## Reviewer Guidance

- Verify the state machine handles the RFC 4180 test cases listed in T001 validation
- Check that all types are `Sendable` (this is critical for actor isolation in WP02)
- Verify protocol method signatures match `data-model.md`
- Check that CSVParser has NO SwiftData dependencies (pure utility)

## Activity Log

- 2026-03-01T09:10:10Z – claude-opus – shell_pid=87128 – lane=doing – Started implementation via workflow command
- 2026-03-01T10:41:42Z – claude-opus – shell_pid=87128 – lane=done – Already reviewed and approved in earlier session
