# Data Model: 010 Settings + Onboarding

**Feature**: Settings + Onboarding
**Date**: 2026-02-28

## Overview

This feature adds **one new field** to an existing SwiftData model (`HealthProfile`), introduces **one new enum** at the data layer (`E1RMFormula`), one view-layer enum (`OnboardingStep`), and one new service (`SettingsService`). No new SwiftData `@Model` classes are created. All settings live on the existing single-row `HealthProfile` table per AGENT_RULES Section 8.

### Change Summary

| Category | Count | Details |
|----------|-------|---------|
| New SwiftData models | 0 | -- |
| Modified SwiftData models | 1 | `HealthProfile` (+1 field) |
| New enums (data layer) | 1 | `E1RMFormula` |
| New enums (view layer) | 1 | `OnboardingStep` |
| New services | 1 | `SettingsService` |
| Modified services/repos | 0 | Existing protocols unchanged |

---

## Existing Entities (No Changes)

### BodyweightEntry (specdoc S6.6)

File: `Reppo/Data/Models/BodyweightEntry.swift`

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | UUID | `UUID()` | Primary key |
| `healthProfileId` | UUID | -- | FK to HealthProfile |
| `date` | Date | `Date()` | Measurement date |
| `bodyweightKg` | Double | -- | Always stored in kg |
| `createdAt` | Date | `Date()` | -- |
| `updatedAt` | Date | `Date()` | -- |

Used by the Settings bodyweight log section and the onboarding bodyweight step. Accessed via `BodyweightServiceProtocol`.

### UnitPreference (existing enum)

File: `Reppo/Data/Enums/UnitPreference.swift`

```swift
enum UnitPreference: String, Codable, CaseIterable {
    case metric
    case imperial
}
```

No changes. Used by Settings units toggle and onboarding units step.

---

## Modified Entity: HealthProfile

File: `Reppo/Data/Models/HealthProfile.swift`

### Current Schema

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | UUID | `UUID()` | Primary key |
| `unitPreference` | UnitPreference | `.metric` | Display units |
| `includeWarmupsInVolume` | Bool | `false` | Volume calc setting |
| `includeWarmupsInPRs` | Bool | `false` | PR eligibility setting |
| `e1RMFormula` | String | `"epley"` | Formula identifier (raw value) |
| `createdAt` | Date | `Date()` | -- |
| `updatedAt` | Date | `Date()` | -- |

### New Field

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `defaultRestTimeSeconds` | Int? | `nil` | Default rest timer in seconds. `nil` = no preference set. |

**Rationale**: The rest timer currently falls back to `Exercise.defaultRestTime`. This field provides a global user-level default that applies when an exercise has no per-exercise rest time configured. The nullable design means "no preference" rather than forcing a value.

**UI picker values**: 30, 60, 90, 120, 180, 300 seconds (displayed as "30s", "1 min", "1:30", "2 min", "3 min", "5 min").

### Updated Init Signature

```swift
init(
    id: UUID = UUID(),
    unitPreference: UnitPreference = .metric,
    includeWarmupsInVolume: Bool = false,
    includeWarmupsInPRs: Bool = false,
    e1RMFormula: String = "epley",
    defaultRestTimeSeconds: Int? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
)
```

### Migration

SwiftData lightweight migration handles adding an optional field. No manual migration code required. Existing rows get `nil` for `defaultRestTimeSeconds`.

---

## New Enum: E1RMFormula

File: `Reppo/Data/Enums/E1RMFormula.swift`

This enum provides type-safe access to the formula identifiers stored as `String` in `HealthProfile.e1RMFormula`. It lives at the data layer alongside other enums (`UnitPreference`, `SetType`, etc.) because it maps directly to a persisted model field.

```swift
import Foundation

enum E1RMFormula: String, CaseIterable, Sendable {
    case epley
    case brzycki
    case lombardi

    /// Human-readable name for UI display.
    var displayName: String {
        switch self {
        case .epley:    return "Epley"
        case .brzycki:  return "Brzycki"
        case .lombardi: return "Lombardi"
        }
    }

    /// Plain-English explanation of the formula for onboarding / settings.
    var description: String {
        switch self {
        case .epley:
            return "Most widely used. Works well across rep ranges. "
                 + "Formula: weight x (1 + reps / 30)"
        case .brzycki:
            return "Slightly more conservative at higher reps. "
                 + "Formula: weight x 36 / (37 - reps)"
        case .lombardi:
            return "Power-law model. Simple and predictable. "
                 + "Formula: weight x reps^0.10"
        }
    }

    /// Calculate estimated 1-rep max for the given weight and reps.
    ///
    /// - Parameters:
    ///   - weight: The weight lifted (in any unit; output matches input unit).
    ///   - reps: Number of reps performed. Must be >= 1.
    /// - Returns: Estimated 1RM. Returns `weight` unchanged when `reps == 1`.
    func calculate(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        let r = Double(reps)
        switch self {
        case .epley:
            return weight * (1.0 + r / 30.0)
        case .brzycki:
            return weight * 36.0 / (37.0 - r)
        case .lombardi:
            return weight * pow(r, 0.10)
        }
    }
}
```

### Formula Reference

| Formula | Equation | 1RM for 100 kg x 5 | Behavior |
|---------|----------|---------------------|----------|
| Epley | `w * (1 + r/30)` | 116.7 kg | Linear; most popular |
| Brzycki | `w * 36 / (37 - r)` | 112.5 kg | Conservative at high reps |
| Lombardi | `w * r^0.10` | 117.5 kg | Power-law; simple curve |

### Relationship to HealthProfile

`HealthProfile.e1RMFormula` stores the `rawValue` string (`"epley"`, `"brzycki"`, `"lombardi"`). Convert with:

```swift
let formula = E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley
```

The fallback to `.epley` guards against corrupt or unexpected stored values.

### Relationship to Existing e1RM Usage

`WorkoutSet.e1RM` is computed at write-time by `SetService` using the formula active at save. Each set also stores `e1RMFormulaVersion` so historical sets retain the formula they were computed with. Changing the formula in Settings affects **future** sets only -- existing `WorkoutSet.e1RM` values are not retroactively recomputed (per specdoc S8.10 and spec edge cases).

---

## New Enum: OnboardingStep (View Layer)

File: `Reppo/Features/Onboarding/OnboardingStep.swift`

This is a **view-layer only** enum -- not persisted, not in the data layer. It drives the `TabView`-based step progression during the onboarding flow.

```swift
import Foundation

enum OnboardingStep: Int, CaseIterable {
    case welcome       = 0
    case units         = 1
    case formula       = 2
    case bodyweight    = 3
    case importPrompt  = 4

    /// Total number of steps in the onboarding flow.
    static var totalSteps: Int { allCases.count }

    /// Whether this step is skippable (has sensible defaults).
    var isSkippable: Bool {
        switch self {
        case .welcome:      return false  // Entry point
        case .units:        return true   // Default: metric
        case .formula:      return true   // Default: epley
        case .bodyweight:   return true   // Optional entry
        case .importPrompt: return true   // Optional action
        }
    }

    /// The default value applied when the user skips this step.
    var skipBehavior: String {
        switch self {
        case .welcome:      return "N/A"
        case .units:        return "metric (kg)"
        case .formula:      return "Epley"
        case .bodyweight:   return "No entry recorded"
        case .importPrompt: return "No import triggered"
        }
    }
}
```

### Onboarding Completion Tracking

Onboarding completion is tracked via `@AppStorage("hasCompletedOnboarding")` in `ReppoApp`. This provides a synchronous check at app launch without requiring an async SwiftData fetch. On onboarding finish (or skip), the `OnboardingViewModel` saves settings via `SettingsService`, then sets the `@AppStorage` flag to `true`. The flag is separate from the data model to avoid coupling app launch flow to SwiftData readiness.

---

## New Service: SettingsService

File: `Reppo/Core/Services/SettingsService.swift`
Protocol: `Reppo/Core/Services/Protocols/SettingsServiceProtocol.swift`

### Why a New Service

The existing architecture enforces ViewModels -> Services -> Repositories (AGENT_RULES S6). ViewModels must not call repositories directly. Settings changes have side effects (rebuild orchestration) that belong in a service, not a ViewModel.

### Protocol

```swift
import Foundation

/// Service for reading/writing user settings on HealthProfile
/// and orchestrating side effects (rebuilds) when settings change.
///
/// SettingsService does NOT:
/// - Own PR logic (delegates to PRService)
/// - Own stats logic (delegates to StatsService)
/// - Access ModelContext directly (uses HealthProfileRepository)
protocol SettingsServiceProtocol: Sendable {

    // MARK: - Read

    /// Fetch the current HealthProfile, creating one with defaults if needed.
    func fetchSettings() async throws -> HealthProfile

    // MARK: - Write

    /// Update the unit preference (metric / imperial).
    /// Display-only change -- no rebuild needed.
    func updateUnitPreference(_ preference: UnitPreference) async throws

    /// Update the e1RM formula.
    /// Future sets use the new formula. No rebuild of existing sets.
    func updateE1RMFormula(_ formula: E1RMFormula) async throws

    /// Update the "include warmups in volume" setting.
    /// Triggers StatsService.rebuildAll() because volume totals change.
    func updateIncludeWarmupsInVolume(_ include: Bool) async throws

    /// Update the "include warmups in PRs" setting.
    /// Triggers PRService.rebuildAll() because PR eligibility changes.
    func updateIncludeWarmupsInPRs(_ include: Bool) async throws

    /// Update the default rest time.
    /// No rebuild needed -- applies to future rest timer starts only.
    func updateDefaultRestTime(_ seconds: Int?) async throws

    // MARK: - Rebuild Operations

    /// Rebuild all PRs from raw sets (delegates to PRService.rebuildAll).
    func rebuildPRs() async throws

    /// Rebuild all stats from raw sets (delegates to StatsService.rebuildAll).
    func rebuildStats() async throws

    /// Rebuild both PRs and stats.
    func rebuildAll() async throws
}
```

### Dependencies

```
SettingsService
├── HealthProfileRepositoryProtocol   (read/write HealthProfile)
├── PRServiceProtocol                 (rebuildAll for PR setting changes)
└── StatsServiceProtocol              (rebuildAll for volume setting changes)
```

### Rebuild Trigger Matrix

| Setting Changed | PRService.rebuildAll() | StatsService.rebuildAll() | Reason |
|----------------|:----------------------:|:-------------------------:|--------|
| `unitPreference` | -- | -- | Display-only; stored values unchanged |
| `e1RMFormula` | -- | -- | Future sets only; existing e1RM values retained |
| `includeWarmupsInVolume` | -- | Yes | Volume aggregation includes/excludes warmup sets |
| `includeWarmupsInPRs` | Yes | -- | PR eligibility includes/excludes warmup sets |
| `defaultRestTimeSeconds` | -- | -- | Runtime behavior only; no stored data affected |

### ServiceContainer Integration

`SettingsService` will be added to `ServiceContainer` alongside existing services:

```swift
// In ServiceContainer.init(repositoryContainer:)

// 8. SettingsService — depends on HealthProfileRepository + PRService + StatsService
let settingsService = SettingsService(
    healthProfileRepository: repositoryContainer.healthProfileRepository,
    prService: prService,
    statsService: statsService
)

self.settingsService = settingsService
```

No circular dependencies: `SettingsService` depends on `PRService` and `StatsService`, neither of which depends on `SettingsService`.

---

## Relationships and Data Flow

### Entity Relationship Diagram

```
HealthProfile (single row)
│
├── .unitPreference ─────────── UnitPreference enum (display conversion)
├── .e1RMFormula ────────────── E1RMFormula enum (rawValue bridge)
├── .includeWarmupsInVolume ─── StatsService (volume calc filter)
├── .includeWarmupsInPRs ────── PRService (eligibility filter)
├── .defaultRestTimeSeconds ─── Rest timer (runtime fallback)
│
└──< BodyweightEntry (1:many via healthProfileId)
     └── Used by: BodyweightService, Settings bodyweight log, Onboarding step 4
```

### Settings Screen Data Flow

```
SettingsView
  └── SettingsViewModel
        └── SettingsServiceProtocol
              ├── fetchSettings() ──→ HealthProfileRepository.fetchOrCreate()
              │                       └── returns HealthProfile
              │
              ├── updateIncludeWarmupsInPRs(true)
              │   ├── HealthProfileRepository (save updated profile)
              │   └── PRService.rebuildAll() (side effect)
              │
              ├── updateIncludeWarmupsInVolume(true)
              │   ├── HealthProfileRepository (save updated profile)
              │   └── StatsService.rebuildAll() (side effect)
              │
              └── rebuildAll()
                  ├── PRService.rebuildAll()
                  └── StatsService.rebuildAll()
```

### Onboarding Data Flow

```
OnboardingView (TabView with OnboardingStep pages)
  └── OnboardingViewModel
        ├── SettingsServiceProtocol
        │   ├── updateUnitPreference(.imperial)
        │   └── updateE1RMFormula(.brzycki)
        │
        └── BodyweightServiceProtocol
            └── saveEntry(bodyweightKg:, date:)

Step progression:
  welcome → units → formula → bodyweight → importPrompt → dismiss
  (any step skippable except welcome; defaults applied on skip)
```

### Rest Timer Fallback Chain

The rest timer resolves its initial value through a priority chain:

```
1. Exercise.defaultRestTime   (per-exercise override, if set)
2. HealthProfile.defaultRestTimeSeconds  (global user preference, if set)
3. Hardcoded fallback: 90 seconds  (app default)
```

This chain is evaluated at rest timer start time (after set completion), not at settings save time.

---

## Existing Services Used (No Protocol Changes)

### HealthProfileRepositoryProtocol

File: `Reppo/Core/Repositories/Protocols/HealthProfileRepositoryProtocol.swift`

| Method | Used By | Purpose |
|--------|---------|---------|
| `fetch()` | SettingsService | Check if profile exists (onboarding gate) |
| `fetchOrCreate()` | SettingsService | Load settings with guaranteed defaults |
| `save(_:)` | SettingsService | Persist setting changes |

### BodyweightServiceProtocol

File: `Reppo/Core/Services/Protocols/BodyweightServiceProtocol.swift`

| Method | Used By | Purpose |
|--------|---------|---------|
| `saveEntry(bodyweightKg:date:)` | OnboardingViewModel, SettingsViewModel | Record bodyweight |
| `fetchAllEntries()` | SettingsViewModel (bodyweight log) | Display entry list + trend chart |
| `closestBodyweight(to:)` | -- (not used directly by Settings) | Referenced for context only |

### PRServiceProtocol

File: `Reppo/Core/Services/Protocols/PRServiceProtocol.swift`

| Method | Used By | Purpose |
|--------|---------|---------|
| `rebuildAll()` | SettingsService | After `includeWarmupsInPRs` toggle or manual rebuild |
| `rebuild(for:)` | -- (not used by Settings) | Per-exercise rebuild; available but not needed here |

### StatsServiceProtocol

File: `Reppo/Core/Services/Protocols/StatsServiceProtocol.swift`

| Method | Used By | Purpose |
|--------|---------|---------|
| `rebuildAll()` | SettingsService | After `includeWarmupsInVolume` toggle or manual rebuild |
| `rebuild(for:)` | -- (not used by Settings) | Per-exercise rebuild; available but not needed here |

---

## Schema Changes Summary

| Entity | Change | Migration |
|--------|--------|-----------|
| `HealthProfile` | Add `defaultRestTimeSeconds: Int?` | SwiftData lightweight (additive optional field) |
| `BodyweightEntry` | None | -- |
| All other models | None | -- |

No new indexes are required. `HealthProfile` is a single-row table fetched without predicates.
