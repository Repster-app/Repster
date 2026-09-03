// CalendarExerciseCard.swift
// Read-only exercise card with name, set rows, PR badges.
// Spec: 008-calendar-tab, WP03 T012. Pattern: design-system.md "Exercise Card (Day View)"

import SwiftUI

struct CalendarExerciseCard: View {
    let exercise: ChartExerciseData
    let sets: [ChartSetData]
    let stats: ChartExerciseStatsData?
    let unitPreference: UnitPreference
    let onTapped: () -> Void

    /// Whether this card sits inside a superset container.
    ///
    /// Only the surface changes: the container carries the `bgCard` fill, the radius and the
    /// group's border, so a nested card must not paint its own or it reads as a card sitting *on*
    /// the group rather than in it. Padding is unchanged, so the rows line up with an unnested card
    /// directly above or below. See SUPERSETS_SCOPING.md §5.2.
    var insideSupersetCard: Bool = false

    private var displaySets: [ChartSetData] {
        sets.filter { $0.hasData }
            .sorted { $0.orderInExercise < $1.orderInExercise }
    }

    private var readOnlyFields: [WorkoutSetReadOnlyField] {
        WorkoutSetPerformanceFormatter.readOnlyFields(for: exercise.trackingType)
    }

    var body: some View {
        Button(action: onTapped) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if !displaySets.isEmpty {
                    setTable
                }
            }
            .padding(14)
            .background(insideSupersetCard ? Color.clear : Color.bgCard)
            .cornerRadius(insideSupersetCard ? 0 : 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Text(exercise.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text("\(displaySets.count) sets")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.bgSubtle)
                .cornerRadius(6)
        }
    }

    // MARK: - Set Table

    private var setTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SET")
                    .frame(width: 32, alignment: .leading)
                ForEach(readOnlyFields) { field in
                    headerCell(for: field)
                }
                Color.clear
                    .frame(width: 44)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.textTertiary)
            .padding(.bottom, 6)

            let labels = SetBadgeLabel.assign(for: displaySets.map(\.setType))
            ForEach(Array(displaySets.enumerated()), id: \.element.id) { index, workoutSet in
                setRow(label: labels[index], workoutSet: workoutSet)
            }
        }
    }

    /// Warm-ups and drop sets carry the same colours here as everywhere else — gold and
    /// `chart5` — so the set type is readable without opening the workout.
    private func labelTint(for label: SetBadgeLabel) -> Color {
        switch label {
        case .warmup:  return .gold
        case .dropset: return .chart5
        case .working: return .textSecondary
        }
    }

    // The `workoutSet.modelContext == nil` guard that used to wrap this row is gone: it
    // existed to swallow crashes from live models detaching mid-render, and a snapshot
    // has no context to detach from.
    private func setRow(label: SetBadgeLabel, workoutSet: ChartSetData) -> some View {
        let isWarmup = workoutSet.setType == .warmup

        return HStack {
            ZStack(alignment: .topTrailing) {
                // This card used to print `index + 1` for every set and lean on opacity alone,
                // so a warm-up was numbered as a working set and looked merely faint. It now
                // shares `SetBadgeLabel` with the set table and the exercise history.
                Text(label.text)
                    .font(.system(size: 12))
                    .foregroundStyle(labelTint(for: label))

                if workoutSet.hasNote {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .offset(x: 4, y: -2)
                }
            }
            .frame(width: 32, alignment: .leading)

            ForEach(readOnlyFields) { field in
                fieldView(
                    WorkoutSetPerformanceFormatter.fieldDisplay(
                        for: field,
                        set: workoutSet,
                        exercise: exercise,
                        unitPreference: unitPreference
                    ),
                    field: field,
                    set: workoutSet
                )
            }

            Color.clear
                .frame(width: 44, height: 1)
                .overlay(alignment: .trailing) {
                    PRBadgeView(status: CachedPRStatus.effectiveStatus(for: workoutSet, among: displaySets))
                }
        }
        .padding(.vertical, 4)
        .opacity(isWarmup ? 0.45 : 1.0)
    }

    private func headerCell(for field: WorkoutSetReadOnlyField) -> some View {
        Text(field.title)
            .frame(maxWidth: .infinity, alignment: alignment(for: field))
    }

    @ViewBuilder
    private func fieldView(
        _ display: WorkoutSetReadOnlyCellDisplay,
        field: WorkoutSetReadOnlyField,
        set: ChartSetData
    ) -> some View {
        if !display.stackedLabels.isEmpty {
            VStack(spacing: 1) {
                ForEach(display.stackedLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(field == .rir ? Color.textSecondary : Color.textPrimary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment(for: field))
        } else {
            Text(display.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color(for: field, text: display.text, set: set))
                .frame(maxWidth: .infinity, alignment: alignment(for: field))
        }
    }

    private func alignment(for field: WorkoutSetReadOnlyField) -> Alignment {
        switch field {
        case .weight:
            return .trailing
        case .reps, .distance, .time, .rir:
            return .center
        }
    }

    private func color(for field: WorkoutSetReadOnlyField, text: String, set: ChartSetData) -> Color {
        guard field == .rir else { return .textPrimary }
        return text == "—" ? .textSecondary : Color.rirColor(for: set.rir)
    }
}
