import SwiftData
import Foundation

@ModelActor
actor ExerciseRepository: ExerciseRepositoryProtocol {

    // MARK: - CRUD

    func save(_ exercise: Exercise) throws {
        modelContext.insert(exercise)
        try modelContext.save()
    }

    func delete(_ exercise: Exercise) throws {
        modelContext.delete(exercise)
        try modelContext.save()
    }

    func fetch(byId id: UUID) throws -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Queries

    func fetchAll() throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAllChartExercises() throws -> [ChartExerciseData] {
        try fetchAll().map(ChartExerciseData.init(from:))
    }

    func fetchChartExercise(byId id: UUID) throws -> ChartExerciseData? {
        try fetch(byId: id).map(ChartExerciseData.init(from:))
    }

    func fetchMetadataSnapshot(byId id: UUID) throws -> ExerciseMetadataSnapshot? {
        try fetch(byId: id).map(ExerciseMetadataSnapshot.init(from:))
    }

    // MARK: - Mutation
    //
    // Fetch, mutate and save happen here, inside the actor that owns the context.
    // Callers pass values and never see the model — a service mutating a live
    // `Exercise` on its own executor is the same illegal cross-context write that
    // produced crash B, regardless of which thread it runs on.

    /// Apply an edit to an existing exercise. No-op if the id no longer exists.
    ///
    /// Only the user-editable fields are touched; `fatigueRate`, learning counters and
    /// `createdAt` are left alone.
    func applyEdit(id: UUID, fields: ExerciseEditableFields) throws {
        guard let exercise = try fetch(byId: id) else { return }

        exercise.name = fields.name
        exercise.equipmentType = fields.equipmentType
        exercise.trackingType = fields.trackingType
        exercise.primaryMuscle = fields.primaryMuscle
        exercise.secondaryMuscles = fields.secondaryMuscles
        exercise.movementPattern = fields.movementPattern
        exercise.unilateral = fields.unilateral
        exercise.unilateralRepTargetMode = fields.unilateralRepTargetMode
        exercise.bilateralLoadFactor = fields.bilateralLoadFactor
        exercise.bodyweightFactor = fields.bodyweightFactor
        exercise.weightIncrement = fields.weightIncrement
        exercise.defaultRestTime = fields.defaultRestTime
        exercise.updatedAt = Date()

        try modelContext.save()
    }

    /// Insert a new exercise built from plain values. Returns its id.
    func create(fields: ExerciseEditableFields) throws -> UUID {
        let exercise = Exercise(
            name: fields.name,
            equipmentType: fields.equipmentType,
            trackingType: fields.trackingType,
            primaryMuscle: fields.primaryMuscle,
            secondaryMuscles: fields.secondaryMuscles,
            movementPattern: fields.movementPattern,
            unilateral: fields.unilateral,
            unilateralRepTargetMode: fields.unilateralRepTargetMode,
            bilateralLoadFactor: fields.bilateralLoadFactor,
            bodyweightFactor: fields.bodyweightFactor,
            weightIncrement: fields.weightIncrement,
            defaultRestTime: fields.defaultRestTime
        )
        modelContext.insert(exercise)
        try modelContext.save()
        return exercise.id
    }

    func search(name: String) throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate {
                $0.name.localizedStandardContains(name)
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func hasAssociatedSets(_ exerciseId: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    func hasLoggedSetData(_ exerciseId: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        return try modelContext.fetch(descriptor).contains { $0.hasData }
    }
}
