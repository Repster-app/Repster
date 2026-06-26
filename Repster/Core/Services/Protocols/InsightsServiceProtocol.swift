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
    let chartLabels: [String]
    let chartValues: [Double]
    let isNew: Bool
    let generatedAt: Date

    var category: InsightCategory {
        InsightCategory(ruleId: ruleId)
    }
}

/// Display grouping for insight cards, derived from the producing rule.
enum InsightCategory: String {
    case muscleBalance
    case targetAdherence
    case prRhythm
    case restSweetSpot
    case rirCalibration
    case other

    init(ruleId: String) {
        self = InsightCategory(rawValue: ruleId) ?? .other
    }

    var displayName: String {
        switch self {
        case .muscleBalance: return "Muscle balance"
        case .targetAdherence: return "Targets"
        case .prRhythm: return "PR rhythm"
        case .restSweetSpot: return "Rest"
        case .rirCalibration: return "Effort accuracy"
        case .other: return "Insight"
        }
    }
}

protocol InsightsServiceProtocol: Sendable {
    /// Re-runs the analysis if workout data changed since the last run.
    /// Cheap when nothing changed — safe to call on every Home appearance.
    func refreshIfNeeded() async throws

    /// Active (non-snoozed) insights, new first, then by score.
    func fetchActiveInsights() async throws -> [InsightItem]

    /// Count of active insights the user hasn't seen yet (home badge).
    func newInsightCount() async throws -> Int

    /// Marks all active insights as seen (called when the feed appears).
    func markAllSeen() async throws

    /// Hides an insight for the cooldown period.
    func snooze(insightId: UUID) async throws
}
