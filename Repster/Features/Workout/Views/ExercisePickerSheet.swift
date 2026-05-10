// ExercisePickerSheet.swift
// Temporary exercise picker for adding exercises to the active workout.
// Spec: FR-007 (Add exercises to workout)
// Contract: WP05 T025
//
// This is a STUB — feature 007 will replace it with the full exercise browser.
// Fetches all exercises via ExerciseService, supports search and multi-select.

import SwiftUI

/// Sheet for picking exercises to add to the active workout.
///
/// Fetches all exercises from ExerciseService, displays in a searchable list,
/// and supports multi-select. "Add" button calls ViewModel.addExercises().
///
/// This is a temporary stub until the full exercise browser (Feature 007) is built.
struct ExercisePickerSheet: View {

    // MARK: - Dependencies

    /// The ViewModel to add exercises to.
    var viewModel: ActiveWorkoutViewModel

    /// The exercise service for fetching available exercises.
    let exerciseService: any ExerciseServiceProtocol

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// All available exercises fetched from the service.
    @State private var exercises: [Exercise] = []

    /// IDs of selected exercises for multi-select.
    @State private var selectedIds: Set<UUID> = []

    /// Search text for filtering exercises by name.
    @State private var searchText = ""

    /// Whether exercises are currently loading.
    @State private var isLoading = true

    // MARK: - Computed

    /// Exercises filtered by search text (case-insensitive).
    private var filteredExercises: [Exercise] {
        if searchText.isEmpty { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if exercises.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell")
                            .font(.system(size: 40))
                            .foregroundColor(.textTertiary)
                        Text("No exercises available")
                            .font(.headline)
                            .foregroundColor(.textSecondary)
                        Text("Create exercises in the exercise library first.")
                            .font(.subheadline)
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredExercises, id: \.id) { exercise in
                        exerciseRow(exercise)
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search exercises")
                }
            }
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedIds.count))") {
                        Task {
                            await viewModel.addExercises(Array(selectedIds))
                            dismiss()
                        }
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
        .task {
            await loadExercises()
        }
    }

    // MARK: - Subviews

    /// A single exercise row with name and checkmark indicator.
    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .foregroundColor(.textPrimary)
                Text(exercise.trackingType.rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).trimmingCharacters(in: .whitespaces).capitalized)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            if selectedIds.contains(exercise.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accent)
                    .font(.system(size: 22))
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.textTertiary)
                    .font(.system(size: 22))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedIds.contains(exercise.id) {
                selectedIds.remove(exercise.id)
            } else {
                selectedIds.insert(exercise.id)
            }
        }
    }

    // MARK: - Data Loading

    /// Fetch all exercises from the service.
    private func loadExercises() async {
        isLoading = true
        defer { isLoading = false }
        do {
            exercises = try await exerciseService.fetchAllExercises()
        } catch {
            dbg("[ExercisePickerSheet] Failed to fetch exercises: \(error)")
        }
    }
}
