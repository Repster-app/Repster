// InsightRules+Progress.swift
// The rules that carry the feed: high coverage, renewable, and able to fire in
// both directions.
//
// v1's whole catalog was diagnostic — every rule told the user something was
// wrong. These exist so the feed is worth opening on a week when nothing is.

import Foundation

// MARK: - Strength trend

/// Per-exercise estimated-1RM direction over the medium term.
///
/// The thing users most want to know and can least see for themselves. Computed
/// from stored per-set `e1RM` (populated by SetService on save) rather than
/// `ExerciseStats.estimated1RMTrendSlope`, because the copy needs the endpoints
/// — "142 to 151 kg" — not just a gradient.
struct StrengthTrendInsightRule: InsightRule {
    let ruleId = "strengthTrend"
    let actionability = 0.5

    static let windowDays = 56
    static let minimumSessions = 3
    static let minimumSpanDays = 42.0
    /// Below this the movement is indistinguishable from day-to-day noise.
    static let minimumChangeFraction = 0.03
    static let relaxedMinimumChangeFraction = 0.015
    /// A long flat stretch is worth saying out loud; a short one isn't.
    static let staleSpanDays = 70.0

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        findings(context, minimumChange: Self.minimumChangeFraction)
    }

    func evaluateRelaxed(_ context: InsightAnalysisContext) -> [InsightFinding] {
        findings(context, minimumChange: Self.relaxedMinimumChangeFraction)
    }

    private func findings(
        _ context: InsightAnalysisContext, minimumChange: Double
    ) -> [InsightFinding] {
        guard let windowStart = Calendar.current.date(
            byAdding: .day, value: -Self.windowDays, to: context.referenceDate
        ) else { return [] }

        var results: [InsightFinding] = []

        for (exerciseId, dailyBests) in Self.dailyBestE1RM(context, since: windowStart) {
            guard dailyBests.count >= Self.minimumSessions,
                  let exercise = context.exercisesById[exerciseId],
                  let first = dailyBests.first, let last = dailyBests.last
            else { continue }

            let spanDays = last.day.timeIntervalSince(first.day) / 86_400
            guard spanDays >= Self.minimumSpanDays else { continue }

            // Compare window halves rather than raw endpoints so one heavy day
            // can't manufacture a trend.
            let midpoint = dailyBests.count / 2
            let earlyMean = Self.mean(dailyBests.prefix(max(1, midpoint)).map(\.value))
            let lateMean = Self.mean(dailyBests.suffix(max(1, dailyBests.count - midpoint)).map(\.value))
            guard earlyMean > 0 else { continue }

            let change = (lateMean - earlyMean) / earlyMean
            let weeks = Int((spanDays / 7).rounded())

            if change >= minimumChange {
                results.append(InsightFinding(
                    ruleId: ruleId,
                    subjectId: exerciseId,
                    subjectName: exercise.name,
                    headline: "Your \(exercise.name.lowercased()) is up \(Int((change * 100).rounded()))% over \(weeks) weeks",
                    detailText: "Estimated 1RM has climbed from \(Self.weight(earlyMean, context)) to \(Self.weight(lateMean, context)). Whatever you're doing on this lift is working.",
                    methodologyText: "Daily best estimated 1RM, \(dailyBests.count) sessions",
                    chartKind: .series,
                    chartLabels: dailyBests.map { _ in "" },
                    chartValues: dailyBests.map(\.value),
                    effectSize: min(1.0, change / 0.12),
                    tone: .progress
                ))
            } else if change <= -minimumChange {
                results.append(InsightFinding(
                    ruleId: ruleId,
                    subjectId: exerciseId,
                    subjectName: exercise.name,
                    headline: "Your \(exercise.name.lowercased()) has drifted down",
                    detailText: "Estimated 1RM has slipped from \(Self.weight(earlyMean, context)) to \(Self.weight(lateMean, context)) over \(weeks) weeks. A lighter week or a change of rep range often turns this around.",
                    methodologyText: "Daily best estimated 1RM, \(dailyBests.count) sessions",
                    chartKind: .series,
                    chartLabels: dailyBests.map { _ in "" },
                    chartValues: dailyBests.map(\.value),
                    effectSize: min(1.0, abs(change) / 0.12),
                    tone: .diagnostic
                ))
            } else if spanDays >= Self.staleSpanDays {
                results.append(InsightFinding(
                    ruleId: ruleId,
                    subjectId: exerciseId,
                    subjectName: exercise.name,
                    headline: "\(exercise.name) has been flat for \(weeks) weeks",
                    detailText: "Estimated 1RM has stayed around \(Self.weight(lateMean, context)) since \(Self.monthName(first.day)). A different rep range often unsticks a lift this settled.",
                    methodologyText: "Daily best estimated 1RM, \(dailyBests.count) sessions",
                    chartKind: .series,
                    chartLabels: dailyBests.map { _ in "" },
                    chartValues: dailyBests.map(\.value),
                    effectSize: 0.35,
                    tone: .neutral
                ))
            }
        }

        return results
    }

    /// Best e1RM per calendar day per exercise, oldest first.
    static func dailyBestE1RM(
        _ context: InsightAnalysisContext, since: Date
    ) -> [UUID: [(day: Date, value: Double)]] {
        let calendar = Calendar.current
        var bestByExerciseDay: [UUID: [Date: Double]] = [:]

        for set in context.eligibleWorkingSets where set.date >= since {
            guard let e1RM = set.e1RM, e1RM > 0 else { continue }
            let day = calendar.startOfDay(for: set.date)
            let existing = bestByExerciseDay[set.exerciseId]?[day] ?? 0
            bestByExerciseDay[set.exerciseId, default: [:]][day] = max(existing, e1RM)
        }

        return bestByExerciseDay.mapValues { days in
            days.sorted { $0.key < $1.key }.map { (day: $0.key, value: $0.value) }
        }
    }

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    static func weight(_ kg: Double, _ context: InsightAnalysisContext) -> String {
        UnitConversion.formatWeightLabel(kg, unitPreference: context.unitPreference)
    }

    static func monthName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }
}

// MARK: - Consistency

/// Session frequency against the user's own norm.
///
/// Needs only workout dates, so it covers every user and works from about week
/// three. This is the cold-start card — the one thing the feed can say before
/// any lift has enough history to analyse.
struct ConsistencyInsightRule: InsightRule {
    let ruleId = "consistency"
    let actionability = 0.4

    static let windowWeeks = 12
    static let minimumWeeks = 3
    /// A run has to be this long before it's a streak rather than a fortnight.
    static let minimumRunWeeks = 3

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        guard let weekly = Self.weeklySessionCounts(context), weekly.count >= Self.minimumWeeks
        else { return [] }

        // Exclude the in-progress week from run detection: it's incomplete by
        // definition and would break every streak on a Monday.
        let complete = Array(weekly.dropLast())
        guard complete.count >= Self.minimumWeeks else { return [] }

        let median = Self.median(complete.map(\.count))
        guard median > 0 else { return [] }

        var runLength = 0
        for week in complete.reversed() {
            guard week.count >= median else { break }
            runLength += 1
        }

        guard runLength >= Self.minimumRunWeeks else { return [] }

        let frequency = complete.suffix(runLength).map(\.count)
        let runFrequency = Self.median(frequency)
        let priorMedian = complete.count > runLength
            ? Self.median(complete.dropLast(runLength).map(\.count))
            : median
        // Only interesting if the run is actually above where they were.
        guard runFrequency > priorMedian else { return [] }

        return [InsightFinding(
            ruleId: ruleId,
            subjectId: nil,
            subjectName: nil,
            headline: "\(runLength) straight weeks at \(runFrequency) session\(runFrequency == 1 ? "" : "s")",
            detailText: "Before that you were averaging about \(priorMedian) a week. Frequency is the part of training that compounds quietest.",
            methodologyText: "Completed workouts per week, last \(complete.count) weeks",
            chartKind: .column,
            chartLabels: complete.map { _ in "" },
            chartValues: complete.map { Double($0.count) },
            effectSize: min(1.0, Double(runLength) / 8.0 + 0.3),
            tone: .progress
        )]
    }

    func evaluateRelaxed(_ context: InsightAnalysisContext) -> [InsightFinding] {
        guard let weekly = Self.weeklySessionCounts(context), weekly.count >= Self.minimumWeeks
        else { return [] }
        let complete = Array(weekly.dropLast())
        guard complete.count >= Self.minimumWeeks else { return [] }

        let median = Self.median(complete.map(\.count))
        guard median > 0 else { return [] }
        let total = complete.reduce(0) { $0 + $1.count }

        return [InsightFinding(
            ruleId: ruleId,
            subjectId: nil,
            subjectName: nil,
            headline: "You're training about \(median) time\(median == 1 ? "" : "s") a week",
            detailText: "\(total) sessions over the last \(complete.count) weeks. That's the baseline everything else here is measured against.",
            methodologyText: "Completed workouts per week, last \(complete.count) weeks",
            chartKind: .column,
            chartLabels: complete.map { _ in "" },
            chartValues: complete.map { Double($0.count) },
            effectSize: 0.3,
            tone: .neutral
        )]
    }

    /// Sessions per week, oldest first, including the in-progress week last.
    static func weeklySessionCounts(
        _ context: InsightAnalysisContext
    ) -> [(weekStart: Date, count: Int)]? {
        let calendar = Calendar.current
        guard let windowStart = calendar.date(
            byAdding: .weekOfYear, value: -windowWeeks, to: context.referenceDate
        ) else { return nil }

        let dates = context.workouts
            .filter { $0.date >= windowStart }
            .map(\.date)
        guard !dates.isEmpty else { return nil }

        var counts: [Date: Int] = [:]
        for date in dates {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            else { continue }
            counts[week, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }.map { (weekStart: $0.key, count: $0.value) }
    }

    static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

// MARK: - Dropped exercise

/// An exercise the user trained regularly and then quietly stopped.
///
/// Invisible to the user by construction — nobody notices the absence of
/// something — and actionable either way: put it back, or take it out of the
/// template so it stops looking like a gap.
struct DroppedExerciseInsightRule: InsightRule {
    let ruleId = "droppedExercise"
    let actionability = 0.85

    static let minimumSessions = 8
    static let gapMultiplier = 3.0
    static let minimumGapDays = 21.0
    /// Past this the exercise reads as retired rather than dropped, and saying
    /// so months later is just noise.
    static let maximumGapDays = 120.0

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        var sessionDatesByExercise: [UUID: Set<Date>] = [:]
        let calendar = Calendar.current

        for set in context.eligibleWorkingSets {
            sessionDatesByExercise[set.exerciseId, default: []]
                .insert(calendar.startOfDay(for: set.date))
        }

        var findings: [InsightFinding] = []

        for (exerciseId, days) in sessionDatesByExercise {
            guard days.count >= Self.minimumSessions,
                  let exercise = context.exercisesById[exerciseId]
            else { continue }

            let sorted = days.sorted()
            guard let last = sorted.last else { continue }

            let gaps = zip(sorted, sorted.dropFirst()).map {
                $1.timeIntervalSince($0) / 86_400
            }
            guard !gaps.isEmpty else { continue }
            let medianGap = gaps.sorted()[gaps.count / 2]
            guard medianGap > 0 else { continue }

            let currentGap = context.referenceDate.timeIntervalSince(last) / 86_400
            guard currentGap >= max(Self.minimumGapDays, medianGap * Self.gapMultiplier),
                  currentGap <= Self.maximumGapDays
            else { continue }

            findings.append(InsightFinding(
                ruleId: ruleId,
                subjectId: exerciseId,
                subjectName: exercise.name,
                headline: "You've quietly stopped doing \(exercise.name.lowercased())",
                detailText: String(
                    format: "You trained it %d times, about every %.0f days, then nothing for %.0f. Worth adding back — or dropping from your template so it stops looking like a gap.",
                    days.count, medianGap, currentGap
                ),
                methodologyText: "Last performed \(Self.dayLabel(last))",
                chartKind: .timeline,
                chartLabels: sorted.suffix(8).map { _ in "" },
                chartValues: sorted.suffix(8).map { $0.timeIntervalSince1970 },
                effectSize: min(1.0, currentGap / (medianGap * 8)),
                tone: .diagnostic
            ))
        }

        return findings
    }

    static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }
}

// MARK: - Volume ramp

/// Weekly working-set count against the user's own recent baseline.
///
/// Fires in both directions. A fast ramp is worth flagging because that's where
/// niggles start; a sustained drop is worth flagging because it's usually
/// unintentional.
struct VolumeRampInsightRule: InsightRule {
    let ruleId = "volumeRamp"
    let actionability = 0.5

    static let windowWeeks = 8
    static let minimumWeeks = 6
    static let minimumChangeFraction = 0.25
    static let sustainedWeeks = 2

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        let calendar = Calendar.current
        guard let windowStart = calendar.date(
            byAdding: .weekOfYear, value: -Self.windowWeeks, to: context.referenceDate
        ) else { return [] }

        var byWeek: [Date: Int] = [:]
        for set in context.eligibleWorkingSets where set.date >= windowStart {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: set.date)?.start
            else { continue }
            byWeek[week, default: 0] += 1
        }

        let weeks = byWeek.sorted { $0.key < $1.key }.map { (week: $0.key, sets: $0.value) }
        guard weeks.count >= Self.minimumWeeks else { return [] }

        // Drop the in-progress week — it's always partial and would read as a crash.
        let complete = Array(weeks.dropLast())
        guard complete.count >= Self.minimumWeeks - 1 else { return [] }

        let recent = complete.suffix(Self.sustainedWeeks)
        let prior = complete.dropLast(Self.sustainedWeeks)
        guard !prior.isEmpty else { return [] }

        let recentMean = Double(recent.reduce(0) { $0 + $1.sets }) / Double(recent.count)
        let priorMean = Double(prior.reduce(0) { $0 + $1.sets }) / Double(prior.count)
        guard priorMean > 0 else { return [] }

        let change = (recentMean - priorMean) / priorMean
        guard abs(change) >= Self.minimumChangeFraction else { return [] }

        let percent = Int((abs(change) * 100).rounded())
        let climbing = change > 0

        return [InsightFinding(
            ruleId: ruleId,
            subjectId: nil,
            subjectName: nil,
            headline: climbing
                ? "Your weekly sets are up \(percent)%"
                : "Your weekly sets are down \(percent)%",
            // Names both windows rather than saying "from about N a week",
            // which read as a claim about the user's normal and collided with
            // the status card — the one surface that owns "your usual".
            detailText: climbing
                ? "The last \(recent.count) weeks averaged \(Int(recentMean.rounded())) sets against \(Int(priorMean.rounded())) over the \(prior.count) before. Fast ramps are where niggles usually start — holding here for a week before adding more is rarely wasted."
                : "The last \(recent.count) weeks averaged \(Int(recentMean.rounded())) sets against \(Int(priorMean.rounded())) over the \(prior.count) before. If that wasn't deliberate, it's the kind of drift that's easier to correct early.",
            methodologyText: "Working sets per week, last \(complete.count) weeks",
            chartKind: .column,
            chartLabels: complete.map { _ in "" },
            chartValues: complete.map { Double($0.sets) },
            effectSize: min(1.0, abs(change) / 0.6),
            tone: climbing ? .neutral : .diagnostic
        )]
    }
}
