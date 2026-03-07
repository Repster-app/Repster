# Feature Specification: Set + Stats Services

**Feature Branch**: `004-set-and-stats-services`
**Created**: 2026-02-19
**Status**: Draft
**Input**: SetService orchestration per specdoc Sections 4 and 8. StatsService per AGENT_RULES Section 6.

## User Scenarios & Testing

### User Story 1 - Set Save Orchestration (Priority: P1)

As a lifter completing a set, I need the system to save the set, compute effectiveWeight, trigger the PR pipeline, and update stats - all as one coordinated operation.

**Why this priority**: This is the core write path. Every set flows through SetService.

**Independent Test**: Save a set via SetService, verify effectiveWeight is calculated, cachedPRStatus is set, and ExerciseStats is updated.

**Acceptance Scenarios**:

1. **Given** an exercise with bodyweightFactor=0.65 and user bodyweight=80kg, **When** I save a set with weight=20kg, **Then** effectiveWeight is stored as 72kg (20 + 80*0.65).
2. **Given** a saved set, **When** save completes, **Then** PRService.evaluate(set) has been called and cachedPRStatus is populated.
3. **Given** a saved set, **When** save completes, **Then** StatsService.updateStats(for: exerciseId) has been called.
4. **Given** an exercise with bodyweightFactor=0.0, **When** I save a set with weight=100kg, **Then** effectiveWeight=100kg.
5. **Given** no bodyweight entry exists, **When** I save a set for an exercise with bodyweightFactor=0.65, **Then** effectiveWeight=weight (bodyweight portion skipped, user warned).

### User Story 2 - Set Edit (Priority: P1)

As a lifter who made an error, I need to edit a set and have all derived data recomputed.

**Why this priority**: Editing is frequent; derived data must stay consistent.

**Independent Test**: Edit a set's weight, verify effectiveWeight recalculated and PR pipeline re-evaluated.

**Acceptance Scenarios**:

1. **Given** a saved set, **When** I edit the weight, **Then** effectiveWeight is recalculated and the PR pipeline re-evaluates per specdoc Section 7.2 (edit path).
2. **Given** a saved set, **When** I edit the weight, **Then** ExerciseStats is updated to reflect the change.

### User Story 3 - Set Delete (Priority: P1)

As a lifter, I need to delete a set and have PRs and stats recomputed correctly.

**Why this priority**: Hard delete with correct cascade is critical for data integrity.

**Independent Test**: Delete a set, verify ExerciseStats updated and PRs recomputed if needed.

**Acceptance Scenarios**:

1. **Given** a set that owns a PR, **When** I delete it, **Then** PRService handles recomputation (find next best or remove PR record) per specdoc Section 7.2 (delete path).
2. **Given** a deleted set, **When** delete completes, **Then** ExerciseStats totals are decremented.

### User Story 4 - Stats Service Aggregation (Priority: P1)

As a developer, I need ExerciseStats updated incrementally at write-time so screens display instant, accurate data.

**Why this priority**: Prevents expensive read-time aggregation over large datasets.

**Independent Test**: After saving sets, ExerciseStats reflects correct totalSets, totalReps, totalVolume, maxWeight, etc.

**Acceptance Scenarios**:

1. **Given** ExerciseStats for exercise X, **When** a new set is saved, **Then** totalSets, totalReps, totalVolume, lastPerformedDate are updated incrementally.
2. **Given** StatsService, **When** rebuildAll() is called, **Then** all ExerciseStats are recomputed from raw sets using database aggregation (not Swift iteration).
3. **Given** a partial set, **When** stats are updated, **Then** partial sets are excluded from volume calculations.
4. **Given** warmup sets and includeWarmupsInVolume=false, **When** stats are updated, **Then** warmup sets are excluded from volume.

### Edge Cases

- Set with hasData=false: still saved but excluded from analytics/PRs.
- effectiveWeight when bodyweightFactor=0: effectiveWeight equals raw weight.
- Volume for duration-only exercises: volume is not applicable (no weight component).
- StatsService.rebuildAll() on 12,000+ sets: must use database aggregation, not iteration.
- Concurrent saves: SetService should handle saves sequentially to avoid race conditions on PRs.

## Requirements

### Functional Requirements

- **FR-001**: SetService.save(set) MUST compute effectiveWeight at save time per specdoc Section 5.4: effectiveWeight = weight + (closestBodyweight x exercise.bodyweightFactor).
- **FR-002**: SetService.save(set) MUST call PRService.evaluate(set) after persisting.
- **FR-003**: SetService.save(set) MUST call StatsService.updateStats(for: exerciseId) after PR evaluation.
- **FR-004**: SetService.edit(set) MUST recalculate effectiveWeight and re-trigger the PR + stats pipeline.
- **FR-005**: SetService.delete(set) MUST trigger PR recomputation (if PR owner) and stats update.
- **FR-006**: SetService MUST NOT access ModelContext directly - it uses SetRepository (per AGENT_RULES Section 2).
- **FR-007**: StatsService.updateStats(for:) MUST update ExerciseStats incrementally when possible.
- **FR-008**: StatsService.rebuildAll() MUST recompute all ExerciseStats using database aggregation.
- **FR-009**: Volume calculation MUST use effectiveWeight x reps, excluding partial sets and warmups (per settings).
- **FR-010**: effectiveWeight MUST never be recalculated retroactively - historical sets keep their original value.
- **FR-011**: The entire save pipeline (persist + PR + stats) MUST complete within 100ms per AGENT_RULES Section 5.5.
- **FR-012**: Sets MUST persist immediately on entry - "Finish Workout" is a UI action not a data commit.

### Key Entities

- **SetService**: Orchestrates set save/edit/delete, computes effectiveWeight, triggers PR and stats pipelines.
- **StatsService**: Owns ExerciseStats updates - incremental and full rebuild.
- **ExerciseStats**: Rebuildable cache per exercise (totalWorkouts, totalSets, totalReps, totalVolume, maxWeight, bestE1RM, etc.).

## Success Criteria

### Measurable Outcomes

- **SC-001**: effectiveWeight is correctly computed for all bodyweightFactor values (0.0, 0.5, 0.64, 0.65, 0.80).
- **SC-002**: PR pipeline and stats update both fire on every set save.
- **SC-003**: ExerciseStats totals are accurate after any sequence of saves, edits, and deletes.
- **SC-004**: rebuildAll() produces identical results to incremental updates for the same dataset.
- **SC-005**: Set save pipeline completes within 100ms.

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| specdoc.md | Section 4 | Edit/delete behavior contracts |
| specdoc.md | Section 5.4 | effectiveWeight calculation |
| specdoc.md | Section 6.4 | ExerciseStats fields |
| specdoc.md | Section 8 | Implementation contracts (write-time, aggregation, performance) |
| AGENT_RULES.md | Section 3.3 | effectiveWeight rules |
| AGENT_RULES.md | Section 5 | Performance rules |
| AGENT_RULES.md | Section 6 | Service responsibilities |
