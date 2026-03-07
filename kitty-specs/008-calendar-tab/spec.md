# Feature Specification: Calendar Tab

**Feature Branch**: `008-calendar-tab`
**Created**: 2026-02-19
**Status**: Draft
**Input**: screen_tree Section 2. Muscle group dots and workout detail.

## User Scenarios & Testing

### User Story 1 - Calendar View with Workout Indicators (Priority: P1)

As a lifter, I need a calendar showing colored dots on dates I trained, representing muscle groups worked, so I can visualize my training frequency and distribution.

**Why this priority**: Primary history view - the default landing screen.

**Independent Test**: View calendar with past workouts, verify colored dots appear on correct dates.

**Acceptance Scenarios**:

1. **Given** the calendar tab, **When** I view it, **Then** I see vertically scrollable month grids.
2. **Given** dates with workouts, **When** viewing the calendar, **Then** colored dots below the date represent the muscle groups worked (derived from exercises in that workout).
3. **Given** today's date, **When** viewing the calendar, **Then** today has a blue fill indicator.
4. ~~**Given** a scheduled future session, **When** viewing the calendar, **Then** it shows a blue outline.~~ *Deferred — requires Programs feature (v1.1). No mechanism to create scheduled sessions in v1.*
5. **Given** the calendar, **When** I tap "Today" button, **Then** it scrolls to the current date.

### User Story 2 - Workout Detail Inline (Priority: P1)

As a lifter, I need to tap a date and see the workout detail inline below the calendar with full exercise cards.

**Why this priority**: This is how users review past workouts.

**Independent Test**: Tap a date with a workout, verify detail appears below with summary stats and exercise cards.

**Acceptance Scenarios**:

1. **Given** a date with a workout, **When** I tap it, **Then** workout detail appears inline below the calendar.
2. **Given** the workout detail, **When** viewing it, **Then** I see summary stats (volume, exercises, sets).
3. **Given** the workout detail, **When** viewing exercise cards, **Then** each shows sets, weights, reps, and PR badges.
4. **Given** an exercise card in workout detail, **When** I tap it, **Then** it navigates (push) to Exercise Detail (reused component from feature 007).

### User Story 3 - Multiple Workouts per Date (Priority: P2)

As a lifter who sometimes does two-a-day sessions, I need the calendar to handle multiple workouts on the same date.

**Why this priority**: Less common but must work correctly.

**Independent Test**: Create two workouts on the same date, tap date, verify both appear.

**Acceptance Scenarios**:

1. **Given** two workouts on one date, **When** I tap the date, **Then** both workouts are shown in the detail area.

### Edge Cases

- Date with no workout: tap shows "No workout" or empty state.
- Very long workout with many exercises: workout detail should scroll.
- Muscle group dots: derived from exercises' primaryMuscle across all sets in that workout.
- Bottom nav visible on this screen.
- Set rows in workout detail are read-only (not editable from calendar).

## Requirements

### Functional Requirements

- **FR-001**: Calendar MUST display vertically scrollable month grids.
- **FR-002**: Dates with workouts MUST show colored dots representing muscle groups worked.
- **FR-003**: Today MUST be highlighted with blue fill.
- **FR-004**: "Today" button MUST scroll to current date.
- **FR-005**: Tapping a date MUST show workout detail in the lower section of a split-view layout (calendar scrolls independently above, detail scrolls independently below).
- **FR-006**: Workout detail MUST show summary stats strip (volume, exercises, sets).
- **FR-007**: Workout detail MUST show exercise cards with sets, weights, reps, PR badges.
- **FR-008**: Tapping an exercise card MUST navigate to Exercise Detail (reused component).
- **FR-009**: Bottom navigation MUST be visible on this screen.
- **FR-010**: Muscle group dots MUST be derived from the exercises performed (primaryMuscle of each exercise in the workout).

### Key Entities

- **Calendar View**: Month grid with workout dot indicators.
- **Workout Detail (inline)**: Summary stats + exercise cards for selected date.
- **Muscle Group Dots**: Color-coded indicators derived from workout exercises.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Calendar loads and displays within 200ms screen transition budget.
- **SC-002**: Muscle group dots appear on correct dates matching workout data.
- **SC-003**: Workout detail appears inline without navigation transition.
- **SC-004**: Exercise cards show correct PR badges from cachedPRStatus.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| screen_tree.md | Section 2 | Calendar tab full tree |
| screen_tree.md | Section 8 | Reused components (Exercise Detail, Set Row, Summary Stats) |
| design-system.md | Section 6.2 | Card patterns |
| design-system.md | Section 6.4 | PR badge styles |
| specdoc.md | Section 6.2 | Workout schema |
