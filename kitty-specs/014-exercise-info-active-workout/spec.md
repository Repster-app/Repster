# Feature Specification: Exercise Info in Active Workout

**Feature Branch**: `014-exercise-info-active-workout`
**Created**: 2026-03-01
**Status**: Draft
**Input**: Add a contextual Exercise Info section below the set table in the active workout view, showing estimated 1RM, last workout data, and progress comparisons per reference screenshot.

## User Scenarios & Testing

### User Story 1 - Estimated 1RM Display (Priority: P1)

As a lifter mid-workout, I need to see my estimated one-rep max for the current exercise so I can gauge my strength level and choose appropriate weights.

**Why this priority**: The e1RM is the single most important contextual metric for weight selection decisions during a workout.

**Independent Test**: Complete 2 working sets for an exercise, verify the Estimated 1RM card updates and shows the correct value based on today's best set.

**Acceptance Scenarios**:

1. **Given** an active workout with at least one completed working set, **When** viewing the Exercise Info section below the set table, **Then** a prominent e1RM card displays the current estimated 1RM value with unit (e.g., "105.5 kg").
2. **Given** multiple completed sets for the exercise, **When** the e1RM card updates, **Then** it uses the best set from today's session (highest e1RM) for the calculation.
3. **Given** the e1RM card, **When** viewing "Best today", **Then** it shows the weight × reps of today's best set (e.g., "Best today: 85 × 8").
4. **Given** the e1RM card, **When** historical data exists from approximately 4 weeks ago, **Then** it shows a comparison (e.g., "vs 4wk ago: −1.1 kg" in red, or "+2.3 kg" in green).
5. **Given** no completed sets yet for this exercise in the current workout, **When** viewing Exercise Info, **Then** the e1RM card shows the most recent historical e1RM or a placeholder if no history exists.

### User Story 2 - Last Workout Summary (Priority: P1)

As a lifter, I need to see what I did last time for this exercise so I can match or beat my previous performance.

**Why this priority**: Last workout data is the most commonly referenced information when deciding weight and reps for the current session.

**Independent Test**: View Exercise Info for an exercise that was performed 9 days ago, verify it shows the top sets and "9 days ago".

**Acceptance Scenarios**:

1. **Given** an exercise with previous workout history, **When** viewing the "Last Workout" card, **Then** it shows the top working sets from the most recent previous session (e.g., "85×8, 45×8").
2. **Given** the Last Workout card, **When** viewing the time reference, **Then** it displays how long ago the last session was (e.g., "9 days ago").
3. **Given** an exercise with no previous workout history, **When** viewing Exercise Info, **Then** the Last Workout card shows an empty state (e.g., "No previous data" or is hidden).
4. **Given** the last workout had warmup and working sets, **When** displaying top sets, **Then** only working sets are shown (warmups excluded).

### User Story 3 - Estimated Weight for Rep Range (Priority: P2)

As a lifter, I need to see what weight I should use for a given rep target so I can make faster, more informed loading decisions.

**Why this priority**: Reduces guesswork for weight selection, especially useful for exercises where the user is still dialing in weights.

**Independent Test**: View Exercise Info for an exercise with recent history, verify it shows an estimated weight for the current rep range.

**Acceptance Scenarios**:

1. **Given** an exercise with enough history to calculate estimates, **When** viewing the "Est. for N reps" card, **Then** it shows an estimated weight for the rep range currently being used (e.g., "Est. for 8 reps: 85 kg").
2. **Given** the estimate card, **When** viewing the source label, **Then** it displays "Based on recent data" to indicate the estimate is derived from historical performance.
3. **Given** an exercise with insufficient history, **When** viewing Exercise Info, **Then** the estimate card shows a placeholder or is hidden.
4. **Given** the user's most recent working set has a specific rep count, **When** displaying the estimate, **Then** the rep target matches that rep count.

### User Story 4 - Exercise Info Layout (Priority: P1)

As a lifter, I need the Exercise Info section to be clearly laid out below my set table so I can quickly glance at contextual data without disrupting my logging flow.

**Why this priority**: Poor layout would make the information hard to scan, defeating its purpose.

**Independent Test**: Open active workout, scroll below set table, verify Exercise Info section is visible with proper card layout.

**Acceptance Scenarios**:

1. **Given** an active workout, **When** scrolling below the set table and action buttons (Add Set / Add Warmup), **Then** an "EXERCISE INFO" section header appears followed by info cards.
2. **Given** the Exercise Info section, **When** viewing the layout, **Then** the e1RM card spans the full width (large/prominent), and the Last Workout and Est. for N reps cards appear side by side below it.
3. **Given** the Exercise Info section, **When** switching between exercises via the tab strip, **Then** the info updates to reflect the newly selected exercise.
4. **Given** the Exercise Info cards, **When** viewing styling, **Then** they follow design-system.md: bgCard background, 14pt corner radius, appropriate typography scale.

### Edge Cases

- **New exercise with zero history**: All three cards show empty/placeholder states gracefully.
- **Exercise performed only once (current session is the first)**: e1RM shows current session data, Last Workout shows "No previous data", estimate may be unavailable.
- **Duration-based exercises**: e1RM is not applicable for duration tracking types. Exercise Info should adapt or hide irrelevant cards.
- **Bodyweight exercises**: e1RM calculation uses effectiveWeight (includes bodyweight factor). Display should show the effective weight value.
- **Tab switching performance**: Exercise Info data should load quickly when switching exercises. Cache previously loaded data to avoid redundant fetches.
- **e1RM formula**: Uses the user's selected formula from HealthProfile (Epley, Brzycki, etc.).
- **Historical comparison period**: "vs N wk ago" uses approximately 4 weeks as the comparison window. If no data exists at that point, use the closest available historical e1RM.

## Requirements

### Functional Requirements

- **FR-001**: Active workout view MUST display an "EXERCISE INFO" section below the set table and Add Set/Add Warmup buttons.
- **FR-002**: Estimated 1RM card MUST show the current e1RM value calculated from today's best working set.
- **FR-003**: Estimated 1RM card MUST show "Best today: W × R" (weight × reps of best set in current workout).
- **FR-004**: Estimated 1RM card MUST show a comparison vs approximately 4 weeks ago (e.g., "+2.3 kg" in green or "−1.1 kg" in red).
- **FR-005**: Last Workout card MUST show the top working sets from the most recent previous session with a relative time label.
- **FR-006**: Est. for N reps card MUST show an estimated weight for the rep range matching the user's most recent working set rep count.
- **FR-007**: Exercise Info MUST update when the user switches exercises via the tab strip.
- **FR-008**: Cards MUST show appropriate empty/placeholder states when data is insufficient.
- **FR-009**: Duration-based exercises MUST hide or adapt cards that require weight/rep data.
- **FR-010**: e1RM calculations MUST use the user's selected formula from HealthProfile.
- **FR-011**: All cards MUST follow design-system.md tokens for colors, spacing, typography, and corner radii.

### Key Entities

- **Exercise Info Section**: Contextual data panel displayed below the set table for the currently selected exercise.
- **Estimated 1RM Card**: Primary metric card showing calculated one-rep max with historical comparison.
- **Last Workout Card**: Compact card showing the most recent previous session's top sets for context.
- **Estimated Reps Card**: Compact card showing suggested weight for the current rep target.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Exercise Info section loads within 500ms of exercise tab selection.
- **SC-002**: Estimated 1RM value matches the result of applying the user's selected formula to the best working set.
- **SC-003**: Last Workout data accurately reflects the most recent previous session (excluding current workout).
- **SC-004**: Historical comparison (vs N wk ago) shows correct directional trend (positive = green, negative = red).
- **SC-005**: Scrolling through set table and Exercise Info maintains 60 FPS.
- **SC-006**: All touch targets are at least 44x44pt.

## Assumptions

- e1RM is calculated using the user's selected formula (defaulting to Epley). The formula is already implemented in the stats pipeline.
- "Best today" is determined by highest calculated e1RM across all completed working sets in the current workout for the exercise.
- The 4-week comparison window is approximate — if no data exists at exactly 4 weeks, the nearest available historical e1RM is used.
- "Top sets" from last workout means the heaviest working sets, not all sets (warmups excluded).
- The estimated weight for N reps is derived by reverse-calculating from the user's recent best e1RM.
- This feature modifies ActiveWorkoutView and its ViewModel but does not change any service or repository interfaces.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| home-screen-redesign-context.md | Exercise Info section | Reference screenshot and design description |
| design-system.md | Sections 2-4 | Color tokens, typography, spacing, card patterns |
| AGENT_RULES.md | Section 7.4 | PR celebration and badge rules |
| AGENT_RULES.md | Section 7.5 | Unit display rules |
