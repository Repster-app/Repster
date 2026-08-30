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
    /// Typical spacing between plotted events, for `.timeline` findings whose
    /// text quotes a cadence. Nil leaves the chart to estimate its own.
    let typicalGapDays: Double?
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

/// What the muscle panel counts. Sets is the default because it's what the
/// status card above the panel compares; the other two answer different
/// questions about the same week.
enum MuscleMetric: String, CaseIterable, Identifiable, Sendable {
    case sets
    case reps
    case volume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sets:   return "Sets"
        case .reps:   return "Reps"
        case .volume: return "Volume"
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
    let currentReps: Int
    /// Mean 7-day reps for this group over the baseline window.
    let baselineReps: Double?
    /// Always kg. Converted once at the display edge, like everywhere else.
    let currentVolume: Double
    /// Mean 7-day volume in kg for this group over the baseline window.
    let baselineVolume: Double?

    var id: String { group }

    /// Rounded difference against baseline. Nil during cold start.
    var delta: Int? {
        guard let baselineSets else { return nil }
        return Int((Double(currentSets) - baselineSets).rounded())
    }

    /// A group the user normally trains that got nothing this week. The one
    /// case worth colouring — it's factual, not a verdict on volume.
    ///
    /// Deliberately defined on sets whatever metric is on screen: it means the
    /// group went untrained, which is a fact about training rather than about
    /// weight moved. Keyed to volume it would flag a group trained hard with
    /// bodyweight only.
    var isAbsent: Bool {
        guard let baselineSets else { return false }
        return currentSets == 0 && baselineSets >= 1
    }

    // MARK: - Metric access

    func current(for metric: MuscleMetric) -> Double {
        switch metric {
        case .sets:   return Double(currentSets)
        case .reps:   return Double(currentReps)
        case .volume: return currentVolume
        }
    }

    func baseline(for metric: MuscleMetric) -> Double? {
        switch metric {
        case .sets:   return baselineSets
        case .reps:   return baselineReps
        case .volume: return baselineVolume
        }
    }

    /// Difference against baseline in the metric's own units. Nil during cold
    /// start, matching `delta`.
    func delta(for metric: MuscleMetric) -> Double? {
        guard let baseline = baseline(for: metric) else { return nil }
        return current(for: metric) - baseline
    }

    /// The group was trained but carries no weight — bodyweight-only work. Worth
    /// distinguishing from a genuine zero when the volume view is on screen.
    var hasVolumeGap: Bool {
        currentSets > 0 && currentVolume == 0
    }
}

// MARK: - Rule diagnostics

/// Admin-only account of what every rule did against the user's real data.
///
/// The feed only shows what survived curation, which makes two very different
/// failures look identical from the outside: a rule whose gates never clear for
/// this user, and a rule that produces a finding every week but loses the
/// ranking. Those need opposite fixes — one is a gate to loosen, the other a
/// weight to change — so the diagnostic reports them apart.
struct RuleDiagnostic: Sendable, Identifiable {
    let ruleId: String
    /// The rule's fixed ranking weight, so a rule that is silent despite a high
    /// weight stands out.
    let actionability: Double
    /// Findings from the normal pass, best-scoring first.
    let findings: [Candidate]
    /// Findings from the lower-bar pass. Only progress rules implement it, and
    /// it only runs when the whole normal pass came back empty.
    let relaxedFindings: [Candidate]
    /// True when one of this rule's findings is in the live feed.
    let survivedCuration: Bool
    /// When a cooling rule may fire again. Nil for every rule without a refire
    /// interval, which is all but one of them.
    let refireAvailableAt: Date?

    var id: String { ruleId }

    /// One candidate finding, with the score curation actually ranked it on.
    struct Candidate: Sendable, Identifiable {
        let id = UUID()
        let subjectName: String?
        let headline: String
        /// `effectSize * actionability` — what `curate` sorts by.
        let score: Double
        let effectSize: Double
        let isDiagnostic: Bool
    }

    /// Why this rule is or isn't on screen.
    enum Status: Sendable {
        /// In the feed right now.
        case shown
        /// Produced a finding that lost the ranking — a weighting problem.
        case rankedOut
        /// Produced a finding but is inside its refire cooldown.
        case cooling
        /// Only the relaxed pass produced anything, so it appears solely when
        /// the feed would otherwise be empty.
        case relaxedOnly
        /// Produced nothing — its gates never cleared. A rules problem, and no
        /// amount of re-ranking will surface it.
        case silent
    }

    var status: Status {
        if survivedCuration { return .shown }
        if refireAvailableAt != nil { return .cooling }
        if !findings.isEmpty { return .rankedOut }
        if !relaxedFindings.isEmpty { return .relaxedOnly }
        return .silent
    }
}

protocol InsightsServiceProtocol: Sendable {
    /// Re-runs the analysis if workout data changed since the last run.
    /// Cheap when nothing changed — safe to call on every Home appearance.
    ///
    /// Returns true when the analysis actually re-ran. Callers holding an
    /// already-loaded status or feed use this to skip re-fetching values that
    /// cannot have changed; re-deriving the status is the single most expensive
    /// call on the service.
    @discardableResult
    func refreshIfNeeded() async throws -> Bool

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

    /// Runs every rule against the current data and reports what each produced,
    /// including the findings curation discarded. Admin diagnostics only — this
    /// evaluates the whole rule set and persists nothing.
    func ruleDiagnostics() async throws -> [RuleDiagnostic]
}
