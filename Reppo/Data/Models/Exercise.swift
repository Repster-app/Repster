import Foundation
import SwiftData

enum ExerciseFatigueRateSource: String, Codable, Sendable {
    case manualOverride
    case learned
}

@Model
final class Exercise {
    var id: UUID
    var name: String
    var equipmentType: EquipmentType
    var trackingType: TrackingType
    var primaryMuscle: String?
    var secondaryMuscles: [String]
    var movementPattern: MovementPattern?
    var unilateral: Bool
    var bilateralLoadFactor: Double?
    var bodyweightFactor: Double
    var weightIncrement: Double?
    var defaultRestTime: Int?

    // MARK: - Fatigue Profile (Smart Suggestions)

    /// Per-exercise fatigue rate. nil = use global/default learned rate (0.03 fallback).
    /// Controls how much each set's stress accumulates as session fatigue.
    var fatigueRate: Double?
    /// Source of the stored per-exercise fatigue rate.
    var fatigueRateSourceRawValue: String?

    /// Per-exercise recovery constant in seconds. nil = use global default (180).
    /// Controls how quickly fatigue decays during rest periods.
    var recoveryConstant: Double?

    // MARK: - Adaptive Fatigue Learning

    /// Number of qualifying workout sessions that contributed to fatigue learning.
    var fatigueLearningSessionCount: Int?

    /// Running EMA of normalized prediction errors across sessions.
    /// Negative = model consistently too aggressive, positive = too lenient.
    var fatigueLearningCumulativeError: Double?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        equipmentType: EquipmentType,
        trackingType: TrackingType,
        primaryMuscle: String? = nil,
        secondaryMuscles: [String] = [],
        movementPattern: MovementPattern? = nil,
        unilateral: Bool = false,
        bilateralLoadFactor: Double? = nil,
        bodyweightFactor: Double = 0.0,
        weightIncrement: Double? = nil,
        defaultRestTime: Int? = nil,
        fatigueRate: Double? = nil,
        fatigueRateSourceRawValue: String? = nil,
        recoveryConstant: Double? = nil,
        fatigueLearningSessionCount: Int? = nil,
        fatigueLearningCumulativeError: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.equipmentType = equipmentType
        self.trackingType = trackingType
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.movementPattern = movementPattern
        self.unilateral = unilateral
        self.bilateralLoadFactor = bilateralLoadFactor
        self.bodyweightFactor = bodyweightFactor
        self.weightIncrement = weightIncrement
        self.defaultRestTime = defaultRestTime
        self.fatigueRate = fatigueRate
        self.fatigueRateSourceRawValue = fatigueRateSourceRawValue
        self.recoveryConstant = recoveryConstant
        self.fatigueLearningSessionCount = fatigueLearningSessionCount
        self.fatigueLearningCumulativeError = fatigueLearningCumulativeError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Exercise: @unchecked Sendable {}

extension Exercise {
    var supportsUnilateralLogging: Bool {
        trackingType == .weightReps || trackingType == .weightRepsDuration
    }

    var resolvedFatigueRateSource: ExerciseFatigueRateSource? {
        if let raw = fatigueRateSourceRawValue, let source = ExerciseFatigueRateSource(rawValue: raw) {
            return source
        }
        guard fatigueRate != nil else { return nil }
        return (fatigueLearningSessionCount ?? 0) > 0 ? .learned : .manualOverride
    }

    func refreshFatigueRateSourceMetadata() {
        fatigueRateSourceRawValue = resolvedFatigueRateSource?.rawValue
    }

    var isBodyweightStyleExercise: Bool {
        equipmentType == .bodyweight || bodyweightFactor > 0
    }
}
