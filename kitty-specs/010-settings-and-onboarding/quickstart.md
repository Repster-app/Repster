# Quickstart: 010 Settings + Onboarding

**Feature**: Settings + Onboarding
**Date**: 2026-02-28

## Prerequisites

- Feature 009 (Charts Tab) merged
- Existing services: `WorkoutService`, `SetService`, `ExerciseService`, `StatsService`, `BodyweightService`, `ChartDataService`
- Existing repositories: `WorkoutRepository`, `SetRepository`, `ExerciseRepository`, `ExerciseStatsRepository`, `PerformanceRecordRepository`
- Existing models: `HealthProfile`, `Workout`, `WorkoutSet`, `Exercise`, `ExerciseStats`, `PerformanceRecord`

## File Structure

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
│   │   │   ├── SettingsView.swift                 # NEW: main settings screen (Form with sections)
│   │   │   ├── BodyweightLogView.swift            # NEW: trend chart + entry list + add
│   │   │   ├── RebuildStatsView.swift             # NEW: explanation + 3 rebuild buttons
│   │   │   └── Components/
│   │   │       ├── UnitPickerSheet.swift           # NEW: metric/imperial selection sheet
│   │   │       ├── FormulaPickerSheet.swift        # NEW: e1RM formula picker with descriptions
│   │   │       └── RestTimePickerSheet.swift       # NEW: rest time selection
│   │   └── ViewModels/
│   │       ├── SettingsViewModel.swift             # NEW: @Observable, settings state + actions
│   │       └── BodyweightLogViewModel.swift        # NEW: @Observable, bodyweight entries + chart data
│   │
│   └── Onboarding/
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
│   └── ContentView.swift                         # MODIFY: replace SettingsPlaceholderView
│
└── Reppo.xcodeproj/
    └── project.pbxproj                           # MODIFY: add new file references
```

## Key Architecture Decisions

1. **HealthProfile extension** — add `defaultRestTimeSeconds: Int?` with nil default; no migration needed (optional field)
2. **E1RMFormula enum** — standalone enum with `epley`, `brzycki`, `lombardi` cases and a `calculate(weight:reps:) -> Double` method
3. **SettingsService** — wraps HealthProfile CRUD and orchestrates rebuild operations (PRs, Stats, All) via existing services
4. **Onboarding flow** — TabView-based 5-step container; all steps skippable; completes by setting `@AppStorage("hasCompletedOnboarding")` to true
5. **Conditional root view** — `ReppoApp` checks `@AppStorage("hasCompletedOnboarding")` to show either `OnboardingContainerView` or `ContentView`
6. **Settings Form layout** — 5 sections: GENERAL (units, e1RM formula), WORKOUT PREFERENCES (warmup toggles, rest time), DATA (import/export stubs, rebuild stats), BODY (bodyweight log), ABOUT (version, feedback)

## Wiring Checklist

- [ ] Add `defaultRestTimeSeconds: Int?` to `HealthProfile`
- [ ] Create `E1RMFormula` enum in `Data/Enums/`
- [ ] Create `SettingsServiceProtocol` and `SettingsService`
- [ ] Add `settingsService` to `ServiceContainer`
- [ ] Add `@AppStorage("hasCompletedOnboarding")` check in `ReppoApp.swift`
- [ ] Replace `SettingsPlaceholderView()` with `SettingsView(...)` in `ContentView.swift`
- [ ] Pass required services to `SettingsView` and `OnboardingContainerView` via init or environment
- [ ] Add all new file references to `project.pbxproj`

## Quick Verification

After implementation, verify:
- [ ] HealthProfile.defaultRestTimeSeconds field added with nil default
- [ ] E1RMFormula enum has 3 cases with calculate() method returning correct values
- [ ] SettingsService wraps HealthProfile CRUD and rebuild orchestration
- [ ] ServiceContainer updated with settingsService
- [ ] SettingsView renders all 5 sections (GENERAL, WORKOUT PREFERENCES, DATA, BODY, ABOUT)
- [ ] Unit toggle updates HealthProfile.unitPreference
- [ ] e1RM formula picker shows 3 options with descriptions
- [ ] Warmup toggles trigger rebuild confirmation alert
- [ ] CSV Import/Export buttons show "Coming Soon" stub
- [ ] Rebuild Stats view has 3 buttons (Rebuild PRs, Rebuild Stats, Rebuild All) with confirmation
- [ ] Bodyweight Log shows trend chart (Swift Charts LineMark) and chronological entries
- [ ] Add bodyweight entry works via BodyweightService.saveEntry()
- [ ] About section shows app version (Bundle.main.infoDictionary)
- [ ] Send Feedback opens mailto: link
- [ ] OnboardingContainerView has 5 steps (Welcome, Units, Formula, Bodyweight, Import)
- [ ] All onboarding steps are skippable
- [ ] @AppStorage("hasCompletedOnboarding") prevents re-showing
- [ ] After onboarding, user arrives at Calendar tab
- [ ] ContentView replaces SettingsPlaceholderView with SettingsView
- [ ] Build succeeds with 0 errors
