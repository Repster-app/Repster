// MuscleVolumePanelView.swift
// Trailing-week work per muscle group against each group's own usual week.
//
// Groups come from the user's own exercises, so custom values ("calves",
// "glutes") appear here alongside the catalog ones. Rows rank by baseline
// rather than current volume — sorting by this week buries the group that got
// skipped, which is the one worth seeing.
//
// Bars are ratios to each group's own usual, not raw magnitudes on one shared
// scale. The shared-scale version was least readable exactly when it had most
// to say: one leg-focused week put legs at the full track and left chest, back
// and arms as stubs of a few pixels, and because every row's tick sat at a
// different x there was no way to scan which groups were up and which were
// down. Ratios put one reference line down the panel and make every row
// comparable — a group can now only be read against the thing it should be read
// against, which is what it usually does.
//
// Deltas are deliberately not coloured green/red: that would assert more volume
// is better, which isn't reliably true and contradicts the readiness rule. The
// one exception is a group with a real baseline that got nothing, which is a
// fact rather than a verdict.

import SwiftUI

/// One row's bar, as a fraction of a track whose midpoint is that group's own
/// usual week.
struct MuscleRowGeometry: Equatable {
    /// Where a group that matched its usual week reaches. Putting it at the
    /// midpoint gives equal room to a group that halved and one that doubled,
    /// which is the range ordinary weeks move in.
    static let usualFraction = 0.5

    /// Twice the usual fills the track. Past that the exact multiple stops
    /// being the point — the value column carries the number, and a scale
    /// stretched to fit an 8× row would flatten every ordinary one back into
    /// the stubs this replaced.
    static let cap = 1 / usualFraction

    let fillFraction: Double
    /// Ran past the cap, so the bar is drawn with an overflow mark rather than
    /// reading as exactly twice.
    let isOverCap: Bool
    /// No usual to compare against — the group is new since the baseline
    /// window, so there is a bar but no ratio behind it.
    let isUncompared: Bool

    init(current: Double, usual: Double?) {
        guard let usual, usual > 0 else {
            fillFraction = current > 0 ? 1 : 0
            isOverCap = false
            isUncompared = current > 0
            return
        }
        let ratio = current / usual
        fillFraction = min(ratio, Self.cap) / Self.cap
        isOverCap = ratio > Self.cap
        isUncompared = false
    }
}

struct MuscleVolumePanelView: View {
    let rows: [MuscleVolumeRow]
    @Binding var isExpanded: Bool
    @Binding var metric: MuscleMetric
    let unitPreference: UnitPreference

    /// Enough to cover a typical split without turning Home's destination into
    /// a wall of bars.
    static let collapsedRowCount = 6

    private static let nameColumnWidth: CGFloat = 62
    private static let columnSpacing: CGFloat = 9
    /// Reserved at the end of every track for the overflow mark, so a row at
    /// exactly the cap still stops short of the edge and a row past it has
    /// somewhere to put the chevron.
    private static let overflowGutter: CGFloat = 13
    private static let barHeight: CGFloat = 8

    /// Ranked by the metric on screen — the reason to rank by baseline holds per
    /// metric, and a volume view sorted by set count reads as unsorted.
    private var sortedRows: [MuscleVolumeRow] {
        rows.sorted {
            let left = $0.baseline(for: metric) ?? $0.current(for: metric)
            let right = $1.baseline(for: metric) ?? $1.current(for: metric)
            if left != right { return left > right }
            let leftCurrent = $0.current(for: metric)
            let rightCurrent = $1.current(for: metric)
            if leftCurrent != rightCurrent { return leftCurrent > rightCurrent }
            return $0.displayName < $1.displayName
        }
    }

    private var visibleRows: [MuscleVolumeRow] {
        isExpanded ? sortedRows : Array(sortedRows.prefix(Self.collapsedRowCount))
    }

    private var hiddenCount: Int {
        max(0, rows.count - Self.collapsedRowCount)
    }

    /// Ratios need something to be a ratio of. Before the baseline window fills
    /// there is nothing to compare against, so the panel falls back to plain
    /// magnitudes on a shared scale and drops the reference line with it —
    /// drawing the line with no baseline behind it would be a lie about what
    /// the user has earned.
    private var hasBaselines: Bool {
        rows.contains { ($0.baseline(for: metric) ?? 0) > 0 }
    }

    /// Shared scale for the cold-start fallback only.
    private var absoluteScale: Double {
        var maximum = 1.0
        for row in rows {
            maximum = max(maximum, row.current(for: metric))
        }
        return maximum
    }

    /// Sized from the widest figure actually on screen rather than a constant
    /// per metric. The fixed 46pt version wrapped "284" and "+241" onto two
    /// lines each the first time someone had a heavy leg week in reps, which is
    /// the exact case the panel is for. Digits are monospaced, so counting
    /// characters is deterministic.
    private var valueColumnWidth: CGFloat {
        let valueChars = visibleRows.map { valueText(for: $0).count }.max() ?? 1
        let deltaChars = visibleRows.compactMap { deltaText(for: $0)?.count }.max() ?? 0
        let value = CGFloat(valueChars) * 7.4
        let delta = deltaChars > 0 ? CGFloat(deltaChars) * 6.4 + 5 : 0
        return min(112, max(46, value + delta))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(spacing: 9) {
                if hasBaselines {
                    referenceCaption
                }

                ForEach(visibleRows) { row in
                    rowView(row)
                }

                if hiddenCount > 0 {
                    disclosure
                }
            }
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("LAST 7 DAYS BY MUSCLE")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.textTertiary)

            Spacer(minLength: 8)

            metricPicker
        }
    }

    /// A segmented control rather than three bare words: the old row read as a
    /// legend until you happened to tap it, and the selected state was a weight
    /// change most people wouldn't notice.
    private var metricPicker: some View {
        HStack(spacing: 2) {
            ForEach(MuscleMetric.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        metric = option
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(metric == option ? Color.bg : Color.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(metric == option ? Color.accent : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(option.title.lowercased())")
                .accessibilityAddTraits(metric == option ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.bgSubtle))
    }

    // MARK: - Reference line

    /// Names the line once, above the rows, so the tick repeated down every row
    /// is a labelled reference rather than a mark to guess at.
    private var referenceCaption: some View {
        HStack(spacing: Self.columnSpacing) {
            Color.clear
                .frame(width: Self.nameColumnWidth, height: 1)

            GeometryReader { geo in
                let usable = max(1, geo.size.width - Self.overflowGutter)
                Text("your usual")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.3)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 70, alignment: .center)
                    .offset(x: usable * MuscleRowGeometry.usualFraction - 35)
            }
            .frame(height: 12)

            Color.clear
                .frame(width: valueColumnWidth, height: 1)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Rows

    private func rowView(_ row: MuscleVolumeRow) -> some View {
        HStack(spacing: Self.columnSpacing) {
            Text(row.displayName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: Self.nameColumnWidth, alignment: .leading)

            bar(for: row)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(valueText(for: row))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(
                        row.current(for: metric) == 0 ? Color.textTertiary : Color.textPrimary
                    )

                if let delta = deltaText(for: row) {
                    Text(delta)
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.isAbsent ? Color.danger : Color.textTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: valueColumnWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func bar(for row: MuscleVolumeRow) -> some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - Self.overflowGutter)
            let geometry = MuscleRowGeometry(
                current: row.current(for: metric),
                usual: hasBaselines ? row.baseline(for: metric) : nil
            )
            let fraction = hasBaselines
                ? geometry.fillFraction
                : row.current(for: metric) / absoluteScale
            let tint = MuscleGroupColors.color(for: row.group)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.bgSubtle)
                    .frame(height: Self.barHeight)

                if fraction > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(5, usable * fraction), height: Self.barHeight)
                }

                // A group the user normally trains that got nothing keeps a mark
                // at the start of the track. An entirely empty row reads as a
                // rendering failure; the red pip reads as a zero that counts.
                if row.isAbsent {
                    Circle()
                        .fill(Color.danger)
                        .frame(width: 5, height: 5)
                }

                if hasBaselines {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.textSecondary.opacity(0.75))
                        .frame(width: 2, height: 14)
                        .offset(x: usable * MuscleRowGeometry.usualFraction)

                    if geometry.isOverCap || geometry.isUncompared {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(tint)
                            .offset(x: usable + 3)
                    }
                }
            }
            .frame(height: 14)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
    }

    // MARK: - Values

    /// Counts render as counts. Volume borrows the app's compact formatter but
    /// drops the unit suffix — one global unit repeated down twelve rows is
    /// noise, and the accessibility label still spells it out.
    private func valueText(for row: MuscleVolumeRow) -> String {
        switch metric {
        case .sets:   return "\(row.currentSets)"
        case .reps:   return "\(row.currentReps)"
        case .volume:
            // A group trained only with bodyweight has real work behind a zero.
            // "0" would read as "you skipped it"; the dash says "no weight".
            if row.hasVolumeGap { return "—" }
            return Self.compactVolume(row.currentVolume, unitPreference: unitPreference)
        }
    }

    private func deltaText(for row: MuscleVolumeRow) -> String? {
        guard let baseline = row.baseline(for: metric) else { return nil }

        // Nothing to be a delta against. "+284" against a usual of zero is the
        // same statement as the value itself; "new" is the part worth reading.
        if baseline == 0 {
            // Only meaningful against rows that do have a usual. A user coming
            // back from a lay-off has a zero baseline everywhere, and labelling
            // every group "new" would be a statement about the gap, not about
            // the group.
            guard hasBaselines, row.current(for: metric) > 0,
                  !(metric == .volume && row.hasVolumeGap)
            else { return nil }
            return "new"
        }

        let delta = row.current(for: metric) - baseline
        switch metric {
        case .sets, .reps:
            let rounded = Int(delta.rounded())
            guard rounded != 0 else { return nil }
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        case .volume:
            // Below a kilo of difference there's nothing worth reporting, and a
            // bodyweight-only group's "shortfall" is an artefact of the metric.
            guard !row.hasVolumeGap, abs(delta) >= 1 else { return nil }
            let magnitude = Self.compactVolume(abs(delta), unitPreference: unitPreference)
            return delta > 0 ? "+\(magnitude)" : "-\(magnitude)"
        }
    }

    private static func compactVolume(_ kg: Double, unitPreference: UnitPreference) -> String {
        let formatted = WorkoutPrimaryMetric.volume(kg)
            .formattedValue(style: .compact, unitPreference: unitPreference)
        // The shared formatter appends " kg" / " lb"; the column shows the unit
        // once in the selector instead.
        return formatted
            .replacingOccurrences(of: " kg", with: "")
            .replacingOccurrences(of: " lb", with: "")
    }

    // MARK: - Disclosure

    private var disclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Text(isExpanded ? "Show less" : "Show all \(rows.count) groups")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.accent)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.top, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for row: MuscleVolumeRow) -> String {
        let value = spokenValue(for: row)
        guard let baseline = row.baseline(for: metric) else {
            return "\(row.displayName), \(value)"
        }
        if baseline == 0 {
            guard hasBaselines, row.current(for: metric) > 0 else {
                return "\(row.displayName), \(value)"
            }
            return "\(row.displayName), \(value), new since your last 8 weeks"
        }
        let delta = row.current(for: metric) - baseline
        guard abs(delta) >= 1 else {
            return "\(row.displayName), \(value), about your usual"
        }
        if metric == .volume && row.hasVolumeGap {
            return "\(row.displayName), \(value)"
        }
        let direction = delta > 0 ? "above" : "below"
        return "\(row.displayName), \(value), \(spokenMagnitude(abs(delta))) \(direction) your usual"
    }

    private func spokenValue(for row: MuscleVolumeRow) -> String {
        switch metric {
        case .sets:   return row.currentSets == 1 ? "1 set" : "\(row.currentSets) sets"
        case .reps:   return row.currentReps == 1 ? "1 rep" : "\(row.currentReps) reps"
        case .volume:
            if row.hasVolumeGap { return "bodyweight only, no volume recorded" }
            return WorkoutPrimaryMetric.volume(row.currentVolume)
                .formattedValue(style: .compact, unitPreference: unitPreference)
        }
    }

    private func spokenMagnitude(_ magnitude: Double) -> String {
        switch metric {
        case .sets, .reps: return "\(Int(magnitude.rounded()))"
        case .volume:
            return WorkoutPrimaryMetric.volume(magnitude)
                .formattedValue(style: .compact, unitPreference: unitPreference)
        }
    }
}

// MARK: - Previews

#Preview("Muscle panel — leg-focused week") {
    struct Harness: View {
        @State private var metric: MuscleMetric = .reps
        @State private var isExpanded = false

        /// The reported screen: one group an order of magnitude past the rest,
        /// which flattened every other row under the old shared scale.
        private let rows: [MuscleVolumeRow] = [
            MuscleVolumeRow(
                group: "legs", displayName: "Legs",
                currentSets: 12, baselineSets: 6,
                currentReps: 284, baselineReps: 43,
                currentVolume: 14_200, baselineVolume: 4_100
            ),
            MuscleVolumeRow(
                group: "chest", displayName: "Chest",
                currentSets: 8, baselineSets: 5,
                currentReps: 84, baselineReps: 38,
                currentVolume: 6_400, baselineVolume: 3_900
            ),
            MuscleVolumeRow(
                group: "back", displayName: "Back",
                currentSets: 6, baselineSets: 5,
                currentReps: 42, baselineReps: 34,
                currentVolume: 5_100, baselineVolume: 4_400
            ),
            MuscleVolumeRow(
                group: "shoulders", displayName: "Shoulders",
                currentSets: 4, baselineSets: 6,
                currentReps: 24, baselineReps: 34,
                currentVolume: 1_800, baselineVolume: 2_600
            ),
            // Trained hard, no weight — the volume view must not read as a skip.
            MuscleVolumeRow(
                group: "abs", displayName: "Abs",
                currentSets: 0, baselineSets: 3,
                currentReps: 0, baselineReps: 5,
                currentVolume: 0, baselineVolume: 0
            ),
            MuscleVolumeRow(
                group: "triceps", displayName: "Triceps",
                currentSets: 4, baselineSets: 1,
                currentReps: 24, baselineReps: 3,
                currentVolume: 900, baselineVolume: 200
            ),
        ]

        var body: some View {
            VStack(spacing: 20) {
                MuscleVolumePanelView(
                    rows: rows,
                    isExpanded: $isExpanded,
                    metric: $metric,
                    unitPreference: .metric
                )
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.bg)
        }
    }

    return Harness()
}

#Preview("Muscle panel — cold start") {
    struct Harness: View {
        @State private var metric: MuscleMetric = .sets
        @State private var isExpanded = false

        private let rows: [MuscleVolumeRow] = [
            MuscleVolumeRow(
                group: "chest", displayName: "Chest",
                currentSets: 12, baselineSets: nil,
                currentReps: 96, baselineReps: nil,
                currentVolume: 4_200, baselineVolume: nil
            ),
            MuscleVolumeRow(
                group: "back", displayName: "Back",
                currentSets: 8, baselineSets: nil,
                currentReps: 72, baselineReps: nil,
                currentVolume: 3_600, baselineVolume: nil
            ),
        ]

        var body: some View {
            MuscleVolumePanelView(
                rows: rows,
                isExpanded: $isExpanded,
                metric: $metric,
                unitPreference: .metric
            )
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.bg)
        }
    }

    return Harness()
}
