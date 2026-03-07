// ExerciseDetailViewModel.swift
// Central ViewModel for Exercise Detail screen with lazy-loaded data per tab.
// Spec: FR-006, FR-007, SC-002, SC-004
// Contract: view-contracts.md ExerciseDetailViewModel
// Feature: 007-exercise-list-and-detail WP04 T016

import Foundation

@Observable @MainActor
final class ExerciseDetailViewModel {

    // MARK: - Dependencies

    private let exerciseId: UUID
    private let exerciseService: any ExerciseServiceProtocol
    private let prService: any PRServiceProtocol
    private let setService: any SetServiceProtocol
    private let statsService: any StatsServiceProtocol

    // MARK: - Published State

    var exercise: Exercise?
    var stats: ExerciseStats?
    var prTable: [PRTableEntry] = []
    var historyWorkouts: [WorkoutHistoryGroup] = []
    var isLoading: Bool = false
    var hasSets: Bool = false

    // MARK: - Load Tracking

    private var historyLoaded = false
    private var prsLoaded = false

    // MARK: - Init

    init(
        exerciseId: UUID,
        exerciseService: any ExerciseServiceProtocol,
        prService: any PRServiceProtocol,
        setService: any SetServiceProtocol,
        statsService: any StatsServiceProtocol
    ) {
        self.exerciseId = exerciseId
        self.exerciseService = exerciseService
        self.prService = prService
        self.setService = setService
        self.statsService = statsService
    }

    // MARK: - Load Exercise (on appear)

    func loadExercise() async {
        isLoading = true
        exercise = try? await exerciseService.fetchExercise(exerciseId)
        stats = try? await statsService.fetchStats(for: exerciseId)
        hasSets = (try? await exerciseService.exerciseHasSets(exerciseId)) ?? false
        isLoading = false
    }

    // MARK: - Lazy Tab Loading

    func loadHistory() async {
        guard !historyLoaded else { return }
        let sets = (try? await setService.fetchSets(for: exerciseId, limit: nil)) ?? []
        let grouped = Dictionary(grouping: sets) { $0.workoutId }
        historyWorkouts = grouped.map { workoutId, workoutSets in
            WorkoutHistoryGroup(
                id: workoutId,
                date: workoutSets.first?.date ?? Date(),
                sets: workoutSets.sorted { $0.orderInExercise < $1.orderInExercise }
            )
        }
        .sorted { $0.date > $1.date }
        historyLoaded = true
    }

    func loadPRs() async {
        guard !prsLoaded else { return }
        prTable = (try? await prService.fetchPRTable(for: exerciseId)) ?? []
        prsLoaded = true
    }

    // MARK: - Actions

    func deleteExercise() async throws {
        try await exerciseService.deleteExercise(exerciseId)
    }
}
