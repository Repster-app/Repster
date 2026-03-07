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

    // MARK: - Weight Prescription Settings (optional for migration compatibility)

    /// Whether smart weight suggestions are enabled globally. Default: true.
    var prescriptionEnabled: Bool?

    /// How many weeks of recent data to consider for e1RM estimation. Default: 6.
    var prescriptionRecencyWeeks: Int?

    /// Default weight increment for rounding prescribed weights (kg). Default: 2.5.
    var prescriptionDefaultIncrement: Double?

    /// Whether to apply a freshness bonus (~3-6%) on the first set. Default: false.
    var prescriptionFreshnessBonus: Bool?

    /// Freshness bonus percentage (0.0–0.1). Default: 0.03.
    var prescriptionFreshnessBonusPercent: Double?

    /// Whether fatigue modeling is enabled. Default: true.
    var prescriptionFatigueModelingEnabled: Bool?

    /// Default recovery constant in seconds for fatigue decay. Default: 180.
    var prescriptionDefaultRecoveryConstant: Double?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        unitPreference: UnitPreference = .metric,
        includeWarmupsInVolume: Bool = false,
        includeWarmupsInPRs: Bool = false,
        e1RMFormula: String = "epley",
        defaultRestTimeSeconds: Int? = nil,
        prescriptionEnabled: Bool = true,
        prescriptionRecencyWeeks: Int = 6,
        prescriptionDefaultIncrement: Double = 2.5,
        prescriptionFreshnessBonus: Bool = false,
        prescriptionFreshnessBonusPercent: Double = 0.03,
        prescriptionFatigueModelingEnabled: Bool = true,
        prescriptionDefaultRecoveryConstant: Double = 180,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.unitPreference = unitPreference
        self.includeWarmupsInVolume = includeWarmupsInVolume
        self.includeWarmupsInPRs = includeWarmupsInPRs
        self.e1RMFormula = e1RMFormula
        self.defaultRestTimeSeconds = defaultRestTimeSeconds
        self.prescriptionEnabled = prescriptionEnabled
        self.prescriptionRecencyWeeks = prescriptionRecencyWeeks
        self.prescriptionDefaultIncrement = prescriptionDefaultIncrement
        self.prescriptionFreshnessBonus = prescriptionFreshnessBonus
        self.prescriptionFreshnessBonusPercent = prescriptionFreshnessBonusPercent
        self.prescriptionFatigueModelingEnabled = prescriptionFatigueModelingEnabled
        self.prescriptionDefaultRecoveryConstant = prescriptionDefaultRecoveryConstant
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
