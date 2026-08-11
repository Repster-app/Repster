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
            // Gate on the band, not on baselineSets being non-nil: a baseline
            // of 0 is non-nil but useless, and comparing against it produced a
            // "8-week avg 0" reading under copy that says the baseline is still
            // being built. Band is nil in exactly the cases with nothing to
            // compare against.
            if status.band != nil {
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

    /// Calm by default, and the same for every band. Tinting by direction reads
    /// as a verdict however it's meant — green for "normal" and amber for
    /// anything else says a light week went wrong. The headline states where the
    /// week sits; the mark only says whether there's a baseline to sit against.
    private var mark: (symbol: String, tint: Color) {
        status.band == nil
            ? ("circle.dashed", .stale)
            : ("circle.righthalf.filled", .accent)
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

            BaselineMeter(
                current: status.currentSets,
                baseline: status.baselineSets ?? 0,
                showsCaption: true
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(status.currentSets) sets in the last 7 days, against a baseline of \(Int((status.baselineSets ?? 0).rounded()))"
        )
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

// MARK: - Previews

/// Ratios chosen to cover the range the meter has to survive, including the
/// ones the old fixed-anchor version drew identically.
#Preview("Status card — range") {
    func status(_ current: Int, _ baseline: Double?) -> TrainingStatus {
        TrainingStatus(
            currentSets: current,
            baselineSets: baseline,
            muscles: [],
            hasData: true
        )
    }

    return ScrollView {
        VStack(spacing: 12) {
            TrainingStatusCardView(status: status(24, 6))    // 4.0x
            TrainingStatusCardView(status: status(24, 12))   // 2.0x — the reported screen
            TrainingStatusCardView(status: status(12, 12))   // 1.0x
            TrainingStatusCardView(status: status(5, 12))    // 0.4x
            TrainingStatusCardView(status: status(0, 12))    // nothing logged
            TrainingStatusCardView(status: status(9, nil))   // no baseline yet
        }
        .padding(16)
    }
    .background(Color.bg)
}
