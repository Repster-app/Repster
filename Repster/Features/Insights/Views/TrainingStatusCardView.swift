// TrainingStatusCardView.swift
// Where the trailing week sits against the user's own recent norm.
//
// Everything here is arithmetic on the user's own data, so it always renders
// and can never be wrong the way a finding can. It states the comparison rather
// than scoring it — a score invites arguing with it, and there's nothing to win
// in that argument.

import SwiftUI

struct TrainingStatusCardView: View {
    let status: TrainingStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if status.baselineSets != nil {
                comparison
            } else {
                coldStartFigure
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: mark.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(mark.tint)
                .frame(width: 34, height: 34)
                .background(mark.tint.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var headline: String {
        guard status.hasData else { return "No sets logged yet" }
        return status.band?.headline ?? "Your first weeks"
    }

    private var subtitle: String {
        guard status.hasData else {
            return "Your training status builds as you log workouts"
        }
        guard status.band != nil else {
            return "Building your baseline — comparisons start in a few weeks"
        }
        return "Last 7 days"
    }

    /// Calm by default. The mark reflects distance from the user's norm in
    /// either direction; it never implies that more volume is better.
    private var mark: (symbol: String, tint: Color) {
        switch status.band {
        case .normal:                 return ("circle.righthalf.filled", .success)
        case .wellBelow, .wellAbove:  return ("circle.lefthalf.filled", .gold)
        case .below, .above:          return ("circle.righthalf.filled", .gold)
        case nil:                     return ("circle.dashed", .stale)
        }
    }

    // MARK: - Comparison

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(status.currentSets)")
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text("SETS")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Color.textTertiary)

                Spacer(minLength: 8)

                Text("8-week avg \(Int((status.baselineSets ?? 0).rounded()))")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }

            meter

            HStack {
                Text("this week")
                Spacer()
                Text("your baseline")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(status.currentSets) sets in the last 7 days, against a baseline of \(Int((status.baselineSets ?? 0).rounded()))"
        )
    }

    private var meter: some View {
        GeometryReader { geo in
            let baseline = status.baselineSets ?? 0
            // The baseline tick sits at 74% so there's headroom to render a week
            // that ran above it without the bar pinning at full width.
            let tickFraction = 0.74
            let scale = baseline > 0 ? tickFraction / baseline : 0
            let fillFraction = min(1.0, Double(status.currentSets) * scale)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.bgSubtle)
                    .frame(height: 7)

                Capsule()
                    .fill(mark.tint)
                    .frame(width: max(4, geo.size.width * fillFraction), height: 7)

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.textSecondary)
                    .frame(width: 2, height: 13)
                    .offset(x: geo.size.width * tickFraction)
            }
            .frame(height: 13)
        }
        .frame(height: 13)
    }

    // MARK: - Cold start

    /// Before there's a baseline the card states what it has rather than
    /// apologising for what it doesn't. No progress bar toward unlocking.
    private var coldStartFigure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(status.currentSets)")
                .font(.system(size: 24, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text(status.currentSets == 1 ? "SET IN THE LAST 7 DAYS" : "SETS IN THE LAST 7 DAYS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Color.textTertiary)
            Spacer(minLength: 0)
        }
    }
}
