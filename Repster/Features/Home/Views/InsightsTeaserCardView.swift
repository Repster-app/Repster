// InsightsTeaserCardView.swift
// Home screen entry card for the Insights feed, with a new-findings badge.

import SwiftUI

struct InsightsTeaserCardView: View {
    let newCount: Int
    let topHeadline: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INSIGHTS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.gold)
                    .frame(width: 34, height: 34)
                    .background(Color.goldSoft)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(topHeadline ?? "Findings from your training data")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 8)

                if newCount > 0 {
                    Text("\(newCount) new")
                        .font(.system(size: 11, weight: .bold))
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
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
    }

    private var subtitle: String {
        if newCount > 0 {
            return newCount == 1 ? "1 new finding to read" : "\(newCount) new findings to read"
        }
        return topHeadline == nil
            ? "Unlocks as you log workouts"
            : "Tap to review your findings"
    }
}
