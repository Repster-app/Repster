// TimeSeriesBarChart.swift
// Line+Point chart with dashed trend line overlay and tap-to-select dots.
// Feature: 016-charts-tab-v2 WP07 (T120)

import SwiftUI
import Charts

struct TimeSeriesBarChart: View {
    let data: [WorkoutsTimeSeriesPoint]
    let trendLine: TrendLineData?
    let yAxisLabel: String
    var selectedIndex: Int?
    var onSelectIndex: ((Int) -> Void)?

    @State private var rawSelectedDate: Date?

    var body: some View {
        Chart {
            // Single continuous line connecting all data points
            ForEach(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Series", "Data")
                )
                .foregroundStyle(Color.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.linear)
            }

            // Dots on each data point
            ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(Color.accent)
                .symbolSize(index == selectedIndex ? 80 : 28)
            }

            // Selected data point highlight ring
            if let selectedIndex, selectedIndex >= 0, selectedIndex < data.count {
                let point = data[selectedIndex]
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(Color.accent.opacity(0.3))
                .symbolSize(120)
            }

            // Trend line as dashed overlay
            if let trend = trendLine, data.count >= 2 {
                let startY = trend.startPoint.y
                let endY = trend.endPoint.y
                LineMark(
                    x: .value("Date", data.first!.date),
                    y: .value("Trend", max(startY, 0)),
                    series: .value("Series", "Trend")
                )
                .foregroundStyle(trend.isPositive ? Color.success : Color.danger)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

                LineMark(
                    x: .value("Date", data.last!.date),
                    y: .value("Trend", max(endY, 0)),
                    series: .value("Series", "Trend")
                )
                .foregroundStyle(trend.isPositive ? Color.success : Color.danger)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .onChange(of: rawSelectedDate) { _, newDate in
            guard let newDate else { return }
            // Find closest data point to the tapped date
            let closest = data.enumerated().min(by: {
                abs($0.element.date.timeIntervalSince(newDate)) < abs($1.element.date.timeIntervalSince(newDate))
            })
            if let closest {
                onSelectIndex?(closest.offset)
            }
        }
        .frame(height: 220)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.border)
                AxisValueLabel()
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .chartLegend(.hidden)
    }
}
