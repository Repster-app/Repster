// ChartLegend.swift
// Color-coded legend for donut chart segments and line chart series.
// Feature: 016-charts-tab-v2 WP05 (T111)

import SwiftUI

struct ChartLegendItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String?
    let color: Color
}

struct ChartLegend: View {
    let items: [ChartLegendItem]
    var columns: Int = 2

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridItems, alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color)
                        .frame(width: 10, height: 10)
                    Text(item.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    if let value = item.value {
                        Text(value)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
    }
}
