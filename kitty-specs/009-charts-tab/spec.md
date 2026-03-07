# Feature Specification: Charts Tab

**Feature Branch**: `009-charts-tab`
**Created**: 2026-02-19
**Status**: Draft
**Input**: screen_tree Section 4. Chart performance strategy per specdoc Section 8.10. Time-series aggregation per specdoc Section 11.1.

## User Scenarios & Testing

### User Story 1 - Overview Dashboard (Priority: P1)

As a lifter, I need a dashboard showing my training trends at a glance: weekly volume, training frequency, and muscle group distribution.

**Why this priority**: Top-level analytics screen - motivates and informs training.

**Independent Test**: View charts tab with workout history, verify overview charts display correctly.

**Acceptance Scenarios**:

1. **Given** the charts tab, **When** I view the OVERVIEW section, **Then** I see weekly volume (bar chart, last 12 weeks).
2. **Given** the overview, **When** I view training frequency, **Then** I see sessions per week.
3. **Given** the overview, **When** I view muscle group distribution, **Then** I see distribution for the last 4 weeks.

### User Story 2 - Per-Exercise Chart Cards (Priority: P1)

As a lifter, I need to see my exercises listed with their current e1RM, trend direction, and a sparkline so I can identify progress.

**Why this priority**: Quick scan of all exercise progress.

**Independent Test**: View PER EXERCISE section, verify cards show current e1RM and sparkline.

**Acceptance Scenarios**:

1. **Given** the charts tab, **When** I view the PER EXERCISE section, **Then** exercise cards are sorted by most recent.
2. **Given** an exercise card, **When** I view it, **Then** it shows: current e1RM, trend direction, sparkline.
3. **Given** an exercise card, **When** I tap it, **Then** it navigates to Exercise Charts Detail (pushed).

### User Story 3 - Exercise Charts Detail (Priority: P1)

As a lifter, I need detailed charts for a specific exercise with time range filtering.

**Why this priority**: Deep drill-down for tracking exercise-specific progress.

**Independent Test**: Tap exercise card, verify detail screen with time range selector and 4 chart types.

**Acceptance Scenarios**:

1. **Given** exercise charts detail, **When** I view it, **Then** I see a time range selector: [3M] [6M] [1Y] [All].
2. **Given** exercise charts detail, **When** I view charts, **Then** I see: e1RM trend (line), volume per session (bar), top weight per session (line), rep PR progression (multi-line: 1RM, 3RM, 5RM over time).
3. **Given** the time range selector, **When** I tap [6M], **Then** all charts filter to the last 6 months of data.

### User Story 4 - Chart Performance (Priority: P2)

Charts must load quickly even with large datasets by using lazy computation and session-scoped caching.

**Why this priority**: Charts must not degrade app performance.

**Independent Test**: Open charts with 12,000+ sets of history, verify charts render within 1 second.

**Acceptance Scenarios**:

1. **Given** a large dataset, **When** I open a chart, **Then** data is lazy-computed on first access (not preloaded at startup).
2. **Given** a chart that was already loaded, **When** I navigate away and back, **Then** the cached result is used (session-scoped).
3. **Given** any chart, **When** it queries data, **Then** only the needed date range is queried, not all history.

### Edge Cases

- Exercise with no history: show empty state in charts detail.
- Single data point: show point, no trendline possible.
- Time range with no data: show "No data for this period".
- Charts tab with no workouts at all: show motivational empty state.
- Use Swift Charts for all chart rendering (no third-party libs).

## Requirements

### Functional Requirements

- **FR-001**: Overview MUST show weekly volume bar chart (last 12 weeks).
- **FR-002**: Overview MUST show training frequency (sessions per week).
- **FR-003**: Overview MUST show muscle group distribution (last 4 weeks).
- **FR-004**: Per-exercise cards MUST show current e1RM, trend direction, sparkline, sorted by most recent.
- **FR-005**: Exercise Charts Detail MUST show time range selector: 3M, 6M, 1Y, All.
- **FR-006**: Exercise Charts Detail MUST show 4 charts: e1RM trend (line), volume/session (bar), top weight/session (line), rep PR progression (multi-line).
- **FR-007**: Chart data MUST be lazy-computed on first access, not at startup (per specdoc Section 8.10).
- **FR-008**: Chart data MUST be session-scoped cached (in memory while displayed, released on navigate away).
- **FR-009**: Charts MUST query only the needed date range, not all history.
- **FR-010**: All charts MUST use Swift Charts (no third-party chart libraries per AGENT_RULES Section 12).
- **FR-011**: Bottom navigation MUST be visible on the charts dashboard.

### Key Entities

- **Charts Dashboard**: Overview section + per-exercise cards list.
- **Exercise Charts Detail**: Time-filtered drill-down with 4 chart types.
- **Chart Data**: Lazy-computed, session-cached, date-range-scoped.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Overview charts render within 1 second on a dataset with 12,000+ sets.
- **SC-002**: Exercise charts detail loads within 200ms (after initial lazy computation).
- **SC-003**: No chart data is computed at app startup.
- **SC-004**: Memory for chart data is released when navigating away from the chart screen.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| screen_tree.md | Section 4 | Charts tab full tree |
| specdoc.md | Section 8.10 | Chart performance strategy |
| specdoc.md | Section 11.1 | Time-series aggregation strategy |
| AGENT_RULES.md | Section 5.3 | Memory management (charts data) |
| AGENT_RULES.md | Section 7.1 | Swift Charts requirement |
| AGENT_RULES.md | Section 12 | Approved dependencies |
