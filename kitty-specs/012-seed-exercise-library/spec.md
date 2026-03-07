# Feature Specification: Seed Exercise Library

**Feature Branch**: `012-seed-exercise-library`
**Created**: 2026-02-19
**Status**: Ready for Implementation
**Input**: Load seed_exercises.json on first launch. 67 exercises with full metadata.

## User Scenarios & Testing

### User Story 1 - First Launch Seeding (Priority: P1)

As a new user on first launch, I need 67 pre-configured exercises available immediately so I can start logging workouts without manual exercise setup.

**Why this priority**: Empty exercise list on first launch is a terrible UX.

**Independent Test**: Fresh install, launch app, verify 67 exercises are available in the Exercise List with correct metadata.

**Acceptance Scenarios**:

1. **Given** first launch (empty database), **When** the app starts, **Then** 67 exercises from seed_exercises.json are created in the database.
2. **Given** seeded exercises, **When** I browse the exercise list, **Then** each exercise has: name, equipmentType, trackingType, primaryMuscle, secondaryMuscles, movementPattern, unilateral, bodyweightFactor, weightIncrement, defaultRestTime - all matching the JSON file.
3. **Given** a seeded exercise like "Pull-up", **When** I inspect it, **Then** bodyweightFactor=0.65, trackingType=WEIGHT_REPS, equipmentType=bodyweight, primaryMuscle=lats.
4. **Given** seed has run once, **When** the app launches again, **Then** seeding does NOT run again (idempotent).

### User Story 2 - Correct Metadata Mapping (Priority: P1)

As a developer, I need every field in seed_exercises.json correctly mapped to the Exercise model with proper enum conversions.

**Why this priority**: Incorrect mapping would break trackingType, PR calculations, or bodyweightFactor.

**Independent Test**: Verify all 67 exercises have valid enum values for equipmentType, trackingType, and movementPattern.

**Acceptance Scenarios**:

1. **Given** the seed data, **When** mapping equipmentType, **Then** values like "barbell", "dumbbell", "bodyweight", "cable", "machine_plate", "machine_pin" map to the EquipmentType enum.
2. **Given** the seed data, **When** mapping trackingType, **Then** "WEIGHT_REPS" maps to TrackingType.weightReps, "DURATION" maps to TrackingType.duration, etc.
3. **Given** the seed data, **When** mapping movementPattern, **Then** values like "squat", "press", "pull", "hinge" map to the MovementPattern enum.
4. **Given** exercises with bodyweightFactor > 0, **When** inspected, **Then** values match the JSON (e.g., Pull-up=0.65, Dip=0.80, Push-up=0.64).
5. **Given** exercises with secondaryMuscles, **When** inspected, **Then** the array is correctly stored (e.g., Bench Press has ["shoulders", "triceps"]).

### Edge Cases

- App upgrade (not first launch): seed should not overwrite user-modified exercises.
- User deletes a seed exercise: it stays deleted (no re-seeding on next launch).
- seed_exercises.json must be bundled in the app Resources.
- Seed operation should be fast (67 exercises should insert in under 1 second).
- If seed JSON has an unknown enum value: skip that exercise and log a warning.

## Requirements

### Functional Requirements

- **FR-001**: seed_exercises.json MUST be bundled in the app's Resources.
- **FR-002**: On first launch (empty Exercise table), all 67 exercises MUST be created.
- **FR-003**: Seeding MUST be idempotent - it runs only when the Exercise table is empty.
- **FR-004**: All JSON fields MUST map correctly to Exercise model fields: name, equipmentType, trackingType, primaryMuscle, secondaryMuscles, movementPattern, unilateral, bodyweightFactor, weightIncrement, defaultRestTime.
- **FR-005**: Enum values in JSON MUST be converted to Swift enum cases (e.g., "WEIGHT_REPS" -> TrackingType.weightReps).
- **FR-006**: Seeding MUST NOT overwrite existing exercises on subsequent launches.
- **FR-007**: Seeding MUST complete within 1 second.
- **FR-008**: Seeding MUST handle invalid JSON entries gracefully (skip and log).

### Key Entities

- **seed_exercises.json**: 67 exercises with full metadata, bundled in Resources.
- **SeedService or AppInitializer**: Checks if Exercise table is empty, loads and parses JSON, creates Exercise records.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All 67 exercises are present after first launch.
- **SC-002**: Every exercise has valid enum values for all enum fields.
- **SC-003**: Exercises with bodyweightFactor > 0 have correct values matching the JSON.
- **SC-004**: Seeding completes in under 1 second.
- **SC-005**: Second launch does not duplicate exercises.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| seed_exercises.json | Entire file | 67 exercises with full metadata |
| specdoc.md | Section 6.3 | Exercise model fields |
| specdoc.md | Appendix A | Enum values for trackingType, equipmentType, movementPattern |
