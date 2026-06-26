// InsightCardView.swift
// One insight in the feed: category pill, headline, mini chart, expandable detail.

import SwiftUI

struct InsightCardView: View {
    let insight: InsightItem
    let onSnooze: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(insight.headline)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !insight.chartValues.isEmpty {
                InsightMiniChartView(
                    labels: insight.chartLabels,
                    values: insight.chartValues,
                    color: insight.category.accentColor
                )
            }

            Text(insight.detailText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text(insight.methodologyText)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(insight.category.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(insight.category.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(insight.category.accentColor.opacity(0.12))
                .cornerRadius(6)

            if let subjectName = insight.subjectName {
                Text(subjectName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            if insight.isNew {
                Text("NEW")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentSoft)
                    .cornerRadius(5)
            }

            Spacer()

            Menu {
                Button {
                    onSnooze()
                } label: {
                    Label("Snooze for 3 weeks", systemImage: "clock.badge.xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
        }
    }
}

/// Compact capsule bar chart for the values a finding is based on.
/// Negative values (e.g. underperformance) render in the danger color.
struct InsightMiniChartView: View {
    let labels: [String]
    let values: [Double]
    let color: Color

    private var maxMagnitude: Double {
        max(values.map(abs).max() ?? 1, 0.001)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(value < 0 ? Color.danger : color)
                        .frame(height: max(6, CGFloat(abs(value) / maxMagnitude) * 44))
                        .frame(maxHeight: 44, alignment: .bottom)

                    if index < labels.count {
                        Text(labels[index])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }
}

extension InsightCategory {
    var accentColor: Color {
        switch self {
        case .restSweetSpot: return .orange
        case .muscleBalance: return .chart7
        case .prRhythm: return .gold
        case .rirCalibration: return .chart5
        case .targetAdherence: return .accent
        case .other: return .stale
        }
    }
}
