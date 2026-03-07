// CalendarExerciseCard.swift
// Read-only exercise card with name, set rows, PR badges.
// Spec: 008-calendar-tab, WP03 T012. Pattern: design-system.md "Exercise Card (Day View)"

import SwiftUI

struct CalendarExerciseCard: View {
    let exercise: Exercise
    let sets: [WorkoutSet]
    let stats: ExerciseStats?
    let onTapped: () -> Void

    private var displaySets: [WorkoutSet] {
        sets.filter { $0.modelContext != nil && $0.hasData }
            .sorted { $0.orderInExercise < $1.orderInExercise }
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
            .background(Color.bgCard)
            .cornerRadius(14)
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
            // Column headers
            HStack {
                Text("SET")
                    .frame(width: 32, alignment: .leading)
                Text("WEIGHT")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("REPS")
                    .frame(width: 44, alignment: .center)
                Text("RIR")
                    .frame(width: 32, alignment: .center)
                Color.clear
                    .frame(width: 44)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.textTertiary)
            .padding(.bottom, 6)

            // Set rows
            ForEach(Array(displaySets.enumerated()), id: \.element.id) { index, workoutSet in
                setRow(index: index + 1, workoutSet: workoutSet)
            }
        }
    }

    @ViewBuilder
    private func setRow(index: Int, workoutSet: WorkoutSet) -> some View {
        // Guard against deleted/detached SwiftData objects to prevent crashes
        if workoutSet.modelContext == nil {
            EmptyView()
        } else {
        let isWarmup = workoutSet.setType == .warmup
        let hasNote = workoutSet.notes != nil && !(workoutSet.notes?.isEmpty ?? true)

        HStack {
            // Set number with optional note dot
            ZStack(alignment: .topTrailing) {
                Text("\(index)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)

                if hasNote {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .offset(x: 4, y: -2)
                }
            }
            .frame(width: 32, alignment: .leading)

            Text(formatWeight(workoutSet))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(formatReps(workoutSet))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 44, alignment: .center)

            // RIR value (color-coded)
            Text(formatRIR(workoutSet))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rirColor(for: workoutSet.rir))
                .frame(width: 32, alignment: .center)

            Color.clear
                .frame(width: 44, height: 1)
                .overlay(alignment: .trailing) {
                    PRBadgeView(status: workoutSet.cachedPRStatus)
                }
        }
        .padding(.vertical, 4)
        .opacity(isWarmup ? 0.45 : 1.0)
        }
    }

    // MARK: - Formatting

    private func formatWeight(_ set: WorkoutSet) -> String {
        guard let weight = set.effectiveWeight else { return "—" }
        return "\(UnitConversion.formatWeight(weight)) kg"
    }

    private func formatReps(_ set: WorkoutSet) -> String {
        guard let reps = set.reps else { return "—" }
        return "\(reps)"
    }

    private func formatRIR(_ set: WorkoutSet) -> String {
        guard let rir = set.rir else { return "—" }
        return rir >= 5 ? "5+" : "\(Int(rir))"
    }
}
