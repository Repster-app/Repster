import Foundation
import SwiftData

@Model
final class HealthProfile {
    var id: UUID
    var unitPreferenceRawValue: String = UnitPreference.metric.rawValue
    var includeWarmupsInVolume: Bool
    var includeWarmupsInPRs: Bool
    var e1RMFormula: String
    var defaultRestTimeSeconds: Int?

    /// Default rest time after warmup sets. Typically shorter than working set rest.
    /// When nil, falls back to defaultRestTimeSeconds.
    var defaultWarmupRestTimeSeconds: Int?

    /// Alert mode when rest timer finishes: "off", "vibration", "sound", or "both".
    ///
    /// Two different defaults apply and they are deliberately not the same value:
    /// a *new* profile is created with `"vibration"` (see `init`), while a profile from before
    /// this attribute existed reads `nil` and is treated as `defaultAlertMode` below. Changing
    /// the latter would silently alter the alarm for every migrated user.
    var restTimerAlert: String?

    /// What a `nil` `restTimerAlert` means. Read by the ViewModel and both Settings surfaces,
    /// which previously disagreed — the picker said "Both", the summary row said "Vibration",
    /// and the behaviour was "Both".
    static let defaultAlertMode = "both"

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

    /// Whether Smart Suggestions admin diagnostics are enabled. Default: false.
    var prescriptionAdminModeEnabled: Bool?

    /// Kill switch for the epoch-2 capacity changes: crediting reps in reserve as a floor,
    /// restricting capacity evidence to point-estimate set types, and clamping downward moves.
    ///
    /// Defaults to on. It exists because this is the first change in the feature's history that can
    /// make the app ask for *more* weight rather than less — every previous failure mode was "too
    /// light", which is a disappointment, and this one's is "too heavy", which is a failed rep.
    /// Without a lever the only remedy for a bad interaction in the field is an App Store release.
    ///
    /// Off restores the 1.x behaviour exactly: no floor, capacity from any non-warmup set, no clamp.
    var prescriptionCapacityGuardsEnabled: Bool?

    /// User-wide learned fatigue rate. Nil = use fixed default (0.03) when no exercise override exists.
    var prescriptionLearnedFatigueRate: Double? = nil

    /// Number of qualifying workouts contributing to the global fatigue baseline.
    var prescriptionFatigueLearningSessionCount: Int? = nil

    /// Running EMA of normalized prediction errors across all qualifying workouts.
    var prescriptionFatigueLearningCumulativeError: Double? = nil

    var createdAt: Date
    var updatedAt: Date

    var unitPreference: UnitPreference {
        get {
            UnitPreference(rawValue: unitPreferenceRawValue) ?? .metric
        }
        set {
            unitPreferenceRawValue = newValue.rawValue
        }
    }

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
        prescriptionAdminModeEnabled: Bool = false,
        prescriptionCapacityGuardsEnabled: Bool = true,
        prescriptionLearnedFatigueRate: Double? = nil,
        prescriptionFatigueLearningSessionCount: Int? = nil,
        prescriptionFatigueLearningCumulativeError: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.unitPreferenceRawValue = unitPreference.rawValue
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
        self.prescriptionAdminModeEnabled = prescriptionAdminModeEnabled
        self.prescriptionCapacityGuardsEnabled = prescriptionCapacityGuardsEnabled
        self.prescriptionLearnedFatigueRate = prescriptionLearnedFatigueRate
        self.prescriptionFatigueLearningSessionCount = prescriptionFatigueLearningSessionCount
        self.prescriptionFatigueLearningCumulativeError = prescriptionFatigueLearningCumulativeError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension HealthProfile: @unchecked Sendable {}
