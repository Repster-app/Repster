// ExerciseListViewModel.swift
// Central ViewModel for the Exercise List screen.
// Manages loading, search, filter, sort, and selection state.
// Spec: FR-004 (exercise list), FR-007 (search/filter)
// Contract: view-contracts.md ExerciseListViewModel

import SwiftUI

@Observable @MainActor
final class ExerciseListViewModel {

    // MARK: - Dependencies

    private let exerciseService: any ExerciseServiceProtocol
    private let statsService: any StatsServiceProtocol

    // MARK: - Raw Data

    private(set) var allExercises: [Exercise] = []

    // MARK: - Display State

    var exercises: [Exercise] = []
    var allExerciseStats: [UUID: ExerciseStats] = [:]
    var isLoading: Bool = false
    var availableMuscleGroups: [String] = []

    var searchText: String = "" {
        didSet { applyFiltersAndSort() }
    }

    var selectedMuscleFilters: Set<String> = [] {
        didSet { applyFiltersAndSort() }
    }

    var sortOrder: ExerciseListSortOrder = .alphabetical {
        didSet { applyFiltersAndSort() }
    }

    /// Ordered array preserving the user's selection order.
    /// Used instead of Set<UUID> so that template exercises respect the pick order.
    var selectedExerciseIds: [UUID] = []

    // MARK: - Mode

    let mode: ExerciseListMode

    // MARK: - Computed

    var selectedCount: Int { selectedExerciseIds.count }
    var hasSelection: Bool { !selectedExerciseIds.isEmpty }

    // MARK: - Init

    init(
        mode: ExerciseListMode,
        exerciseService: any ExerciseServiceProtocol,
        statsService: any StatsServiceProtocol
    ) {
        self.mode = mode
        self.exerciseService = exerciseService
        self.statsService = statsService
    }

    // MARK: - Actions

    func loadExercises() async {
        isLoading = true
        defer { isLoading = false }

        do {
            allExercises = try await exerciseService.fetchAllExercises()
            allExerciseStats = try await statsService.fetchAllStats()

            availableMuscleGroups = ExerciseMuscleGroupCatalog.orderedValues(
                from: allExercises.compactMap(\.primaryMuscle)
            )

            applyFiltersAndSort()
        } catch {
            exercises = []
        }
    }

    func toggleSelection(_ exerciseId: UUID) {
        if let index = selectedExerciseIds.firstIndex(of: exerciseId) {
            selectedExerciseIds.remove(at: index)
        } else {
            selectedExerciseIds.append(exerciseId)
        }
    }

    func clearSelection() {
        selectedExerciseIds.removeAll()
    }

    func deleteExercise(_ exerciseId: UUID) async {
        do {
            try await exerciseService.deleteExercise(exerciseId)
            allExercises.removeAll { $0.id == exerciseId }
            allExerciseStats.removeValue(forKey: exerciseId)
            selectedExerciseIds.removeAll { $0 == exerciseId }
            applyFiltersAndSort()
        } catch {
            // Deletion failed — state unchanged
        }
    }

    // MARK: - Filtering & Sorting

    private func applyFiltersAndSort() {
        var result = allExercises

        // Search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Muscle filter (case-insensitive: filters are stored lowercase)
        if !selectedMuscleFilters.isEmpty {
            result = result.filter {
                guard let muscle = ExercisePrimaryGroup.normalizedValue($0.primaryMuscle) else { return false }
                return selectedMuscleFilters.contains(muscle)
            }
        }

        // Sort
        switch sortOrder {
        case .alphabetical:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostRecent:
            result.sort { a, b in
                let dateA = allExerciseStats[a.id]?.lastPerformedDate
                let dateB = allExerciseStats[b.id]?.lastPerformedDate
                switch (dateA, dateB) {
                case (.some(let da), .some(let db)): return da > db
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.name < b.name
                }
            }
        case .mostUsed:
            result.sort { a, b in
                let countA = allExerciseStats[a.id]?.totalWorkouts ?? 0
                let countB = allExerciseStats[b.id]?.totalWorkouts ?? 0
                if countA != countB { return countA > countB }
                return a.name < b.name
            }
        }

        exercises = result
    }
}
