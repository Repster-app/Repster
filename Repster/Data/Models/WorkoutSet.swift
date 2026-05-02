import Foundation
import SwiftData

// iOS 18+: Add the following index macros at module scope when minimum target is raised:
// #Index<WorkoutSet>([\.exerciseId, \.reps, \.effectiveWeight, \.date])
// #Index<WorkoutSet>([\.workoutId])
// #Index<WorkoutSet>([\.exerciseId])

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
    var leftReps: Int?
    var rightReps: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var e1RM: Double?
    var e1RMFormulaVersion: String?
    var rpe: Double?
    var rir: Double?
    var leftRIR: Double?
    var rightRIR: Double?
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
    var overrideTargetRepMin: Int?
    var overrideTargetRepMax: Int?
    var targetRPE: Double?
    var targetRIR: Int?
    var createdAt: Date
    var updatedAt: Date
    /// Actual rest duration in seconds captured from the rest timer when it runs to zero.
    /// Nil when timer was dismissed early or no timer was used — falls back to configured rest.
    var restDurationSeconds: Int?

    @Transient var persistedFatigueSnapshot: FatigueLearningSetSnapshot? = nil

    var overrideTargetRepRange: ClosedRange<Int>? {
        guard let overrideTargetRepMin, let overrideTargetRepMax, overrideTargetRepMin < overrideTargetRepMax else {
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

    var templateSaveTargetRepBounds: (min: Int?, max: Int?) {
        if hasOverrideRepTarget {
            switch (overrideTargetRepMin, overrideTargetRepMax) {
            case let (.some(min), .some(max)):
                return (min, max)
            case let (.some(value), .none), let (.none, .some(value)):
                return (value, value)
            case (.none, .none):
                return (nil, nil)
            }
        }

        if targetRepMin != nil || targetRepMax != nil {
            return (targetRepMin, targetRepMax)
        }

        if let reps {
            return (reps, reps)
        }

        return (nil, nil)
    }

    var hasData: Bool {
        ((weight ?? 0) > 0 && prReps > 0) ||
        totalReps > 0 ||
        (durationSeconds ?? 0) > 0 ||
        (distanceMeters ?? 0) > 0
    }

    var volume: Double? {
        guard let ew = effectiveWeight, statsReps > 0 else { return nil }
        return ew * Double(statsReps)
    }

    var isUnilateralSet: Bool {
        leftReps != nil || rightReps != nil || leftRIR != nil || rightRIR != nil
    }

    var prReps: Int {
        if let leftReps, let rightReps {
            return max(leftReps, rightReps)
        }
        return reps ?? 0
    }

    var totalReps: Int {
        if let leftReps, let rightReps {
            return leftReps + rightReps
        }
        return reps ?? 0
    }

    var statsReps: Int {
        totalReps
    }

    var performanceRIR: Double? {
        switch (leftReps, rightReps, leftRIR, rightRIR) {
        case let (.some(left), .some(right), .some(leftRIR), .some(rightRIR)):
            if left > right { return leftRIR }
            if right > left { return rightRIR }
            return min(leftRIR, rightRIR)
        case (_, _, let leftRIR?, nil):
            return leftRIR
        case (_, _, nil, let rightRIR?):
            return rightRIR
        default:
            return rir
        }
    }

    func syncDerivedPerformanceFields(for exercise: Exercise?) {
        guard exercise?.supportsUnilateralLogging == true, exercise?.unilateral == true else { return }

        let resolvedPRReps = prReps
        reps = resolvedPRReps > 0 ? resolvedPRReps : nil
        rir = performanceRIR
        side = isUnilateralSet ? .both : nil
    }

    func fatigueLearningSnapshot(effectiveWeightOverride: Double? = nil) -> FatigueLearningSetSnapshot {
        FatigueLearningSetSnapshot(
            completed: completed,
            setType: setType,
            actualWeight: effectiveWeightOverride ?? effectiveWeight ?? weight,
            actualReps: reps,
            actualRIR: rir,
            restDurationSeconds: restDurationSeconds
        )
    }

    func markFatigueLearningSnapshotPersisted(effectiveWeightOverride: Double? = nil) {
        persistedFatigueSnapshot = fatigueLearningSnapshot(effectiveWeightOverride: effectiveWeightOverride)
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
        leftReps: Int? = nil,
        rightReps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        e1RM: Double? = nil,
        e1RMFormulaVersion: String? = nil,
        rpe: Double? = nil,
        rir: Double? = nil,
        leftRIR: Double? = nil,
        rightRIR: Double? = nil,
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
        overrideTargetRepMin: Int? = nil,
        overrideTargetRepMax: Int? = nil,
        targetRPE: Double? = nil,
        targetRIR: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        restDurationSeconds: Int? = nil
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
        self.leftReps = leftReps
        self.rightReps = rightReps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.e1RM = e1RM
        self.e1RMFormulaVersion = e1RMFormulaVersion
        self.rpe = rpe
        self.rir = rir
        self.leftRIR = leftRIR
        self.rightRIR = rightRIR
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
        self.overrideTargetRepMin = overrideTargetRepMin
        self.overrideTargetRepMax = overrideTargetRepMax
        self.targetRPE = targetRPE
        self.targetRIR = targetRIR
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.restDurationSeconds = restDurationSeconds
    }
}

extension WorkoutSet: @unchecked Sendable {}
