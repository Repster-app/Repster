import Foundation

/// Repository protocol for FatigueObservation entity.
/// Used by FatigueLearningService to persist and query prediction error data.
protocol FatigueObservationRepositoryProtocol: Sendable {

    /// Insert a new observation.
    func save(_ observation: FatigueObservation) async throws

    /// Fetch all observations for a specific workout.
    func fetchObservations(for workoutId: UUID) async throws -> [FatigueObservation]

    /// Fetch all observations for a specific exercise, ordered by createdAt DESC.
    func fetchObservations(exerciseId: UUID, limit: Int?) async throws -> [FatigueObservation]

    /// Count the number of distinct workouts with observations for an exercise.
    func distinctWorkoutCount(exerciseId: UUID) async throws -> Int

    /// Delete observations older than the most recent N sessions for a given exercise.
    /// Returns the number of deleted records.
    @discardableResult
    func pruneObservations(exerciseId: UUID, keepRecentSessions: Int) async throws -> Int
}
