# Feature Specification: Charts Tab v2 — 3-Tab Redesign

**Feature Branch**: `016-charts-tab-v2`
**Created**: 2026-03-04
**Status**: Draft
**Supersedes**: 009-charts-tab (replaces dashboard layout; extends ChartDataService)
**Prototype**: `prototype-charts-tab.html`

---

## Overview

Redesign the Charts tab from a single-scroll dashboard (overview + per-exercise drill-down) to a 3-tab layout: **Breakdown** (donut chart), **Workouts** (time-series bar chart), and **Exercises** (multi-exercise line chart). Each tab has its own dropdowns, time range filters, and interactive features.

---

## User Scenarios & Testing

### User Story 1 — Breakdown Tab: Distribution Analysis (Priority: P1)

As a lifter, I want to see how my training is distributed across muscle categories or individual exercises so I can identify imbalances.

**Independent Test**: Navigate to Charts tab → Breakdown sub-tab, verify donut chart renders with correct data for each of the 8 chart type options.

**Acceptance Scenarios**:

1. **Given** the Breakdown tab, **When** I select "Volume by Category" from the dropdown, **Then** a donut chart shows volume distribution across muscle categories with color-coded segments and a legend with percentages.
2. **Given** the Breakdown tab, **When** I switch between the 8 chart type options (Volume/Sets/Reps/Workouts × Category/Exercise), **Then** the donut chart updates with the correct data.
3. **Given** the Breakdown tab, **When** I select a time range pill (All/Year/Month/Week/Day), **Then** the chart filters to that time range and the date range label updates.
4. **Given** the Breakdown tab with "Volume by Exercise" selected, **When** the chart renders, **Then** each exercise name appears as a separate donut segment (top 7 by value, remainder grouped as "Other" — max 8 total segments).
5. **Given** the Breakdown tab, **When** a chart renders with data, **Then** a summary stats row below the legend shows totals for the selected time range: total volume, total sets, total reps, and total workouts.
6. **Given** the Breakdown tab with a time range that has no data, **Then** an appropriate empty state is shown.

### User Story 2 — Workouts Tab: Time-Series Metrics (Priority: P1)

As a lifter, I want to see how metrics like volume, sets, and reps trend over time, aggregated by workout/week/month/year, optionally filtered to a category or exercise.

**Independent Test**: Navigate to Charts tab → Workouts sub-tab, verify bar chart renders with trend line for various metric/aggregation/filter combinations.

**Acceptance Scenarios**:

1. **Given** the Workouts tab, **When** I select metric "Volume", aggregation "Per Month", filter "All", **Then** a bar chart shows monthly volume over the selected time range with Y-axis showing "kg" values.
2. **Given** the Workouts tab, **When** I change the metric dropdown to "Reps", **Then** the chart updates to show total reps per aggregation period.
3. **Given** the Workouts tab, **When** I select filter "Category → Chest", **Then** the chart shows only data from exercises in the Chest category.
4. **Given** the Workouts tab, **When** I select filter "Exercise → Bench Press", **Then** the chart shows only data from that specific exercise.
5. **Given** the Workouts tab, **When** the chart renders, **Then** a dotted trend line is overlaid with a slope indicator badge (positive=green, negative=red).
6. **Given** the Workouts tab, **When** I tap the left/right navigation arrows (< >), **Then** the selected data point changes and the detail below shows the specific value and date.
7. **Given** the Workouts tab, **When** I change the time range pill (All/1y/6mo/3mo/1mo), **Then** the chart and trend line update to reflect the filtered period.

### User Story 3 — Exercises Tab: Multi-Exercise Progress (Priority: P1)

As a lifter, I want to track progress for specific exercises over time on a single chart so I can compare their progression.

**Independent Test**: Navigate to Charts tab → Exercises sub-tab, select exercises, verify multi-line chart renders with trend line.

**Acceptance Scenarios**:

1. **Given** the Exercises tab, **When** I select "Estimated 1RM" and have exercises selected, **Then** a line chart shows one colored line per exercise with data points over time.
2. **Given** the Exercises tab, **When** I tap the exercise selection button, **Then** a modal sheet opens with "Current" and "Presets" tabs.
3. **Given** the exercise selection modal on "Current" tab, **When** I view it, **Then** I see the currently selected exercises with drag handles (≡), category badges, and remove (−) buttons.
4. **Given** the exercise selection modal, **When** I tap "Add Exercise", **Then** an exercise picker allows me to add an exercise (up to 10 total).
5. **Given** the exercise selection modal, **When** I tap "Apply to Graph", **Then** the modal closes and the chart updates with the selected exercises.
6. **Given** the exercise selection modal, **When** I tap "Save as Preset", **Then** the current selection is saved as a named preset accessible from the "Presets" tab.
7. **Given** the exercise selection modal on "Presets" tab, **When** I tap a preset, **Then** the exercises from that preset are loaded into the current selection.
8. **Given** the exercise selection modal, **When** I tap "Clear Selection", **Then** all selected exercises are removed.
9. **Given** the Exercises tab with data, **When** the chart renders, **Then** a dotted trend line is shown for the first exercise with a slope indicator badge.
10. **Given** the Exercises tab, **When** I use the navigation arrows (< >), **Then** I can browse individual data points showing the value, exercise name, and date.
11. **Given** the Exercises tab, **When** I change the metric to "Max Distance" and select an exercise that only tracks distance, **Then** the chart shows distance values on the Y-axis.
12. **Given** the Exercises tab with no exercises selected, **Then** a prompt state says "Select exercises to view progress".

### User Story 4 — Tab Navigation and Performance (Priority: P1)

As a user, I want smooth tab switching with data loading that doesn't degrade app performance.

**Acceptance Scenarios**:

1. **Given** the Charts tab, **When** I switch between Breakdown/Workouts/Exercises sub-tabs, **Then** the transition is immediate (< 200ms) and previously loaded data is cached within the session.
2. **Given** any chart tab with a large dataset (12,000+ sets), **When** the chart loads, **Then** it renders within 1 second.
3. **Given** any chart tab, **When** I navigate away from the Charts tab entirely, **Then** chart data memory is released (session-scoped caching per AGENT_RULES 5.3).
4. **Given** the Exercises tab with 10 exercises selected, **When** data loads, **Then** all 10 exercise queries run in parallel (not sequentially) and complete within 1 second.

---

## Edge Cases

- **No workouts at all**: All tabs show motivational empty state ("Start your first workout to see charts").
- **Single data point**: Show the point; no trend line (need ≥2 points for trend).
- **Time range with no data**: Show "No data for this period" within the chart card.
- **Exercise with no weight data** (duration/distance only): Weight-based metrics show "N/A" or are hidden. Only applicable metrics display.
- **"By Exercise" breakdown with 20+ exercises**: Show top 7 by value, group remainder as "Other" (max 8 total segments).
- **Preset with deleted exercise**: Filter out deleted exerciseIds when loading preset; warn if preset is empty after filtering.
- **Tab switching during load**: Cancel in-flight requests when switching tabs to avoid stale data replacing fresh data.

---

## Requirements

### Functional Requirements

- **FR-001**: Charts tab MUST have 3 sub-tabs: Breakdown, Workouts, Exercises.
- **FR-002**: Breakdown tab MUST support 8 chart type options (4 metrics × 2 groupBy) via dropdown.
- **FR-003**: Breakdown tab MUST render a donut chart (SectorMark) with color-coded segments and legend.
- **FR-004**: Breakdown tab MUST support 5 time range options: All, Year, Month, Week, Day.
- **FR-005**: Workouts tab MUST support 6 metrics, 4 aggregation periods, and category/exercise filtering via dropdowns.
- **FR-006**: Workouts tab MUST render a bar chart with a linear regression trend line and slope indicator.
- **FR-007**: Workouts tab MUST support interactive data point navigation with ← → arrows.
- **FR-008**: Workouts tab MUST support 5 time range options: All, 1y, 6mo, 3mo, 1mo.
- **FR-008a**: Exercises tab MUST support the same 5 time range options as Workouts tab (All, 1y, 6mo, 3mo, 1mo) via the shared `WorkoutsTimeRange` enum.
- **FR-009**: Exercises tab MUST support 11 metric options via dropdown.
- **FR-010**: Exercises tab MUST render a multi-line chart (up to 10 exercise series).
- **FR-011**: Exercises tab MUST include an exercise selection modal with Current/Presets tabs.
- **FR-012**: Exercise selection modal MUST support add, remove, reorder (drag handles), Apply, Save as Preset, Clear.
- **FR-013**: Exercises tab MUST show a trend line with slope indicator for the primary exercise.
- **FR-014**: Exercises tab MUST support interactive data point navigation with ← → arrows.
- **FR-015**: All charts MUST use Swift Charts (SectorMark, BarMark, LineMark). No third-party chart libraries.
- **FR-016**: Chart data MUST be lazy-computed on tab activation, not at app startup.
- **FR-017**: Chart data MUST be session-scoped cached (released when navigating away from Charts tab).
- **FR-018**: Chart presets MUST be persisted across app sessions (UserDefaults/JSON).
- **FR-019**: Bottom navigation MUST be visible on the Charts tab.
- **FR-020**: All weight values on chart axes MUST respect user's unit preference (kg/lbs) with conversion at view layer.

### Non-Functional Requirements

- **NFR-001**: Chart render time ≤ 1 second on 12,000+ set dataset.
- **NFR-002**: Tab switching ≤ 200ms (cached data).
- **NFR-003**: Memory released when leaving Charts tab entirely.
- **NFR-004**: Exercises tab parallel loading for up to 10 exercises using TaskGroup.

---

## Key Entities

| Entity                                                      | Description                                  |
| ----------------------------------------------------------- | -------------------------------------------- |
| `BreakdownMetric`                                           | Enum driving the 8 chart type options        |
| `WorkoutsMetric` / `WorkoutsAggregation` / `WorkoutsFilter` | Enums driving the 3 Workouts tab dropdowns   |
| `ExerciseMetric`                                            | Enum with 11 exercise metric options         |
| `ChartPreset`                                               | Codable struct for saved exercise selections |
| `TrendLineData`                                             | Linear regression result struct              |
| `BreakdownDataPoint`                                        | Donut chart segment data                     |
| `WorkoutsTimeSeriesPoint`                                   | Bar chart data point                         |
| `ExerciseProgressSeries` / `ExerciseProgressPoint`          | Multi-line chart data                        |

---

## Success Criteria

| ID     | Criterion                                        | How to Verify                                                      |
| ------ | ------------------------------------------------ | ------------------------------------------------------------------ |
| SC-001 | All 3 sub-tabs render with correct chart types   | Manual test: switch tabs, verify donut/bar/line charts             |
| SC-002 | All dropdown options produce correct chart data  | Manual test: cycle through each dropdown option                    |
| SC-003 | Time range filtering works on all tabs           | Manual test: switch time ranges, verify data updates               |
| SC-004 | Trend line and slope indicator display correctly | Manual test: verify dotted trend line and badge                    |
| SC-005 | Data point navigation works with ← → arrows      | Manual test: tap arrows, verify value/date updates                 |
| SC-006 | Exercise selection modal works end-to-end        | Manual test: add/remove/reorder/apply/save preset/clear            |
| SC-007 | Presets persist across app restarts              | Manual test: save preset, force-quit, reopen, verify preset exists |
| SC-008 | Charts render within 1 second on large dataset   | Manual test with imported CSV data (12,000+ sets)                  |
| SC-009 | Empty states display correctly                   | Manual test with new account (no workouts)                         |
| SC-010 | Unit preference respected on all chart axes      | Manual test: switch to lbs in settings, verify chart labels        |

---

## Documentation References

| Document                                      | Section      | What it defines                               |
| --------------------------------------------- | ------------ | --------------------------------------------- |
| `prototype-charts-tab.html`                   | Full file    | Interactive HTML mockup of all 3 tabs         |
| `design-system.md`                            | Sections 2–6 | Color tokens, typography, spacing, components |
| `AGENT_RULES.md`                              | Section 5.3  | Memory management (chart data session-scoped) |
| `AGENT_RULES.md`                              | Section 7.1  | Swift Charts requirement                      |
| `AGENT_RULES.md`                              | Section 3.2  | Unit storage (kg) and UI conversion           |
| `kitty-specs/016-charts-tab-v2/data-model.md` | Full file    | All new enums, structs, protocol methods      |
| `kitty-specs/016-charts-tab-v2/research.md`   | Full file    | Current state analysis, reuse assessment      |
