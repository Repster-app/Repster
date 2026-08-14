// InsightRules.swift
// The launch rule set for InsightsService. Every rule gates itself on data
// sufficiency and a minimum effect size — returning [] is the normal outcome.

import Foundation

// MARK: - Rest sweet spot

/// Compares rep performance after short vs. long rests at the user's most
/// common working weight per exercise. restDurationSeconds on set N is the
/// timed rest taken after completing set N, so it precedes set N+1.
struct RestSweetSpotInsightRule: InsightRule {
    let ruleId = "restSweetSpot"
    let actionability = 1.0

    static let minimumPairs = 12
    static let minimumGroupSize = 5
    static let minimumRepEffect = 1.0

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        struct RestRepPair {
            let restSeconds: Int
            let reps: Int
        }

        var weightedPairs: [UUID: [(pair: RestRepPair, weight: Double)]] = [:]

        for workout in context.workouts {
            guard !workout.excludesEntireWorkoutFromProgressionHistory else { continue }
            let excluded = workout.excludedExerciseIdsForProgressionHistory
            let sets = (context.setsByWorkout[workout.id] ?? [])
                .filter { $0.setType == .working && !excluded.contains($0.exerciseId) }
            let byExercise = Dictionary(grouping: sets, by: \.exerciseId)

            for (exerciseId, exerciseSets) in byExercise {
                let ordered = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }
                for (previous, current) in zip(ordered, ordered.dropFirst()) {
                    guard let rest = previous.restDurationSeconds,
                          rest > 0,
                          let reps = current.reps,
                          let weight = current.weight,
                          weight > 0
                    else { continue }
                    weightedPairs[exerciseId, default: []].append(
                        (RestRepPair(restSeconds: rest, reps: reps), weight)
                    )
                }
            }
        }

        var findings: [InsightFinding] = []

        for (exerciseId, all) in weightedPairs {
            guard let exercise = context.exercisesById[exerciseId] else { continue }

            // Control for load: only compare sets at the modal working weight.
            let weightCounts = Dictionary(grouping: all, by: { $0.weight })
            guard let modal = weightCounts.max(by: { $0.value.count < $1.value.count })
            else { continue }
            let pairs = modal.value.map(\.pair)
            guard pairs.count >= Self.minimumPairs else { continue }

            let sortedRests = pairs.map(\.restSeconds).sorted()
            let medianRest = sortedRests[sortedRests.count / 2]
            let short = pairs.filter { $0.restSeconds < medianRest }
            let long = pairs.filter { $0.restSeconds >= medianRest }
            guard short.count >= Self.minimumGroupSize,
                  long.count >= Self.minimumGroupSize
            else { continue }

            let shortMean = Double(short.map(\.reps).reduce(0, +)) / Double(short.count)
            let longMean = Double(long.map(\.reps).reduce(0, +)) / Double(long.count)
            let effect = longMean - shortMean
            guard effect >= Self.minimumRepEffect else { continue }

            let shortRestMean = short.map(\.restSeconds).reduce(0, +) / short.count
            let longRestMean = long.map(\.restSeconds).reduce(0, +) / long.count

            findings.append(InsightFinding(
                ruleId: ruleId,
                subjectId: exerciseId,
                subjectName: exercise.name,
                headline: "Longer rest is buying you reps on \(exercise.name)",
                detailText: String(
                    format: "At %@, sets after ~%@ of rest average %.1f reps, versus %.1f after ~%@. If you usually cut rest short, the extra time is doing real work.",
                    Self.formatWeight(modal.key, context: context),
                    Self.formatRest(longRestMean),
                    longMean,
                    shortMean,
                    Self.formatRest(shortRestMean)
                ),
                methodologyText: "\(pairs.count) timed rests at \(Self.formatWeight(modal.key, context: context))",
                chartKind: .comparison,
                chartLabels: ["~\(Self.formatRest(shortRestMean))", "~\(Self.formatRest(longRestMean))"],
                chartValues: [shortMean, longMean],
                effectSize: min(1.0, effect / 3.0),
                tone: .diagnostic
            ))
        }

        return findings
    }

    static func formatRest(_ seconds: Int) -> String {
        if seconds < 90 { return "\(seconds)s" }
        let minutes = Double(seconds) / 60.0
        return String(format: "%.1f min", minutes)
    }

    static func formatWeight(_ kg: Double, context: InsightAnalysisContext) -> String {
        UnitConversion.formatWeightLabel(kg, unitPreference: context.unitPreference)
    }
}

// MARK: - Target adherence

/// Checks how often working sets land inside their target rep range over the
/// last four weeks.
struct TargetAdherenceInsightRule: InsightRule {
    let ruleId = "targetAdherence"
    let actionability = 0.9

    static let windowDays = 28
    static let minimumSets = 12
    static let lowHitRate = 0.5

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        guard let windowStart = Calendar.current.date(
            byAdding: .day, value: -Self.windowDays, to: context.referenceDate
        ) else { return [] }

        var hits = 0
        var below = 0
        var above = 0

        for set in context.eligibleWorkingSets where set.date >= windowStart {
            let bounds = set.preferredTargetRepBounds
            guard bounds.min != nil || bounds.max != nil else { continue }
            let reps = set.prReps
            guard reps > 0 else { continue }

            if let min = bounds.min, reps < min {
                below += 1
            } else if let max = bounds.max, reps > max {
                above += 1
            } else {
                hits += 1
            }
        }

        let total = hits + below + above
        guard total >= Self.minimumSets else { return [] }
        let hitRate = Double(hits) / Double(total)

        if hitRate < Self.lowHitRate {
            let missesBelow = below >= above
            return [InsightFinding(
                ruleId: ruleId,
                subjectId: nil,
                subjectName: nil,
                headline: missesBelow
                    ? "Your rep targets are running ahead of you"
                    : "You keep overshooting your rep targets",
                detailText: missesBelow
                    ? "Only \(Int(hitRate * 100))% of your recent sets reached their target rep range. Pulling targets down a notch (or weights back ~5%) puts progress back within reach."
                    : "Only \(Int(hitRate * 100))% of your recent sets stayed inside their target range — most went over. Your targets look too easy for where you are now.",
                methodologyText: "\(total) targeted sets over \(Self.windowDays) days",
                chartKind: .proportion,
                chartLabels: ["below", "in range", "above"],
                chartValues: [Double(below), Double(hits), Double(above)],
                effectSize: min(1.0, (Self.lowHitRate - hitRate) / Self.lowHitRate + 0.4),
                tone: .diagnostic
            )]
        }

        return []
    }
}

// MARK: - Muscle balance

/// Flags muscle groups the user historically trains that have fallen far
/// behind the rest over the last two weeks.
struct MuscleBalanceInsightRule: InsightRule {
    let ruleId = "muscleBalance"
    let actionability = 0.8

    static let recentWindowDays = 14
    static let historyWindowDays = 60
    static let minimumGroups = 3
    static let minimumMedianSets = 6
    static let neglectRatio = 1.0 / 3.0

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        let calendar = Calendar.current
        guard let recentStart = calendar.date(
            byAdding: .day, value: -Self.recentWindowDays, to: context.referenceDate
        ), let historyStart = calendar.date(
            byAdding: .day, value: -Self.historyWindowDays, to: context.referenceDate
        ) else { return [] }

        var recentSets: [String: Int] = [:]
        var historySets: [String: Int] = [:]

        for set in context.eligibleWorkingSets where set.date >= historyStart {
            guard let exercise = context.exercisesById[set.exerciseId],
                  let group = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle)
            else { continue }
            historySets[group, default: 0] += 1
            if set.date >= recentStart {
                recentSets[group, default: 0] += 1
            }
        }

        let trainedGroups = historySets.filter { $0.value >= 4 }.map(\.key)
        guard trainedGroups.count >= Self.minimumGroups else { return [] }

        let recentCounts = trainedGroups.map { recentSets[$0] ?? 0 }.sorted()
        let median = recentCounts[recentCounts.count / 2]
        guard median >= Self.minimumMedianSets else { return [] }

        let threshold = Double(median) * Self.neglectRatio
        let neglected = trainedGroups
            .map { (group: $0, count: recentSets[$0] ?? 0) }
            .filter { Double($0.count) < threshold }
            .sorted { $0.count < $1.count }

        guard let worst = neglected.first else { return [] }

        // The comparison groups, stated as the range they actually span. Saying
        // "got \(median)+ each" claimed a floor the median doesn't provide — a
        // card reading "7+ each" beside a shoulders row showing 5 is just wrong.
        let neglectedGroups = Set(neglected.map(\.group))
        let comparisonCounts = trainedGroups
            .filter { !neglectedGroups.contains($0) }
            .map { recentSets[$0] ?? 0 }
            .sorted()
        let comparisonSummary: String = {
            guard let low = comparisonCounts.first, let high = comparisonCounts.last else {
                return "\(median)"
            }
            return low == high ? "\(low)" : "\(low)–\(high)"
        }()

        let sortedGroups = trainedGroups.sorted {
            (recentSets[$0] ?? 0) > (recentSets[$1] ?? 0)
        }

        return [InsightFinding(
            ruleId: ruleId,
            subjectId: nil,
            subjectName: worst.group,
            headline: worst.count == 0
                ? "\(worst.group.capitalized) has gone quiet"
                : "\(worst.group.capitalized) is falling behind",
            detailText: worst.count == 0
                ? "No \(worst.group) sets in the last \(Self.recentWindowDays) days, while your other muscle groups got \(comparisonSummary). One focused session closes the gap."
                : "Only \(worst.count) \(worst.group) sets in the last \(Self.recentWindowDays) days versus ~\(median) for your other groups. Worth a few extra sets this week.",
            methodologyText: "Working sets per muscle group, last \(Self.recentWindowDays) days",
            chartKind: .ranking,
                chartLabels: sortedGroups,
            chartValues: sortedGroups.map { Double(recentSets[$0] ?? 0) },
            effectSize: min(1.0, 1.0 - Double(worst.count) / max(1.0, Double(median))),
                tone: .diagnostic
        )]
    }
}

// MARK: - PR rhythm

/// PR cadence against the user's own history, in both directions.
///
/// Replaces v1's `prRhythm`, which could only report a drought. PRs naturally
/// slow as a lifter advances, so a drought-only rule nags hardest at the most
/// committed users — exactly backwards. The good-stretch variant uses the same
/// data and outranks the drought when both are available.
struct PRPaceInsightRule: InsightRule {
    let ruleId = "prPace"
    let actionability = 0.7

    static let minimumPRs = 4
    static let minimumDroughtDays = 14
    static let droughtMultiplier = 1.5
    static let stillTrainedWindowDays = 14
    /// A recent burst has to beat the user's own cadence by this much to count.
    static let burstWindowDays = 30.0
    static let burstMultiplier = 1.5

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        let calendar = Calendar.current
        guard let trainedStart = calendar.date(
            byAdding: .day, value: -Self.stillTrainedWindowDays, to: context.referenceDate
        ) else { return [] }

        var prDatesByExercise: [UUID: [Date]] = [:]
        var lastTrainedByExercise: [UUID: Date] = [:]

        for set in context.eligibleWorkingSets {
            lastTrainedByExercise[set.exerciseId] = max(
                lastTrainedByExercise[set.exerciseId] ?? .distantPast, set.date
            )
            guard set.prStatus != nil, set.excludeFromPRs != true else { continue }
            prDatesByExercise[set.exerciseId, default: []].append(set.date)
        }

        var findings: [InsightFinding] = []
        if let burst = burstFinding(context: context, prDatesByExercise: prDatesByExercise) {
            findings.append(burst)
        }

        for (exerciseId, dates) in prDatesByExercise {
            guard dates.count >= Self.minimumPRs,
                  let exercise = context.exercisesById[exerciseId],
                  let lastTrained = lastTrainedByExercise[exerciseId],
                  lastTrained >= trainedStart
            else { continue }

            let sorted = dates.sorted()
            let gaps = zip(sorted, sorted.dropFirst()).map {
                $1.timeIntervalSince($0) / 86_400
            }
            let sortedGaps = gaps.sorted()
            let medianGap = sortedGaps[sortedGaps.count / 2]
            guard medianGap > 0 else { continue }

            let daysSinceLastPR = context.referenceDate.timeIntervalSince(sorted.last!) / 86_400
            let droughtThreshold = max(
                Double(Self.minimumDroughtDays), medianGap * Self.droughtMultiplier
            )
            guard daysSinceLastPR > droughtThreshold else { continue }

            findings.append(InsightFinding(
                ruleId: ruleId,
                subjectId: exerciseId,
                subjectName: exercise.name,
                headline: "\(exercise.name) is overdue for a PR",
                detailText: String(
                    format: "You usually set a new %@ PR about every %.0f days — it's been %.0f. A plateau this long is a good cue to vary rep ranges or take a lighter week.",
                    exercise.name, medianGap, daysSinceLastPR
                ),
                methodologyText: "\(dates.count) PRs on record; cadence from your own history",
                chartKind: .timeline,
                // Event timestamps, not the two durations the text quotes:
                // `InsightTimelineChart` reads the last value as the most recent
                // event and measures the trailing gap as (now − it). Handing it
                // [medianGap, daysSinceLastPR] placed both dots a few minutes
                // after the epoch, so the card headlined its gap as ~20,000 days
                // and dated the series to 1 Jan 1970.
                chartLabels: sorted.map { _ in "PR" },
                chartValues: sorted.map { $0.timeIntervalSince1970 },
                typicalGapDays: medianGap,
                // Ranked below the burst variant so a good stretch wins when
                // both hold.
                effectSize: min(0.75, daysSinceLastPR / (medianGap * 3.0)),
                tone: .diagnostic
            ))
        }

        return findings
    }

    /// "Three PRs this month — your best stretch since March."
    private func burstFinding(
        context: InsightAnalysisContext,
        prDatesByExercise: [UUID: [Date]]
    ) -> InsightFinding? {
        let allPRs = prDatesByExercise.values.flatMap { $0 }.sorted()
        guard allPRs.count >= Self.minimumPRs else { return nil }

        guard let windowStart = Calendar.current.date(
            byAdding: .day, value: -Int(Self.burstWindowDays), to: context.referenceDate
        ) else { return nil }

        let recent = allPRs.filter { $0 >= windowStart }
        guard recent.count >= 2 else { return nil }

        // The user's own typical PRs-per-30-days over their whole history.
        let historySpanDays = max(
            Self.burstWindowDays,
            context.referenceDate.timeIntervalSince(allPRs.first!) / 86_400
        )
        let typicalPerWindow = Double(allPRs.count) / historySpanDays * Self.burstWindowDays
        guard Double(recent.count) >= typicalPerWindow * Self.burstMultiplier else { return nil }

        let names = prDatesByExercise
            .filter { $0.value.contains { $0 >= windowStart } }
            .compactMap { context.exercisesById[$0.key]?.name }
            .sorted()

        let subjects = names.count <= 3
            ? ListFormatter.localizedString(byJoining: names)
            : "\(names.count) exercises"

        return InsightFinding(
            ruleId: ruleId,
            subjectId: nil,
            subjectName: nil,
            headline: "\(recent.count) PRs in the last month",
            detailText: subjects.isEmpty
                ? "That's well ahead of your usual pace of about \(Int(typicalPerWindow.rounded())) a month."
                : "\(subjects) all moved — well ahead of your usual pace of about \(Int(typicalPerWindow.rounded())) a month.",
            methodologyText: "\(allPRs.count) PRs on record; pace from your own history",
            chartKind: .timeline,
            chartLabels: recent.map { _ in "PR" },
            chartValues: recent.map { $0.timeIntervalSince1970 },
            effectSize: min(1.0, Double(recent.count) / max(1.0, typicalPerWindow * 2)),
            tone: .progress
        )
    }
}

// MARK: - RIR calibration

/// Uses the fatigue model's per-set prediction errors to tell whether the
/// user's reported RIR systematically under- or overstates their effort.
struct RIRCalibrationInsightRule: InsightRule {
    let ruleId = "rirCalibration"
    let actionability = 0.6

    static let minimumObservations = 10
    static let minimumBias = 0.03
    static let saturationBias = 0.10

    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding] {
        let byExercise = Dictionary(grouping: context.observations, by: \.exerciseId)
        var findings: [InsightFinding] = []

        for (exerciseId, observations) in byExercise {
            guard observations.count >= Self.minimumObservations,
                  let exercise = context.exercisesById[exerciseId]
            else { continue }

            let errors = observations.map(\.normalizedError).sorted()
            let median = errors[errors.count / 2]
            guard abs(median) >= Self.minimumBias else { continue }

            // Negative error = the user outperformed the model's prediction,
            // i.e. their reported RIR understates what they had left.
            let sandbagging = median < 0
            let percent = Int((abs(median) * 100).rounded())

            findings.append(InsightFinding(
                ruleId: ruleId,
                subjectId: exerciseId,
                subjectName: exercise.name,
                headline: sandbagging
                    ? "You have more in the tank on \(exercise.name) than you report"
                    : "Your \(exercise.name) effort reports run optimistic",
                detailText: sandbagging
                    ? "Across your recent sets you consistently beat the predicted output by ~\(percent)%. Your logged RIR is likely a rep or two higher in reality — suggestions could push harder."
                    : "Your recent sets came in ~\(percent)% under the predicted output. Your logged RIR may be understating fatigue — easing suggestions off slightly would fit your data better.",
                methodologyText: "\(observations.count) predicted vs. actual set comparisons",
                chartKind: .series,
                chartLabels: recentErrorLabels(observations),
                chartValues: recentErrorPercents(observations),
                effectSize: min(1.0, abs(median) / Self.saturationBias),
                tone: .diagnostic
            ))
        }

        return findings
    }

    /// Per-set "demonstrated vs. predicted" gap in percent for the most
    /// recent sets, oldest first — positive means the user beat the model.
    private func recentErrorPercents(_ observations: [FatigueObservation]) -> [Double] {
        observations
            .prefix(8)
            .reversed()
            .map { -$0.normalizedError * 100 }
    }

    private func recentErrorLabels(_ observations: [FatigueObservation]) -> [String] {
        let count = min(8, observations.count)
        return (1...count).map { "set \($0)" }
    }
}
