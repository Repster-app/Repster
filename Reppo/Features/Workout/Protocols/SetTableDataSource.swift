// SetTableDataSource.swift
// Shared protocol enabling SetTableView and ExerciseTabStripView to work with
// both ActiveWorkoutViewModel and EditWorkoutViewModel.
// Spec: 015-edit-historic-workout, contracts/view-contracts.md

import Foundation

/// Data source protocol for set table and exercise tab strip components.
///
/// Conforming types provide exercise/set state and handle user actions
/// (complete set, add set, delete set, reorder exercises, etc.).
/// Both `ActiveWorkoutViewModel` and `EditWorkoutViewModel` conform.
@MainActor
protocol SetTableDataSource: AnyObject, Observable {

    // MARK: - State

    /// All exercises in the current workout, ordered by display position.
    var exercises: [Exercise] { get }

    /// Index of the currently selected exercise in the tab strip.
    var selectedExerciseIndex: Int { get set }

    // MARK: - Computed

    /// The currently selected exercise, or nil if no exercises exist.
    var currentExercise: Exercise? { get }

    /// Sets for the currently selected exercise, ordered by orderInExercise.
    var currentSets: [WorkoutSet] { get }

    // MARK: - Set Actions

    /// Complete or update a set with the given values.
    ///
    /// For new sets: persists via SetService.save().
    /// For existing sets: persists via SetService.edit().
    func completeSet(
        _ set: WorkoutSet,
        weight: Double?,
        reps: Int?,
        durationSeconds: Int?,
        distanceMeters: Double?
    ) async

    /// Add a new working set for the given exercise.
    func addSet(for exerciseId: UUID) async

    /// Add a new warmup set for the given exercise.
    func addWarmupSet(for exerciseId: UUID) async

    /// Uncomplete a set, flipping it back to incomplete state.
    func uncompleteSet(_ set: WorkoutSet) async

    /// Delete a set from the workout.
    func deleteSet(_ set: WorkoutSet) async

    /// Change a set's type (e.g., warmup -> working -> dropset).
    func changeSetType(_ set: WorkoutSet, to type: SetType) async

    /// Mark a set as having unsaved text field changes.
    /// Called when the user edits weight/reps/duration/distance text.
    func markSetDirty(_ set: WorkoutSet)

    /// Update the note on a set. Called from the context menu note editor.
    func updateSetNote(_ set: WorkoutSet, note: String?) async

    // MARK: - Exercise Actions

    /// Reorder exercises by moving from source indices to destination.
    func reorderExercises(from source: IndexSet, to destination: Int)

    /// Remove the exercise at the given index and delete all its sets.
    func removeExercise(at index: Int) async

    /// Sets grouped by exercise ID for checking completion status.
    var setsByExercise: [UUID: [WorkoutSet]] { get }
}
