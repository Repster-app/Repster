// SidesCardView.swift
// Left against right on unilateral exercises. The map shows WHERE there is an
// imbalance — a muscle group lights up when any of its exercises shows a stronger
// side — and each row opens the exercises behind it, which carry the direction.
// Spec: UNILATERAL_IMBALANCE_EXPLORATION.md §4.2, D21.
//
// Never drawn when nothing has both sides logged (D10) — InsightsView checks `state`
// first, so this view never renders an empty state.
//
// The body figures were archived on 2026-09-29: two 244pt figures made this card ~650pt, about a
// screenful, and they carried no information the group rows don't say in words. `BodyFigure`,
// `BodyMapGeometry`, `SidesBodyFill` and the generated paths all stay, kept compiling and correct
// by SidesAnalysisTests — including the mirror trap, where the library's `left` is the figure's
// right on the front view only. Restoring the map is putting `figures` and `legend` back here.

import SwiftUI

struct SidesCardView: View {
    let status: SidesStatus
    let onSelectGroup: (SideGroupSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(alignment: .leading, spacing: 12) {
                headline

                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)

                VStack(spacing: 2) {
                    ForEach(status.groups) { group in
                        row(group)
                    }
                }

                if !status.untrackedGroupNames.isEmpty {
                    coverageNote
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("LEFT VS RIGHT")
            Spacer(minLength: 8)
            Text("RECENT SESSIONS")
        }
        .font(.system(size: 11, weight: .semibold))
        .kerning(0.8)
        .foregroundStyle(Color.textTertiary)
        .accessibilityElement(children: .combine)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(headlineText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitleText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headlineText: String {
        switch status.state {
        case .building:
            return "Building your baseline"
        case .even:
            return "Both sides are even"
        case .possible:
            let count = status.possibleGroupCount
            return count == 1 ? "Possible imbalance in 1 muscle group" : "Possible imbalances in \(count) muscle groups"
        case .imbalanced, .hidden:
            let count = status.imbalancedGroupCount
            return count == 1 ? "Imbalance found in 1 muscle group" : "Imbalances found in \(count) muscle groups"
        }
    }

    private var subtitleText: String {
        if status.state == .building {
            return "Each exercise needs \(SidesAnalysis.minSessions) sessions with both sides logged"
        }
        if status.state == .possible {
            return "It needs a few more sessions to confirm"
        }
        return "Your last \(SidesAnalysis.sessionsConsidered) sessions of each exercise, compared at the same weight"
    }

    // MARK: - Rows

    /// No strength mark here: a group has no single degree — its exercises do.
    private func row(_ group: SideGroupSummary) -> some View {
        Button {
            onSelectGroup(group)
        } label: {
            HStack(spacing: 10) {
                Text(group.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: 76, alignment: .leading)

                Text(group.status.sentence)
                    .font(.system(size: 13, weight: group.status.isImbalance ? .semibold : .medium))
                    .foregroundStyle(group.status.isImbalance ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.displayName), \(group.status.sentence)")
        .accessibilityHint("Shows the exercises behind it")
    }

    // MARK: - Coverage

    private var coverageNote: some View {
        let names = status.untrackedGroupNames
        let list = ListFormatter.localizedString(byJoining: names)
        let verb = names.count == 1 ? "isn’t" : "aren’t"
        return HStack(alignment: .top, spacing: 8) {
            Text("\(list) \(verb) tracked by side — only exercises marked Unilateral, with left and right logged, count.")
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

/// Three bars, one to three lit — an exercise's degree, for scanning (D14).
struct SideStrengthMark: View {
    let status: SideStatus

    private static let heights: [CGFloat] = [5, 8, 11]

    var body: some View {
        let level = status.degree?.rawValue ?? 0
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < level ? Color.sidesStronger : Color.bgSubtle)
                    .frame(width: 3, height: Self.heights[index])
            }
        }
        .frame(width: 17, height: 11, alignment: .bottom)
        .opacity(level == 0 ? 0 : 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#if DEBUG
enum SidesPreviewData {
    static func sessions(_ pairs: [(left: Double, right: Double)]) -> [SideSession] {
        pairs.enumerated().map { index, pair in
            SideSession(
                id: UUID(),
                date: Calendar.current.date(byAdding: .day, value: -7 * (pairs.count - index), to: Date()) ?? Date(),
                left: pair.left,
                right: pair.right
            )
        }
    }

    static func exercise(
        _ name: String,
        _ status: SideStatus,
        _ pairs: [(left: Double, right: Double)],
        bests: [SideBestRow] = [],
        oneSided: Int = 0,
        canTrackSides: Bool = true
    ) -> SideExerciseSummary {
        let list = sessions(pairs)
        let classification = SidesAnalysis.classify(list)
        return SideExerciseSummary(
            id: UUID(), name: name, status: status, sessions: list,
            averageGap: classification.averageGap, leadCount: classification.leadCount,
            differingCount: classification.differingCount, bestReps: bests,
            oneSideOnlySets: oneSided, rirOnOneSideSets: 0, canTrackSides: canTrackSides
        )
    }

    static let legs = SideGroupSummary(
        id: "legs",
        displayName: "Legs",
        status: .imbalance(exercises: 3),
        exercises: [
            exercise("One Legged Leg Curl", .stronger(.right, .clearly), [(9, 9.5), (9, 10), (7, 9.5)],
                     // Matched reps, different reserve: the case the old table drew as a tie.
                     bests: [SideBestRow(weight: 30, left: 6, right: 6, leftRIR: 1, rightRIR: 2),
                             SideBestRow(weight: 25, left: 10, right: 10, leftRIR: 0, rightRIR: 1)]),
            exercise("Leg Extension - 1 leg", .stronger(.left, .slightly), [(12, 12), (9, 8), (13, 13), (9, 7.5), (10, 9), (10.5, 10.5)],
                     bests: [SideBestRow(weight: 50, left: 9, right: 9, leftRIR: 2, rightRIR: 1),
                             SideBestRow(weight: 45, left: 12, right: 12, leftRIR: nil, rightRIR: nil)], oneSided: 1),
            exercise("1 Leg Stand Up", .stronger(.right, .slightly), [(7.5, 8), (9, 9), (8.5, 8.5), (10, 11), (12, 12), (7, 10)]),
            exercise("1 Legged Hip Thrust", .possible(.left), [(11, 9.5), (10.5, 8.5), (9.5, 9.5)]),
            exercise("Leg Curl 1 Leg", .collecting(sessions: 1), [(12, 12)]),
            SideExerciseSummary(
                id: UUID(), name: "Barbell Hip Thrust", status: .notTracked(.notUnilateral), sessions: [],
                averageGap: 0, leadCount: 0, differingCount: 0, bestReps: [], oneSideOnlySets: 0,
                rirOnOneSideSets: 0, canTrackSides: true
            ),
            SideExerciseSummary(
                id: UUID(), name: "Sled Push", status: .notTracked(.notUnilateral), sessions: [],
                averageGap: 0, leadCount: 0, differingCount: 0, bestReps: [], oneSideOnlySets: 0,
                rirOnOneSideSets: 0, canTrackSides: false
            ),
        ]
    )

    static let status = SidesStatus(
        groups: [
            legs,
            SideGroupSummary(id: "shoulders", displayName: "Shoulders", status: .even, exercises: []),
            SideGroupSummary(id: "back", displayName: "Back", status: .collecting(sessions: 1), exercises: []),
        ],
        untrackedGroupNames: ["Abs", "Biceps", "Chest", "Triceps"]
    )
}

#Preview("Sides card") {
    ScrollView {
        SidesCardView(status: SidesPreviewData.status) { _ in }
            .padding(20)
    }
    .background(Color.bg)
}
#endif
