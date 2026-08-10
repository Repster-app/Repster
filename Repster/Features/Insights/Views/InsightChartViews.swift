// InsightChartViews.swift
// One component per InsightChartKind.
//
// v1 drew every finding as the same capsule bar chart, which made a two-group
// comparison, a proportion and a signed time series look identical — and threw
// away the sign on the one where the sign was the whole point.

import SwiftUI

/// Picks the component that matches the finding's data shape.
struct InsightChartView: View {
    let insight: InsightItem
    let color: Color

    var body: some View {
        switch insight.chartKind {
        case .series:
            if InsightChartKind.signedSeriesRules.contains(insight.ruleId) {
                InsightSignedSeriesChart(values: insight.chartValues, labels: insight.chartLabels)
            } else {
                InsightSeriesChart(values: insight.chartValues, color: color)
            }
        case .column:
            InsightColumnChart(values: insight.chartValues, color: color)
        case .ranking:
            InsightRankingChart(labels: insight.chartLabels, values: insight.chartValues, color: color)
        case .proportion:
            InsightProportionChart(labels: insight.chartLabels, values: insight.chartValues)
        case .comparison:
            InsightComparisonChart(labels: insight.chartLabels, values: insight.chartValues, color: color)
        case .range:
            InsightRangeChart(labels: insight.chartLabels, values: insight.chartValues, color: color)
        case .timeline:
            InsightTimelineChart(values: insight.chartValues, color: color)
        }
    }
}

// MARK: - Series

/// A trend line with an emphasised endpoint. The y-axis is deliberately
/// unlabelled — the card's text carries the numbers; the line carries shape.
struct InsightSeriesChart: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size)
            ZStack {
                if points.count >= 2 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.13))

                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .position(points[points.count - 1])
                }
            }
        }
        .frame(height: 52)
    }

    static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let span = max(maximum - minimum, 0.0001)
        let inset: CGFloat = 5
        let usable = max(size.height - inset * 2, 1)

        return values.enumerated().map { index, value in
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                y: inset + usable * (1 - CGFloat((value - minimum) / span))
            )
        }
    }
}

/// Bars around a zero line, for series where the sign is the finding —
/// performance against prediction, not a magnitude.
struct InsightSignedSeriesChart: View {
    let values: [Double]
    let labels: [String]

    var body: some View {
        GeometryReader { geo in
            let scale = max(values.map(abs).max() ?? 1, 0.001)
            let midpoint = geo.size.height / 2

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)
                    .offset(y: midpoint)

                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        let height = max(3, midpoint * CGFloat(abs(value) / scale))
                        VStack(spacing: 0) {
                            if value >= 0 {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.success)
                                    .frame(height: height)
                                Spacer(minLength: 0).frame(height: midpoint)
                            } else {
                                Spacer(minLength: 0).frame(height: midpoint)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.danger)
                                    .frame(height: height)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 52)
        .accessibilityLabel(
            "\(values.filter { $0 < 0 }.count) of \(values.count) below expectation"
        )
    }
}

// MARK: - Column

/// One bar per period, latest emphasised.
struct InsightColumnChart: View {
    let values: [Double]
    let color: Color

    var body: some View {
        let scale = max(values.max() ?? 1, 0.001)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == values.count - 1 ? color : color.opacity(0.35))
                    .frame(height: max(3, 46 * CGFloat(value / scale)))
            }
        }
        .frame(height: 46, alignment: .bottom)
    }
}

// MARK: - Ranking

/// Ordered categories drawn in the subject's own colours, so a muscle-group
/// ranking reads the same here as it does in the status panel.
struct InsightRankingChart: View {
    let labels: [String]
    let values: [Double]
    let color: Color

    var body: some View {
        let scale = max(values.max() ?? 1, 0.001)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint(at: index))
                    .frame(height: max(3, 34 * CGFloat(value / scale)))
            }
        }
        .frame(height: 34, alignment: .bottom)
    }

    private func tint(at index: Int) -> Color {
        guard index < labels.count, !labels[index].isEmpty else { return color }
        return MuscleGroupColors.color(for: labels[index])
    }
}

// MARK: - Proportion

/// Parts of a whole: one stacked bar with a key. Three separate bars for
/// below/in-range/above hid the fact that they sum to 100%.
struct InsightProportionChart: View {
    let labels: [String]
    let values: [Double]

    private static let segmentColors: [Color] = [.danger, .success, .stale]

    var body: some View {
        let total = max(values.reduce(0, +), 0.001)

        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        Rectangle()
                            .fill(Self.color(at: index))
                            .frame(width: geo.size.width * CGFloat(value / total))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())

            HStack(spacing: 12) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    if index < values.count {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Self.color(at: index))
                                .frame(width: 7, height: 7)
                            Text("\(label) \(Int((values[index] / total * 100).rounded()))%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private static func color(at index: Int) -> Color {
        segmentColors[index % segmentColors.count]
    }
}

// MARK: - Comparison

/// Two groups side by side, each with its figure. A two-bar chart isn't a
/// chart; the numbers are what the reader is actually comparing.
struct InsightComparisonChart: View {
    let labels: [String]
    let values: [Double]
    let color: Color

    var body: some View {
        let scale = max(values.map(abs).max() ?? 1, 0.001)

        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(values.prefix(2).enumerated()), id: \.offset) { index, value in
                VStack(alignment: .leading, spacing: 5) {
                    Text(Self.format(value))
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)

                    Capsule()
                        .fill(Color.bgSubtle)
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(index == values.count - 1 ? color : Color.textTertiary)
                                    .frame(width: geo.size.width * CGFloat(abs(value) / scale))
                            }
                        }
                        .frame(height: 6)

                    if index < labels.count {
                        Text(labels[index].uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .kerning(0.4)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    static func format(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

// MARK: - Range

/// An interval that moved: two segments on a shared axis, so the shift is the
/// thing you see rather than four numbers you have to compare.
struct InsightRangeChart: View {
    let labels: [String]
    let values: [Double]
    let color: Color

    var body: some View {
        // values = [wasLow, wasHigh, nowLow, nowHigh]
        let bounds = values.prefix(4)
        let minimum = bounds.min() ?? 0
        let maximum = bounds.max() ?? 1
        let span = max(maximum - minimum, 0.001)

        VStack(spacing: 9) {
            if values.count >= 2 {
                lane(label: labels.first ?? "WAS", low: values[0], high: values[1],
                     minimum: minimum, span: span, tint: Color.textTertiary)
            }
            if values.count >= 4 {
                lane(label: labels.count > 1 ? labels[1] : "NOW", low: values[2], high: values[3],
                     minimum: minimum, span: span, tint: color)
            }
        }
    }

    private func lane(
        label: String, low: Double, high: Double,
        minimum: Double, span: Double, tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 38, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bgSubtle).frame(height: 9)
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: max(6, geo.size.width * CGFloat((high - low) / span)),
                            height: 9
                        )
                        .offset(x: geo.size.width * CGFloat((low - minimum) / span))
                }
                .frame(height: 9)
            }
            .frame(height: 9)

            Text("\(Int(low))–\(Int(high))")
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

// MARK: - Timeline

/// Events and the gaps between them — dots spaced by when things actually
/// happened, so a drought looks like a drought.
struct InsightTimelineChart: View {
    /// Event timestamps as `timeIntervalSince1970`, oldest first.
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let first = values.min() ?? 0
            let last = values.max() ?? 1
            let span = max(last - first, 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.bgSubtle)
                    .frame(height: 2)

                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .offset(x: (geo.size.width - 8) * CGFloat((value - first) / span))
                }
            }
            .frame(height: 8)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 22)
    }
}
