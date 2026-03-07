# Feature Specification: CSV Import + Export

**Feature Branch**: `011-csv-import-export`
**Created**: 2026-02-19
**Status**: Draft
**Input**: Export format per specdoc Section 12. Import mapping per tech_stack Section 11. Import rules per AGENT_RULES Section 9.

## User Scenarios & Testing

### User Story 1 - CSV Import from Competitor App (Priority: P1)

As a lifter migrating from another app, I need to import my ~12,000 sets of training history from a CSV file so I don't lose years of data.

**Why this priority**: User is migrating - this is a hard requirement for adoption.

**Independent Test**: Import a CSV with known data, verify correct workouts, exercises, and sets are created.

**Acceptance Scenarios**:

1. **Given** Settings -> Import Data, **When** I tap it, **Then** a file picker opens for CSV selection.
2. **Given** a selected CSV, **When** import starts, **Then** I see a preview of the data and mapping before committing.
3. **Given** the CSV structure (Date, Exercise, Category, Weight kg, Weight lbs, Reps, Distance, Distance Unit, Time, Notes, Kind), **When** import runs, **Then** rows are grouped by Date to create Workouts, exercises are created for unknown names, sets are created with proper relationships.
4. **Given** the Kind column, **When** mapping, **Then** Kind maps to Exercise.trackingType inference (NOT Set.setType - all imported sets default to setType=working).
5. **Given** import completes, **When** stats are rebuilt, **Then** StatsService.rebuildAll() and PRService.rebuildAll() run (NOT per-set PR pipeline).
6. **Given** malformed rows, **When** import validates, **Then** malformed rows are rejected with clear error reporting.
7. **Given** a successful import, **When** viewing results, **Then** I see: sets imported, workouts created, exercises created, errors/skipped.

### User Story 2 - CSV Export (Priority: P1)

As a lifter, I need to export all my data as CSV for backup or migration to another app.

**Why this priority**: Data portability and backup are essential for trust.

**Independent Test**: Export data, open CSV, verify all workouts and sets are present with correct format.

**Acceptance Scenarios**:

1. **Given** Settings -> Export Data, **When** I tap Export, **Then** a CSV is generated and the system share sheet appears for saving/sharing.
2. **Given** export completes, **When** I open the CSV, **Then** all workouts, exercises, and sets are included.
3. **Given** the export, **When** I check weight values, **Then** they are in kg (internal storage unit).

### User Story 3 - Import Progress (Priority: P2)

As a lifter importing a large dataset, I need to see progress so I know the app isn't frozen.

**Why this priority**: UX for long-running operation.

**Independent Test**: Import 12,000 rows, verify progress indicator updates.

**Acceptance Scenarios**:

1. **Given** a large import in progress, **When** I view the screen, **Then** I see a progress indicator (rows processed / total).
2. **Given** import completes, **When** I view results, **Then** a summary shows counts and any errors.

### Edge Cases

- Duplicate exercise names: match existing exercises by name (case-insensitive).
- Unknown exercise in CSV: create with sensible defaults (trackingType inferred from columns, equipmentType="other").
- Weight (lbs) column: IGNORE - use Weight (kg) column only.
- Distance and Time columns: map to distanceMeters and durationSeconds when present.
- Distance Unit column: if "mi" or "miles", convert distance to meters; otherwise assume meters.
- Time column: integer seconds (parsed as Int).
- Empty rows or rows with only notes: skip.
- CSV encoding: handle UTF-8 and common variants.
- Do NOT run per-set PR pipeline during bulk import - use bulk rebuild after.

## Requirements

### Functional Requirements

- **FR-001**: Import MUST accept CSV with columns: Date, Exercise, Category, Weight (kg), Weight (lbs), Reps, Distance, Distance Unit, Time, Notes, Kind.
- **FR-002**: Import MUST group rows by Date to create one Workout per unique date.
- **FR-003**: Import MUST create Exercises for unknown names with sensible defaults.
- **FR-004**: Import MUST map: Weight (kg) -> Set.weight, Reps -> Set.reps, Category -> Exercise.primaryMuscle, Distance -> Set.distanceMeters, Time -> Set.durationSeconds, Notes -> Set.notes.
- **FR-005**: Kind column MUST be used to infer Exercise.trackingType (NOT Set.setType). All imported sets default to setType=working.
- **FR-006**: Import MUST NOT run per-set PR pipeline. Instead: import all sets, then run StatsService.rebuildAll() + PRService.rebuildAll() per AGENT_RULES Section 9.
- **FR-007**: Import MUST validate data and reject malformed rows with error reporting.
- **FR-008**: Import MUST show progress indicator for large datasets.
- **FR-009**: Import MUST ignore the Weight (lbs) column (derived, not authoritative).
- **FR-010**: Export MUST include all workouts, exercises, and sets in CSV format.
- **FR-011**: Export MUST use share sheet for file delivery.
- **FR-012**: Import/Export accessible from Settings -> DATA section.

### Key Entities

- **ImportService**: CSV parsing, data mapping, bulk insert, trigger rebuild. No per-set PR pipeline.
- **Export**: CSV generation from all data with share sheet.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Import of 12,000 rows completes within 60 seconds.
- **SC-002**: All valid rows create correct Workout/Exercise/Set relationships.
- **SC-003**: Post-import rebuild produces correct PRs and stats.
- **SC-004**: Export CSV can be re-imported with no data loss.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| tech_stack_and_architecture.md | Section 11 | Import/export decisions and CSV mapping |
| tech_stack_and_architecture.md | Section 11 | Export format and CSV column structure |
| AGENT_RULES.md | Section 6 | ImportService responsibilities |
| AGENT_RULES.md | Section 9 | Import rules (bulk rebuild, no per-set pipeline) |
