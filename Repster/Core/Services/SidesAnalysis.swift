// SidesAnalysis.swift
// Left against right on unilateral exercises. Spec: UNILATERAL_IMBALANCE_EXPLORATION.md §5.
//
// Two levels (D21):
// - An EXERCISE has a direction — "Left is slightly stronger". That's where it's true:
//   one movement, one weight, both sides in the same set.
// - A MUSCLE GROUP only says whether any of its exercises shows an imbalance. Exercises in
//   one group can lean different ways — quads and hamstrings both live in "legs" — so a
//   group-level stronger side would be an average of disagreements.
//
// Pure functions over `InsightAnalysisContext`, like `trainingStatus(from:)`, so the rules
// test against an in-memory store and nothing else.
//
// Everything compares the two sides *within one set*, so both sides always share a weight:
// the comparison is load-controlled by construction, and bodyweight unilateral work (no
// weight at all) still counts.

import Foundation

/// The figure's own side — never the viewer's. See `BodyMapGeometry.librarySide(for:in:)`.
enum SideLean: String, Sendable, Hashable {
    case left
    case right

    var word: String { self == .left ? "Left" : "Right" }
}

/// How much stronger, in the three steps the strength mark draws (D13).
enum SideDegree: Int, Sendable, Hashable, Comparable {
    case slightly = 1
    case clearly = 2
    case much = 3

    static func < (lhs: SideDegree, rhs: SideDegree) -> Bool { lhs.rawValue < rhs.rawValue }

    var word: String {
        switch self {
        case .slightly: return "slightly"
        case .clearly:  return "clearly"
        case .much:     return "much"
        }
    }
}

enum SideNotTrackedReason: Sendable, Hashable {
    /// Not marked Unilateral, so it logs one rep count for both sides.
    case notUnilateral
    /// Marked Unilateral, but no set in the lookback has both sides filled in.
    case neverBothSides
}

/// One exercise's verdict (D22).
enum SideStatus: Sendable, Hashable {
    case stronger(SideLean, SideDegree)
    /// Enough sessions, and the sessions that differed agree — but too few of them differed to
    /// confirm it (D24). Said tentatively, with no strength mark.
    case possible(SideLean)
    case even
    /// Fewer sessions with both sides logged than a verdict needs.
    case collecting(sessions: Int)
    case notTracked(SideNotTrackedReason)

    /// The row's sentence (D13): plain words, no numbers.
    var sentence: String {
        switch self {
        case let .stronger(lean, degree):
            return "\(lean.word) is \(degree.word) stronger"
        case let .possible(lean):
            return "\(lean.word) seems stronger — needs more sessions to confirm"
        case .even:
            return "Even"
        case let .collecting(sessions):
            return SidesAnalysis.needsMoreSessions(after: sessions)
        case .notTracked(.notUnilateral):
            return "Not tracked by side"
        case .notTracked(.neverBothSides):
            return "No sets with both sides logged"
        }
    }

    var isStronger: Bool {
        if case .stronger = self { return true }
        return false
    }

    var isPossible: Bool {
        if case .possible = self { return true }
        return false
    }

    /// Enough sessions for a verdict: stronger, possible or even.
    var isClassified: Bool {
        switch self {
        case .stronger, .possible, .even: return true
        case .collecting, .notTracked: return false
        }
    }

    var isTracked: Bool {
        if case .notTracked = self { return false }
        return true
    }

    var degree: SideDegree? {
        if case let .stronger(_, degree) = self { return degree }
        return nil
    }

    /// Never a name or a number — see the Training Insights note in `AnalyticsServiceProtocol`.
    var analyticsValue: String {
        switch self {
        case .stronger:   return "stronger"
        case .possible:   return "possible"
        case .even:       return "even"
        case .collecting: return "collecting"
        case .notTracked: return "not_tracked"
        }
    }

    /// List order: stronger, even, collecting, not tracked.
    fileprivate var rank: Int {
        switch self {
        case .stronger:   return 0
        case .possible:   return 1
        case .even:       return 2
        case .collecting: return 3
        case .notTracked: return 4
        }
    }
}

/// A muscle group's verdict (D21): whether any exercise in it shows an imbalance — never which side.
enum SideGroupStatus: Sendable, Hashable {
    case imbalance(exercises: Int)
    /// No confirmed imbalance, but at least one exercise seems to lean (D24).
    case possible(exercises: Int)
    case even
    /// No exercise in the group has enough sessions yet; carries the closest one's count.
    case collecting(sessions: Int)

    var sentence: String {
        switch self {
        case let .imbalance(count):
            return count == 1 ? "Imbalance in 1 exercise" : "Imbalance in \(count) exercises"
        case let .possible(count):
            return count == 1 ? "Possible imbalance in 1 exercise" : "Possible imbalance in \(count) exercises"
        case .even:
            return "Even"
        case let .collecting(sessions):
            return SidesAnalysis.needsMoreSessions(after: sessions)
        }
    }

    var isImbalance: Bool {
        if case .imbalance = self { return true }
        return false
    }

    var isPossible: Bool {
        if case .possible = self { return true }
        return false
    }

    var isClassified: Bool {
        if case .collecting = self { return false }
        return true
    }

    var analyticsValue: String {
        switch self {
        case .imbalance:  return "imbalance"
        case .possible:   return "possible"
        case .even:       return "even"
        case .collecting: return "collecting"
        }
    }

    fileprivate var rank: Int {
        switch self {
        case .imbalance:  return 0
        case .possible:   return 1
        case .even:       return 2
        case .collecting: return 3
        }
    }
}

/// One workout's comparison: the median capacity per side across its sets.
struct SideSession: Sendable, Equatable, Identifiable {
    /// The workout.
    let id: UUID
    let date: Date
    let left: Double
    let right: Double

    /// Positive when the right side is ahead.
    var gap: Double { right - left }

    /// Nil for a tie — drawn on the line, and never counted as a lead.
    var lean: SideLean? {
        guard abs(gap) >= SidesAnalysis.tieBelow else { return nil }
        return gap > 0 ? .right : .left
    }

    var degree: SideDegree? {
        guard lean != nil else { return nil }
        return SidesAnalysis.degree(gap: gap, meanCapacity: (left + right) / 2)
    }
}

/// The best single set at one weight — both sides as they were logged together.
///
/// Never two sides from two different sets: the whole comparison rests on both sides sharing a
/// weight inside one set, and a row that mixed two sets would invite the reader to compare
/// reserves that were never side by side.
struct SideBestRow: Sendable, Equatable, Identifiable {
    /// Kilograms, as logged. Nil for bodyweight work.
    let weight: Double?
    let left: Int
    let right: Int
    /// Reps in reserve, when the set has them for both sides. Nil follows `capacity`: a blank isn't
    /// failure, and two "5+" sides compare on reps alone, so neither gets a reserve here.
    let leftRIR: Double?
    let rightRIR: Double?

    var id: String { weight.map { String(format: "%.3f", $0) } ?? "bodyweight" }
}

struct SideExerciseSummary: Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let status: SideStatus
    /// The sessions the verdict was made from — at most `sessionsConsidered`, oldest first.
    let sessions: [SideSession]
    /// Average right-minus-left gap across `sessions`, ties counting as zero.
    let averageGap: Double
    /// Sessions where the stronger side led.
    let leadCount: Int
    /// Sessions where the sides differed at all.
    let differingCount: Int
    /// Heaviest first; bodyweight last.
    let bestReps: [SideBestRow]
    /// Rows with only one side's reps. Excluded from everything above.
    let oneSideOnlySets: Int
    /// Rows with RIR on only one side. Compared on reps alone — a blank isn't failure.
    let rirOnOneSideSets: Int
}

struct SideGroupSummary: Sendable, Equatable, Identifiable {
    /// Normalised primary muscle, e.g. "legs".
    let id: String
    let displayName: String
    let status: SideGroupStatus
    /// Every exercise with this primary group done in the lookback, tracked or not, in list order.
    let exercises: [SideExerciseSummary]

    var trackedExerciseCount: Int { exercises.filter(\.status.isTracked).count }
}

enum SidesCardState: String, Sendable {
    /// Nothing has both sides logged in the lookback. The card isn't drawn (D10).
    case hidden
    /// Tracked groups exist, none with enough sessions yet (S1).
    case building
    /// Groups have enough sessions and none shows an imbalance (S2).
    case even
    /// No confirmed imbalance, but something seems to lean — needs more sessions (D24).
    case possible
    case imbalanced
}

struct SidesStatus: Sendable, Equatable {
    /// Groups with at least one both-sides session, in list order.
    let groups: [SideGroupSummary]
    /// Groups trained in the lookback that nothing tracks by side — the coverage note.
    let untrackedGroupNames: [String]

    static let empty = SidesStatus(groups: [], untrackedGroupNames: [])

    var imbalancedGroupCount: Int { groups.filter(\.status.isImbalance).count }
    var possibleGroupCount: Int { groups.filter(\.status.isPossible).count }

    var state: SidesCardState {
        if groups.isEmpty { return .hidden }
        if groups.contains(where: \.status.isImbalance) { return .imbalanced }
        if groups.contains(where: \.status.isPossible) { return .possible }
        if groups.contains(where: \.status.isClassified) { return .even }
        return .building
    }
}

enum SidesAnalysis {
    // D22 — starting values; check them on cohort data, not one lifter's.

    /// Recent, whatever the training frequency: twice a week is the last three weeks.
    static let sessionsConsidered = 6
    /// A lift you stopped doing drops out.
    static let lookbackDays = 84
    /// Below this an exercise is still collecting.
    static let minSessions = 3
    /// Below this many sessions that differed, a lean only "seems" (D24): a single odd session
    /// or set can't confirm a direction.
    static let minDifferingSessions = 3
    /// Same side ahead in three of every four sessions that differed.
    static let minConsistency = 0.75
    /// Average gap, ties counting as zero. Evening out shows up as this falling.
    static let minAverageGap = 0.5
    static let usableRIR: ClosedRange<Double> = 0...4
    /// Stored for the "5+" chip. A floor, not a value.
    static let censoredRIR = 5.0
    static let degreeClearly = 0.12
    static let degreeMuch = 0.25
    /// Session gaps under half a rep are a tie.
    static let tieBelow = 0.5

    struct Classification: Equatable {
        let status: SideStatus
        let averageGap: Double
        let leadCount: Int
        let differingCount: Int
    }

    static func needsMoreSessions(after sessions: Int) -> String {
        let needed = max(1, minSessions - sessions)
        return needed == 1 ? "Needs 1 more session" : "Needs \(needed) more sessions"
    }

    /// Reps plus reps in reserve. Both sides need RIR, or neither gets it — a blank isn't failure.
    /// "5+" against a side at 0–4 counts as 5: the direction is certain and 5 is the smallest
    /// the difference can be. Two "5+" sides compare on reps alone.
    static func capacity(
        leftReps: Int,
        rightReps: Int,
        leftRIR: Double?,
        rightRIR: Double?
    ) -> (left: Double, right: Double) {
        let left = Double(leftReps)
        let right = Double(rightReps)
        guard let leftRIR, let rightRIR else { return (left, right) }
        let leftUsable = usableRIR.contains(leftRIR)
        let rightUsable = usableRIR.contains(rightRIR)
        if leftUsable && rightUsable {
            return (left + leftRIR, right + rightRIR)
        }
        if leftUsable || rightUsable {
            return (left + min(leftRIR, censoredRIR), right + min(rightRIR, censoredRIR))
        }
        return (left, right)
    }

    /// The reserves a best-set row may print, following `capacity` exactly: both sides or neither,
    /// and a censored "5+" is shown as the floor it was counted as. Two "5+" sides compared on reps
    /// alone get nothing, because nothing about their reserve was comparable.
    static func comparableRIR(_ leftRIR: Double?, _ rightRIR: Double?) -> (left: Double?, right: Double?) {
        guard let leftRIR, let rightRIR else { return (nil, nil) }
        guard usableRIR.contains(leftRIR) || usableRIR.contains(rightRIR) else { return (nil, nil) }
        return (min(leftRIR, censoredRIR), min(rightRIR, censoredRIR))
    }

    /// Relative, not absolute: one rep matters more on a set of 6 than a set of 15.
    static func degree(gap: Double, meanCapacity: Double) -> SideDegree {
        guard meanCapacity > 0 else { return .much }
        let relative = abs(gap) / meanCapacity
        if relative < degreeClearly { return .slightly }
        if relative < degreeMuch { return .clearly }
        return .much
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// §5.3. Direction from the sessions that differed; size from all of them, ties as zero.
    ///
    /// People show an imbalance two ways. Some do different reps — as it evens out, their gap
    /// gets smaller. Others match reps and let RIR carry it — as it evens out, their gap shows up
    /// less often, because RIR is a whole number. An average that counts equal sessions as zero
    /// falls in both cases; a median of only the differing sessions would freeze for the second.
    static func classify(_ sessions: [SideSession]) -> Classification {
        let count = sessions.count
        let average = count == 0 ? 0 : sessions.map(\.gap).reduce(0, +) / Double(count)
        let rights = sessions.filter { $0.lean == .right }.count
        let lefts = sessions.filter { $0.lean == .left }.count
        let differing = rights + lefts

        guard count >= minSessions else {
            return Classification(status: .collecting(sessions: count), averageGap: average, leadCount: 0, differingCount: differing)
        }

        let lean: SideLean = rights >= lefts ? .right : .left
        let leads = max(rights, lefts)
        let agrees = differing > 0 && Double(leads) / Double(differing) >= minConsistency
        let sized = abs(average) >= minAverageGap && (average > 0) == (lean == .right)
        guard agrees, sized else {
            return Classification(status: .even, averageGap: average, leadCount: leads, differingCount: differing)
        }
        // The lean is there, but on too few sessions to call it — not "Even" (D24).
        guard differing >= minDifferingSessions else {
            return Classification(status: .possible(lean), averageGap: average, leadCount: leads, differingCount: differing)
        }

        let meanCapacity = sessions.map { ($0.left + $0.right) / 2 }.reduce(0, +) / Double(count)
        return Classification(
            status: .stronger(lean, degree(gap: average, meanCapacity: meanCapacity)),
            averageGap: average,
            leadCount: leads,
            differingCount: differing
        )
    }

    static func exerciseOrder(_ lhs: SideExerciseSummary, _ rhs: SideExerciseSummary) -> Bool {
        if lhs.status.rank != rhs.status.rank { return lhs.status.rank < rhs.status.rank }
        let lhsDegree = lhs.status.degree?.rawValue ?? 0
        let rhsDegree = rhs.status.degree?.rawValue ?? 0
        if lhsDegree != rhsDegree { return lhsDegree > rhsDegree }
        if abs(lhs.averageGap) != abs(rhs.averageGap) { return abs(lhs.averageGap) > abs(rhs.averageGap) }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    static func groupOrder(_ lhs: SideGroupSummary, _ rhs: SideGroupSummary) -> Bool {
        if lhs.status.rank != rhs.status.rank { return lhs.status.rank < rhs.status.rank }
        if case let .imbalance(lhsCount) = lhs.status, case let .imbalance(rhsCount) = rhs.status, lhsCount != rhsCount {
            return lhsCount > rhsCount
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private struct Sample {
        let workoutId: UUID
        let date: Date
        let left: Double
        let right: Double
    }

    /// Ranked by the same capacity the verdict uses, then by reps, then by recency — so the row a
    /// lifter reads is the set the verdict would have leaned on hardest.
    private struct BestAccumulator {
        let weight: Double?
        let left: Int
        let right: Int
        let leftRIR: Double?
        let rightRIR: Double?
        let capacity: Double
        let date: Date

        var totalReps: Int { left + right }

        func isBeaten(by other: BestAccumulator) -> Bool {
            if other.capacity != capacity { return other.capacity > capacity }
            if other.totalReps != totalReps { return other.totalReps > totalReps }
            return other.date > date
        }
    }

    private static func sessions(from samples: [Sample]) -> [SideSession] {
        Dictionary(grouping: samples, by: \.workoutId).map { workoutId, list in
            SideSession(
                id: workoutId,
                date: list.map(\.date).min() ?? .distantPast,
                left: median(list.map(\.left)),
                right: median(list.map(\.right))
            )
        }
        .sorted { $0.date < $1.date }
    }

    static func status(from context: InsightAnalysisContext) -> SidesStatus {
        guard let lookbackStart = Calendar.current.date(
            byAdding: .day, value: -lookbackDays, to: context.referenceDate
        ) else { return .empty }

        var samples: [UUID: [Sample]] = [:]
        var oneSideOnly: [UUID: Int] = [:]
        var rirOnOneSide: [UUID: Int] = [:]
        var bests: [UUID: [String: BestAccumulator]] = [:]
        var exercisesByGroup: [String: Set<UUID>] = [:]

        // `eligibleWorkingSets` already honours progression exclusions and drops warm-ups and
        // partials; the fetch behind it keeps only completed sets.
        for set in context.eligibleWorkingSets where set.date >= lookbackStart {
            guard let exercise = context.exercisesById[set.exerciseId],
                  let group = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle),
                  !InsightsService.statusExcludedGroups.contains(group)
            else { continue }
            exercisesByGroup[group, default: []].insert(exercise.id)
            guard exercise.unilateral, exercise.supportsUnilateralLogging else { continue }

            let left = set.leftReps ?? 0
            let right = set.rightReps ?? 0
            if (left > 0) != (right > 0) {
                oneSideOnly[exercise.id, default: 0] += 1
                continue
            }
            // Drop, back-off, myo and the rest are submaximal or fragmented — not evidence.
            guard left > 0, right > 0, set.setType.isCapacityPointEstimate else { continue }
            if (set.leftRIR == nil) != (set.rightRIR == nil) {
                rirOnOneSide[exercise.id, default: 0] += 1
            }

            let cap = capacity(leftReps: left, rightReps: right, leftRIR: set.leftRIR, rightRIR: set.rightRIR)
            samples[exercise.id, default: []].append(
                Sample(workoutId: set.workoutId, date: set.date, left: cap.left, right: cap.right)
            )

            let weight = set.weight.flatMap { $0 > 0 ? $0 : nil }
            let key = weight.map { String(format: "%.3f", $0) } ?? "bodyweight"
            let reserve = comparableRIR(set.leftRIR, set.rightRIR)
            let candidate = BestAccumulator(
                weight: weight,
                left: left,
                right: right,
                leftRIR: reserve.left,
                rightRIR: reserve.right,
                capacity: cap.left + cap.right,
                date: set.date
            )
            if bests[exercise.id]?[key]?.isBeaten(by: candidate) ?? true {
                bests[exercise.id, default: [:]][key] = candidate
            }
        }

        var groups: [SideGroupSummary] = []
        var untracked: [String] = []

        for (group, exerciseIds) in exercisesByGroup {
            var summaries: [SideExerciseSummary] = []

            for id in exerciseIds {
                guard let exercise = context.exercisesById[id] else { continue }
                let recent = Array(sessions(from: samples[id] ?? []).suffix(sessionsConsidered))
                let classification: Classification
                if !(exercise.unilateral && exercise.supportsUnilateralLogging) {
                    classification = Classification(status: .notTracked(.notUnilateral), averageGap: 0, leadCount: 0, differingCount: 0)
                } else if recent.isEmpty {
                    classification = Classification(status: .notTracked(.neverBothSides), averageGap: 0, leadCount: 0, differingCount: 0)
                } else {
                    classification = classify(recent)
                }
                let bestRows = (bests[id] ?? [:]).values
                    .map {
                        SideBestRow(
                            weight: $0.weight,
                            left: $0.left,
                            right: $0.right,
                            leftRIR: $0.leftRIR,
                            rightRIR: $0.rightRIR
                        )
                    }
                    .sorted { ($0.weight ?? -1) > ($1.weight ?? -1) }
                summaries.append(SideExerciseSummary(
                    id: id,
                    name: exercise.name,
                    status: classification.status,
                    sessions: recent,
                    averageGap: classification.averageGap,
                    leadCount: classification.leadCount,
                    differingCount: classification.differingCount,
                    bestReps: bestRows,
                    oneSideOnlySets: oneSideOnly[id] ?? 0,
                    rirOnOneSideSets: rirOnOneSide[id] ?? 0
                ))
            }

            let displayName = ExercisePrimaryGroup.displayName(for: group)
            let tracked = summaries.filter(\.status.isTracked)
            guard !tracked.isEmpty else {
                untracked.append(displayName)
                continue
            }

            let imbalanced = tracked.filter(\.status.isStronger).count
            let possible = tracked.filter(\.status.isPossible).count
            let status: SideGroupStatus
            if imbalanced > 0 {
                status = .imbalance(exercises: imbalanced)
            } else if possible > 0 {
                status = .possible(exercises: possible)
            } else if tracked.contains(where: \.status.isClassified) {
                status = .even
            } else {
                status = .collecting(sessions: tracked.map(\.sessions.count).max() ?? 0)
            }

            groups.append(SideGroupSummary(
                id: group,
                displayName: displayName,
                status: status,
                exercises: summaries.sorted(by: exerciseOrder)
            ))
        }

        return SidesStatus(groups: groups.sorted(by: groupOrder), untrackedGroupNames: untracked.sorted())
    }
}
