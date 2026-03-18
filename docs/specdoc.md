# Strength Training App — Data Model Specification

**Version:** 1.3 (Consolidated)  
**Status:** Authoritative Source of Truth  
**Last Updated:** January 2026

---

## Document Overview

This document consolidates all design decisions, data structures, and implementation contracts for the workout app's data model. It combines and reconciles content from:

- Initial table/field definitions and logic
- Frozen Sections 1–4 specification
- Section 4 & 5 decisions document

### Section Status Summary

| Section | Status | Description |
|---------|--------|-------------|
| 1 | **FROZEN** | Core Performance Data (Set-level facts) |
| 2 | **FROZEN** | Set Context & Qualitative Data |
| 3 | **FROZEN** | Workout (Session-level container) |
| 4 | **LOCKED** | Editing, Deletion, PRs & Derived Data |
| 5 | **WORKING DRAFT** | Exercise Metadata & Interpretation Rules |

---

## Table of Contents

1. [Core Performance Data](#1-core-performance-data)
2. [Set Context & Qualitative Data](#2-set-context--qualitative-data)
3. [Workout (Session Container)](#3-workout-session-container)
4. [Editing, Deletion, PRs & Derived Data](#4-editing-deletion-prs--derived-data)
5. [Exercise Metadata & Interpretation Rules](#5-exercise-metadata--interpretation-rules)
6. [Complete Schema Reference](#6-complete-schema-reference)
7. [PR Pipeline & Key Queries](#7-pr-pipeline--key-queries)
8. [Implementation Contracts](#8-implementation-contracts)
9. [User Settings](#9-user-settings)
10. [Explicit Non-Decisions (Deferred)](#10-explicit-non-decisions-deferred)
11. [Architecture Decisions Pending](#11-architecture-decisions-pending)

---

# 1. Core Performance Data

**Status:** FROZEN  
**Purpose:** Capture the atomic, historical truth of what happened in training, independent of interpretation, progression logic, or UI.

## 1.1 Minimal Atomic Performance Variables

The system supports **four atomic performance dimensions** (the "Core-4"):

| Variable | Type | Description |
|----------|------|-------------|
| `weight` | kg (float) | Load lifted |
| `reps` | int | Repetition count |
| `durationSeconds` | int | Time under tension or work duration |
| `distanceMeters` | float | Distance covered |

### Rules

- A set may use **1–3** of these dimensions, depending on the exercise
- An exercise defines **which dimensions are valid** via `trackingType`
- Within a single exercise, the **same dimensions apply to all its sets**
- Mixing different performance dimensions within the same exercise over time is **not supported**

### Examples

| Exercise | Dimensions Used |
|----------|-----------------|
| Barbell squat | weight + reps |
| Plank | duration |
| Sled push | weight + distance |
| AMRAP with load | weight + reps + duration |

## 1.2 Set Completion & Lifecycle

A set is considered **completed** when the user clicks "save" or uses a checkmark (depending on settings).

Completion is represented by a boolean (`completed`).

**Once completed:**
- The set participates in stats and PR logic
- The set is considered a historical fact **but not immutable** (editing/deletion allowed—see Section 4)

### `completed` vs `hasData` Distinction

These are two different concepts:

| Concept | Type | Meaning | Used for |
|---------|------|---------|----------|
| `completed` | Stored boolean | User checked the "done" checkbox | UI workflow, user intent |
| `hasData` | Computed property | Set has actual measurable values entered | Analytics, PRs, volume calculations |

**Why this matters:**
- A set can be `completed = true` but `hasData = false` (user checked by mistake, no values entered)
- A set can be `completed = false` but `hasData = true` (user entered data but forgot to check)

**Rule:** Analytics, PR calculations, and volume calculations should use `hasData`, not `completed`.

**`hasData` logic:**
```
hasData = true if ANY of:
  - weight > 0 AND reps > 0
  - durationSeconds > 0
  - distanceMeters > 0
```

## 1.3 Set Types

Sets are categorized to distinguish intent and meaning.

**Supported set types:**

| Type | Description | PR Eligibility | Volume Contribution |
|------|-------------|----------------|---------------------|
| `warmup` | Preparatory sets | Excluded by default (unless settings override) | Excluded by default (configurable) |
| `working` | Primary training sets | Full PR/stats participation | Yes |
| `partial` | Incomplete ROM or assisted | **No** — excluded from PRs | **No** — excluded from volume |
| `dropset` | Reduced weight continuation after failure | Full participation | Yes |
| `restpause` | Brief rest, then continue same weight | Full participation | Yes |
| `cluster` | Intra-set rest between mini-sets | Full participation | Yes |
| `myo` | Myo-reps / rest-pause hypertrophy method | Full participation | Yes |
| `amrap` | As Many Reps As Possible | Full participation | Yes |
| `backoff` | Reduced intensity after top sets | Full participation | Yes |
| `failure` | Taken to technical/absolute failure | Full participation | Yes |
| `tempo` | Specific tempo prescription | Full participation | Yes |
| `isometric` | Static hold | Full participation | N/A (duration-based) |
| `eccentric` | Eccentric-focused / negative | Full participation | Yes |

The model supports **future expansion** of set types. Unused types can be hidden in UI.

## 1.4 Special Techniques & Intensity Methods

Techniques such as drop sets, rest-pause, tempo manipulation, and accommodating resistance are **not first-class structured fields**.

**Decision:** Capture via **notes/tags** on the set to avoid UI and schema explosion. Interpretation may evolve later.

## 1.5 Editing & Deletion

Sets can be edited or deleted after completion. Consequences are handled in Section 4.

---

# 2. Set Context & Qualitative Data

**Status:** FROZEN  
**Purpose:** Capture how the set felt, how it was performed, and where it sits in the workout structure.

## 2.1 Subjective Effort

**Supported measures:**
- `RPE` (Rate of Perceived Exertion)
- `RIR` (Reps in Reserve)

**Rules:**
- Both may exist in the system
- User chooses which they input
- Backend logic **may convert** between them for calculations (e.g., e1RM estimation)
- The **original user input is preserved**

## 2.2 Notes

Short free-text notes per set, used for technique reminders, unusual conditions, and qualitative flags.

Notes have **no semantic meaning** to the engine (for now).

## 2.3 Ordering & Structure

Two ordering concepts exist:

| Field | Purpose |
|-------|---------|
| `orderInWorkout` | Temporal order of sets in the workout; used for UI rendering and timeline reconstruction |
| `orderInExercise` | Ordinal position within the same exercise; helps detect top sets vs back-offs, fatigue progression |

These are **structural**, not performance variables.

## 2.4 Grouping (Supersets, Circuits)

Sets may optionally belong to a grouping (e.g., superset, circuit) via `supersetGroupId`.

**Purpose:**
- Enable correct rest logic
- Preserve workout structure
- Avoid incorrect assumptions based on linear ordering alone

**Important:** If implementing smart rest timers, naive "previous set" logic fails for alternating sets. Use `supersetGroupId` to compute "rest for the same exercise."

---

# 3. Workout (Session Container)

**Status:** FROZEN  
**Purpose:** Provide temporal, psychological, and organizational context for sets.

## 3.1 Definition

A workout represents a single training session, contains one or more sets, and may optionally belong to a program.

## 3.2 Stored Properties

| Field | Type | Description |
|-------|------|-------------|
| `id` | string/UUID | Unique identifier |
| `date` | date | Workout date |
| `startTime` | timestamp | Session start |
| `endTime` | timestamp | Session end |
| `duration` | int | Session duration (computed or stored) |
| `perceivedEffort` | float | Session RPE |
| `notes` | text | Session notes |
| `programId` | string (nullable) | Link to program/template |

## 3.3 Scope & Constraints

- Workouts may exist without completed sets (e.g., abandoned session)
- Sets belong to **exactly one workout**
- Moving sets between workouts is allowed conceptually (implementation detail)

## 3.4 Analytics Role

Workout-level metrics are mostly **derived** and provide context for fatigue, density, and workload distribution.

**Workouts are not PR-defining entities by default.**

---

# 4. Editing, Deletion, PRs & Derived Data

**Status:** LOCKED  
**Purpose:** Ensure correctness when historical facts (sets) change. Guarantee PR and stats integrity while keeping reads fast and flexible.

## 4.1 Core Principles

| Principle | Decision |
|-----------|----------|
| Set mutability | Sets are **editable and deletable** |
| Historical facts | Sets are historical facts but **not immutable** |
| PR derivation | PRs and cached stats are **derived from sets**; must reference originating `setId` |
| PR ownership | **Earliest occurrence** wins (first-highest owns the PR) |
| Exact matches | Do **not** create a new PR; UI shows "Match PR" status |
| Caching | Derived values **may be stored as caches** when it improves read performance |
| Rebuildability | PRs and stats must be **recomputable** from raw sets |
| Execution model | Sync now, but design must support **async later** without schema changes |

## 4.2 PR Tie / Match Rules

**PR uniqueness key for rep PRs:** `(exerciseId, recordType='repMax', reps)` in `PerformanceRecord`

**Implementation:** Store one row per `(exerciseId, recordType, reps)` with `value` (effectiveWeight) and `setId` of earliest occurrence.

**On exact-equality matches:**
- Do **not** create a new PR row
- Provide UI indication "Match PR" for sets that equal the current PR value

**For non-exact tie situations:** Use deterministic tie-breaker (earliest wins).

## 4.3 e1RM Policy

| Decision | Details |
|----------|---------|
| Storage | `e1RM` can be stored on `Set` at write time as a snapshot |
| Formula changes | Old sets retain stored e1RM unless reprocessing/migration is run |
| Optional | Store `e1RMFormulaVersion` per set for selective recompute |

## 4.4 Edit/Delete Behavior Contract

### On Set Edit

If the set did **not** own any PR or cached-stat maximum:
- Run standard incremental update (adjust stats and PR candidates)

If the set **was** the owner of a PR or contributed to a cached maximum:
- Recompute that PR/stat incrementally (preferred if cheap), OR
- Mark stats/PR stale and schedule background rebuild (safe fallback)

### On Set Delete

If the set owned a PR:
- Recompute the PR for that exercise (find next best candidate)
- If none exists, PR is removed

Always:
- Adjust affected aggregates (total volume, total sets, etc.)
- Rebuild path must be available and reliable

## 4.5 Performance & Execution Model

- PR/stat computation runs as a bounded, cheap work unit **after set save**
- Synchronous execution acceptable initially
- Code should be modular for sync or async dispatch
- Reads for PR screens must be O(1) or rely on small tables (`PerformanceRecord`, `ExerciseStats`)

---

# 5. Exercise Metadata & Interpretation Rules

**Status:** WORKING DRAFT  
**Purpose:** Define how sets are interpreted and how exercise metadata influences calculations, PRs, and UI. Keep metadata descriptive; avoid embedding derived analytics into metadata.

## 5.1 Metadata vs Data Principle

| Category | Location | Description |
|----------|----------|-------------|
| Metadata | `Exercise` table | Describes how an exercise is interpreted (low-frequency changes) |
| Data | `Set`/`Workout` tables | Raw historical facts |
| Derived | `ExerciseStats`/PR tables | Computed from sets, stored for performance |

**Principle:** Keep `Exercise` strictly descriptive. Analytics values belong to `ExerciseStats` or other caches.

## 5.2 Exercise Metadata Fields

### Behavior-Defining Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string/UUID | Unique identifier |
| `name` | string | Display name (e.g., "Pull-up") |
| `equipmentType` | enum | `barbell`, `dumbbell`, `machine_plate`, `machine_pin`, `bodyweight`, `sled`, etc. |
| `trackingType` | enum | `WEIGHT_REPS`, `DURATION`, `WEIGHT_DISTANCE`, `CUSTOM` — which Core-4 dimensions apply |
| `primaryMuscle` | string/enum | Primary muscle targeted |
| `secondaryMuscles` | list | Supporting muscles |
| `movementPattern` | enum | `hinge`, `squat`, `press`, `pull`, etc. |
| `unilateral` | bool | Whether exercise is commonly unilateral |
| `bilateralLoadFactor` | float (optional) | Analytic factor for bilateral scaling (analytics only, not PR ownership) |
| `bodyweightFactor` | float | 0.0 to 1.0 — portion of bodyweight contributing to effective load (e.g., 0 for bench, 0.65 for pull-ups) |
| `weightIncrement` | float | Smallest step / plate increments |
| `defaultRestTime` | int (seconds) | UI hint only |

## 5.3 Tracking Mode / Performance Dimensions

| Decision | Details |
|----------|---------|
| Who decides | `Exercise.trackingType` declares which Core-4 apply |
| 1-dimension | Allowed (e.g., plank uses `duration` only) |
| 2–3 dimensions | Allowed; dimensions are fixed per exercise and do not vary per set |
| UI behavior | Input form shows/hides fields according to `trackingType` |

## 5.4 Load Interpretation Rules (Minimal v1)

**Raw storage:** `weight` on Set = the external load typed by user (e.g., added weight for pull-ups, barbell weight for bench).

**Effective weight calculation:** At set save time, compute and store:
```
effectiveWeight = weight + (closestBodyweight × exercise.bodyweightFactor)
```

| Exercise | bodyweightFactor | User weighs 80kg, adds 20kg | effectiveWeight |
|----------|------------------|----------------------------|-----------------|
| Bench press | 0.0 | 20kg | 20kg |
| Pull-up | 0.65 | 20kg | 20 + (80 × 0.65) = 72kg |
| Dip | 0.80 | 20kg | 20 + (80 × 0.80) = 84kg |
| Push-up | 0.64 | 0kg | 0 + (80 × 0.64) = 51.2kg |

**Rules:**
- If `bodyweightFactor = 0` → `effectiveWeight = weight`
- If no bodyweight entry exists → `effectiveWeight = weight` (warn user to log bodyweight)
- Store once at save time, never recalculate retroactively
- Historical sets keep their original effective weight (accurate to what it was at the time)

**Usage:**
- Volume calculations use `effectiveWeight × reps`
- PR comparisons use `effectiveWeight`
- Charts use `effectiveWeight` for fair cross-exercise comparison

**Unilateral handling:**
- Store `side` on sets (`left`, `right`, `both`)
- Keep PR logic based on what was actually lifted per set
- Apply `bilateralLoadFactor` only in analytics, not PR ownership

## 5.5 Exercise Identity & Granularity

**Default:** Keep identity coarse (e.g., "Pull-up" is the exercise). Variations (grip, assistance, added load) are **data**, not separate exercise identities.

**User option:** Create distinct exercises for fundamentally different movements if they want separate PRs/stats.

**Rule of thumb:** Create a new exercise identity when mechanics or muscle emphasis changes materially.

## 5.6 Metadata Mutability Rules

### Immutable Once Sets Exist

- `trackingType` — **Cannot be changed** once any set is linked to the exercise. User must create a new exercise if they need different tracking dimensions.

### Require Rebuild if Changed

- `unilateral`
- `bilateralLoadFactor`
- `equipmentType`
- `bodyweightFactor`

If changed, system must rebuild `ExerciseStats` & PRs for that exercise.

### Mutable with Low Risk

- `name`
- `primaryMuscle` / `secondaryMuscles`
- `movementPattern`
- `defaultRestTime`
- `weightIncrement`

## 5.7 Metadata Purpose Classification

| Purpose | Fields |
|---------|--------|
| Calculation-critical | `trackingType`, `unilateral`, `bilateralLoadFactor`, `bodyweightFactor`, `weightIncrement` |
| UX-only | `defaultRestTime`, equipment icon, display hints |

## 5.8 Bilateral Load Factor Usage

**Decision:** Raw values for PRs, scaled values for analytics only.

| Context | Value Used | Example |
|---------|------------|---------|
| PR display | Raw (actual weight lifted) | "30kg PR" for dumbbell press |
| PR ownership logic | Raw | Compares 30kg vs 30kg |
| Analytics/charts | Scaled (bilateral equivalent) | Shows 60kg for volume comparisons |
| Cross-exercise comparison | Scaled | Enables fair comparison between unilateral and bilateral movements |

This ensures PRs feel "real" (you actually lifted that weight) while analytics allow apples-to-apples comparison.

---

# 6. Complete Schema Reference

## 6.1 `Set` — Atomic Performance Record

The historical fact representing one completed or planned set.

### Stored Fields

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `id` | string/UUID | No | Unique identifier |
| `workoutId` | string | No | Parent workout |
| `exerciseId` | string | No | Exercise performed |
| `date` | date | No | When performed |
| `startedAt` | timestamp | Yes | When set began (optional, for duration tracking) |
| `completedAt` | timestamp | Yes | When set was saved/finished (for rest calculations) |
| `weight` | float (kg) | Yes | External load lifted (user input) |
| `effectiveWeight` | float (kg) | Yes | `weight + (bodyweight × bodyweightFactor)` — calculated at save time |
| `reps` | int | Yes | Repetition count |
| `durationSeconds` | int | Yes | Time under tension |
| `distanceMeters` | float | Yes | Distance covered |
| `e1RM` | float | Yes | Estimated 1RM snapshot |
| `e1RMFormulaVersion` | string | Yes | Formula version (optional) |
| `rpe` | float | Yes | Rate of Perceived Exertion (actual) |
| `rir` | float | Yes | Reps in Reserve (actual) |
| `setType` | enum | No | See Section 1.3 for full list |
| `pauseDuration` | int (seconds) | Yes | Rest-pause duration |
| `side` | enum | Yes | `left`, `right`, `both` |
| `notes` | text | Yes | Free-form notes |
| `orderInWorkout` | int | No | Temporal order in workout |
| `orderInExercise` | int | No | Order within exercise |
| `supersetGroupId` | string | Yes | Superset/circuit grouping |
| `completed` | bool | No | Completion status (user workflow) |
| `excludeFromPRs` | bool | Yes | Manual override to exclude from PR calculations |
| `cachedPRStatus` | enum | Yes | PR status cached at write-time (see below) |
| `targetWeight` | float (kg) | Yes | Prescribed weight (from program or manual input) |
| `targetRepMin` | int | Yes | Minimum target reps (e.g., 4 in "4-6 reps") |
| `targetRepMax` | int | Yes | Maximum target reps (e.g., 6 in "4-6 reps") |
| `targetRPE` | float | Yes | Target RPE |
| `targetRIR` | int | Yes | Target RIR |
| `createdAt` | timestamp | No | Record creation time |
| `updatedAt` | timestamp | No | Last modification time |

### Computed Properties (not stored)

| Property | Logic | Used for |
|----------|-------|----------|
| `hasData` | `(weight > 0 AND reps > 0) OR durationSeconds > 0 OR distanceMeters > 0` | Analytics, PR eligibility, volume calculations |
| `volume` | `effectiveWeight × reps` (only for weight-based exercises) | Volume calculations |

### `cachedPRStatus` Values

| Value | Meaning |
|-------|---------|
| `current` | This set IS the current PR for its rep count |
| `matched` | This set equals the PR but wasn't first (tie) |
| `previous` | This set WAS a PR but has since been beaten |
| `null` | Not a PR |

**Note:** `cachedPRStatus` is set at write-time by the PR pipeline. See Section 7 for full PR logic.

### Target Fields

Target fields can be populated from:
- **Program**: Copied from `PlannedSet` when starting a workout from a program
- **Manual input**: User enters targets directly during ad-hoc workouts

UI displays targets alongside actual performance for real-time coaching (e.g., "Target: 100kg × 4-6 @ RPE 8 | Actual: 100kg × 5 @ RPE 7.5").

### Notes on `excludeFromPRs`

This is an independent user override. Warmup sets are excluded by default (unless settings override), but users can manually exclude any individual set regardless of type.

## 6.2 `Workout` — Session Container

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `id` | string/UUID | No | Unique identifier |
| `date` | date | No | Workout date |
| `startTime` | timestamp | Yes | Session start |
| `endTime` | timestamp | Yes | Session end |
| `duration` | int | Yes | Duration in seconds |
| `perceivedEffort` | float | Yes | Session RPE |
| `notes` | text | Yes | Session notes |
| `programId` | string | Yes | Link to program |
| `createdAt` | timestamp | No | Record creation time |
| `updatedAt` | timestamp | No | Last modification time |

## 6.3 `Exercise` — Metadata

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `id` | string/UUID | No | Unique identifier |
| `name` | string | No | Display name |
| `equipmentType` | enum | No | Equipment category |
| `trackingType` | enum | No | Which Core-4 dimensions apply (**immutable once sets exist**) |
| `primaryMuscle` | string | Yes | Primary muscle |
| `secondaryMuscles` | list | Yes | Supporting muscles |
| `movementPattern` | enum | Yes | Movement pattern |
| `unilateral` | bool | No | Is unilateral exercise |
| `bilateralLoadFactor` | float | Yes | Analytics scaling factor |
| `bodyweightFactor` | float | No | 0.0–1.0; portion of bodyweight in effective load |
| `weightIncrement` | float | Yes | Minimum increment |
| `defaultRestTime` | int | Yes | UI hint (seconds) |
| `createdAt` | timestamp | No | Record creation time |
| `updatedAt` | timestamp | No | Last modification time |

**Common `bodyweightFactor` values:**

| Exercise Type | Factor | Rationale |
|--------------|--------|-----------|
| Barbell/Dumbbell lifts | 0.0 | No bodyweight component |
| Pull-up / Chin-up | 0.65 | ~65% of bodyweight lifted |
| Dip | 0.80 | ~80% of bodyweight lifted |
| Push-up | 0.64 | ~64% of bodyweight lifted |
| Inverted row | 0.50 | ~50% of bodyweight |

## 6.4 `ExerciseStats` — Cached Aggregates

Rebuildable cache of exercise-level statistics.

| Field | Type | Description |
|-------|------|-------------|
| `exerciseId` | string | Exercise reference |
| `totalWorkouts` | int | Number of workouts |
| `totalSets` | int | Total sets performed |
| `totalReps` | int | Total reps performed |
| `totalVolume` | float | Lifetime tonnage (Σ weight × reps) |
| `maxWeight` | float | Best single lift |
| `bestE1RM` | float | Best estimated 1RM |
| `averageIntensity` | float | Average %1RM or avg RPE |
| `estimated1RMTrendSlope` | float | Trend analysis |
| `lastPRDate` | date | Most recent PR |
| `lastPerformedDate` | date | Last performed |
| `maxSessionVolume` | float | Best per-workout volume |

## 6.5 `PerformanceRecord` — Consolidated PR Table

Single table for all performance records, preventing state drift between separate PR tables.

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `id` | string/UUID | No | Unique identifier |
| `exerciseId` | string | No | Exercise reference |
| `recordType` | enum | No | `repMax`, `e1RM`, `maxVolume` |
| `reps` | int | Yes | Rep count (required for `repMax` type) |
| `value` | float | No | The record value (weight, e1RM, or volume) |
| `setId` | string | No | Set that holds this record |
| `date` | date | No | When achieved |
| `createdAt` | timestamp | No | Record creation time |
| `updatedAt` | timestamp | No | Last modification time |

**Uniqueness constraint:** `(exerciseId, recordType, reps)` — one record per combination.

**recordType values:**

| Type | Description | `reps` field |
|------|-------------|--------------|
| `repMax` | Best weight for specific rep count | Required (1, 2, 3, etc.) |
| `e1RM` | Best estimated 1RM | Null |
| `maxVolume` | Best session volume | Null |

**Key principle:** All PR lookups and updates go through this single table. No separate `ExercisePR` or `ExerciseRepPR` tables.

## 6.6 `BodyweightEntry` — Bodyweight Tracking

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `id` | string/UUID | No | Unique identifier |
| `healthProfileId` | string | No | Health profile reference |
| `date` | date | No | Entry date |
| `bodyweightKg` | float | No | Bodyweight in kg |
| `createdAt` | timestamp | No | Record creation time |
| `updatedAt` | timestamp | No | Last modification time |

Used for `effectiveWeight` calculation when `Exercise.bodyweightFactor > 0`.

## 6.7 `HealthProfile` — Local User Profile

Single-row table for local app deployment (no multi-user auth).

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `id` | string/UUID | No | Unique identifier |
| `unitPreference` | enum | No | `metric` or `imperial` (display preference) |
| `createdAt` | timestamp | No | Profile creation time |
| `updatedAt` | timestamp | No | Last modification time |

## 6.8 Program & Planning Tables

### `Program`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string/UUID | Unique identifier |
| `name` | string | Program name |
| `progressionModel` | string | Progression rules |
| `deloadRules` | string | Deload configuration |
| `autoRegulationEnabled` | bool | Auto-regulation flag |
| `createdAt` | timestamp | Record creation time |
| `updatedAt` | timestamp | Last modification time |

### `ProgramExercise`

| Field | Type | Description |
|-------|------|-------------|
| `programId` | string | Program reference |
| `exerciseId` | string | Exercise reference |
| `targetRepRange` | string | Target rep range |
| `intensityRule` | string | Intensity prescription |
| `minIncrement` | float | Minimum progression |
| `maxIncrement` | float | Maximum progression |

### `PlannedWorkout`

| Field | Type | Description |
|-------|------|-------------|
| `programId` | string | Program reference |
| `scheduledDate` | date | Planned date |
| `weekIndex` | int | Week in program |

### `PlannedSet`

| Field | Type | Description |
|-------|------|-------------|
| `plannedWorkoutId` | string | Planned workout reference |
| `exerciseId` | string | Exercise reference |
| `targetReps` | int | Target reps |
| `targetWeight` | float | Target weight |
| `targetRPE` | float | Target RPE |
| `orderInWorkout` | int | Order in workout |

## 6.9 Optional Aggregation Tables

For performance if charts/reports get slow:

- `ExerciseMonthlyStats(exerciseId, month, totalVolume, maxE1RM)`
- `MuscleGroupWeeklyLoad(muscleGroup, week, totalVolume)`

---

# 7. PR Pipeline & Key Queries

## 7.1 Table Usage: PerformanceRecord vs Set

**Critical principle:** Use `PerformanceRecord` for all normal PR operations. Only query `Set` table when recomputing after PR deletion/edit.

| Operation | Table Used | Query Scope |
|-----------|------------|-------------|
| Check if new set is a PR | `PerformanceRecord` | 1 row lookup |
| Display "Your 5-rep PR is 100kg" | `PerformanceRecord` | 1 row lookup |
| Display PR table for exercise | `PerformanceRecord` | ~50 rows max |
| Get old PR set to update status | `Set` | 1 row by setId |
| Find new PR after deletion | `Set` | Indexed query (rare) |

**Rationale:** `PerformanceRecord` is small and indexed. Querying it is O(1). Querying `Set` table should only happen in rare cases (PR owner deleted/edited).

## 7.2 PR Pipeline — Complete Logic

### On New Set Saved

```
1. ELIGIBILITY CHECK
   If NOT set.hasData → cachedPRStatus = null, DONE
   If set.excludeFromPRs → cachedPRStatus = null, DONE
   If set.setType IN ('warmup', 'partial') AND settings exclude these → cachedPRStatus = null, DONE

2. LOOKUP CURRENT PR
   Query: SELECT value, setId FROM PerformanceRecord 
          WHERE exerciseId = ? AND recordType = 'repMax' AND reps = ?
   
3. IF NO EXISTING PR (first set for this exercise/reps):
   → INSERT into PerformanceRecord (exerciseId, recordType='repMax', reps, value=effectiveWeight, setId, date)
   → set.cachedPRStatus = "current"
   → DONE
   
4. IF NEW SET BEATS EXISTING PR (set.effectiveWeight > existingValue):
   → Fetch old PR set by setId from PerformanceRecord
   → oldSet.cachedPRStatus = "previous"
   → UPDATE PerformanceRecord SET value = ?, setId = ?, date = ?
   → set.cachedPRStatus = "current"
   → DONE
   
5. IF NEW SET MATCHES EXISTING PR (set.effectiveWeight == existingValue):
   → Check: Is set in same workout as PR-owning set?
   → If same workout: set.cachedPRStatus = null (UI won't show badge)
   → If different workout: set.cachedPRStatus = "matched"
   → Do NOT update PerformanceRecord (earliest wins)
   → DONE
   
6. IF NEW SET IS BELOW PR (set.effectiveWeight < existingValue):
   → set.cachedPRStatus = null
   → DONE
```

### On Set Edited

```
1. IF set.cachedPRStatus != "current":
   → Re-run "New Set Saved" logic with new values
   → DONE
   
2. IF set WAS the PR owner (cachedPRStatus == "current"):
   a. Fetch current PerformanceRecord for this exercise/reps
   b. IF edited effectiveWeight >= PerformanceRecord.value:
      → Just update PerformanceRecord with new value
      → DONE
   c. IF edited effectiveWeight < PerformanceRecord.value:
      → Need to find new PR owner
      → Query Set table (indexed):
        SELECT id, effectiveWeight FROM Set 
        WHERE exerciseId = ? AND reps = ? 
          AND hasData = true AND excludeFromPRs = false
        ORDER BY effectiveWeight DESC, date ASC
        LIMIT 1
      → IF found and winner != this set:
        - UPDATE PerformanceRecord to point to winner
        - winner.cachedPRStatus = "current"
        - Re-evaluate this set (may be "previous", "matched", or null)
      → IF this set still wins (no other sets):
        - UPDATE PerformanceRecord with new lower value
        - Keep cachedPRStatus = "current"
```

### On Set Deleted

```
1. IF set.cachedPRStatus != "current":
   → Just delete the set, no PR changes needed
   → DONE
   
2. IF set WAS the PR owner (cachedPRStatus == "current"):
   → Query Set table to find new max:
     SELECT id, effectiveWeight FROM Set 
     WHERE exerciseId = ? AND reps = ? 
       AND hasData = true AND excludeFromPRs = false
       AND id != ? (exclude deleted set)
     ORDER BY effectiveWeight DESC, date ASC
     LIMIT 1
   → IF new winner found:
     - UPDATE PerformanceRecord to point to new winner
     - newWinner.cachedPRStatus = "current"
   → IF no sets remain:
     - DELETE FROM PerformanceRecord WHERE exerciseId = ? AND recordType = 'repMax' AND reps = ?
   → Delete the set
```

## 7.3 Same-Workout PR Matching Rule

When a set matches an existing PR (exact same weight and reps):
- **Store** `cachedPRStatus = "matched"` in the database
- **UI hides** the "Matched PR" badge if the set is in the same workout as the PR-owning set

This keeps data accurate (the match exists) while avoiding annoying badges for consecutive identical sets.

## 7.4 PR Table Display — Suffix-Max Filtering

When displaying the rep-max PR table, filter out "overwritten" records where a higher-rep PR has equal or greater weight.

**Algorithm:**
```
1. Fetch all PerformanceRecord rows for this exercise WHERE recordType = 'repMax'
2. Sort by reps DESCENDING (highest first)
3. Initialize maxWeightSeen = 0
4. Iterate from highest reps to lowest:
   - IF this row's value > maxWeightSeen:
     - SHOW this row (it's a true capability boundary)
     - maxWeightSeen = this row's value
   - ELSE:
     - HIDE this row (overwritten by higher-rep capability)
```

**Example:**

| Reps | Weight | maxWeightSeen | Show? |
|------|--------|---------------|-------|
| 12 | 90kg | 0 → 90 | ✅ Yes |
| 10 | 85kg | 90 | ❌ No (85 < 90) |
| 8 | 95kg | 90 → 95 | ✅ Yes |
| 5 | 100kg | 95 → 100 | ✅ Yes |
| 3 | 110kg | 100 → 110 | ✅ Yes |
| 1 | 120kg | 110 → 120 | ✅ Yes |

The 10-rep "85kg" is hidden because the 12-rep at 90kg proves the user can do 90kg for 10 reps.

## 7.5 Rep Dominance Query

To answer "what's the best weight for ≤ R reps?" (used in some analytics):

```sql
SELECT MAX(value) FROM PerformanceRecord
WHERE exerciseId = ? AND recordType = 'repMax' AND reps >= X;
```

## 7.6 Database Indexes for PR Queries

Required indexes for fast PR operations:

```sql
-- Fast PR lookup
CREATE INDEX idx_performance_record ON PerformanceRecord(exerciseId, recordType, reps);

-- Fast Set queries when recomputing PR (rare but must be fast)
CREATE INDEX idx_set_pr_lookup ON Set(exerciseId, reps, effectiveWeight DESC, date ASC);
```

---

# 8. Implementation Contracts

## 8.1 Volume Calculation

**Definition:** `volume = effectiveWeight × reps`

**Scope:**
- Applies only to weight-based exercises (`trackingType` includes `weight`)
- Uses `effectiveWeight` (which includes bodyweight contribution) for accurate cross-exercise comparison
- Duration-based and distance-based exercises have **no volume concept** for now
- Partial sets are **excluded** from volume calculations
- Warmup sets are excluded by default (configurable via settings)

## 8.2 Units Policy

| Dimension | Base Unit | Notes |
|-----------|-----------|-------|
| Weight | kg | Convert in UI |
| Distance | meters | Convert in UI |
| Duration | seconds | Convert in UI |

**Rationale:** Avoids aggregation problems; consistent storage.

## 8.3 Float Comparison Policy

**Decision:** Convert weights to integer grams for all PR comparisons.

```swift
// Convert kg float to integer grams for comparison
func toGrams(_ kg: Double) -> Int {
    return Int(round(kg * 1000))
}

// PR comparison
let isNewPR = toGrams(newSet.effectiveWeight) > toGrams(existingPR.value)
let isMatch = toGrams(newSet.effectiveWeight) == toGrams(existingPR.value)
```

**Why not epsilon?** Epsilon (e.g., 0.001) can still produce edge cases. Integer grams are deterministic — 100.0kg and 100.0001kg both become 100000 grams, producing consistent equality.

**Storage:** Continue storing as float kg (human-readable). Convert to grams only for comparison logic.

## 8.4 Write-Time vs Read-Time

| Operation | Timing | Rationale |
|-----------|--------|-----------|
| PR updates | Write-time | Keep screens instant |
| Stats aggregates | Write-time | Avoid scanning history |
| Per-set volume | Read-time | Cheap; no storage needed |
| Rep dominance | Read-time | Single query from sparse table |

## 8.5 Background Processing

- PR pipeline runs on background queue/context
- UI may show optimistic PRs immediately
- Persistence happens in background
- Avoids blocking main thread

## 8.6 Database Aggregation Over Iteration

**Critical principle:** Let the database do aggregation work. Do not load large collections into code to iterate.

```swift
// ❌ BAD: Load sets, iterate in code
let sets = fetchAllSets(for: exerciseId)  // Loads 500 sets into memory
var total = 0.0
for set in sets {
    total += set.weight * Double(set.reps)  // Memory + CPU intensive
}

// ✅ GOOD: Let database aggregate
let total = fetchTotalVolume(for: exerciseId)
// SQL: SELECT SUM(weight * reps) FROM Set WHERE exerciseId = ?
// Returns single number, no iteration

// ✅ BEST: Use pre-computed value
let stats = fetchExerciseStats(for: exerciseId)
let total = stats.totalVolume  // Already computed at write-time
```

**When iteration is acceptable:**
- Displaying a paginated list of sets (load only visible page)
- Building charts with per-set data points (load specific date range)
- One-time migrations or data repairs

**When iteration is NOT acceptable:**
- Computing totals, averages, or maximums (use SQL aggregation or pre-computed stats)
- Checking PR status (use PerformanceRecord lookup)
- Any operation that runs frequently

## 8.7 No Startup Index Rebuild

**Critical principle:** The app should NOT rebuild indexes or caches at startup.

`PerformanceRecord` and `ExerciseStats` are your persistent indexes. They're updated at write-time and always current. At startup:
- Do NOT scan all sets to rebuild PR indexes
- Do NOT load all workouts into memory dictionaries
- Do NOT pre-compute stats that are already stored

**When rebuild IS needed:**
- Data migration (changed PR logic)
- Database corruption recovery
- Import from external source

These are rare maintenance operations, not startup tasks. Provide an explicit "Rebuild Stats" action in settings for these cases.

## 8.8 Memory Management — What Lives Where

**ALWAYS in Database (never load entirely into RAM):**

| Table | Reason |
|-------|--------|
| `Set` | Potentially 10,000+ rows. Query what you need. |
| `Workout` | Hundreds/thousands of rows. Query by date range. |
| `PerformanceRecord` | Query per exercise, don't load all. |
| `ExerciseStats` | Query per exercise, don't load all. |
| `BodyweightEntry` | Query by date range when needed. |

**In Memory ONLY when actively displayed:**

| Data | When loaded | When released |
|------|-------------|---------------|
| Current workout's sets | Workout screen opens | Workout screen closes |
| Exercise history sets | Viewing exercise detail | Navigating away |
| Chart data points | Chart is displayed | Leaving chart screen |
| PR table for one exercise | Viewing records | Navigating away |

**In Memory for session (small, bounded):**

| Data | Typical Size | Reason |
|------|--------------|--------|
| Exercise name list (autocomplete) | ~200 strings | Fast autocomplete, small footprint |
| User settings | 1 object | Accessed constantly |
| Active workout state | 1 workout + sets | Currently being edited |

**NEVER as global in-memory cache:**

| Anti-pattern | Why Bad |
|--------------|---------|
| All workouts in dictionary | Unbounded growth, duplicates database |
| All exercises with all sets | Massive memory, stale data risk |
| All PRs for all exercises | Query per exercise instead |

## 8.9 Anti-Pattern: Multi-Layer Read Caches

**Symptom:** You find yourself building multiple cache layers with different TTLs (1 minute, 5 minutes, session-long, persistent).

**Root cause:** Computing too much at read-time, requiring caches to avoid repeated computation.

**Solution:** Compute at write-time instead. When a set is saved:
- PR tables are updated
- ExerciseStats are updated
- Data is always fresh

Reads become simple fetches from pre-computed tables. No cache invalidation complexity.

**Rule of thumb:** If a value is displayed frequently but changes rarely (PRs, totals, stats), compute it at write-time and store it.

## 8.10 Chart Performance Strategy

Charts that require time-series data (e.g., e1RM trend over time) may need to query historical sets.

**For v1:**
- Lazy compute on first access
- Cache result for session duration (in-memory while chart is displayed)
- Query only the date range needed, not all history

**If performance is insufficient:**
- Consider pre-aggregated weekly/monthly tables (see Section 11.1)
- Do NOT add background warming at launch unless lazy compute proves too slow in practice

**Charts should not impact normal app operation.** PR checks, set saving, and workout logging should all be fast regardless of chart data.

---

# 9. User Settings

User-configurable options that affect calculations and behavior.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `includeWarmupsInVolume` | bool | `false` | Whether warmup sets contribute to session/total volume calculations |
| `includeWarmupsInPRs` | bool | `false` | Whether warmup sets are eligible for PR consideration |

**Implementation note:** These settings are checked at calculation time. Changing a setting may require recalculation of affected stats.

---

# 10. Explicit Non-Decisions (Deferred)

These choices are **intentionally left open** and do not block implementation. They can be decided later without schema changes.

| Topic | Options | Notes |
|-------|---------|-------|
| Incremental vs full rebuild on edit/delete | Incremental preferred if cheap; full rebuild as fallback | Performance vs simplicity tradeoff |
| Non-rep PR types to persist | `repMax` confirmed; `e1RM`, `maxVolume` TBD | `maxSessionVolume` in `ExerciseStats` |
| `e1RMFormulaVersion` per set | Optional field exists; usage TBD | Enables selective recompute |
| Optimistic vs confirmed UI PR updates | UI behavior choice | UX decision |
| Rest timer superset logic | Algorithm for computing rest time in superset scenarios | Not yet implemented |
| e1RM formula selection | Which formula to use (Epley, Brzycki, etc.) | Decide before implementation |
| RPE ↔ RIR conversion formula | Keep as independent variables initially | May add conversion later |

**Meta-rule:** Decisions above can be made later without schema changes; the model is intentionally permissive about caching derived values because it keeps reads fast and correctness is preserved by rebuildability.

---

# 11. Architecture Decisions Pending

Larger structural decisions that require more analysis before implementation. These are **not** small implementation details — they affect system architecture.

## 11.1 Time-Series Aggregation Strategy

**Context:** Current dataset has 12,000+ sets. Chart queries include e1RM trends over all time, volume per week, volume per muscle group.

**Problem:** Scanning raw sets for every chart render will become slow as data grows.

**Options under consideration:**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| Pre-aggregated tables | `ExerciseWeeklyStats`, `ExerciseMonthlyStats`, `MuscleGroupWeeklyVolume` updated at write-time | Fast reads, predictable performance | More write complexity, storage overhead |
| Materialized views | Database-level aggregation, scheduled refresh | Clean separation, database handles optimization | Refresh latency, database-specific |
| Query optimization only | Indexes, query tuning, no aggregation tables | Simpler schema, no sync issues | May hit performance ceiling |
| Hybrid approach | Aggregate only high-frequency queries, compute others on demand | Balanced complexity | More decisions needed |

**Suggested pre-aggregated tables (if chosen):**

| Table | Grain | Key Fields |
|-------|-------|------------|
| `ExerciseWeeklyStats` | Per exercise, per week | `exerciseId`, `weekStart`, `totalVolume`, `maxWeight`, `maxE1RM`, `setCount` |
| `ExerciseMonthlyStats` | Per exercise, per month | Same as above but monthly |
| `MuscleGroupWeeklyVolume` | Per muscle group, per week | `muscleGroup`, `weekStart`, `totalVolume` |

**Decision needed before:** Chart/analytics feature implementation

## 11.2 Memory Management Strategy

**Context:** Similar apps have suffered from memory bloat by caching too much in RAM. This impacts performance and battery life on mobile devices.

**Current guidance (Section 8.8):** Provides principles for what should and shouldn't be in memory. This guidance should be evaluated during implementation.

**Questions to resolve:**

| Question | Considerations |
|----------|----------------|
| Exercise name autocomplete | Is ~200 strings acceptable? Could use database LIKE query instead? |
| Active workout state | How much memory does a workout with 20 exercises and 100 sets consume? |
| Chart data caching | Session-scoped cache vs. re-query on each view? |
| SwiftData/ORM behavior | Does the ORM cache aggressively? Do we need to manage this? |

**Validation approach:**
1. Implement with current guidance
2. Profile memory usage with realistic dataset (10,000+ sets)
3. Identify hotspots
4. Adjust strategy based on evidence

**Decision needed before:** Performance testing phase

---

# Appendix A: Enumeration Values

## `trackingType`

| Value | Dimensions | Example |
|-------|------------|---------|
| `WEIGHT_REPS` | weight, reps | Barbell squat |
| `DURATION` | durationSeconds | Plank |
| `WEIGHT_DISTANCE` | weight, distanceMeters | Sled push |
| `WEIGHT_REPS_DURATION` | weight, reps, durationSeconds | AMRAP |
| `CUSTOM` | TBD | Future expansion |

## `equipmentType`

- `barbell`
- `dumbbell`
- `machine_plate`
- `machine_pin`
- `bodyweight`
- `sled`
- `cable`
- `kettlebell`
- `band`
- `other`

## `setType`

- `warmup`
- `working`
- `partial`
- `dropset`
- `restpause`
- `cluster`
- `myo`
- `amrap`
- `backoff`
- `failure`
- `tempo`
- `isometric`
- `eccentric`

## `side`

- `left`
- `right`
- `both`

## `movementPattern`

- `hinge`
- `squat`
- `press`
- `pull`
- `carry`
- `rotation`
- `other`

## `recordType` (PerformanceRecord.recordType)

- `repMax` — Best weight for specific rep count
- `e1RM` — Best estimated 1RM
- `maxVolume` — Best session volume

## `cachedPRStatus` (Set.cachedPRStatus)

- `current` — This set IS the current PR
- `matched` — This set equals the PR but wasn't first
- `previous` — This set WAS a PR but has been beaten
- `null` — Not a PR

---

# Appendix B: Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | January 2026 | Initial consolidated specification |
| 1.1 | January 2026 | Added: `HealthProfile` table, `bodyweightContribution` field, expanded set types, `startedAt`/`completedAt` timestamps, `createdAt`/`updatedAt` audit fields, User Settings section, Architecture Decisions Pending section. Resolved: partial sets excluded from PRs/volume, `trackingType` immutable once sets exist, bilateral load factor for analytics only, volume = weight × reps (weight-based only), hard delete (no soft delete). |
| 1.2 | January 2026 | Added: `hasData` concept (Section 1.2), `cachedPRStatus` field on Set, target fields on Set (`targetWeight`, `targetRepMin`, `targetRepMax`, `targetRPE`, `targetRIR`), comprehensive PR pipeline logic (Section 7), suffix-max PR display filtering, same-workout matching rule, database aggregation guidance (Section 8.6), no startup rebuild principle (Section 8.7), memory management guidance (Section 8.8), anti-pattern documentation (Section 8.9), chart performance strategy (Section 8.10), memory management architecture consideration (Section 11.2). |
| 1.3 | January 2026 | **Breaking schema changes:** Replaced `bodyweightContribution: bool` with `bodyweightFactor: float` (0.0–1.0) on Exercise. Added `effectiveWeight` field on Set (calculated at save time: `weight + bodyweight × factor`). Merged `ExercisePR` + `ExerciseRepPR` into single `PerformanceRecord` table. Updated PR pipeline to use `effectiveWeight` for comparisons. Added integer grams comparison policy (Section 8.3). Updated volume calculation to use `effectiveWeight × reps`. |

---

*End of Document*
