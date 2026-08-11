// BaselineMeterView.swift
// This week's sets against the user's own baseline, on a track that fits both.
//
// Shared by the Insights status card and the Home hook so the two can't drift.
//
// The track scales to whatever is larger — the week or the baseline — rather
// than pinning the baseline at a fixed fraction of the width. A fixed anchor
// only has room for a week that ran modestly above the norm; past that the fill
// clamps and a big week draws the same as a middling one, which is exactly when
// the meter has something to say. Scaling to the data keeps the fill honest at
// 0.2x or 4x, and the tick lands wherever the baseline actually falls.
//
// Colour carries no verdict here. Distance from the tick is the whole message,
// and the headline above states it in words — tinting by direction would assert
// that more volume is better, which is the same reason MuscleVolumePanelView
// leaves its deltas uncoloured.

import SwiftUI

/// The meter's arithmetic, split out from the view so the range it has to
/// survive can be asserted rather than eyeballed — the bug this replaces was a
/// clamp that only misbehaved past a ratio nobody previewed.
struct BaselineMeterGeometry: Equatable {
    /// Keeps the longer of the two bars off the right edge, so a fill that runs
    /// well above baseline still reads as a bar rather than a full track.
    static let headroom = 1.12

    /// Width reserved for the caption so it can be centred on the tick without
    /// measuring text. Wide enough for "your baseline" at 10pt.
    static let captionWidth: CGFloat = 76

    let fillFraction: Double
    let tickFraction: Double

    init(current: Int, baseline: Double) {
        let scale = max(Double(current), baseline) * Self.headroom
        guard scale > 0 else {
            fillFraction = 0
            tickFraction = 0
            return
        }
        fillFraction = Double(current) / scale
        tickFraction = baseline / scale
    }

    /// Centres the caption under the tick, clamped so it stays inside the track
    /// when the baseline sits near either end.
    func captionOffset(width: CGFloat) -> CGFloat {
        let centred = width * tickFraction - Self.captionWidth / 2
        return min(max(0, centred), max(0, width - Self.captionWidth))
    }
}

struct BaselineMeter: View {
    let current: Int
    let baseline: Double
    /// The Insights card labels the tick; the Home hook is too compact for it.
    var showsCaption: Bool = false

    private var geometry: BaselineMeterGeometry {
        BaselineMeterGeometry(current: current, baseline: baseline)
    }

    var body: some View {
        GeometryReader { geo in
            let geometry = self.geometry
            let fillFraction = geometry.fillFraction
            let tickFraction = geometry.tickFraction

            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.bgSubtle)
                        .frame(height: 7)

                    Capsule()
                        .fill(Color.accent)
                        .frame(width: max(4, geo.size.width * fillFraction), height: 7)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.textSecondary)
                        .frame(width: 2, height: 13)
                        .offset(x: geo.size.width * tickFraction)
                }
                .frame(height: 13)

                if showsCaption {
                    Text("your baseline")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: BaselineMeterGeometry.captionWidth, alignment: .center)
                        .offset(x: geometry.captionOffset(width: geo.size.width))
                }
            }
        }
        .frame(height: showsCaption ? 31 : 13)
    }
}
