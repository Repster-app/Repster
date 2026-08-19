// BaselineMeterView.swift
// This week against the user's own usual week, drawn as two labelled bars.
//
// Shared by the Insights status card and the Home hook so the two can't drift.
// (File name is historical — the meter it held became the comparison below.)
//
// What this replaces: one bar with a tick on it and "your baseline" captioned
// underneath, while the number the tick stood for ("8-week avg 16") sat at the
// far end of the card. Every part of that had to be decoded — the track's
// length meant nothing on its own, the tick was a notation, and the reader had
// to carry a number across the card to give the notation a value. Two bars on
// one scale, each labelled with what it is and ending in what it counts, states
// the same comparison with nothing to learn first.
//
// Colour still carries no verdict: the gap between the two bars is the message
// and the headline above states it in words. Tinting by direction would assert
// that more volume is better, which is the same reason MuscleVolumePanelView
// leaves its deltas uncoloured.

import SwiftUI

/// The comparison's arithmetic, split out from the view so the range it has to
/// survive can be asserted rather than eyeballed.
struct WeekComparisonGeometry: Equatable {
    let currentFraction: Double
    let usualFraction: Double

    /// The longer of the two bars fills the track. With both bars drawn and
    /// labelled there is nothing to mistake a full bar for — it is simply the
    /// larger of two quantities, not a meter that has run out.
    init(current: Int, usual: Double) {
        let scale = max(Double(current), usual)
        guard scale > 0 else {
            currentFraction = 0
            usualFraction = 0
            return
        }
        currentFraction = Double(current) / scale
        usualFraction = usual / scale
    }

    /// The magnitude in words, so "well above your usual" comes with a size.
    /// Multiples past 1.5x, percentages inside it: "0.6x your usual" is a
    /// quantity nobody says out loud, and "150% above" past that point is worse
    /// than "2.5x".
    static func relationText(current: Int, usual: Double) -> String? {
        guard usual > 0 else { return nil }
        guard current > 0 else { return "nothing logged this week" }

        let ratio = Double(current) / usual
        if ratio >= 1.5 {
            return "\(multipleText(ratio))\u{00D7} your usual"
        }
        let percent = Int((abs(ratio - 1) * 100).rounded())
        guard percent >= 5 else { return "about your usual" }
        return ratio > 1
            ? "\(percent)% above your usual"
            : "\(percent)% below your usual"
    }

    /// One decimal, and none when it would be a trailing zero — "3x your usual"
    /// rather than "3.0x".
    private static func multipleText(_ ratio: Double) -> String {
        let rounded = (ratio * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded))"
            : String(format: "%.1f", rounded)
    }
}

struct WeekComparisonBars: View {
    let current: Int
    let usual: Double
    /// The Home hook has less room than the Insights card and sits under a
    /// subtitle that already carries the headline figure.
    var isCompact: Bool = false

    private var geometry: WeekComparisonGeometry {
        WeekComparisonGeometry(current: current, usual: usual)
    }

    private var labelWidth: CGFloat { isCompact ? 62 : 70 }
    private var barHeight: CGFloat { isCompact ? 7 : 9 }

    var body: some View {
        VStack(spacing: isCompact ? 6 : 8) {
            barRow(
                label: "This week",
                value: "\(current)",
                fraction: geometry.currentFraction,
                tint: .accent,
                isCurrent: true
            )
            barRow(
                label: "Usual week",
                value: "\(Int(usual.rounded()))",
                fraction: geometry.usualFraction,
                tint: Color.textTertiary.opacity(0.55),
                isCurrent: false
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(current) sets this week, against a usual week of \(Int(usual.rounded()))"
        )
    }

    private func barRow(
        label: String,
        value: String,
        fraction: Double,
        tint: Color,
        isCurrent: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Text(label)
                .font(.system(size: isCompact ? 10.5 : 11.5, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.bgSubtle)
                        .frame(height: barHeight)

                    if fraction > 0 {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(4, geo.size.width * fraction), height: barHeight)
                    }
                }
                .frame(height: barHeight)
                .frame(maxHeight: .infinity)
            }
            .frame(height: barHeight)

            Text(value)
                .font(.system(
                    size: isCurrent ? (isCompact ? 13 : 16) : (isCompact ? 11.5 : 13),
                    weight: isCurrent ? .bold : .medium
                ))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.textPrimary : Color.textSecondary)
                .lineLimit(1)
                .frame(width: isCompact ? 28 : 34, alignment: .trailing)
        }
    }
}

// MARK: - Previews

#Preview("Week comparison — range") {
    VStack(alignment: .leading, spacing: 22) {
        ForEach([(39, 16.0), (24, 12.0), (12, 12.0), (5, 12.0), (0, 12.0)], id: \.0) { pair in
            VStack(alignment: .leading, spacing: 6) {
                Text(WeekComparisonGeometry.relationText(current: pair.0, usual: pair.1) ?? "—")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                WeekComparisonBars(current: pair.0, usual: pair.1)
            }
        }
    }
    .padding(20)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.bg)
}
