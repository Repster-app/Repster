# Tasks: Xcode Project + SwiftData Models

**Feature**: 001-xcode-project-swiftdata-models
**Generated**: 2026-02-19
**Total Subtasks**: 27
**Total Work Packages**: 3

## Subtask Index

| ID | Description | WP | Parallel |
|----|------------|-----|----------|
| T001 | Create Xcode project "Reppo" (iOS 17+, SwiftUI lifecycle, iPhone only) | WP01 | |
| T002 | Create full directory scaffold (App/, Features/, Core/, Data/, Resources/) | WP01 | |
| T003 | Create TrackingType enum | WP01 | [P] |
| T004 | Create SetType enum | WP01 | [P] |
| T005 | Create EquipmentType enum | WP01 | [P] |
| T006 | Create RecordType enum | WP01 | [P] |
| T007 | Create CachedPRStatus enum | WP01 | [P] |
| T008 | Create Side enum | WP01 | [P] |
| T009 | Create MovementPattern enum | WP01 | [P] |
| T010 | Create UnitPreference enum | WP01 | [P] |
| T011 | Create WorkoutStatus enum | WP01 | [P] |
| T012 | Create WorkoutSet model (28 stored fields + 2 computed) | WP02 | [P] |
| T013 | Create Workout model (11 fields + status) | WP02 | [P] |
| T014 | Create Exercise model (14 fields) | WP02 | [P] |
| T015 | Create ExerciseStats model (14 fields) | WP02 | [P] |
| T016 | Create PerformanceRecord model (9 fields) | WP02 | [P] |
| T017 | Create BodyweightEntry model (6 fields) | WP02 | [P] |
| T018 | Create HealthProfile model (7 fields + settings) | WP02 | [P] |
| T019 | Create Program model (7 fields) | WP02 | [P] |
| T020 | Create ProgramExercise model (10 fields incl. timestamps) | WP02 | [P] |
| T021 | Create PlannedWorkout model (6 fields incl. timestamps) | WP02 | [P] |
| T022 | Create PlannedSet model (9 fields incl. timestamps) | WP02 | [P] |
| T023 | Create ModelContainerSetup.swift with schema config | WP03 | |
| T024 | Create ReppoApp.swift entry point with ModelContainer and placeholder ContentView | WP03 | |
| T025 | Create UnitConversion.swift extension (kg<->lbs, m<->ft helpers) | WP03 | [P] |
| T026 | Add seed_exercises.json to Resources/ (placeholder [] if not pre-existing; feature 012 populates) | WP03 | [P] |
| T027 | Verify project builds with zero errors and zero warnings | WP03 | |

## Work Packages

---

### WP01: Xcode Project Scaffold + Enums

**Priority**: P1 (foundation - everything depends on this)
**Dependencies**: None
**Estimated Prompt Size**: ~450 lines
**Subtasks**: T001-T011 (11 subtasks - but 9 are trivially parallel enum files, each ~15 lines of code)
**Implementation command**: `spec-kitty implement WP01`

**Goal**: Create the Reppo Xcode project with correct target settings, full directory structure per AGENT_RULES Section 2, and all 9 enum types from specdoc Appendix A.

**Independent Test**: Project opens in Xcode, directory structure matches spec, all enums compile.

**Included Subtasks**:
- [x] T001: Create Xcode project "Reppo" (com.magnusespensen.Reppo, iOS 17+, SwiftUI, iPhone)
- [x] T002: Create directory scaffold (App/, Features/{Workout,Exercise,History,Programs,Settings}/{Views,ViewModels}, Core/{Services,Repositories,Extensions}, Data/{Models,Enums,Persistence}, Resources/)
- [x] T003: TrackingType enum (5 cases)
- [x] T004: SetType enum (13 cases)
- [x] T005: EquipmentType enum (10 cases)
- [x] T006: RecordType enum (3 cases)
- [x] T007: CachedPRStatus enum (3 cases)
- [x] T008: Side enum (3 cases)
- [x] T009: MovementPattern enum (7 cases)
- [x] T010: UnitPreference enum (2 cases)
- [x] T011: WorkoutStatus enum (2 cases)

**Implementation Sketch**:
1. Create Xcode project manually via Xcode (File → New → App) — do NOT use `swift package init` (produces a Swift Package, not an iOS .xcodeproj). Alternatively use `xcodegen` with a project.yml if preferred.
2. Configure target: iOS 17.0, iPhone only, SwiftUI lifecycle
3. Create all directory folders with placeholder files where needed
4. Create all 9 enum files in Data/Enums/ (parallel - no interdependencies)
5. Verify enums compile

**Risks**:
- Xcode project creation from CLI may need manual .xcodeproj adjustments
- Ensure bundle ID is exactly com.magnusespensen.Reppo

---

### WP02: SwiftData Models (All 11 @Model Classes)

**Priority**: P1 (data layer foundation)
**Dependencies**: WP01 (enums must exist for model field types)
**Estimated Prompt Size**: ~500 lines
**Subtasks**: T012-T022 (11 subtasks - all parallel, each is an independent model file)
**Implementation command**: `spec-kitty implement WP02 --base WP01`

**Goal**: Implement all 11 SwiftData @Model classes with exact fields, types, nullability, and computed properties per specdoc Section 6 and plan.md Phase 1.

**Independent Test**: All 11 models compile, field types match specdoc, hasData and volume computed properties work correctly.

**Included Subtasks**:
- [x] T012: WorkoutSet (28 stored + hasData + volume computed)
- [x] T013: Workout (11 fields + status: WorkoutStatus)
- [x] T014: Exercise (14 fields including secondaryMuscles: [String])
- [x] T015: ExerciseStats (14 fields - rebuildable cache)
- [x] T016: PerformanceRecord (9 fields - unified PR table)
- [x] T017: BodyweightEntry (6 fields)
- [x] T018: HealthProfile (7 fields + settings from AGENT_RULES S8)
- [x] T019: Program (7 fields)
- [x] T020: ProgramExercise (10 fields incl. createdAt/updatedAt per FR-014)
- [x] T021: PlannedWorkout (6 fields incl. createdAt/updatedAt per FR-014)
- [x] T022: PlannedSet (9 fields incl. createdAt/updatedAt per FR-014)

**Implementation Sketch**:
1. Create all 11 model files in Data/Models/ (all parallel)
2. Each model: import SwiftData, @Model class, stored properties with correct types, init with defaults
3. WorkoutSet: add hasData and volume computed properties
4. Verify all models compile with enums from WP01

**Risks**:
- WorkoutSet has 28+ stored fields - careful with nullability
- SwiftData requires Codable enums with String raw values (already handled in WP01)
- No @Relationship annotations (UUID foreign keys per plan decision)

---

### WP03: ModelContainer, App Entry Point, and Build Verification

**Priority**: P1 (wires everything together)
**Dependencies**: WP02 (models must exist for ModelContainer registration)
**Estimated Prompt Size**: ~300 lines
**Subtasks**: T023-T027 (5 subtasks)
**Implementation command**: `spec-kitty implement WP03 --base WP02`

**Goal**: Configure the SwiftData ModelContainer, create the app entry point with placeholder UI, add unit conversion helpers and seed data file, and verify the entire project builds cleanly.

**Independent Test**: App launches in simulator showing placeholder view, ModelContainer initializes without errors, build has zero errors and zero warnings.

**Included Subtasks**:
- [x] T023: ModelContainerSetup.swift (factory method registering all 11 model types)
- [x] T024: ReppoApp.swift (@main, WindowGroup, modelContainer, placeholder ContentView)
- [x] T025: UnitConversion.swift (kg<->lbs, m<->ft, seconds formatting helpers)
- [x] T026: Copy seed_exercises.json to Resources/ — source file is pre-existing in the repository root (created by feature 012 spec planning); if absent, create a minimal placeholder JSON array (`[]`) so the bundle resource target is satisfied and feature 012 can populate it later
- [x] T027: Full build verification (zero errors, zero warnings, simulator launch)

**Implementation Sketch**:
1. Create ModelContainerSetup.swift in Data/Persistence/
2. Create ReppoApp.swift in App/ with ModelContainer wired to all models
3. Create placeholder ContentView.swift (dark background, "Reppo" text)
4. Create UnitConversion.swift in Core/Extensions/
5. Copy seed_exercises.json to Resources/
6. Build and verify in simulator

**Risks**:
- ModelContainer misconfiguration could cause runtime crash (not compile-time)
- seed_exercises.json must be added to Xcode target's bundle resources

---

## Parallelization Opportunities

- **Within WP01**: All 9 enum files (T003-T011) are fully parallel
- **Within WP02**: All 11 model files (T012-T022) are fully parallel
- **Within WP03**: T023, T025, T026 are parallel; T024 depends on T023; T027 depends on all
- **Between WPs**: Sequential only (WP01 -> WP02 -> WP03) due to compile dependencies

## MVP Scope

**WP01 alone** gives a buildable project with proper structure. **WP01+WP02** gives the complete data layer. All three WPs are needed for the feature to be complete.
