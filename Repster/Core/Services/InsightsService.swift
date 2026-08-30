// InsightsService.swift
// Analysis engine for the Insights feed.
//
// Pipeline: generate (every rule runs) → gate (data sufficiency + minimum
// effect, enforced inside each rule) → score → curate (one card per rule,
// capped) → persist as InsightRecords. Zero insights is a valid outcome —
// rules stay silent below their statistical gates rather than emitting
// low-confidence findings.

import Foundation
import SwiftData

// MARK: - Rule plumbing

/// A candidate finding emitted by a rule. Scoring happens in the engine.
struct InsightFinding {
    let ruleId: String
    let subjectId: UUID?
    let subjectName: String?
    let headline: String
    let detailText: String
    let methodologyText: String
    let chartKind: InsightChartKind
    let chartLabels: [String]
    let chartValues: [Double]
    /// The typical spacing between the plotted events, for `.timeline` findings
    /// that quote one in their text.
    ///
    /// Carried rather than left to the chart to re-derive: rules take their
    /// median over the whole history but pass the chart a trailing window of
    /// events, so the two disagreed on the same card — a chart reading "usually
    /// every 15" under prose reading "about every 10 days".
    let typicalGapDays: Double?
    /// Normalized 0...1 magnitude of the finding. Rules return nothing below
    /// their minimum-effect floor, so this is always "worth saying".
    let effectSize: Double
    /// Set per finding rather than per rule: the same rule fires in both
    /// directions (a rising e1RM and a stalled one come from one rule).
    let tone: InsightTone

    init(
        ruleId: String,
        subjectId: UUID?,
        subjectName: String?,
        headline: String,
        detailText: String,
        methodologyText: String,
        chartKind: InsightChartKind,
        chartLabels: [String],
        chartValues: [Double],
        typicalGapDays: Double? = nil,
        effectSize: Double,
        tone: InsightTone = .neutral
    ) {
        self.tone = tone
        self.ruleId = ruleId
        self.subjectId = subjectId
        self.subjectName = subjectName
        self.headline = headline
        self.detailText = detailText
        self.methodologyText = methodologyText
        self.chartKind = chartKind
        self.chartLabels = chartLabels
        self.chartValues = chartValues
        self.typicalGapDays = typicalGapDays
        self.effectSize = effectSize
    }
}

/// What kind of claim a rule makes. The feed caps how many diagnostic cards can
/// appear at once — v1's whole catalog was diagnostic, which is why the feed
/// read as a weekly grading rather than something worth opening.
enum InsightTone {
    /// Tells the user something is wrong.
    case diagnostic
    /// Reports progress or a milestone.
    case progress
    /// Descriptive, neither good nor bad.
    case neutral
}

/// Read-only snapshot of training data that rules evaluate against.
struct InsightAnalysisContext {
    /// Completed workouts, newest first.
    let workouts: [Workout]
    /// Completed sets with data, grouped by workout, ordered by orderInWorkout.
    let setsByWorkout: [UUID: [WorkoutSet]]
    let exercisesById: [UUID: Exercise]
    /// Fatigue observations, newest first.
    let observations: [FatigueObservation]
    let referenceDate: Date
    let unitPreference: UnitPreference

    /// Working sets eligible for progression analysis (respects per-workout
    /// and per-exercise exclusion flags), newest workout first.
    ///
    /// Materialized once at construction rather than computed per access: most
    /// rules read it, and as a computed property every read was a fresh pass
    /// over every workout and set in the store.
    let eligibleWorkingSets: [WorkoutSet]

    init(
        workouts: [Workout],
        setsByWorkout: [UUID: [WorkoutSet]],
        exercisesById: [UUID: Exercise],
        observations: [FatigueObservation],
        referenceDate: Date,
        unitPreference: UnitPreference
    ) {
        self.workouts = workouts
        self.setsByWorkout = setsByWorkout
        self.exercisesById = exercisesById
        self.observations = observations
        self.referenceDate = referenceDate
        self.unitPreference = unitPreference
        self.eligibleWorkingSets = workouts.flatMap { workout -> [WorkoutSet] in
            guard !workout.excludesEntireWorkoutFromProgressionHistory else { return [] }
            let excluded = workout.excludedExerciseIdsForProgressionHistory
            return (setsByWorkout[workout.id] ?? []).filter {
                $0.setType == .working && !excluded.contains($0.exerciseId)
            }
        }
    }
}

protocol InsightRule {
    var ruleId: String { get }
    /// Relative weight for findings the user can directly act on (0...1).
    var actionability: Double { get }
    /// Minimum gap before this rule may fire again for the same subject. Nil
    /// means it may resurface as soon as it's re-detected.
    var minimumRefireInterval: TimeInterval? { get }

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding]

    /// Lower-bar pass used only when the normal pass produced nothing at all.
    /// Progress rules implement this so the feed always has something once
    /// there's history; describing carries far less risk than prescribing, so a
    /// relaxed gate is defensible here and nowhere else.
    func evaluateRelaxed(_ context: InsightAnalysisContext) -> [InsightFinding]
}

extension InsightRule {
    var minimumRefireInterval: TimeInterval? { nil }
    func evaluateRelaxed(_ context: InsightAnalysisContext) -> [InsightFinding] { [] }
}

// MARK: - Engine

@ModelActor
actor InsightsService: InsightsServiceProtocol {

    /// Bump when rule logic changes so existing users get a fresh analysis.
    static let analysisVersion = 3
    /// Ten rules compete for these slots, and the ranking is a fixed weight per
    /// rule, so a narrow feed doesn't rotate — it locks. At three, the top two
    /// diagnostics and the top progress rule won every week and the other seven
    /// rules were unreachable no matter how long someone trained. Widening it
    /// is safe because every rule already gates itself: a finding only exists
    /// once it has cleared its own minimum-effect bar, so there is no pile of
    /// weak findings that the cap was holding back.
    static let maxVisibleInsights = 6
    static let snoozeDays = 21
    /// At most half the feed may be diagnostic, so it is never all criticism.
    /// v1 had no such cap and a catalog that was entirely diagnostic, which is
    /// most of why it read as a weekly grading. Proportional rather than a
    /// fixed count so widening the feed doesn't widen the criticism with it.
    static let maxDiagnosticInsights = maxVisibleInsights / 2

    private static let lastAnalysisSignatureKey = "insightsLastAnalysisSignature"
    private static let lastFiredKey = "insightsLastFiredByRule"

    /// Clears the analysis cache and refire cooldowns. Both live in
    /// UserDefaults so they survive relaunches, which also means they leak
    /// between tests in a shared process — call this from setUp.
    static func resetPersistedAnalysisState() {
        UserDefaults.standard.removeObject(forKey: lastAnalysisSignatureKey)
        UserDefaults.standard.removeObject(forKey: lastFiredKey)
    }

    static let rules: [any InsightRule] = [
        // Tier 1 — carry the feed
        StrengthTrendInsightRule(),
        ConsistencyInsightRule(),
        DroppedExerciseInsightRule(),
        VolumeRampInsightRule(),
        DeloadReadinessInsightRule(),
        // Existing
        RestSweetSpotInsightRule(),
        TargetAdherenceInsightRule(),
        MuscleBalanceInsightRule(),
        PRPaceInsightRule(),
        RIRCalibrationInsightRule()
    ]

    // MARK: - InsightsServiceProtocol

    @discardableResult
    func refreshIfNeeded() async throws -> Bool {
        let now = Date()
        let signature = try currentDataSignature(referenceDate: now)
        let stored = UserDefaults.standard.string(forKey: Self.lastAnalysisSignatureKey)
        guard signature != stored else { return false }

        try runAnalysis(referenceDate: now)
        UserDefaults.standard.set(signature, forKey: Self.lastAnalysisSignatureKey)
        return true
    }

    func fetchActiveInsights() async throws -> [InsightItem] {
        try activeRecords().map(Self.item(from:))
    }

    func fetchTrainingStatus() async throws -> TrainingStatus {
        try trainingStatus(referenceDate: Date())
    }

    func newInsightCount() async throws -> Int {
        try activeRecords().filter { $0.state == .new }.count
    }

    func markAllSeen() async throws {
        let now = Date()
        var changed = false
        for record in try activeRecords() where record.state == .new {
            record.state = .seen
            record.seenAt = now
            record.updatedAt = now
            changed = true
        }
        if changed {
            try modelContext.save()
        }
    }

    func snooze(insightId: UUID) async throws {
        let descriptor = FetchDescriptor<InsightRecord>(
            predicate: #Predicate { $0.id == insightId }
        )
        guard let record = try modelContext.fetch(descriptor).first else { return }
        let now = Date()
        record.snoozedUntil = Calendar.current.date(byAdding: .day, value: Self.snoozeDays, to: now)
        record.state = .seen
        record.seenAt = record.seenAt ?? now
        record.updatedAt = now
        try modelContext.save()
    }

    func ruleDiagnostics() async throws -> [RuleDiagnostic] {
        try ruleDiagnostics(referenceDate: Date())
    }

    // MARK: - Rule diagnostics

    /// Internal so tests can drive it with a fixed reference date.
    ///
    /// "In the feed" is read from the persisted records rather than by re-running
    /// curation: a second curate pass would disagree with the real feed for any
    /// rule holding a refire cooldown, because the run that put it on screen also
    /// stamped the cooldown that a re-run then trips over.
    func ruleDiagnostics(referenceDate: Date) throws -> [RuleDiagnostic] {
        let context = try buildContext(referenceDate: referenceDate)
        let lastFired = Self.loadLastFired()
        let liveRuleIds = Set(try activeRecords().map(\.ruleId))

        return Self.rules.map { rule in
            let normal = rule.evaluate(context)
            let isShown = liveRuleIds.contains(rule.ruleId)

            // A cooldown only explains silence when the rule actually has a
            // finding being held back.
            let held = normal.first {
                !Self.refireAllowed(
                    $0, rule: rule, lastFired: lastFired, referenceDate: referenceDate
                )
            }
            let refireAvailableAt = held.flatMap { finding -> Date? in
                guard let interval = rule.minimumRefireInterval,
                      let last = lastFired[Self.firedKey(finding)]
                else { return nil }
                return last.addingTimeInterval(interval)
            }

            return RuleDiagnostic(
                ruleId: rule.ruleId,
                actionability: rule.actionability,
                findings: Self.candidates(normal, rule: rule),
                relaxedFindings: Self.candidates(rule.evaluateRelaxed(context), rule: rule),
                survivedCuration: isShown,
                refireAvailableAt: isShown ? nil : refireAvailableAt
            )
        }
    }

    private static func candidates(
        _ findings: [InsightFinding], rule: any InsightRule
    ) -> [RuleDiagnostic.Candidate] {
        findings
            .map { finding in
                RuleDiagnostic.Candidate(
                    subjectName: finding.subjectName,
                    headline: finding.headline,
                    score: finding.effectSize * rule.actionability,
                    effectSize: finding.effectSize,
                    isDiagnostic: finding.tone == .diagnostic
                )
            }
            .sorted { $0.score > $1.score }
    }

    // MARK: - Analysis

    /// Runs the full pipeline against the current store. Internal so tests can
    /// drive it with a fixed reference date.
    func runAnalysis(referenceDate: Date) throws {
        let context = try buildContext(referenceDate: referenceDate)
        var lastFired = Self.loadLastFired()

        func scored(_ evaluate: (any InsightRule) -> [InsightFinding]) -> [Scored] {
            Self.rules.flatMap { rule in
                evaluate(rule)
                    .filter {
                        Self.refireAllowed(
                            $0, rule: rule, lastFired: lastFired, referenceDate: referenceDate
                        )
                    }
                    .map { Scored(finding: $0, score: $0.effectSize * rule.actionability) }
            }
        }

        var curated = Self.curate(scored { $0.evaluate(context) })

        // Positive floor: rather than an empty feed, fall back to a relaxed pass
        // over the rules that describe rather than prescribe. "Your squat is up
        // 6%" needs no confidence interval to be safe to say.
        if curated.isEmpty {
            curated = Self.curate(scored { $0.evaluateRelaxed(context) })
        }

        for entry in curated where Self.ruleFor(entry.finding)?.minimumRefireInterval != nil {
            lastFired[Self.firedKey(entry.finding)] = referenceDate
        }
        Self.saveLastFired(lastFired)

        try persist(curated, referenceDate: referenceDate)
    }

    struct Scored {
        let finding: InsightFinding
        let score: Double
    }

    /// One card per rule, best finding wins, capped feed, diagnostics limited.
    static func curate(_ findings: [Scored]) -> [Scored] {
        var bestPerRule: [String: Scored] = [:]
        for entry in findings {
            if let existing = bestPerRule[entry.finding.ruleId], existing.score >= entry.score {
                continue
            }
            bestPerRule[entry.finding.ruleId] = entry
        }

        var selected: [Scored] = []
        var diagnostics = 0
        // Two passes so a lower-scoring non-diagnostic can still claim the last
        // slot once the diagnostic budget is spent.
        for entry in bestPerRule.values.sorted(by: { $0.score > $1.score }) {
            guard selected.count < maxVisibleInsights else { break }
            if entry.finding.tone == .diagnostic {
                guard diagnostics < maxDiagnosticInsights else { continue }
                diagnostics += 1
            }
            selected.append(entry)
        }
        return selected
    }

    private static func ruleFor(_ finding: InsightFinding) -> (any InsightRule)? {
        rules.first { $0.ruleId == finding.ruleId }
    }

    private static func firedKey(_ finding: InsightFinding) -> String {
        "\(finding.ruleId)|\(finding.subjectId?.uuidString ?? "-")"
    }

    /// Rules with a refire interval stay quiet until it lapses, even when the
    /// finding still holds. Shared with the admin diagnostics so the two can't
    /// disagree about why a rule is silent.
    private static func refireAllowed(
        _ finding: InsightFinding,
        rule: any InsightRule,
        lastFired: [String: Date],
        referenceDate: Date
    ) -> Bool {
        guard let interval = rule.minimumRefireInterval,
              let last = lastFired[firedKey(finding)]
        else { return true }
        return referenceDate.timeIntervalSince(last) >= interval
    }

    /// Refire timestamps live in UserDefaults rather than on InsightRecord:
    /// records are deleted the moment a finding stops holding, so they can't
    /// carry the memory a cooldown needs.
    private static func loadLastFired() -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: lastFiredKey) as? [String: Double] ?? [:]
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func saveLastFired(_ value: [String: Date]) {
        UserDefaults.standard.set(
            value.mapValues { $0.timeIntervalSince1970 }, forKey: lastFiredKey
        )
    }

    private func persist(_ curated: [Scored], referenceDate: Date) throws {
        let existing = try modelContext.fetch(FetchDescriptor<InsightRecord>())
        var liveIds = Set<UUID>()

        for entry in curated {
            let finding = entry.finding
            let match = existing.first {
                $0.ruleId == finding.ruleId && $0.subjectId == finding.subjectId
            }

            if let match {
                // Snoozed insights stay hidden even when re-detected.
                match.score = entry.score
                // Rules with a nil subjectId (muscle balance, for one) match the
                // same record whatever the subject now is, so this has to be
                // refreshed with the rest. Left stale it showed the previous
                // subject's name beside the new subject's headline — "abs" on a
                // card reading "Legs has gone quiet".
                match.subjectName = finding.subjectName
                match.headline = finding.headline
                match.detailText = finding.detailText
                match.methodologyText = finding.methodologyText
                match.chartKind = finding.chartKind
                match.chartLabels = finding.chartLabels
                match.chartValues = finding.chartValues
                match.typicalGapDays = finding.typicalGapDays
                match.generatedAt = referenceDate
                match.updatedAt = referenceDate
                liveIds.insert(match.id)
            } else {
                let record = InsightRecord(
                    ruleId: finding.ruleId,
                    subjectId: finding.subjectId,
                    subjectName: finding.subjectName,
                    score: entry.score,
                    headline: finding.headline,
                    detailText: finding.detailText,
                    methodologyText: finding.methodologyText,
                    chartKind: finding.chartKind,
                    chartLabels: finding.chartLabels,
                    chartValues: finding.chartValues,
                    typicalGapDays: finding.typicalGapDays,
                    generatedAt: referenceDate
                )
                modelContext.insert(record)
                liveIds.insert(record.id)
            }
        }

        // Findings that no longer hold are removed; snoozed records survive
        // until their cooldown lapses so re-detection inside the window stays
        // suppressed.
        for record in existing where !liveIds.contains(record.id) {
            if let snoozedUntil = record.snoozedUntil, snoozedUntil > referenceDate {
                continue
            }
            modelContext.delete(record)
        }

        try modelContext.save()
    }

    // MARK: - Training status

    /// Windows for the status layer.
    ///
    /// A trailing 7 days rather than the calendar week: comparing a partial
    /// calendar week against a full-week average shows every muscle group down
    /// 80% on a Monday, which would teach users to distrust the panel inside a
    /// fortnight. The baseline excludes the trailing window so the comparison
    /// isn't diluted by the thing it's measuring.
    static let statusWindowDays = 7
    static let statusBaselineWeeks = 8
    /// Groups that live in the catalog but aren't muscles. Ranking them next to
    /// chest and back distorts the panel, and "you're neglecting full body"
    /// means nothing.
    static let statusExcludedGroups: Set<String> = ["cardio", "full body"]

    /// Oldest date the status layer reads. History before this affects only how
    /// many baseline weeks are available, which `historyStart` answers on its own.
    static func statusWindowStart(for referenceDate: Date) -> Date? {
        Calendar.current.date(
            byAdding: .day,
            value: -statusWindowDays - statusBaselineWeeks * 7,
            to: referenceDate
        )
    }

    /// Internal so tests can drive it with a fixed reference date.
    func trainingStatus(referenceDate: Date) throws -> TrainingStatus {
        guard let windowStart = Self.statusWindowStart(for: referenceDate) else {
            return TrainingStatus(currentSets: 0, baselineSets: nil, muscles: [], hasData: false)
        }
        let context = try buildStatusContext(referenceDate: referenceDate, windowStart: windowStart)
        return Self.trainingStatus(from: context, historyStart: try earliestLoggedSetDate())
    }

    /// `historyStart` is when the user first logged anything, supplied by callers
    /// whose context is windowed and therefore can't see back that far. Nil means
    /// the context carries the full history and the date is derived from it.
    static func trainingStatus(
        from context: InsightAnalysisContext,
        historyStart: Date? = nil
    ) -> TrainingStatus {
        let calendar = Calendar.current
        let reference = context.referenceDate

        guard let currentStart = calendar.date(
            byAdding: .day, value: -statusWindowDays, to: reference
        ), let baselineStart = statusWindowStart(for: reference) else {
            return TrainingStatus(currentSets: 0, baselineSets: nil, muscles: [], hasData: false)
        }

        var currentByGroup: [String: Int] = [:]
        var baselineByGroup: [String: Int] = [:]
        // Reps and volume ride along in the same pass — the loop already visits
        // every eligible set, so the extra metrics cost accumulators, not work.
        var currentRepsByGroup: [String: Int] = [:]
        var baselineRepsByGroup: [String: Int] = [:]
        var currentVolumeByGroup: [String: Double] = [:]
        var baselineVolumeByGroup: [String: Double] = [:]
        var currentTotal = 0
        var baselineTotal = 0
        var sawAnySet = false
        /// Days of baseline history actually available, so a user six weeks in
        /// gets a fair average rather than one diluted by weeks that never existed.
        var earliestSetDate: Date?

        for set in context.eligibleWorkingSets {
            guard let exercise = context.exercisesById[set.exerciseId],
                  let group = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle),
                  !statusExcludedGroups.contains(group)
            else { continue }

            sawAnySet = true
            earliestSetDate = min(earliestSetDate ?? set.date, set.date)

            // Volume is nil for sets carrying no weight (bodyweight work), which
            // contributes zero here rather than dropping the set from the other
            // two metrics.
            let volume = set.volume ?? 0

            if set.date >= currentStart {
                currentByGroup[group, default: 0] += 1
                currentRepsByGroup[group, default: 0] += set.totalReps
                currentVolumeByGroup[group, default: 0] += volume
                currentTotal += 1
            } else if set.date >= baselineStart {
                baselineByGroup[group, default: 0] += 1
                baselineRepsByGroup[group, default: 0] += set.totalReps
                baselineVolumeByGroup[group, default: 0] += volume
                baselineTotal += 1
            }
        }

        let baselineWeeks = Self.availableBaselineWeeks(
            earliestSetDate: historyStart ?? earliestSetDate,
            currentStart: currentStart,
            baselineStart: baselineStart
        )

        // Every group the user trains, not just the ones they trained this week —
        // a group that got nothing is exactly what the panel exists to show.
        let groups = Set(currentByGroup.keys).union(baselineByGroup.keys)

        let rows = groups.map { group -> MuscleVolumeRow in
            MuscleVolumeRow(
                group: group,
                displayName: ExercisePrimaryGroup.displayName(for: group),
                currentSets: currentByGroup[group] ?? 0,
                baselineSets: baselineWeeks.map { Double(baselineByGroup[group] ?? 0) / $0 },
                currentReps: currentRepsByGroup[group] ?? 0,
                baselineReps: baselineWeeks.map { Double(baselineRepsByGroup[group] ?? 0) / $0 },
                currentVolume: currentVolumeByGroup[group] ?? 0,
                baselineVolume: baselineWeeks.map { (baselineVolumeByGroup[group] ?? 0) / $0 }
            )
        }
        // Rank by baseline, not by current volume: sorting by this week pushes
        // the group you skipped to the bottom, and that group is the entire
        // reason to look at the panel.
        .sorted {
            let left = $0.baselineSets ?? Double($0.currentSets)
            let right = $1.baselineSets ?? Double($1.currentSets)
            if left != right { return left > right }
            if $0.currentSets != $1.currentSets { return $0.currentSets > $1.currentSets }
            return $0.displayName < $1.displayName
        }

        return TrainingStatus(
            currentSets: currentTotal,
            baselineSets: baselineWeeks.map { Double(baselineTotal) / $0 },
            muscles: rows,
            // A lapsed user has data even when the window is empty, and a
            // windowed context can't tell the difference on its own.
            hasData: historyStart != nil || sawAnySet
        )
    }

    /// Whole weeks of baseline history available, or nil when there isn't enough
    /// to compare against. Below this the UI shows counts with no comparison
    /// rather than a baseline built from one thin week.
    static let minimumBaselineWeeks = 3.0

    private static func availableBaselineWeeks(
        earliestSetDate: Date?,
        currentStart: Date,
        baselineStart: Date
    ) -> Double? {
        guard let earliestSetDate else { return nil }
        let effectiveStart = max(earliestSetDate, baselineStart)
        let days = currentStart.timeIntervalSince(effectiveStart) / 86_400
        let weeks = days / 7
        guard weeks >= minimumBaselineWeeks else { return nil }
        return weeks
    }

    /// Context narrowed to the nine weeks the status layer actually reads.
    ///
    /// Only valid as input to `trainingStatus(from:historyStart:)` — it holds no
    /// observations and no history before `windowStart`, so rules evaluated
    /// against it would silently see a truncated store.
    ///
    /// The narrowing is the whole point: fetching every set ever logged cost
    /// more than everything else the Home screen does put together, and grew
    /// with every month the user kept training.
    private func buildStatusContext(
        referenceDate: Date,
        windowStart: Date
    ) throws -> InsightAnalysisContext {
        let workouts = try modelContext.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.date >= windowStart },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )).filter { $0.status == .completed }
        let workoutIds = Set(workouts.map(\.id))

        // Unsorted: the status counts sets and never reads their order.
        let sets = try modelContext.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.completed == true && $0.date >= windowStart }
        )).filter { $0.hasData && workoutIds.contains($0.workoutId) }

        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        let profile = try modelContext.fetch(FetchDescriptor<HealthProfile>()).first

        return InsightAnalysisContext(
            workouts: workouts,
            setsByWorkout: Dictionary(grouping: sets, by: \.workoutId),
            exercisesById: Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) }),
            observations: [],
            referenceDate: referenceDate,
            unitPreference: profile?.unitPreference ?? .metric
        )
    }

    /// When the user first logged a set. Cheap (one indexed row) and needed
    /// separately because the windowed status context cannot see past its own
    /// window, while how much history exists decides the baseline average.
    private func earliestLoggedSetDate() throws -> Date? {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.completed == true },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.date
    }

    private func buildContext(referenceDate: Date) throws -> InsightAnalysisContext {
        let workoutDescriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let workouts = try modelContext.fetch(workoutDescriptor)
            .filter { $0.status == .completed }
        let workoutIds = Set(workouts.map(\.id))

        let setDescriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.completed == true },
            sortBy: [SortDescriptor(\.orderInWorkout)]
        )
        let sets = try modelContext.fetch(setDescriptor)
            .filter { $0.hasData && workoutIds.contains($0.workoutId) }

        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())

        let observationDescriptor = FetchDescriptor<FatigueObservation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let observations = try modelContext.fetch(observationDescriptor)

        let profile = try modelContext.fetch(FetchDescriptor<HealthProfile>()).first

        return InsightAnalysisContext(
            workouts: workouts,
            setsByWorkout: Dictionary(grouping: sets, by: \.workoutId),
            exercisesById: Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) }),
            observations: observations,
            referenceDate: referenceDate,
            unitPreference: profile?.unitPreference ?? .metric
        )
    }

    // MARK: - Helpers

    private func activeRecords() throws -> [InsightRecord] {
        let now = Date()
        let records = try modelContext.fetch(FetchDescriptor<InsightRecord>())
        return records
            .filter { $0.snoozedUntil == nil || $0.snoozedUntil! <= now }
            .sorted {
                if ($0.state == .new) != ($1.state == .new) {
                    return $0.state == .new
                }
                return $0.score > $1.score
            }
    }

    /// Cheap change detector: completed workout count + latest completion date
    /// + current day + analysis version. Avoids re-running the pipeline on every
    /// Home load.
    ///
    /// The day component matters: every rule evaluates over a rolling window
    /// relative to `referenceDate`, and those windows move as time passes, not
    /// only when a workout is logged. Without it the analysis freezes the moment
    /// the user stops training — a stale muscle-balance card is easy to miss,
    /// but a stale "last 7 days" figure on Home is not.
    ///
    /// Internal so tests can drive it with a fixed reference date.
    func currentDataSignature(referenceDate: Date) throws -> String {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let completed = try modelContext.fetch(descriptor)
            .filter { $0.status == .completed }
        let latest = completed.first?.date.timeIntervalSince1970 ?? 0
        let day = Calendar.current.startOfDay(for: referenceDate).timeIntervalSince1970
        return "v\(Self.analysisVersion)-\(completed.count)-\(latest)-\(day)"
    }

    private static func item(from record: InsightRecord) -> InsightItem {
        InsightItem(
            id: record.id,
            ruleId: record.ruleId,
            subjectName: record.subjectName,
            headline: record.headline,
            detailText: record.detailText,
            methodologyText: record.methodologyText,
            chartKind: record.chartKind,
            chartLabels: record.chartLabels,
            chartValues: record.chartValues,
            typicalGapDays: record.typicalGapDays,
            isNew: record.state == .new,
            generatedAt: record.generatedAt
        )
    }
}
