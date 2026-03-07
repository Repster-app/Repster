---
work_package_id: "WP02"
title: "SwiftData Models (All 11 @Model Classes)"
lane: "done"
dependencies: ["WP01"]
subtasks: ["T012", "T013", "T014", "T015", "T016", "T017", "T018", "T019", "T020", "T021", "T022"]
agent: "claude-opus"
shell_pid: "56520"
reviewed_by: "Magnus Espensen"
review_status: "approved"
history:
  - date: "2026-02-19"
    action: "created"
    by: "spec-kitty.tasks"
---

# WP02: SwiftData Models (All 11 @Model Classes)

**Implementation command**: `spec-kitty implement WP02 --base WP01`

## Objective

Implement all 11 SwiftData @Model classes with exact field names, types, nullability, defaults, and computed properties per specdoc Section 6 and plan.md Phase 1. These models are the data layer foundation that every service, repository, and screen will build upon.

## Context

- **Framework**: SwiftData (import SwiftData, use @Model macro)
- **Relationships**: UUID foreign keys only (no @Relationship annotations in v1 per plan decision)
- **Units**: All weight in kg (Double), distance in meters (Double), duration in seconds (Int)
- **IDs**: All models use UUID primary keys
- **Timestamps**: All models have createdAt and updatedAt (Date) - except Program sub-models (ProgramExercise, PlannedWorkout, PlannedSet) which may omit them per specdoc
- **Naming**: The set model is `WorkoutSet` (not `Set`) to avoid Swift.Set collision
- **Enums**: All enum types from WP01 are used as stored properties (String raw-value Codable)
- **Computed properties**: `hasData` and `volume` on WorkoutSet are NOT stored

## Reference Documents

- `kitty-specs/001-xcode-project-swiftdata-models/plan.md` - Complete field listings for all 11 models
- `kitty-specs/001-xcode-project-swiftdata-models/spec.md` - Acceptance scenarios and success criteria
- `.kittify/memory/constitution.md` - Data model principles (units, naming, hasData rules)

---

## Subtasks

### T012: Create WorkoutSet Model

**Purpose**: The atomic performance record - the most important model. Named WorkoutSet to avoid Swift.Set collision.

**File**: `Reppo/Data/Models/WorkoutSet.swift`

**Implementation**:

```swift
import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var id: UUID
    var workoutId: UUID
    var exerciseId: UUID
    var date: Date
    var startedAt: Date?
    var completedAt: Date?
    var weight: Double?
    var effectiveWeight: Double?
    var reps: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var e1RM: Double?
    var e1RMFormulaVersion: String?
    var rpe: Double?
    var rir: Double?
    var setType: SetType
    var pauseDuration: Int?
    var side: Side?
    var notes: String?
    var orderInWorkout: Int
    var orderInExercise: Int
    var supersetGroupId: UUID?
    var completed: Bool
    var excludeFromPRs: Bool?
    var cachedPRStatus: CachedPRStatus?
    var targetWeight: Double?
    var targetRepMin: Int?
    var targetRepMax: Int?
    var targetRPE: Double?
    var targetRIR: Int?
    var createdAt: Date
    var updatedAt: Date

    // COMPUTED - not stored in SwiftData
    var hasData: Bool {
        ((weight ?? 0) > 0 && (reps ?? 0) > 0) ||
        (durationSeconds ?? 0) > 0 ||
        (distanceMeters ?? 0) > 0
    }

    var volume: Double? {
        guard let ew = effectiveWeight, let r = reps, r > 0 else { return nil }
        return ew * Double(r)
    }

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        exerciseId: UUID,
        date: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        weight: Double? = nil,
        effectiveWeight: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        e1RM: Double? = nil,
        e1RMFormulaVersion: String? = nil,
        rpe: Double? = nil,
        rir: Double? = nil,
        setType: SetType = .working,
        pauseDuration: Int? = nil,
        side: Side? = nil,
        notes: String? = nil,
        orderInWorkout: Int,
        orderInExercise: Int,
        supersetGroupId: UUID? = nil,
        completed: Bool = false,
        excludeFromPRs: Bool? = nil,
        cachedPRStatus: CachedPRStatus? = nil,
        targetWeight: Double? = nil,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        targetRPE: Double? = nil,
        targetRIR: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.date = date
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.weight = weight
        self.effectiveWeight = effectiveWeight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.e1RM = e1RM
        self.e1RMFormulaVersion = e1RMFormulaVersion
        self.rpe = rpe
        self.rir = rir
        self.setType = setType
        self.pauseDuration = pauseDuration
        self.side = side
        self.notes = notes
        self.orderInWorkout = orderInWorkout
        self.orderInExercise = orderInExercise
        self.supersetGroupId = supersetGroupId
        self.completed = completed
        self.excludeFromPRs = excludeFromPRs
        self.cachedPRStatus = cachedPRStatus
        self.targetWeight = targetWeight
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.targetRPE = targetRPE
        self.targetRIR = targetRIR
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

**Critical rules**:
- `hasData` MUST be computed, NOT stored (constitution principle)
- `volume` uses `effectiveWeight`, NOT raw `weight` (constitution principle)
- All weight fields are kg (Double), duration is seconds (Int), distance is meters (Double)
- `setType` defaults to `.working`
- `completed` defaults to `false`

**Validation**:
- [ ] 28+ stored fields with correct types and nullability
- [ ] `hasData` is computed property matching specdoc Section 1.2 logic
- [ ] `volume` uses effectiveWeight (not weight)
- [ ] All weight in kg, duration in seconds, distance in meters
- [ ] init has sensible defaults (setType: .working, completed: false)

---

### T013: Create Workout Model

**Purpose**: Session container with lifecycle status.

**File**: `Reppo/Data/Models/Workout.swift`

**Fields**:
- `id`: UUID
- `date`: Date
- `startTime`: Date?
- `endTime`: Date?
- `duration`: Int? (seconds)
- `perceivedEffort`: Double?
- `notes`: String?
- `programId`: UUID?
- `status`: WorkoutStatus (default: .inProgress)
- `createdAt`: Date
- `updatedAt`: Date

**Critical rules**:
- `status` defaults to `.inProgress` per AGENT_RULES Section 7.3
- `duration` is in seconds (Int)
- "Finish Workout" is a UI action that flips status to `.completed` and sets `endTime`

**Validation**:
- [ ] All 11 fields present with correct types
- [ ] `status` field uses WorkoutStatus enum with default `.inProgress`
- [ ] `duration` is Int (seconds)

---

### T014: Create Exercise Model

**Purpose**: Exercise metadata defining tracking and interpretation.

**File**: `Reppo/Data/Models/Exercise.swift`

**Fields**:
- `id`: UUID
- `name`: String
- `equipmentType`: EquipmentType
- `trackingType`: TrackingType (IMMUTABLE once sets exist - enforced in service layer, NOT here)
- `primaryMuscle`: String?
- `secondaryMuscles`: [String] (SwiftData handles arrays of Codable natively)
- `movementPattern`: MovementPattern?
- `unilateral`: Bool (default: false)
- `bilateralLoadFactor`: Double?
- `bodyweightFactor`: Double (default: 0.0, range 0.0-1.0)
- `weightIncrement`: Double?
- `defaultRestTime`: Int? (seconds)
- `createdAt`: Date
- `updatedAt`: Date

**Critical rules**:
- `trackingType` immutability is NOT enforced at the model level (enforced in ExerciseService/Repository later)
- `secondaryMuscles` as `[String]` is natively supported by SwiftData
- `bodyweightFactor` defaults to 0.0 (no bodyweight component)

**Validation**:
- [ ] All 14 fields with correct types
- [ ] `secondaryMuscles` is `[String]` with default `[]`
- [ ] `bodyweightFactor` defaults to 0.0
- [ ] `unilateral` defaults to false

---

### T015: Create ExerciseStats Model

**Purpose**: Per-exercise rebuildable aggregate cache.

**File**: `Reppo/Data/Models/ExerciseStats.swift`

**Fields**:
- `id`: UUID
- `exerciseId`: UUID
- `totalWorkouts`: Int
- `totalSets`: Int
- `totalReps`: Int
- `totalVolume`: Double
- `maxWeight`: Double
- `bestE1RM`: Double
- `averageIntensity`: Double
- `estimated1RMTrendSlope`: Double
- `lastPRDate`: Date?
- `lastPerformedDate`: Date?
- `maxSessionVolume`: Double
- `createdAt`: Date
- `updatedAt`: Date

**Critical rules**:
- This is a rebuildable cache - all values can be recomputed from raw WorkoutSet data
- Updated at write-time by StatsService (feature 004), never at read-time
- Numeric fields default to 0

**Validation**:
- [ ] All 14 fields with correct types
- [ ] Numeric fields (totalWorkouts, totalSets, etc.) default to 0
- [ ] Date fields (lastPRDate, lastPerformedDate) are optional

---

### T016: Create PerformanceRecord Model

**Purpose**: Unified PR table for all record types.

**File**: `Reppo/Data/Models/PerformanceRecord.swift`

**Fields**:
- `id`: UUID
- `exerciseId`: UUID
- `recordType`: RecordType
- `reps`: Int? (null for e1RM and maxVolume, populated for repMax)
- `value`: Double (the record value - weight in kg for repMax, calculated e1RM, or volume)
- `setId`: UUID (the set that owns this PR)
- `date`: Date
- `createdAt`: Date
- `updatedAt`: Date

**Critical rules**:
- Uniqueness on (exerciseId, recordType, reps) enforced in SERVICE LAYER, not model
- Single table for all PR types (repMax, e1RM, maxVolume) - no separate tables
- `reps` is null for e1RM and maxVolume record types

**Validation**:
- [ ] All 9 fields with correct types
- [ ] `reps` is optional (Int?)
- [ ] `value` is non-optional Double
- [ ] No uniqueness constraints at model level

---

### T017: Create BodyweightEntry Model

**Purpose**: Bodyweight history for effectiveWeight calculations.

**File**: `Reppo/Data/Models/BodyweightEntry.swift`

**Fields**:
- `id`: UUID
- `healthProfileId`: UUID
- `date`: Date
- `bodyweightKg`: Double (always kg, never lbs)
- `createdAt`: Date
- `updatedAt`: Date

**Critical rules**:
- `bodyweightKg` is always stored in kg - convert to lbs in UI only
- Used by SetService to compute effectiveWeight at save time

**Validation**:
- [ ] All 6 fields with correct types
- [ ] Field named `bodyweightKg` (explicit unit in name)
- [ ] No imperial unit fields

---

### T018: Create HealthProfile Model

**Purpose**: Single-row local user profile with settings.

**File**: `Reppo/Data/Models/HealthProfile.swift`

**Fields**:
- `id`: UUID
- `unitPreference`: UnitPreference (default: .metric)
- `includeWarmupsInVolume`: Bool (default: false)
- `includeWarmupsInPRs`: Bool (default: false)
- `e1RMFormula`: String (default: "epley")
- `createdAt`: Date
- `updatedAt`: Date

**Critical rules**:
- Settings fields from AGENT_RULES Section 8
- `unitPreference` only affects display, never storage
- `e1RMFormula` as String allows future formula additions

**Validation**:
- [ ] All 7 fields with correct types and defaults
- [ ] `unitPreference` defaults to `.metric`
- [ ] Both `includeWarmupsIn*` default to false
- [ ] `e1RMFormula` defaults to "epley"

---

### T019: Create Program Model

**Purpose**: Training program container.

**File**: `Reppo/Data/Models/Program.swift`

**Fields**:
- `id`: UUID
- `name`: String
- `progressionModel`: String?
- `deloadRules`: String?
- `autoRegulationEnabled`: Bool (default: false)
- `createdAt`: Date
- `updatedAt`: Date

**Validation**:
- [ ] All 7 fields with correct types
- [ ] `autoRegulationEnabled` defaults to false

---

### T020: Create ProgramExercise Model

**Purpose**: Exercise configuration within a program.

**File**: `Reppo/Data/Models/ProgramExercise.swift`

**Fields**:
- `id`: UUID
- `programId`: UUID
- `exerciseId`: UUID
- `targetRepRange`: String?
- `intensityRule`: String?
- `minIncrement`: Double?
- `maxIncrement`: Double?

**Note**: No createdAt/updatedAt per specdoc Section 6.8 (program sub-entities).

**Validation**:
- [ ] All 7 fields (no timestamps per plan)
- [ ] Foreign keys: programId, exerciseId

---

### T021: Create PlannedWorkout Model

**Purpose**: Scheduled workout within a program.

**File**: `Reppo/Data/Models/PlannedWorkout.swift`

**Fields**:
- `id`: UUID
- `programId`: UUID
- `scheduledDate`: Date?
- `weekIndex`: Int?

**Note**: No createdAt/updatedAt per specdoc Section 6.8.

**Validation**:
- [ ] All 4 fields (no timestamps per plan)
- [ ] Both scheduledDate and weekIndex are optional

---

### T022: Create PlannedSet Model

**Purpose**: Planned set within a planned workout.

**File**: `Reppo/Data/Models/PlannedSet.swift`

**Fields**:
- `id`: UUID
- `plannedWorkoutId`: UUID
- `exerciseId`: UUID
- `targetReps`: Int?
- `targetWeight`: Double? (kg)
- `targetRPE`: Double?
- `orderInWorkout`: Int?

**Note**: No createdAt/updatedAt per specdoc Section 6.8.

**Validation**:
- [ ] All 7 fields (no timestamps per plan)
- [ ] `targetWeight` in kg (Double)

---

## Definition of Done

- [ ] All 11 @Model classes exist in `Reppo/Data/Models/`
- [ ] Every model uses `@Model` macro with `import SwiftData`
- [ ] Every model has UUID `id` field
- [ ] Models with timestamps have both `createdAt` and `updatedAt`
- [ ] All weight fields store kg (Double), duration in seconds (Int), distance in meters (Double)
- [ ] WorkoutSet has computed `hasData` and `volume` properties (not stored)
- [ ] WorkoutSet.hasData matches specdoc Section 1.2 logic exactly
- [ ] No @Relationship annotations (UUID foreign keys only)
- [ ] No fields not in specdoc Section 6 (except status on Workout, settings on HealthProfile per AGENT_RULES)
- [ ] All models compile with zero errors when combined with WP01 enums
- [ ] Every init() has sensible default values where applicable

## Risks

| Risk | Mitigation |
|------|-----------|
| WorkoutSet field count (28+) is error-prone | Copy exact field list from plan.md, verify count |
| Optional vs non-optional mismatch | Follow plan.md nullability exactly (? suffix) |
| hasData logic error | Test mentally: weight=0,reps=0,dur=0 -> false; weight=5,reps=3 -> true; dur=30 -> true |
| SwiftData enum storage | All enums are String raw-value Codable (handled in WP01) |

## Reviewer Guidance

1. **Count fields**: WorkoutSet(28+2 computed), Workout(11), Exercise(14), ExerciseStats(14), PerformanceRecord(9), BodyweightEntry(6), HealthProfile(7), Program(7), ProgramExercise(7), PlannedWorkout(4), PlannedSet(7)
2. **Check hasData logic**: Must match `((weight ?? 0) > 0 && (reps ?? 0) > 0) || (durationSeconds ?? 0) > 0 || (distanceMeters ?? 0) > 0`
3. **Check volume**: Must use `effectiveWeight` not `weight`
4. **Check units**: No lbs, no feet, no minutes - only kg, meters, seconds
5. **Check naming**: WorkoutSet (not Set), bodyweightKg (not bodyweight)
6. **Check no extras**: No fields invented beyond specdoc + AGENT_RULES additions

## Activity Log

- 2026-02-20T17:23:07Z – claude-opus – shell_pid=54520 – lane=doing – Started implementation via workflow command
- 2026-02-20T17:28:00Z – claude-opus – shell_pid=54520 – lane=for_review – Ready for review: All 11 SwiftData @Model classes implemented with correct fields, types, nullability, defaults, and computed properties per specdoc Section 6 and plan.md. ProgramExercise/PlannedWorkout/PlannedSet include createdAt/updatedAt per FR-014 remediation. hasData matches specdoc 1.2, volume uses effectiveWeight. Build succeeds with zero errors and zero warnings.
- 2026-02-20T17:28:41Z – claude-opus – shell_pid=56520 – lane=doing – Started review via workflow command
- 2026-02-20T17:29:37Z – claude-opus – shell_pid=56520 – lane=done – Review passed: All 11 @Model classes verified. Field counts correct (WorkoutSet 32 stored + 2 computed, all others match plan). hasData logic matches specdoc 1.2 exactly. volume uses effectiveWeight (not weight). All units metric (kg/meters/seconds), no imperial. No @Relationship annotations — UUID foreign keys throughout. ProgramExercise/PlannedWorkout/PlannedSet include createdAt/updatedAt per FR-014 remediation. No invented fields. WP01 dependency confirmed done. Build succeeded.
