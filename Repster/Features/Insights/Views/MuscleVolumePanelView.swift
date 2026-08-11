// MuscleVolumePanelView.swift
// Trailing-week work per muscle group against each group's own baseline.
//
// Groups come from the user's own exercises, so custom values ("calves",
// "glutes") appear here alongside the catalog ones. Rows rank by baseline
// rather than current volume — sorting by this week buries the group that got
// skipped, which is the one worth seeing.
//
// Deltas are deliberately not coloured green/red: that would assert more volume
// is better, which isn't reliably true and contradicts the readiness rule. The
// one exception is a group with a real baseline that got nothing, which is a
// fact rather than a verdict.
//
// The metric selector lives on the header line rather than in a bar of its own:
// this panel sits under the status card and shouldn't out-weigh it.

import SwiftUI

struct MuscleVolumePanelView: View {
    let rows: [MuscleVolumeRow]
    @Binding var isExpanded: Bool
    @Binding var metric: MuscleMetric
    let unitPreference: UnitPreference

    /// Enough to cover a typical split without turning Home's destination into
    /// a wall of bars.
    static let collapsedRowCount = 6

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

    /// Bars scale against the largest value in the selected metric so the tick
    /// marks line up meaningfully across rows. Falls back to current volume
    /// during cold start.
    private var scale: Double {
        var maximum = 1.0
        for row in rows {
            maximum = max(maximum, row.baseline(for: metric) ?? 0)
            maximum = max(maximum, row.current(for: metric))
        }
        return maximum
    }

    /// Volume needs room for "8.9k" plus a signed delta; counts don't.
    private var valueColumnWidth: CGFloat {
        metric == .volume ? 78 : 46
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(spacing: 9) {
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

            HStack(spacing: 10) {
                ForEach(MuscleMetric.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            metric = option
                        }
                    } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: metric == option ? .semibold : .medium))
                            .foregroundStyle(metric == option ? Color.accent : Color.textTertiary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(option.title.lowercased())")
                    .accessibilityAddTraits(metric == option ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: - Rows

    private func rowView(_ row: MuscleVolumeRow) -> some View {
        HStack(spacing: 9) {
            Text(row.displayName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .frame(width: 62, alignment: .leading)

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
            .frame(width: valueColumnWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func bar(for row: MuscleVolumeRow) -> some View {
        GeometryReader { geo in
            let current = row.current(for: metric)
            let baseline = row.baseline(for: metric)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.bgSubtle)
                    .frame(height: 8)

                if current > 0 {
                    Capsule()
                        .fill(MuscleGroupColors.color(for: row.group))
                        .frame(width: max(4, geo.size.width * (current / scale)), height: 8)
                }

                if let baseline, baseline > 0 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.textSecondary.opacity(0.75))
                        .frame(width: 2, height: 14)
                        .offset(x: min(geo.size.width - 2, geo.size.width * (baseline / scale)))
                }
            }
            .frame(height: 14)
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
        guard let delta = row.delta(for: metric) else { return nil }
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
        guard let delta = row.delta(for: metric), abs(delta) >= 1 else {
            return "\(row.displayName), \(value)"
        }
        if metric == .volume && row.hasVolumeGap {
            return "\(row.displayName), \(value)"
        }
        let direction = delta > 0 ? "above" : "below"
        return "\(row.displayName), \(value), \(spokenMagnitude(abs(delta))) \(direction) your baseline"
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

#Preview("Muscle panel — metrics") {
    struct Harness: View {
        @State private var metric: MuscleMetric = .sets
        @State private var isExpanded = false

        private let rows: [MuscleVolumeRow] = [
            MuscleVolumeRow(
                group: "chest", displayName: "Chest",
                currentSets: 24, baselineSets: 20,
                currentReps: 210, baselineReps: 180,
                currentVolume: 8_900, baselineVolume: 7_700
            ),
            MuscleVolumeRow(
                group: "back", displayName: "Back",
                currentSets: 18, baselineSets: 17,
                currentReps: 160, baselineReps: 158,
                currentVolume: 7_100, baselineVolume: 6_700
            ),
            // Trained hard, no weight — the volume view must not read as a skip.
            MuscleVolumeRow(
                group: "abs", displayName: "Abs",
                currentSets: 9, baselineSets: 8,
                currentReps: 140, baselineReps: 120,
                currentVolume: 0, baselineVolume: 0
            ),
            // Genuinely skipped this week.
            MuscleVolumeRow(
                group: "legs", displayName: "Legs",
                currentSets: 0, baselineSets: 14,
                currentReps: 0, baselineReps: 120,
                currentVolume: 0, baselineVolume: 12_400
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
