// SetTableDataSource.swift
// Shared protocol enabling SetTableView and ExerciseTabStripView to work with
// both ActiveWorkoutViewModel and EditWorkoutViewModel.
// Spec: 015-edit-historic-workout, contracts/view-contracts.md

import Foundation

/// Draft-edit field identity for set table rows.
enum SetDraftField: Sendable {
    case weight
    case reps
    case duration
    case distance
    case rir
}

struct SetCompletionInput: Sendable {
    let weight: Double?
    let reps: Int?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let rir: Double?
    let leftReps: Int?
    let rightReps: Int?
    let leftRIR: Double?
    let rightRIR: Double?

    init(
        weight: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rir: Double? = nil,
        leftReps: Int? = nil,
        rightReps: Int? = nil,
        leftRIR: Double? = nil,
        rightRIR: Double? = nil
    ) {
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rir = rir
        self.leftReps = leftReps
        self.rightReps = rightReps
        self.leftRIR = leftRIR
        self.rightRIR = rightRIR
    }
}

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
    func completeSet(_ set: WorkoutSet, input: SetCompletionInput) async

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
    /// Called when the user edits a set-table field.
    func markSetDirty(_ set: WorkoutSet, field: SetDraftField)

    /// Update the note on a set. Called from the context menu note editor.
    func updateSetNote(_ set: WorkoutSet, note: String?) async

    // MARK: - Exercise Actions

    /// Reorder exercises by moving from source indices to destination.
    func reorderExercises(from source: IndexSet, to destination: Int)

    /// Remove the exercise at the given index and delete all its sets.
    func removeExercise(at index: Int) async

    /// Sets grouped by exercise ID for checking completion status.
    var setsByExercise: [UUID: [WorkoutSet]] { get }

    /// Optional row-addressable Smart Suggestion state for a specific pending set.
    /// Returns nil when suggestions are unavailable or the row has no pending state.
    func suggestionState(for setId: UUID) -> SetSuggestionState?

    /// Optional row-addressable suggested weight for a specific pending set.
    /// Returns nil when suggestions are unavailable or no mapping exists.
    func suggestedWeight(for setId: UUID) -> Double?
}

extension SetTableDataSource {
    func suggestionState(for setId: UUID) -> SetSuggestionState? { nil }
    func suggestedWeight(for setId: UUID) -> Double? {
        suggestionState(for: setId)?.suggestion?.suggestedWeight
    }
}
