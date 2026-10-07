// SideGroupDetailView.swift
// The deep dive behind a Sides row: one muscle group's exercises, each with its own
// direction — "Left is slightly stronger" — then one exercise session by session.
// Spec §4.3–4.4, D21.
//
// No group-level chart: exercises in one group can lean different ways, and a line
// averaged across them would draw through a disagreement. Each exercise's own chart
// is one tap down. D13: the exercise view is the only place a rep count appears.

import SwiftUI

struct SideGroupDetailSheet: View {
    let group: SideGroupSummary
    let unitPreference: UnitPreference
    var onExerciseOpened: (SideExerciseSummary) -> Void = { _ in }
    var onExerciseEdited: () -> Void = {}

    private enum Route: Hashable {
        case exercise(UUID)
        case untracked
    }

    /// Only exercises that can carry a verdict. `exercisesByGroup` is filled before the unilateral
    /// guard, so the full list is every exercise trained in the group — for Legs that was a couple
    /// of real rows inside a dozen "Not tracked by side". The rest are one line at the bottom.
    private var tracked: [SideExerciseSummary] { group.exercises.filter(\.status.isTracked) }
    private var untracked: [SideExerciseSummary] { group.exercises.filter { !$0.status.isTracked } }

    /// One ruler for the whole group, so the rows can be read against each other. That comparison
    /// is the only thing this screen shows that the exercise screen cannot.
    private var scale: Double {
        max(3, (tracked.map { abs($0.averageGap) }.max() ?? 0).rounded(.up))
    }

    /// Two exercises in one group leaning opposite ways is exactly why the map never names a side.
    private var leansBothWays: Bool {
        let leans = Set(tracked.compactMap { summary -> SideLean? in
            switch summary.status {
            case let .stronger(lean, _): return lean
            case let .possible(lean): return lean
            default: return nil
            }
        })
        return leans.count > 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    SidesDivider()

                    if tracked.isEmpty {
                        Text("Nothing here is tracked by side yet.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        SidesSectionLabel(text: "EXERCISES")

                        VStack(spacing: 0) {
                            ForEach(Array(tracked.enumerated()), id: \.element.id) { index, exercise in
                                exerciseRow(exercise, isLast: index == tracked.count - 1)
                            }
                        }
                        .padding(.top, -8)

                        axis

                        Text("Every exercise on one scale, so you can read them against each other.")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.sidesCaption)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !untracked.isEmpty {
                        untrackedRow
                    }

                    Text("Each exercise is judged on its last \(SidesAnalysis.sessionsConsidered) sessions, comparing both sides at the same weight.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.sidesCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color.bgCard)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .exercise(id):
                    if let exercise = group.exercises.first(where: { $0.id == id }) {
                        SideExerciseDetailView(exercise: exercise, unitPreference: unitPreference) {
                            onExerciseOpened(exercise)
                        }
                    }
                case .untracked:
                    SideUntrackedListView(exercises: untracked, onChanged: onExerciseEdited)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgCard)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.displayName)
                .font(.system(size: 24, weight: .bold))
                .kerning(-0.3)
                .foregroundStyle(Color.textPrimary)

            Text(headline)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: String {
        let line = SidesCopy.statusLine(for: group)
        return leansBothWays ? "\(line) — and not all the same way" : line
    }

    // MARK: - Rows

    private func exerciseRow(_ exercise: SideExerciseSummary, isLast: Bool) -> some View {
        NavigationLink(value: Route.exercise(exercise.id)) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(exercise.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }

                HStack(spacing: 10) {
                    Text(exercise.status.sentence)
                        .font(.system(size: 12.5, weight: exercise.status.isStronger ? .semibold : .medium))
                        .foregroundStyle(exercise.status.isStronger ? Color.textPrimary : Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    SideStrengthMark(status: exercise.status)
                    SideMiniBeam(averageGap: exercise.averageGap, status: exercise.status, scale: scale)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(Color.border)
                        .frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows each session")
    }

    /// Labels the shared ruler once, under the column the beams line up in.
    private var axis: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            ZStack {
                HStack(spacing: 0) {
                    Text("Left")
                    Spacer(minLength: 0)
                    Text("Right")
                }
                Text("Even")
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Color.sidesCaption)
            .frame(width: SideMiniBeam.width)
        }
        .padding(.top, -6)
    }

    private var untrackedRow: some View {
        NavigationLink(value: Route.untracked) {
            HStack(spacing: 10) {
                Text(untrackedLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Mark one")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgInput)
            .cornerRadius(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var untrackedLine: String {
        let name = group.displayName.lowercased()
        return untracked.count == 1
            ? "1 other \(name) exercise isn\u{2019}t tracked by side"
            : "\(untracked.count) other \(name) exercises aren\u{2019}t tracked by side"
    }
}

// MARK: - Not tracked by side

/// The exercises a group trains that log one number for both sides. Each opens its own editor,
/// where the Unilateral switch lives — the flag is the whole reach of the feature, and 6 of the 69
/// seeded exercises carry it, so this list is the only place the reach can grow.
struct SideUntrackedListView: View {
    let exercises: [SideExerciseSummary]
    var onChanged: () -> Void = {}

    @Environment(ServiceContainer.self) private var services
    @State private var editing: ChartExerciseData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("These log one number for both sides. Mark one Unilateral and Repster compares left against right from your next session.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sidesCaption)
                        .padding(.top, 2)
                    Text("Only worth it for movements you train one side at a time. A back squat logged per side would compare two numbers that never differ.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.sidesCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgInput)
                .cornerRadius(10)

                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        row(exercise, isLast: index == exercises.count - 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.bgCard)
        .navigationTitle("Not tracked by side")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { data in
            CreateEditExerciseSheet(exercise: data, services: services, onSave: onChanged)
        }
    }

    @ViewBuilder
    private func row(_ exercise: SideExerciseSummary, isLast: Bool) -> some View {
        if exercise.canTrackSides {
            Button {
                Task { editing = try? await services.exerciseService.fetchExerciseSnapshot(exercise.id) }
            } label: {
                HStack(spacing: 10) {
                    Text(exercise.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) { divider(isLast) }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this exercise to mark it Unilateral")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                Text("Doesn\u{2019}t log reps, so sides can\u{2019}t be compared")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { divider(isLast) }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func divider(_ isLast: Bool) -> some View {
        if !isLast {
            Rectangle().fill(Color.border).frame(height: 1)
        }
    }
}

/// Already carries `id`; `.sheet(item:)` needs the conformance spelled out.
extension ChartExerciseData: Identifiable {}

// MARK: - Exercise

struct SideExerciseDetailView: View {
    let exercise: SideExerciseSummary
    let unitPreference: UnitPreference
    var onFirstAppear: () -> Void = {}

    @State private var hasReportedOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    // The size of the gap leads and the consistency supports it: a lifter asks how
                    // far apart their sides are before they ask how often.
                    if let gap = SidesCopy.gapLine(for: exercise) {
                        Text(gap)
                            .font(.system(size: 19, weight: .bold))
                            .kerning(-0.2)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(SidesCopy.statusLine(for: exercise))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(SidesCopy.statusLine(for: exercise))
                            .font(.system(size: 19, weight: .bold))
                            .kerning(-0.2)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if exercise.status.isClassified {
                    SideBalanceBeam(averageGap: exercise.averageGap, status: exercise.status)
                }

                if !exercise.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SidesSectionLabel(text: "EACH SESSION")
                        SideSessionLadder(sessions: exercise.sessions)
                    }
                }

                if !exercise.bestReps.isEmpty {
                    SideEffortTable(rows: exercise.bestReps, unitPreference: unitPreference)
                }

                if let note = incompleteNote {
                    noteView(note)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.bgCard)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasReportedOpen else { return }
            hasReportedOpen = true
            onFirstAppear()
        }
    }

    /// Rows with a side missing: one-sided reps aren't compared at all; RIR on one side
    /// compares on reps alone, because a blank isn't failure.
    private var incompleteNote: String? {
        var parts: [String] = []
        let reps = exercise.oneSideOnlySets
        if reps > 0 {
            parts.append(reps == 1
                ? "1 set had only one side logged, so it isn’t counted."
                : "\(reps) sets had only one side logged, so they aren’t counted.")
        }
        let rir = exercise.rirOnOneSideSets
        if rir > 0 {
            parts.append(rir == 1
                ? "1 set had reps in reserve on one side only, so it’s compared on reps."
                : "\(rir) sets had reps in reserve on one side only, so they’re compared on reps.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func noteView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgInput)
        .cornerRadius(10)
    }
}

// MARK: - Shared pieces

struct SidesSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(Color.textTertiary)
    }
}

struct SidesDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.border)
            .frame(height: 1)
    }
}

/// Status lines for the deep dive and the exercise view (D13, D21).
enum SidesCopy {
    static func statusLine(for group: SideGroupSummary) -> String {
        let tracked = group.trackedExerciseCount
        switch group.status {
        case let .imbalance(count):
            if count == tracked {
                return count == 1 ? "An imbalance in the one exercise you track here" : "An imbalance in all \(count) exercises you track here"
            }
            return "An imbalance in \(count) of the \(tracked) exercises you track here"
        case let .possible(count):
            let exercises = count == 1 ? "1 exercise" : "\(count) exercises"
            return "A possible imbalance in \(exercises) — needs more sessions to confirm"
        case .even:
            return "Even on every exercise with enough sessions"
        case let .collecting(sessions):
            return collectingLine(sessions)
        }
    }

    static func statusLine(for exercise: SideExerciseSummary) -> String {
        let count = exercise.sessions.count
        switch exercise.status {
        case let .stronger(lean, _):
            let side = lean.rawValue
            if exercise.leadCount == count {
                return "Your \(side) side has been stronger in all of your last \(count) sessions"
            }
            // Level sessions aren't against it — say so, or "3 of 6" reads like a coin flip.
            if exercise.leadCount == exercise.differingCount {
                return "Your \(side) side was ahead every time your sides differed — \(exercise.leadCount) of your last \(count) sessions"
            }
            return "Your \(side) side has been stronger in \(exercise.leadCount) of your last \(count) sessions"
        case let .possible(lean):
            return "Your \(lean.rawValue) side was ahead in \(exercise.leadCount) of your last \(count) sessions. It needs a few more to confirm."
        case .even:
            return exercise.differingCount == 0
                ? "Your sides matched in all of your last \(count) sessions"
                : "No consistent difference across your last \(count) sessions"
        case let .collecting(sessions):
            return collectingLine(sessions)
        case .notTracked(.notUnilateral):
            return "Not marked Unilateral, so both sides are logged as one"
        case .notTracked(.neverBothSides):
            return "No recent sets with both sides logged"
        }
    }

    /// The only numbers in the feature (D13).
    static func gapLine(for exercise: SideExerciseSummary) -> String? {
        switch exercise.status {
        case let .stronger(lean, _):
            let reps = max(1, Int(abs(exercise.averageGap).rounded()))
            return "About \(reps) more \(reps == 1 ? "rep" : "reps") on your \(lean.rawValue), at the same weight"
        case let .possible(lean):
            let reps = max(1, Int(abs(exercise.averageGap).rounded()))
            return "About \(reps) more \(reps == 1 ? "rep" : "reps") on your \(lean.rawValue) so far, at the same weight"
        case .even:
            return "Within a rep of each other, at the same weight"
        default:
            return nil
        }
    }

    private static func collectingLine(_ sessions: Int) -> String {
        let needed = max(1, SidesAnalysis.minSessions - sessions)
        return needed == 1
            ? "Needs 1 more session with both sides logged"
            : "Needs \(needed) more sessions with both sides logged"
    }
}

#if DEBUG
#Preview("Legs deep dive") {
    SideGroupDetailSheet(group: SidesPreviewData.legs, unitPreference: .metric)
}

/// One per state, because the beam and the ladder each read differently in all four and a device
/// pass on only the confirmed case would miss three of them.
#Preview("Exercise — stronger") {
    NavigationStack {
        SideExerciseDetailView(exercise: SidesPreviewData.legs.exercises[0], unitPreference: .metric)
    }
}

#Preview("Exercise — seems stronger") {
    NavigationStack {
        SideExerciseDetailView(exercise: SidesPreviewData.legs.exercises[3], unitPreference: .metric)
    }
}

#Preview("Exercise — even") {
    NavigationStack {
        SideExerciseDetailView(
            exercise: SidesPreviewData.exercise(
                "1 Leg Press", .even, [(10, 10), (9, 9.5), (11, 10.5), (10, 10), (9.5, 9.5), (12, 12)]
            ),
            unitPreference: .metric
        )
    }
}

#Preview("Exercise — collecting") {
    NavigationStack {
        SideExerciseDetailView(exercise: SidesPreviewData.legs.exercises[4], unitPreference: .metric)
    }
}
#endif
