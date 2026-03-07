# Feature Specification: Repositories + Indexes

**Feature Branch**: `002-repositories-and-indexes`
**Created**: 2026-02-19
**Status**: Draft
**Input**: Repository protocols and implementations for all SwiftData models, plus required database indexes.

## User Scenarios & Testing

### User Story 1 - Repository Protocols (Priority: P1)

As a developer building services, I need protocol-based repository abstractions for every SwiftData model so services never touch ModelContext directly.

**Why this priority**: Services cannot be built without repositories. This enforces the layer separation rule.

**Independent Test**: Each repository protocol compiles, each implementation can save/fetch/delete its entity through SwiftData.

**Acceptance Scenarios**:

1. **Given** the repository layer, **When** I inspect any Service, **Then** it accesses data exclusively through repository protocols, never through ModelContext.
2. **Given** SetRepository, **When** I call save/fetch/delete, **Then** WorkoutSet entities are persisted and retrievable via SwiftData.
3. **Given** all repositories, **When** I check the layer structure, **Then** only repositories import SwiftData and access ModelContext.

### User Story 2 - Database Indexes (Priority: P1)

As a developer, I need the required database indexes configured so PR lookups and set queries meet the <100ms performance target.

**Why this priority**: Without indexes, the PR pipeline will be slow on datasets of 10,000+ sets.

**Independent Test**: Indexes are configured in the SwiftData model configuration and can be verified via the schema.

**Acceptance Scenarios**:

1. **Given** the SwiftData configuration, **When** I inspect indexes, **Then** PerformanceRecord has an index on (exerciseId, recordType, reps).
2. **Given** the SwiftData configuration, **When** I inspect indexes, **Then** WorkoutSet has an index on (exerciseId, reps, effectiveWeight DESC, date ASC).

### User Story 3 - Aggregation Query Methods (Priority: P2)

As a developer, I need efficient query methods that avoid loading large collections into memory, using sort+fetchLimit for MAX and pre-computed ExerciseStats for totals.

**Why this priority**: Prevents the anti-pattern of iterating in Swift over large datasets.

**Independent Test**: MAX queries use sort+fetchLimit(1). Total volume reads from pre-computed ExerciseStats, not from loading all sets.

**Acceptance Scenarios**:

1. **Given** ExerciseStatsRepository, **When** I call fetch(for: exerciseId), **Then** the returned ExerciseStats contains a pre-computed totalVolume that was updated at write-time, not computed by loading all sets.
2. **Given** SetRepository, **When** I call fetchMaxEffectiveWeight(for: exerciseId, reps:), **Then** it returns the maximum via database query.

### Edge Cases

- What if a repository method is called with an exerciseId that has no data? Return nil or 0 as appropriate.
- What if ModelContext save fails? Throw the error to the service layer for handling.
- SwiftData index syntax may differ from raw SQL - use SwiftData's native index API.

## Requirements

### Functional Requirements

- **FR-001**: A repository protocol MUST exist for each entity: SetRepository, WorkoutRepository, ExerciseRepository, ExerciseStatsRepository, PerformanceRecordRepository, BodyweightEntryRepository, HealthProfileRepository, ProgramRepository.
- **FR-002**: Repository implementations MUST be the only layer that imports SwiftData and accesses ModelContext (per AGENT_RULES Section 2).
- **FR-003**: Repositories MUST support async/await pattern for all operations.
- **FR-004**: SetRepository MUST include query methods: fetchSets(for exerciseId:, reps:, orderedBy: SetSortOrder), fetchSets(for exerciseId:, limit:), fetchSets(for workoutId:), and fetchMaxEffectiveWeight(for exerciseId:, reps:). SetSortOrder enum MUST have cases: effectiveWeightDesc, dateAsc, dateDesc.
- **FR-005**: PerformanceRecordRepository MUST include lookup by (exerciseId, recordType, reps) and bulk fetch by exerciseId.
- **FR-006**: Database index on PerformanceRecord(exerciseId, recordType, reps) MUST be configured per AGENT_RULES Section 5.4.
- **FR-007**: Database index on WorkoutSet(exerciseId, reps, effectiveWeight, date) MUST be configured per AGENT_RULES Section 5.4.
- **FR-008**: BodyweightEntryRepository MUST support closest-weight lookup by date (for effectiveWeight calculation).
- **FR-009**: Repository methods MUST avoid loading large collections to iterate. Use sort+fetchLimit for MAX queries. Use pre-computed ExerciseStats (write-time updated) for totals. SwiftData has no native SUM/AVG — see constitution Known Platform Limitations.
- **FR-010**: All repository methods MUST use Swift error handling (throws) for failure cases.

### Key Entities

- **Repository Protocol**: Defines the contract for data access per entity. Lives in Core/Repositories/.
- **Repository Implementation**: SwiftData-backed implementation of each protocol. Also in Core/Repositories/.
- **ModelContext**: SwiftData context, only accessed within repository implementations.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Every SwiftData model has a corresponding repository protocol and implementation.
- **SC-002**: No service or ViewModel imports SwiftData or references ModelContext.
- **SC-003**: Both required indexes are configured in SwiftData model configuration.
- **SC-004**: Aggregation methods (volume, max weight) compute at the database level.
- **SC-005**: All repository methods compile and follow async/await patterns.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| tech_stack_and_architecture.md | Section 4.3 | Repository pattern with protocol example |
| AGENT_RULES.md | Section 2 | Layer rules - only repositories touch SwiftData |
| AGENT_RULES.md | Section 5.2 | Database aggregation over Swift iteration |
| AGENT_RULES.md | Section 5.4 | Required database indexes |
| specdoc.md | Section 7.6 | Index definitions for PR queries |
| specdoc.md | Section 8.6 | Database aggregation guidance |
