// CopyPreviousSheet.swift
// Modal sheet for selecting a past workout to copy.
// Spec: 013-home-screen, WP04 T018

import SwiftUI

struct CopyPreviousSheet: View {
    let services: ServiceContainer
    @Binding var showDiscardConfirmation: Bool
    let onWorkoutSelected: (UUID) -> Void
    let onDiscardAndCopy: () -> Void
    let onCancelDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Loaded inside the sheet rather than handed in by the presenter: the list used to be
    /// fetched while the Start Workout sheet was still dismissing, and the sheet came up
    /// showing whatever the presenter's state held at that moment — nothing, on first open.
    @State private var workouts: [CopyPreviousWorkout] = []
    @State private var isLoading = true

    /// Copying is a recency habit — people repeat last week's session, not one from eight
    /// months ago. Every workout past this cap costs a set fetch to build a card nobody
    /// scrolls to. Finding an old session wants search, not a longer list.
    private static let workoutLimit = 30

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingState
                } else if workouts.isEmpty {
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
        .task { await loadWorkouts() }
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
                    Text(primaryMetric.formattedValue(unitPreference: services.unitPreference))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.textTertiary)

            // Same flowing tags as the home screen's recent workout cards — an HStack here
            // squeezed the wider names until they wrapped mid-word ("Shoulder / s").
            if !workout.muscleGroups.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(workout.muscleGroups, id: \.self) { muscle in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(MuscleGroupColors.color(for: muscle))
                                .frame(width: 4, height: 4)
                            Text(ExercisePrimaryGroup.displayName(for: muscle))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
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

    // MARK: - Placeholder States

    @ViewBuilder
    private var loadingState: some View {
        ProgressView()
            .tint(Color.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No workouts yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    @MainActor
    private func loadWorkouts() async {
        defer { isLoading = false }
        do {
            let allWorkouts = try await services.workoutService.fetchAllWorkoutSummaries(limit: nil, offset: nil)
            // Capped after the status filter, not via fetchAllWorkoutSummaries(limit:) —
            // limiting the query would cap the pre-filter set and silently drop completed
            // workouts behind any in-progress ones.
            let completed = allWorkouts
                .filter { $0.status == .completed }
                .sorted { $0.date > $1.date }
                .prefix(Self.workoutLimit)

            // A lifter rotates a few dozen exercises, so the same ones recur in almost every
            // workout. Without this each one is refetched per workout it appears in.
            var exerciseCache: [UUID: ChartExerciseData] = [:]
            var items: [CopyPreviousWorkout] = []
            for workout in completed {
                let sets = try await services.setService.fetchSetSnapshots(for: workout.id)
                // Performed work, not just straight sets: you are copying a session you did,
                // and the drop sets were part of it.
                let workingSetsWithData = sets.filter { $0.setType.countsAsPerformedWork && $0.hasData }
                // First-appearance order, not Set order. Sets come back sorted by
                // orderInWorkout, so this lists muscles in the order they were trained —
                // and stays put between launches, which Set iteration does not.
                var seenExerciseIds: Set<UUID> = []
                let exerciseIds = sets.map(\.exerciseId).filter { seenExerciseIds.insert($0).inserted }

                var exerciseLookup: [UUID: ChartExerciseData] = [:]
                var muscleGroups: [String] = []
                for exerciseId in exerciseIds {
                    let exercise: ChartExerciseData?
                    if let cached = exerciseCache[exerciseId] {
                        exercise = cached
                    } else {
                        // Misses aren't cached — a nil here means a deleted exercise, which
                        // is rare enough not to be worth an optional-of-optional dictionary.
                        exercise = try await services.exerciseService.fetchExerciseSnapshot(exerciseId)
                        if let exercise { exerciseCache[exerciseId] = exercise }
                    }
                    guard let exercise else { continue }

                    exerciseLookup[exerciseId] = exercise
                    if let muscle = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle),
                       !muscleGroups.contains(muscle) {
                        muscleGroups.append(muscle)
                    }
                }
                let aggregate = WorkoutAggregateSummary.summarize(
                    sets: workingSetsWithData,
                    exercisesById: exerciseLookup
                )

                items.append(CopyPreviousWorkout(
                    id: workout.id,
                    displayTitle: workout.displayTitle,
                    date: workout.date,
                    exerciseCount: exerciseIds.count,
                    setCount: workingSetsWithData.count,
                    primaryMetric: aggregate.primaryMetric,
                    muscleGroups: muscleGroups
                ))
            }

            workouts = items
        } catch {
            dbg("[CopyPreviousSheet] Failed to load workouts: \(error)")
        }
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}
