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

                    activeWorkoutStats
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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

    private var activeWorkoutStats: some View {
        ViewThatFits(in: .horizontal) {
            activeWorkoutStatsRow
            activeWorkoutStatsFallback
        }
    }

    private var activeWorkoutStatsRow: some View {
        HStack(spacing: 12) {
            timerStat
            exerciseStat
            setStat
        }
    }

    private var activeWorkoutStatsFallback: some View {
        VStack(alignment: .leading, spacing: 6) {
            timerStat

            if activeExerciseCount > 0 || activeSetCount > 0 {
                HStack(spacing: 12) {
                    exerciseStat
                    setStat
                }
            }
        }
    }

    @ViewBuilder
    private var timerStat: some View {
        if let startTime = activeWorkoutStartTime {
            activeWorkoutStat(systemImage: "clock") {
                Text(startTime, style: .timer)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var exerciseStat: some View {
        if activeExerciseCount > 0 {
            activeWorkoutStat(systemImage: "dumbbell") {
                Text("\(activeExerciseCount) exercises")
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var setStat: some View {
        if activeSetCount > 0 {
            activeWorkoutStat(systemImage: "checkmark.circle") {
                Text("\(activeSetCount) sets")
                    .lineLimit(1)
            }
        }
    }

    private func activeWorkoutStat<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            content()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.textSecondary)
        .fixedSize(horizontal: true, vertical: false)
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

// MARK: - Previews

#Preview("Active Workout - Standard Width") {
    StartWorkoutCardPreview(
        startTime: StartWorkoutCardPreviewData.standardStartTime,
        exerciseCount: 5,
        setCount: 7,
        width: nil
    )
}

#Preview("Active Workout - Narrow Width") {
    StartWorkoutCardPreview(
        startTime: StartWorkoutCardPreviewData.standardStartTime,
        exerciseCount: 5,
        setCount: 7,
        width: 310
    )
}

#Preview("Active Workout - Long Timer") {
    StartWorkoutCardPreview(
        startTime: StartWorkoutCardPreviewData.longTimerStartTime,
        exerciseCount: 12,
        setCount: 18,
        width: 310
    )
}

private struct StartWorkoutCardPreview: View {
    let startTime: Date
    let exerciseCount: Int
    let setCount: Int
    let width: CGFloat?

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            previewCard
        }
    }

    private var previewCard: some View {
        Group {
            if let width {
                card
                    .frame(width: width)
            } else {
                card
            }
        }
        .padding()
    }

    private var card: some View {
        StartWorkoutCardView(
            hasActiveWorkout: true,
            activeWorkoutStartTime: startTime,
            activeExerciseCount: exerciseCount,
            activeSetCount: setCount,
            accessMessage: nil,
            onCardTapped: {},
            onPlusTapped: {}
        )
    }
}

private enum StartWorkoutCardPreviewData {
    static let standardStartTime = Date(timeIntervalSinceNow: -1164)
    static let longTimerStartTime = Date(timeIntervalSinceNow: -11862)
}
