import Foundation
import SwiftData

/// Records the prediction error for a single completed set during a workout session.
/// Used by FatigueLearningService to adaptively tune per-exercise fatigue parameters.
@Model
final class FatigueObservation {
    var id: UUID
    var exerciseId: UUID
    var workoutId: UUID

    /// 0-indexed position among completed working sets for this exercise in the session.
    var setIndex: Int

    /// The effective e1RM the fatigue model predicted for this set (before completion).
    var predictedEffectiveE1RM: Double

    /// The actual e1RM demonstrated by the user (computed from actual weight/reps/RIR).
    var actualE1RM: Double

    /// Normalized error: (predicted - actual) / baseE1RM.
    /// Negative = model was too aggressive (user stronger than predicted).
    /// Positive = model was too lenient (user weaker than predicted).
    var normalizedError: Double

    /// The base e1RM used for normalization.
    var baseE1RM: Double

    /// The weight the model suggested.
    var prescribedWeight: Double

    /// The weight the user actually used.
    var actualWeight: Double

    /// The reps the user actually completed.
    var actualReps: Int

    /// The RIR the user reported.
    var actualRIR: Double

    /// Rest duration before this set (from rest timer), if captured.
    var restDurationSeconds: Int?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        workoutId: UUID,
        setIndex: Int,
        predictedEffectiveE1RM: Double,
        actualE1RM: Double,
        normalizedError: Double,
        baseE1RM: Double,
        prescribedWeight: Double,
        actualWeight: Double,
        actualReps: Int,
        actualRIR: Double,
        restDurationSeconds: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.workoutId = workoutId
        self.setIndex = setIndex
        self.predictedEffectiveE1RM = predictedEffectiveE1RM
        self.actualE1RM = actualE1RM
        self.normalizedError = normalizedError
        self.baseE1RM = baseE1RM
        self.prescribedWeight = prescribedWeight
        self.actualWeight = actualWeight
        self.actualReps = actualReps
        self.actualRIR = actualRIR
        self.restDurationSeconds = restDurationSeconds
        self.createdAt = createdAt
    }
}
