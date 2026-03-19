// CalendarWorkoutDetailView.swift
// Container for workout detail: stats strip + exercise cards.
// Handles multiple workouts per date with session labels and dividers.
// Spec: 008-calendar-tab, WP03 T013/T016

import SwiftUI

struct CalendarWorkoutDetailView: View {
    let workoutDetails: [WorkoutDetail]
    let selectedDate: Date
    let onSaveAsTemplate: ((Workout) -> Void)?
    let onExerciseTapped: (UUID) -> Void

    var body: some View {
        if workoutDetails.isEmpty {
            emptyState
        } else {
            VStack(spacing: 16) {
                ForEach(Array(workoutDetails.enumerated()), id: \.element.workout.id) { index, detail in
                    if index > 0 {
                        Divider()
                            .background(Color.border)
                            .padding(.vertical, 8)
                    }
                    workoutSection(detail)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Workout Section

    @ViewBuilder
    private func workoutSection(_ detail: WorkoutDetail) -> some View {
        VStack(spacing: 12) {
            if let onSaveAsTemplate {
                workoutHeader(detail.workout, onSaveAsTemplate: onSaveAsTemplate)
            } else if workoutDetails.count > 1 {
                sessionLabel(detail.workout)
            }

            SummaryStatsStrip(
                totalVolume: detail.totalVolume,
                exerciseCount: detail.exerciseCount,
                setCount: detail.setCount,
                duration: detail.workout.duration
            )

            ForEach(detail.exerciseGroups, id: \.exercise.id) { group in
                CalendarExerciseCard(
                    exercise: group.exercise,
                    sets: group.sets,
                    stats: group.stats,
                    onTapped: { onExerciseTapped(group.exercise.id) }
                )
            }
        }
    }

    // MARK: - Session Label (T016)

    private func workoutHeader(
        _ workout: Workout,
        onSaveAsTemplate: @escaping (Workout) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                if workoutDetails.count > 1 {
                    sessionLabel(workout)
                }
            }

            Spacer()

            Menu {
                Button {
                    onSaveAsTemplate(workout)
                } label: {
                    Label("Save as Template", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
    }

    private func sessionLabel(_ workout: Workout) -> some View {
        let label: String = {
            guard let startTime = workout.startTime else { return "Session" }
            let hour = Calendar.current.component(.hour, from: startTime)
            if hour < 12 { return "Morning Session" }
            if hour < 17 { return "Afternoon Session" }
            return "Evening Session"
        }()

        return Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No workout")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
