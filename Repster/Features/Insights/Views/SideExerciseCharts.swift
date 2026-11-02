// SideExerciseCharts.swift
// The blocks of the Sides exercise page: one chart of both sides over the sessions, and the best
// set from the most recent of them. Scoping: SIDES_RETHINK_SCOPING.md, D27, D30, D31.
//
// The chart plots session medians, because that is what the verdict runs on, and prints none of
// them. Nobody lifted 8.5, and a figure like that beside the real sets in the table reads as a
// contradiction, so every number on the page is a set the lifter logged.
//
// The chart is a `Canvas`: the points are fractions of a width that varies by device, and a Canvas
// is handed its size without a GeometryReader or a layout pass of its own.
//
// `SideEffortTable` has no call site for now (D28). `SideSession.bestSet` reuses its row type.

import SwiftUI

// MARK: - Scale

/// The chart's reps axis, apart from the drawing so it can be pinned without rendering.
struct SideChartScale: Equatable {
    /// Reps from top to bottom, at least. Without a floor a half-rep gap fills the chart and
    /// looks as large as a five-rep one.
    static let minimumSpan = 3.5
    /// End labels closer together than this overlap.
    static let minimumLabelGap: CGFloat = 15

    let domain: ClosedRange<Double>
    /// Two whole numbers for the gridlines.
    let ticks: [Double]

    init(sessions: [SideSession]) {
        let values = sessions.flatMap { [$0.left, $0.right] }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let span = max(Self.minimumSpan, (high - low) * 1.2)
        let lower = max(0, (low + high - span) / 2)
        domain = lower...(lower + span)

        let lowTick = low.rounded(.up)
        let highTick = high.rounded(.down)
        if highTick > lowTick {
            ticks = [lowTick, highTick]
        } else {
            let tick = ((low + high) / 2).rounded(.down)
            ticks = [tick, tick + 1]
        }
    }

    /// `plot` runs top to bottom, so a higher value lands nearer its top.
    func y(_ value: Double, in plot: CGRect) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        return plot.minY + plot.height * CGFloat((domain.upperBound - value) / span)
    }

    /// How far to nudge the end labels when the last two points nearly touch. The higher point's
    /// label goes up; on an exact tie `leftOnTop` decides.
    static func labelOffsets(leftY: CGFloat, rightY: CGFloat, leftOnTop: Bool) -> (left: CGFloat, right: CGFloat) {
        let distance = abs(leftY - rightY)
        guard distance < minimumLabelGap else { return (0, 0) }
        let push = (minimumLabelGap - distance) / 2
        let leftIsHigher = leftY == rightY ? leftOnTop : leftY < rightY
        return leftIsHigher ? (-push, push) : (push, -push)
    }
}

// MARK: - Lines

/// Left and right over the sessions, with the gap between them shaded. Right is always a filled
/// point and left a hollow one, so the sides differ by more than colour. The leading side is
/// bright and the other dim; an unconfirmed leader is dashed (D24), and with no leader both sides
/// share the even blue and nothing is shaded.
struct SideLinesChart: View {
    let sessions: [SideSession]
    let status: SideStatus
    let coverage: SideRIRCoverage

    private let height: CGFloat = 164
    /// Where the first point sits, clear of the gridline labels.
    private let firstX: CGFloat = 30
    /// Room after the last point for the end labels.
    private let endRoom: CGFloat = 32
    private let plotTop: CGFloat = 10
    /// Room under the plot for the dates.
    private let plotBottom: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                legendItem(.left)
                legendItem(.right)
                Spacer(minLength: 8)
                SideRIRMarker(coverage: coverage)
            }

            Canvas { context, size in draw(&context, size) }
                .frame(height: height)
                .accessibilityLabel("Left and right over your last \(sessions.count) sessions")
                .accessibilityChildren {
                    VStack {
                        ForEach(sessions) { session in
                            Text(spokenLabel(session))
                        }
                    }
                }
        }
    }

    // MARK: Style

    private var leader: SideLean? { status.lean }

    /// The leader goes last, so it sits on top where the lines meet.
    private var drawOrder: [SideLean] {
        leader == .left ? [.right, .left] : [.left, .right]
    }

    private var bandOpacity: Double? {
        switch status {
        case .stronger: return 0.14
        case .possible: return 0.08
        case .even, .collecting, .notTracked: return nil
        }
    }

    private func colour(_ side: SideLean) -> Color {
        guard let leader else { return .sidesEvenBright }
        return side == leader ? .sidesStronger : .sidesNeutralMark
    }

    private func stroke(_ side: SideLean) -> StrokeStyle {
        let isUnconfirmed = status.isPossible && side == leader
        return StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: isUnconfirmed ? [5, 5] : [])
    }

    private func labelColour(_ side: SideLean) -> Color {
        side == leader ? .textPrimary : .textSecondary
    }

    private func legendItem(_ side: SideLean) -> some View {
        HStack(spacing: 6) {
            Group {
                if side == .right {
                    Circle().fill(colour(side))
                } else {
                    Circle().strokeBorder(colour(side), lineWidth: 2)
                }
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)

            Text(side.word)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(labelColour(side))
        }
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        guard let last = sessions.indices.last else { return }
        let scale = SideChartScale(sessions: sessions)
        let plot = CGRect(x: 0, y: plotTop, width: size.width, height: size.height - plotTop - plotBottom)
        let step = last > 0 ? (size.width - firstX - endRoom) / CGFloat(last) : 0

        func point(_ index: Int, _ value: Double) -> CGPoint {
            CGPoint(x: firstX + step * CGFloat(index), y: scale.y(value, in: plot))
        }
        let leftPoints = sessions.enumerated().map { point($0.offset, $0.element.left) }
        let rightPoints = sessions.enumerated().map { point($0.offset, $0.element.right) }
        func points(_ side: SideLean) -> [CGPoint] { side == .left ? leftPoints : rightPoints }

        drawGrid(&context, size, scale: scale, plot: plot)

        if let bandOpacity {
            var band = Path()
            band.addLines(rightPoints + leftPoints.reversed())
            band.closeSubpath()
            context.fill(band, with: .color(.sidesStronger.opacity(bandOpacity)))
        }

        for side in drawOrder {
            var line = Path()
            line.addLines(points(side))
            context.stroke(line, with: .color(colour(side)), style: stroke(side))
        }
        for side in drawOrder {
            for point in points(side) {
                drawPoint(&context, at: point, side: side)
            }
        }

        drawEndLabels(&context, left: leftPoints[last], right: rightPoints[last])
        drawDates(&context, size, x: leftPoints.map(\.x))
    }

    private func drawGrid(_ context: inout GraphicsContext, _ size: CGSize, scale: SideChartScale, plot: CGRect) {
        for tick in scale.ticks {
            let y = scale.y(tick, in: plot)
            context.fill(
                Path(CGRect(x: 20, y: y - 0.5, width: size.width - 20 - endRoom + 6, height: 1)),
                with: .color(.border)
            )
            let label = Text(String(Int(tick)))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sidesCaption)
            context.draw(context.resolve(label), at: CGPoint(x: 14, y: y), anchor: .trailing)
        }
    }

    private func drawPoint(_ context: inout GraphicsContext, at point: CGPoint, side: SideLean) {
        func circle(_ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        switch side {
        case .right:
            context.fill(circle(6), with: .color(.bgCard))
            context.fill(circle(4), with: .color(colour(side)))
        case .left:
            context.fill(circle(5), with: .color(.bgCard))
            context.stroke(circle(4), with: .color(colour(side)), lineWidth: 2)
        }
    }

    private func drawEndLabels(_ context: inout GraphicsContext, left: CGPoint, right: CGPoint) {
        let offsets = SideChartScale.labelOffsets(leftY: left.y, rightY: right.y, leftOnTop: leader != .right)
        let x = left.x + 14

        for (side, y) in [(SideLean.left, left.y + offsets.left), (.right, right.y + offsets.right)] {
            let label = Text(side == .left ? "L" : "R")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(labelColour(side))
            context.draw(context.resolve(label), at: CGPoint(x: x, y: y), anchor: .leading)
        }
    }

    private func drawDates(_ context: inout GraphicsContext, _ size: CGSize, x: [CGFloat]) {
        for (session, x) in zip(sessions, x) {
            let label = Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sidesCaption)
            context.draw(context.resolve(label), at: CGPoint(x: x, y: size.height - 9), anchor: .center)
        }
    }

    private func spokenLabel(_ session: SideSession) -> String {
        let date = session.date.formatted(.dateTime.month(.wide).day())
        guard let lean = session.lean else { return "\(date): both sides even." }
        return "\(date): \(lean.rawValue) ahead."
    }
}

// MARK: - RIR

/// Says whether the numbers include RIR. The same blue marks it on each row of the table (D31).
struct SideRIRMarker: View {
    let coverage: SideRIRCoverage

    var body: some View {
        SideRIRPill(text: SidesCopy.rirMarker(for: coverage), isCounted: coverage != .repsOnly)
    }
}

struct SideRIRPill: View {
    let text: String
    var isCounted = true

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isCounted ? Color.sidesRIR : Color.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isCounted ? Color.sidesStronger.opacity(0.16) : Color.bgSubtle)
            .cornerRadius(6)
    }
}

// MARK: - Best set each session

/// The best set from the latest sessions, as logged: the part of the page a lifter can check
/// against their own history. A side with no pill was compared on reps alone.
struct SideBestSetTable: View {
    let sessions: [SideSession]
    let unitPreference: UnitPreference

    static let rowLimit = 3

    private let sideColumn: CGFloat = 104

    /// Newest first.
    private var rows: [(session: SideSession, set: SideBestRow)] {
        sessions.suffix(Self.rowLimit).reversed().compactMap { session in
            session.bestSet.map { (session, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                columnTitle("LEFT")
                columnTitle("RIGHT")
            }
            .frame(minHeight: 26)
            .accessibilityHidden(true)

            ForEach(rows, id: \.session.id) { row in
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)
                rowView(row.session, set: row.set)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Color.sidesCaption)
            .frame(width: sideColumn, alignment: .trailing)
    }

    private func rowView(_ session: SideSession, set: SideBestRow) -> some View {
        let left = Double(set.left) + (set.leftRIR ?? 0)
        let right = Double(set.right) + (set.rightRIR ?? 0)

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text(weightLabel(set.weight))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.sidesCaption)
            }
            Spacer(minLength: 0)
            sideCell(reps: set.left, reserve: set.leftRIR, leads: left > right)
            sideCell(reps: set.right, reserve: set.rightRIR, leads: right > left)
        }
        .frame(minHeight: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(session, set: set))
    }

    private func sideCell(reps: Int, reserve: Double?, leads: Bool) -> some View {
        HStack(spacing: 6) {
            Text("\(reps)")
                .font(.system(size: 15, weight: leads ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(leads ? Color.textPrimary : Color.textSecondary)
            if let reserve {
                SideRIRPill(text: SidesCopy.reserveText(reserve))
            }
        }
        .frame(width: sideColumn, alignment: .trailing)
    }

    private func weightLabel(_ kg: Double?) -> String {
        guard let kg else { return "Bodyweight" }
        return UnitConversion.formatWeightLabel(kg, unitPreference: unitPreference)
    }

    private func spokenLabel(_ session: SideSession, set: SideBestRow) -> String {
        func side(_ reps: Int, _ reserve: Double?) -> String {
            let count = "\(reps) \(reps == 1 ? "rep" : "reps")"
            return reserve.map { "\(count) with \(SidesCopy.reserveText($0))" } ?? count
        }
        let date = session.date.formatted(.dateTime.month(.wide).day())
        return "\(date), \(weightLabel(set.weight)): left \(side(set.left, set.leftRIR)), right \(side(set.right, set.rightRIR))."
    }
}

// MARK: - Best set at each weight

/// The best single set at each weight, reps and reserve together. Without the reserve this table
/// prints "6 and 6" under a verdict that says one side is stronger, and reads as a contradiction.
struct SideEffortTable: View {
    let rows: [SideBestRow]
    let unitPreference: UnitPreference

    private let weightColumn: CGFloat = 44
    private let letterColumn: CGFloat = 10
    private let barWidth: CGFloat = 132
    private let barHeight: CGFloat = 10

    /// Reps plus reserve, so the pale tail is drawn to the same scale as the solid part.
    private var ceiling: Double {
        let totals = rows.flatMap { row -> [Double] in
            [Double(row.left) + (row.leftRIR ?? 0), Double(row.right) + (row.rightRIR ?? 0)]
        }
        return max(1, totals.max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                SidesSectionLabel(text: "BEST SET AT EACH WEIGHT")
                Spacer(minLength: 0)
                key(colour: .sidesTrail, label: "done")
                key(colour: .sidesReserve, label: "left")
            }

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    sideRow(row, side: .left, showsWeight: true)
                    sideRow(row, side: .right, showsWeight: false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(row))
            }

            if rows.contains(where: { $0.leftRIR != nil }) {
                Text("The pale blue is what you had left in the tank. Same reps on both sides is not a tie if one side had more left.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.sidesCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func key(colour: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4)
                .fill(colour)
                .frame(width: 14, height: 8)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sidesCaption)
        }
    }

    @ViewBuilder
    private func sideRow(_ row: SideBestRow, side: SideLean, showsWeight: Bool) -> some View {
        let reps = side == .left ? row.left : row.right
        let reserve = side == .left ? row.leftRIR : row.rightRIR
        let leads = (Double(reps) + (reserve ?? 0)) >= otherCapacity(row, than: side)

        HStack(alignment: .center, spacing: 8) {
            Group {
                if showsWeight {
                    Text(weightLabel(row.weight))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                } else {
                    Color.clear
                }
            }
            .frame(width: weightColumn, alignment: .leading)

            Text(side == .left ? "L" : "R")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Color.sidesNeutralMark)
                .frame(width: letterColumn, alignment: .leading)

            Canvas { context, size in
                draw(&context, size, reps: reps, reserve: reserve)
            }
            .frame(width: barWidth, height: barHeight)

            Text(effortLabel(reps: reps, reserve: reserve))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(leads ? Color.textPrimary : Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func otherCapacity(_ row: SideBestRow, than side: SideLean) -> Double {
        side == .left
            ? Double(row.right) + (row.rightRIR ?? 0)
            : Double(row.left) + (row.leftRIR ?? 0)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, reps: Int, reserve: Double?) {
        let done = size.width * CGFloat(Double(reps) / ceiling)
        let total = size.width * CGFloat((Double(reps) + (reserve ?? 0)) / ceiling)
        let radius = size.height / 2
        let shape = Path(
            roundedRect: CGRect(x: 0, y: 0, width: max(total, size.height), height: size.height),
            cornerRadius: radius
        )
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.fill(Path(CGRect(x: 0, y: 0, width: done, height: size.height)), with: .color(.sidesTrail))
            if total > done {
                layer.fill(
                    Path(CGRect(x: done, y: 0, width: total - done, height: size.height)),
                    with: .color(.sidesReserve)
                )
            }
        }
    }

    private func weightLabel(_ kg: Double?) -> String {
        guard let kg else { return "Bodyweight" }
        return UnitConversion.formatWeightLabel(kg, unitPreference: unitPreference)
    }

    private func effortLabel(reps: Int, reserve: Double?) -> String {
        let repsText = "\(reps) \(reps == 1 ? "rep" : "reps")"
        guard let reserve else { return repsText }
        if reserve <= 0 { return "\(repsText) · none left" }
        if reserve >= SidesAnalysis.censoredRIR { return "\(repsText) · 5+ left" }
        return "\(repsText) · \(Self.reserveFormat(reserve)) left"
    }

    private static func reserveFormat(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func accessibilityLabel(_ row: SideBestRow) -> String {
        let left = effortLabel(reps: row.left, reserve: row.leftRIR)
        let right = effortLabel(reps: row.right, reserve: row.rightRIR)
        return "\(weightLabel(row.weight)): left \(left); right \(right)."
            .replacingOccurrences(of: " · ", with: ", ")
    }
}
