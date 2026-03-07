# Feature Specification: Edit Historic Workout

**Feature Branch**: `015-edit-historic-workout`
**Created**: 2026-03-02
**Status**: Draft
**Input**: Allow users to edit completed workouts from the workout detail screen via the existing "Edit Workout" toolbar menu item.

## User Scenarios & Testing

### User Story 1 - Edit Set Values on a Completed Workout (Priority: P1)

As a user who logged incorrect weight or reps during a workout, I need to open a completed workout and fix the set data so my training history and personal records are accurate.

**Why this priority**: The most common reason to edit a historic workout is correcting data entry mistakes (wrong weight, wrong reps). This is the core editing capability that everything else builds on.

**Independent Test**: Navigate to a completed workout, tap Edit Workout, change the weight on a set, confirm the checkbox, verify the value persists and PR badges update.

**Acceptance Scenarios**:

1. **Given** I am viewing a completed workout detail, **When** I tap the toolbar menu and select "Edit Workout", **Then** a full-screen edit view opens showing all exercises and sets with their current values pre-populated in editable input fields.
2. **Given** I am in the edit view, **When** I change the weight on a set from 80 kg to 85 kg and tap the completion checkbox, **Then** the new value is persisted immediately, the effective weight is recomputed, and PR status badges update if the change affects personal records.
3. **Given** I am in the edit view, **When** I change the reps on a set from 6 to 8 and confirm, **Then** the new rep count is persisted, the set's estimated 1RM is recalculated, and PR badges update accordingly.
4. **Given** I edit a set that was a current PR, **When** I reduce its weight below another set's value at the same rep count, **Then** the PR badge transfers to the new best set and the edited set loses its PR badge.
5. **Given** I am in the edit view, **When** I tap the back/done button, **Then** the edit view dismisses and the workout detail screen refreshes to show the updated values.

---

### User Story 2 - Add and Delete Sets (Priority: P2)

As a user who forgot to log a set or logged an extra set by mistake, I need to add or remove sets from a completed workout so my history reflects what actually happened.

**Why this priority**: After correcting values, the next most common edit is adjusting the number of sets (forgot to log the last set, accidentally logged a duplicate).

**Independent Test**: Open a completed workout for editing, add a new set with weight and reps, verify it persists. Delete an existing set, verify it is removed and stats/PRs recalculate.

**Acceptance Scenarios**:

1. **Given** I am editing a workout, **When** I tap "Add Set" below the set table for an exercise, **Then** a new empty set row appears that I can fill in with weight, reps, and confirm via the checkbox.
2. **Given** I add a new set and enter values, **When** I tap the completion checkbox, **Then** the set is saved immediately with correct ordering, effective weight is computed, and PR evaluation runs.
3. **Given** I am editing a workout, **When** I tap "Add Warmup" below the set table, **Then** a warmup set is inserted before the first working set, matching the active workout behavior.
4. **Given** I am editing a workout, **When** I long-press or use the context menu on a set and select "Delete Set", **Then** the set is deleted immediately, remaining sets reindex their order, and PR/stats recalculate for the affected exercise.
5. **Given** I delete a set that held a personal record, **When** the deletion completes, **Then** the PR is reassigned to the next best eligible set if one exists.

---

### User Story 3 - Add and Remove Exercises (Priority: P2)

As a user who forgot to log an exercise or wants to clean up a workout, I need to add new exercises or remove existing ones from a completed workout.

**Why this priority**: Less common than set-level edits but important for keeping workout history accurate when entire exercises were missed or logged incorrectly.

**Independent Test**: Open edit view, add a new exercise via the exercise picker, log a set, verify it persists. Remove an exercise, verify all its sets are deleted.

**Acceptance Scenarios**:

1. **Given** I am editing a workout, **When** I tap the "+Exercise" button, **Then** the exercise picker opens allowing me to search and select exercises to add to the workout.
2. **Given** I add a new exercise, **When** it appears in the exercise tab strip, **Then** an initial empty set is created for that exercise and the tab strip scrolls to show it.
3. **Given** I am editing a workout with multiple exercises, **When** I long-press an exercise tab and select "Delete Exercise", **Then** a confirmation dialog appears warning that this will remove the exercise and all its sets.
4. **Given** I confirm exercise deletion, **When** the deletion completes, **Then** all sets for that exercise are deleted, the exercise tab is removed, PR/stats recalculate, and the tab strip adjusts to show the remaining exercises.
5. **Given** I am editing a workout with only one exercise, **When** I long-press that exercise tab, **Then** the "Delete Exercise" option is not available (cannot have an empty workout).

---

### User Story 4 - Edit Workout Notes (Priority: P3)

As a user, I need to add or modify notes on a completed workout so I can record observations about how the session went.

**Why this priority**: Notes are supplementary metadata. Editing them is useful but not as critical as correcting actual training data.

**Independent Test**: Open edit view, modify the notes text, dismiss, verify the updated notes appear on the workout detail.

**Acceptance Scenarios**:

1. **Given** I am editing a workout that has existing notes, **When** the edit view opens, **Then** the notes field shows the current notes text in an editable text area.
2. **Given** I am editing a workout with no notes, **When** the edit view opens, **Then** the notes field shows a placeholder inviting the user to add notes.
3. **Given** I modify the notes text, **When** I dismiss the edit view, **Then** the updated notes are persisted to the workout.

---

### Edge Cases

- What happens if the user navigates away mid-edit? Since changes persist immediately, all confirmed edits (checkbox tapped) are already saved. Unconfirmed changes (text typed but checkbox not tapped) are lost.
- What happens if the user starts an active workout while the edit screen is open? The edit screen is for a completed workout and does not conflict with an active workout (different workout IDs, different status).
- What happens if two sets at the same rep count tie for PR after an edit? The existing PR service handles ties — the most recent set wins.
- What happens if the user deletes all sets for an exercise but doesn't delete the exercise? The exercise remains with an empty set table and "Add Set" button visible, same as adding a new exercise.

## Requirements

### Functional Requirements

- **FR-001**: System MUST enable the "Edit Workout" menu item on the workout detail screen for completed workouts.
- **FR-002**: System MUST present the edit view as a full-screen cover, matching the active workout presentation pattern.
- **FR-003**: System MUST pre-populate all set input fields with the current stored values (weight, reps, duration, distance) when the edit view opens.
- **FR-004**: System MUST persist each set edit immediately when the user confirms it (via the completion checkbox), using the existing set edit pipeline (effective weight recomputation, PR re-evaluation, stats update).
- **FR-005**: System MUST allow adding new working sets and warmup sets to any exercise in the workout, persisting each immediately via the set save pipeline.
- **FR-006**: System MUST allow deleting sets via the existing context menu, with immediate persistence and PR/stats recalculation.
- **FR-007**: System MUST allow adding new exercises via the exercise picker, creating an initial empty set for each.
- **FR-008**: System MUST allow removing exercises (when more than one exists) with a confirmation dialog, cascade-deleting all associated sets.
- **FR-009**: System MUST provide a notes text area for editing the workout's free-text notes, persisted when the user dismisses the edit view.
- **FR-010**: System MUST NOT allow changing the workout date — only content (sets, exercises, notes) is editable.
- **FR-011**: System MUST reuse the same set entry components (set table, set row, input fields, exercise tab strip) used in the active workout to ensure visual and behavioral consistency.
- **FR-012**: System MUST refresh the workout detail screen with updated data when the edit view is dismissed.

### Key Entities

- **Workout**: A completed training session with date, duration, notes, and perceived effort. The edit feature modifies its content but not its date or status.
- **WorkoutSet**: An individual set within an exercise (weight, reps, type, PR status). Sets are the primary unit of editing — values can be changed, sets can be added or removed.
- **Exercise**: A movement tracked in the workout. Exercises can be added to or removed from the workout during editing.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can open and begin editing a completed workout within 1 second of tapping "Edit Workout".
- **SC-002**: Each individual set edit (change value + confirm) persists and updates PR badges within the same performance target as the active workout (~100ms).
- **SC-003**: The edit view is visually consistent with the active workout view — same set table layout, same input fields, same exercise tab strip.
- **SC-004**: After editing, the workout detail screen accurately reflects all changes including updated set values, added/removed sets, added/removed exercises, and modified notes.
- **SC-005**: PR and stats recalculations after edits produce correct results — no stale PR badges or incorrect stats.

## Assumptions

- The existing set entry components (SetTableView, SetRowView, SetInputField, ExerciseTabStripView) can be made reusable via a shared protocol without breaking the active workout flow.
- The workout date is not editable — users who want to change the date should delete and re-create the workout.
- Perceived effort (RPE) is not editable in this version — only notes are editable metadata.
- The edit feature is accessed only from the Home tab's workout detail screen (WorkoutDetailFromHomeView). Calendar tab detail integration can be added later.
