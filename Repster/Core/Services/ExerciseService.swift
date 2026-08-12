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

    init(from exercise: ChartExerciseData) {
        self.trackingType = exercise.trackingType
        self.equipmentType = exercise.equipmentType
        self.unilateral = exercise.unilateral
        self.bilateralLoadFactor = exercise.bilateralLoadFactor
        self.bodyweightFactor = exercise.bodyweightFactor
    }

    init(from fields: ExerciseEditableFields) {
        self.trackingType = fields.trackingType
        self.equipmentType = fields.equipmentType
        self.unilateral = fields.unilateral
        self.bilateralLoadFactor = fields.bilateralLoadFactor
        self.bodyweightFactor = fields.bodyweightFactor
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

/// The user-editable fields of an `Exercise`, as plain values.
///
/// This is what the edit UI sends to `ExerciseService` instead of a live `@Model`
/// instance. Handing over the live object was the write half of the 1.4 crash B:
/// `CreateEditExerciseViewModel` mutated the very `Exercise` the active-workout set
/// table was rendering, then had it saved on the repository actor.
///
/// Deliberately excludes the fatigue-learning fields — those are owned by
/// `FatigueLearningService` and must not be clobbered by a metadata edit.
struct ExerciseEditableFields: Sendable, Equatable {
    var name: String
    var equipmentType: EquipmentType
    var trackingType: TrackingType
    var primaryMuscle: String?
    var secondaryMuscles: [String]
    var movementPattern: MovementPattern?
    var unilateral: Bool
    var unilateralRepTargetMode: UnilateralRepTargetMode
    var bilateralLoadFactor: Double?
    var bodyweightFactor: Double
    var weightIncrement: Double?
    var defaultRestTime: Int?

    init(
        name: String,
        equipmentType: EquipmentType,
        trackingType: TrackingType,
        primaryMuscle: String? = nil,
        secondaryMuscles: [String] = [],
        movementPattern: MovementPattern? = nil,
        unilateral: Bool = false,
        unilateralRepTargetMode: UnilateralRepTargetMode = .perSide,
        bilateralLoadFactor: Double? = nil,
        bodyweightFactor: Double = 0,
        weightIncrement: Double? = nil,
        defaultRestTime: Int? = nil
    ) {
        self.name = name
        self.equipmentType = equipmentType
        self.trackingType = trackingType
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.movementPattern = movementPattern
        self.unilateral = unilateral
        self.unilateralRepTargetMode = unilateralRepTargetMode
        self.bilateralLoadFactor = bilateralLoadFactor
        self.bodyweightFactor = bodyweightFactor
        self.weightIncrement = weightIncrement
        self.defaultRestTime = defaultRestTime
    }

    /// Boundary helper for screens that still hold a live `Exercise` and have not yet been
    /// converted. Reads values out so the live model is never handed to the service.
    init(from exercise: Exercise) {
        self.init(from: ChartExerciseData(from: exercise))
    }

    /// Seeds the editable fields from an existing snapshot, so an edit that changes
    /// one field leaves the rest exactly as they were.
    init(from exercise: ChartExerciseData) {
        self.name = exercise.name
        self.equipmentType = exercise.equipmentType
        self.trackingType = exercise.trackingType
        self.primaryMuscle = exercise.primaryMuscle
        self.secondaryMuscles = exercise.secondaryMuscles
        self.movementPattern = exercise.movementPattern
        self.unilateral = exercise.unilateral
        self.unilateralRepTargetMode = exercise.unilateralRepTargetMode
        self.bilateralLoadFactor = exercise.bilateralLoadFactor
        self.bodyweightFactor = exercise.bodyweightFactor
        self.weightIncrement = exercise.weightIncrement
        self.defaultRestTime = exercise.defaultRestTime
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

    @discardableResult
    func createExercise(fields: ExerciseEditableFields) async throws -> UUID {
        try await exerciseRepo.create(fields: fields)
    }

    func fetchExercise(_ exerciseId: UUID) async throws -> Exercise? {
        return try await exerciseRepo.fetch(byId: exerciseId)
    }

    func fetchExerciseSnapshot(_ exerciseId: UUID) async throws -> ChartExerciseData? {
        return try await exerciseRepo.fetchChartExercise(byId: exerciseId)
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

    /// Persist an edited exercise from plain values.
    ///
    /// The pre-edit state is read here, from the store, rather than captured by the caller.
    /// That removes the ordering trap the old signature carried — it required `original` to
    /// be snapshotted *before* the caller mutated the live model, and silently detected no
    /// change if the caller got that wrong.
    func updateExercise(id: UUID, fields: ExerciseEditableFields) async throws {
        guard let original = try await exerciseRepo.fetchMetadataSnapshot(byId: id) else {
            throw ExerciseServiceError.exerciseNotFound(id)
        }

        let hasLoggedSetData = try await exerciseRepo.hasLoggedSetData(id)

        // FR-005: trackingType immutability (specdoc S5.6)
        if hasLoggedSetData && fields.trackingType != original.trackingType {
            throw ExerciseServiceError.trackingTypeImmutable(exerciseId: id)
        }

        // Detect rebuild-required field changes (specdoc S5.6)
        var needsRebuild = false
        if hasLoggedSetData {
            needsRebuild = ExerciseMetadataSnapshot(from: fields).requiresRebuild(comparedTo: original)
        }

        // Persist the update — mutation happens inside the repository actor
        try await exerciseRepo.applyEdit(id: id, fields: fields)

        // Rebuild if calculation-critical fields changed (FR-006)
        // Uses existing stored effectiveWeight values — never recalculates retroactively
        if needsRebuild {
            try await prService.rebuild(for: id)
            try await statsService.rebuild(for: id)
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
