---
work_package_id: "WP02"
subtasks:
  - "T006"
  - "T007"
  - "T008"
  - "T009"
  - "T010"
  - "T011"
  - "T012"
title: "Settings Screen — Main View + ViewModel + Pickers"
phase: "Phase 2 - Settings UI"
lane: "done"
assignee: ""
agent: "claude-opus-reviewer"
shell_pid: "53821"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-28T18:49:28Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP02 – Settings Screen — Main View + ViewModel + Pickers

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

Build the main Settings screen with all 5 sections and 3 picker sheet components:

1. **SettingsViewModel** — `@Observable` class that manages settings state and actions via SettingsService.
2. **SettingsView** — `Form`-based UI with 5 sections: GENERAL, WORKOUT PREFERENCES, DATA, BODY, ABOUT.
3. **UnitPickerSheet** — metric/imperial selection sheet.
4. **FormulaPickerSheet** — e1RM formula picker with descriptions.
5. **RestTimePickerSheet** — default rest time selection.
6. **Warmup toggle confirmation** — alerts before triggering rebuild.
7. **About section** — version display + Send Feedback mailto link.

**Success criteria**:
- Settings tab renders all 5 sections with correct row labels and controls.
- Units and e1RM Formula rows open picker sheets. Selection persists to HealthProfile.
- Warmup toggles show confirmation alert before saving + triggering rebuild.
- CSV Import/Export buttons show "Coming Soon" alert.
- Rebuild Stats and Bodyweight Log rows are NavigationLinks (targets built in WP03).
- About section shows app version and Send Feedback opens mail client.

## Context & Constraints

**Design documents**:
- `kitty-specs/010-settings-and-onboarding/plan.md` — view hierarchy, component architecture, SettingsViewModel spec
- `kitty-specs/010-settings-and-onboarding/research.md` — RQ-3 (Form patterns), RQ-7 (unit propagation), RQ-8 (Send Feedback)
- `kitty-specs/010-settings-and-onboarding/data-model.md` — HealthProfile fields, E1RMFormula enum
- `kitty-specs/010-settings-and-onboarding/spec.md` — User Stories 1-2, acceptance scenarios

**Architecture rules**:
- SwiftUI Form with Section headers for grouped settings.
- `.scrollContentBackground(.hidden)` + `.background(Color.bg)` for dark mode.
- Units and e1RM Formula open as `.sheet` (per screen_tree `[sheet]` annotation).
- Deeper screens (Bodyweight Log, Rebuild Stats) use `NavigationLink`.
- SettingsViewModel is `@Observable`, fetches HealthProfile via SettingsService on `.task {}`.
- No `ModelContext` in ViewModel — all data via SettingsService.

**Prerequisite WP01 provides**:
- `SettingsServiceProtocol` / `SettingsService` (fetching, updating, rebuild orchestration)
- `E1RMFormula` enum (formula cases, display names, descriptions)
- `HealthProfile.defaultRestTimeSeconds` field
- `ServiceContainer.settingsService` wiring

## Subtasks & Detailed Guidance

### Subtask T006 – Create SettingsViewModel

**Purpose**: Manage all settings state and actions. The single ViewModel for the main settings screen.

**Steps**:
1. Create `Reppo/Features/Settings/ViewModels/SettingsViewModel.swift`.
2. Define as `@Observable`:
   ```swift
   import Foundation

   @Observable
   final class SettingsViewModel {
       // State
       var profile: HealthProfile?
       var isLoading = true
       var isRebuilding = false
       var rebuildProgress: String?
       var showError = false
       var errorMessage = ""

       // Sheet/Alert presentation state
       var showUnitsSheet = false
       var showFormulaSheet = false
       var showRestTimeSheet = false
       var showComingSoonAlert = false
       var showRebuildVolumeConfirmation = false
       var showRebuildPRsConfirmation = false

       // Dependencies
       private let settingsService: any SettingsServiceProtocol

       init(settingsService: any SettingsServiceProtocol) {
           self.settingsService = settingsService
       }
   }
   ```
3. Add methods:
   - `loadProfile()` — async, fetches via `settingsService.fetchSettings()`, sets `profile`, clears `isLoading`.
   - `updateUnitPreference(_ preference: UnitPreference)` — async, calls service, reloads profile.
   - `updateE1RMFormula(_ formula: E1RMFormula)` — async, calls service, reloads profile.
   - `updateDefaultRestTime(_ seconds: Int?)` — async, calls service, reloads profile.
   - `confirmToggleWarmupVolume()` — sets `showRebuildVolumeConfirmation = true`.
   - `toggleWarmupVolume()` — async, calls `settingsService.updateIncludeWarmupsInVolume(!currentValue)`, shows progress, reloads.
   - `confirmToggleWarmupPRs()` — sets `showRebuildPRsConfirmation = true`.
   - `toggleWarmupPRs()` — async, calls `settingsService.updateIncludeWarmupsInPRs(!currentValue)`, shows progress, reloads.
   - `sendFeedback()` — opens mailto: URL with version info.
4. Computed helpers:
   - `unitDisplayName: String` — `profile?.unitPreference.rawValue.capitalized ?? "Metric"`
   - `formulaDisplayName: String` — `E1RMFormula(rawValue: profile?.e1RMFormula ?? "epley")?.displayName ?? "Epley"`
   - `restTimeDisplayName: String` — format `profile?.defaultRestTimeSeconds` or "Not Set"
   - `appVersion: String` — from `Bundle.main.infoDictionary`

**Files**: `Reppo/Features/Settings/ViewModels/SettingsViewModel.swift` (NEW, ~120 lines)

**Notes**:
- Error handling: wrap service calls in `do/catch`, set `errorMessage` and `showError` on failure.
- For warmup toggles: the confirmation flow is `user taps toggle -> show confirmation alert -> if confirmed, call service (which saves + rebuilds) -> reload profile`. If cancelled, do NOT change the toggle state.
- `isRebuilding` should be `true` during warmup toggle operations (which trigger rebuilds).

---

### Subtask T007 – Create SettingsView

**Purpose**: The main settings screen with Form layout and 5 sections.

**Steps**:
1. Create `Reppo/Features/Settings/Views/SettingsView.swift`.
2. Structure:
   ```swift
   import SwiftUI

   struct SettingsView: View {
       @State private var viewModel: SettingsViewModel

       init(settingsService: any SettingsServiceProtocol) {
           _viewModel = State(initialValue: SettingsViewModel(settingsService: settingsService))
       }

       var body: some View {
           NavigationStack {
               Form {
                   generalSection
                   workoutPreferencesSection
                   dataSection
                   bodySection
                   aboutSection
               }
               .scrollContentBackground(.hidden)
               .background(Color.bg)
               .navigationTitle("Settings")
               .task { await viewModel.loadProfile() }
           }
       }
   }
   ```
3. Implement each section as a computed property:

   **GENERAL section**:
   - Units row: Button that shows current unit, opens `UnitPickerSheet` via `.sheet`.
   - e1RM Formula row: Button that shows current formula name, opens `FormulaPickerSheet` via `.sheet`.
   - Both rows use `HStack { Label; Spacer(); currentValue }` pattern with chevron indicator.

   **WORKOUT PREFERENCES section**:
   - "Include Warmups in Volume" — Toggle bound to a local state derived from `viewModel.profile?.includeWarmupsInVolume`. On change, call `viewModel.confirmToggleWarmupVolume()`.
   - "Include Warmups in PRs" — Same pattern, calls `viewModel.confirmToggleWarmupPRs()`.
   - "Default Rest Time" — Button that shows current value, opens `RestTimePickerSheet`.

   **DATA section**:
   - "Import Data (CSV)" — Button, shows "Coming Soon" alert.
   - "Export Data (CSV)" — Button, shows "Coming Soon" alert.
   - "Rebuild Stats" — `NavigationLink` to `RebuildStatsView(settingsService:)`. (RebuildStatsView created in WP03; use placeholder `Text("Rebuild Stats")` if needed.)

   **BODY section**:
   - "Bodyweight Log" — `NavigationLink` to `BodyweightLogView(...)`. (Created in WP03; use placeholder if needed.)

   **ABOUT section**:
   - Version row: `HStack { Text("Version"); Spacer(); Text(viewModel.appVersion) }`.
   - "Send Feedback" — Button, calls `viewModel.sendFeedback()`.

4. Add sheet modifiers for the 3 pickers.
5. Add alert modifiers for warmup rebuild confirmations and "Coming Soon".
6. Add error alert for service failures.

**Files**: `Reppo/Features/Settings/Views/SettingsView.swift` (NEW, ~200 lines)

**Notes**:
- Use SF Symbols for section row icons: `Image(systemName: "scalemass")` for Units, `Image(systemName: "function")` for e1RM, etc.
- Form rows should have `.foregroundStyle(Color.textPrimary)` for labels, `.foregroundStyle(Color.textSecondary)` for current values.
- The warmup toggles should NOT use standard `Toggle` binding directly to the profile, because the toggle change needs a confirmation step. Instead, use a local `@State` or compute the binding to intercept changes.
- NavigationLinks to WP03 sub-screens: If those views don't exist yet in the worktree, use a simple placeholder `Text("Coming Soon")` view. WP03 will build the real views.

---

### Subtask T008 – Create UnitPickerSheet

**Purpose**: A sheet for selecting between metric and imperial units.

**Steps**:
1. Create `Reppo/Features/Settings/Views/Components/UnitPickerSheet.swift`.
2. Structure:
   ```swift
   struct UnitPickerSheet: View {
       let currentUnit: UnitPreference
       let onSelect: (UnitPreference) -> Void
       @Environment(\.dismiss) private var dismiss

       var body: some View {
           NavigationStack {
               List {
                   ForEach(UnitPreference.allCases, id: \.self) { unit in
                       Button {
                           onSelect(unit)
                           dismiss()
                       } label: {
                           HStack {
                               VStack(alignment: .leading) {
                                   Text(unit == .metric ? "Metric" : "Imperial")
                                   Text(unit == .metric ? "Kilograms (kg)" : "Pounds (lbs)")
                                       .font(.caption)
                                       .foregroundStyle(Color.textSecondary)
                               }
                               Spacer()
                               if unit == currentUnit {
                                   Image(systemName: "checkmark")
                                       .foregroundStyle(Color.accent)
                               }
                           }
                       }
                   }
               }
               .navigationTitle("Units")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .cancellationAction) {
                       Button("Cancel") { dismiss() }
                   }
               }
           }
           .presentationDetents([.medium])
       }
   }
   ```

**Files**: `Reppo/Features/Settings/Views/Components/UnitPickerSheet.swift` (NEW, ~45 lines)

**Parallel?**: Yes — independent from other picker sheets.

**Notes**:
- Use `.presentationDetents([.medium])` — the content is short.
- Checkmark indicates current selection.
- On select: callback fires, sheet dismisses. SettingsView handles the async save.

---

### Subtask T009 – Create FormulaPickerSheet

**Purpose**: A sheet for selecting the e1RM formula with plain-English descriptions.

**Steps**:
1. Create `Reppo/Features/Settings/Views/Components/FormulaPickerSheet.swift`.
2. Structure similar to UnitPickerSheet but with 3 options:
   - Iterate over `E1RMFormula.allCases`.
   - Show `formula.displayName` as title and `formula.description` as subtitle.
   - Checkmark for current selection.
3. Callback: `let onSelect: (E1RMFormula) -> Void`.

**Files**: `Reppo/Features/Settings/Views/Components/FormulaPickerSheet.swift` (NEW, ~50 lines)

**Parallel?**: Yes — independent from other picker sheets.

**Notes**:
- The descriptions should help users understand each formula without needing math knowledge.
- Changing the formula does NOT trigger any rebuild — future sets use the new formula; existing sets keep their `e1RMFormulaVersion`.

---

### Subtask T010 – Create RestTimePickerSheet

**Purpose**: A sheet for selecting the default rest time between sets.

**Steps**:
1. Create `Reppo/Features/Settings/Views/Components/RestTimePickerSheet.swift`.
2. Preset values: `[nil, 30, 60, 90, 120, 150, 180, 240, 300]` seconds.
3. Display format: Use `UnitConversion.formatDuration()` if available, or manually format:
   - `nil` → "Not Set"
   - `30` → "30s"
   - `60` → "1 min"
   - `90` → "1m 30s"
   - `120` → "2 min"
   - `180` → "3 min"
   - `240` → "4 min"
   - `300` → "5 min"
4. Callback: `let onSelect: (Int?) -> Void`.
5. Checkmark for current selection. `nil` option at top labeled "Not Set".

**Files**: `Reppo/Features/Settings/Views/Components/RestTimePickerSheet.swift` (NEW, ~55 lines)

**Parallel?**: Yes — independent from other picker sheets.

**Notes**:
- The "Not Set" option (`nil`) means no global default — rest timer uses exercise-specific value or no timer.
- Check if `UnitConversion.formatDuration(_:)` exists in the codebase. If yes, use it. If not, format manually.

---

### Subtask T011 – Add Warmup Toggle Rebuild Confirmation Dialogs

**Purpose**: When the user toggles "Include Warmups in Volume" or "Include Warmups in PRs", show a confirmation alert explaining the rebuild consequence before proceeding.

**Steps**:
1. In SettingsView, the warmup toggles must intercept changes:
   - Instead of binding directly to `viewModel.profile?.includeWarmupsInVolume`, use a computed `Binding` that triggers the confirmation flow on change.
   - Pattern:
     ```swift
     Toggle("Include Warmups in Volume", isOn: Binding(
         get: { viewModel.profile?.includeWarmupsInVolume ?? false },
         set: { _ in viewModel.confirmToggleWarmupVolume() }
     ))
     ```
2. Add `.alert` modifiers for both confirmations:
   ```swift
   .alert("Rebuild Volume Stats?", isPresented: $viewModel.showRebuildVolumeConfirmation) {
       Button("Cancel", role: .cancel) {}
       Button("Rebuild") {
           Task { await viewModel.toggleWarmupVolume() }
       }
   } message: {
       Text("This will recompute all volume statistics. This may take a moment.")
   }
   ```
3. Same pattern for warmup PRs with message: "This will rebuild all personal records. This may take a moment."
4. During rebuild: `viewModel.isRebuilding = true`. Show a subtle ProgressView or disable interaction.

**Files**: `Reppo/Features/Settings/Views/SettingsView.swift` (part of T007 implementation)

**Notes**:
- The toggle visual state must NOT change until the rebuild completes. If the user cancels, the toggle stays at its original position.
- After successful toggle + rebuild, reload the profile to reflect the new state.
- If the rebuild fails, show an error alert and revert the toggle state.

---

### Subtask T012 – Wire About Section (Version + Send Feedback)

**Purpose**: Display app version info and provide a feedback mechanism via mailto: link.

**Steps**:
1. In SettingsViewModel, implement `sendFeedback()`:
   ```swift
   func sendFeedback() {
       let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
       let subject = "Reppo Feedback"
       let body = "\n\n---\nApp Version: \(version) (\(build))\niOS: \(UIDevice.current.systemVersion)"

       let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
       let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

       if let url = URL(string: "mailto:feedback@reppo.app?subject=\(encodedSubject)&body=\(encodedBody)") {
           UIApplication.shared.open(url)
       }
   }
   ```
2. In SettingsViewModel, implement `appVersion: String`:
   ```swift
   var appVersion: String {
       let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
       return "\(version) (\(build))"
   }
   ```
3. In SettingsView ABOUT section:
   - Version row: non-interactive `HStack` with label and value.
   - Send Feedback row: `Button` that calls `viewModel.sendFeedback()`.

**Files**: `Reppo/Features/Settings/ViewModels/SettingsViewModel.swift` (part of T006), `Reppo/Features/Settings/Views/SettingsView.swift` (part of T007)

**Notes**:
- `UIApplication.shared.open()` requires `import UIKit`. In SwiftUI files, use `@Environment(\.openURL)` as an alternative.
- The email address can be a placeholder (`feedback@reppo.app`) — the actual address is a product decision.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Warmup toggle visual state desyncs | Use computed Binding that only updates after confirmation + service call succeeds |
| Form styling inconsistent with app theme | Use `.scrollContentBackground(.hidden)` + `.background(Color.bg)`, verify all text uses DesignTokens colors |
| NavigationLinks to WP03 views that don't exist yet | Use placeholder views; WP03 replaces them |
| Send Feedback fails silently when no mail app | Acceptable for v1; check `canOpenURL` in future |

## Definition of Done Checklist

- [ ] SettingsViewModel created with all methods and state properties
- [ ] SettingsView renders all 5 sections (GENERAL, WORKOUT PREFERENCES, DATA, BODY, ABOUT)
- [ ] UnitPickerSheet opens from Units row, selection persists
- [ ] FormulaPickerSheet opens from e1RM row, shows descriptions, selection persists
- [ ] RestTimePickerSheet opens from Default Rest Time row, selection persists
- [ ] Warmup toggles show confirmation alert before triggering rebuild
- [ ] CSV Import/Export buttons show "Coming Soon" alert
- [ ] Rebuild Stats row is a NavigationLink (target can be placeholder)
- [ ] Bodyweight Log row is a NavigationLink (target can be placeholder)
- [ ] Version displays correctly in About section
- [ ] Send Feedback opens mailto: URL
- [ ] Dark mode styling applied (scrollContentBackground hidden, design token colors)
- [ ] Project compiles with 0 errors

## Review Guidance

- Verify warmup toggle confirmation flow: tap -> alert -> confirm -> rebuild -> profile reload.
- Verify that cancelling warmup toggle confirmation does NOT change the toggle state.
- Check that all Form sections match the spec's section layout (GENERAL, WORKOUT PREFERENCES, DATA, BODY, ABOUT).
- Verify picker sheets dismiss after selection and SettingsView reflects the change.
- Check dark mode styling: `.scrollContentBackground(.hidden)`, colors from DesignTokens.

## Activity Log

- 2026-02-28T18:49:28Z – system – lane=planned – Prompt created.
- 2026-02-28T19:27:56Z – claude-opus – shell_pid=51147 – lane=doing – Started implementation via workflow command
- 2026-02-28T19:34:09Z – claude-opus – shell_pid=51147 – lane=for_review – Ready for review: SettingsViewModel (T006), SettingsView with 5 sections (T007), UnitPickerSheet (T008), FormulaPickerSheet (T009), RestTimePickerSheet (T010), warmup confirmation alerts (T011), About section with version+feedback (T012). Build succeeds 0 errors.
- 2026-02-28T19:35:47Z – claude-opus-reviewer – shell_pid=53821 – lane=doing – Started review via workflow command
- 2026-03-01T08:20:48Z – claude-opus-reviewer – shell_pid=53821 – lane=done – Correcting lane: WP02 was reviewed and approved in prior session
