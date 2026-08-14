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
    /// Which chart component renders this finding. Optional for lightweight
    /// migration of rows written before v2; nil reads as `.ranking`, which is
    /// what every v1 record was effectively drawn as.
    var chartKindRaw: String?
    var chartLabels: [String]
    var chartValues: [Double]
    /// Typical spacing between the plotted events for `.timeline` findings, so
    /// the chart quotes the same cadence the card's text does instead of
    /// re-deriving one from the trailing window it was handed. Optional both for
    /// lightweight migration of rows written before it existed and because most
    /// chart kinds have no such figure; nil leaves the chart to its own estimate.
    var typicalGapDays: Double?
    var generatedAt: Date
    var seenAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var state: InsightState {
        get { InsightState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    var chartKind: InsightChartKind {
        get { chartKindRaw.flatMap(InsightChartKind.init(rawValue:)) ?? .ranking }
        set { chartKindRaw = newValue.rawValue }
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
        chartKind: InsightChartKind = .ranking,
        chartLabels: [String] = [],
        chartValues: [Double] = [],
        typicalGapDays: Double? = nil,
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
        self.chartKindRaw = chartKind.rawValue
        self.chartLabels = chartLabels
        self.chartValues = chartValues
        self.typicalGapDays = typicalGapDays
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

