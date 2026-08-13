import Foundation

/// Complete value-type mirror of `WorkoutSet`.
///
/// Carries *every* stored property rather than only the fields today's callers happen to read —
/// the same rule `ChartExerciseData` follows, and for the same reason: one snapshot type per
/// entity means one `init(from:)` to keep in sync, and a drift guard that *names* the property
/// when the model gains a field. A second, narrower set snapshot would be free to drift, which is
/// exactly how the RIR column silently blanked during Stage 1.
///
/// Two stored properties on `WorkoutSet` are deliberately **not** mirrored by name, both handled
/// explicitly by the drift guard rather than by omission:
///
///  - `cachedPRStatusRaw` is mirrored as the decoded `prStatus`, matching how every caller reads
///    it. `WorkoutSet.prStatus` is the computed accessor over the same storage.
///  - `cachedPRStatus` is a legacy persisted enum kept only for schema compatibility. Its own
///    declaration says app logic must never read it, so mirroring it would mean doing the one
///    thing the model forbids.
struct ChartSetData: Sendable, Equatable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let date: Date
    let startedAt: Date?
    let completedAt: Date?
    let weight: Double?
    let effectiveWeight: Double?
    let reps: Int?
    let prReps: Int
    let totalReps: Int
    let leftReps: Int?
    let rightReps: Int?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let e1RM: Double?
    let e1RMFormulaVersion: String?
    let rpe: Double?
    let rir: Double?
    let leftRIR: Double?
    let rightRIR: Double?
    let setType: SetType
    let pauseDuration: Int?
    let side: Side?
    let notes: String?
    let orderInWorkout: Int
    let orderInExercise: Int
    let supersetGroupId: UUID?
    let completed: Bool
    let excludeFromPRs: Bool
    let prStatus: CachedPRStatus?
    let targetWeight: Double?
    let targetRepMin: Int?
    let targetRepMax: Int?
    let overrideTargetRepMin: Int?
    let overrideTargetRepMax: Int?
    let targetRPE: Double?
    let targetRIR: Int?
    let createdAt: Date
    let updatedAt: Date
    let restDurationSeconds: Int?

    var hasData: Bool {
        ((weight ?? 0) > 0 && prReps > 0) ||
        totalReps > 0 ||
        (durationSeconds ?? 0) > 0 ||
        (distanceMeters ?? 0) > 0
    }

    var volume: Double? {
        guard let ew = effectiveWeight, totalReps > 0 else { return nil }
        return ew * Double(totalReps)
    }

    init(from set: WorkoutSet) {
        self.id = set.id
        self.workoutId = set.workoutId
        self.exerciseId = set.exerciseId
        self.date = set.date
        self.startedAt = set.startedAt
        self.completedAt = set.completedAt
        self.weight = set.weight
        self.effectiveWeight = set.effectiveWeight
        self.reps = set.reps
        self.prReps = set.prReps
        self.totalReps = set.totalReps
        self.leftReps = set.leftReps
        self.rightReps = set.rightReps
        self.durationSeconds = set.durationSeconds
        self.distanceMeters = set.distanceMeters
        self.e1RM = set.e1RM
        self.e1RMFormulaVersion = set.e1RMFormulaVersion
        self.rpe = set.rpe
        self.rir = set.rir
        self.leftRIR = set.leftRIR
        self.rightRIR = set.rightRIR
        self.setType = set.setType
        self.pauseDuration = set.pauseDuration
        self.side = set.side
        self.notes = set.notes
        self.orderInWorkout = set.orderInWorkout
        self.orderInExercise = set.orderInExercise
        self.supersetGroupId = set.supersetGroupId
        self.completed = set.completed
        self.excludeFromPRs = set.excludeFromPRs ?? false
        self.prStatus = set.prStatus
        self.targetWeight = set.targetWeight
        self.targetRepMin = set.targetRepMin
        self.targetRepMax = set.targetRepMax
        self.overrideTargetRepMin = set.overrideTargetRepMin
        self.overrideTargetRepMax = set.overrideTargetRepMax
        self.targetRPE = set.targetRPE
        self.targetRIR = set.targetRIR
        self.createdAt = set.createdAt
        self.updatedAt = set.updatedAt
        self.restDurationSeconds = set.restDurationSeconds
    }

    /// Mirrors `WorkoutSet.statsReps`.
    var statsReps: Int { totalReps }

    var hasNote: Bool {
        !(notes ?? "").isEmpty
    }

    // MARK: - Ported rep-target logic
    //
    // Same bodies as `WorkoutSet`'s. These are the rules `SetTableView` and `SetRowView` read
    // per row, so step 5 needs them on the value type — and duplicated *rules* are what caused
    // the Stage 1 RIR near-miss, so if either of these grows a condition, both must change.

    var overrideTargetRepRange: ClosedRange<Int>? {
        guard let overrideTargetRepMin,
              let overrideTargetRepMax,
              overrideTargetRepMin < overrideTargetRepMax else {
            return nil
        }
        return overrideTargetRepMin...overrideTargetRepMax
    }

    var hasOverrideRepTarget: Bool {
        overrideTargetRepMin != nil || overrideTargetRepMax != nil
    }

    var preferredTargetRepBounds: (min: Int?, max: Int?) {
        if hasOverrideRepTarget {
            return (overrideTargetRepMin, overrideTargetRepMax)
        }
        return (targetRepMin, targetRepMax)
    }
}

/// Complete value-type mirror of `Exercise`.
///
/// Deliberately carries *every* stored property rather than only the fields today's callers
/// happen to read. One snapshot type per entity means one `init(from:)` to keep in sync;
/// a second, narrower exercise snapshot would be free to drift from this one, which is
/// exactly how the RIR column silently blanked during Stage 1.
///
/// Every computed property below delegates to the same shared logic `Exercise` uses, so
/// the two cannot disagree.
struct ChartExerciseData: Sendable, Equatable {
    let id: UUID
    let name: String
    let equipmentType: EquipmentType
    let trackingType: TrackingType
    let primaryMuscle: String?
    let secondaryMuscles: [String]
    let movementPattern: MovementPattern?
    let unilateral: Bool
    let unilateralRepTargetModeRawValue: String?
    let bilateralLoadFactor: Double?
    let bodyweightFactor: Double
    let weightIncrement: Double?
    let defaultRestTime: Int?
    let fatigueRate: Double?
    let fatigueRateSourceRawValue: String?
    let recoveryConstant: Double?
    let fatigueLearningSessionCount: Int?
    let fatigueLearningCumulativeError: Double?
    let createdAt: Date
    let updatedAt: Date

    init(from exercise: Exercise) {
        self.id = exercise.id
        self.name = exercise.name
        self.equipmentType = exercise.equipmentType
        self.trackingType = exercise.trackingType
        self.primaryMuscle = exercise.primaryMuscle
        self.secondaryMuscles = exercise.secondaryMuscles
        self.movementPattern = exercise.movementPattern
        self.unilateral = exercise.unilateral
        self.unilateralRepTargetModeRawValue = exercise.unilateralRepTargetModeRawValue
        self.bilateralLoadFactor = exercise.bilateralLoadFactor
        self.bodyweightFactor = exercise.bodyweightFactor
        self.weightIncrement = exercise.weightIncrement
        self.defaultRestTime = exercise.defaultRestTime
        self.fatigueRate = exercise.fatigueRate
        self.fatigueRateSourceRawValue = exercise.fatigueRateSourceRawValue
        self.recoveryConstant = exercise.recoveryConstant
        self.fatigueLearningSessionCount = exercise.fatigueLearningSessionCount
        self.fatigueLearningCumulativeError = exercise.fatigueLearningCumulativeError
        self.createdAt = exercise.createdAt
        self.updatedAt = exercise.updatedAt
    }

    var isBodyweightStyleExercise: Bool {
        isBodyweightStyle(equipmentType: equipmentType, bodyweightFactor: bodyweightFactor)
    }

    var supportsUnilateralLogging: Bool {
        trackingType.supportsUnilateralLogging
    }

    var unilateralRepTargetMode: UnilateralRepTargetMode {
        UnilateralRepTargetMode.resolve(
            rawValue: unilateralRepTargetModeRawValue,
            exerciseName: name,
            unilateral: unilateral,
            trackingType: trackingType
        )
    }

    var usesTotalAcrossSidesRepTargets: Bool {
        unilateral && supportsUnilateralLogging && unilateralRepTargetMode == .totalAcrossSides
    }

    var resolvedFatigueRateSource: ExerciseFatigueRateSource? {
        ExerciseFatigueRateSource.resolve(
            rawValue: fatigueRateSourceRawValue,
            fatigueRate: fatigueRate,
            fatigueLearningSessionCount: fatigueLearningSessionCount
        )
    }
}

struct ChartExerciseStatsData: Sendable, Equatable {
    let exerciseId: UUID
    let lastPerformedDate: Date?

    init(from stats: ExerciseStats) {
        self.exerciseId = stats.exerciseId
        self.lastPerformedDate = stats.lastPerformedDate
    }
}

/// Snapshot of a `Workout` for read-only UI (Home, Copy Previous, Calendar, workout detail).
///
/// `displayTitle` is resolved here, inside the owning actor, so the main thread never
/// faults `title`/`startTime` back through a background `ModelContext`.
struct WorkoutSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let title: String?
    let displayTitle: String
    let startTime: Date?
    let endTime: Date?
    let duration: Int?
    let status: WorkoutStatus
    let createdAt: Date

    init(from workout: Workout) {
        self.id = workout.id
        self.date = workout.date
        self.title = workout.title
        self.displayTitle = workout.displayTitle
        self.startTime = workout.startTime
        self.endTime = workout.endTime
        self.duration = workout.duration
        self.status = workout.status
        self.createdAt = workout.createdAt
    }
}

/// Snapshot of a `PerformanceRecord` for the Home "Recent PRs" section.
struct PerformanceRecordSummaryData: Sendable, Equatable {
    let exerciseId: UUID
    let value: Double
    let reps: Int?
    let date: Date

    init(from record: PerformanceRecord) {
        self.exerciseId = record.exerciseId
        self.value = record.value
        self.reps = record.reps
        self.date = record.date
    }
}
