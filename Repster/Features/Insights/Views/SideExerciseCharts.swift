// SideExerciseCharts.swift
// The three visual blocks of the Sides exercise deep dive: the balance beam (how far apart the
// sides are on average), the session ladder (how far each side actually got, session by session),
// and the best set at each weight with the reserve that decided it.
//
// Replaces the C2 difference columns of D18. Those drew `SideDegree` — three quantised steps — so
// the chart could not express the rep the headline names, and it reserved half its height for a
// side that by definition never leads once an exercise has a verdict.
// Scoping: SIDES_DETAIL_REDESIGN_SCOPING.md.
//
// Every track is a `Canvas`: the fills are fractions of a width that varies by device, and a
// Canvas is handed its size without a GeometryReader or a layout pass of its own.

import SwiftUI

// MARK: - Balance beam

/// The average gap on one reps scale, with the tie threshold drawn rather than explained: the
/// shaded middle IS `SidesAnalysis.tieBelow`, so "why doesn't that count?" answers itself.
struct SideBalanceBeam: View {
    let averageGap: Double
    let status: SideStatus

    private let gutter: CGFloat = 46
    private let columnGap: CGFloat = 8
    private let chipHeight: CGFloat = 18
    private let trackHeight: CGFloat = 14

    /// Reps either side of centre. Adaptive with a floor of three, so a five-rep gap widens the
    /// beam instead of pinning at the end — which would read as "as bad as it gets" on every
    /// exercise past three.
    private var scale: Double { max(3, abs(averageGap).rounded(.up)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: columnGap) {
                Text("Average")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.sidesCaption)
                    .frame(width: gutter, alignment: .leading)

                Canvas { context, size in draw(&context, size) }
                    .frame(height: chipHeight + trackHeight)
            }

            HStack(spacing: columnGap) {
                Color.clear.frame(width: gutter, height: 0)
                ZStack {
                    HStack(spacing: 0) {
                        edgeLabel("Left")
                        Spacer(minLength: 0)
                        edgeLabel("Right")
                    }
                    edgeLabel("Even")
                }
                .frame(height: 13)
            }

            Text("The shaded middle is where a difference is too small to count.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.sidesCaption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func edgeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.sidesCaption)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let top = chipHeight
        let centre = size.width / 2
        let perRep = centre / scale
        let radius = trackHeight / 2

        context.fill(
            Path(roundedRect: CGRect(x: 0, y: top, width: size.width, height: trackHeight), cornerRadius: radius),
            with: .color(.bgInput)
        )

        let tie = SidesAnalysis.tieBelow * perRep
        context.fill(
            Path(CGRect(x: centre - tie, y: top, width: tie * 2, height: trackHeight)),
            with: .color(.bgSubtle)
        )

        drawVerdict(&context, size: size, top: top, centre: centre, perRep: perRep, radius: radius)

        context.fill(
            Path(CGRect(x: centre - 0.5, y: top - 5, width: 1, height: trackHeight + 10)),
            with: .color(.sidesTrail)
        )

        drawChip(&context, size: size, centre: centre, perRep: perRep)
    }

    private func drawVerdict(
        _ context: inout GraphicsContext,
        size: CGSize,
        top: CGFloat,
        centre: CGFloat,
        perRep: CGFloat,
        radius: CGFloat
    ) {
        let reach = CGFloat(abs(averageGap)) * perRep
        let leadsRight = averageGap > 0
        let fill = CGRect(
            x: leadsRight ? centre : centre - reach,
            y: top,
            width: max(reach, 1),
            height: trackHeight
        )
        let rounded = Path(roundedRect: fill, cornerRadius: min(radius, fill.width / 2))

        switch status {
        case .stronger:
            context.fill(rounded, with: .color(.sidesStronger))
        case .possible:
            // D24: a lean on too few differing sessions gets no solid mark anywhere in the feature.
            context.fill(rounded, with: .color(.sidesStronger.opacity(0.12)))
            context.stroke(rounded, with: .color(.sidesStronger), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .even:
            context.fill(
                Path(ellipseIn: CGRect(x: centre - 5, y: top + radius - 5, width: 10, height: 10)),
                with: .color(.sidesEven)
            )
        case .collecting, .notTracked:
            break
        }
    }

    private func drawChip(_ context: inout GraphicsContext, size: CGSize, centre: CGFloat, perRep: CGFloat) {
        guard let label = chipLabel else { return }
        let text = Text(label)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(chipColour)
        let resolved = context.resolve(text)
        let measured = resolved.measure(in: CGSize(width: size.width, height: chipHeight))
        let half = measured.width / 2
        let wanted = centre + CGFloat(averageGap) * perRep
        let x = min(max(wanted, half), size.width - half)
        context.draw(resolved, at: CGPoint(x: x, y: chipHeight / 2), anchor: .center)
    }

    private var chipLabel: String? {
        switch status {
        case .stronger:
            let size = abs(averageGap)
            let unit = size == 1 ? "rep" : "reps"
            return String(format: "+%.1f %@", size, unit)
        case .possible:
            return "not confirmed"
        case .even:
            return "Even"
        case .collecting, .notTracked:
            return nil
        }
    }

    private var chipColour: Color {
        switch status {
        case .stronger: return .sidesStronger
        case .possible, .even: return .sidesCaption
        case .collecting, .notTracked: return .sidesCaption
        }
    }

    private var accessibilitySummary: String {
        let size = abs(averageGap)
        let unit = size == 1 ? "rep" : "reps"
        let amount = String(format: "%.1f %@", size, unit)
        switch status {
        case let .stronger(lean, _):
            return "On average your \(lean.rawValue) side is ahead by \(amount). Differences under half a rep count as even."
        case let .possible(lean):
            return "Your \(lean.rawValue) side is ahead by \(amount) so far, not confirmed. Differences under half a rep count as even."
        case .even:
            return "Your sides are even: the average difference is under half a rep."
        case .collecting, .notTracked:
            return "Not enough sessions yet to measure a difference."
        }
    }
}

// MARK: - Session ladder

/// One row per session: both sides on a shared capacity scale, with the leading side's length
/// *beyond* the trailing side picked out. The dotted rule at the trailing length makes the reading
/// literal — same up to here, then extra.
struct SideSessionLadder: View {
    let sessions: [SideSession]

    private let dateColumn: CGFloat = 52
    private let letterColumn: CGFloat = 12
    private let gapColumn: CGFloat = 40
    private let rowHeight: CGFloat = 24
    private let barHeight: CGFloat = 9

    /// One scale for every row, so a session where both sides did more stands taller than one
    /// where both did less. The headroom matters at one session: without it the leading bar fills
    /// the track and a first session reads as maxed out rather than as a starting point.
    private var ceiling: Double {
        max(1, (sessions.flatMap { [$0.left, $0.right] }.max() ?? 1) * 1.15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 15) {
                ForEach(sessions) { session in
                    row(session)
                }
            }

            Text("Each row is one session: how far each side got, and in blue how much further the leading side went.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.sidesCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ session: SideSession) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sidesCaption)
                .frame(width: dateColumn, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                sideLetter("L")
                Spacer(minLength: 0)
                sideLetter("R")
            }
            .frame(width: letterColumn, height: rowHeight)

            Canvas { context, size in draw(&context, size, session: session) }
                .frame(height: rowHeight)

            Text(gapLabel(session))
                .font(.system(size: 12.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(session.lean == nil ? Color.sidesCaption : Color.sidesStronger)
                .frame(width: gapColumn, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(session))
    }

    private func sideLetter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.sidesNeutralMark)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, session: SideSession) {
        let leftWidth = size.width * CGFloat(session.left / ceiling)
        let rightWidth = size.width * CGFloat(session.right / ceiling)
        let trailing = min(leftWidth, rightWidth)
        let radius = barHeight / 2

        bar(&context, y: 1, width: leftWidth, leads: leftWidth > rightWidth, trailing: trailing, radius: radius)
        bar(&context, y: rowHeight - barHeight - 1, width: rightWidth, leads: rightWidth > leftWidth, trailing: trailing, radius: radius)

        guard session.lean != nil else { return }
        context.fill(
            Path(CGRect(x: trailing - 0.5, y: 0, width: 1, height: rowHeight)),
            with: .color(.white.opacity(0.18))
        )
    }

    private func bar(
        _ context: inout GraphicsContext,
        y: CGFloat,
        width: CGFloat,
        leads: Bool,
        trailing: CGFloat,
        radius: CGFloat
    ) {
        let rect = CGRect(x: 0, y: y, width: max(width, barHeight), height: barHeight)
        let shape = Path(roundedRect: rect, cornerRadius: radius)
        guard leads else {
            context.fill(shape, with: .color(.sidesTrail))
            return
        }
        // Two flat fills inside the rounded bar: the shared length, then the excess.
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.fill(Path(CGRect(x: 0, y: y, width: trailing, height: barHeight)), with: .color(.sidesTrail))
            layer.fill(
                Path(CGRect(x: trailing, y: y, width: rect.width - trailing, height: barHeight)),
                with: .color(.sidesStronger)
            )
        }
    }

    private func gapLabel(_ session: SideSession) -> String {
        guard session.lean != nil else { return "even" }
        return String(format: "+%.1f", abs(session.gap))
    }

    private func accessibilityLabel(_ session: SideSession) -> String {
        let date = session.date.formatted(.dateTime.month(.wide).day())
        guard let lean = session.lean else { return "\(date): both sides even." }
        let size = abs(session.gap)
        let unit = size == 1 ? "rep" : "reps"
        return String(format: "%@: %@ ahead by %.1f %@.", date, lean.rawValue, size, unit)
    }
}

// MARK: - Best set

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


// MARK: - Group row beam

/// The balance beam shrunk to a list row. The scale comes from the caller so every exercise in a
/// muscle group is drawn against the same ruler — the one thing the group screen can show that the
/// exercise screen cannot.
struct SideMiniBeam: View {
    let averageGap: Double
    let status: SideStatus
    /// Reps either side of centre, shared across the group.
    let scale: Double

    static let width: CGFloat = 120
    private let height: CGFloat = 10

    var body: some View {
        Canvas { context, size in draw(&context, size) }
            .frame(width: Self.width, height: height)
            .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let centre = size.width / 2
        let perRep = centre / max(scale, 1)
        let radius = size.height / 2

        context.fill(
            Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius),
            with: .color(.bgInput)
        )
        let tie = SidesAnalysis.tieBelow * perRep
        context.fill(
            Path(CGRect(x: centre - tie, y: 0, width: tie * 2, height: size.height)),
            with: .color(.bgSubtle)
        )

        let reach = CGFloat(abs(averageGap)) * perRep
        let fill = CGRect(
            x: averageGap > 0 ? centre : centre - reach,
            y: 0,
            width: max(reach, 1),
            height: size.height
        )
        let rounded = Path(roundedRect: fill, cornerRadius: min(radius, fill.width / 2))

        switch status {
        case .stronger:
            context.fill(rounded, with: .color(.sidesStronger))
        case .possible:
            context.fill(rounded, with: .color(.sidesStronger.opacity(0.12)))
            context.stroke(rounded, with: .color(.sidesStronger), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .even, .collecting, .notTracked:
            break
        }

        context.fill(
            Path(CGRect(x: centre - 0.5, y: -2, width: 1, height: size.height + 4)),
            with: .color(status.isClassified ? .sidesTrail : .bodyOutline)
        )
    }
}
