// MultiLineChart.swift
// Multi-series LineMark chart with tap-to-select, series separation, and trend line.
// Feature: 016-charts-tab-v2 WP08 (T126)

import SwiftUI
import Charts

struct MultiLineChart: View {
    let series: [ExerciseProgressSeries]
    let trendLine: TrendLineData?
    let yAxisLabel: String
    var selectedIndex: Int?
    var onSelectIndex: ((Int) -> Void)?

    @State private var rawSelectedDate: Date?

    var body: some View {
        Chart {
            // Lines per exercise series (separate ForEach for lines only)
            ForEach(series) { s in
                ForEach(s.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Series", s.name)
                    )
                    .foregroundStyle(s.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Dots per exercise series (separate ForEach to avoid dual-series)
            ForEach(series) { s in
                ForEach(s.points) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(s.color)
                    .symbolSize(24)
                }
            }

            // Selected point highlight (first series only for navigation)
            if let selectedIndex, let firstSeries = series.first,
               selectedIndex >= 0, selectedIndex < firstSeries.points.count {
                let point = firstSeries.points[selectedIndex]
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(firstSeries.color)
                .symbolSize(80)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(firstSeries.color.opacity(0.3))
                .symbolSize(120)
            }

            // Trend line for first series (dashed, separate series)
            if let trend = trendLine, let firstSeries = series.first,
               firstSeries.points.count >= 2 {
                let startY = trend.startPoint.y
                let endY = trend.endPoint.y

                LineMark(
                    x: .value("Date", firstSeries.points.first!.date),
                    y: .value("Trend", max(startY, 0)),
                    series: .value("Series", "Trend")
                )
                .foregroundStyle(trend.isPositive ? Color.success : Color.danger)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

                LineMark(
                    x: .value("Date", firstSeries.points.last!.date),
                    y: .value("Trend", max(endY, 0)),
                    series: .value("Series", "Trend")
                )
                .foregroundStyle(trend.isPositive ? Color.success : Color.danger)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .onChange(of: rawSelectedDate) { _, newDate in
            guard let newDate, let firstSeries = series.first else { return }
            // Find closest point in first series
            let closest = firstSeries.points.enumerated().min(by: {
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
