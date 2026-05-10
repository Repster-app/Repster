// CopyPreviousSheet.swift
// Modal sheet for selecting a past workout to copy.
// Spec: 013-home-screen, WP04 T018

import SwiftUI

struct CopyPreviousSheet: View {
    let workouts: [CopyPreviousWorkout]
    let unitPreference: UnitPreference
    @Binding var showDiscardConfirmation: Bool
    let onWorkoutSelected: (UUID) -> Void
    let onDiscardAndCopy: () -> Void
    let onCancelDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    emptyState
                } else {
                    workoutList
                }
            }
            .navigationTitle("Copy Previous")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .background(Color.bg)
            .confirmationDialog(
                "Active Workout",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard & Copy", role: .destructive) {
                    onDiscardAndCopy()
                }
                Button("Cancel", role: .cancel) {
                    onCancelDiscard()
                }
            } message: {
                Text("You have an active workout. Discard it and start a copy?")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Workout List

    @ViewBuilder
    private var workoutList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(workouts) { workout in
                    Button {
                        onWorkoutSelected(workout.id)
                    } label: {
                        workoutRow(workout)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func workoutRow(_ workout: CopyPreviousWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(formatDate(workout.date))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 12) {
                Text("\(workout.exerciseCount) exercises")
                Text("\u{00B7}")
                Text("\(workout.setCount) sets")
                if let primaryMetric = workout.primaryMetric {
                    Text("\u{00B7}")
                    Text(primaryMetric.formattedValue(unitPreference: unitPreference))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.textTertiary)

            if !workout.muscleGroups.isEmpty {
                HStack(spacing: 6) {
                    ForEach(workout.muscleGroups, id: \.self) { muscle in
                        Text(ExercisePrimaryGroup.displayName(for: muscle))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.bgSubtle)
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No workouts yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}
