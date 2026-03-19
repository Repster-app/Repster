// TemplateService.swift
// Workout template management: CRUD, start workout from template, save workout as template.
// Uses TemplateRepository for template data, plus WorkoutRepository/SetRepository/ExerciseRepository
// for cross-entity operations (start workout, save from workout).

import Foundation

enum TemplateServiceError: Error {
    case templateNotFound(UUID)
    case workoutNotFound(UUID)
    case exerciseNotFound(UUID)
    case invalidTemplateArchiveVersion(Int)
}

actor TemplateService: TemplateServiceProtocol {

    // MARK: - Dependencies

    private let templateRepo: TemplateRepositoryProtocol
    private let workoutRepo: WorkoutRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol

    init(
        templateRepository: TemplateRepositoryProtocol,
        workoutRepository: WorkoutRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol
    ) {
        self.templateRepo = templateRepository
        self.workoutRepo = workoutRepository
        self.setRepo = setRepository
        self.exerciseRepo = exerciseRepository
    }

    // MARK: - Template CRUD

    func fetchAllTemplates() async throws -> [TemplateSummary] {
        let templates = try await templateRepo.fetchAllTemplates()

        var summaries: [TemplateSummary] = []
        for template in templates {
            let exercises = try await templateRepo.fetchTemplateExercises(for: template.id)

            var totalSets = 0
            var muscleGroups: [String] = []

            for templateExercise in exercises {
                let sets = try await templateRepo.fetchTemplateSets(for: templateExercise.id)
                totalSets += sets.count

                // Look up exercise for muscle group
                if let exercise = try await exerciseRepo.fetch(byId: templateExercise.exerciseId),
                   let muscle = exercise.primaryMuscle?.lowercased(),
                   !muscleGroups.contains(muscle) {
                    muscleGroups.append(muscle)
                }
            }

            summaries.append(TemplateSummary(
                id: template.id,
                name: template.name,
                notes: template.notes,
                exerciseCount: exercises.count,
                totalSetCount: totalSets,
                muscleGroups: muscleGroups,
                lastUsedAt: template.lastUsedAt,
                createdAt: template.createdAt
            ))
        }

        // Sort by lastUsedAt (most recent first), then createdAt for never-used templates
        return summaries.sorted { a, b in
            let aDate = a.lastUsedAt ?? .distantPast
            let bDate = b.lastUsedAt ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.createdAt > b.createdAt
        }
    }

    func fetchTemplateDetail(_ templateId: UUID) async throws -> TemplateDetail? {
        guard let template = try await templateRepo.fetchTemplate(byId: templateId) else {
            return nil
        }

        let templateExercises = try await templateRepo.fetchTemplateExercises(for: templateId)
        var exerciseDetails: [TemplateExerciseDetail] = []
        var totalSets = 0
        var muscleGroups: [String] = []

        for te in templateExercises {
            let sets = try await templateRepo.fetchTemplateSets(for: te.id)
            totalSets += sets.count

            let exercise = try await exerciseRepo.fetch(byId: te.exerciseId)
            let exerciseName = exercise?.name ?? "Unknown Exercise"
            let primaryMuscle = exercise?.primaryMuscle

            if let muscle = primaryMuscle?.lowercased(), !muscleGroups.contains(muscle) {
                muscleGroups.append(muscle)
            }

            exerciseDetails.append(TemplateExerciseDetail(
                id: te.id,
                exerciseId: te.exerciseId,
                exerciseName: exerciseName,
                primaryMuscle: primaryMuscle,
                orderInTemplate: te.orderInTemplate,
                supersetGroupId: te.supersetGroupId,
                restTimeSeconds: te.restTimeSeconds,
                notes: te.notes,
                sets: sets.map { s in
                    TemplateSetDetail(
                        id: s.id,
                        setType: s.setType,
                        targetRepMin: s.targetRepMin,
                        targetRepMax: s.targetRepMax,
                        targetRIR: s.targetRIR,
                        orderInExercise: s.orderInExercise
                    )
                }
            ))
        }

        let summary = TemplateSummary(
            id: template.id,
            name: template.name,
            notes: template.notes,
            exerciseCount: templateExercises.count,
            totalSetCount: totalSets,
            muscleGroups: muscleGroups,
            lastUsedAt: template.lastUsedAt,
            createdAt: template.createdAt
        )

        return TemplateDetail(template: summary, exercises: exerciseDetails)
    }

    func createTemplate(_ data: TemplateSaveData) async throws -> UUID {
        let template = WorkoutTemplate(name: data.name, notes: data.notes)
        try await templateRepo.saveTemplate(template)

        for exerciseData in data.exercises {
            let te = TemplateExercise(
                templateId: template.id,
                exerciseId: exerciseData.exerciseId,
                orderInTemplate: exerciseData.orderInTemplate,
                supersetGroupId: exerciseData.supersetGroupId,
                restTimeSeconds: exerciseData.restTimeSeconds,
                notes: exerciseData.notes
            )
            try await templateRepo.saveTemplateExercise(te)

            for setData in exerciseData.sets {
                let ts = TemplateSet(
                    templateExerciseId: te.id,
                    setType: setData.setType,
                    targetRepMin: setData.targetRepMin,
                    targetRepMax: setData.targetRepMax,
                    targetRIR: setData.targetRIR,
                    orderInExercise: setData.orderInExercise
                )
                try await templateRepo.saveTemplateSet(ts)
            }
        }

        return template.id
    }

    func updateTemplate(_ templateId: UUID, data: TemplateSaveData) async throws {
        guard let template = try await templateRepo.fetchTemplate(byId: templateId) else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        // Update template metadata
        template.name = data.name
        template.notes = data.notes
        template.updatedAt = Date()
        try await templateRepo.saveTemplate(template)

        // Delete all existing exercises and sets (cascade)
        try await templateRepo.deleteTemplateExercises(for: templateId)

        // Re-create exercises and sets from the new data
        for exerciseData in data.exercises {
            let te = TemplateExercise(
                templateId: templateId,
                exerciseId: exerciseData.exerciseId,
                orderInTemplate: exerciseData.orderInTemplate,
                supersetGroupId: exerciseData.supersetGroupId,
                restTimeSeconds: exerciseData.restTimeSeconds,
                notes: exerciseData.notes
            )
            try await templateRepo.saveTemplateExercise(te)

            for setData in exerciseData.sets {
                let ts = TemplateSet(
                    templateExerciseId: te.id,
                    setType: setData.setType,
                    targetRepMin: setData.targetRepMin,
                    targetRepMax: setData.targetRepMax,
                    targetRIR: setData.targetRIR,
                    orderInExercise: setData.orderInExercise
                )
                try await templateRepo.saveTemplateSet(ts)
            }
        }
    }

    func deleteTemplate(_ templateId: UUID) async throws {
        guard let template = try await templateRepo.fetchTemplate(byId: templateId) else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        // Delete exercises + sets (cascade)
        try await templateRepo.deleteTemplateExercises(for: templateId)

        // Delete template itself
        try await templateRepo.deleteTemplate(template)
    }

    // MARK: - Start Workout from Template

    func startWorkoutFromTemplate(_ templateId: UUID) async throws -> Workout {
        guard let detail = try await fetchTemplateDetail(templateId) else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        // Create the workout
        let workout = Workout(
            date: Date(),
            startTime: Date(),
            status: .inProgress
        )
        try await workoutRepo.save(workout)

        // Create WorkoutSets from template structure
        var globalSetOrder = 1

        for exerciseDetail in detail.exercises {
            for (setIndex, templateSet) in exerciseDetail.sets.enumerated() {
                let workoutSet = WorkoutSet(
                    workoutId: workout.id,
                    exerciseId: exerciseDetail.exerciseId,
                    date: Date(),
                    setType: templateSet.setType,
                    orderInWorkout: globalSetOrder,
                    orderInExercise: setIndex + 1,
                    supersetGroupId: exerciseDetail.supersetGroupId,
                    completed: false,
                    targetRepMin: templateSet.targetRepMin,
                    targetRepMax: templateSet.targetRepMax,
                    targetRIR: templateSet.targetRIR
                )
                try await setRepo.save(workoutSet)
                globalSetOrder += 1
            }
        }

        // Update template's lastUsedAt
        if let template = try await templateRepo.fetchTemplate(byId: templateId) {
            template.lastUsedAt = Date()
            template.updatedAt = Date()
            try await templateRepo.saveTemplate(template)
        }

        return workout
    }

    // MARK: - Save as Template from Workout

    func createTemplateFromWorkout(_ workoutId: UUID, name: String) async throws -> UUID {
        guard let _ = try await workoutRepo.fetch(byId: workoutId) else {
            throw TemplateServiceError.workoutNotFound(workoutId)
        }

        // Fetch all sets for this workout, grouped by exercise
        let allSets = try await setRepo.fetchSets(for: workoutId)

        // Group sets by exerciseId, preserving order
        var exerciseOrder: [UUID] = []
        var setsByExercise: [UUID: [WorkoutSet]] = [:]

        for set in allSets.sorted(by: { $0.orderInWorkout < $1.orderInWorkout }) {
            if setsByExercise[set.exerciseId] == nil {
                exerciseOrder.append(set.exerciseId)
                setsByExercise[set.exerciseId] = []
            }
            setsByExercise[set.exerciseId]?.append(set)
        }

        // Build template save data
        var exercises: [TemplateSaveExercise] = []

        for (order, exerciseId) in exerciseOrder.enumerated() {
            let exerciseSets = setsByExercise[exerciseId] ?? []
            let sortedSets = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }

            let templateSets: [TemplateSaveSet] = sortedSets.enumerated().map { index, workoutSet in
                TemplateSaveSet(
                    setType: workoutSet.setType,
                    targetRepMin: workoutSet.targetRepMin ?? workoutSet.reps,
                    targetRepMax: workoutSet.targetRepMax ?? workoutSet.reps,
                    targetRIR: workoutSet.targetRIR,
                    orderInExercise: index + 1
                )
            }

            exercises.append(TemplateSaveExercise(
                exerciseId: exerciseId,
                orderInTemplate: order + 1,
                supersetGroupId: sortedSets.first?.supersetGroupId,
                restTimeSeconds: nil,
                notes: nil,
                sets: templateSets
            ))
        }

        let saveData = TemplateSaveData(
            name: name,
            notes: nil,
            exercises: exercises
        )

        return try await createTemplate(saveData)
    }

    // MARK: - Import / Export

    func exportTemplate(_ templateId: UUID) async throws -> Data {
        guard let detail = try await fetchTemplateDetail(templateId) else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        let archiveExercises = try await detail.exercises.mapAsync { exerciseDetail in
            guard let exercise = try await exerciseRepo.fetch(byId: exerciseDetail.exerciseId) else {
                throw TemplateServiceError.exerciseNotFound(exerciseDetail.exerciseId)
            }

            return TemplateArchiveExercise(
                exercise: TemplateArchiveExerciseMetadata(
                    id: exercise.id,
                    name: exercise.name,
                    equipmentType: exercise.equipmentType,
                    trackingType: exercise.trackingType,
                    primaryMuscle: exercise.primaryMuscle,
                    secondaryMuscles: exercise.secondaryMuscles,
                    movementPattern: exercise.movementPattern,
                    unilateral: exercise.unilateral,
                    bilateralLoadFactor: exercise.bilateralLoadFactor,
                    bodyweightFactor: exercise.bodyweightFactor,
                    weightIncrement: exercise.weightIncrement,
                    defaultRestTime: exercise.defaultRestTime,
                    fatigueRate: exercise.fatigueRate,
                    recoveryConstant: exercise.recoveryConstant
                ),
                orderInTemplate: exerciseDetail.orderInTemplate,
                supersetGroupId: exerciseDetail.supersetGroupId,
                restTimeSeconds: exerciseDetail.restTimeSeconds,
                notes: exerciseDetail.notes,
                sets: exerciseDetail.sets.map { set in
                    TemplateArchiveSet(
                        setType: set.setType,
                        targetRepMin: set.targetRepMin,
                        targetRepMax: set.targetRepMax,
                        targetRIR: set.targetRIR,
                        orderInExercise: set.orderInExercise
                    )
                }
            )
        }

        let archive = TemplateArchive(
            version: TemplateArchive.currentVersion,
            template: TemplateArchiveTemplate(
                id: detail.template.id,
                name: detail.template.name,
                notes: detail.template.notes
            ),
            exercises: archiveExercises
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    func importTemplate(data: Data) async throws -> UUID {
        let archive = try JSONDecoder().decode(TemplateArchive.self, from: data)
        guard archive.version == TemplateArchive.currentVersion else {
            throw TemplateServiceError.invalidTemplateArchiveVersion(archive.version)
        }

        let templateName = try await uniqueImportedTemplateName(for: archive.template.name)
        let exercises = try await archive.exercises
            .sorted(by: { $0.orderInTemplate < $1.orderInTemplate })
            .mapAsync { archivedExercise in
                let resolvedExercise = try await resolveExercise(for: archivedExercise.exercise)
                return TemplateSaveExercise(
                    exerciseId: resolvedExercise.id,
                    orderInTemplate: archivedExercise.orderInTemplate,
                    supersetGroupId: archivedExercise.supersetGroupId,
                    restTimeSeconds: archivedExercise.restTimeSeconds,
                    notes: archivedExercise.notes,
                    sets: archivedExercise.sets
                        .sorted(by: { $0.orderInExercise < $1.orderInExercise })
                        .map { set in
                            TemplateSaveSet(
                                setType: set.setType,
                                targetRepMin: set.targetRepMin,
                                targetRepMax: set.targetRepMax,
                                targetRIR: set.targetRIR,
                                orderInExercise: set.orderInExercise
                            )
                        }
                )
            }

        let saveData = TemplateSaveData(
            name: templateName,
            notes: archive.template.notes,
            exercises: exercises
        )
        return try await createTemplate(saveData)
    }

    // MARK: - Helpers

    private func resolveExercise(for archivedExercise: TemplateArchiveExerciseMetadata) async throws -> Exercise {
        if let existingById = try await exerciseRepo.fetch(byId: archivedExercise.id) {
            return existingById
        }

        let normalizedArchivedName = normalizeName(archivedExercise.name)
        let allExercises = try await exerciseRepo.fetchAll()
        if let existingByName = allExercises.first(where: {
            normalizeName($0.name) == normalizedArchivedName
        }) {
            return existingByName
        }

        let newExercise = Exercise(
            id: archivedExercise.id,
            name: archivedExercise.name,
            equipmentType: archivedExercise.equipmentType,
            trackingType: archivedExercise.trackingType,
            primaryMuscle: archivedExercise.primaryMuscle,
            secondaryMuscles: archivedExercise.secondaryMuscles,
            movementPattern: archivedExercise.movementPattern,
            unilateral: archivedExercise.unilateral,
            bilateralLoadFactor: archivedExercise.bilateralLoadFactor,
            bodyweightFactor: archivedExercise.bodyweightFactor,
            weightIncrement: archivedExercise.weightIncrement,
            defaultRestTime: archivedExercise.defaultRestTime,
            fatigueRate: archivedExercise.fatigueRate,
            recoveryConstant: archivedExercise.recoveryConstant
        )
        try await exerciseRepo.save(newExercise)
        return newExercise
    }

    private func uniqueImportedTemplateName(for proposedName: String) async throws -> String {
        let baseName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Imported Template"
            : proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingTemplates = try await templateRepo.fetchAllTemplates()
        let existingNames = Set(existingTemplates.map { normalizeName($0.name) })
        let normalizedBaseName = normalizeName(baseName)

        if !existingNames.contains(normalizedBaseName) {
            return baseName
        }

        let importedName = "\(baseName) (Imported)"
        if !existingNames.contains(normalizeName(importedName)) {
            return importedName
        }

        var index = 2
        while true {
            let candidate = "\(baseName) (Imported \(index))"
            if !existingNames.contains(normalizeName(candidate)) {
                return candidate
            }
            index += 1
        }
    }

    private func normalizeName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}

private extension Array {
    func mapAsync<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}
