// ExerciseService.swift
// Exercise CRUD, trackingType immutability, metadata mutability enforcement
// Spec: FR-005, FR-006, FR-007, FR-011, FR-012
// Source: specdoc S5, S5.6; AGENT_RULES S3.5, S6

import Foundation

/// The exercise metadata that affects already-stored calculations, captured
/// before an edit is applied.
///
/// `updateExercise` needs the pre-edit values to decide whether PRs and stats
/// have to be rebuilt, and it cannot recover them from the store: callers mutate
/// a live `Exercise`, and re-fetching by ID hands back that same instance from
/// the repository's context, so a "before vs after" comparison would compare
/// every value to itself and always report no change.
struct ExerciseMetadataSnapshot: Sendable, Equatable {
    let trackingType: TrackingType
    let equipmentType: EquipmentType
    let unilateral: Bool
    let bilateralLoadFactor: Double?
    let bodyweightFactor: Double

    init(from exercise: Exercise) {
        self.trackingType = exercise.trackingType
        self.equipmentType = exercise.equipmentType
        self.unilateral = exercise.unilateral
        self.bilateralLoadFactor = exercise.bilateralLoadFactor
        self.bodyweightFactor = exercise.bodyweightFactor
    }

    /// Whether the fields that invalidate stored effectiveWeight-derived values
    /// changed (specdoc S5.6).
    ///
    /// `trackingType` is deliberately excluded — it is immutable once sets are
    /// logged, and a change is rejected rather than rebuilt.
    func requiresRebuild(comparedTo original: ExerciseMetadataSnapshot) -> Bool {
        equipmentType != original.equipmentType
            || unilateral != original.unilateral
            || bilateralLoadFactor != original.bilateralLoadFactor
            || bodyweightFactor != original.bodyweightFactor
    }
}

actor ExerciseService: ExerciseServiceProtocol {

    // MARK: - Dependencies

    private let exerciseRepo: ExerciseRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let exerciseStatsRepo: ExerciseStatsRepositoryProtocol
    private let performanceRecordRepo: PerformanceRecordRepositoryProtocol
    private let prService: PRServiceProtocol
    private let statsService: StatsServiceProtocol
    private let fatigueLearningService: FatigueLearningService

    init(
        exerciseRepository: ExerciseRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        exerciseStatsRepository: ExerciseStatsRepositoryProtocol,
        performanceRecordRepository: PerformanceRecordRepositoryProtocol,
        prService: PRServiceProtocol,
        statsService: StatsServiceProtocol,
        fatigueLearningService: FatigueLearningService
    ) {
        self.exerciseRepo = exerciseRepository
        self.setRepo = setRepository
        self.exerciseStatsRepo = exerciseStatsRepository
        self.performanceRecordRepo = performanceRecordRepository
        self.prService = prService
        self.statsService = statsService
        self.fatigueLearningService = fatigueLearningService
    }

    // MARK: - CRUD (FR-005, FR-007)

    func createExercise(_ exercise: Exercise) async throws {
        try await exerciseRepo.save(exercise)
    }

    func fetchExercise(_ exerciseId: UUID) async throws -> Exercise? {
        return try await exerciseRepo.fetch(byId: exerciseId)
    }

    func fetchAllExercises() async throws -> [Exercise] {
        return try await exerciseRepo.fetchAll()
    }

    func searchExercises(name query: String) async throws -> [Exercise] {
        return try await exerciseRepo.search(name: query)
    }

    func exerciseHasSets(_ exerciseId: UUID) async throws -> Bool {
        return try await exerciseRepo.hasAssociatedSets(exerciseId)
    }

    func exerciseHasLoggedSetData(_ exerciseId: UUID) async throws -> Bool {
        return try await exerciseRepo.hasLoggedSetData(exerciseId)
    }

    // MARK: - Update with Metadata Enforcement (FR-005, FR-006)

    /// Persist an edited exercise.
    ///
    /// `original` must be captured by the caller *before* it mutates `exercise`,
    /// otherwise no change can be detected — see `ExerciseMetadataSnapshot`.
    func updateExercise(_ exercise: Exercise, original: ExerciseMetadataSnapshot) async throws {
        let hasLoggedSetData = try await exerciseRepo.hasLoggedSetData(exercise.id)

        // FR-005: trackingType immutability (specdoc S5.6)
        if hasLoggedSetData && exercise.trackingType != original.trackingType {
            throw ExerciseServiceError.trackingTypeImmutable(exerciseId: exercise.id)
        }

        // Detect rebuild-required field changes (specdoc S5.6)
        var needsRebuild = false
        if hasLoggedSetData {
            needsRebuild = ExerciseMetadataSnapshot(from: exercise).requiresRebuild(comparedTo: original)
        }

        // Persist the update
        exercise.updatedAt = Date()
        try await exerciseRepo.save(exercise)

        // Rebuild if calculation-critical fields changed (FR-006)
        // Uses existing stored effectiveWeight values — never recalculates retroactively
        if needsRebuild {
            try await prService.rebuild(for: exercise.id)
            try await statsService.rebuild(for: exercise.id)
        }
    }

    // MARK: - Deletion (FR-011)

    /// Delete an exercise with full cascade.
    /// No rebuild needed — everything related to this exercise is removed.
    func deleteExercise(_ exerciseId: UUID) async throws {
        guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else {
            throw ExerciseServiceError.exerciseNotFound(exerciseId)
        }

        // 1. Remove fatigue learning rows tied to this exercise before deleting core history.
        try await fatigueLearningService.removeCapturedExerciseData(exerciseId: exerciseId)

        // 2. Bulk delete all sets for this exercise
        try await setRepo.deleteSets(forExercise: exerciseId)

        // 3. Delete ExerciseStats (if exists)
        if let stats = try await exerciseStatsRepo.fetch(for: exerciseId) {
            try await exerciseStatsRepo.delete(stats)
        }

        // 4. Delete all PerformanceRecords for this exercise
        try await performanceRecordRepo.deleteAll(for: exerciseId)

        // 5. Delete the exercise itself
        try await exerciseRepo.delete(exercise)
    }

}
