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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    SidesDivider()
                    SidesSectionLabel(text: "EXERCISES")

                    VStack(spacing: 0) {
                        ForEach(Array(group.exercises.enumerated()), id: \.element.id) { index, exercise in
                            exerciseRow(exercise, isLast: index == group.exercises.count - 1)
                        }
                    }
                    .padding(.top, -8)

                    Text("Each exercise is judged on its last \(SidesAnalysis.sessionsConsidered) sessions, comparing both sides at the same weight.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color.bgCard)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let exercise = group.exercises.first(where: { $0.id == id }) {
                    SideExerciseDetailView(exercise: exercise, unitPreference: unitPreference) {
                        onExerciseOpened(exercise)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgCard)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            BodyFigure(view: thumbnailView) { region, _ in
                SidesBodyFill.color(region: region, statuses: [group.id: group.status], only: group.id)
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text(group.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .kerning(-0.3)
                    .foregroundStyle(Color.textPrimary)

                Text(SidesCopy.statusLine(for: group))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(trackedChip)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.bgSubtle)
                    .cornerRadius(6)
            }
        }
    }

    /// Groups that live on the back of the body show the back.
    private var thumbnailView: BodyView {
        ["back", "glutes", "hamstrings"].contains(group.id) ? .back : .front
    }

    private var trackedChip: String {
        let count = group.trackedExerciseCount
        return count == 1 ? "1 exercise tracked" : "\(count) exercises tracked"
    }

    // MARK: - Rows

    @ViewBuilder
    private func exerciseRow(_ exercise: SideExerciseSummary, isLast: Bool) -> some View {
        let tracked = exercise.status.isTracked
        let content = VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(exercise.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(tracked ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if tracked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            HStack(spacing: 10) {
                Text(exercise.status.sentence)
                    .font(.system(size: 12.5, weight: exercise.status.isStronger ? .semibold : .medium))
                    .foregroundStyle(
                        exercise.status.isStronger ? Color.textPrimary : (tracked ? Color.textSecondary : Color.textTertiary)
                    )
                Spacer(minLength: 0)
                SideStrengthMark(status: exercise.status)
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

        if tracked {
            NavigationLink(value: exercise.id) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows each session")
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Exercise

struct SideExerciseDetailView: View {
    let exercise: SideExerciseSummary
    let unitPreference: UnitPreference
    var onFirstAppear: () -> Void = {}

    @State private var hasReportedOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(SidesCopy.statusLine(for: exercise))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let gap = SidesCopy.gapLine(for: exercise) {
                        Text(gap)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !exercise.sessions.isEmpty {
                    SidesSectionLabel(text: "EACH SESSION, BOTH SIDES")
                    SideDifferenceChart(sessions: exercise.sessions)
                }

                if !exercise.bestReps.isEmpty {
                    SidesSectionLabel(text: "BEST REPS PER SIDE")
                    bestTable
                }

                if let note = incompleteNote {
                    noteView(note)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
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

    private var bestTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("WEIGHT")
                Spacer(minLength: 8)
                Text("LEFT").frame(width: 60, alignment: .trailing)
                Text("RIGHT").frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(Color.textTertiary)
            .padding(.bottom, 6)

            ForEach(exercise.bestReps) { row in
                HStack(spacing: 0) {
                    Text(weightLabel(row.weight))
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 8)
                    Text("\(row.left)")
                        .foregroundStyle(row.left >= row.right ? Color.textPrimary : Color.textSecondary)
                        .frame(width: 60, alignment: .trailing)
                    Text("\(row.right)")
                        .foregroundStyle(row.right >= row.left ? Color.textPrimary : Color.textSecondary)
                        .frame(width: 60, alignment: .trailing)
                }
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .padding(.vertical, 8)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.border)
                        .frame(height: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(weightLabel(row.weight)): left \(row.left), right \(row.right)")
            }
        }
    }

    private func weightLabel(_ kg: Double?) -> String {
        guard let kg else { return "Bodyweight" }
        return UnitConversion.formatWeightLabel(kg, unitPreference: unitPreference)
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

// MARK: - Chart

/// C2 (D18), per exercise: one column per session — up when the right side did more, down
/// when the left did, one to three steps tall like the strength mark. No axis numbers.
struct SideDifferenceChart: View {
    let sessions: [SideSession]

    private let step: CGFloat = 11
    private var half: CGFloat { step * 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    sideLabel("Right")
                    Spacer(minLength: 0)
                    sideLabel("Left")
                }
                .frame(width: 50, height: half * 2 + 2)

                HStack(alignment: .center, spacing: 0) {
                    ForEach(sessions) { session in
                        column(session)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: half * 2 + 2)
                .background(guides)
            }

            if let first = sessions.first, let last = sessions.last {
                HStack(spacing: 0) {
                    Text(first.date.formatted(.dateTime.month(.abbreviated).day()))
                    Spacer(minLength: 8)
                    if sessions.count > 1 {
                        Text(last.date.formatted(.dateTime.month(.abbreviated).day()))
                    }
                }
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 58)
            }

            Text("Each column is one session. Taller means a bigger difference — the same three steps as the strength mark.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func sideLabel(_ side: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(side)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text("stronger")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func column(_ session: SideSession) -> some View {
        let height = CGFloat(session.degree?.rawValue ?? 0) * step - 1
        return VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.clear
                if session.lean == .right { bar(height) }
            }
            .frame(height: half)

            ZStack {
                Color.clear
                if session.lean == nil {
                    Circle()
                        .fill(Color.textTertiary)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 2)

            ZStack(alignment: .top) {
                Color.clear
                if session.lean == .left { bar(height) }
            }
            .frame(height: half)
        }
    }

    private func bar(_ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.sidesStronger)
            .frame(minWidth: 3, maxWidth: 16)
            .frame(height: height)
    }

    private var guides: some View {
        Canvas { context, size in
            let mid = size.height / 2
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: mid))
            baseline.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(baseline, with: .color(.bodyOutline), lineWidth: 1)

            for level in 1...3 {
                for direction in [-1.0, 1.0] {
                    let y = mid + CGFloat(direction) * CGFloat(level) * step
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(Color.white.opacity(0.04)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
        }
    }

    private var accessibilitySummary: String {
        let right = sessions.filter { $0.lean == .right }.count
        let left = sessions.filter { $0.lean == .left }.count
        let even = sessions.count - right - left
        return "Of \(sessions.count) sessions, the right side was stronger in \(right), the left in \(left), and they were even in \(even)."
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
#endif
