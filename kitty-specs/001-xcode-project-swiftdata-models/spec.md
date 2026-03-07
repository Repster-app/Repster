# Feature Specification: Xcode Project + SwiftData Models

**Feature Branch**: `001-xcode-project-swiftdata-models`
**Created**: 2026-02-19
**Status**: Draft
**Input**: Create the Xcode project and all SwiftData models, enums, and file structure per project documentation.

## User Scenarios & Testing

### User Story 1 - Project Foundation (Priority: P1)

As a developer, I need an Xcode project with the correct target settings (iOS 17+, SwiftUI lifecycle, iPhone only) and file organization so all subsequent features have a buildable foundation.

**Why this priority**: Nothing else can be built without a compilable project.

**Independent Test**: The project opens in Xcode, builds successfully targeting iOS 17+ iPhone simulator, and launches showing a placeholder root view.

**Acceptance Scenarios**:

1. **Given** a fresh clone, **When** I open the .xcodeproj in Xcode, **Then** it builds with zero errors targeting iOS 17+ iPhone simulator.
2. **Given** the project, **When** I inspect the target settings, **Then** deployment target is iOS 17.0, devices is iPhone, and the app lifecycle is SwiftUI (`@main` App struct).
3. **Given** the project, **When** I examine the file structure, **Then** it matches the organization in AGENT_RULES Section 2 (App/, Features/, Core/, Data/, Resources/).

### User Story 2 - SwiftData Models (Priority: P1)

As a developer, I need all SwiftData `@Model` classes accurately reflecting the specdoc Section 6 schema so that services and repositories can be built on top of them.

**Why this priority**: The data models are the foundation for every service, repository, and screen.

**Independent Test**: All @Model classes compile, have correct field types/nullability, computed properties work, and relationships are expressed.

**Acceptance Scenarios**:

1. **Given** the models, **When** I inspect `WorkoutSet`, **Then** it has all stored fields from specdoc Section 6.1 with correct types and nullability, plus `hasData` and `volume` as computed properties.
2. **Given** the models, **When** I look for the Swift `Set` collision, **Then** the set model is named `WorkoutSet` (per AGENT_RULES Section 3.1).
3. **Given** all models, **When** I check unit storage, **Then** weight fields store kg (Double), distance stores meters (Double), duration stores seconds (Int) - no imperial units stored anywhere.
4. **Given** `WorkoutSet`, **When** I check `hasData`, **Then** it returns true only when `(weight > 0 AND reps > 0) OR durationSeconds > 0 OR distanceMeters > 0` per specdoc Section 1.2.
5. **Given** `Workout`, **When** I inspect fields, **Then** it has a `status` field (inProgress/completed) per AGENT_RULES Section 7.3.

### User Story 3 - All Enumerations (Priority: P1)

As a developer, I need all enum types from specdoc Appendix A defined as Swift enums so they can be used by models and services.

**Why this priority**: Enums are referenced by every model and must exist for compilation.

**Independent Test**: All enums compile and have the exact cases listed in specdoc Appendix A.

**Acceptance Scenarios**:

1. **Given** the enums, **When** I check `TrackingType`, **Then** it has cases: weightReps, duration, weightDistance, weightRepsDuration, custom.
2. **Given** the enums, **When** I check `SetType`, **Then** it has all 13 cases from Appendix A.
3. **Given** the enums, **When** I check `EquipmentType`, **Then** it has all 10 cases.
4. **Given** the enums, **When** I check `RecordType`, **Then** it has cases: repMax, e1RM, maxVolume.
5. **Given** the enums, **When** I check `CachedPRStatus`, **Then** it has cases: current, matched, previous.
6. **Given** the enums, **When** I check remaining enums (Side, MovementPattern, UnitPreference, WorkoutStatus), **Then** all have correct cases per Appendix A and AGENT_RULES.

### Edge Cases

- SwiftData schema migration: Use lightweight migration only for v1, no custom migration logic.
- Swift keyword collision: Set model named `WorkoutSet`.
- `secondaryMuscles` on Exercise: SwiftData handles arrays of Codable types natively.
- `cachedPRStatus` is nullable (Optional enum).

## Requirements

### Functional Requirements

- **FR-001**: Project MUST target iOS 17.0+ with SwiftUI lifecycle (`@main` App struct).
- **FR-002**: Project MUST be iPhone-only (no iPad).
- **FR-003**: File structure MUST follow AGENT_RULES Section 2: App/, Features/ (Workout, Exercise, History, Programs, Settings), Core/ (Services, Repositories, Extensions), Data/ (Models, Persistence), Resources/.
- **FR-004**: `WorkoutSet` model MUST have all stored fields from specdoc Section 6.1 with correct types/nullability, plus computed `hasData` and `volume`.
- **FR-005**: `Workout` model MUST have all fields from specdoc Section 6.2 plus `status` field (WorkoutStatus enum) per AGENT_RULES Section 7.3.
- **FR-006**: `Exercise` model MUST have all fields from specdoc Section 6.3 including bodyweightFactor (Double, 0.0-1.0).
- **FR-007**: `ExerciseStats` model MUST have all fields from specdoc Section 6.4.
- **FR-008**: `PerformanceRecord` model MUST have all fields from specdoc Section 6.5.
- **FR-009**: `BodyweightEntry` model MUST have all fields from specdoc Section 6.6.
- **FR-010**: `HealthProfile` model MUST have all fields from specdoc Section 6.7 plus settings from AGENT_RULES Section 8 (includeWarmupsInVolume, includeWarmupsInPRs, e1RMFormula).
- **FR-011**: Program tables (Program, ProgramExercise, PlannedWorkout, PlannedSet) per specdoc Section 6.8.
- **FR-012**: All enum types from specdoc Appendix A defined as Swift enums (String, Codable, CaseIterable).
- **FR-013**: All weight stored in kg, distance in meters, duration in seconds. No imperial storage.
- **FR-014**: All models have createdAt/updatedAt timestamps and UUID ids.
- **FR-015**: SwiftData ModelContainer configured in the App struct.

### Non-Functional Requirements

- **NFR-001**: App cold launch MUST complete in < 2 seconds (constitution performance target).
- **NFR-002**: Data model design MUST support 50,000+ WorkoutSet rows without degradation (scale target per constitution).
- **NFR-003**: ModelContainer initialization MUST NOT trigger any index rebuild, cache rebuild, or PR recomputation at startup (constitution "No Startup Rebuild" principle).
- **NFR-004**: No third-party dependencies introduced in this feature — SwiftUI and SwiftData only.

### Key Entities

- **WorkoutSet**: Atomic performance record (named to avoid Swift.Set collision).
- **Workout**: Session container with status lifecycle (inProgress/completed).
- **Exercise**: Metadata defining tracking and interpretation. trackingType immutable once sets exist.
- **ExerciseStats**: Rebuildable per-exercise aggregate cache.
- **PerformanceRecord**: Unified PR table for repMax, e1RM, maxVolume.
- **BodyweightEntry**: Bodyweight history for effectiveWeight calculations.
- **HealthProfile**: Single-row local user profile with settings.
- **Program/ProgramExercise/PlannedWorkout/PlannedSet**: Planning tables (schema only for v1).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Project builds with zero errors in Xcode targeting iOS 17.0 iPhone simulator.
- **SC-002**: All 11 @Model classes compile and have correct field types per specdoc Section 6.
- **SC-003**: All 9+ enum types defined with correct cases per specdoc Appendix A.
- **SC-004**: No imperial units stored in any model field.
- **SC-005**: WorkoutSet.hasData computed property matches specdoc Section 1.2 logic.
- **SC-006**: File organization matches AGENT_RULES Section 2.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| specdoc.md | Section 6 (all) | Complete schema for all tables |
| specdoc.md | Appendix A | All enumeration values |
| specdoc.md | Section 1.2 | hasData logic |
| specdoc.md | Section 5.4 | effectiveWeight formula |
| AGENT_RULES.md | Section 2 | File organization |
| AGENT_RULES.md | Section 3 | Data model rules (naming, units, effectiveWeight) |
| AGENT_RULES.md | Section 7.3 | Workout status field |
| AGENT_RULES.md | Section 8 | User settings on HealthProfile |
| tech_stack_and_architecture.md | Section 2 | Platform decisions |
