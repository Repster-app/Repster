// ExerciseServiceProtocol.swift
// Contract for Exercise CRUD and metadata mutability enforcement
// Spec: FR-005, FR-006, FR-007, FR-011, FR-012
// Source: specdoc S5, S5.6; AGENT_RULES S3.5, S6

import Foundation

enum ExerciseServiceError: Error {
    case exerciseNotFound(UUID)
    case trackingTypeImmutable(exerciseId: UUID)
}

/// ExerciseService owns exercise lifecycle and metadata rules.
///
/// Responsibilities (per AGENT_RULES S6):
/// - Exercise CRUD
/// - Name search for autocomplete (FR-007)
/// - Enforce trackingType immutability once sets exist (FR-005, specdoc S5.6)
/// - Trigger stats/PR rebuild when calculation-critical fields change (FR-006)
/// - Cascade deletion: bulk delete sets, PRs, stats for exercise (FR-011)
///
/// ExerciseService does NOT:
/// - Store analytics (that's ExerciseStats)
/// - Handle set logic (that's SetService)
/// - Access ModelContext directly (uses repositories)
///
/// Metadata mutability rules (specdoc S5.6):
///   Immutable (sets exist): trackingType
///   Rebuild required: bodyweightFactor, unilateral, bilateralLoadFactor, equipmentType
///   Low-risk mutable: name, primaryMuscle, secondaryMuscles, movementPattern, defaultRestTime, weightIncrement
protocol ExerciseServiceProtocol: Sendable {

    // MARK: - CRUD

    /// Create a new exercise.
    ///
    /// - Parameter exercise: The Exercise to persist.
    func createExercise(_ exercise: Exercise) async throws

    /// Update an existing exercise with metadata mutability enforcement.
    ///
    /// 1. If logged set data exists AND trackingType changed -> throw ExerciseServiceError.trackingTypeImmutable
    /// 2. Detect if rebuild-required fields changed
    /// 3. Persist the update
    /// 4. If rebuild needed -> trigger PR + stats rebuild
    ///
    /// Rebuild-required fields (specdoc S5.6):
    /// bodyweightFactor, unilateral, bilateralLoadFactor, equipmentType
    ///
    /// IMPORTANT: Rebuild uses existing stored effectiveWeight values on sets.
    /// Historical effectiveWeight is never recalculated retroactively (specdoc S5.4).
    ///
    /// - Parameter exercise: The Exercise with updated values.
    /// - Parameter originalTrackingType: The trackingType before edit, for immutability check.
    func updateExercise(_ exercise: Exercise, originalTrackingType: TrackingType) async throws

    /// Fetch an exercise by ID.
    func fetchExercise(_ exerciseId: UUID) async throws -> Exercise?

    /// Fetch all exercises, ordered by name.
    func fetchAllExercises() async throws -> [Exercise]

    // MARK: - Search (FR-007)

    /// Search exercises by name (case-insensitive contains).
    /// Used for autocomplete in exercise picker.
    ///
    /// - Parameter query: The search string.
    /// - Returns: Matching exercises, ordered by name.
    func searchExercises(name query: String) async throws -> [Exercise]

    // MARK: - Deletion (FR-011)

    /// Delete an exercise with full cascade.
    ///
    /// 1. Bulk delete all sets for this exercise
    /// 2. Delete ExerciseStats (if exists)
    /// 3. Delete all PerformanceRecords for this exercise
    /// 4. Delete the exercise
    ///
    /// No rebuild needed — everything related to this exercise is removed.
    ///
    /// - Parameter exerciseId: The exercise to delete.
    func deleteExercise(_ exerciseId: UUID) async throws

    // MARK: - Queries

    /// Check if an exercise has associated sets.
    /// Used by UI to determine if trackingType field should be editable.
    ///
    /// - Parameter exerciseId: The exercise to check.
    /// - Returns: true if any WorkoutSets reference this exercise.
    func exerciseHasSets(_ exerciseId: UUID) async throws -> Bool

    /// Check if an exercise has logged set data.
    /// Used by UI/service to lock trackingType only after real values exist.
    func exerciseHasLoggedSetData(_ exerciseId: UUID) async throws -> Bool
}
