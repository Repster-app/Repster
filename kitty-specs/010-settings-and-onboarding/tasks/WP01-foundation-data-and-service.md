---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
  - "T005"
title: "Foundation — Data Layer + SettingsService"
phase: "Phase 1 - Foundation"
lane: "done"
assignee: ""
agent: "claude-opus"
shell_pid: "50319"
review_status: "approved"
reviewed_by: "Magnus Espensen"
dependencies: []
history:
  - timestamp: "2026-02-28T18:49:28Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP01 – Foundation — Data Layer + SettingsService

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

This work package establishes the data-layer and service-layer foundations that all subsequent WPs depend on:

1. **HealthProfile** gains a new optional field `defaultRestTimeSeconds: Int?` for the global rest timer fallback.
2. A new **E1RMFormula** enum provides type-safe formula selection with `calculate(weight:reps:)`.
3. A new **SettingsService** (actor + protocol) wraps HealthProfile CRUD and orchestrates rebuild operations when warmup settings change.
4. **ServiceContainer** is wired with the new service.

**Success criteria**:
- HealthProfile compiles with the new field, existing tests/code unaffected.
- E1RMFormula enum has 3 cases with correct `calculate()` implementations.
- SettingsService can fetch/update HealthProfile and trigger `rebuildAll()` on PRService/StatsService.
- ServiceContainer initializes without errors, no circular dependencies.

## Context & Constraints

**Design documents** (read these for full context):
- `kitty-specs/010-settings-and-onboarding/plan.md` — architecture, component details, rebuild trigger matrix
- `kitty-specs/010-settings-and-onboarding/data-model.md` — schema changes, enum definitions, service protocol
- `kitty-specs/010-settings-and-onboarding/research.md` — RQ-2 (formula decisions), RQ-4 (HealthProfile fields)
- `kitty-specs/010-settings-and-onboarding/quickstart.md` — file structure, wiring checklist

**Architecture rules**:
- MVVM: View -> ViewModel -> Service -> Repository -> SwiftData
- All services are `actor` types for thread safety
- ViewModels use `@Observable` (not `ObservableObject`)
- No `ModelContext` in ViewModels — all data via services
- Protocol-first: create protocol, then implementation
- Store metric only, convert in UI

**Existing code references**:
- `Reppo/Data/Models/HealthProfile.swift` — model to modify
- `Reppo/Core/Services/ServiceContainer.swift` — wiring target
- `Reppo/Core/Services/PRService.swift` — has `rebuildAll()` at ~line 365
- `Reppo/Core/Services/StatsService.swift` — has `rebuildAll()` at ~line 59
- `Reppo/Core/Repositories/Protocols/HealthProfileRepositoryProtocol.swift` — `fetch()`, `fetchOrCreate()`, `save(_:)`
- `Reppo/Data/Enums/UnitPreference.swift` — existing enum pattern to follow

## Subtasks & Detailed Guidance

### Subtask T001 – Add `defaultRestTimeSeconds: Int?` to HealthProfile

**Purpose**: Provide a global user-level default rest time that applies when an exercise has no per-exercise rest time configured.

**Steps**:
1. Open `Reppo/Data/Models/HealthProfile.swift`.
2. Add a new stored property:
   ```swift
   var defaultRestTimeSeconds: Int?
   ```
3. Update the `init()` to include the new parameter with `nil` default:
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
   ) {
       self.id = id
       self.unitPreference = unitPreference
       self.includeWarmupsInVolume = includeWarmupsInVolume
       self.includeWarmupsInPRs = includeWarmupsInPRs
       self.e1RMFormula = e1RMFormula
       self.defaultRestTimeSeconds = defaultRestTimeSeconds
       self.createdAt = createdAt
       self.updatedAt = updatedAt
   }
   ```

**Files**: `Reppo/Data/Models/HealthProfile.swift` (MODIFY)

**Notes**:
- SwiftData lightweight migration handles adding an optional field automatically. No migration code needed.
- Existing HealthProfile rows will get `nil` for this field.
- The `nil` value means "no preference" — the rest timer falls back to exercise-specific or hardcoded default.
- Do NOT change any existing property names or types.

---

### Subtask T002 – Create E1RMFormula Enum

**Purpose**: Provide type-safe access to the formula identifiers stored as `String` in `HealthProfile.e1RMFormula`.

**Steps**:
1. Create `Reppo/Data/Enums/E1RMFormula.swift`.
2. Define the enum with 3 cases:
   ```swift
   import Foundation

   enum E1RMFormula: String, CaseIterable, Sendable {
       case epley
       case brzycki
       case lombardi
   }
   ```
3. Add computed properties:
   - `displayName: String` — "Epley", "Brzycki", "Lombardi"
   - `description: String` — plain-English explanation of each formula (see data-model.md for exact text)
4. Add the `calculate(weight:reps:) -> Double` method:
   - Guard `reps > 1`, return `weight` unchanged when `reps == 1`
   - Epley: `weight * (1.0 + Double(reps) / 30.0)`
   - Brzycki: `weight * 36.0 / (37.0 - Double(reps))`
   - Lombardi: `weight * pow(Double(reps), 0.10)`

**Files**: `Reppo/Data/Enums/E1RMFormula.swift` (NEW, ~55 lines)

**Notes**:
- The rawValue strings MUST match what HealthProfile stores: `"epley"`, `"brzycki"`, `"lombardi"`.
- Use `E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley` pattern for safe conversion with fallback.
- This enum lives at the data layer (alongside `UnitPreference`, `SetType`, etc.) because it maps to a persisted field.
- Follow the existing pattern in `UnitPreference.swift` for style consistency.

---

### Subtask T003 – Create SettingsServiceProtocol

**Purpose**: Define the contract for the SettingsService so ViewModels depend on the protocol, not the implementation.

**Steps**:
1. Create `Reppo/Core/Services/Protocols/SettingsServiceProtocol.swift`.
2. Define the protocol:
   ```swift
   import Foundation

   protocol SettingsServiceProtocol: Sendable {
       // Read
       func fetchSettings() async throws -> HealthProfile

       // Write (individual field updates)
       func updateUnitPreference(_ preference: UnitPreference) async throws
       func updateE1RMFormula(_ formula: E1RMFormula) async throws
       func updateIncludeWarmupsInVolume(_ include: Bool) async throws
       func updateIncludeWarmupsInPRs(_ include: Bool) async throws
       func updateDefaultRestTime(_ seconds: Int?) async throws

       // Rebuild operations
       func rebuildPRs() async throws
       func rebuildStats() async throws
       func rebuildAll() async throws
   }
   ```

**Files**: `Reppo/Core/Services/Protocols/SettingsServiceProtocol.swift` (NEW, ~25 lines)

**Notes**:
- Follow the existing protocol pattern used by `PRServiceProtocol`, `StatsServiceProtocol`, etc.
- `Sendable` conformance required for actor isolation.
- `updateIncludeWarmupsInVolume` triggers `StatsService.rebuildAll()` as a side effect.
- `updateIncludeWarmupsInPRs` triggers `PRService.rebuildAll()` as a side effect.
- Other update methods have NO rebuild side effects.

---

### Subtask T004 – Create SettingsService Implementation

**Purpose**: Implement the SettingsService actor that wraps HealthProfile CRUD and coordinates rebuilds.

**Steps**:
1. Create `Reppo/Core/Services/SettingsService.swift`.
2. Define as an `actor`:
   ```swift
   actor SettingsService: SettingsServiceProtocol {
       private let healthProfileRepository: any HealthProfileRepositoryProtocol
       private let prService: any PRServiceProtocol
       private let statsService: any StatsServiceProtocol

       init(
           healthProfileRepository: any HealthProfileRepositoryProtocol,
           prService: any PRServiceProtocol,
           statsService: any StatsServiceProtocol
       ) { ... }
   }
   ```
3. Implement each method:
   - `fetchSettings()`: Call `healthProfileRepository.fetchOrCreate()`.
   - `updateUnitPreference(_:)`: Fetch profile, set `unitPreference`, update `updatedAt`, save.
   - `updateE1RMFormula(_:)`: Fetch profile, set `e1RMFormula` to `formula.rawValue`, update `updatedAt`, save.
   - `updateIncludeWarmupsInVolume(_:)`: Fetch, update field, save, then call `statsService.rebuildAll()`.
   - `updateIncludeWarmupsInPRs(_:)`: Fetch, update field, save, then call `prService.rebuildAll()`.
   - `updateDefaultRestTime(_:)`: Fetch, update field, save.
   - `rebuildPRs()`: Delegate to `prService.rebuildAll()`.
   - `rebuildStats()`: Delegate to `statsService.rebuildAll()`.
   - `rebuildAll()`: Call both `prService.rebuildAll()` and `statsService.rebuildAll()`.

**Files**: `Reppo/Core/Services/SettingsService.swift` (NEW, ~100 lines)

**Notes**:
- The fetch-update-save pattern for each update method:
  ```swift
  func updateUnitPreference(_ preference: UnitPreference) async throws {
      let profile = try await healthProfileRepository.fetchOrCreate()
      profile.unitPreference = preference
      profile.updatedAt = Date()
      try await healthProfileRepository.save(profile)
  }
  ```
- `updateIncludeWarmupsInVolume` and `updateIncludeWarmupsInPRs` save FIRST, then trigger rebuild. This ensures the setting is persisted even if rebuild fails.
- `rebuildAll()` can run both rebuilds sequentially (simpler) or concurrently with `async let`. Sequential is safer for v1.

---

### Subtask T005 – Wire SettingsService into ServiceContainer

**Purpose**: Register SettingsService in the app-wide DI container so ViewModels can access it.

**Steps**:
1. Open `Reppo/Core/Services/ServiceContainer.swift`.
2. Add a new property:
   ```swift
   let settingsService: any SettingsServiceProtocol
   ```
3. In the `init(repositoryContainer:)`, create the SettingsService AFTER PRService and StatsService:
   ```swift
   // SettingsService — depends on HealthProfileRepository + PRService + StatsService
   let settingsService = SettingsService(
       healthProfileRepository: repositoryContainer.healthProfileRepository,
       prService: prService,
       statsService: statsService
   )
   self.settingsService = settingsService
   ```

**Files**: `Reppo/Core/Services/ServiceContainer.swift` (MODIFY)

**Notes**:
- Place the SettingsService initialization AFTER PRService and StatsService but BEFORE services that might depend on it (currently none do).
- Verify no circular dependencies: SettingsService depends on PRService and StatsService. Neither depends on SettingsService.
- Follow the existing pattern for how other services are initialized and assigned.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| E1RMFormula rawValue mismatch | Use `"epley"`, `"brzycki"`, `"lombardi"` — exact match to existing HealthProfile.e1RMFormula values |
| Circular dependency in ServiceContainer | SettingsService only consumes PRService/StatsService, never the reverse |
| HealthProfile migration | Optional field + nil default = automatic lightweight migration |
| SettingsService rebuild failure | Save setting FIRST, then trigger rebuild. Setting persists even if rebuild errors. |

## Definition of Done Checklist

- [ ] HealthProfile.swift compiles with `defaultRestTimeSeconds: Int?` field
- [ ] E1RMFormula enum has 3 cases with correct `calculate()` values (verify: 100kg x 5 reps = ~116.7 Epley, ~112.5 Brzycki, ~117.5 Lombardi)
- [ ] SettingsServiceProtocol defines all 9 methods
- [ ] SettingsService actor implements all protocol methods
- [ ] ServiceContainer.settingsService is initialized and accessible
- [ ] Project compiles with 0 errors
- [ ] No existing tests broken

## Review Guidance

- Verify E1RMFormula rawValues exactly match existing stored values in HealthProfile.
- Verify SettingsService fetch-update-save pattern uses `fetchOrCreate()` (not `fetch()`).
- Verify rebuild triggers: `updateIncludeWarmupsInVolume` -> `statsService.rebuildAll()`, `updateIncludeWarmupsInPRs` -> `prService.rebuildAll()`.
- Verify no other update methods trigger rebuilds (unitPreference, e1RMFormula, defaultRestTime are display/future-only changes).
- Check ServiceContainer init order — SettingsService must come after PRService and StatsService.

## Activity Log

- 2026-02-28T18:49:28Z – system – lane=planned – Prompt created.
- 2026-02-28T19:18:31Z – claude-opus – shell_pid=48070 – lane=doing – Started implementation via workflow command
- 2026-02-28T19:24:29Z – claude-opus – shell_pid=48070 – lane=for_review – Ready for review: HealthProfile +defaultRestTimeSeconds, E1RMFormula enum (3 cases + calculate), SettingsServiceProtocol (9 methods), SettingsService actor, ServiceContainer wired. Build succeeds 0 errors.
- 2026-02-28T19:25:04Z – claude-opus – shell_pid=50319 – lane=doing – Started review via workflow command
- 2026-03-01T08:20:47Z – claude-opus – shell_pid=50319 – lane=done – Correcting lane: WP01 was reviewed and approved in prior session
