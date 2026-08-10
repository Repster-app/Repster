// InsightRules+Readiness.swift
// Accumulated-fatigue detection.
//
// This is the rule where being wrong costs the most: "the app told me to
// deload" is a claim users act on and judge the app for. Every threshold here
// is deliberately conservative, the language suggests rather than instructs,
// and the rule can only speak once every three weeks.

import Foundation

struct DeloadReadinessInsightRule: InsightRule {
    let ruleId = "deloadReadiness"
    let actionability = 0.8

    /// Once every three weeks at most. Without this the rule could reappear the
    /// moment it's re-detected, which would turn a serious signal into nagging.
    let minimumRefireInterval: TimeInterval? = 21 * 86_400

    // Data sufficiency — a hard floor, never relaxed.
    static let minimumHistoryDays = 42
    static let minimumSessions = 12

    // Signal 1: performance regression. Universal — per-set e1RM is populated
    // for every user, unlike FatigueObservation which needs Smart Suggestions.
    static let recentWindowDays = 14
    static let priorWindowDays = 42
    static let minimumRegressingExercises = 3
    static let minimumRegressionFraction = 0.03

    // Signal 2: corroboration.
    static let minimumErrorShift = 0.04
    static let minimumRatedSessions = 4
    static let minimumEffortShift = 1.0

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        let calendar = Calendar.current
        guard let recentStart = calendar.date(
                byAdding: .day, value: -Self.recentWindowDays, to: context.referenceDate
              ),
              let priorStart = calendar.date(
                byAdding: .day, value: -Self.priorWindowDays, to: recentStart
              )
        else { return [] }

        // MARK: Data sufficiency
        let completed = context.workouts
        guard completed.count >= Self.minimumSessions,
              let earliest = completed.map(\.date).min(),
              context.referenceDate.timeIntervalSince(earliest) / 86_400 >= Double(Self.minimumHistoryDays)
        else { return [] }

        // MARK: Guard — volume must not have dropped
        //
        // Without this the rule detects a week off and calls it fatigue, which
        // is the single most embarrassing way it could be wrong.
        let recentSets = context.eligibleWorkingSets.filter { $0.date >= recentStart }.count
        let priorSets = context.eligibleWorkingSets
            .filter { $0.date >= priorStart && $0.date < recentStart }.count
        let priorWeeklyRate = Double(priorSets) / (Double(Self.priorWindowDays) / 7)
        let recentWeeklyRate = Double(recentSets) / (Double(Self.recentWindowDays) / 7)
        guard priorWeeklyRate > 0, recentWeeklyRate >= priorWeeklyRate * 0.9 else { return [] }

        // MARK: Signal 1 — session-best e1RM regression across exercises
        let regressions = Self.regressingExercises(
            context, recentStart: recentStart, priorStart: priorStart
        )
        guard regressions.count >= Self.minimumRegressingExercises else { return [] }

        // MARK: Signal 2 — corroboration from prediction error or effort
        let errorShift = Self.normalizedErrorShift(context, recentStart: recentStart)
        let effortShift = Self.effortShift(context, recentStart: recentStart, priorStart: priorStart)

        let corroboratedByError = (errorShift ?? 0) >= Self.minimumErrorShift
        let corroboratedByEffort = (effortShift ?? 0) >= Self.minimumEffortShift
        guard corroboratedByError || corroboratedByEffort else { return [] }

        let meanDrop = regressions.map(\.drop).reduce(0, +) / Double(regressions.count)
        let low = Int((regressions.map(\.drop).min() ?? 0) * 100)
        let high = Int((regressions.map(\.drop).max() ?? 0) * 100)

        let corroboration = corroboratedByEffort
            ? "while your effort ratings climbed"
            : "while coming in under predicted output"

        return [InsightFinding(
            ruleId: ruleId,
            subjectId: nil,
            subjectName: nil,
            headline: "Your sessions are landing under your usual output",
            detailText: "\(regressions.count) exercises came in \(low)–\(high)% below their recent norm over the last two weeks, \(corroboration). Your volume hasn't dropped, so this looks like accumulated fatigue rather than a lighter patch. An easier week often resets it.",
            methodologyText: "\(regressions.count) exercises compared against the previous \(Self.priorWindowDays / 7) weeks",
            chartKind: .series,
            chartLabels: regressions.prefix(6).map(\.name),
            // Negative values: the card draws a signed series around zero.
            chartValues: regressions.prefix(6).map { -$0.drop * 100 },
            effectSize: min(1.0, meanDrop / 0.10),
            tone: .diagnostic
        )]
    }

    // MARK: - Signals

    /// Exercises whose best e1RM in the recent window sits materially below
    /// their best in the prior window. Session-best rather than per-set, so one
    /// bad set doesn't count as a regression.
    static func regressingExercises(
        _ context: InsightAnalysisContext, recentStart: Date, priorStart: Date
    ) -> [(name: String, drop: Double)] {
        var recentBest: [UUID: Double] = [:]
        var priorBest: [UUID: Double] = [:]

        for set in context.eligibleWorkingSets {
            guard let e1RM = set.e1RM, e1RM > 0 else { continue }
            if set.date >= recentStart {
                recentBest[set.exerciseId] = max(recentBest[set.exerciseId] ?? 0, e1RM)
            } else if set.date >= priorStart {
                priorBest[set.exerciseId] = max(priorBest[set.exerciseId] ?? 0, e1RM)
            }
        }

        var results: [(name: String, drop: Double)] = []
        for (exerciseId, recent) in recentBest {
            guard let prior = priorBest[exerciseId], prior > 0,
                  let exercise = context.exercisesById[exerciseId]
            else { continue }
            let drop = (prior - recent) / prior
            guard drop >= minimumRegressionFraction else { continue }
            results.append((name: exercise.name, drop: drop))
        }
        return results.sorted { $0.drop > $1.drop }
    }

    /// How far the fatigue model's median error moved in the positive direction
    /// (user underperforming prediction). Nil when the user has no
    /// observations — Smart Suggestions has to be on for these to exist, which
    /// is why this is corroboration and not the primary detector.
    static func normalizedErrorShift(
        _ context: InsightAnalysisContext, recentStart: Date
    ) -> Double? {
        let recent = context.observations.filter { $0.createdAt >= recentStart }
        let prior = context.observations.filter { $0.createdAt < recentStart }
        guard recent.count >= 8, prior.count >= 8 else { return nil }
        return median(recent.map(\.normalizedError)) - median(prior.map(\.normalizedError))
    }

    /// Change in median session RPE. Optional on the summary sheet, so plenty
    /// of users will never supply it.
    static func effortShift(
        _ context: InsightAnalysisContext, recentStart: Date, priorStart: Date
    ) -> Double? {
        let recent = context.workouts
            .filter { $0.date >= recentStart }
            .compactMap(\.perceivedEffort)
        let prior = context.workouts
            .filter { $0.date >= priorStart && $0.date < recentStart }
            .compactMap(\.perceivedEffort)
        guard recent.count >= minimumRatedSessions, prior.count >= minimumRatedSessions
        else { return nil }
        return median(recent) - median(prior)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
