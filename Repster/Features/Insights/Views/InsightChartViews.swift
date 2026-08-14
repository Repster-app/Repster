// InsightChartViews.swift
// One component per InsightChartKind.
//
// v1 drew every finding as the same capsule bar chart, which made a two-group
// comparison, a proportion and a signed time series look identical — and threw
// away the sign on the one where the sign was the whole point.

import SwiftUI

/// Shared body height for the shape-based kinds. They were 22–52pt with no
/// rationale, which made the feed read as a set of unrelated widgets rather
/// than one system. Row-based kinds still size to their content.
enum InsightChartMetrics {
    static let body: CGFloat = 46
    static let caption: CGFloat = 10
    static let figure: CGFloat = 12
}

/// Picks the component that matches the finding's data shape.
struct InsightChartView: View {
    let insight: InsightItem
    let color: Color
    let unitPreference: UnitPreference

    var body: some View {
        switch insight.chartKind {
        case .series:
            if InsightChartKind.signedSeriesRules.contains(insight.ruleId) {
                InsightSignedSeriesChart(values: insight.chartValues, labels: insight.chartLabels)
            } else {
                InsightSeriesChart(
                    values: insight.chartValues,
                    color: color,
                    unitPreference: unitPreference
                )
            }
        case .column:
            InsightColumnChart(values: insight.chartValues, color: color)
        case .ranking:
            InsightRankingChart(
                labels: insight.chartLabels,
                values: insight.chartValues,
                subject: insight.subjectName,
                color: color
            )
        case .proportion:
            InsightProportionChart(labels: insight.chartLabels, values: insight.chartValues)
        case .comparison:
            InsightComparisonChart(labels: insight.chartLabels, values: insight.chartValues, color: color)
        case .range:
            InsightRangeChart(labels: insight.chartLabels, values: insight.chartValues, color: color)
        case .timeline:
            InsightTimelineChart(
                values: insight.chartValues,
                color: color,
                typicalGapDays: insight.typicalGapDays
            )
        }
    }
}

// MARK: - Series

/// A trend line with its endpoints printed.
///
/// The y-axis stays unlabelled, but the two endpoints are not decoration — they
/// are the axis. Without them the line is equally consistent with a 2 kg drift
/// and a 13 kg climb, and the headline's claim can't be checked against the
/// picture. The previous version deferred the numbers to the card's text, which
/// `InsightCardView` clamps to two lines while collapsed — so on the state most
/// of these are read in, neither the chart nor the prose carried a figure.
struct InsightSeriesChart: View {
    let values: [Double]
    let color: Color
    let unitPreference: UnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            .frame(height: InsightChartMetrics.body)

            endpoints
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var endpoints: some View {
        if let first = values.first, let last = values.last, values.count >= 2 {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(weight(first))
                    .font(.system(size: InsightChartMetrics.figure, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)

                Spacer(minLength: 6)

                if let change = signedChange(from: first, to: last) {
                    Text(change)
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textTertiary)
                }

                Text(weight(last))
                    .font(.system(size: InsightChartMetrics.figure, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    private func weight(_ kg: Double) -> String {
        UnitConversion.formatWeightLabel(kg, unitPreference: unitPreference)
    }

    /// Nil when the two ends round to the same displayed weight — a "+0 kg"
    /// caption on a flat lift says less than nothing.
    private func signedChange(from first: Double, to last: Double) -> String? {
        let delta = last - first
        let converted = unitPreference == .imperial ? UnitConversion.kgToLbs(abs(delta)) : abs(delta)
        guard converted.rounded() != 0 else { return nil }
        return (delta > 0 ? "+" : "−") + weight(abs(delta))
    }

    private var accessibilityLabel: String {
        guard let first = values.first, let last = values.last, values.count >= 2 else {
            return "Trend chart"
        }
        return "From \(weight(first)) to \(weight(last)) across \(values.count) sessions"
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
///
/// Two things were wrong here. Green above and red below graded training the
/// user chose, the same verdict colouring dropped from the status card; and for
/// `rirCalibration` the grading was actively backwards, since "more left in the
/// tank than you logged" is not bad news. Direction is already carried by which
/// side of the line a bar sits on, so hue was doing nothing but judging.
///
/// The count was also computed here, spoken to VoiceOver, and shown to nobody.
/// Both rules already pass real `chartLabels` — exercise names from
/// `deloadReadiness`, per-observation labels from `rirCalibration` — which this
/// view previously discarded.
struct InsightSignedSeriesChart: View {
    let values: [Double]
    let labels: [String]

    private var belowCount: Int { values.filter { $0 < 0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(belowCount) of \(values.count)")
                    .font(.system(size: InsightChartMetrics.figure, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text("below expected")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Spacer(minLength: 0)
            }

            chart

            if let first = labels.first(where: { !$0.isEmpty }),
               let last = labels.last(where: { !$0.isEmpty }), first != last {
                HStack {
                    Text(first)
                    Spacer(minLength: 8)
                    Text(last)
                }
                .font(.system(size: InsightChartMetrics.caption, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(belowCount) of \(values.count) below expectation")
    }

    private var chart: some View {
        GeometryReader { geo in
            let scale = max(values.map(abs).max() ?? 1, 0.001)
            let midpoint = geo.size.height / 2

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)
                    .offset(y: midpoint)

                // Names what zero means, so a bar below the line reads as
                // "under what was predicted" rather than as a bad mark.
                Text("expected")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .offset(y: midpoint + 1)

                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        let height = max(3, midpoint * CGFloat(abs(value) / scale))
                        VStack(spacing: 0) {
                            if value >= 0 {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accent)
                                    .frame(height: height)
                                Spacer(minLength: 0).frame(height: midpoint)
                            } else {
                                Spacer(minLength: 0).frame(height: midpoint)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.stale)
                                    .frame(height: height)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: InsightChartMetrics.body)
    }
}

// MARK: - Column

/// One bar per week, latest emphasised, with the latest figure printed.
///
/// Both rules that use this kind — `consistency` and `volumeRamp` — rendered
/// identically for entirely different data, with nothing saying what was being
/// counted. The period labels and the current figure are what fix that.
///
/// Deliberately draws **no** reference line. An earlier version derived a median
/// from the displayed weeks and labelled it "typical", which put a third
/// definition of the user's norm on screen beside the status card's baseline
/// and the rule's own two-window comparison — three numbers, all reading as
/// "your usual", two of them adjacent on the same card. The status card owns
/// that phrase; this chart shows the shape and the latest value only.
struct InsightColumnChart: View {
    let values: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bars

            HStack(spacing: 6) {
                Text(values.count == 1 ? "1 week" : "\(values.count) weeks ago")
                Spacer(minLength: 8)
                if let latest = values.last {
                    Text(Self.format(latest))
                        .font(.system(size: InsightChartMetrics.figure, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                    Text("this week")
                }
            }
            .font(.system(size: InsightChartMetrics.caption, weight: .medium))
            .foregroundStyle(Color.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var bars: some View {
        let scale = max(values.max() ?? 1, 0.001)

        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == values.count - 1 ? color : color.opacity(0.35))
                    .frame(height: max(3, InsightChartMetrics.body * CGFloat(value / scale)))
            }
        }
        .frame(height: InsightChartMetrics.body, alignment: .bottom)
    }

    /// Weekly counts are whole; weekly set totals may not be after averaging.
    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private var accessibilityLabel: String {
        guard let latest = values.last else { return "Weekly chart" }
        return "\(Self.format(latest)) this week, over \(values.count) weeks"
    }
}

// MARK: - Ranking

/// Named muscle groups ranked by recent sets, in the same row grammar as the
/// status screen's muscle panel.
///
/// The previous version drew bare columns with no names and no figures: four
/// coloured blocks that the reader had to match to muscle groups from memory,
/// with the neglected group — the entire subject of the finding — reduced to an
/// unlabelled sliver indistinguishable from a rendering artefact. Naming the
/// rows and printing the counts is what makes it a chart rather than decoration.
struct InsightRankingChart: View {
    let labels: [String]
    let values: [Double]
    /// The group the finding is about, emphasised so the chart points at the
    /// thing the headline is talking about.
    let subject: String?
    let color: Color

    /// Enough to establish "the rest of your groups" without turning a feed card
    /// into a full panel. The subject is always kept on top of this.
    private static let maximumRows = 5

    private struct Row: Identifiable {
        let label: String
        let value: Double
        let isSubject: Bool
        var id: String { label }
    }

    private var rows: [Row] {
        let paired = zip(labels, values).map { label, value in
            Row(
                label: label,
                value: value,
                isSubject: subject?.caseInsensitiveCompare(label) == .orderedSame
            )
        }
        guard paired.count > Self.maximumRows else { return paired }

        // The subject ranks last by definition, so a plain prefix would drop the
        // one row that matters. Keep the leaders, then the subject.
        var trimmed = Array(paired.prefix(Self.maximumRows))
        if !trimmed.contains(where: \.isSubject), let subjectRow = paired.first(where: \.isSubject) {
            trimmed.removeLast()
            trimmed.append(subjectRow)
        }
        return trimmed
    }

    var body: some View {
        let scale = max(values.max() ?? 1, 0.001)

        VStack(spacing: 7) {
            ForEach(rows) { row in
                HStack(spacing: 9) {
                    Text(ExercisePrimaryGroup.displayName(for: row.label))
                        .font(.system(size: 11.5, weight: row.isSubject ? .semibold : .medium))
                        .foregroundStyle(row.isSubject ? Color.textPrimary : Color.textSecondary)
                        .lineLimit(1)
                        .frame(width: 62, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.bgSubtle)
                                .frame(height: 8)

                            // A group with nothing still gets a nub, so zero reads
                            // as "almost none" rather than as a missing bar.
                            Capsule()
                                .fill(tint(for: row))
                                .frame(
                                    width: max(3, geo.size.width * CGFloat(row.value / scale)),
                                    height: 8
                                )
                        }
                        .frame(height: 8)
                    }
                    .frame(height: 8)

                    Text("\(Int(row.value))")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.isSubject ? Color.textPrimary : Color.textTertiary)
                        .frame(width: 24, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: row))
            }
        }
    }

    private func tint(for row: Row) -> Color {
        guard !row.label.isEmpty else { return color }
        // The subject's own colour at full strength; the groups it's being
        // measured against step back so the comparison has a foreground.
        let base = MuscleGroupColors.color(for: row.label)
        return row.isSubject ? base : base.opacity(0.55)
    }

    private func accessibilityLabel(for row: Row) -> String {
        let name = ExercisePrimaryGroup.displayName(for: row.label)
        let count = Int(row.value)
        let sets = count == 1 ? "1 set" : "\(count) sets"
        return row.isSubject ? "\(name), \(sets), the group this finding is about" : "\(name), \(sets)"
    }
}

/// The four kinds reworked on 11 Aug, at the ratios that broke the old ones.
#Preview("Reworked kinds") {
    func daysAgo(_ days: Double) -> Double {
        Date().addingTimeInterval(-days * 86_400).timeIntervalSince1970
    }

    return ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            Group {
                Text("SERIES — strengthTrend").font(.system(size: 10, weight: .bold))
                InsightSeriesChart(
                    values: [102, 104, 103, 107, 106, 110, 112, 115],
                    color: .success,
                    unitPreference: .metric
                )

                Text("SIGNED — deloadReadiness").font(.system(size: 10, weight: .bold))
                InsightSignedSeriesChart(
                    values: [1.5, -3.2, -4.8, -2.6, -6.1, -5.4],
                    labels: ["Bench Press", "Squat", "Row", "Press", "Deadlift", "Curl"]
                )

                Text("COLUMN — consistency").font(.system(size: 10, weight: .bold))
                InsightColumnChart(values: [3, 3, 4, 3, 4, 4, 4, 5], color: .accent)

                Text("COLUMN — volumeRamp").font(.system(size: 10, weight: .bold))
                InsightColumnChart(values: [42, 45, 48, 52, 61, 68, 74], color: .chart5)
            }

            Group {
                Text("TIMELINE — droppedExercise (94-day gap)").font(.system(size: 10, weight: .bold))
                InsightTimelineChart(
                    values: [180, 166, 150, 137, 122, 108, 94].map { daysAgo($0) },
                    color: .orange
                )

                Text("TIMELINE — prPace (tightening)").font(.system(size: 10, weight: .bold))
                InsightTimelineChart(
                    values: [64, 48, 33, 21, 12, 7, 4].map { daysAgo($0) },
                    color: .gold
                )
            }
            .foregroundStyle(Color.textTertiary)
        }
        .foregroundStyle(Color.textTertiary)
        .padding(16)
    }
    .background(Color.bg)
}

#Preview("Ranking chart") {
    VStack(alignment: .leading, spacing: 24) {
        // The reported case: a group on zero against groups that kept training.
        InsightRankingChart(
            labels: ["chest", "back", "abs", "legs"],
            values: [12, 10, 7, 0],
            subject: "legs",
            color: .chart7
        )

        // More groups than fit: the subject ranks last and must survive trimming.
        InsightRankingChart(
            labels: ["chest", "back", "quads", "shoulders", "biceps", "calves"],
            values: [16, 14, 12, 9, 8, 1],
            subject: "calves",
            color: .chart7
        )
    }
    .padding(14)
    .background(Color.bgCard)
    .cornerRadius(14)
    .padding(20)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.bg)
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

/// Events, and the gap between the last one and now.
///
/// The axis is anchored to **today**, not to the final event. Ending it at the
/// last dot meant the interval the finding is actually about — 94 days without
/// the lift — was the one interval never drawn, so a card headlined "you've
/// stopped doing this" showed evenly spaced dots that read as regular training.
///
/// Serves both rules on this kind. `droppedExercise` is about the trailing gap;
/// `prPace` is about the gap having changed, and the median interval it's
/// compared against is derived from the timestamps rather than passed in.
struct InsightTimelineChart: View {
    /// Event timestamps as `timeIntervalSince1970`, oldest first.
    let values: [Double]
    let color: Color
    /// The producing rule's own cadence figure, when it has one. Preferred over
    /// the derived estimate below so the chart and the card's text can't quote
    /// different numbers for the same series.
    var typicalGapDays: Double?
    var referenceDate: Date = Date()

    private var sorted: [Double] { values.sorted() }

    private var trailingGapDays: Int {
        guard let last = sorted.last else { return 0 }
        return max(0, Int(((referenceDate.timeIntervalSince1970 - last) / 86_400).rounded()))
    }

    /// Typical spacing between events, so the trailing gap has something to be
    /// unusual against.
    ///
    /// Falls back to a median over the plotted events only when the rule didn't
    /// supply one — that estimate is over whatever trailing window the chart was
    /// handed, which is why a rule that quotes a cadence should pass its own.
    /// Even counts take the upper of the two middle gaps rather than their
    /// average, matching how the rules pick their median.
    private var medianGapDays: Int? {
        if let typicalGapDays {
            return max(1, Int(typicalGapDays.rounded()))
        }
        guard sorted.count >= 3 else { return nil }
        let gaps = zip(sorted.dropFirst(), sorted).map { ($0 - $1) / 86_400 }.sorted()
        guard !gaps.isEmpty else { return nil }
        return max(1, Int(gaps[gaps.count / 2].rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(trailingGapDays)")
                    .font(.system(size: InsightChartMetrics.figure, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(trailingGapDays == 1 ? "day since" : "days since")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Spacer(minLength: 6)
                if let medianGapDays {
                    Text("usually every \(medianGapDays)")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.textTertiary)
                }
            }

            ribbon

            HStack {
                if let first = sorted.first {
                    Text(Self.shortDate(first))
                }
                Spacer(minLength: 8)
                Text("today")
                    .foregroundStyle(Color.textSecondary)
            }
            .font(.system(size: InsightChartMetrics.caption, weight: .medium))
            .foregroundStyle(Color.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var ribbon: some View {
        GeometryReader { geo in
            let start = sorted.first ?? 0
            let now = referenceDate.timeIntervalSince1970
            let span = max(now - start, 1)
            let dotSize: CGFloat = 7
            let usable = max(geo.size.width - dotSize, 1)
            let lastX = usable * CGFloat(((sorted.last ?? start) - start) / span)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.bgSubtle)
                    .frame(height: 6)

                // The stretch that was trained, solid; the gap after it dashed
                // and running all the way to today.
                Capsule()
                    .fill(color.opacity(0.45))
                    .frame(width: max(dotSize, lastX + dotSize), height: 6)

                Path { path in
                    path.move(to: CGPoint(x: lastX + dotSize + 3, y: 11))
                    path.addLine(to: CGPoint(x: geo.size.width - 2, y: 11))
                }
                .stroke(
                    Color.textTertiary,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )

                ForEach(Array(sorted.enumerated()), id: \.offset) { _, value in
                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: usable * CGFloat((value - start) / span))
                }

                // Today: the edge the whole chart is measured to.
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.textPrimary)
                    .frame(width: 2, height: 16)
                    .offset(x: geo.size.width - 2)
            }
            .frame(height: 22)
        }
        .frame(height: 22)
    }

    static func shortDate(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private var accessibilityLabel: String {
        let base = "\(values.count) sessions, \(trailingGapDays) days since the last"
        guard let medianGapDays else { return base }
        return base + ", usually every \(medianGapDays) days"
    }
}
