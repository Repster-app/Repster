# Feature Specification: Workout + Exercise + Bodyweight Services

**Feature Branch**: `005-workout-exercise-bodyweight-services`
**Created**: 2026-02-19
**Status**: Draft
**Input**: Workout lifecycle per specdoc Sections 3 and 6.2. Exercise CRUD and trackingType immutability per specdoc Section 5. Service responsibilities per AGENT_RULES Section 6.

## User Scenarios & Testing

### User Story 1 - Workout Lifecycle (Priority: P1)

As a lifter, I need to start a workout (status=inProgress), add sets during the session, and finish it (status=completed). If the app is killed mid-workout, it should resume automatically on relaunch.

**Why this priority**: The workout lifecycle is the core user flow. Without it, nothing else works.

**Independent Test**: Start a workout, verify status=inProgress, add a set, kill and relaunch app, verify it navigates back to the active workout.

**Acceptance Scenarios**:

1. **Given** no active workout, **When** I start a new workout, **Then** a Workout is created with status=inProgress, startTime=now, and date=today.
2. **Given** a workout with status=inProgress, **When** the app launches, **Then** it detects the active workout and navigates to it.
3. **Given** an active workout, **When** I tap "Finish Workout", **Then** status flips to completed, endTime is set, and duration is calculated.
4. **Given** an active workout, **When** sets are added, **Then** sets persist immediately (not on "Finish" - Finish is a UI action not a data commit).

### User Story 2 - Exercise CRUD (Priority: P1)

As a lifter, I need to create, edit, and view exercises with proper metadata, and the system must prevent changing trackingType once sets exist.

**Why this priority**: Exercises are required before sets can be logged.

**Independent Test**: Create an exercise, add a set to it, then attempt to change trackingType - verify it is blocked.

**Acceptance Scenarios**:

1. **Given** the exercise form, **When** I create an exercise with name, equipmentType, trackingType, primaryMuscle, bodyweightFactor, **Then** it is persisted with a UUID and timestamps.
2. **Given** an exercise with no sets, **When** I change its trackingType, **Then** the change is allowed.
3. **Given** an exercise with existing sets, **When** I attempt to change trackingType, **Then** the change is BLOCKED with an error (per specdoc Section 5.6).
4. **Given** an exercise with sets, **When** I change its name or primaryMuscle, **Then** the change is allowed (low-risk mutable fields).
5. **Given** an exercise with sets, **When** I change bodyweightFactor, **Then** the change is allowed but triggers an ExerciseStats and PR rebuild for that exercise.

### User Story 3 - Bodyweight Service (Priority: P2)

As a lifter, I need to log my bodyweight so effectiveWeight calculations are accurate for bodyweight exercises (pull-ups, dips, etc.).

**Why this priority**: Required for correct effectiveWeight on exercises with bodyweightFactor > 0.

**Independent Test**: Log a bodyweight entry, save a pull-up set, verify effectiveWeight uses the closest bodyweight.

**Acceptance Scenarios**:

1. **Given** a bodyweight entry of 80kg on Jan 15, **When** I save a set on Jan 16 for pull-ups (bodyweightFactor=0.65), **Then** effectiveWeight uses 80kg as the closest bodyweight.
2. **Given** no bodyweight entries, **When** effectiveWeight is calculated, **Then** bodyweight portion is skipped (effectiveWeight = raw weight) and user is warned.
3. **Given** multiple bodyweight entries, **When** closest is requested for a date, **Then** the entry with the nearest date (before or after) is returned.

### User Story 4 - Workout Deletion (Priority: P2)

As a lifter, I need to delete a workout and have all its sets and derived data cleaned up.

**Why this priority**: Data management - users need to remove erroneous workouts.

**Independent Test**: Delete a workout, verify all its sets are deleted and PRs/stats recomputed.

**Acceptance Scenarios**:

1. **Given** a workout with 10 sets, **When** I delete the workout, **Then** all 10 sets are deleted (hard delete).
2. **Given** deleted sets included PR owners, **When** deletion completes, **Then** PRs and ExerciseStats are recomputed for affected exercises.

### Edge Cases

- Starting a workout when one is already inProgress: block or warn (only one active workout at a time).
- Exercise with 0 sets: all metadata fields are editable.
- Bodyweight lookup with entries both before and after the target date: pick the nearest.
- Deleting an exercise that has sets: must cascade-delete sets and recompute PRs/stats.

## Requirements

### Functional Requirements

- **FR-001**: WorkoutService MUST create workouts with status=inProgress and set startTime.
- **FR-002**: WorkoutService MUST support finishing a workout (status=completed, endTime set, duration calculated).
- **FR-003**: WorkoutService MUST detect and return any workout with status=inProgress on app launch.
- **FR-004**: WorkoutService MUST enforce only one active workout at a time.
- **FR-005**: ExerciseService MUST enforce trackingType immutability once sets exist (per specdoc Section 5.6).
- **FR-006**: ExerciseService MUST trigger stats/PR rebuild when calculation-critical fields change (bodyweightFactor, unilateral, bilateralLoadFactor, equipmentType) per specdoc Section 5.6.
- **FR-007**: ExerciseService MUST support name search for autocomplete.
- **FR-008**: BodyweightService MUST support CRUD for bodyweight entries.
- **FR-009**: BodyweightService MUST support closest-weight lookup by date for effectiveWeight calculation.
- **FR-010**: Workout deletion MUST cascade to all contained sets with proper PR/stats recomputation.
- **FR-011**: Exercise deletion MUST cascade to all linked sets, PRs, and ExerciseStats (hard delete, everything rebuildable).
- **FR-012**: All services MUST use repositories for data access, never ModelContext directly.

### Key Entities

- **WorkoutService**: Workout CRUD, active workout management, finish workflow.
- **ExerciseService**: Exercise CRUD, name search, trackingType immutability enforcement.
- **BodyweightService**: BodyweightEntry CRUD, closest-weight lookup.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Active workout survives app kill and is restored on relaunch.
- **SC-002**: trackingType change is blocked when sets exist for the exercise.
- **SC-003**: Closest bodyweight lookup returns the correct entry for any target date.
- **SC-004**: Workout/exercise deletion cascades correctly with no orphaned data.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| specdoc.md | Section 3 | Workout definition and properties |
| specdoc.md | Section 5 | Exercise metadata and mutability rules |
| specdoc.md | Section 5.6 | Metadata mutability classification |
| specdoc.md | Section 6.2 | Workout schema |
| specdoc.md | Section 6.6 | BodyweightEntry schema |
| AGENT_RULES.md | Section 6 | Service responsibilities |
| AGENT_RULES.md | Section 7.3 | Active workout flow and status field |
