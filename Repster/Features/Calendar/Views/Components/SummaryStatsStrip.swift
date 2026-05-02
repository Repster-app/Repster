// SummaryStatsStrip.swift
// Horizontal stats strip: volume, exercises, sets, optional duration.
// Spec: 008-calendar-tab, WP03 T011. Pattern: design-system.md Section 6.2 "Summary Stat Card"

import SwiftUI

struct SummaryStatsStrip: View {
    let primaryMetric: WorkoutPrimaryMetric?
    let exerciseCount: Int
    let setCount: Int
    let duration: Int?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(statItems.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    divider
                }
                statItem(value: item.value, label: item.label)
            }
        }
        .padding(14)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Components

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.border)
            .frame(width: 1)
            .padding(.vertical, 2)
    }

    private var statItems: [(label: String, value: String)] {
        var items: [(label: String, value: String)] = []

        if let primaryMetric {
            items.append((
                label: primaryMetric.label.uppercased(),
                value: primaryMetric.formattedValue()
            ))
        }

        items.append((label: "EXERCISES", value: "\(exerciseCount)"))
        items.append((label: "SETS", value: "\(setCount)"))

        if let duration {
            items.append((label: "DURATION", value: formatDuration(duration)))
        }

        return items
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
