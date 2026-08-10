// InsightsServiceProtocol.swift
// Contract for the insights analysis engine and feed access.

import Foundation

/// Value snapshot of an InsightRecord, safe to hand to the UI layer.
struct InsightItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let ruleId: String
    let subjectName: String?
    let headline: String
    let detailText: String
    let methodologyText: String
    let chartKind: InsightChartKind
    let chartLabels: [String]
    let chartValues: [Double]
    let isNew: Bool
    let generatedAt: Date

    var category: InsightCategory {
        InsightCategory(ruleId: ruleId)
    }
}

/// The shape a finding's supporting data actually has.
///
/// v1 rendered every finding as the same capsule bar chart, which made a
/// two-group comparison, a proportion and a signed time series look identical.
/// The kind travels with the record so the card can pick a component that fits.
enum InsightChartKind: String, Sendable, Codable {
    /// Something over time. `isSigned` findings render around a zero line.
    case series
    /// Discrete periods — one bar per week, latest emphasised.
    case column
    /// Ordered categories, drawn in the subject's own colours.
    case ranking
    /// Parts of a whole: one stacked bar with a key.
    case proportion
    /// Two groups, or a value against a mark.
    case comparison
    /// An interval that moved — two segments on a shared axis.
    case range
    /// Events and the gaps between them.
    case timeline

    /// Series where the sign carries the meaning (performance vs. prediction),
    /// so the chart needs a zero line rather than a common baseline.
    static let signedSeriesRules: Set<String> = ["rirCalibration", "deloadReadiness"]
}

/// Display grouping for insight cards, derived from the producing rule.
enum InsightCategory: String {
    case muscleBalance
    case targetAdherence
    case restSweetSpot
    case rirCalibration
    case strengthTrend
    case consistency
    case droppedExercise
    case volumeRamp
    case deloadReadiness
    case prPace
    case other

    init(ruleId: String) {
        self = InsightCategory(rawValue: ruleId) ?? .other
    }

    var displayName: String {
        switch self {
        case .muscleBalance: return "Muscle balance"
        case .targetAdherence: return "Targets"
        case .restSweetSpot: return "Rest"
        case .rirCalibration: return "Effort accuracy"
        case .strengthTrend: return "Progress"
        case .consistency: return "Consistency"
        case .droppedExercise: return "Drift"
        case .volumeRamp: return "Load"
        case .deloadReadiness: return "Readiness"
        case .prPace: return "PR pace"
        case .other: return "Insight"
        }
    }
}

// MARK: - Training status

/// Where the user's trailing week sits against their own recent norm.
///
/// Descriptive only: every value here is arithmetic on the user's own data, so
/// this layer always renders and can never be "wrong" the way a finding can.
struct TrainingStatus: Sendable, Equatable {
    /// Working sets in the trailing 7 days.
    let currentSets: Int
    /// Mean 7-day set total over the 8 weeks preceding the trailing window.
    /// Nil until there is enough history to compare against.
    let baselineSets: Double?
    let muscles: [MuscleVolumeRow]
    /// True once any eligible set exists — drives "has the user started" copy.
    let hasData: Bool

    /// Nil while there is no baseline, which is the cold-start case.
    var band: Band? {
        guard let baselineSets, baselineSets > 0 else { return nil }
        return Band(ratio: Double(currentSets) / baselineSets)
    }

    enum Band: Sendable {
        case wellBelow, below, normal, above, wellAbove

        init(ratio: Double) {
            switch ratio {
            case ..<0.60:      self = .wellBelow
            case 0.60..<0.85:  self = .below
            case 0.85..<1.15:  self = .normal
            case 1.15..<1.40:  self = .above
            default:           self = .wellAbove
            }
        }

        /// Deliberately states the comparison rather than grading it. No score:
        /// a number invites arguing with it, and there is nothing to win there.
        var headline: String {
            switch self {
            case .wellBelow: return "Lighter week than your usual"
            case .below:     return "A bit below your usual"
            case .normal:    return "Tracking normally"
            case .above:     return "Busier week than your usual"
            case .wellAbove: return "Well above your usual"
            }
        }
    }
}

/// One muscle group's trailing-week volume against its own baseline.
struct MuscleVolumeRow: Sendable, Equatable, Identifiable {
    /// Normalized group value, e.g. "chest". Derived from the user's own
    /// exercises, so custom groups appear here too.
    let group: String
    let displayName: String
    let currentSets: Int
    /// Mean 7-day sets for this group over the baseline window.
    let baselineSets: Double?

    var id: String { group }

    /// Rounded difference against baseline. Nil during cold start.
    var delta: Int? {
        guard let baselineSets else { return nil }
        return Int((Double(currentSets) - baselineSets).rounded())
    }

    /// A group the user normally trains that got nothing this week. The one
    /// case worth colouring — it's factual, not a verdict on volume.
    var isAbsent: Bool {
        guard let baselineSets else { return false }
        return currentSets == 0 && baselineSets >= 1
    }
}

protocol InsightsServiceProtocol: Sendable {
    /// Re-runs the analysis if workout data changed since the last run.
    /// Cheap when nothing changed — safe to call on every Home appearance.
    func refreshIfNeeded() async throws

    /// Trailing-week training status. Always returns a value; `hasData` is false
    /// for a user who hasn't logged anything yet.
    func fetchTrainingStatus() async throws -> TrainingStatus

    /// Active (non-snoozed) insights, new first, then by score.
    func fetchActiveInsights() async throws -> [InsightItem]

    /// Count of active insights the user hasn't seen yet (home badge).
    func newInsightCount() async throws -> Int

    /// Marks all active insights as seen (called when the feed appears).
    func markAllSeen() async throws

    /// Hides an insight for the cooldown period.
    func snooze(insightId: UUID) async throws
}
