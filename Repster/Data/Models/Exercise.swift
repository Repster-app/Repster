import Foundation
import SwiftData

enum ExerciseFatigueRateSource: String, Codable, Sendable {
    case manualOverride
    case learned
}

enum UnilateralRepTargetMode: String, Codable, CaseIterable, Sendable {
    case perSide = "per_side"
    case totalAcrossSides = "total_across_sides"

    var displayName: String {
        switch self {
        case .perSide:
            return "Per Side"
        case .totalAcrossSides:
            return "Total Reps"
        }
    }

    var helpText: String {
        switch self {
        case .perSide:
            return "Targets and Smart Suggestions use reps for each side."
        case .totalAcrossSides:
            return "Targets and Smart Suggestions start from the total reps across both sides."
        }
    }
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
    var unilateralRepTargetModeRawValue: String?
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
        unilateralRepTargetMode: UnilateralRepTargetMode? = nil,
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
        self.unilateralRepTargetModeRawValue = unilateralRepTargetMode?.rawValue
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
    private static let totalAcrossSidesFallbackNames: Set<String> = [
        "dumbbell lunge"
    ]

    var supportsUnilateralLogging: Bool {
        trackingType == .weightReps || trackingType == .weightRepsDuration
    }

    var unilateralRepTargetMode: UnilateralRepTargetMode {
        get {
            if let rawValue = unilateralRepTargetModeRawValue,
               let mode = UnilateralRepTargetMode(rawValue: rawValue) {
                return mode
            }
            return defaultUnilateralRepTargetMode
        }
        set {
            unilateralRepTargetModeRawValue = newValue.rawValue
        }
    }

    var usesTotalAcrossSidesRepTargets: Bool {
        unilateral && supportsUnilateralLogging && unilateralRepTargetMode == .totalAcrossSides
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

    private var defaultUnilateralRepTargetMode: UnilateralRepTargetMode {
        guard unilateral, supportsUnilateralLogging else { return .perSide }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Self.totalAcrossSidesFallbackNames.contains(normalizedName) {
            return .totalAcrossSides
        }
        return .perSide
    }
}
