// StartWorkoutCardView.swift
// Dual-state CTA card: "Start Workout" when idle, "Current Workout" when active.
// Spec: 013-home-screen, WP03 T013

import SwiftUI

struct StartWorkoutCardView: View {
    let hasActiveWorkout: Bool
    let activeWorkoutStartTime: Date?
    let activeExerciseCount: Int
    let activeSetCount: Int
    let accessMessage: String?
    let onCardTapped: () -> Void
    let onPlusTapped: () -> Void

    var body: some View {
        if hasActiveWorkout {
            activeWorkoutCard
        } else {
            startWorkoutCard
        }
    }

    // MARK: - Active Workout Card

    private var activeWorkoutCard: some View {
        Button(action: onCardTapped) {
            HStack(spacing: 12) {
                // Pulsing indicator
                Circle()
                    .fill(Color.accent)
                    .frame(width: 10, height: 10)
                    .shadow(color: Color.accent.opacity(0.6), radius: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKOUT IN PROGRESS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .kerning(0.8)

                    Text("Resume Workout")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 12) {
                        if let startTime = activeWorkoutStartTime {
                            Label {
                                Text(startTime, style: .timer)
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        }

                        if activeExerciseCount > 0 {
                            Label("\(activeExerciseCount) exercises", systemImage: "dumbbell")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }

                        if activeSetCount > 0 {
                            Label("\(activeSetCount) sets", systemImage: "checkmark.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accent)
                    .cornerRadius(22)
            }
            .padding(14)
            .background(Color.accentSoft)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Start Workout Card

    private var startWorkoutCard: some View {
        Button(action: onCardTapped) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("READY TO TRAIN")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .kerning(0.8)

                    Text("Start Workout")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text("Log exercises, sets & reps")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.textSecondary)

                    if let accessMessage, !accessMessage.isEmpty {
                        Text(accessMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accent)
                    }
                }

                Spacer()

                Button(action: onPlusTapped) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accent)
                        .cornerRadius(22)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
