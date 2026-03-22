import Foundation
import SwiftData

@Model
final class HealthProfile {
    var id: UUID
    var unitPreference: UnitPreference
    var includeWarmupsInVolume: Bool
    var includeWarmupsInPRs: Bool
    var e1RMFormula: String
    var defaultRestTimeSeconds: Int?

    /// Default rest time after warmup sets. Typically shorter than working set rest.
    /// When nil, falls back to defaultRestTimeSeconds.
    var defaultWarmupRestTimeSeconds: Int?

    /// Alert mode when rest timer finishes: "off", "vibration", "sound", or "both".
    /// Default: "both".
    var restTimerAlert: String?

    // MARK: - Smart Suggestions Settings (legacy field names for migration compatibility)

    /// Whether smart weight suggestions are enabled globally. Default: true.
    var prescriptionEnabled: Bool?

    /// How many weeks of recent data to consider for e1RM estimation. Default: 6.
    var prescriptionRecencyWeeks: Int?

    /// Default weight increment for rounding prescribed weights (kg). Default: 2.5.
    var prescriptionDefaultIncrement: Double?

    /// Default reps target used when a set is missing reps guidance. Default: 8.
    var prescriptionDefaultTargetReps: Int?

    /// Default RIR target used when a set is missing RIR guidance. Default: 2.
    var prescriptionDefaultTargetRIR: Int?

    /// Whether to apply a freshness bonus (~3-6%) on the first set. Default: false.
    var prescriptionFreshnessBonus: Bool?

    /// Freshness bonus percentage (0.0–0.1). Default: 0.03.
    var prescriptionFreshnessBonusPercent: Double?

    /// Whether fatigue modeling is enabled. Default: true.
    var prescriptionFatigueModelingEnabled: Bool?

    /// Default recovery constant in seconds for fatigue decay. Default: 180.
    var prescriptionDefaultRecoveryConstant: Double?

    /// User-wide learned fatigue rate. Nil = use fixed default (0.04) when no exercise override exists.
    var prescriptionLearnedFatigueRate: Double? = nil

    /// Number of qualifying workouts contributing to the global fatigue baseline.
    var prescriptionFatigueLearningSessionCount: Int? = nil

    /// Running EMA of normalized prediction errors across all qualifying workouts.
    var prescriptionFatigueLearningCumulativeError: Double? = nil

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        unitPreference: UnitPreference = .metric,
        includeWarmupsInVolume: Bool = false,
        includeWarmupsInPRs: Bool = false,
        e1RMFormula: String = "epley",
        defaultRestTimeSeconds: Int? = 150,
        restTimerAlert: String = "vibration",
        prescriptionEnabled: Bool = true,
        prescriptionRecencyWeeks: Int = 6,
        prescriptionDefaultIncrement: Double = 2.5,
        prescriptionDefaultTargetReps: Int = 8,
        prescriptionDefaultTargetRIR: Int = 2,
        prescriptionFreshnessBonus: Bool = false,
        prescriptionFreshnessBonusPercent: Double = 0.03,
        prescriptionFatigueModelingEnabled: Bool = true,
        prescriptionDefaultRecoveryConstant: Double = 180,
        prescriptionLearnedFatigueRate: Double? = nil,
        prescriptionFatigueLearningSessionCount: Int? = nil,
        prescriptionFatigueLearningCumulativeError: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.unitPreference = unitPreference
        self.includeWarmupsInVolume = includeWarmupsInVolume
        self.includeWarmupsInPRs = includeWarmupsInPRs
        self.e1RMFormula = e1RMFormula
        self.defaultRestTimeSeconds = defaultRestTimeSeconds
        self.restTimerAlert = restTimerAlert
        self.prescriptionEnabled = prescriptionEnabled
        self.prescriptionRecencyWeeks = prescriptionRecencyWeeks
        self.prescriptionDefaultIncrement = prescriptionDefaultIncrement
        self.prescriptionDefaultTargetReps = prescriptionDefaultTargetReps
        self.prescriptionDefaultTargetRIR = prescriptionDefaultTargetRIR
        self.prescriptionFreshnessBonus = prescriptionFreshnessBonus
        self.prescriptionFreshnessBonusPercent = prescriptionFreshnessBonusPercent
        self.prescriptionFatigueModelingEnabled = prescriptionFatigueModelingEnabled
        self.prescriptionDefaultRecoveryConstant = prescriptionDefaultRecoveryConstant
        self.prescriptionLearnedFatigueRate = prescriptionLearnedFatigueRate
        self.prescriptionFatigueLearningSessionCount = prescriptionFatigueLearningSessionCount
        self.prescriptionFatigueLearningCumulativeError = prescriptionFatigueLearningCumulativeError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension HealthProfile: @unchecked Sendable {}
