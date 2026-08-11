// TrainingInsightsHookView.swift
// Home entry point for Training Insights.
//
// Replaces the old teaser one-for-one. The difference that matters isn't the
// styling: the old card had nothing to show unless a rule had fired, so most
// users most weeks saw "Unlocks as you log workouts" and learned not to tap it.
// This one renders the week's status every week, and the badge means "there's
// advice as well" rather than "this card finally has a reason to exist".
//
// Provisional — variant B ("meter") from the design review. The open direction
// is a figures-first treatment matching MonthlyStatsCardView's grammar, which
// is what Home actually speaks.

import SwiftUI

struct TrainingInsightsHookView: View {
    let status: TrainingStatus?
    let newCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRAINING INSIGHTS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.textTertiary)

            VStack(spacing: 10) {
                HStack(spacing: 11) {
                    Image(systemName: mark.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(mark.tint)
                        .frame(width: 34, height: 34)
                        .background(mark.tint.opacity(0.12))
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if newCount > 0 {
                        Text("\(newCount)")
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.bg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accent)
                            .cornerRadius(9)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }

                if let baseline = status?.baselineSets, baseline > 0 {
                    BaselineMeter(current: status?.currentSets ?? 0, baseline: baseline)
                }
            }
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your training status and findings")
    }

    private var headline: String {
        guard let status, status.hasData else { return "Training status" }
        return status.band?.headline ?? "Your first weeks"
    }

    private var subtitle: String {
        guard let status, status.hasData else {
            return "Builds as you log workouts"
        }
        let sets = "\(status.currentSets) set\(status.currentSets == 1 ? "" : "s") this week"
        guard let baseline = status.baselineSets, baseline > 0 else { return sets }
        return "\(sets) · you average \(Int(baseline.rounded()))"
    }

    /// Matches TrainingStatusCardView: one calm tint for every band, so neither
    /// surface implies a light week went wrong. See the note there.
    private var mark: (symbol: String, tint: Color) {
        status?.band == nil
            ? ("circle.dashed", .stale)
            : ("circle.righthalf.filled", .accent)
    }
}
