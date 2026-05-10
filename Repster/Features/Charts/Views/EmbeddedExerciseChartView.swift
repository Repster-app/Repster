// EmbeddedExerciseChartView.swift
// Reusable wrapper that embeds ExercisesTabView for a single pre-selected exercise.
// Used in ActiveWorkoutView (Charts sub-tab) and ExerciseDetailView (Charts tab).
// Replaces the old ExerciseChartsView with the full-featured Charts tab experience.

import SwiftUI

/// Embeds the Exercises tab chart (metric dropdown, time pills, multi-line chart,
/// trend line, data navigator) for a single pre-determined exercise.
///
/// Owns its own `ExercisesTabViewModel` in embedded mode — the exercise selector
/// button is hidden since the exercise is predetermined by the context.
///
/// Usage:
/// ```
/// EmbeddedExerciseChartView(
///     exerciseId: exercise.id,
///     exerciseName: exercise.name,
///     exerciseCategory: exercise.primaryMuscle ?? "",
///     chartDataService: services.chartDataService,
///     exerciseService: services.exerciseService
/// )
/// ```
struct EmbeddedExerciseChartView: View {

    // MARK: - Config

    let exerciseId: UUID
    let exerciseName: String
    let exerciseCategory: String
    let chartDataService: any ChartDataServiceProtocol
    let exerciseService: any ExerciseServiceProtocol

    // MARK: - State

    @State private var viewModel: ExercisesTabViewModel?
    @Environment(ServiceContainer.self) private var services

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel {
                ScrollView {
                    ExercisesTabView(viewModel: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = ExercisesTabViewModel(
                    chartDataService: chartDataService,
                    exerciseService: exerciseService,
                    preselectedExercise: (
                        id: exerciseId,
                        name: exerciseName,
                        category: exerciseCategory.isEmpty
                            ? ""
                            : ExercisePrimaryGroup.displayName(for: exerciseCategory)
                    )
                )
                vm.unitPreference = services.unitPreference
                viewModel = vm
                Task { await vm.loadData() }
            }
        }
        .onChange(of: services.unitPreference) { _, newValue in
            guard let viewModel else { return }
            viewModel.unitPreference = newValue
            Task { await viewModel.loadData() }
        }
    }
}
