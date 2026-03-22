// ExerciseHistoryView.swift
// Shows past sessions for an exercise, grouped by workout, newest first.
// Spec: FR-006, SC-002
// Contract: view-contracts.md ExerciseHistoryView
// Feature: 007-exercise-list-and-detail WP04 T018

import SwiftUI

struct ExerciseHistoryView: View {

    let historyWorkouts: [WorkoutHistoryGroup]

    // MARK: - Body

    var body: some View {
        if historyWorkouts.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(historyWorkouts) { group in
                        workoutSessionCard(group)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Session Card

    private func workoutSessionCard(_ group: WorkoutHistoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatDate(group.date))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 0) {
                ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
                    setRow(set, index: index, siblings: group.sets)
                    if index < group.sets.count - 1 {
                        Divider()
                            .background(Color.border)
                    }
                }
            }
            .padding(12)
            .background(Color.bgCard)
            .cornerRadius(10)
        }
    }

    // MARK: - Set Row

    private func setRow(_ set: WorkoutSet, index: Int, siblings: [WorkoutSet]) -> some View {
        let hasNote = set.notes != nil && !(set.notes?.isEmpty ?? true)
        let isWarmup = set.setType == .warmup

        return HStack(spacing: 8) {
            // Set number with note indicator and set type badge
            ZStack(alignment: .topTrailing) {
                if isWarmup {
                    Text("W")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.gold)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }

                if hasNote {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .offset(x: 4, y: -2)
                }
            }
            .frame(width: 24)

            if let performanceLabel = formattedPerformanceLabel(for: set) {
                Text(performanceLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
            }

            // RIR display (color-coded)
            if let rir = set.rir {
                Text("RIR \(rir >= 5 ? "5+" : "\(Int(rir))")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.rirColor(for: rir))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.rirColor(for: rir).opacity(0.10))
                    .cornerRadius(4)
            }

            Spacer()

            PRBadgeView(status: CachedPRStatus.effectiveStatus(for: set, among: siblings))
        }
        .padding(.vertical, 6)
        .opacity(isWarmup ? 0.6 : 1.0)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("No history yet")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func formatWeight(_ weight: Double) -> String {
        "\(UnitConversion.formatWeight(weight)) kg"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        if meters == meters.rounded() {
            return String(format: "%.0f m", meters)
        }
        return String(format: "%.1f m", meters)
    }

    private func formattedPerformanceLabel(for set: WorkoutSet) -> String? {
        if let weight = set.weight, let reps = set.reps, reps > 0 {
            let weightLabel = weight > 0 ? formatWeight(weight) : "BW"
            return "\(weightLabel) × \(reps)"
        }
        if let weight = set.weight, weight > 0,
           let distance = set.distanceMeters, distance > 0 {
            return "\(formatWeight(weight)) • \(formatDistance(distance))"
        }
        if let duration = set.durationSeconds, duration > 0,
           let distance = set.distanceMeters, distance > 0 {
            return "\(UnitConversion.formatDuration(duration)) • \(formatDistance(distance))"
        }
        if let duration = set.durationSeconds, duration > 0 {
            return UnitConversion.formatDuration(duration)
        }
        if let distance = set.distanceMeters, distance > 0 {
            return formatDistance(distance)
        }
        return nil
    }
}
