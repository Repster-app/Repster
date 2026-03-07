// ActiveWorkoutViewModelContract.swift
// Contract for ActiveWorkoutViewModel — feature 006
//
// This is a planning artifact, not compilable code.
// It defines the public interface the ViewModel exposes to Views.

import Foundation

// MARK: - ViewModel Contract

/// @Observable @MainActor final class
/// Dependencies: WorkoutServiceProtocol, SetServiceProtocol, ExerciseServiceProtocol
protocol ActiveWorkoutViewModelContract {

    // MARK: - Published State (read by Views)

    /// Current active workout (nil if none)
    var workout: Workout? { get }

    /// Ordered list of exercises in this workout
    var exercises: [Exercise] { get }

    /// Index of the currently selected exercise tab
    var selectedExerciseIndex: Int { get set }

    /// Sets grouped by exerciseId
    var setsByExercise: [UUID: [WorkoutSet]] { get }

    /// Current exercise (derived from selectedExerciseIndex)
    var currentExercise: Exercise? { get }

    /// Sets for the current exercise (derived)
    var currentSets: [WorkoutSet] { get }

    /// Loading state
    var isLoading: Bool { get }

    /// Rest timer state
    var restTimer: RestTimerState { get }

    /// Elapsed workout time in seconds
    var elapsedTime: TimeInterval { get }

    /// Controls for sheet presentation
    var showFinishSheet: Bool { get set }
    var showAddExerciseSheet: Bool { get set }

    // MARK: - Lifecycle

    /// Load or resume active workout. Called on appear.
    func loadActiveWorkout() async

    // MARK: - Set Operations

    /// Complete a set with the given input values. Triggers save pipeline + rest timer.
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

    /// Delete a set. Triggers PR/stats recalculation.
    func deleteSet(_ set: WorkoutSet) async

    /// Change the set type (e.g., working → warmup).
    func changeSetType(_ set: WorkoutSet, to type: SetType) async

    // MARK: - Exercise Operations

    /// Add exercises to the workout (from picker sheet).
    func addExercises(_ exerciseIds: [UUID]) async

    /// Remove an exercise and all its sets from the workout.
    func removeExercise(at index: Int) async

    /// Reorder exercises via drag gesture on tab strip.
    func reorderExercises(from source: IndexSet, to destination: Int)

    // MARK: - Rest Timer

    /// Manually start or restart the rest timer.
    func startRestTimer(duration: Int)

    /// Add seconds to the running timer (+30s button).
    func addTime(_ seconds: Int)

    /// Dismiss the rest timer.
    func dismissTimer()

    // MARK: - Finish Workout

    /// Finish the workout with optional notes and RPE. Navigates away on success.
    func finishWorkout(notes: String?, perceivedEffort: Double?) async
}

// MARK: - Rest Timer State

enum RestTimerState: Equatable {
    /// No timer running
    case idle
    /// Timer counting down: remaining seconds and total seconds
    case running(remaining: Int, total: Int)
    /// Timer has reached zero
    case finished
}

// MARK: - Summary Data (for WorkoutSummarySheet)

struct WorkoutSummaryData {
    let date: Date
    let duration: TimeInterval
    let totalSets: Int
    let totalVolume: Double
    let exerciseSummaries: [ExerciseSummary]
    let prsHit: Int
}

struct ExerciseSummary {
    let exerciseName: String
    let setCount: Int
    let bestWeight: Double?
    let bestReps: Int?
    let hadPR: Bool
}
