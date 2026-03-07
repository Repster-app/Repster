# Research: CSV Import + Export

**Feature**: 011-csv-import-export | **Date**: 2026-03-01

## 1. CSV Parsing in Pure Swift

**Decision**: Character-by-character state machine parser (RFC 4180 compliant)
**Rationale**: No third-party dependency. Fixed 11-column format is well-known. Must handle quoted fields (Notes column may contain commas).
**Alternatives considered**: CodableCSV (battle-tested but adds dependency), `String.components(separatedBy:)` (cannot handle quoted fields — rejected)

### Key Algorithm

State machine with `inQuotes` flag. Three character classes: quote (`"`), delimiter (`,`), newline (`\n`).

- Outside quotes: comma ends field, newline ends row, quote opens quoted mode
- Inside quotes: everything is literal EXCEPT `""` (escaped quote) and lone `"` (closes quoted mode — peek ahead to distinguish)
- Normalize `\r\n` to `\n` before parsing (discard `\r` outside quotes)
- Guard against trailing newline producing spurious empty row

### Gotchas

- Never split by newline first — embedded newlines inside quoted fields corrupt the parse
- After closing quote, next char must be comma or newline (per RFC 4180). Real-world files may violate this — be lenient
- A trailing newline at EOF produces a spurious empty row — guard in final flush

## 2. SwiftUI `.fileImporter` API

**Decision**: Use `.fileImporter(isPresented:allowedContentTypes:onCompletion:)` with `UTType.commaSeparatedText`
**Rationale**: Native SwiftUI API, no UIKit wrapper needed. Available iOS 14+.

### Security-Scoped Resource Access

The URL from `.fileImporter` is security-scoped. MUST call `url.startAccessingSecurityScopedResource()` before reading and `url.stopAccessingSecurityScopedResource()` in a `defer` block.

```swift
let accessing = url.startAccessingSecurityScopedResource()
defer { if accessing { url.stopAccessingSecurityScopedResource() } }
let data = try Data(contentsOf: url)
```

### Gotchas

- `startAccessingSecurityScopedResource()` returns `false` for files already in sandbox — safe to call unconditionally
- All file reading must happen within the `start`/`stop` scope — cannot store URL and defer reading
- `UTType.commaSeparatedText` matches `.csv` extension correctly

## 3. SwiftUI `ShareLink` for Export

**Decision**: Use `ShareLink` with a custom `Transferable` type using `FileRepresentation` + `ProxyRepresentation` fallback
**Rationale**: Native SwiftUI, simpler than UIActivityViewController wrapper

### iOS 17 Bug Workaround

`FileRepresentation` alone silently fails when targeting the Files app. Fix: declare `ProxyRepresentation` after `FileRepresentation` in the `transferRepresentation` body. FileRepresentation takes priority for apps that support it; ProxyRepresentation serves as fallback.

### Key Pattern

Define a `Transferable` struct wrapping `Data` + filename. Export as `UTType.commaSeparatedText`. Write to temp directory at share time.

### Gotchas

- Using `DataRepresentation` instead of `FileRepresentation` loses the custom filename
- Temporary directory files are ephemeral — create at share time, not at app launch
- Ensure `exportedContentType` is `.commaSeparatedText` (not `.text`) for proper `.csv` extension

## 4. SwiftData Batch Insert Performance

**Decision**: Use `@ModelActor` for background inserts. Batch 500–1000 records per `modelContext.save()` call.
**Rationale**: Prevents memory spikes with 12k rows. Allows progress reporting between batches. `@ModelActor` creates its own context with autosave disabled by default.
**Alternatives considered**: Single transaction (risks memory pressure at 12k records), main-context inserts (blocks UI)

### Key Pattern

```
@ModelActor actor → modelContext auto-synthesized (autosave OFF)
→ insert in loop → save() every 500–1000 records → changes propagate to main context
```

### Gotchas

- `ModelContext` and model objects are NOT `Sendable` — never pass across actors
- Pass `ModelContainer` (which IS `Sendable`) to the actor, create context locally
- Do NOT call `save()` on the main actor's context from a background task
- SwiftData iOS 17.0 had background context propagation bugs fixed in 17.2+ — test carefully

### Architecture Decision: @ModelActor vs Repository Pattern

The existing codebase uses a Repository pattern where repositories hold a `ModelContext`. For the import operation specifically, we need a background context to avoid blocking the UI. Two approaches:

1. **@ModelActor for import only**: Create a dedicated `@ModelActor` for batch inserts, bypassing the repository layer for the import operation
2. **Repository with background context**: Create repository instances with a background `ModelContext`

**Decision**: Use approach 1 — `@ModelActor` for import. The import is a one-shot bulk operation that doesn't need the repository abstraction layer. Post-import rebuild uses the existing service/repository pattern (PRService.rebuildAll(), StatsService.rebuildAll()).

## 5. AsyncStream for Progress Reporting

**Decision**: Return `AsyncStream<ImportProgress>` from ImportService. Use continuation-based initializer with `yield()` for updates and mandatory `finish()`.
**Rationale**: Clean Swift concurrency pattern. ViewModel consumes with `for await`. Decouples service from UI.

### Key Pattern

```
actor ImportService:
  func importCSV(url:) -> AsyncStream<ImportProgress>
    → AsyncStream { continuation in Task { ... continuation.yield(.progress(...)) ... continuation.finish() } }

ViewModel:
  Task { for await update in stream { updateUI(update) } }
```

### Gotchas

- `continuation.finish()` MUST be called — forgetting it means the `for await` loop never terminates
- Cancelling consumer Task does NOT cancel producer Task — handle via `continuation.onTermination`
- `yield` from within an actor is safe — continuations are `@Sendable`

## 6. Date Parsing

**Decision**: Use `Date.ISO8601FormatStyle` (iOS 15+, `Sendable`, value type)
**Rationale**: Thread-safe for use inside `@ModelActor`. Parses "2021-05-20" format directly.
**Alternatives considered**: `DateFormatter` (mutable state risks), `ISO8601DateFormatter` (non-`Sendable`, cannot cross actor boundaries)

### Key Pattern

```swift
let dateStyle = Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)
let date = try? dateStyle.parse("2021-05-20")
```

### Gotchas

- Parses to midnight UTC for date-only strings — store as UTC, format at display time with local timezone
- Create format style once and reuse (not per-row)
- `ISO8601DateFormatter` works faster but is non-`Sendable` — unsuitable inside `@ModelActor`

## Summary Decision Table

| Topic | Decision | Key Risk |
|-------|----------|----------|
| CSV parsing | State machine, RFC 4180 | Quoted fields with embedded commas/newlines |
| File import | `.fileImporter` + security-scoped access | Must read within start/stop scope |
| File export | `ShareLink` + `FileRepresentation` + `ProxyRepresentation` | iOS 17 Files app bug without ProxyRepresentation fallback |
| Batch insert | `@ModelActor`, 500-1000/batch, explicit `save()` | ModelContext not Sendable; iOS 17.0 propagation bugs |
| Progress | `AsyncStream<ImportProgress>` | Must call `continuation.finish()` |
| Date parsing | `Date.ISO8601FormatStyle` | Midnight UTC — handle timezone at display |
