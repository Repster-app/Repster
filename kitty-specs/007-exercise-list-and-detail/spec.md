# Feature Specification: Exercise List + Detail

**Feature Branch**: `007-exercise-list-and-detail`
**Created**: 2026-02-19
**Status**: Draft
**Input**: Exercise list from screen_tree Section 3, exercise detail from screen_tree Section 2, create/edit sheet from screen_tree Section 3.

## User Scenarios & Testing

### User Story 1 - Exercise List Browse Mode (Priority: P1)

As a lifter, I need to browse my exercise library with search, filter by muscle group, and sort options to find exercises quickly.

**Why this priority**: Entry point for both workouts and exercise browsing.

**Independent Test**: Open exercise list, search for "squat", filter by "quads", sort by A-Z, verify correct results.

**Acceptance Scenarios**:

1. **Given** the exercise list, **When** I type in the search bar, **Then** exercises are filtered by name in real-time.
2. **Given** the exercise list, **When** I tap a muscle group filter pill, **Then** only exercises with that primaryMuscle are shown.
3. **Given** the exercise list, **When** I select a sort option, **Then** exercises reorder (A-Z, most recent, most used).
4. **Given** an exercise card, **When** I view it, **Then** it shows: name, muscle, equipment, tracking type, last performed, best lift.
5. **Given** browse mode (no active workout), **When** I tap an exercise card, **Then** it navigates to Exercise Detail (pushed).

### User Story 2 - Exercise List Selection Mode (Priority: P1)

As a lifter starting a workout, I need to select multiple exercises from the list and start a workout with them.

**Why this priority**: This is the workout initiation flow.

**Independent Test**: Select 3 exercises, verify "Start Workout (3)" button appears, tap it, verify active workout starts.

**Acceptance Scenarios**:

1. **Given** the exercise list in selection mode, **When** I tap exercise cards, **Then** they toggle selection state and a count badge updates.
2. **Given** selected exercises, **When** I view the bottom, **Then** "Start Workout (N)" button is visible with the count.
3. **Given** "Start Workout (N)" tapped, **When** the workout starts, **Then** Active Workout screen opens with those exercises as tabs.

### User Story 3 - Exercise Detail (Reused Component) (Priority: P1)

As a lifter, I need to see an exercise's history, PRs, and charts in a detail view that is reused across Calendar, Exercise List, and Active Workout.

**Why this priority**: Core informational component used in 3 locations.

**Independent Test**: Open exercise detail from Calendar, Exercise List, and Active Workout - verify same component with History/PRs/Charts tabs.

**Acceptance Scenarios**:

1. **Given** exercise detail, **When** I view the [History] tab, **Then** past sessions for this exercise are shown, newest first.
2. **Given** exercise detail, **When** I view the [PRs] tab, **Then** the suffix-max filtered rep-max PR table is displayed.
3. **Given** exercise detail, **When** I view the [Charts] tab, **Then** e1RM trend and volume per session charts are shown.

### User Story 4 - Create/Edit Exercise (Priority: P1)

As a lifter, I need to create new exercises and edit existing ones via a sheet form.

**Why this priority**: Users need custom exercises beyond the seed library.

**Independent Test**: Tap [+ New], fill out form, save - verify exercise appears in list with correct metadata.

**Acceptance Scenarios**:

1. **Given** the exercise list, **When** I tap [+ New], **Then** a sheet opens with: name, equipment type, tracking type, primary muscle, secondary muscles, movement pattern, unilateral toggle, bodyweight factor, weight increment, default rest time.
2. **Given** the create form, **When** I fill in required fields and save, **Then** the exercise is created with correct metadata.
3. **Given** an existing exercise with no sets, **When** I edit it, **Then** all fields including trackingType are editable.
4. **Given** an existing exercise WITH sets, **When** I edit it, **Then** trackingType is locked/disabled (immutable per specdoc Section 5.6).

### Edge Cases

- Exercise list with 0 exercises (fresh install before seed loads): show empty state.
- Muscle group filter pills: horizontally scrollable, multiple can be active.
- Exercise detail opened from Active Workout sub-tabs: same component, embedded not pushed.
- Search with no results: show "No exercises found" message.
- Deleting an exercise from detail: must cascade-delete sets and recompute stats.

## Requirements

### Functional Requirements

- **FR-001**: Exercise list MUST support real-time search by name.
- **FR-002**: Exercise list MUST support filtering by muscle group via horizontal pill strip.
- **FR-003**: Exercise list MUST support sorting: A-Z, most recent, most used.
- **FR-004**: Exercise cards MUST show: name, muscle, equipment, tracking type, last performed, best lift.
- **FR-005**: Exercise list MUST have two modes: browse (tap -> detail) and selection (tap -> toggle, "Start Workout" button).
- **FR-006**: Exercise Detail MUST be a reusable component with [History], [PRs], [Charts] tabs (per screen_tree Section 8).
- **FR-007**: PRs tab MUST display suffix-max filtered rep-max table per specdoc Section 7.4.
- **FR-008**: Create/Edit Exercise sheet MUST include all fields from specdoc Section 6.3.
- **FR-009**: trackingType MUST be locked/disabled when exercise has associated sets.
- **FR-010**: Bottom nav MUST be visible when browsing, HIDDEN when in workout flow.

### Key Entities

- **Exercise List**: Searchable, filterable, sortable list with browse/selection modes.
- **Exercise Detail**: Reused component with History/PRs/Charts tabs.
- **Create/Edit Exercise Sheet**: Full form for exercise metadata.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Search returns results in under 200ms for 200+ exercises.
- **SC-002**: Exercise Detail component works identically in all 3 locations (Calendar, List, Active Workout).
- **SC-003**: trackingType editing is blocked when exercise has sets.
- **SC-004**: PR table displays correct suffix-max filtered results.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| screen_tree.md | Section 3 | Exercise List full tree |
| screen_tree.md | Section 2 | Exercise Detail (reused) |
| screen_tree.md | Section 8 | Reused components list |
| specdoc.md | Section 5 | Exercise metadata and mutability |
| specdoc.md | Section 6.3 | Exercise model fields |
| specdoc.md | Section 7.4 | Suffix-max PR display |
| design-system.md | Section 6.2 | Card patterns |
