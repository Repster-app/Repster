// InsightCardView.swift
// One insight in the feed: category pill, headline, mini chart, expandable detail.

import SwiftUI

struct InsightCardView: View {
    let insight: InsightItem
    let onSnooze: () -> Void
    var onExpand: (() -> Void)? = nil
    var onRate: ((Bool) -> Void)? = nil

    @State private var isExpanded = false
    @State private var rating: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(insight.headline)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !insight.chartValues.isEmpty {
                InsightChartView(insight: insight, color: insight.category.accentColor)
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

                ratingRow
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
            if isExpanded {
                onExpand?()
            }
        }
    }

    /// Deliberately only in the expanded state. On the collapsed card it would
    /// clutter the feed and collect reflex taps; here it's answered by people
    /// who actually read the finding.
    private var ratingRow: some View {
        HStack(spacing: 8) {
            if let rating {
                Text(rating ? "Thanks — more like this" : "Thanks — noted")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            } else {
                Text("Was this useful?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)

                ratingButton(useful: true, symbol: "hand.thumbsup")
                ratingButton(useful: false, symbol: "hand.thumbsdown")
            }

            Spacer()
        }
        .padding(.top, 2)
    }

    private func ratingButton(useful: Bool, symbol: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                rating = useful
            }
            onRate?(useful)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 30, height: 26)
                .background(Color.bgSubtle)
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(useful ? "Useful" : "Not useful")
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

extension InsightCategory {
    var accentColor: Color {
        switch self {
        case .restSweetSpot: return .orange
        case .muscleBalance: return .chart7
        case .rirCalibration: return .chart5
        case .targetAdherence: return .accent
        case .strengthTrend: return .success
        case .consistency: return .accent
        case .droppedExercise: return .orange
        case .volumeRamp: return .chart5
        case .deloadReadiness: return .danger
        case .prPace: return .gold
        case .other: return .stale
        }
    }
}
