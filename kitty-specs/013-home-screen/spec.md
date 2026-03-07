# Feature Specification: Home Screen

**Feature Branch**: `013-home-screen`
**Created**: 2026-03-01
**Status**: Draft
**Input**: Replace the Programs placeholder tab with a full Home screen serving as the app's landing page after onboarding.

## User Scenarios & Testing

### User Story 1 - Home Screen as Landing Page (Priority: P1)

As a user opening the app, I need a Home screen that shows me at-a-glance information — what I did recently, my weekly activity, and a clear way to start a new workout — so I have a useful starting point instead of an empty placeholder.

**Why this priority**: The Home screen is the first thing users see every time they open the app. A blank placeholder creates a poor first impression and provides no value.

**Independent Test**: Launch app after onboarding, verify Home tab is selected with all sections visible and populated.

**Acceptance Scenarios**:

1. **Given** a user who has completed onboarding, **When** the app launches, **Then** the Home tab is selected by default showing a scrollable screen with header, week strip, start workout card, quick actions, this week activity, and recent workouts.
2. **Given** the Home tab, **When** viewing the header, **Then** it displays the current date (e.g., "Wednesday, Feb 12"), title "Workout", and a profile avatar placeholder on the right.
3. **Given** the Home tab, **When** viewing the screen, **Then** all sections follow design-system.md tokens: bg background, bgCard cards, 20pt horizontal padding, 14pt card corner radius.
4. **Given** the tab bar, **When** viewing the first tab, **Then** it reads "Home" with a house SF Symbol icon (replacing the old "Programs" tab).

### User Story 2 - Week Strip Calendar (Priority: P1)

As a user, I need a compact week strip showing Mon–Sun so I can see which days this week I trained at a glance.

**Why this priority**: Provides immediate visual context about training consistency without navigating to Calendar.

**Independent Test**: View Home screen with 2 completed workouts this week, verify today is highlighted and workout days have dots.

**Acceptance Scenarios**:

1. **Given** the Home screen, **When** viewing the week strip, **Then** it shows 7 day cells (Mon through Sun) for the current week with day abbreviation and date number.
2. **Given** today is Wednesday, **When** viewing the week strip, **Then** today's cell has an accent-colored background to distinguish it from other days.
3. **Given** workouts completed on Monday and Tuesday, **When** viewing the week strip, **Then** those day cells show a small accent-colored dot below the date number.
4. **Given** no workouts this week, **When** viewing the week strip, **Then** no dots appear on any day cells.

### User Story 3 - Start Workout Card (Priority: P1)

As a user ready to train, I need a prominent card to start a new workout so I can begin logging immediately.

**Why this priority**: Starting a workout is the app's core action — it must be front and center.

**Independent Test**: Tap the Start Workout card body and verify exercise list opens; tap the [+] icon and verify empty workout starts.

**Acceptance Scenarios**:

1. **Given** the Home screen, **When** viewing the Start Workout card, **Then** it displays "READY TO TRAIN" label (accent color, small caps), "Start Workout" title, "Log exercises, sets & reps" subtitle, and a [+] button on the right side.
2. **Given** no active workout, **When** I tap the Start Workout card body, **Then** ExerciseListView opens in browse mode (same behavior as the center FAB).
3. **Given** no active workout, **When** I tap the [+] icon on the card, **Then** an empty workout is created and ActiveWorkoutView is presented as a fullScreenCover.
4. **Given** an active workout already exists, **When** I tap the Start Workout card, **Then** the existing active workout is resumed (ActiveWorkoutView presented).

### User Story 4 - Quick Action Cards (Priority: P2)

As a user, I need quick actions to copy a previous workout or use a template so I can start training faster with familiar exercises.

**Why this priority**: Reduces friction for repeat workouts — the most common use case for experienced lifters. Templates is a placeholder for v1.1.

**Independent Test**: Tap "Copy Previous", verify sheet with past workouts appears; tap "Templates", verify placeholder message.

**Acceptance Scenarios**:

1. **Given** the Home screen, **When** viewing quick action cards, **Then** two equal-width cards appear side by side: "Copy Previous" (with copy icon) and "Templates" (with document icon).
2. **Given** I tap "Copy Previous", **When** I have completed workouts, **Then** a sheet opens showing recent completed workouts with date, exercise count, sets, volume, and muscle group tags.
3. **Given** the copy previous sheet, **When** I tap a past workout, **Then** a new workout is created with the same exercises (same order), the exact number of working sets are duplicated per exercise with weight and reps pre-filled from the source, and ActiveWorkoutView is presented.
4. **Given** I tap "Templates", **When** the Templates feature is not yet built, **Then** a "Coming soon" message or placeholder is displayed.
5. **Given** I tap "Copy Previous", **When** I have no completed workouts, **Then** an empty state message is shown (e.g., "No workouts yet").
6. **Given** I select a workout in the copy previous sheet, **When** an active workout already exists, **Then** a confirmation dialog is shown asking whether to discard the active workout and start the copied workout, or cancel and resume the existing one.

### User Story 5 - This Week Activity (Priority: P2)

As a user, I need to see my training activity for the current week so I can track my consistency toward a weekly goal.

**Why this priority**: Weekly activity visibility motivates consistent training habits.

**Independent Test**: Complete 2 workouts on Mon/Tue, verify bars filled for those days and counter shows "2 / 4 sessions".

**Acceptance Scenarios**:

1. **Given** the Home screen, **When** viewing the activity section, **Then** it shows a "THIS WEEK" section header, a day-by-day bar chart (M T W T F S S), and a session counter "X / 4 sessions".
2. **Given** workouts on Monday and Tuesday, **When** viewing activity bars, **Then** Monday and Tuesday bars are filled (accent color), other days are empty/dim.
3. **Given** today is Wednesday, **When** viewing the activity chart, **Then** today's day label is visually distinguished (e.g., bold or accent-colored).
4. **Given** the default weekly goal of 4, **When** 2 workouts are completed (each workout counts individually, even multiple on the same day), **Then** the counter reads "2 / 4 sessions" with the completed count in accent color.

### User Story 6 - Recent Workouts (Priority: P1)

As a user, I need to see my recent workouts so I can review what I've done and navigate to past workout details.

**Why this priority**: Recent workout visibility is essential context for planning the next session.

**Independent Test**: Complete 3 workouts over past week, verify 3 cards appear with correct stats and are tappable.

**Acceptance Scenarios**:

1. **Given** the Home screen, **When** viewing the recent section, **Then** it shows a "RECENT" section header followed by up to 5 most recent completed workout cards in reverse chronological order (no time-range limit).
2. **Given** a recent workout, **When** viewing its card, **Then** it displays: workout date, stats row (exercise count, set count, duration in minutes, total volume in tonnes), and muscle group tags as pills.
3. **Given** a recent workout card, **When** I tap it, **Then** I navigate to a workout detail view showing the full exercise-by-exercise breakdown.
4. **Given** no completed workouts, **When** viewing the recent section, **Then** an empty state message is shown (e.g., "Complete your first workout to see it here").
5. **Given** the workouts have associated exercises, **When** viewing muscle tags, **Then** they show the primary muscle groups worked (deduplicated).

### Edge Cases

- **First launch after onboarding**: All sections show empty states gracefully (no dots on week strip, "0 / 4 sessions", no recent workouts).
- **Copy Previous with active workout**: If an active workout exists when the user selects a past workout to copy, a confirmation dialog asks whether to discard the active workout or cancel. Discarding deletes the active workout before creating the copied one.
- **App killed and relaunched with active workout**: Active workout resume logic is unchanged (existing `.task` block in ContentView handles this).
- **Workout finished**: When returning from a completed workout, Home screen refreshes to show updated data (new recent workout, updated week dots, updated activity).
- **Week boundary**: Week strip resets to new Mon–Sun range when the week changes.
- **Volume display**: Volume shown in kg only for v1 (no unit preference setting exists yet).
- **Duration display**: Shown in minutes (e.g., "52m"), or "< 1m" for very short sessions.
- **Tap targets**: All interactive elements (cards, buttons) meet the 44pt minimum.

## Clarifications

### Session 2026-03-01

- Q: When the user taps "Copy Previous" and selects a past workout, but an active workout already exists, what should happen? → A: Show a confirmation dialog asking whether to discard the active workout and start the copy.
- Q: When copying a past workout, what should the duplicated sets contain for each exercise? → A: Copy the exact number of working sets with weight and reps pre-filled from the source workout.
- Q: For the Recent Workouts section, what time range and ordering? → A: Show the 5 most recent completed workouts regardless of age, in reverse chronological order.
- Q: If a user completes two workouts on the same day, does the session counter count 1 or 2? → A: Count each workout individually (2 workouts = 2 sessions).

## Requirements

### Functional Requirements

- **FR-001**: Home tab MUST replace the Programs placeholder as the first tab in the tab bar.
- **FR-002**: Tab MUST be labeled "Home" with a house SF Symbol icon.
- **FR-003**: Home screen MUST display a scrollable layout with sections: header, week strip, start workout card, quick action cards, this week activity, recent workouts.
- **FR-004**: Week strip MUST show Mon–Sun for the current week with today highlighted and workout dots.
- **FR-005**: Start Workout card body tap MUST open ExerciseListView in browse mode (same as FAB).
- **FR-006**: Start Workout card [+] icon tap MUST create an empty workout and present ActiveWorkoutView.
- **FR-007**: "Copy Previous" MUST open a sheet listing recent completed workouts.
- **FR-008**: Selecting a workout in Copy Previous MUST create a new workout with the same exercises (same order), duplicating the exact number of working sets per exercise with weight and reps pre-filled from the source, and present ActiveWorkoutView.
- **FR-009**: "Templates" MUST show a placeholder/coming soon state for v1.
- **FR-010**: This Week activity MUST show a day-by-day bar chart with a session counter against a default goal of 4 sessions/week.
- **FR-011**: Recent workouts MUST display up to 5 most recent completed workouts (no time-range limit, reverse chronological) with date, exercise count, sets, duration, volume, and muscle tags.
- **FR-012**: Recent workout cards MUST be tappable and navigate to a workout detail view.
- **FR-013**: MainTab enum MUST rename `.programs` to `.home`.
- **FR-014**: Home screen MUST refresh data when appearing (after finishing a workout or switching back to the tab).
- **FR-015**: All UI MUST follow design-system.md tokens for colors, spacing, typography, and corner radii.
- **FR-016**: All data MUST be fetched from existing services (no new service or repository methods).

### Key Entities

- **Home Screen**: The app's landing page and primary navigation hub showing at-a-glance workout information.
- **Week Strip**: Compact 7-day calendar visualization of the current week's training activity.
- **Start Workout Card**: Primary call-to-action for beginning a new workout session.
- **Quick Action Cards**: Secondary entry points for copying past workouts or using templates.
- **This Week Activity**: Weekly training frequency visualization with goal tracking.
- **Recent Workout Card**: Summary card for a completed workout with key stats and muscle group tags.
- **Copy Previous Sheet**: Modal list of past workouts available for duplication.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Home screen loads and displays all sections within 1 second of tab selection.
- **SC-002**: Users can start a workout from the Home screen within 2 taps.
- **SC-003**: Recent workouts display accurate stats matching the data in Calendar workout detail.
- **SC-004**: Week strip correctly reflects workout completion for every day of the current week.
- **SC-005**: Scrolling the Home screen maintains 60 FPS.
- **SC-006**: All touch targets are at least 44x44pt.
- **SC-007**: Copy Previous creates a new workout with identical exercises in the same order as the source workout.

## Assumptions

- Weekly session goal defaults to 4 and is hardcoded for v1. A user-configurable goal setting will be added to Settings in a future feature.
- Profile avatar in the header is a placeholder circle (no user profile system in v1).
- "Templates" card is a non-functional placeholder linking to the Programs feature planned for v1.1.
- Workout detail view navigated from Recent cards reuses the same workout detail pattern from the Calendar feature.
- Volume is calculated as sum of (effectiveWeight × reps) for all completed working sets, displayed in kg only for v1.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| home-screen-redesign-context.md | Full doc | Design decisions, reference screenshots, discussion context |
| screen_tree.md | Section 1 | Programs tab (to be updated to Home) |
| design-system.md | Sections 2-4 | Color tokens, typography, spacing, card patterns |
| AGENT_RULES.md | Section 7.2 | Navigation structure (tab bar) |
| AGENT_RULES.md | Section 7.3 | Active workout flow (FAB → Exercise List → workout) |
