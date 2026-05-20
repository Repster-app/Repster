// ExerciseDetailView.swift
// Main exercise detail screen with History/PRs/Charts tab picker.
// Reusable component: takes exerciseId, creates own ViewModel.
// Spec: FR-006, FR-007, SC-002, SC-004, User Story 3
// Contract: view-contracts.md ExerciseDetailView
// Feature: 007-exercise-list-and-detail WP04 T017, WP07 T031/T034

import SwiftUI

struct ExerciseDetailView: View {

    // MARK: - Config

    let exerciseId: UUID

    // MARK: - State

    @State private var viewModel: ExerciseDetailViewModel
    @State private var selectedTab: ExerciseDetailTab = .history
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    init(exerciseId: UUID, services: ServiceContainer) {
        self.exerciseId = exerciseId
        self._viewModel = State(initialValue: ExerciseDetailViewModel(
            exerciseId: exerciseId,
            exerciseService: services.exerciseService,
            prService: services.prService,
            setService: services.setService,
            statsService: services.statsService
        ))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                loadingState
            } else if let exercise = viewModel.exercise {
                exerciseHeader(exercise)

                tabPicker

                tabContent
            } else {
                notFoundState
            }
        }
        .background(Color.bg)
        .navigationTitle(viewModel.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
        // Edit/Delete toolbar menu (T034)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit Exercise", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
            }
        }
        // Edit sheet (T034)
        .sheet(isPresented: $showEditSheet) {
            CreateEditExerciseSheet(
                exercise: viewModel.exercise,
                services: services,
                onSave: {
                    Task {
                        await viewModel.loadExercise()
                    }
                }
            )
        }
        // Delete confirmation (T034)
        .confirmationDialog(
            "Delete Exercise",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                dismiss()
                Task {
                    try? await viewModel.deleteExercise()
                }
            }
        } message: {
            Text("This will permanently delete this exercise and all its recorded sets, PRs, and stats. This cannot be undone.")
        }
        .task {
            await viewModel.loadExercise()
            await viewModel.loadHistory()
        }
        .onChange(of: selectedTab) { _, newTab in
            Task {
                switch newTab {
                case .history: await viewModel.loadHistory()
                case .prs: await viewModel.loadPRs()
                case .charts: break // Charts are self-contained via EmbeddedExerciseChartView
                }
            }
        }
    }

    // MARK: - Exercise Header

    private func exerciseHeader(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let muscle = exercise.primaryMuscle {
                        Text(ExercisePrimaryGroup.displayName(for: muscle))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.accent)
                    }
                    Text(exercise.equipmentType.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
            }

            if let stats = viewModel.stats {
                HStack(spacing: 16) {
                    statItem(label: "Workouts", value: "\(stats.totalWorkouts)")
                    if stats.bestE1RM > 0 {
                        statItem(label: "Best e1RM", value: formatWeight(stats.bestE1RM))
                    }
                    if let lastDate = stats.lastPerformedDate {
                        statItem(label: "Last", value: formatRelativeDate(lastDate))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.5)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(ExerciseDetailTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .history:
            ExerciseHistoryView(
                historyWorkouts: viewModel.historyWorkouts,
                exercise: viewModel.exercise,
                unitPreference: services.unitPreference
            )
        case .prs:
            ExercisePRsView(
                prTable: viewModel.prTable,
                unitPreference: services.unitPreference,
                isPerSide: viewModel.exercise?.unilateral == true && viewModel.exercise?.supportsUnilateralLogging == true
            )
        case .charts:
            if let exercise = viewModel.exercise {
                EmbeddedExerciseChartView(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCategory: exercise.primaryMuscle ?? "",
                    chartDataService: services.chartDataService,
                    exerciseService: services.exerciseService
                )
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var notFoundState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("Exercise not found")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Formatting

    private func formatWeight(_ weight: Double) -> String {
        UnitConversion.formatWeightLabel(weight, unitPreference: services.unitPreference)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        if days < 30 { return "\(days / 7)w ago" }
        return "\(days / 30)mo ago"
    }
}
