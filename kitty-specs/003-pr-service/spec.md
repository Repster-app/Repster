# Feature Specification: PR Service

**Feature Branch**: `003-pr-service`
**Created**: 2026-02-19
**Status**: Draft
**Input**: Full PR pipeline per specdoc Section 7, PR rules per AGENT_RULES Section 4, integer grams comparison per AGENT_RULES Section 3.4.

## User Scenarios & Testing

### User Story 1 - New Set PR Evaluation (Priority: P1)

As a lifter completing a set, I want PRs detected automatically at write-time so I see a badge instantly without waiting for a background scan.

**Why this priority**: PR detection is the core differentiator. Must work correctly from day one.

**Independent Test**: Save a set with a higher effectiveWeight than the existing PR for that exercise/reps, verify PerformanceRecord is updated and cachedPRStatus is set to "current".

**Acceptance Scenarios**:

1. **Given** no existing PR for exercise X at 5 reps, **When** I save a set with effectiveWeight 100kg for 5 reps, **Then** a PerformanceRecord is created (exerciseId=X, recordType=repMax, reps=5, value=100) and cachedPRStatus="current".
2. **Given** an existing 5-rep PR of 100kg, **When** I save a set with effectiveWeight 105kg for 5 reps, **Then** the PerformanceRecord is updated to 105kg, the new set gets cachedPRStatus="current", and the old PR set gets cachedPRStatus="previous".
3. **Given** an existing 5-rep PR of 100kg, **When** I save a set with effectiveWeight 100kg (exact match) in a different workout, **Then** PerformanceRecord is NOT updated and the new set gets cachedPRStatus="matched".
4. **Given** an existing 5-rep PR of 100kg, **When** I save a set with effectiveWeight 100kg in the SAME workout as the PR-owning set, **Then** the new set gets cachedPRStatus="matched" in the database (UI hides the badge for same-workout sets per specdoc S7.3).
5. **Given** an existing 5-rep PR of 100kg, **When** I save a set with effectiveWeight 95kg, **Then** the new set gets cachedPRStatus=null.

### User Story 2 - PR Eligibility Filtering (Priority: P1)

As a lifter, I want warmup and partial sets excluded from PRs by default so my actual working PRs are accurate.

**Why this priority**: Incorrect PR attribution would undermine trust in the app.

**Independent Test**: Save a warmup set that beats the current PR, verify it does NOT update the PerformanceRecord.

**Acceptance Scenarios**:

1. **Given** a set with hasData=false, **When** PR evaluation runs, **Then** cachedPRStatus=null, no PerformanceRecord change.
2. **Given** a set with excludeFromPRs=true, **When** PR evaluation runs, **Then** cachedPRStatus=null, no PerformanceRecord change.
3. **Given** a warmup set and settings.includeWarmupsInPRs=false, **When** PR evaluation runs, **Then** cachedPRStatus=null.
4. **Given** a partial set (always excluded), **When** PR evaluation runs, **Then** cachedPRStatus=null regardless of settings.

### User Story 3 - PR Recomputation on Edit/Delete (Priority: P1)

As a lifter who edits or deletes a set that held a PR, I want the system to find the next best candidate automatically.

**Why this priority**: Data integrity - PRs must always point to valid sets.

**Independent Test**: Delete the PR-owning set, verify PerformanceRecord updates to the next best set.

**Acceptance Scenarios**:

1. **Given** set A owns the 5-rep PR at 100kg, **When** set A is deleted, **Then** the system queries WorkoutSet for the next best (exerciseId, reps=5, ordered by effectiveWeight DESC, date ASC) and updates PerformanceRecord.
2. **Given** set A owns the 5-rep PR at 100kg and no other 5-rep sets exist, **When** set A is deleted, **Then** the PerformanceRecord row is deleted.
3. **Given** set A owns the 5-rep PR at 100kg, **When** set A is edited to 95kg, **Then** the system finds the new best candidate and updates accordingly.

### User Story 4 - Suffix-Max PR Display (Priority: P2)

As a lifter viewing my PR table, I want dominated entries hidden so I see my true capability frontier.

**Why this priority**: Display quality - avoids confusing users with overwritten records.

**Independent Test**: Given PRs at various rep counts, verify the suffix-max algorithm filters correctly.

**Acceptance Scenarios**:

1. **Given** PRs: 12rep=90kg, 10rep=85kg, 8rep=95kg, 5rep=100kg, **When** displaying the PR table, **Then** the 10-rep entry (85kg) is hidden because 12rep at 90kg dominates it.

### User Story 5 - Integer Grams Comparison (Priority: P1)

All weight comparisons in the PR pipeline must use integer grams conversion to avoid floating-point errors.

**Why this priority**: Float comparison bugs would cause missed PRs or phantom PRs.

**Independent Test**: Compare 100.0kg and 100.0001kg - they must be treated as equal (both 100000 grams).

**Acceptance Scenarios**:

1. **Given** effectiveWeight 100.0001 and existing PR value 100.0, **When** compared via toGrams(), **Then** both equal 100000 grams, treated as a match not a new PR.

### Edge Cases

- First-ever set for an exercise: creates the initial PerformanceRecord.
- All sets for a rep count deleted: PerformanceRecord row is removed entirely.
- Exercise with bodyweightFactor > 0: PR comparison uses effectiveWeight (includes bodyweight contribution).
- Multiple sets in same workout with same weight: only the first gets "matched" badge (if it matches PR), rest get null.
- PR rebuild after settings change (includeWarmupsInPRs toggled): requires PRService.rebuildAll().

## Requirements

### Functional Requirements

- **FR-001**: PRService.evaluate(set) MUST run at write-time after every set save, implementing the full pipeline from specdoc Section 7.2.
- **FR-002**: PR comparisons MUST use integer grams conversion: toGrams(_ kg: Double) -> Int = Int(round(kg * 1000)), per AGENT_RULES Section 3.4.
- **FR-003**: Eligibility check MUST filter out: sets with hasData=false, sets with excludeFromPRs=true, warmup sets (when setting is off), partial sets (always).
- **FR-004**: PR ownership MUST follow earliest-occurrence-wins for ties, per specdoc Section 4.2.
- **FR-005**: Exact matches MUST set cachedPRStatus="matched" in the database regardless of workout context. The UI hides the badge for same-workout sets. Per specdoc Section 7.3.
- **FR-006**: On edit of PR-owning set where new value is lower, MUST query WorkoutSet table to find new best candidate, per specdoc Section 7.2.
- **FR-007**: On delete of PR-owning set, MUST find next best or delete the PerformanceRecord row, per specdoc Section 7.2.
- **FR-008**: Suffix-max filtering MUST be available for PR table display, per specdoc Section 7.4.
- **FR-009**: PRService MUST only modify cachedPRStatus on sets - it does NOT handle other set fields (per AGENT_RULES Section 6).
- **FR-010**: PRService MUST query PerformanceRecord for normal operations, only querying WorkoutSet when recomputing after edit/delete (per specdoc Section 7.1).
- **FR-011**: PRService.rebuildAll() MUST be available for bulk rebuild after import or settings changes.
- **FR-012**: PR pipeline MUST run on a background context to avoid blocking UI, per specdoc Section 8.5.

### Key Entities

- **PerformanceRecord**: Single table for all PR types. Uniqueness: (exerciseId, recordType, reps).
- **WorkoutSet.cachedPRStatus**: Enum field set by PRService at write-time (current/matched/previous/null).
- **PRService**: Owns all PR evaluation logic. Does not modify sets beyond cachedPRStatus.

## Success Criteria

### Measurable Outcomes

- **SC-001**: New PR detection completes within the 100ms set-save budget.
- **SC-002**: Float comparison never produces incorrect PR results (integer grams conversion verified).
- **SC-003**: Warmup and partial sets never appear as PRs when settings exclude them.
- **SC-004**: Deleting a PR-owning set correctly promotes the next best candidate.
- **SC-005**: Suffix-max filtering produces the correct capability frontier for any PR dataset.
- **SC-006**: Same-workout duplicate sets store cachedPRStatus="matched" in the database but the UI does not display the badge (per specdoc S7.3).

## Documentation References

| Document | Section | What it defines |
|----------|---------|-----------------|
| specdoc.md | Section 7 (all) | Complete PR pipeline logic |
| specdoc.md | Section 7.1 | Table usage - PerformanceRecord vs Set |
| specdoc.md | Section 7.2 | Full PR pipeline for save/edit/delete |
| specdoc.md | Section 7.3 | Same-workout matching rule |
| specdoc.md | Section 7.4 | Suffix-max filtering algorithm |
| specdoc.md | Section 4.1-4.5 | Edit/delete behavior contracts |
| specdoc.md | Section 8.3 | Float comparison - integer grams |
| AGENT_RULES.md | Section 3.4 | Integer grams implementation |
| AGENT_RULES.md | Section 4 | PR pipeline rules |
| AGENT_RULES.md | Section 6 | Service responsibilities (PRService) |
