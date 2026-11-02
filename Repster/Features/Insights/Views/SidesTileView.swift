// SidesTileView.swift
// Left against right on Insights: one tile, in the shape of the status card's header, that opens
// the list of exercises. Spec: SIDES_RETHINK_SCOPING.md, D25.
//
// Never drawn when nothing has both sides logged (D10) — InsightsView checks `state` first, so
// this view never renders an empty state.
//
// The body figures that used to sit here were archived on 2026-09-29, and the card they sat on is
// gone too (D25), so bringing the map back means finding it a new home. `BodyFigure` and the
// generated paths compile only under REPSTER_BODY_MAP (D32), and SidesAnalysisTests keeps the
// mirror trap pinned, where the library's `left` is the figure's right on the front view only.

import SwiftUI

struct SidesTileView: View {
    let status: SidesStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LEFT VS RIGHT")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.textTertiary)

            NavigationLink(value: SidesRoute.list) {
                SidesTile(
                    mark: SidesTileMark(state: status.state),
                    title: SidesCopy.tileHeadline(for: status),
                    subtitle: SidesCopy.tileSubtitle(for: status)
                ) {
                    SidesChevron()
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows each exercise")
        }
    }
}

// MARK: - Tile

/// The one row shape behind the Insights tile, the list and the exercise verdict, so tapping a
/// tile lands on the same tile at the top of the next page.
struct SidesTile<Trailing: View>: View {
    let mark: SidesTileMark
    let title: String
    let subtitle: String
    var subtitleColor: Color
    let trailing: Trailing

    init(
        mark: SidesTileMark,
        title: String,
        subtitle: String,
        subtitleColor: Color = .textSecondary,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.mark = mark
        self.title = title
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            SidesTileBox(mark: mark)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// What the 34pt box at the head of a tile shows. Dashed when the claim isn't confirmed: an
/// unconfirmed lean gets no solid mark anywhere in the feature (D24).
struct SidesTileMark: Equatable {
    enum Glyph: Equatable {
        case arrows
        case side(SideLean)
        case equal
        case collecting
    }

    let glyph: Glyph
    let tint: Color
    var isDashed = false

    init(glyph: Glyph, tint: Color, isDashed: Bool = false) {
        self.glyph = glyph
        self.tint = tint
        self.isDashed = isDashed
    }

    init(state: SidesCardState) {
        switch state {
        case .imbalanced, .hidden:
            self.init(glyph: .arrows, tint: .sidesStronger)
        case .possible:
            self.init(glyph: .arrows, tint: .sidesStronger, isDashed: true)
        case .even:
            self.init(glyph: .arrows, tint: .sidesEvenBright)
        case .building:
            self.init(glyph: .collecting, tint: .stale)
        }
    }

    init(status: SideStatus) {
        switch status {
        case let .stronger(lean, _):
            self.init(glyph: .side(lean), tint: .sidesStronger)
        case let .possible(lean):
            self.init(glyph: .side(lean), tint: .sidesStronger, isDashed: true)
        case .even:
            self.init(glyph: .equal, tint: .sidesEvenBright)
        case .collecting, .notTracked:
            self.init(glyph: .collecting, tint: .stale)
        }
    }
}

private struct SidesTileBox: View {
    let mark: SidesTileMark

    var body: some View {
        glyph
            .foregroundStyle(mark.tint)
            .frame(width: 34, height: 34)
            .background {
                if mark.isDashed {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(mark.tint.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(mark.tint.opacity(0.12))
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch mark.glyph {
        case .arrows:
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 15, weight: .semibold))
        case let .side(lean):
            Text(lean == .left ? "L" : "R")
                .font(.system(size: 15, weight: .bold))
        case .equal:
            Text("=")
                .font(.system(size: 17, weight: .bold))
        case .collecting:
            Image(systemName: "circle.dashed")
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

struct SidesChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.textTertiary)
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
    /// `pairs` are capacities, one per session. The best set takes the reserve back off, so a row
    /// adds up to the point it sits under. Pass a nil `rir` for an exercise logged without it.
    static func sessions(_ pairs: [(left: Double, right: Double)], rir: Double? = 1) -> [SideSession] {
        pairs.enumerated().map { index, pair in
            SideSession(
                id: UUID(),
                date: Calendar.current.date(byAdding: .day, value: -7 * (pairs.count - index), to: Date()) ?? Date(),
                left: pair.left,
                right: pair.right,
                bestSet: SideBestRow(
                    weight: 22.5,
                    left: Int(pair.left - (rir ?? 0)),
                    right: Int(pair.right - (rir ?? 0)),
                    leftRIR: rir,
                    rightRIR: rir
                ),
                setCount: 3,
                rirSetCount: rir == nil ? 0 : 3
            )
        }
    }

    static func exercise(
        _ name: String,
        _ status: SideStatus,
        _ pairs: [(left: Double, right: Double)],
        rir: Double? = 1,
        bests: [SideBestRow] = [],
        oneSided: Int = 0,
        canTrackSides: Bool = true
    ) -> SideExerciseSummary {
        let list = sessions(pairs, rir: rir)
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
            exercise("One Legged Leg Curl", .stronger(.right, .clearly), [(9, 10.5), (9, 9.5), (10, 10), (8, 10), (9, 10.5), (8.5, 10)]),
            exercise("Leg Extension - 1 leg", .stronger(.left, .slightly), [(12, 12), (9, 8), (13, 13), (9, 7.5), (10, 9), (10.5, 10.5)], oneSided: 1),
            exercise("1 Leg Stand Up", .stronger(.right, .slightly), [(7.5, 8), (9, 9), (8.5, 8.5), (10, 11), (12, 12), (7, 10)], rir: nil),
            exercise("1 Legged Hip Thrust", .possible(.left), [(11, 9.5), (10.5, 8.5), (9.5, 9.5)]),
            exercise("Leg Curl 1 Leg", .collecting(sessions: 1), [(12, 12)]),
            untracked[0],
            untracked[1],
        ]
    )

    static let untracked = [
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

    static let status = SidesStatus(
        groups: [
            legs,
            SideGroupSummary(id: "shoulders", displayName: "Shoulders", status: .even, exercises: [
                exercise("Cable Lateral Raise", .even, [(10, 10), (9, 9.5), (11, 10.5), (10, 10), (9.5, 9.5), (12, 12)], rir: nil),
            ]),
            SideGroupSummary(id: "back", displayName: "Back", status: .collecting(sessions: 1), exercises: [
                exercise("Dumbbell Row", .collecting(sessions: 1), [(10, 11)]),
            ]),
        ],
        untrackedExercises: untracked
    )
}

#Preview("Left vs right tile") {
    NavigationStack {
        ScrollView {
            SidesTileView(status: SidesPreviewData.status)
                .padding(20)
        }
        .background(Color.bg)
    }
}
#endif
