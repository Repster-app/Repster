// ExerciseListView.swift
// Main exercise list screen with dual mode support (browse / addToWorkout).
// Browse mode: single-tap to start workout with that exercise; trailing info opens detail.
// addToWorkout mode: multi-select, then "Add (N)" button.
// Composes: search bar, MuscleFilterStrip, SortOptionMenu, ExerciseCardView list.
// Spec: FR-001–FR-005, User Stories 1 & 2
// Feature: 007-exercise-list-and-detail WP03, WP07 T031/T033

import SwiftUI

struct ExerciseListView: View {

    // MARK: - Config

    let mode: ExerciseListMode
    var onExercisesSelected: (([UUID]) -> Void)?

    // MARK: - State

    @State private var viewModel: ExerciseListViewModel
    @State private var showCreateSheet = false
    @State private var showAssignMuscleGroups = false
    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    private var unassignedMuscleCount: Int {
        viewModel.allExercises.reduce(into: 0) { count, exercise in
            let normalized = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle)
            if normalized == nil || normalized?.isEmpty == true {
                count += 1
            }
        }
    }

    // MARK: - Init

    init(
        mode: ExerciseListMode,
        onExercisesSelected: (([UUID]) -> Void)? = nil,
        services: ServiceContainer
    ) {
        self.mode = mode
        self.onExercisesSelected = onExercisesSelected
        self._viewModel = State(initialValue: ExerciseListViewModel(
            mode: mode,
            exerciseService: services.exerciseService,
            statsService: services.statsService
        ))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if mode == .manage && unassignedMuscleCount > 0 {
                unassignedMuscleBanner
            }

            // Filter strip + sort header
            filterHeader

            // Content
            if viewModel.isLoading {
                loadingState
            } else if viewModel.allExercises.isEmpty {
                emptyState
            } else if viewModel.exercises.isEmpty {
                noResultsState
            } else {
                exerciseList
            }
        }
        .background(Color.bg)
        .searchable(text: $viewModel.searchText, prompt: "Search exercises")
        .navigationTitle(mode == .manage ? "Exercise Library" : "Exercises")
        .toolbar {
            if mode != .manage {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .addToWorkout ? "Cancel" : "Close") { dismiss() }
                }
            }
            // "Add New" button for creating exercises (T033)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add New") { showCreateSheet = true }
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Only show action button for addToWorkout mode (multi-select)
            if mode == .addToWorkout {
                actionButton
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateEditExerciseSheet(
                exercise: nil,
                services: services,
                onSave: {
                    Task {
                        await viewModel.loadExercises()
                    }
                }
            )
        }
        .sheet(isPresented: $showAssignMuscleGroups, onDismiss: {
            Task { await viewModel.loadExercises() }
        }) {
            AssignMuscleGroupsView(exerciseService: services.exerciseService)
        }
        .task {
            await viewModel.loadExercises()
        }
    }

    // MARK: - Unassigned Muscle Banner

    private var unassignedMuscleBanner: some View {
        Button {
            showAssignMuscleGroups = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unassignedMuscleCount == 1
                         ? "1 exercise missing muscle group"
                         : "\(unassignedMuscleCount) exercises missing muscle group")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Tap to assign")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Header

    private var filterHeader: some View {
        VStack(spacing: 8) {
            if !viewModel.availableMuscleGroups.isEmpty {
                MuscleFilterStrip(
                    muscleGroups: viewModel.availableMuscleGroups,
                    selectedFilters: $viewModel.selectedMuscleFilters
                )
            }
            HStack {
                SortOptionMenu(sortOrder: $viewModel.sortOrder)
                Spacer()
                Text("\(viewModel.exercises.count) exercises")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(viewModel.exercises) { exercise in
                    exerciseCardRow(exercise)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, mode == .addToWorkout && viewModel.hasSelection ? 80 : 0)
        }
    }

    // MARK: - Card Row (Dual Mode)

    @ViewBuilder
    private func exerciseCardRow(_ exercise: Exercise) -> some View {
        let stats = viewModel.allExerciseStats[exercise.id]
        let isSelected = viewModel.selectedExerciseIds.contains(exercise.id)

        switch mode {
        case .browse:
            HStack(spacing: 8) {
                Button {
                    onExercisesSelected?([exercise.id])
                } label: {
                    ExerciseCardView(
                        exercise: exercise,
                        stats: stats,
                        isSelected: false,
                        mode: mode
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ExerciseDetailView(exerciseId: exercise.id, services: services)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Color.bgCard)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        case .manage:
            NavigationLink {
                ExerciseDetailView(exerciseId: exercise.id, services: services)
            } label: {
                ExerciseCardView(
                    exercise: exercise,
                    stats: stats,
                    isSelected: false,
                    mode: mode
                )
            }
            .buttonStyle(.plain)
        case .addToWorkout:
            Button {
                viewModel.toggleSelection(exercise.id)
            } label: {
                ExerciseCardView(
                    exercise: exercise,
                    stats: stats,
                    isSelected: isSelected,
                    mode: mode,
                    onSelectionToggle: {
                        viewModel.toggleSelection(exercise.id)
                    }
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Action Button (addToWorkout mode only)

    @ViewBuilder
    private var actionButton: some View {
        if viewModel.hasSelection {
            Button {
                onExercisesSelected?(viewModel.selectedExerciseIds)
            } label: {
                Text("Add (\(viewModel.selectedCount))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accent)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dumbbell")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No Exercises Yet")
                .font(.title3.bold())
                .foregroundStyle(Color.textPrimary)
            Text("Create your first exercise to get started")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)

            Button {
                showCreateSheet = true
            } label: {
                Text("Create Exercise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Color.accent)
                    .cornerRadius(10)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - No Results State

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("No exercises found")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
            if !viewModel.selectedMuscleFilters.isEmpty {
                Button("Clear Filters") {
                    viewModel.selectedMuscleFilters.removeAll()
                }
                .foregroundStyle(Color.accent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
