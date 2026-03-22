// ExerciseCardView.swift
// Compact card showing exercise summary with muscle color dot and workout count.
// Spec: FR-004, design-system.md Section 6.2
// Feature: 007-exercise-list-and-detail WP02 T009

import SwiftUI

struct ExerciseCardView: View {
    let exercise: Exercise
    let stats: ExerciseStats?
    let isSelected: Bool
    let mode: ExerciseListMode

    var onSelectionToggle: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            // Leading: Muscle group color dot
            Circle()
                .fill(MuscleGroupColors.color(for: exercise.primaryMuscle ?? ""))
                .frame(width: 10, height: 10)

            // Center: Exercise info
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if let lastDate = stats?.lastPerformedDate {
                    Text(lastDate, style: .date)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Text("Never performed")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            // Trailing: Workout count
            if let workoutCount = stats?.totalWorkouts, workoutCount > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(workoutCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(workoutCount == 1 ? "workout" : "workouts")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Selection checkmark for addToWorkout mode only
            if mode == .addToWorkout {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accent : Color.textTertiary.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isSelected && mode == .addToWorkout ? Color.accentSoft : Color.bgCard)
        .cornerRadius(10)
    }
}
