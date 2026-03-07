---
work_package_id: "WP05"
subtasks:
  - "T026"
  - "T027"
  - "T028"
  - "T029"
  - "T030"
title: "Integration + App Wiring"
phase: "Phase 3 - Integration"
lane: "done"
assignee: ""
agent: "claude-reviewer"
shell_pid: "62107"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: ["WP02", "WP03", "WP04"]
history:
  - timestamp: "2026-02-28T18:49:28Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP05 – Integration + App Wiring

## Implementation Command

```bash
spec-kitty implement WP05 --base WP04
```

**Note**: WP05 depends on WP02, WP03, and WP04. The `--base` flag should reference the branch that includes all prior WPs merged. If WP02/WP03/WP04 branches are sequential (WP01 → WP02 → WP03, WP01 → WP04), you may need to merge them first or use the latest branch that contains all changes.

## Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

Wire all Settings and Onboarding components into the app entry point:

1. **ReppoApp.swift** — Add `@AppStorage("hasCompletedOnboarding")` conditional to show onboarding or main app.
2. **ContentView.swift** — Replace `SettingsPlaceholderView` with the real `SettingsView`.
3. **Dependency wiring** — Pass required services from ServiceContainer to all new views.
4. **project.pbxproj** — Add all new file references to the Xcode project.
5. **Build verification** — Ensure 0 compile errors.

**Success criteria**:
- App launches. First launch: onboarding flow appears.
- Complete onboarding → arrive at Calendar tab.
- Re-launch: onboarding does NOT appear.
- Tap Settings tab: see full SettingsView with all 5 sections.
- Navigate to Rebuild Stats and Bodyweight Log from Settings.
- Build succeeds with 0 errors on all targets.

## Context & Constraints

**Design documents**:
- `kitty-specs/010-settings-and-onboarding/plan.md` — view hierarchy, data flow, ReppoApp structure
- `kitty-specs/010-settings-and-onboarding/research.md` — RQ-1 (onboarding persistence, `if/else` approach)
- `kitty-specs/010-settings-and-onboarding/quickstart.md` — wiring checklist, file structure

**Architecture rules**:
- `@AppStorage("hasCompletedOnboarding")` in ReppoApp for synchronous first-launch detection.
- `if/else` in ReppoApp body (NOT `.fullScreenCover`) — avoids flash of ContentView.
- Services are injected via init parameters or SwiftUI environment.
- ServiceContainer is already created in ReppoApp.init() and passed via `.environment()`.

**Prerequisite WPs provide**:
- WP01: `SettingsService` in ServiceContainer
- WP02: `SettingsView`, `SettingsViewModel`, picker sheets
- WP03: `RebuildStatsView`, `BodyweightLogView`, `BodyweightLogViewModel`
- WP04: `OnboardingContainerView`, `OnboardingViewModel`, step views

**Existing code references**:
- `Reppo/App/ReppoApp.swift` — current structure: `modelContainer`, `repositories`, `services` created in `init()`
- `Reppo/App/ContentView.swift` — `SettingsPlaceholderView()` at ~line 64 in Settings tab
- `Reppo/Features/Exercise/Views/TabPlaceholderViews.swift` — `SettingsPlaceholderView` definition at ~line 61

## Subtasks & Detailed Guidance

### Subtask T026 – Add @AppStorage Onboarding Gate in ReppoApp.swift

**Purpose**: Conditionally show onboarding on first launch, main app on subsequent launches.

**Steps**:
1. Open `Reppo/App/ReppoApp.swift`.
2. Add the `@AppStorage` property:
   ```swift
   @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
   ```
3. Modify the `body` to conditionally show onboarding:
   ```swift
   var body: some Scene {
       WindowGroup {
           if hasCompletedOnboarding {
               ContentView()
                   // ... existing environment modifiers
           } else {
               OnboardingContainerView(
                   settingsService: services.settingsService,
                   bodyweightService: services.bodyweightService,
                   onComplete: {
                       hasCompletedOnboarding = true
                   }
               )
               // ... same environment modifiers as ContentView
           }
       }
       .modelContainer(modelContainer)
       // ... existing modifiers
   }
   ```

**Files**: `Reppo/App/ReppoApp.swift` (MODIFY)

**Notes**:
- The `if/else` approach is preferred over `.fullScreenCover` — it prevents a brief flash of ContentView before the cover appears (see research.md RQ-1).
- Both branches need the same `.modelContainer()` and `.environment()` modifiers so services/repos are available to both onboarding and main app.
- The `onComplete` closure sets `hasCompletedOnboarding = true` which triggers SwiftUI to re-evaluate the body and show `ContentView`.
- After onboarding completes, the user should land on the Calendar tab (the default tab in ContentView).

---

### Subtask T027 – Replace SettingsPlaceholderView in ContentView

**Purpose**: Swap the placeholder Settings tab content with the real SettingsView.

**Steps**:
1. Open `Reppo/App/ContentView.swift`.
2. Find the Settings tab section (currently using `SettingsPlaceholderView()`).
3. Replace with `SettingsView(settingsService:)`:
   ```swift
   // Before:
   SettingsPlaceholderView()
       .tabItem {
           Label("Settings", systemImage: "gearshape")
       }
       .tag(MainTab.settings)

   // After:
   SettingsView(settingsService: services.settingsService)
       .tabItem {
           Label("Settings", systemImage: "gearshape")
       }
       .tag(MainTab.settings)
   ```
4. Ensure `services` is accessible in ContentView (it should already be available via `@Environment` or passed through).

**Files**: `Reppo/App/ContentView.swift` (MODIFY)

**Notes**:
- Check how `services` (ServiceContainer) is accessed in ContentView. It may be via `@Environment(ServiceContainer.self)` or passed as an init parameter. Follow the existing pattern.
- The SettingsView init needs `settingsService`. The SettingsView internally creates its own `SettingsViewModel`.
- If SettingsView also needs to pass services to sub-screens (BodyweightLogView, RebuildStatsView), those are handled internally via NavigationLink targets within SettingsView.
- Optionally: Remove or clean up the `SettingsPlaceholderView` definition in `TabPlaceholderViews.swift` if it's no longer referenced anywhere.

---

### Subtask T028 – Wire Dependencies to Settings + Onboarding Views

**Purpose**: Ensure all views have access to the services they need.

**Steps**:
1. **SettingsView** needs:
   - `SettingsServiceProtocol` (for SettingsViewModel)
   - Internally, NavigationLinks to sub-screens need:
     - `RebuildStatsView` needs: `SettingsServiceProtocol` (for rebuild operations)
     - `BodyweightLogView` needs: `BodyweightServiceProtocol` + `SettingsServiceProtocol` (for CRUD + unit preference)

2. **OnboardingContainerView** needs:
   - `SettingsServiceProtocol` (save preferences)
   - `BodyweightServiceProtocol` (save optional bodyweight entry)

3. Review how services are passed:
   - Option A: Pass services via init parameters (explicit, clear dependencies).
   - Option B: Use `@Environment(ServiceContainer.self)` to access services in views.
   - Follow whichever pattern the existing codebase uses.

4. Verify all ViewModel inits receive their required services:
   - `SettingsViewModel(settingsService:)`
   - `BodyweightLogViewModel(bodyweightService:, settingsService:)`
   - `OnboardingViewModel(settingsService:, bodyweightService:)`

**Files**: Multiple (depends on how views are structured — may need to pass services through NavigationLinks)

**Notes**:
- If using environment-based injection, ensure `ServiceContainer` is in the environment before any view that needs it.
- If using init-based injection, SettingsView's NavigationLinks need to capture the services and pass them to sub-screens.
- Check for any missing service dependencies that would cause compile errors.

---

### Subtask T029 – Add New File References to project.pbxproj

**Purpose**: Register all new Swift files in the Xcode project so they compile.

**Steps**:
1. Add all new files to `Reppo.xcodeproj/project.pbxproj`. The new files are:
   ```
   # Data layer (WP01)
   Reppo/Data/Enums/E1RMFormula.swift

   # Service layer (WP01)
   Reppo/Core/Services/SettingsService.swift
   Reppo/Core/Services/Protocols/SettingsServiceProtocol.swift

   # Settings feature (WP02 + WP03)
   Reppo/Features/Settings/ViewModels/SettingsViewModel.swift
   Reppo/Features/Settings/ViewModels/BodyweightLogViewModel.swift
   Reppo/Features/Settings/Views/SettingsView.swift
   Reppo/Features/Settings/Views/BodyweightLogView.swift
   Reppo/Features/Settings/Views/RebuildStatsView.swift
   Reppo/Features/Settings/Views/Components/UnitPickerSheet.swift
   Reppo/Features/Settings/Views/Components/FormulaPickerSheet.swift
   Reppo/Features/Settings/Views/Components/RestTimePickerSheet.swift

   # Onboarding feature (WP04)
   Reppo/Features/Onboarding/OnboardingStep.swift
   Reppo/Features/Onboarding/ViewModels/OnboardingViewModel.swift
   Reppo/Features/Onboarding/Views/OnboardingContainerView.swift
   Reppo/Features/Onboarding/Views/WelcomeStepView.swift
   Reppo/Features/Onboarding/Views/UnitsStepView.swift
   Reppo/Features/Onboarding/Views/FormulaStepView.swift
   Reppo/Features/Onboarding/Views/BodyweightStepView.swift
   Reppo/Features/Onboarding/Views/ImportStepView.swift
   ```
2. For each file, add:
   - A `PBXFileReference` entry with the correct path
   - A `PBXBuildFile` entry linking to the file reference
   - Add the build file to the `PBXSourcesBuildPhase`
   - Add the file reference to the appropriate `PBXGroup`

**Files**: `Reppo.xcodeproj/project.pbxproj` (MODIFY)

**Notes**:
- Generate unique UUIDs (24-character hex) for each new reference. Do NOT reuse existing UUIDs.
- Follow the existing patterns in the file for formatting and ordering.
- Place files in the correct group hierarchy matching the directory structure.
- This is the most error-prone step — a malformed pbxproj will prevent the project from opening in Xcode.
- Alternative: If using `xcodegen` or `tuist`, update the project manifest instead. Check if either is in use in this project.

---

### Subtask T030 – Build Verification

**Purpose**: Confirm the project compiles with 0 errors after all wiring.

**Steps**:
1. Run a build:
   ```bash
   xcodebuild build \
     -project Reppo.xcodeproj \
     -scheme Reppo \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     -quiet
   ```
   Or open in Xcode and build (Cmd+B).
2. Verify: **0 errors**.
3. If there are errors, fix them:
   - Missing imports → add `import SwiftUI`, `import Charts`, `import Foundation` as needed.
   - Missing file references → check pbxproj entries.
   - Type mismatches → verify protocol conformance and init signatures.
   - Missing dependencies → ensure all services are passed correctly.

**Files**: None (verification step)

**Notes**:
- Warnings are acceptable for now (e.g., unused variables). Focus on 0 errors.
- If the build fails on pbxproj issues, it may be easier to add files via Xcode's "Add Files to Project" workflow.
- Verify the Settings tab shows the real SettingsView, not the placeholder.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| project.pbxproj corruption | Make small, precise edits. Backup before modifying. Verify project opens in Xcode after each change. |
| Missing dependency injection | Compile early and often. Fix missing parameters immediately. |
| @AppStorage key typo | Use the exact string `"hasCompletedOnboarding"` everywhere. Consider extracting to a constant. |
| ContentView flash before onboarding | Use `if/else` in ReppoApp (not `.fullScreenCover`). Verified approach per research.md RQ-1. |
| SettingsPlaceholderView still referenced | Search codebase for remaining references after replacement. Remove if unused. |

## Definition of Done Checklist

- [ ] ReppoApp.swift has `@AppStorage("hasCompletedOnboarding")` conditional
- [ ] First launch shows OnboardingContainerView
- [ ] Completing onboarding shows ContentView (Calendar tab)
- [ ] Re-launch skips onboarding
- [ ] ContentView Settings tab shows real SettingsView (not placeholder)
- [ ] SettingsView NavigationLinks work (Rebuild Stats, Bodyweight Log)
- [ ] All services correctly injected into views and ViewModels
- [ ] All ~18 new Swift files referenced in project.pbxproj
- [ ] Project builds with 0 errors
- [ ] No flash of ContentView before onboarding on first launch

## Review Guidance

- Test the full first-launch flow: app opens → onboarding → complete → Calendar tab.
- Verify re-launch skips onboarding.
- Navigate through all Settings sections and sub-screens.
- Check that no `SettingsPlaceholderView` references remain in active code paths.
- Verify `@AppStorage` key string is consistent across all usage sites.
- Build the project and confirm 0 errors, 0 linker issues.

## Activity Log

- 2026-02-28T18:49:28Z – system – lane=planned – Prompt created.
- 2026-02-28T19:51:52Z – claude-opus – shell_pid=59377 – lane=doing – Started implementation via workflow command
- 2026-02-28T19:58:52Z – claude-opus – shell_pid=59377 – lane=for_review – Ready for review: ReppoApp @AppStorage onboarding gate (T026), SettingsPlaceholderView → real SettingsView (T027), service dependency wiring (T028), pbxproj merge-resolved with all 18 files (T029), build 0 errors (T030). Removed dead SettingsPlaceholderView.
- 2026-02-28T19:59:43Z – claude-reviewer – shell_pid=62107 – lane=doing – Started review via workflow command
- 2026-02-28T20:00:49Z – claude-reviewer – shell_pid=62107 – lane=done – Review passed
