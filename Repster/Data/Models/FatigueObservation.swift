import Foundation
import SwiftData

/// Which generation of the suggestion model a stored prediction came from.
///
/// The learned fatigue rates are calibrated *around* the engine's constants, so a change to the
/// model invalidates them — they are answers to a question the engine no longer asks. The usual
/// remedy is a reset, and the reset that already existed also deleted every observation and audit.
///
/// That is the wrong trade. Learned rates are cheap to rebuild: the learner re-derives them from
/// future sessions, and the raw workout history needed to seed them is never deleted. Predictions
/// are not. `predictedEffectiveE1RM` next to `actualE1RM` is the app's only record of how well it
/// has been calling the shot, it cannot be recomputed from anything once thrown away, and it is
/// exactly what a coaching surface would be built on.
///
/// So: clear the rates, keep the record, and stamp it — learning reads only the current epoch,
/// while diagnostics and coaching can read across the boundary and compare generations.
enum SuggestionModelEpoch {
    /// Epoch 1 — the shipped 1.x model. Written as nil, since it predates stamping.
    static let legacy: Int = 1

    /// Epoch 2 — capacity baseline reads reps in reserve (PR3); RIR >= 3 credited as a floor,
    /// capacity restricted to point-estimate set types, downward moves clamped (PR4).
    static let current: Int = 2

    /// Rows written before stamping existed belong to epoch 1.
    static func resolved(_ stored: Int?) -> Int { stored ?? legacy }
}

/// Records the prediction error for a single completed set during a workout session.
/// Used by FatigueLearningService to adaptively tune per-exercise fatigue parameters.
@Model
final class FatigueObservation {
    var id: UUID
    var exerciseId: UUID
    var workoutId: UUID
    // Stored as optional so pre-existing databases can lightweight-migrate rows that never had a set ID.
    var storedSetId: UUID?

    var setId: UUID {
        get { storedSetId ?? id }
        set { storedSetId = newValue }
    }

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

    /// The set's type, so per-type fatigue can eventually be *learned* rather than asserted.
    ///
    /// Optional and raw-valued so existing stores lightweight-migrate; nil means "recorded before
    /// this was captured", not `.working`. Until this exists on enough rows, the set-type
    /// multipliers in `SuggestionEngine.setTypeMultiplier` are unfalsifiable: a wrong multiplier's
    /// prediction error is absorbed into that exercise's learned fatigue rate and applied to every
    /// set of the exercise regardless of type. Instrument first, then flatten.
    var setTypeRawValue: String?

    var setType: SetType? {
        get { setTypeRawValue.flatMap(SetType.init(rawValue:)) }
        set { setTypeRawValue = newValue?.rawValue }
    }

    /// Which version of the suggestion model produced ``predictedEffectiveE1RM``.
    ///
    /// A prediction is only meaningful next to the model that made it. When the model changes, the
    /// learned rates calibrated around the old constants have to be cleared — but the *record* of
    /// what was predicted and what actually happened must not be, because it is model output and
    /// once deleted it cannot be recomputed from anything. Stamping the epoch lets learning read
    /// only the current one while diagnostics and coaching read across all of them.
    ///
    /// nil means epoch 1 — recorded before stamping existed.
    var modelEpoch: Int?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        workoutId: UUID,
        setId: UUID,
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
        setType: SetType? = nil,
        modelEpoch: Int? = SuggestionModelEpoch.current,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.workoutId = workoutId
        self.storedSetId = setId
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
        self.setTypeRawValue = setType?.rawValue
        self.modelEpoch = modelEpoch
        self.createdAt = createdAt
    }
}

extension FatigueObservation: @unchecked Sendable {}

@Model
final class FatigueLearningSetAudit {
    var id: UUID
    var workoutId: UUID
    var exerciseId: UUID
    var setId: UUID
    /// Visible row number within the exercise card as shown in the workout UI.
    var visibleSetNumber: Int
    var setType: SetType
    var status: FatigueLearningAuditStatus
    var suggestionUnavailableReasonRawValue: String?
    var predictedEffectiveE1RM: Double?
    var baseE1RM: Double?
    var prescribedWeight: Double?
    var actualWeight: Double?
    var actualReps: Int?
    var actualRIR: Double?
    var deviationFraction: Double?
    var normalizedError: Double?
    /// See ``FatigueObservation/modelEpoch``. nil means epoch 1.
    var modelEpoch: Int?
    var createdAt: Date

    var suggestionUnavailableReason: SuggestionUnavailableReason? {
        get {
            guard let suggestionUnavailableReasonRawValue else { return nil }
            return SuggestionUnavailableReason(rawValue: suggestionUnavailableReasonRawValue)
        }
        set {
            suggestionUnavailableReasonRawValue = newValue?.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        exerciseId: UUID,
        setId: UUID,
        visibleSetNumber: Int,
        setType: SetType,
        status: FatigueLearningAuditStatus,
        suggestionUnavailableReason: SuggestionUnavailableReason? = nil,
        predictedEffectiveE1RM: Double? = nil,
        baseE1RM: Double? = nil,
        prescribedWeight: Double? = nil,
        actualWeight: Double? = nil,
        actualReps: Int? = nil,
        actualRIR: Double? = nil,
        deviationFraction: Double? = nil,
        normalizedError: Double? = nil,
        modelEpoch: Int? = SuggestionModelEpoch.current,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.setId = setId
        self.visibleSetNumber = visibleSetNumber
        self.setType = setType
        self.status = status
        self.suggestionUnavailableReasonRawValue = suggestionUnavailableReason?.rawValue
        self.predictedEffectiveE1RM = predictedEffectiveE1RM
        self.baseE1RM = baseE1RM
        self.prescribedWeight = prescribedWeight
        self.actualWeight = actualWeight
        self.actualReps = actualReps
        self.actualRIR = actualRIR
        self.deviationFraction = deviationFraction
        self.normalizedError = normalizedError
        self.modelEpoch = modelEpoch
        self.createdAt = createdAt
    }
}

extension FatigueLearningSetAudit: @unchecked Sendable {}
