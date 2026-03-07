# Research: Workout + Exercise + Bodyweight Services

**Feature**: 005-workout-exercise-bodyweight-services
**Date**: 2026-02-24

## Key Findings

| Topic | Decision | Rationale | Alternatives Considered |
|-------|----------|-----------|------------------------|
| Service threading model | Plain `actor` for all three services | AGENT_RULES S6: services must not access ModelContext. Matches PRService/SetService/StatsService pattern from 003/004. | `@ModelActor` (violates rules), plain class (no concurrency safety) |
| Cascade deletion strategy (workout) | Bulk delete sets via repository, then `PRService.rebuild()` + `StatsService.rebuild()` per affected exercise | AGENT_RULES S6: WorkoutService "Does NOT: Handle individual set logic". specdoc S10: "full rebuild as fallback". Feature spec: "PRs and ExerciseStats are recomputed for affected exercises." | Per-set `SetService.delete()` (violates AGENT_RULES S6, O(n) pipeline calls) |
| Cascade deletion strategy (exercise) | Same as workout: bulk delete sets + rebuild per exercise | Consistent pattern. specdoc S10 same rationale. | Per-set deletion (same issues) |
| Active workout enforcement | Return existing active workout if one exists (no error) | User preference. Spec edge cases: "block or warn". Returning existing is safest — avoids data loss. | Throw error (caller must handle), auto-finish old workout (risky, data loss) |
| trackingType immutability enforcement | Check via `exerciseRepo.hasAssociatedSets()` before allowing change | Method already exists from feature 002. specdoc S5.6: "Cannot be changed once any set is linked." | Check in repository save (wrong layer), check in UI only (unsafe) |
| bodyweightFactor change → rebuild | Rebuild ExerciseStats + PRs using existing stored effectiveWeight values. Never recalculate historical effectiveWeight. | specdoc S5.4: "Store once at save time, never recalculate retroactively." Constitution confirms. | Recalculate all historical effectiveWeight (violates spec) |
| BodyweightService scope | Thin service wrapping repository CRUD + closest-weight lookup + health profile awareness | AGENT_RULES S6: "CRUD for bodyweight entries, closest-weight lookup". Repository already has the query logic. | Put logic directly in ViewModel (violates architecture), complex service (over-engineering) |
| Workout duration calculation | `endTime - startTime` in seconds, computed in `finishWorkout()` | specdoc S6.2: duration is "Duration in seconds". Simple derivation from stored timestamps. | Stopwatch timer (adds complexity, not in spec) |
| Cross-actor data flow | UUID/primitive parameter passing, not @Model objects | SwiftData models not Sendable. Established pattern from PRService/SetService. | DTOs (extra mapping), PersistentIdentifier (internal API) |
| DI wiring order | BodyweightService (no deps) → ExerciseService (needs SetRepo, PRService, StatsService) → WorkoutService (needs SetRepo, PRService, StatsService) | No circular dependencies. WorkoutService and ExerciseService are independent of each other. | Single init (same, just order within ServiceContainer) |

## Repository Gap Analysis

### New Methods Needed on SetRepositoryProtocol

| Method | Purpose | Used By |
|--------|---------|---------|
| `deleteSets(for workoutId: UUID) async throws` | Bulk delete all sets in a workout | WorkoutService cascade deletion |
| `deleteSets(forExercise exerciseId: UUID) async throws` | Bulk delete all sets for an exercise | ExerciseService cascade deletion |
| `fetchExerciseIds(for workoutId: UUID) async throws -> Set<UUID>` | Get affected exercises before workout deletion | WorkoutService (to know which exercises need rebuild) |

### Existing Methods Sufficient

| Method | Already On | Used By (005) |
|--------|-----------|--------------|
| `fetchSets(for workoutId:)` | SetRepositoryProtocol | WorkoutService (backup/verification) |
| `fetchSets(for exerciseId:, limit:)` | SetRepositoryProtocol | ExerciseService (history) |
| `hasAssociatedSets(_:)` | ExerciseRepositoryProtocol | ExerciseService (trackingType guard) |
| `fetchInProgress()` | WorkoutRepositoryProtocol | WorkoutService (active workout) |
| `fetchClosest(to:healthProfileId:)` | BodyweightEntryRepositoryProtocol | BodyweightService (closest lookup) |
| `fetchAll(for healthProfileId:)` | BodyweightEntryRepositoryProtocol | BodyweightService (list entries) |
| `fetchOrCreate()` | HealthProfileRepositoryProtocol | BodyweightService (health profile) |

### No New Repository Types Needed

All repositories required by feature 005 already exist from features 001-002.

## Metadata Mutability Implementation

Per specdoc S5.6, ExerciseService must classify field changes:

| Category | Fields | Action on Change |
|----------|--------|-----------------|
| **Immutable** (sets exist) | `trackingType` | Block with error |
| **Rebuild required** | `bodyweightFactor`, `unilateral`, `bilateralLoadFactor`, `equipmentType` | Allow change, then `PRService.rebuild(for:)` + `StatsService.rebuild(for:)` |
| **Low-risk mutable** | `name`, `primaryMuscle`, `secondaryMuscles`, `movementPattern`, `defaultRestTime`, `weightIncrement` | Allow change, no rebuild |

Key insight: The "rebuild required" fields trigger a rebuild of the *aggregate* data (ExerciseStats, PerformanceRecord), NOT a recalculation of `effectiveWeight` on historical sets. The stored `effectiveWeight` values are immutable facts.
