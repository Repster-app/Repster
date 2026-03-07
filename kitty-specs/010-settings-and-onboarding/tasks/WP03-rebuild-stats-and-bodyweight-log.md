---
work_package_id: "WP03"
subtasks:
  - "T013"
  - "T014"
  - "T015"
  - "T016"
  - "T017"
  - "T018"
title: "Sub-screens — Rebuild Stats + Bodyweight Log"
phase: "Phase 2 - Settings UI"
lane: "done"
assignee: ""
agent: "claude-opus-reviewer"
shell_pid: "56223"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01", "WP02"]
history:
  - timestamp: "2026-02-28T18:49:28Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – Sub-screens — Rebuild Stats + Bodyweight Log

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

Build the two sub-screens navigated from the main Settings view:

1. **RebuildStatsView** — Explanation text + 3 rebuild buttons (PRs, Stats, All) with confirmation alerts and progress overlay.
2. **BodyweightLogView** — Trend chart (Swift Charts), chronological entry list with swipe-to-delete, and Add Entry sheet.
3. **BodyweightLogViewModel** — `@Observable` class managing bodyweight entry CRUD and chart data.

**Success criteria**:
- Navigate from Settings > DATA > Rebuild Stats: see explanation + 3 buttons. Tap "Rebuild All": confirmation → progress overlay → completion message.
- Navigate from Settings > BODY > Bodyweight Log: see trend chart + entry list. Tap [+Add]: enter weight + date → entry appears in list and chart. Swipe-to-delete works.
- Empty state shows when no bodyweight entries exist.
- All weights display in the user's preferred unit (convert from kg at display time).

## Context & Constraints

**Design documents**:
- `kitty-specs/010-settings-and-onboarding/plan.md` — view hierarchy, rebuild trigger matrix, bodyweight chart specs
- `kitty-specs/010-settings-and-onboarding/research.md` — RQ-5 (bodyweight chart), RQ-6 (rebuild UI patterns)
- `kitty-specs/010-settings-and-onboarding/data-model.md` — BodyweightEntry schema, existing services
- `kitty-specs/010-settings-and-onboarding/spec.md` — User Story 3 (Bodyweight Log), User Story 4 (Rebuild Stats)

**Architecture rules**:
- Charts: Swift Charts (`LineMark` + `PointMark`) — same framework used by Charts tab (feature 009).
- `@Observable` ViewModels, all data via services (BodyweightService, SettingsService).
- Store metric only, convert in UI via `UnitConversion.kgToLbs()`.
- Dark mode only — use DesignTokens colors.

**Prerequisite WPs provide**:
- WP01: SettingsService (rebuild orchestration), E1RMFormula enum
- WP02: SettingsView with NavigationLinks to RebuildStatsView and BodyweightLogView

**Existing code references**:
- `Reppo/Core/Services/BodyweightService.swift` — `saveEntry(bodyweightKg:date:)`, `fetchAllEntries()`, `deleteEntry(_:)`
- `Reppo/Core/Services/Protocols/BodyweightServiceProtocol.swift` — protocol definition
- `Reppo/Data/Models/BodyweightEntry.swift` — `id`, `healthProfileId`, `date`, `bodyweightKg`
- `Reppo/Core/Utils/UnitConversion.swift` — `kgToLbs()`, `lbsToKg()`, `formatDuration()`
- Charts tab views (feature 009) — reference for Swift Charts patterns in this codebase

## Subtasks & Detailed Guidance

### Subtask T013 – Create RebuildStatsView

**Purpose**: A dedicated screen for manual rebuild operations with clear explanation, confirmation, and progress feedback.

**Steps**:
1. Create `Reppo/Features/Settings/Views/RebuildStatsView.swift`.
2. Structure:
   ```swift
   import SwiftUI

   struct RebuildStatsView: View {
       let settingsService: any SettingsServiceProtocol
       @State private var isRebuilding = false
       @State private var rebuildStatusMessage = ""
       @State private var showConfirmation = false
       @State private var confirmationMessage = ""
       @State private var pendingRebuildAction: RebuildAction?
       @State private var showCompletion = false
       @State private var completionMessage = ""
       @State private var showError = false
       @State private var errorMessage = ""

       enum RebuildAction {
           case prs, stats, all
       }

       var body: some View {
           List {
               Section {
                   Text("Rebuild recomputes all stats and PRs from your raw workout data. Use this after importing data or if you notice any discrepancies.")
                       .font(.subheadline)
                       .foregroundStyle(Color.textSecondary)
               }

               Section {
                   Button("Rebuild PRs") {
                       pendingRebuildAction = .prs
                       confirmationMessage = "This will recompute all personal records from raw set data."
                       showConfirmation = true
                   }
                   Button("Rebuild Stats") {
                       pendingRebuildAction = .stats
                       confirmationMessage = "This will recompute all exercise statistics from raw set data."
                       showConfirmation = true
                   }
                   Button("Rebuild All") {
                       pendingRebuildAction = .all
                       confirmationMessage = "This will recompute all personal records and exercise statistics from raw set data."
                       showConfirmation = true
                   }
               }
           }
           .navigationTitle("Rebuild Stats")
           .scrollContentBackground(.hidden)
           .background(Color.bg)
           .overlay { /* progress overlay when isRebuilding */ }
           .alert("Confirm Rebuild", isPresented: $showConfirmation) { /* Cancel + Rebuild buttons */ }
           .alert("Rebuild Complete", isPresented: $showCompletion) { /* OK button */ }
           .alert("Rebuild Failed", isPresented: $showError) { /* OK button */ }
       }
   }
   ```
3. Progress overlay: When `isRebuilding == true`, show a centered card with `ProgressView()` and status message on a semi-transparent background. Use `.ignoresSafeArea()` on the overlay to block all interaction.
   ```swift
   .overlay {
       if isRebuilding {
           ZStack {
               Color.black.opacity(0.4)
               VStack(spacing: 16) {
                   ProgressView()
                       .tint(Color.accent)
                   Text(rebuildStatusMessage)
                       .font(.subheadline)
                       .foregroundStyle(Color.textPrimary)
               }
               .padding(32)
               .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 16))
           }
           .ignoresSafeArea()
       }
   }
   ```
4. Rebuild execution: On confirmation, run the appropriate method:
   ```swift
   private func executeRebuild() {
       guard let action = pendingRebuildAction else { return }
       Task {
           isRebuilding = true
           rebuildStatusMessage = "Rebuilding..."
           do {
               switch action {
               case .prs:
                   try await settingsService.rebuildPRs()
                   completionMessage = "All personal records have been recomputed."
               case .stats:
                   try await settingsService.rebuildStats()
                   completionMessage = "All exercise statistics have been recomputed."
               case .all:
                   try await settingsService.rebuildAll()
                   completionMessage = "All personal records and statistics have been recomputed."
               }
               isRebuilding = false
               showCompletion = true
           } catch {
               isRebuilding = false
               errorMessage = error.localizedDescription
               showError = true
           }
       }
   }
   ```

**Files**: `Reppo/Features/Settings/Views/RebuildStatsView.swift` (NEW, ~120 lines)

**Notes**:
- The modal overlay blocks all user interaction during rebuild. This prevents navigation or setting changes mid-rebuild.
- Per SC-003, rebuild for 12,000+ sets should complete within 30 seconds. Indeterminate spinner is appropriate.
- If rebuild throws, show error alert with the localized description. The user can retry.
- The `settingsService` can be passed via init from SettingsView's NavigationLink.

---

### Subtask T014 – Create BodyweightLogViewModel

**Purpose**: Manage bodyweight entry CRUD, provide data for the trend chart, and handle unit conversion for display.

**Steps**:
1. Create `Reppo/Features/Settings/ViewModels/BodyweightLogViewModel.swift`.
2. Define as `@Observable`:
   ```swift
   import Foundation

   @Observable
   final class BodyweightLogViewModel {
       var entries: [BodyweightEntry] = []
       var isLoading = true
       var showAddSheet = false
       var showError = false
       var errorMessage = ""
       var unitPreference: UnitPreference = .metric

       private let bodyweightService: any BodyweightServiceProtocol
       private let settingsService: any SettingsServiceProtocol

       init(bodyweightService: any BodyweightServiceProtocol,
            settingsService: any SettingsServiceProtocol) {
           self.bodyweightService = bodyweightService
           self.settingsService = settingsService
       }
   }
   ```
3. Implement methods:
   - `loadEntries()` — Fetch all entries via `bodyweightService.fetchAllEntries()`. Sort by date descending. Also fetch unit preference from `settingsService.fetchSettings()`.
   - `addEntry(weightKg: Double, date: Date)` — Save via `bodyweightService.saveEntry(bodyweightKg:date:)`. Reload entries.
   - `deleteEntry(_ entry: BodyweightEntry)` — Delete via `bodyweightService.deleteEntry(entry.id)`. Reload entries.
4. Computed helpers:
   - `displayWeight(for entry: BodyweightEntry) -> Double` — Convert to lbs if imperial.
   - `unitLabel: String` — "kg" or "lbs" based on preference.
   - `entriesForChart: [BodyweightEntry]` — Entries sorted by date ascending (for chart rendering).
   - `hasEntries: Bool` — `!entries.isEmpty`.

**Files**: `Reppo/Features/Settings/ViewModels/BodyweightLogViewModel.swift` (NEW, ~80 lines)

**Notes**:
- Entries for the list are date DESC (newest first). Entries for the chart are date ASC (left-to-right chronological).
- Weight input from the user should be in their preferred unit. Convert to kg before saving: if imperial, use `UnitConversion.lbsToKg()`.
- Error handling: wrap async calls in `do/catch`, show error alert on failure.

---

### Subtask T015 – Create BodyweightLogView

**Purpose**: Display the bodyweight log screen with trend chart at top, entry list below, and Add button in toolbar.

**Steps**:
1. Create `Reppo/Features/Settings/Views/BodyweightLogView.swift`.
2. Structure:
   ```swift
   import SwiftUI

   struct BodyweightLogView: View {
       @State private var viewModel: BodyweightLogViewModel

       init(bodyweightService: any BodyweightServiceProtocol,
            settingsService: any SettingsServiceProtocol) {
           _viewModel = State(initialValue: BodyweightLogViewModel(
               bodyweightService: bodyweightService,
               settingsService: settingsService
           ))
       }

       var body: some View {
           Group {
               if viewModel.isLoading {
                   ProgressView()
               } else if !viewModel.hasEntries {
                   emptyState
               } else {
                   ScrollView {
                       VStack(spacing: 16) {
                           chartSection
                           entryListSection
                       }
                       .padding()
                   }
               }
           }
           .navigationTitle("Bodyweight Log")
           .scrollContentBackground(.hidden)
           .background(Color.bg)
           .toolbar {
               ToolbarItem(placement: .primaryAction) {
                   Button { viewModel.showAddSheet = true } label: {
                       Image(systemName: "plus")
                   }
               }
           }
           .sheet(isPresented: $viewModel.showAddSheet) {
               AddBodyweightEntrySheet(
                   unitPreference: viewModel.unitPreference,
                   onSave: { weightKg, date in
                       Task { await viewModel.addEntry(weightKg: weightKg, date: date) }
                   }
               )
           }
           .task { await viewModel.loadEntries() }
       }
   }
   ```
3. **Empty state view**: Centered message encouraging first entry + prominent Add button:
   ```swift
   var emptyState: some View {
       VStack(spacing: 16) {
           Image(systemName: "scalemass")
               .font(.system(size: 48))
               .foregroundStyle(Color.textSecondary)
           Text("No Bodyweight Entries")
               .font(.headline)
           Text("Log your bodyweight to track trends and improve accuracy for bodyweight exercises.")
               .font(.subheadline)
               .foregroundStyle(Color.textSecondary)
               .multilineTextAlignment(.center)
           Button("Add Entry") { viewModel.showAddSheet = true }
               .buttonStyle(.borderedProminent)
       }
       .padding()
   }
   ```
4. **Entry list section**: List of entries with date + weight, swipe-to-delete (see T018).

**Files**: `Reppo/Features/Settings/Views/BodyweightLogView.swift` (NEW, ~130 lines)

**Notes**:
- Chart height: Fixed at ~200pt to fit above the entry list.
- Chart section and entry list both live in a `ScrollView` (not a `List`/`Form`), since combining a chart with a swipeable list in a `Form` can cause layout issues.
- The Add button should appear both in the toolbar AND in the empty state.

---

### Subtask T016 – Implement Bodyweight Trend Chart

**Purpose**: Render a line+point chart showing bodyweight history over time.

**Steps**:
1. In BodyweightLogView, implement the `chartSection` computed property:
   ```swift
   import Charts

   var chartSection: some View {
       Chart(viewModel.entriesForChart, id: \.id) { entry in
           let weight = viewModel.displayWeight(for: entry)

           LineMark(
               x: .value("Date", entry.date),
               y: .value("Weight", weight)
           )
           .foregroundStyle(Color.accent)
           .interpolationMethod(.catmullRom)

           PointMark(
               x: .value("Date", entry.date),
               y: .value("Weight", weight)
           )
           .foregroundStyle(Color.accent)
           .symbolSize(30)
       }
       .chartYScale(domain: .automatic(includesZero: false))
       .chartYAxis {
           AxisMarks { value in
               AxisValueLabel {
                   if let weight = value.as(Double.self) {
                       Text("\(weight, specifier: "%.0f") \(viewModel.unitLabel)")
                   }
               }
           }
       }
       .chartXAxis {
           AxisMarks(values: .stride(by: .month)) {
               AxisValueLabel(format: .dateTime.month(.abbreviated))
           }
       }
       .frame(height: 200)
       .padding(.vertical, 8)
   }
   ```

**Files**: `Reppo/Features/Settings/Views/BodyweightLogView.swift` (part of T015)

**Notes**:
- `chartYScale(domain: .automatic(includesZero: false))` — bodyweight charts must NOT start at zero. The Y axis should show meaningful variation.
- Use `.interpolationMethod(.catmullRom)` for a smooth line connecting data points.
- Unit conversion at display time: `viewModel.displayWeight(for:)` returns kg or lbs.
- Y-axis labels include the unit suffix ("kg" or "lbs").
- If only 1 entry exists, the chart shows just a single point (no line). This is acceptable.
- Chart uses `Color.accent` from DesignTokens for consistency with the Charts tab.

---

### Subtask T017 – Create Add Bodyweight Entry Sheet

**Purpose**: A sheet for entering a new bodyweight measurement with weight input and optional date picker.

**Steps**:
1. Create a view (can be within BodyweightLogView.swift or a separate file):
   ```swift
   struct AddBodyweightEntrySheet: View {
       let unitPreference: UnitPreference
       let onSave: (Double, Date) -> Void
       @Environment(\.dismiss) private var dismiss
       @State private var weightText = ""
       @State private var date = Date()

       var body: some View {
           NavigationStack {
               Form {
                   Section {
                       HStack {
                           TextField("Weight", text: $weightText)
                               .keyboardType(.decimalPad)
                           Text(unitPreference == .metric ? "kg" : "lbs")
                               .foregroundStyle(Color.textSecondary)
                       }
                   }
                   Section {
                       DatePicker("Date", selection: $date, displayedComponents: .date)
                   }
               }
               .scrollContentBackground(.hidden)
               .background(Color.bg)
               .navigationTitle("Add Bodyweight")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .cancellationAction) {
                       Button("Cancel") { dismiss() }
                   }
                   ToolbarItem(placement: .confirmationAction) {
                       Button("Save") {
                           guard let inputWeight = Double(weightText), inputWeight > 0 else { return }
                           let weightKg = unitPreference == .imperial
                               ? UnitConversion.lbsToKg(inputWeight)
                               : inputWeight
                           onSave(weightKg, date)
                           dismiss()
                       }
                       .disabled(Double(weightText) == nil || Double(weightText)! <= 0)
                   }
               }
           }
           .presentationDetents([.medium])
       }
   }
   ```

**Files**: Can be in `Reppo/Features/Settings/Views/BodyweightLogView.swift` or separate `Components/AddBodyweightEntrySheet.swift` (NEW, ~60 lines)

**Notes**:
- Weight input is in the user's preferred unit. Convert to kg before calling `onSave`.
- Date defaults to today. User can pick an earlier date for backdating entries.
- Validate: weight must be a positive number. Disable Save button if invalid.
- `.decimalPad` keyboard for weight input — allows decimal values.
- `.presentationDetents([.medium])` — the form is short.

---

### Subtask T018 – Implement Entry Deletion (Swipe-to-Delete)

**Purpose**: Allow users to remove bodyweight entries from the log.

**Steps**:
1. In the entry list section of BodyweightLogView, render each entry with swipe-to-delete:
   ```swift
   var entryListSection: some View {
       LazyVStack(spacing: 0) {
           ForEach(viewModel.entries, id: \.id) { entry in
               HStack {
                   Text(entry.date, style: .date)
                       .font(.subheadline)
                   Spacer()
                   Text("\(viewModel.displayWeight(for: entry), specifier: "%.1f") \(viewModel.unitLabel)")
                       .font(.subheadline)
                       .foregroundStyle(Color.textSecondary)
               }
               .padding(.horizontal)
               .padding(.vertical, 12)
               .background(Color.bgCard)
               .swipeActions(edge: .trailing) {
                   Button(role: .destructive) {
                       Task { await viewModel.deleteEntry(entry) }
                   } label: {
                       Label("Delete", systemImage: "trash")
                   }
               }
               Divider()
           }
       }
       .clipShape(RoundedRectangle(cornerRadius: 12))
   }
   ```

**Files**: `Reppo/Features/Settings/Views/BodyweightLogView.swift` (part of T015)

**Notes**:
- Entries are sorted by date descending (newest first) in the list view.
- Swipe-to-delete uses `.swipeActions` modifier with destructive role.
- After deletion, the chart and list both update (ViewModel reloads entries).
- No confirmation alert for individual entry deletion — swipe-to-delete is already a deliberate gesture.
- Note: `.swipeActions` requires `List` or `ForEach` inside a `List`. If using `LazyVStack`, you may need to use a `List` for the entry section or implement a custom swipe mechanism. The simplest approach is to use a `List` for the entries section.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Rebuild blocks UI for too long | Per SC-003, should complete < 30s for 12K+ sets. Modal overlay with ProgressView is appropriate. |
| Chart performance with many entries | ~365 entries max per year — trivial for Swift Charts. No optimization needed. |
| Unit conversion applied to stored data | All conversion is display-only. `bodyweightKg` column is never modified. |
| SwipeActions not working in ScrollView | Use `List` for the entry section, or `ForEach` within a `List`. Test swipe gesture. |
| Single entry chart rendering | Swift Charts handles single points gracefully — shows a dot, no line. Acceptable. |

## Definition of Done Checklist

- [ ] RebuildStatsView renders explanation text + 3 buttons
- [ ] Each rebuild button shows confirmation alert before executing
- [ ] Progress overlay appears during rebuild, blocks interaction
- [ ] Completion alert shows after successful rebuild
- [ ] Error alert shows on rebuild failure
- [ ] BodyweightLogViewModel loads entries and unit preference
- [ ] BodyweightLogView displays trend chart with LineMark + PointMark
- [ ] Chart Y-axis does not include zero, shows meaningful range
- [ ] Chart displays weights in user's preferred unit
- [ ] Entry list shows dates and weights, sorted newest first
- [ ] Add Entry sheet saves new bodyweight entry (converting from user unit to kg)
- [ ] Swipe-to-delete removes entries from list and chart
- [ ] Empty state shows when no entries exist
- [ ] NavigationLinks from SettingsView work correctly
- [ ] Project compiles with 0 errors

## Review Guidance

- Verify rebuild confirmation → progress → completion flow for all 3 buttons.
- Verify chart Y-axis uses `.automatic(includesZero: false)`.
- Verify unit conversion: entered lbs are stored as kg, displayed values convert back.
- Check that swipe-to-delete works and updates both list and chart.
- Verify empty state renders correctly with no bodyweight entries.
- Check dark mode styling consistency.

## Activity Log

- 2026-02-28T18:49:28Z – system – lane=planned – Prompt created.
- 2026-02-28T19:37:38Z – claude-opus – shell_pid=54403 – lane=doing – Started implementation via workflow command
- 2026-02-28T19:41:38Z – claude-opus – shell_pid=54403 – lane=for_review – Ready for review: RebuildStatsView with 3 rebuild buttons and progress overlay (T013), BodyweightLogViewModel (T014), BodyweightLogView with Swift Charts trend chart (T015/T016), AddBodyweightEntrySheet (T017), swipe-to-delete (T018). SettingsView updated with real NavigationLinks and bodyweightService param. Build 0 errors.
- 2026-02-28T19:42:41Z – claude-opus-reviewer – shell_pid=56223 – lane=doing – Started review via workflow command
- 2026-02-28T19:43:29Z – claude-opus-reviewer – shell_pid=56223 – lane=done – Review passed: All 6 subtasks verified — RebuildStatsView with 3 buttons/confirmation/progress/completion flow, BodyweightLogViewModel with CRUD and unit conversion, BodyweightLogView with Swift Charts trend chart (includesZero:false, catmullRom), AddBodyweightEntrySheet with lbs→kg conversion, swipe-to-delete via List+onDelete, empty state. SettingsView NavigationLinks wired. Build 0 errors.
