# Feature Specification: Settings + Onboarding

**Feature Branch**: `010-settings-and-onboarding`
**Created**: 2026-02-19
**Status**: Draft
**Input**: Settings from screen_tree Section 5. Onboarding from screen_tree Section 6. User settings per specdoc Section 9. Onboarding per AGENT_RULES Section 11.

## User Scenarios & Testing

### User Story 1 - Settings Screen (Priority: P1)

As a lifter, I need a settings screen to configure units, e1RM formula, warmup preferences, and manage my data.

**Why this priority**: Users must be able to configure the app to their preferences.

**Independent Test**: Open settings, change unit preference from metric to imperial, verify weights display in lbs throughout the app.

**Acceptance Scenarios**:

1. **Given** Settings, **When** I view GENERAL section, **Then** I see: Units toggle (metric/imperial), e1RM Formula picker.
2. **Given** Settings, **When** I view WORKOUT PREFERENCES, **Then** I see: Include Warmups in Volume (toggle), Include Warmups in PRs (toggle), Default Rest Time (picker).
3. **Given** Settings, **When** I view DATA section, **Then** I see: Import Data (CSV), Export Data (CSV), Rebuild Stats.
4. **Given** Settings, **When** I view BODY section, **Then** I see: Bodyweight Log (trend chart, entries, +Add).
5. **Given** Settings, **When** I view ABOUT section, **Then** I see: Version number, Send Feedback.
6. **Given** I toggle "Include Warmups in PRs", **When** the toggle changes, **Then** the app prompts for a PR rebuild and runs PRService.rebuildAll() if confirmed.

### User Story 2 - Units Configuration (Priority: P1)

As a lifter, I need to switch between metric (kg) and imperial (lbs) display with all storage remaining in kg.

**Why this priority**: Essential for international users.

**Independent Test**: Switch to imperial, verify all weight displays show lbs, verify stored values remain in kg.

**Acceptance Scenarios**:

1. **Given** units set to imperial, **When** I view any weight, **Then** it displays in lbs (converted from kg).
2. **Given** units set to imperial, **When** I enter a weight, **Then** the input is in lbs but stored as kg after conversion.
3. **Given** a unit change, **When** viewing history, **Then** all historical weights display in the new unit (no data change).

### User Story 3 - Bodyweight Log (Priority: P2)

As a lifter, I need to log and view my bodyweight history for accurate effectiveWeight calculations.

**Why this priority**: Required for bodyweight exercises but not blocking core workout flow.

**Independent Test**: Add a bodyweight entry, verify it appears in the log and is used for effectiveWeight.

**Acceptance Scenarios**:

1. **Given** bodyweight log screen, **When** I view it, **Then** I see a trend chart and chronological entries.
2. **Given** bodyweight log, **When** I tap [+Add], **Then** I can enter a bodyweight value and date.

### User Story 4 - Rebuild Stats (Priority: P2)

As a lifter, I need a manual rebuild function for rare maintenance scenarios.

**Why this priority**: Safety net for data import, migration, or corruption recovery.

**Independent Test**: Tap "Rebuild All", verify ExerciseStats and PerformanceRecord are recomputed from raw sets.

**Acceptance Scenarios**:

1. **Given** Rebuild Stats screen, **When** I view it, **Then** I see explanation text and buttons: [Rebuild PRs], [Rebuild Stats], [Rebuild All].
2. **Given** I tap [Rebuild All], **When** rebuild completes, **Then** all ExerciseStats and PerformanceRecord rows match what incremental updates would produce.

### User Story 5 - Onboarding Flow (Priority: P1)

As a new user, I need a lightweight onboarding to set my preferences on first launch.

**Why this priority**: First-run experience sets up essential defaults.

**Independent Test**: Launch app for first time, verify 5-screen onboarding flow, complete it, arrive at Calendar tab.

**Acceptance Scenarios**:

1. **Given** first launch, **When** the app opens, **Then** onboarding starts with Welcome screen.
2. **Given** onboarding, **When** I progress through screens, **Then** I see: Welcome, Units selection (kg/lbs), e1RM formula (Epley default with descriptions), Bodyweight entry (optional, skippable), Import prompt (optional - "Migrating from another app?").
3. **Given** onboarding complete, **When** I finish, **Then** I arrive at Calendar tab.
4. **Given** onboarding, **When** I skip optional screens, **Then** sensible defaults are used and app is fully usable.
5. **Given** a returning user, **When** the app opens, **Then** onboarding does NOT show again.

### Edge Cases

- All onboarding settings changeable later in Settings.
- Onboarding must not gate app usage - skipping is always allowed.
- Settings changes that affect PRs (warmup inclusion) prompt for rebuild.
- e1RM formula change: future sets use new formula, existing sets keep their e1RMFormulaVersion.
- Bodyweight log empty state: encourage first entry for accurate effectiveWeight.
- CSV Import/Export buttons show "Coming Soon" placeholder (feature 011 handles full implementation).
- If a rebuild operation fails, show error message. User can retry. No partial data corruption — rebuilds are atomic.

## Requirements

### Functional Requirements

- **FR-001**: Settings MUST have sections: GENERAL, WORKOUT PREFERENCES, DATA, BODY, ABOUT per screen_tree Section 5.
- **FR-002**: Units toggle MUST switch display between metric/imperial with all storage in kg.
- **FR-003**: e1RM Formula MUST be selectable (Epley default) with descriptions.
- **FR-004**: Include Warmups in Volume/PRs toggles MUST trigger rebuild prompts on change.
- **FR-005**: Bodyweight Log MUST show trend chart and chronological entries with [+Add].
- **FR-006**: Rebuild Stats MUST offer [Rebuild PRs], [Rebuild Stats], [Rebuild All].
- **FR-007**: Onboarding MUST have 5 screens: Welcome, Units, e1RM, Bodyweight, Import prompt per screen_tree Section 6.
- **FR-008**: Onboarding MUST only show on first launch.
- **FR-009**: All onboarding steps MUST be skippable with sensible defaults.
- **FR-010**: Settings MUST be stored on HealthProfile (unitPreference, includeWarmupsInVolume, includeWarmupsInPRs, e1RMFormula, defaultRestTimeSeconds) per AGENT_RULES Section 8 and screen_tree Section 5.
- **FR-011**: Bottom navigation MUST be visible on Settings tab.

### Key Entities

- **Settings Screen**: Grouped settings per screen_tree Section 5.
- **Onboarding Flow**: 5-screen first-launch experience.
- **HealthProfile**: Single-row table storing user preferences.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Unit switch immediately updates all displayed weights.
- **SC-002**: Onboarding completes in under 2 minutes.
- **SC-003**: Rebuild All produces correct stats for 12,000+ sets within 30 seconds.
- **SC-004**: Skipping onboarding leaves app fully functional with defaults.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| screen_tree.md | Section 5 | Settings full tree |
| screen_tree.md | Section 6 | Onboarding flow |
| specdoc.md | Section 9 | User settings |
| specdoc.md | Section 6.7 | HealthProfile schema |
| AGENT_RULES.md | Section 8 | User settings on HealthProfile |
| AGENT_RULES.md | Section 11 | Onboarding rules |
