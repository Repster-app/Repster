// RecentWorkoutCardView.swift
// Single card displaying a recent completed workout's summary.
// Compact design with title + date header, inline stats, and flowing muscle tags.
// Spec: 013-home-screen, WP03 T016

import SwiftUI

struct RecentWorkoutCardView: View {
    let summary: RecentWorkoutSummary
    let unitPreference: UnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + Date on same row
            HStack(alignment: .firstTextBaseline) {
                Text(summary.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Text(formatDate(summary.date))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            // Compact inline stats row
            HStack(spacing: 12) {
                statPill(icon: "dumbbell", value: "\(summary.exerciseCount)")
                statPill(icon: "checkmark.circle", value: "\(summary.setCount) sets")
                statPill(icon: "clock", value: formatDuration(summary.durationMinutes))
                if let primaryMetric = summary.primaryMetric {
                    statPill(
                        icon: primaryMetric.systemImageName,
                        value: primaryMetric.formattedValue(unitPreference: unitPreference)
                    )
                }
            }

            // Muscle group tags – flowing layout that doesn't break words
            if !summary.muscleGroups.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(summary.muscleGroups, id: \.self) { muscle in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(MuscleGroupColors.color(for: muscle))
                                .frame(width: 4, height: 4)
                            Text(ExercisePrimaryGroup.displayName(for: muscle))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.bgSubtle)
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Components

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 1 { return "< 1m" }
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - FlowLayout (wrapping horizontal layout)

/// A layout that arranges children horizontally, wrapping to the next line when needed.
/// Prevents word-breaking on muscle group tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                // Wrap to next line
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }

        return (
            size: CGSize(width: totalWidth, height: y + rowHeight),
            positions: positions
        )
    }
}
