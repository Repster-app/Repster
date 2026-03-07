// TrendLineOverlay.swift
// Slope badge component showing trend direction and percentage change.
// Feature: 016-charts-tab-v2 WP05 (T110)

import SwiftUI

struct SlopeBadge: View {
    let trendLine: TrendLineData

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trendLine.isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text(trendLine.formattedSlope)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(trendLine.isPositive ? Color.success.opacity(0.08) : Color.danger.opacity(0.08))
        .foregroundStyle(trendLine.isPositive ? Color.success : Color.danger)
        .cornerRadius(6)
    }
}
