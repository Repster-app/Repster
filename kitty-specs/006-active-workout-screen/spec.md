# Feature Specification: Active Workout Screen

**Feature Branch**: `006-active-workout-screen`
**Created**: 2026-02-19
**Status**: Draft
**Input**: Active workout screen per screen_tree Section 3, design-system Section 6.3, AGENT_RULES Sections 7.3-7.5.

## User Scenarios & Testing

### User Story 1 - Set Entry and Immediate Persistence (Priority: P1)

As a lifter in the gym, I need to enter weight and reps for each set, tap a checkbox to complete it, and have data persisted immediately so nothing is lost if the app is killed.

**Why this priority**: This is the primary interaction loop - the core of the app.

**Independent Test**: Enter weight/reps, tap checkbox, kill app, relaunch - verify set data persists.

**Acceptance Scenarios**:

1. **Given** an active workout with exercises, **When** I enter weight/reps and tap the checkbox, **Then** the set is saved immediately via SetService (not batched to "Finish").
2. **Given** a completed set that is a new PR, **When** save completes, **Then** a gold PR badge (star + "PR", goldSoft bg, gold text) appears on the set row.
3. **Given** a completed set matching an existing PR in a different workout, **When** save completes, **Then** a blue "=" badge appears (cachedPRStatus="matched").
4. **Given** a completed set in the same workout as the PR owner, **When** save completes, **Then** no badge appears (cachedPRStatus=null per same-workout rule).

### User Story 2 - Set Table Layout (Priority: P1)

As a lifter, I need a clear set table with columns adapted to the exercise's trackingType.

**Why this priority**: Wrong columns for the tracking type would confuse users.

**Independent Test**: Open a WEIGHT_REPS exercise, verify 5-column layout; open a DURATION exercise, verify columns adapt.

**Acceptance Scenarios**:

1. **Given** a WEIGHT_REPS exercise, **When** viewing the set table, **Then** columns are: Set# (42pt), Weight (1fr), Reps (1fr), PR (44pt), Check (40pt) per design-system Section 6.3.
2. **Given** a DURATION exercise, **When** viewing the set table, **Then** Weight and Reps columns are replaced with Duration.
3. **Given** a warmup set, **When** viewing the row, **Then** it shows "W" badge and entire row at 0.45-0.5 opacity.
4. **Given** a completed set, **When** viewing the row, **Then** green tint (successSoft) and green checkmark.
5. **Given** any set row, **When** I long-press it, **Then** context menu: Edit Set Type, Delete Set.

### User Story 3 - Exercise Tab Strip (Priority: P1)

As a lifter, I need to switch between exercises via a horizontally scrollable tab strip.

**Why this priority**: Multi-exercise workouts need efficient navigation.

**Independent Test**: Start workout with 3 exercises, tap tabs to switch, verify each shows its own sets.

**Acceptance Scenarios**:

1. **Given** multiple exercises, **When** viewing tab strip, **Then** each has a tab (bgCard, textDim, 8pt radius); active tab is blue with white text.
2. **Given** the tab strip, **When** I long-press a tab, **Then** context menu with "Delete Exercise" (confirmation required).
3. **Given** the tab strip, **When** I drag a tab, **Then** I can reorder exercises.

### User Story 4 - Rest Timer (Priority: P2)

As a lifter, I need a rest timer that auto-starts when I complete a set.

**Why this priority**: Useful gym feature but not blocking core entry.

**Independent Test**: Complete a set, verify countdown starts from exercise.defaultRestTime.

**Acceptance Scenarios**:

1. **Given** exercise with defaultRestTime=180s, **When** I complete a set, **Then** countdown starts from 3:00.
2. **Given** running timer, **When** I tap "+30s", **Then** 30 seconds added.
3. **Given** running timer, **When** I tap "Dismiss", **Then** timer hidden.

### User Story 5 - Finish Workout (Priority: P1)

As a lifter finishing my session, I need to see a summary and confirm completion.

**Why this priority**: Clean session closure for workout lifecycle.

**Independent Test**: Tap "Finish Workout", verify summary sheet with stats, notes, RPE.

**Acceptance Scenarios**:

1. **Given** an active workout, **When** I tap "Finish Workout", **Then** summary sheet shows: date, duration, total volume, total sets, exercise list with set counts and best lifts, PRs hit.
2. **Given** summary sheet, **When** I enter notes and select session RPE (1-10), **Then** saved to Workout.notes and Workout.perceivedEffort.
3. **Given** summary sheet, **When** I tap "Save & Close", **Then** status=completed, endTime set, navigate to Calendar tab.

### Edge Cases

- App killed during workout: status=inProgress persists, resumes on relaunch.
- No exercises yet: empty state prompting to add exercises.
- [+Exercise] mid-workout: opens Exercise List in selection mode (sheet).
- Elapsed timer at top shows time since startTime.
- Row height: 52pt. Bottom nav HIDDEN. Tap targets >= 44pt.
- [+ Add Set] and [+ Add Warmup] buttons below set table.
- Standard iOS number pad for v1 (custom keyboard deferred to v1.1).

## Requirements

### Functional Requirements

- **FR-001**: Active workout screen MUST be focused (NO bottom nav).
- **FR-002**: Set table columns MUST adapt to exercise.trackingType.
- **FR-003**: Sets MUST persist immediately on checkbox tap, not on "Finish".
- **FR-004**: PR badges MUST render based on cachedPRStatus.
- **FR-005**: Exercise tab strip MUST be horizontally scrollable with drag-reorder and long-press delete.
- **FR-006**: Rest timer MUST auto-start on set completion using exercise.defaultRestTime.
- **FR-007**: [+Exercise] MUST open Exercise List in selection mode (sheet).
- **FR-008**: "Finish Workout" MUST show summary sheet.
- **FR-009**: Standard iOS number pad for v1.
- **FR-010**: Warmup rows at 0.45-0.5 opacity with "W" badge.
- **FR-011**: All design tokens per design-system.md.
- **FR-012**: Long-press set row: context menu (Edit Set Type, Delete Set).
- **FR-013**: Elapsed timer at top.

### Key Entities

- **Active Workout Screen**: Focused full-screen set logging experience.
- **Set Table**: Grid layout adapted to trackingType.
- **Exercise Tab Strip**: Horizontal scrollable tabs.
- **Rest Timer**: Auto-countdown from defaultRestTime.
- **Workout Summary Sheet**: Post-workout summary.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Sets persist immediately (survives app kill).
- **SC-002**: PR badges appear correctly within 100ms save budget.
- **SC-003**: Set table columns adapt for all trackingType values.
- **SC-004**: All touch targets >= 44x44pt.
- **SC-005**: Scrolling maintains 60 FPS.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| screen_tree.md | Section 3 | Active Workout full tree |
| design-system.md | Section 6.3 | Set table layout and styles |
| design-system.md | Section 6.4 | Badge styles |
| AGENT_RULES.md | Section 7.3 | Active workout flow |
| AGENT_RULES.md | Section 7.4 | PR celebration rules |
| AGENT_RULES.md | Section 7.6 | Custom keyboard deferred |
