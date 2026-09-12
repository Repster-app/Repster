// WorkoutShareCardBuilder.swift
// The share card's data, built from workout snapshots. Used by both places a card can be
// raised — the summary sheet and a saved workout — so the same workout always shares as the
// same card.
// Scoping: SHARE_FROM_HISTORY_SCOPING.md

import SwiftUI

/// Where a card is being built from. It decides the PR wording and nothing else.
enum WorkoutShareCardContext {
    /// The summary sheet, moments after the workout.
    case summary
    /// A saved workout, which can be months old.
    case history
}

enum WorkoutShareCardBuilder {

    /// One exercise and every set logged against it.
    struct Entry {
        let exercise: ChartExerciseData
        let sets: [ChartSetData]
    }

    // MARK: - Card

    /// Builds the card. `entries` must be in the order the workout ran: the headline is the
    /// first exercise with a record, and ties among the top lifts keep that order.
    ///
    /// **Only ticked sets count** — `completed`, not `hasData`. The two differ by exactly the
    /// Copy Previous rows nobody ticked (UNPERFORMED_SETS_SCOPING.md), and a card is a public
    /// claim about what was done. Every path that records a real set also sets `completed`:
    /// live logging, Edit Workout, CSV import and backup restore.
    ///
    /// **Only a standing record is a PR** — `.current`. `prStatus` decays to `.previous` once a
    /// record is beaten, so an old workout's beaten PR simply isn't on its card. The card prints
    /// no PR count, so this can leave a record out but never claim one that isn't there.
    static func make(
        title: String,
        date: Date,
        duration: TimeInterval?,
        entries: [Entry],
        unitPreference: UnitPreference,
        context: WorkoutShareCardContext,
        now: Date = Date()
    ) -> WorkoutShareCardData {
        let performed = entries.compactMap { entry -> Entry? in
            let completed = entry.sets.filter(\.completed)
            // An exercise added and never done is not a lift. It used to show as a "0 sets"
            // row and count toward "N lifts".
            guard !completed.isEmpty else { return nil }
            return Entry(exercise: entry.exercise, sets: completed)
        }

        let summaries = performed.map { summarize($0, unitPreference: unitPreference) }

        // The single best record, which is what SHARE_CARD_FEATURE_DESIGN B3 makes the headline.
        let prLift = (summaries.first { $0.hadPR && $0.hasWeight } ?? summaries.first { $0.hadPR })?.lift

        let topLifts = summaries
            .sorted { $0.setCount > $1.setCount }
            .prefix(3)
            .map(\.lift)

        let allSets = performed.flatMap(\.sets)
        let exercisesById = Dictionary(
            performed.map { ($0.exercise.id, $0.exercise) },
            uniquingKeysWith: { first, _ in first }
        )
        let primaryMetric = WorkoutAggregateSummary.summarize(
            sets: allSets,
            exercisesById: exercisesById
        ).primaryMetric

        return WorkoutShareCardData(
            title: title,
            dateLabel: dateLabel(date, now: now),
            durationLabel: duration.map(durationLabel),
            setCountLabel: "\(allSets.count)",
            volumeLabel: primaryMetric?.formattedValue(style: .detailed, unitPreference: unitPreference),
            liftCountLabel: "\(summaries.count)",
            prLift: prLift,
            lifts: Array(topLifts),
            extraLiftCount: max(0, summaries.count - topLifts.count),
            muscleSlices: muscleSlices(performed),
            traceBars: traceBars(performed),
            prLabel: context == .summary ? "NEW PR" : "PERSONAL BEST"
        )
    }

    /// A saved workout's card.
    static func make(
        detail: WorkoutDetail,
        unitPreference: UnitPreference,
        now: Date = Date()
    ) -> WorkoutShareCardData {
        make(
            title: detail.workout.displayTitle,
            date: detail.workout.date,
            // Imported workouts can arrive without a duration. Zero is the same absence, and
            // "0m" on a card would read as a claim.
            duration: detail.workout.duration.flatMap { $0 > 0 ? TimeInterval($0) : nil },
            entries: detail.exerciseGroups.map { Entry(exercise: $0.exercise, sets: $0.sets) },
            unitPreference: unitPreference,
            context: .history,
            now: now
        )
    }

    // MARK: - Saved workouts

    /// Whether a saved workout gets a Share button at all.
    ///
    /// Calendar lists every workout regardless of status, so today's in-progress one shows up
    /// there — and a workout with nothing ticked would share as an empty card.
    static func canShare(_ detail: WorkoutDetail) -> Bool {
        detail.workout.status == .completed
            && detail.exerciseGroups.contains { $0.sets.contains(where: \.completed) }
    }

    /// `prs_hit` for a saved workout: the records from that session that are still standing.
    /// Not the same count the summary sends, which is every record the session set.
    static func standingPRCount(in detail: WorkoutDetail) -> Int {
        detail.exerciseGroups.reduce(0) { total, group in
            total + group.sets.filter { $0.completed && $0.prStatus == .current }.count
        }
    }

    /// Whole calendar days between the workout and `now`. Never negative.
    static func daysSince(_ date: Date, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return max(0, days)
    }

    // MARK: - Labels

    /// "Sat, Aug 30", plus the year when it isn't this one — a card shared from history can be
    /// from last year, and "Aug 30" alone would pass it off as recent.
    static func dateLabel(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        guard calendar.component(.year, from: date) != calendar.component(.year, from: now) else {
            return date.formatted(style)
        }
        return date.formatted(style.year())
    }

    /// "1h 4m" or "52m".
    static func durationLabel(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Pieces

    private struct LiftSummary {
        let lift: WorkoutShareCardData.Lift
        let setCount: Int
        let hasWeight: Bool
        let hadPR: Bool
    }

    /// `entry.sets` are already the completed ones.
    ///
    /// Heaviest weight and most reps are separate maxima rather than one set, as they always
    /// were on the summary (SHARE_CARD_FEATURE_DESIGN B1).
    private static func summarize(_ entry: Entry, unitPreference: UnitPreference) -> LiftSummary {
        let sets = entry.sets
        let setCountLabel = "\(sets.count) sets"
        let bestWeight = sets.compactMap(\.effectiveWeight).max()

        var detail = setCountLabel
        if let bestWeight {
            let weightLabel = UnitConversion.formatWeightLabel(bestWeight, unitPreference: unitPreference)
            detail = sets.map(\.prReps).max().map { "\(weightLabel) × \($0)" } ?? weightLabel
        }

        return LiftSummary(
            lift: WorkoutShareCardData.Lift(
                id: entry.exercise.id,
                name: entry.exercise.name,
                detail: detail,
                setCountLabel: setCountLabel
            ),
            setCount: sets.count,
            hasWeight: bestWeight != nil,
            hadPR: sets.contains { $0.prStatus == .current }
        )
    }

    /// Session volume split by each lift's primary muscle. Groups are normalised so they key
    /// into `MuscleGroupColors` and match what Insights shows.
    private static func muscleSlices(_ performed: [Entry]) -> [WorkoutShareCardData.MuscleSlice] {
        var volumeByGroup: [String: Double] = [:]

        for entry in performed {
            guard let group = normalizedGroup(entry.exercise) else { continue }

            let volume = entry.sets.reduce(into: 0.0) { total, set in
                guard set.setType != .warmup else { return }
                total += setVolume(set)
            }

            guard volume > 0 else { continue }
            volumeByGroup[group, default: 0] += volume
        }

        let total = volumeByGroup.values.reduce(0, +)
        guard total > 0 else { return [] }

        return volumeByGroup
            .map { group, volume in
                WorkoutShareCardData.MuscleSlice(
                    group: group,
                    displayName: ExercisePrimaryGroup.displayName(for: group),
                    fraction: volume / total
                )
            }
            .sorted { $0.fraction > $1.fraction }
    }

    /// Every working set in the order it was performed, sized against the session's biggest.
    ///
    /// Magnitude is set volume, not effort. RIR would be the truer axis but it is optional, and
    /// a chart that silently treats "not logged" as "easy" would be inventing a session.
    private static func traceBars(_ performed: [Entry]) -> [WorkoutShareCardData.TraceBar] {
        let entries = performed
            .flatMap { entry in
                entry.sets
                    .filter { $0.setType != .warmup }
                    .map { (set: $0, group: normalizedGroup(entry.exercise), exerciseId: entry.exercise.id) }
            }
            .sorted { $0.set.orderInWorkout < $1.set.orderInWorkout }

        let peak = entries.map { setVolume($0.set) }.max() ?? 0
        guard peak > 0 else { return [] }

        var previousExercise: UUID?
        return entries.map { entry in
            let bar = WorkoutShareCardData.TraceBar(
                id: entry.set.id,
                magnitude: min(1, setVolume(entry.set) / peak),
                group: entry.group,
                isPR: entry.set.prStatus == .current,
                startsNewExercise: entry.exerciseId != previousExercise
            )
            previousExercise = entry.exerciseId
            return bar
        }
    }

    private static func normalizedGroup(_ exercise: ChartExerciseData) -> String? {
        exercise.primaryMuscle.map { ExercisePrimaryGroup.normalizedValue($0) ?? $0.lowercased() }
    }

    /// Bodyweight and cardio sets have no load; reps still represent work done.
    private static func setVolume(_ set: ChartSetData) -> Double {
        let weight = set.weight ?? 0
        let reps = Double(set.reps ?? 0)
        return weight > 0 ? weight * reps : reps
    }
}

// MARK: - Presenting from a saved workout

extension WorkoutDetail: Identifiable {
    var id: UUID { workout.id }
}

extension View {
    /// Presents the share card for a saved workout whenever `detail` is set.
    ///
    /// One modifier for both history surfaces, so the access-tier rule and the analytics wiring
    /// exist once rather than being copied into each screen.
    func shareWorkoutCard(
        item detail: Binding<WorkoutDetail?>,
        entryPoint: ShareCardEntryPoint
    ) -> some View {
        modifier(ShareWorkoutCardModifier(detail: detail, entryPoint: entryPoint))
    }
}

private struct ShareWorkoutCardModifier: ViewModifier {
    @Binding var detail: WorkoutDetail?
    let entryPoint: ShareCardEntryPoint

    @Environment(ServiceContainer.self) private var services
    @State private var accessTier: String?

    func body(content: Content) -> some View {
        content
            .task {
                // Read-only, as on the summary: `recordCompletedWorkoutIfNeeded()` would spend a
                // free workout just to label an event. Resolved when the screen appears so it has
                // settled before anyone taps Share; until then it is nil and the property is
                // omitted rather than guessed.
                let snapshot = await services.accessControlService.currentAccessSnapshot()
                accessTier = snapshot.hasFullAccess ? "subscribed" : "free"
            }
            .sheet(item: $detail) { detail in
                WorkoutSharePreviewSheet(
                    data: WorkoutShareCardBuilder.make(
                        detail: detail,
                        unitPreference: services.unitPreference
                    ),
                    entryPoint: entryPoint,
                    prsHit: WorkoutShareCardBuilder.standingPRCount(in: detail),
                    accessTier: accessTier,
                    analyticsService: services.analyticsService,
                    daysSinceWorkout: WorkoutShareCardBuilder.daysSince(detail.workout.date)
                )
            }
    }
}
