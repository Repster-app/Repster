import Foundation

/// Repository protocol for FatigueObservation entity.
/// Used by FatigueLearningService to persist and query prediction error data.
protocol FatigueObservationRepositoryProtocol: Sendable {

    /// Insert or replace an observation for a completed set.
    func upsert(_ observation: FatigueObservation) async throws

    /// Fetch all observations for a specific workout.
    func fetchObservations(for workoutId: UUID) async throws -> [FatigueObservation]

    /// Fetch all observations for a specific exercise, ordered by createdAt DESC.
    func fetchObservations(exerciseId: UUID, limit: Int?) async throws -> [FatigueObservation]

    /// Count the number of distinct workouts with observations for an exercise.
    func distinctWorkoutCount(exerciseId: UUID) async throws -> Int

    /// Delete any observation for a set.
    func deleteObservation(for setId: UUID) async throws

    /// Delete observations older than the most recent N sessions for a given exercise.
    /// Returns the number of deleted records.
    @discardableResult
    func pruneObservations(exerciseId: UUID, keepRecentSessions: Int) async throws -> Int
}

protocol FatigueLearningSetAuditRepositoryProtocol: Sendable {
    func upsert(_ audit: FatigueLearningSetAudit) async throws
    func fetchAudits(for workoutId: UUID) async throws -> [FatigueLearningSetAudit]
    func fetchAudits(workoutId: UUID, exerciseId: UUID) async throws -> [FatigueLearningSetAudit]
    func fetchAudits(exerciseId: UUID, limit: Int?) async throws -> [FatigueLearningSetAudit]
    func exerciseIdsWithAudits() async throws -> [UUID]
    func deleteAudit(for setId: UUID) async throws
    func deleteAudits(workoutId: UUID) async throws
    func deleteAudits(exerciseId: UUID) async throws
    func deleteAll() async throws
}
