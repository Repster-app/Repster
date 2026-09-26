// SidesCardView.swift
// Left against right on unilateral exercises. The map shows WHERE there is an
// imbalance — a muscle group lights up when any of its exercises shows a stronger
// side — and each row opens the exercises behind it, which carry the direction.
// Spec: UNILATERAL_IMBALANCE_EXPLORATION.md §4.2, D21.
//
// Never drawn when nothing has both sides logged (D10) — InsightsView checks `state`
// first, so this view never renders an empty state.

import SwiftUI

struct SidesCardView: View {
    let status: SidesStatus
    let onSelectGroup: (SideGroupSummary) -> Void

    private static let figureWidth: CGFloat = 124

    private var statuses: [String: SideGroupStatus] {
        Dictionary(uniqueKeysWithValues: status.groups.map { ($0.id, $0.status) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(alignment: .leading, spacing: 12) {
                headline
                figures
                legend

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

    // MARK: - Figures

    private var figures: some View {
        HStack(alignment: .bottom, spacing: 22) {
            figure(.front, caption: "FRONT")
            figure(.back, caption: "BACK")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(figuresAccessibilityLabel)
    }

    private func figure(_ view: BodyView, caption: String) -> some View {
        let statuses = statuses
        return VStack(spacing: 6) {
            BodyFigure(view: view) { region, _ in
                SidesBodyFill.color(region: region, statuses: statuses)
            }
            .frame(width: Self.figureWidth)

            Text(caption)
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var figuresAccessibilityLabel: String {
        let parts = status.groups.map { "\($0.displayName): \($0.status.sentence.lowercased())" }
        return (["Body map, front and back"] + parts).joined(separator: ". ")
    }

    // MARK: - Legend

    private var legendItems: [(color: Color, label: String)] {
        if status.state == .building {
            return [(.sidesCollecting, "Collecting"), (.bodyBase, "Not tracked")]
        }
        return [(.sidesImbalance, "Imbalance found"), (.sidesEven, "Even"), (.sidesCollecting, "Collecting"), (.bodyBase, "Not tracked")]
    }

    private var legend: some View {
        let items = legendItems
        return VStack(spacing: 6) {
            HStack(spacing: 14) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                    legendItem(item.color, item.label)
                }
            }
            if items.count > 3 {
                HStack(spacing: 14) {
                    ForEach(Array(items.dropFirst(3).enumerated()), id: \.offset) { _, item in
                        legendItem(item.color, item.label)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(color == .bodyBase ? Color.bodyOutline : Color.clear, lineWidth: 1)
                )
                .frame(width: 10, height: 8)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
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
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.bodyBase)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.bodyOutline, lineWidth: 1))
                .frame(width: 10, height: 8)
                .padding(.top, 4)

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
        oneSided: Int = 0
    ) -> SideExerciseSummary {
        let list = sessions(pairs)
        let classification = SidesAnalysis.classify(list)
        return SideExerciseSummary(
            id: UUID(), name: name, status: status, sessions: list,
            averageGap: classification.averageGap, leadCount: classification.leadCount,
            differingCount: classification.differingCount, bestReps: bests,
            oneSideOnlySets: oneSided, rirOnOneSideSets: 0
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
                averageGap: 0, leadCount: 0, differingCount: 0, bestReps: [], oneSideOnlySets: 0, rirOnOneSideSets: 0
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
