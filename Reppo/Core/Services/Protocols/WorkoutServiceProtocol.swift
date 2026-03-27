// WorkoutServiceProtocol.swift
// Contract for Workout lifecycle management
// Spec: FR-001, FR-002, FR-003, FR-004, FR-010
// Source: specdoc S3, S6.2; AGENT_RULES S6, S7.3

import Foundation

enum WorkoutServiceError: Error {
    case workoutNotFound(UUID)
    case workoutAlreadyCompleted(UUID)
}

/// WorkoutService owns workout lifecycle: create, finish, delete, active detection.
///
/// Responsibilities (per AGENT_RULES S6):
/// - Create/edit/delete workouts
/// - Manage active workout state (status field)
/// - Enforce single active workout constraint (FR-004)
/// - Cascade deletion: bulk delete sets, rebuild PRs/stats per affected exercise (FR-010)
///
/// WorkoutService does NOT:
/// - Handle individual set logic (that's SetService)
/// - Compute effectiveWeight, PRs, or stats directly
/// - Access ModelContext directly (uses repositories)
///
/// Cascade deletion strategy (per specdoc S10, AGENT_RULES S6):
///   1. Fetch affected exerciseIds
///   2. Bulk delete sets via SetRepository
///   3. Delete workout via WorkoutRepository
///   4. PRService.rebuild() + StatsService.rebuild() per affected exercise
protocol WorkoutServiceProtocol: Sendable {

    // MARK: - Workout Lifecycle (FR-001, FR-003, FR-004)

    /// Start a new workout or return the existing active one.
    ///
    /// If a workout with status == .inProgress already exists, returns it (FR-004).
    /// Otherwise creates a new Workout with status = .inProgress, startTime = now, date = today.
    ///
    /// - Returns: The active Workout (existing or newly created).
    func startWorkout() async throws -> Workout

    /// Finish an active workout.
    ///
    /// Sets status = .completed, endTime = now, duration = endTime - startTime (seconds)
    /// unless a pause-aware override is provided.
    /// Optionally stores user-provided notes and perceived effort (RPE).
    /// Throws if workout not found or already completed.
    ///
    /// - Parameters:
    ///   - workoutId: The workout to finish.
    ///   - title: Optional user-provided title (e.g. "Push Day"). If nil, displayTitle auto-generates.
    ///   - notes: Optional free-text notes entered on the summary sheet.
    ///   - perceivedEffort: Optional RPE value (1–10) from the summary sheet.
    ///   - durationSecondsOverride: Optional explicit duration to persist when the active
    ///     session clock excludes paused time.
    func finishWorkout(
        _ workoutId: UUID,
        title: String?,
        notes: String?,
        perceivedEffort: Double?,
        durationSecondsOverride: Int?
    ) async throws

    // MARK: - Active Workout (FR-003, AGENT_RULES S7.3)

    /// Fetch the currently active workout (status == .inProgress), if any.
    ///
    /// Called at app launch to detect and resume an active workout.
    /// Returns nil if no workout is in progress.
    func getActiveWorkout() async throws -> Workout?

    // MARK: - CRUD

    /// Fetch a workout by ID.
    func fetchWorkout(_ workoutId: UUID) async throws -> Workout?

    /// Fetch workouts within a date range, ordered by date DESC.
    func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout]

    /// Fetch all workouts with optional pagination.
    func fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout]

    // MARK: - Metadata Update (FR-009)

    /// Update metadata (notes, perceived effort) on a completed workout.
    ///
    /// Updates notes, perceivedEffort, and updatedAt. Does not modify status, date,
    /// startTime, endTime, or duration.
    ///
    /// - Parameters:
    ///   - workoutId: The workout to update.
    ///   - notes: Updated free-text notes (nil to clear).
    ///   - perceivedEffort: Updated RPE value (nil to clear).
    func updateWorkoutMetadata(_ workoutId: UUID, notes: String?, perceivedEffort: Double?) async throws

    /// Update workout-scoped PR / Smart Suggest exclusions.
    ///
    /// - Parameters:
    ///   - workoutId: Workout to update.
    ///   - excludeWorkout: When true, the entire workout is ignored for PRs and Smart Suggestions.
    ///   - excludedExerciseIds: Exercise IDs to ignore within this workout only.
    func updateProgressionExclusions(
        _ workoutId: UUID,
        excludeWorkout: Bool,
        excludedExerciseIds: Set<UUID>
    ) async throws

    // MARK: - Deletion (FR-010)

    /// Delete a workout with full cascade.
    ///
    /// 1. Fetch unique exerciseIds from workout's sets
    /// 2. Bulk delete all sets in the workout
    /// 3. Delete the workout
    /// 4. Rebuild PRs + stats for each affected exercise
    ///
    /// - Parameter workoutId: The workout to delete.
    func deleteWorkout(_ workoutId: UUID) async throws
}
