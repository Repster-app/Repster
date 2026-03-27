// EditWorkoutView.swift
// Full-screen edit view for completed workouts.
// Simplified version of ActiveWorkoutView without timers, sub-tabs, or finish flow.
// Spec: 015-edit-historic-workout, FR-001 through FR-012

import SwiftUI

struct EditWorkoutView: View {

    // MARK: - State

    @State private var viewModel: EditWorkoutViewModel
    @State private var showWorkoutExclusionSheet = false

    // MARK: - Dependencies

    private let services: ServiceContainer

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    init(workoutId: UUID, services: ServiceContainer) {
        _viewModel = State(initialValue: EditWorkoutViewModel(
            workoutId: workoutId,
            workoutService: services.workoutService,
            setService: services.setService,
            exerciseService: services.exerciseService,
            statsService: services.statsService
        ))
        self.services = services
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ExerciseTabStripView(dataSource: viewModel)

            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .tint(Color.accent)
                Spacer()
            } else if viewModel.currentExercise != nil {
                ScrollView {
                    SetTableView(dataSource: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    notesSection
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                }
            } else {
                emptyExerciseState
            }

            Spacer(minLength: 0)
        }
        .background(Color.bg.ignoresSafeArea())
        .task {
            await viewModel.loadWorkout()
        }
        .sheet(isPresented: $viewModel.showAddExerciseSheet) {
            exercisePickerSheet
        }
        .sheet(isPresented: $showWorkoutExclusionSheet) {
            if let workout = viewModel.workout {
                WorkoutExclusionSheet(
                    workout: workout,
                    exercises: viewModel.exercises
                ) { excludeWorkout, excludedExerciseIds in
                    try await viewModel.updateProgressionExclusions(
                        excludeWorkout: excludeWorkout,
                        excludedExerciseIds: excludedExerciseIds
                    )
                }
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Done / dismiss button
            Button {
                Task {
                    await viewModel.saveDirtySets()
                    await viewModel.saveNotes()
                    dismiss()
                }
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accent)
                    .frame(height: 44)
            }

            Spacer()

            Text("Edit Workout")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)

            Spacer()

            Button {
                showWorkoutExclusionSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .frame(width: 44, height: 44)
            }

            // +Exercise button
            Button {
                viewModel.showAddExerciseSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accent)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textSecondary)

            ZStack(alignment: .topLeading) {
                if viewModel.notesText.isEmpty {
                    Text("Add workout notes...")
                        .font(.system(size: 15))
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }

                TextEditor(text: $viewModel.notesText)
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .background(Color.bgCard)
            .cornerRadius(10)
        }
    }

    // MARK: - Exercise Picker

    private var exercisePickerSheet: some View {
        NavigationStack {
            ExerciseListView(
                mode: .addToWorkout,
                onExercisesSelected: { selectedIds in
                    Task {
                        await viewModel.addExercises(selectedIds)
                        viewModel.showAddExerciseSheet = false
                    }
                },
                services: services
            )
        }
    }

    // MARK: - Empty State

    private var emptyExerciseState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "dumbbell")
                .font(.system(size: 48))
                .foregroundColor(.textTertiary)

            Text("No exercises")
                .font(.headline)
                .foregroundColor(.textSecondary)

            Text("Add exercises to start editing")
                .font(.subheadline)
                .foregroundColor(.textTertiary)

            Button {
                viewModel.showAddExerciseSheet = true
            } label: {
                Text("Add Exercises")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Color.accent)
                    .cornerRadius(10)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
