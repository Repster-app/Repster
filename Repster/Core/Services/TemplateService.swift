// TemplateService.swift
// Workout template management: CRUD, start workout from template, save from workout,
// and reviewed import/export flows for both native archives and AI-generated drafts.

import Foundation

enum TemplateServiceError: Error, LocalizedError {
    case templateNotFound(UUID)
    case workoutNotFound(UUID)
    case exerciseNotFound(UUID)
    case invalidTemplateArchiveVersion(Int)
    case invalidAITemplateContextVersion(Int)
    case invalidAITemplateDraftVersion(Int)
    case invalidTemplateImportPayload
    case importRequiresResolution(Int)
    case missingImportResolution(String)
    case invalidImportResolution(String)

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "Template not found."
        case .workoutNotFound:
            return "Workout not found."
        case .exerciseNotFound:
            return "Exercise not found."
        case .invalidTemplateArchiveVersion(let version):
            return "Unsupported template archive version: \(version)."
        case .invalidAITemplateContextVersion(let version):
            return "Unsupported AI template context version: \(version)."
        case .invalidAITemplateDraftVersion(let version):
            return "Unsupported AI template draft version: \(version)."
        case .invalidTemplateImportPayload:
            return "The selected JSON is not a supported Repster template archive or AI template draft."
        case .importRequiresResolution(let count):
            return "This import has \(count) exercise reference(s) that need review before it can be saved."
        case .missingImportResolution(let exerciseName):
            return "Choose how to resolve \"\(exerciseName)\" before importing."
        case .invalidImportResolution(let exerciseName):
            return "The selected resolution for \"\(exerciseName)\" is no longer valid."
        }
    }
}

actor TemplateService: TemplateServiceProtocol {

    private struct ImportedTemplateDocument {
        let source: TemplateImportSource
        let templateName: String
        let notes: String?
        let exercises: [ImportedTemplateExercise]
    }

    private struct ImportedTemplateExercise {
        let previewId: UUID
        let proposedExerciseId: UUID
        let exercise: TemplateArchiveExerciseMetadata
        let orderInTemplate: Int
        let supersetGroupKey: String?
        let restTimeSeconds: Int?
        let notes: String?
        let sets: [TemplateArchiveSet]
    }

    // MARK: - Dependencies

    private let templateRepo: TemplateRepositoryProtocol
    private let workoutRepo: WorkoutRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol
    private let exerciseStatsRepo: ExerciseStatsRepositoryProtocol

    init(
        templateRepository: TemplateRepositoryProtocol,
        workoutRepository: WorkoutRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol,
        exerciseStatsRepository: ExerciseStatsRepositoryProtocol
    ) {
        self.templateRepo = templateRepository
        self.workoutRepo = workoutRepository
        self.setRepo = setRepository
        self.exerciseRepo = exerciseRepository
        self.exerciseStatsRepo = exerciseStatsRepository
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

                if let exercise = try await exerciseRepo.fetch(byId: templateExercise.exerciseId),
                   let muscle = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle),
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

        for templateExercise in templateExercises {
            let sets = try await templateRepo.fetchTemplateSets(for: templateExercise.id)
            totalSets += sets.count

            let exercise = try await exerciseRepo.fetch(byId: templateExercise.exerciseId)
            let exerciseName = exercise?.name ?? "Unknown Exercise"
            let primaryMuscle = exercise?.primaryMuscle

            if let muscle = ExercisePrimaryGroup.normalizedValue(primaryMuscle),
               !muscleGroups.contains(muscle) {
                muscleGroups.append(muscle)
            }

            exerciseDetails.append(TemplateExerciseDetail(
                id: templateExercise.id,
                exerciseId: templateExercise.exerciseId,
                exerciseName: exerciseName,
                primaryMuscle: primaryMuscle,
                orderInTemplate: templateExercise.orderInTemplate,
                supersetGroupId: templateExercise.supersetGroupId,
                restTimeSeconds: templateExercise.restTimeSeconds,
                notes: templateExercise.notes,
                sets: sets.map { set in
                    TemplateSetDetail(
                        id: set.id,
                        setType: set.setType,
                        targetRepMin: set.targetRepMin,
                        targetRepMax: set.targetRepMax,
                        targetRIR: set.targetRIR,
                        orderInExercise: set.orderInExercise
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
            let templateExercise = TemplateExercise(
                templateId: template.id,
                exerciseId: exerciseData.exerciseId,
                orderInTemplate: exerciseData.orderInTemplate,
                supersetGroupId: exerciseData.supersetGroupId,
                restTimeSeconds: exerciseData.restTimeSeconds,
                notes: exerciseData.notes
            )
            try await templateRepo.saveTemplateExercise(templateExercise)

            for setData in exerciseData.sets {
                let templateSet = TemplateSet(
                    templateExerciseId: templateExercise.id,
                    setType: setData.setType,
                    targetRepMin: setData.targetRepMin,
                    targetRepMax: setData.targetRepMax,
                    targetRIR: setData.targetRIR,
                    orderInExercise: setData.orderInExercise
                )
                try await templateRepo.saveTemplateSet(templateSet)
            }
        }

        return template.id
    }

    func updateTemplate(_ templateId: UUID, data: TemplateSaveData) async throws {
        guard let template = try await templateRepo.fetchTemplate(byId: templateId) else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        template.name = data.name
        template.notes = data.notes
        template.updatedAt = Date()
        try await templateRepo.saveTemplate(template)

        try await templateRepo.deleteTemplateExercises(for: templateId)

        for exerciseData in data.exercises {
            let templateExercise = TemplateExercise(
                templateId: templateId,
                exerciseId: exerciseData.exerciseId,
                orderInTemplate: exerciseData.orderInTemplate,
                supersetGroupId: exerciseData.supersetGroupId,
                restTimeSeconds: exerciseData.restTimeSeconds,
                notes: exerciseData.notes
            )
            try await templateRepo.saveTemplateExercise(templateExercise)

            for setData in exerciseData.sets {
                let templateSet = TemplateSet(
                    templateExerciseId: templateExercise.id,
                    setType: setData.setType,
                    targetRepMin: setData.targetRepMin,
                    targetRepMax: setData.targetRepMax,
                    targetRIR: setData.targetRIR,
                    orderInExercise: setData.orderInExercise
                )
                try await templateRepo.saveTemplateSet(templateSet)
            }
        }
    }

    func deleteTemplate(_ templateId: UUID) async throws {
        guard let template = try await templateRepo.fetchTemplate(byId: templateId) else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        try await templateRepo.deleteTemplateExercises(for: templateId)
        try await templateRepo.deleteTemplate(template)
    }

    // MARK: - Start Workout from Template

    func startWorkoutFromTemplate(_ templateId: UUID, options: WorkoutStartOptions) async throws -> Workout {
        guard let detail = try await fetchTemplateDetail(templateId) else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        let workout = Workout(
            date: Date(),
            startTime: Date(),
            status: .inProgress,
            excludeFromProgressionHistory: options.excludeFromProgressionHistory
        )
        try await workoutRepo.save(workout)

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

        if let template = try await templateRepo.fetchTemplate(byId: templateId) {
            template.lastUsedAt = Date()
            template.updatedAt = Date()
            try await templateRepo.saveTemplate(template)
        }

        return workout
    }

    // MARK: - Save as Template from Workout

    func createTemplateFromWorkout(_ workoutId: UUID, name: String) async throws -> UUID {
        guard try await workoutRepo.fetch(byId: workoutId) != nil else {
            throw TemplateServiceError.workoutNotFound(workoutId)
        }

        let allSets = try await setRepo.fetchSets(for: workoutId)

        var exerciseOrder: [UUID] = []
        var setsByExercise: [UUID: [WorkoutSet]] = [:]

        for set in allSets.sorted(by: { $0.orderInWorkout < $1.orderInWorkout }) {
            if setsByExercise[set.exerciseId] == nil {
                exerciseOrder.append(set.exerciseId)
                setsByExercise[set.exerciseId] = []
            }
            setsByExercise[set.exerciseId]?.append(set)
        }

        let exercises: [TemplateSaveExercise] = exerciseOrder.enumerated().map { index, exerciseId in
            let exerciseSets = setsByExercise[exerciseId] ?? []
            let sortedSets = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }

            let templateSets = sortedSets.enumerated().map { setIndex, workoutSet in
                let targetBounds = workoutSet.templateSaveTargetRepBounds
                return TemplateSaveSet(
                    setType: workoutSet.setType,
                    targetRepMin: targetBounds.min,
                    targetRepMax: targetBounds.max,
                    targetRIR: workoutSet.targetRIR,
                    orderInExercise: setIndex + 1
                )
            }

            return TemplateSaveExercise(
                exerciseId: exerciseId,
                orderInTemplate: index + 1,
                supersetGroupId: sortedSets.first?.supersetGroupId,
                restTimeSeconds: nil,
                notes: nil,
                sets: templateSets
            )
        }

        return try await createTemplate(
            TemplateSaveData(
                name: name,
                notes: nil,
                exercises: exercises
            )
        )
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
                exercise: archiveMetadata(from: exercise),
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

    func exportAITemplateContext() async throws -> Data {
        let exercises = try await exerciseRepo.fetchAll()
        let stats = try await exerciseStatsRepo.fetchAll()
        let statsByExerciseId = Dictionary(uniqueKeysWithValues: stats.map { ($0.exerciseId, $0) })

        let archive = AITemplateContextArchive(
            version: AITemplateContextArchive.currentVersion,
            exportedAt: Date(),
            exercises: exercises.map { exercise in
                let exerciseStats = statsByExerciseId[exercise.id]
                return AITemplateContextExercise(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    equipmentType: exercise.equipmentType,
                    trackingType: exercise.trackingType,
                    primaryMuscle: exercise.primaryMuscle,
                    secondaryMuscles: exercise.secondaryMuscles,
                    movementPattern: exercise.movementPattern,
                    unilateral: exercise.unilateral,
                    unilateralRepTargetMode: exercise.unilateralRepTargetMode,
                    bilateralLoadFactor: exercise.bilateralLoadFactor,
                    bodyweightFactor: exercise.bodyweightFactor,
                    weightIncrement: exercise.weightIncrement,
                    defaultRestTime: exercise.defaultRestTime,
                    fatigueRate: exercise.fatigueRate,
                    recoveryConstant: exercise.recoveryConstant,
                    stats: AITemplateContextExerciseStats(
                        totalWorkouts: exerciseStats?.totalWorkouts ?? 0,
                        totalSets: exerciseStats?.totalSets ?? 0,
                        lastPerformedDate: exerciseStats?.lastPerformedDate,
                        bestE1RM: exerciseStats?.bestE1RM ?? 0,
                        maxWeight: exerciseStats?.maxWeight ?? 0
                    )
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    func previewTemplateImport(data: Data) async throws -> TemplateImportPreview {
        let importedDocument = try parseImportedTemplateDocument(data: data)
        let allExercises = try await exerciseRepo.fetchAll()

        let exercises = importedDocument.exercises.map { importedExercise in
            TemplateImportExercisePreview(
                id: importedExercise.previewId,
                proposedExerciseId: importedExercise.proposedExerciseId,
                exercise: importedExercise.exercise,
                orderInTemplate: importedExercise.orderInTemplate,
                supersetGroupKey: importedExercise.supersetGroupKey,
                restTimeSeconds: importedExercise.restTimeSeconds,
                notes: importedExercise.notes,
                sets: importedExercise.sets.sorted(by: { $0.orderInExercise < $1.orderInExercise }),
                matchedExercise: resolveExistingMatch(for: importedExercise.exercise, from: allExercises)
            )
        }
        .sorted(by: { $0.orderInTemplate < $1.orderInTemplate })

        return TemplateImportPreview(
            source: importedDocument.source,
            templateName: importedDocument.templateName,
            notes: importedDocument.notes,
            exercises: exercises
        )
    }

    func finalizeTemplateImport(
        _ preview: TemplateImportPreview,
        resolutions: [TemplateImportExerciseResolution]
    ) async throws -> UUID {
        let resolutionByPreviewId = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.previewExerciseId, $0) })
        let templateName = try await uniqueImportedTemplateName(for: preview.templateName)

        var supersetGroupIds: [String: UUID] = [:]
        var createdExerciseIdsByProposedId: [UUID: UUID] = [:]
        var exercises: [TemplateSaveExercise] = []

        for previewExercise in preview.exercises.sorted(by: { $0.orderInTemplate < $1.orderInTemplate }) {
            let resolvedExerciseId: UUID

            if let matchedExercise = previewExercise.matchedExercise {
                resolvedExerciseId = matchedExercise.id
            } else {
                guard let resolution = resolutionByPreviewId[previewExercise.id] else {
                    throw TemplateServiceError.missingImportResolution(previewExercise.exercise.name)
                }

                switch resolution.action {
                case .mapToExisting:
                    guard let existingExerciseId = resolution.existingExerciseId,
                          let existingExercise = try await exerciseRepo.fetch(byId: existingExerciseId) else {
                        throw TemplateServiceError.invalidImportResolution(previewExercise.exercise.name)
                    }
                    resolvedExerciseId = existingExercise.id

                case .createNew:
                    if let previouslyCreatedId = createdExerciseIdsByProposedId[previewExercise.proposedExerciseId] {
                        resolvedExerciseId = previouslyCreatedId
                    } else {
                        let newExercise = makeExercise(from: previewExercise.exercise)
                        if try await exerciseRepo.fetch(byId: newExercise.id) != nil {
                            newExercise.id = UUID()
                        }
                        try await exerciseRepo.save(newExercise)
                        createdExerciseIdsByProposedId[previewExercise.proposedExerciseId] = newExercise.id
                        resolvedExerciseId = newExercise.id
                    }
                }
            }

            let supersetGroupId = normalizedGroupKey(previewExercise.supersetGroupKey).map { groupKey in
                if let existingGroupId = supersetGroupIds[groupKey] {
                    return existingGroupId
                }
                let newGroupId = UUID()
                supersetGroupIds[groupKey] = newGroupId
                return newGroupId
            }

            let sets = previewExercise.sets
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

            exercises.append(
                TemplateSaveExercise(
                    exerciseId: resolvedExerciseId,
                    orderInTemplate: previewExercise.orderInTemplate,
                    supersetGroupId: supersetGroupId,
                    restTimeSeconds: previewExercise.restTimeSeconds,
                    notes: previewExercise.notes,
                    sets: sets
                )
            )
        }

        return try await createTemplate(
            TemplateSaveData(
                name: templateName,
                notes: preview.notes,
                exercises: exercises
            )
        )
    }

    func importTemplate(data: Data) async throws -> UUID {
        let preview = try await previewTemplateImport(data: data)
        guard preview.unresolvedExercises.isEmpty else {
            throw TemplateServiceError.importRequiresResolution(preview.unresolvedExercises.count)
        }
        return try await finalizeTemplateImport(preview, resolutions: [])
    }

    // MARK: - Helpers

    private func archiveMetadata(from exercise: Exercise) -> TemplateArchiveExerciseMetadata {
        TemplateArchiveExerciseMetadata(
            id: exercise.id,
            name: exercise.name,
            equipmentType: exercise.equipmentType,
            trackingType: exercise.trackingType,
            primaryMuscle: exercise.primaryMuscle,
            secondaryMuscles: exercise.secondaryMuscles,
            movementPattern: exercise.movementPattern,
            unilateral: exercise.unilateral,
            unilateralRepTargetMode: exercise.unilateralRepTargetMode,
            bilateralLoadFactor: exercise.bilateralLoadFactor,
            bodyweightFactor: exercise.bodyweightFactor,
            weightIncrement: exercise.weightIncrement,
            defaultRestTime: exercise.defaultRestTime,
            fatigueRate: exercise.fatigueRate,
            recoveryConstant: exercise.recoveryConstant
        )
    }

    private func makeExercise(from metadata: TemplateArchiveExerciseMetadata) -> Exercise {
        Exercise(
            id: metadata.id,
            name: metadata.name,
            equipmentType: metadata.equipmentType,
            trackingType: metadata.trackingType,
            primaryMuscle: metadata.primaryMuscle,
            secondaryMuscles: metadata.secondaryMuscles,
            movementPattern: metadata.movementPattern,
            unilateral: metadata.unilateral,
            unilateralRepTargetMode: metadata.unilateralRepTargetMode,
            bilateralLoadFactor: metadata.bilateralLoadFactor,
            bodyweightFactor: metadata.bodyweightFactor,
            weightIncrement: metadata.weightIncrement,
            defaultRestTime: metadata.defaultRestTime,
            fatigueRate: metadata.fatigueRate,
            recoveryConstant: metadata.recoveryConstant
        )
    }

    private func resolveExistingMatch(
        for archivedExercise: TemplateArchiveExerciseMetadata,
        from allExercises: [Exercise]
    ) -> TemplateImportMatchedExercise? {
        if let existingById = allExercises.first(where: { $0.id == archivedExercise.id }) {
            return TemplateImportMatchedExercise(
                id: existingById.id,
                name: existingById.name,
                method: .exerciseId
            )
        }

        let normalizedArchivedName = normalizeName(archivedExercise.name)
        if let existingByName = allExercises.first(where: {
            normalizeName($0.name) == normalizedArchivedName
        }) {
            return TemplateImportMatchedExercise(
                id: existingByName.id,
                name: existingByName.name,
                method: .normalizedName
            )
        }

        return nil
    }

    private func parseImportedTemplateDocument(data: Data) throws -> ImportedTemplateDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let archive = try? decoder.decode(TemplateArchive.self, from: data) {
            guard archive.version == TemplateArchive.currentVersion else {
                throw TemplateServiceError.invalidTemplateArchiveVersion(archive.version)
            }

            return ImportedTemplateDocument(
                source: .templateArchive,
                templateName: archive.template.name,
                notes: archive.template.notes,
                exercises: archive.exercises.map { archivedExercise in
                    ImportedTemplateExercise(
                        previewId: UUID(),
                        proposedExerciseId: archivedExercise.exercise.id,
                        exercise: archivedExercise.exercise,
                        orderInTemplate: archivedExercise.orderInTemplate,
                        supersetGroupKey: archivedExercise.supersetGroupId?.uuidString,
                        restTimeSeconds: archivedExercise.restTimeSeconds,
                        notes: archivedExercise.notes,
                        sets: archivedExercise.sets
                    )
                }
            )
        }

        if let draft = try? decoder.decode(AITemplateDraft.self, from: data) {
            guard draft.version == AITemplateDraft.currentVersion else {
                throw TemplateServiceError.invalidAITemplateDraftVersion(draft.version)
            }

            return ImportedTemplateDocument(
                source: .aiTemplateDraft,
                templateName: draft.templateName,
                notes: draft.notes,
                exercises: draft.exercises.map { draftExercise in
                    ImportedTemplateExercise(
                        previewId: UUID(),
                        proposedExerciseId: draftExercise.exerciseId,
                        exercise: TemplateArchiveExerciseMetadata(
                            id: draftExercise.exerciseId,
                            name: draftExercise.exerciseName,
                            equipmentType: draftExercise.equipmentType,
                            trackingType: draftExercise.trackingType,
                            primaryMuscle: draftExercise.primaryMuscle,
                            secondaryMuscles: draftExercise.secondaryMuscles,
                            movementPattern: draftExercise.movementPattern,
                            unilateral: draftExercise.unilateral,
                            unilateralRepTargetMode: draftExercise.unilateralRepTargetMode,
                            bilateralLoadFactor: draftExercise.bilateralLoadFactor,
                            bodyweightFactor: draftExercise.bodyweightFactor,
                            weightIncrement: draftExercise.weightIncrement,
                            defaultRestTime: draftExercise.defaultRestTime,
                            fatigueRate: draftExercise.fatigueRate,
                            recoveryConstant: draftExercise.recoveryConstant
                        ),
                        orderInTemplate: draftExercise.orderInTemplate,
                        supersetGroupKey: draftExercise.supersetGroupKey,
                        restTimeSeconds: draftExercise.restTimeSeconds,
                        notes: draftExercise.notes,
                        sets: draftExercise.sets
                    )
                }
            )
        }

        if let context = try? decoder.decode(AITemplateContextArchive.self, from: data),
           context.version != AITemplateContextArchive.currentVersion {
            throw TemplateServiceError.invalidAITemplateContextVersion(context.version)
        }

        throw TemplateServiceError.invalidTemplateImportPayload
    }

    private func uniqueImportedTemplateName(for proposedName: String) async throws -> String {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "Imported Template" : trimmedName

        let existingTemplates = try await templateRepo.fetchAllTemplates()
        let existingNames = Set(existingTemplates.map { normalizeName($0.name) })

        if !existingNames.contains(normalizeName(baseName)) {
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

    private func normalizedGroupKey(_ groupKey: String?) -> String? {
        guard let groupKey else { return nil }
        let normalized = groupKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
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
