# Implementation Plan: Settings + Onboarding

**Branch**: `010-settings-and-onboarding` | **Date**: 2026-02-28 | **Spec**: `kitty-specs/010-settings-and-onboarding/spec.md`
**Input**: Feature specification from `kitty-specs/010-settings-and-onboarding/spec.md`

## Summary

Build the Settings tab (5 sections: General, Workout Preferences, Data, Body, About) and a 5-screen first-launch onboarding flow. Settings manages user preferences on the existing `HealthProfile` model (units, e1RM formula, warmup toggles, default rest time) with rebuild orchestration when warmup settings change. CSV Import/Export buttons are stubbed (feature 011). Bodyweight Log adds a trend chart + entry list backed by the existing `BodyweightService`. Onboarding uses `@AppStorage("hasCompletedOnboarding")` for first-launch detection and saves preferences to `HealthProfile`. A new `SettingsService` wraps HealthProfile CRUD and rebuild coordination. A new `E1RMFormula` enum provides type-safe formula selection with `calculate()` methods.

## Technical Context

**Language/Version**: Swift (latest stable), iOS 17.0+
**Primary Dependencies**: SwiftUI, SwiftData, Swift Charts (bodyweight trend chart only)
**Storage**: SwiftData — reads/writes existing HealthProfile + BodyweightEntry models
**Testing**: Manual testing for v1 (per constitution)
**Target Platform**: iOS 17.0+, iPhone only
**Project Type**: Mobile (single platform)
**Performance Goals**: Rebuild All completes within 30 seconds for 12,000+ sets (SC-003), unit switch immediately updates displayed weights (SC-001), onboarding completes in under 2 minutes (SC-002)
**Constraints**: Dark mode only, no third-party libs, MVVM architecture, no startup rebuild, store metric only (convert in UI)
**Scale/Scope**: Single-row HealthProfile, ~365 bodyweight entries max (daily for ~1 year), rebuild scans all sets via database aggregation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| SwiftUI primary, UIKit only if needed | PASS | All views in SwiftUI. UIKit only for `UIApplication.shared.open()` (mailto) and tab bar appearance |
| MVVM: View → ViewModel → Service → Repository → SwiftData | PASS | SettingsView → SettingsViewModel → SettingsService → HealthProfileRepository |
| @Observable for ViewModels (not ObservableObject) | PASS | SettingsViewModel, BodyweightLogViewModel, OnboardingViewModel all use @Observable |
| No third-party UI libraries | PASS | Swift Charts for bodyweight trend, all native |
| No ModelContext in ViewModel | PASS | All data via SettingsService/BodyweightService |
| NavigationStack (not NavigationView) | PASS | Settings uses NavigationStack for sub-screens |
| Dark mode only | PASS | All colors from DesignTokens.swift, Form styled with `.scrollContentBackground(.hidden)` |
| Database aggregation over Swift iteration | PASS | rebuildAll() uses existing database-level aggregation in PRService/StatsService |
| Do not invent schema | PASS | Only adds `defaultRestTimeSeconds: Int?` to existing HealthProfile (per screen_tree) |
| SF Symbols for icons | PASS | Settings sections use SF Symbols for row icons |
| Minimum 44x44pt tap targets | PASS | Form rows, toggle controls, buttons all meet minimum |
| Store metric, convert in UI | PASS | All weight stored in kg, UnitConversion at display boundary |
| No startup rebuild (constitution) | PASS | Rebuild Stats is explicit user action only |

**Post-Phase 1 re-check**: No violations. SettingsService is a thin orchestration layer that coordinates HealthProfile updates with PRService/StatsService rebuilds. The `E1RMFormula` enum is a view-layer convenience — HealthProfile still stores the raw string for forward compatibility. `@AppStorage` for onboarding avoids any SwiftData dependency at app launch.

## Project Structure

### Documentation (this feature)

```
kitty-specs/010-settings-and-onboarding/
├── plan.md              # This file
├── research.md          # Phase 0 output — onboarding patterns, formula options, UI patterns
├── data-model.md        # Phase 1 output — HealthProfile changes, E1RMFormula enum, SettingsService
├── quickstart.md        # Phase 1 output — file structure, verification checklist
└── tasks.md             # Phase 2 output (NOT created by /spec-kitty.plan)
```

### Source Code (repository root)

```
Reppo/
├── Data/
│   ├── Models/
│   │   └── HealthProfile.swift                    # MODIFY: add defaultRestTimeSeconds: Int?
│   └── Enums/
│       └── E1RMFormula.swift                      # NEW: enum with epley/brzycki/lombardi + calculate()
│
├── Core/
│   └── Services/
│       ├── SettingsService.swift                  # NEW: settings CRUD + rebuild orchestration
│       ├── Protocols/
│       │   └── SettingsServiceProtocol.swift       # NEW: protocol
│       └── ServiceContainer.swift                 # MODIFY: add settingsService
│
├── Features/
│   ├── Settings/
│   │   ├── Views/
│   │   │   ├── SettingsView.swift                 # NEW: main settings (Form, 5 sections)
│   │   │   ├── BodyweightLogView.swift            # NEW: trend chart + entry list + add
│   │   │   ├── RebuildStatsView.swift             # NEW: explanation + 3 rebuild buttons
│   │   │   └── Components/
│   │   │       ├── UnitPickerSheet.swift           # NEW: metric/imperial selection
│   │   │       ├── FormulaPickerSheet.swift        # NEW: e1RM formula picker with descriptions
│   │   │       └── RestTimePickerSheet.swift       # NEW: rest time selection
│   │   └── ViewModels/
│   │       ├── SettingsViewModel.swift             # NEW: @Observable, settings state + actions
│   │       └── BodyweightLogViewModel.swift        # NEW: @Observable, bodyweight entries + chart
│   │
│   └── Onboarding/
│       ├── OnboardingStep.swift                   # NEW: enum driving step progression (view-layer only)
│       ├── Views/
│       │   ├── OnboardingContainerView.swift      # NEW: TabView-based step container
│       │   ├── WelcomeStepView.swift              # NEW: welcome screen
│       │   ├── UnitsStepView.swift                # NEW: unit selection
│       │   ├── FormulaStepView.swift              # NEW: e1RM formula selection
│       │   ├── BodyweightStepView.swift           # NEW: optional bodyweight entry
│       │   └── ImportStepView.swift               # NEW: import prompt (stub for feature 011)
│       └── ViewModels/
│           └── OnboardingViewModel.swift          # NEW: @Observable, step progression + settings save
│
├── App/
│   ├── ReppoApp.swift                            # MODIFY: add @AppStorage onboarding check
│   └── ContentView.swift                         # MODIFY: replace SettingsPlaceholderView → SettingsView
│
└── Reppo.xcodeproj/
    └── project.pbxproj                           # MODIFY: add all new file references
```

**Structure Decision**: Settings follows the established `Features/Settings/` pattern. Onboarding gets its own `Features/Onboarding/` directory since it has distinct lifecycle (first-launch only). A new `SettingsService` in `Core/Services/` encapsulates HealthProfile CRUD + rebuild orchestration, keeping ViewModels thin. The `E1RMFormula` enum lives in `Data/Enums/` alongside other app-wide enums.

## Engineering Alignment (Planning Decisions)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Onboarding persistence | `@AppStorage("hasCompletedOnboarding")` | Avoids async SwiftData fetch at app launch. Standard iOS pattern. Separate concern from data model. |
| 2 | CSV Import/Export | Stubbed (buttons visible, "Coming Soon") | Feature 011 handles full implementation. Reduces scope. |
| 3 | E1RM formulas | Epley (default), Brzycki, Lombardi | Three most common formulas. Plain-English descriptions per AGENT_RULES S11. Stored as String for forward compatibility. |
| 4 | HealthProfile additions | `defaultRestTimeSeconds: Int?` only | Minimal schema change. `hasCompletedOnboarding` stays in @AppStorage. SwiftData lightweight migration handles the new optional field. |
| 5 | Settings architecture | New `SettingsService` + protocol | ViewModels must call Services (not Repositories) per constitution. Service orchestrates HealthProfile updates + rebuild triggers. |
| 6 | Rebuild orchestration | SettingsService calls PRService.rebuildAll() + StatsService.rebuildAll() | Existing rebuild methods handle the heavy lifting. Settings just coordinates and shows progress. |
| 7 | Unit propagation | No notification system | ViewModels fetch HealthProfile on load. Other screens pick up the change naturally on next ViewModel load cycle. |
| 8 | Bodyweight chart | Swift Charts LineMark + PointMark | Same framework used for Charts tab. ~200 entries max = trivial for in-memory rendering. |
| 9 | Send Feedback | mailto: URL | Simplest approach. No dependencies. Pre-populated subject + version info. |
| 10 | Onboarding flow | TabView with .tabViewStyle(.page) + manual buttons | Clean step progression. Skip/Next buttons on each step. No swipe-to-dismiss ambiguity. |

## Component Architecture

### SettingsViewModel (@Observable)

```
Responsibilities:
├── profile: HealthProfile?                 # Current user profile
├── isLoading: Bool                        # Loading state
├── isRebuilding: Bool                     # Rebuild in progress
├── rebuildProgress: String?               # Status message during rebuild
│
├── loadProfile()                          # Fetches HealthProfile via SettingsService
├── updateUnitPreference(_:)               # Updates unitPreference
├── updateE1RMFormula(_:)                  # Updates e1RMFormula
├── toggleWarmupVolume()                   # Toggles + triggers StatsService rebuild
├── toggleWarmupPRs()                      # Toggles + triggers PRService rebuild
├── updateDefaultRestTime(_:)             # Updates defaultRestTimeSeconds
├── rebuildPRs()                          # PRService.rebuildAll()
├── rebuildStats()                        # StatsService.rebuildAll()
├── rebuildAll()                          # Both rebuilds
├── sendFeedback()                        # Opens mailto: URL
│
└── Dependencies (injected):
    └── SettingsService                    # All operations go through this
```

### BodyweightLogViewModel (@Observable)

```
Responsibilities:
├── entries: [BodyweightEntry]             # All bodyweight entries (date DESC)
├── isLoading: Bool
├── showAddSheet: Bool
│
├── loadEntries()                          # Fetches all entries via BodyweightService
├── addEntry(weightKg:, date:)            # Saves via BodyweightService
├── deleteEntry(_:)                       # Deletes via BodyweightService
│
└── Dependencies (injected):
    ├── BodyweightService                  # Entry CRUD
    └── SettingsService                    # Unit preference for display conversion
```

### OnboardingViewModel (@Observable)

```
Responsibilities:
├── currentStep: OnboardingStep = .welcome # Current onboarding step
├── selectedUnit: UnitPreference = .metric # User's choice
├── selectedFormula: E1RMFormula = .epley  # User's choice
├── bodyweightInput: String = ""           # Optional bodyweight entry
├── isComplete: Bool = false               # All steps done
│
├── next()                                 # Advance to next step
├── skip()                                # Skip current step (use defaults)
├── finish()                              # Save all selections to HealthProfile
│
└── Dependencies (injected):
    ├── SettingsService                     # Save HealthProfile settings
    └── BodyweightService                  # Save optional bodyweight entry
```

### SettingsService (actor)

```
Responsibilities:
├── fetchProfile() async → HealthProfile   # HealthProfileRepository.fetchOrCreate()
├── updateProfile(_:) async                # Save updated HealthProfile
├── updateUnitPreference(_:) async         # Update single field
├── updateE1RMFormula(_:) async            # Update single field
├── updateWarmupVolume(_:) async           # Update + trigger StatsService.rebuildAll()
├── updateWarmupPRs(_:) async              # Update + trigger PRService.rebuildAll()
├── updateDefaultRestTime(_:) async        # Update single field
├── rebuildPRs() async                     # PRService.rebuildAll()
├── rebuildStats() async                   # StatsService.rebuildAll()
├── rebuildAll() async                     # Both rebuilds
│
└── Dependencies (injected):
    ├── HealthProfileRepository            # HealthProfile CRUD
    ├── PRService                          # Rebuild PRs
    └── StatsService                       # Rebuild stats
```

### View Hierarchy

```
ReppoApp
├── if !hasCompletedOnboarding:
│   └── OnboardingContainerView (fullScreenCover or conditional)
│       ├── WelcomeStepView
│       ├── UnitsStepView
│       ├── FormulaStepView
│       ├── BodyweightStepView
│       └── ImportStepView (stub — button navigates nowhere for v1)
│
├── else:
│   └── ContentView
│       └── TabView
│           └── Settings tab:
│               └── SettingsView (NavigationStack, bottom nav visible)
│                   ├── Form
│                   │   ├── GENERAL section
│                   │   │   ├── Units → .sheet { UnitPickerSheet }
│                   │   │   └── e1RM Formula → .sheet { FormulaPickerSheet }
│                   │   │
│                   │   ├── WORKOUT PREFERENCES section
│                   │   │   ├── Include Warmups in Volume (Toggle)
│                   │   │   ├── Include Warmups in PRs (Toggle)
│                   │   │   └── Default Rest Time → .sheet { RestTimePickerSheet }
│                   │   │
│                   │   ├── DATA section
│                   │   │   ├── Import Data (CSV) → "Coming Soon" alert
│                   │   │   ├── Export Data (CSV) → "Coming Soon" alert
│                   │   │   └── Rebuild Stats → NavigationLink { RebuildStatsView }
│                   │   │
│                   │   ├── BODY section
│                   │   │   └── Bodyweight Log → NavigationLink { BodyweightLogView }
│                   │   │       ├── Trend chart (LineMark + PointMark, ~200pt)
│                   │   │       ├── Chronological entry list
│                   │   │       └── [+Add] → sheet with weight + date input
│                   │   │
│                   │   └── ABOUT section
│                   │       ├── Version (from Bundle.main)
│                   │       └── Send Feedback → mailto: URL
│                   │
│                   └── .task { loadProfile() }
```

### Data Flow

```
App Launch
  → ReppoApp.body checks @AppStorage("hasCompletedOnboarding")
  → If false: show OnboardingContainerView
    → User progresses through 5 steps (all skippable)
    → OnboardingViewModel.finish():
      → SettingsService.updateProfile() with chosen settings
      → BodyweightService.saveEntry() if bodyweight was entered
      → Set @AppStorage("hasCompletedOnboarding") = true
    → ContentView appears (Calendar tab selected)

Settings Tab
  → SettingsView.task → SettingsViewModel.loadProfile()
    → SettingsService.fetchProfile() → HealthProfileRepository.fetchOrCreate()
  → User toggles "Include Warmups in PRs":
    → Confirmation alert: "This will rebuild all PRs. Continue?"
    → If confirmed: SettingsViewModel.toggleWarmupPRs()
      → SettingsService.updateWarmupPRs(true)
        → HealthProfileRepository.save(updatedProfile)
        → PRService.rebuildAll() — clean-slate rebuild from raw sets
      → SettingsViewModel.isRebuilding = true (shows ProgressView)
      → On completion: isRebuilding = false, success message
  → User taps Bodyweight Log:
    → NavigationLink pushes BodyweightLogView
    → BodyweightLogViewModel.loadEntries() → BodyweightService.fetchAllEntries()
    → Chart renders LineMark + PointMark from entries
    → [+Add] opens sheet → saveEntry(bodyweightKg:, date:)

Rebuild Stats
  → NavigationLink pushes RebuildStatsView
  → 3 buttons: [Rebuild PRs] [Rebuild Stats] [Rebuild All]
  → Each shows confirmation alert → runs respective service method
  → ProgressView overlay during rebuild → completion alert
```

## Rebuild Trigger Matrix

| Setting Change | Triggers | Service Method |
|---------------|----------|----------------|
| unitPreference | No rebuild | Display-only change |
| e1RMFormula | No rebuild | Future sets use new formula; existing sets keep their e1RMFormulaVersion |
| includeWarmupsInVolume | StatsService.rebuildAll() | Volume aggregates change |
| includeWarmupsInPRs | PRService.rebuildAll() | PR eligibility changes |
| defaultRestTimeSeconds | No rebuild | UI hint only |
| Manual: Rebuild PRs | PRService.rebuildAll() | User-initiated |
| Manual: Rebuild Stats | StatsService.rebuildAll() | User-initiated |
| Manual: Rebuild All | PRService.rebuildAll() + StatsService.rebuildAll() | User-initiated |

## Complexity Tracking

| Decision | Justification |
|----------|---------------|
| 3 e1RM formulas (not 5+) | Covers most users (Epley, Brzycki, Lombardi). Can add more later. |
| No notification system for unit changes | ViewModels re-fetch on load. Acceptable UX for rare setting change. |
| Stubbed CSV Import/Export | Feature 011 owns this. Reduces feature 010 scope significantly. |
| @AppStorage over HealthProfile for onboarding flag | Synchronous check at app launch. No async SwiftData dependency. |
| SettingsService as thin orchestrator | Keeps rebuild logic in existing PRService/StatsService. SettingsService only coordinates. |
| ProgressView (indeterminate) for rebuild | Rebuild should complete < 30s (SC-003). No need for progress percentage. |

## Parallel Work Analysis

This feature has a clear dependency chain suitable for sequential work packages.

### Dependency Graph

```
WP01: Foundation (E1RMFormula enum, SettingsService/Protocol, HealthProfile mod, ServiceContainer wiring)
  → WP02: Settings Screen (SettingsView, SettingsViewModel, all 5 sections, pickers, rebuild UI)
  → WP03: Bodyweight Log (BodyweightLogView, BodyweightLogViewModel, trend chart, add entry)
  → WP04: Onboarding Flow (OnboardingContainerView, 5 step views, OnboardingViewModel, ReppoApp wiring)
  → WP05: Integration (ContentView update, tab wiring, build verification)
```

WP01 must complete first (provides SettingsService used by all other WPs). WP02 and WP03 could theoretically be parallelized but share SettingsViewModel patterns. WP04 (Onboarding) depends on WP01 for SettingsService but is otherwise independent. WP05 integrates everything.
