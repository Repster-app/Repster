// MuscleVolumePanelView.swift
// Trailing-week sets per muscle group against each group's own baseline.
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

import SwiftUI

struct MuscleVolumePanelView: View {
    let rows: [MuscleVolumeRow]
    @Binding var isExpanded: Bool

    /// Enough to cover a typical split without turning Home's destination into
    /// a wall of bars.
    static let collapsedRowCount = 6

    private var visibleRows: [MuscleVolumeRow] {
        isExpanded ? rows : Array(rows.prefix(Self.collapsedRowCount))
    }

    private var hiddenCount: Int {
        max(0, rows.count - Self.collapsedRowCount)
    }

    /// Bars scale against the largest baseline so the tick marks line up
    /// meaningfully across rows. Falls back to current volume during cold start.
    private var scale: Double {
        var maximum = 1.0
        for row in rows {
            maximum = max(maximum, row.baselineSets ?? 0)
            maximum = max(maximum, Double(row.currentSets))
        }
        return maximum
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST 7 DAYS BY MUSCLE")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.textTertiary)

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

    private func rowView(_ row: MuscleVolumeRow) -> some View {
        HStack(spacing: 9) {
            Text(row.displayName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .frame(width: 62, alignment: .leading)

            bar(for: row)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(row.currentSets)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(row.currentSets == 0 ? Color.textTertiary : Color.textPrimary)

                if let delta = row.delta, delta != 0 {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.isAbsent ? Color.danger : Color.textTertiary)
                }
            }
            .frame(width: 46, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func bar(for row: MuscleVolumeRow) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.bgSubtle)
                    .frame(height: 8)

                if row.currentSets > 0 {
                    Capsule()
                        .fill(MuscleGroupColors.color(for: row.group))
                        .frame(
                            width: max(4, geo.size.width * (Double(row.currentSets) / scale)),
                            height: 8
                        )
                }

                if let baseline = row.baselineSets, baseline > 0 {
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

    private func accessibilityLabel(for row: MuscleVolumeRow) -> String {
        let sets = row.currentSets == 1 ? "1 set" : "\(row.currentSets) sets"
        guard let delta = row.delta else { return "\(row.displayName), \(sets)" }
        if delta == 0 { return "\(row.displayName), \(sets), level with your baseline" }
        let direction = delta > 0 ? "above" : "below"
        return "\(row.displayName), \(sets), \(abs(delta)) \(direction) your baseline"
    }
}
