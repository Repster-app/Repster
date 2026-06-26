import Foundation
import SwiftData

/// A single surfaced training insight, produced by InsightsService at analysis
/// time and rendered in the Insights feed. Identity for upserts is
/// (ruleId, subjectId) — one live insight per rule per subject.
@Model
final class InsightRecord {
    var id: UUID
    /// Stable identifier of the rule that produced this insight (e.g. "restSweetSpot").
    var ruleId: String
    /// The exercise this insight is about, when exercise-scoped. Nil for global insights.
    var subjectId: UUID?
    /// Denormalized display name for the subject (exercise or muscle group).
    var subjectName: String?
    var stateRaw: String
    /// Hidden from the feed until this date when the user snoozes the insight.
    var snoozedUntil: Date?
    var score: Double
    var headline: String
    var detailText: String
    /// Short "how this was computed" line shown under the card for trust.
    var methodologyText: String
    var chartLabels: [String]
    var chartValues: [Double]
    var generatedAt: Date
    var seenAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var state: InsightState {
        get { InsightState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ruleId: String,
        subjectId: UUID? = nil,
        subjectName: String? = nil,
        state: InsightState = .new,
        snoozedUntil: Date? = nil,
        score: Double,
        headline: String,
        detailText: String,
        methodologyText: String,
        chartLabels: [String] = [],
        chartValues: [Double] = [],
        generatedAt: Date = Date(),
        seenAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ruleId = ruleId
        self.subjectId = subjectId
        self.subjectName = subjectName
        self.stateRaw = state.rawValue
        self.snoozedUntil = snoozedUntil
        self.score = score
        self.headline = headline
        self.detailText = detailText
        self.methodologyText = methodologyText
        self.chartLabels = chartLabels
        self.chartValues = chartValues
        self.generatedAt = generatedAt
        self.seenAt = seenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum InsightState: String, Codable {
    case new
    case seen
}

extension InsightRecord: @unchecked Sendable {}
