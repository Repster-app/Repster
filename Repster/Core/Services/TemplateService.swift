// TemplateService.swift
// Workout template management: CRUD, start workout from template, save from workout,
// and the reviewed import/export flow for `.repstertemplate` archives.

import Foundation

enum TemplateServiceError: Error, LocalizedError {
    case templateNotFound(UUID)
    case workoutNotFound(UUID)
    case exerciseNotFound(UUID)
    case invalidTemplateArchiveVersion(Int)
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
        case .invalidTemplateImportPayload:
            return "The selected JSON is not a supported Repster template archive."
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
        let folder: String?
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
        // Two actor round trips regardless of library size. This was `1 + T + 2TE` — 426 hops at
        // 25 templates × 8 exercises — on every appearance of the list.
        let rows = try await templateRepo.fetchTemplateListRows()
        guard !rows.isEmpty else { return [] }

        let allExercises = try await exerciseRepo.fetchAll()
        var muscleByExerciseId: [UUID: String] = [:]
        for exercise in allExercises {
            if let muscle = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle) {
                muscleByExerciseId[exercise.id] = muscle
            }
        }

        let summaries = rows.map { row in
            // First-seen order, matching what the per-template loop produced before.
            var muscleGroups: [String] = []
            for exerciseId in row.exerciseIds {
                guard let muscle = muscleByExerciseId[exerciseId], !muscleGroups.contains(muscle) else { continue }
                muscleGroups.append(muscle)
            }

            return TemplateSummary(
                id: row.id,
                name: row.name,
                notes: row.notes,
                folder: row.folder,
                exerciseCount: row.exerciseCount,
                totalSetCount: row.totalSetCount,
                muscleGroups: muscleGroups,
                lastUsedAt: row.lastUsedAt,
                createdAt: row.createdAt,
                hasSuperset: row.hasSuperset
            )
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
            folder: template.folder,
            exerciseCount: templateExercises.count,
            totalSetCount: totalSets,
            muscleGroups: muscleGroups,
            lastUsedAt: template.lastUsedAt,
            createdAt: template.createdAt
        )

        return TemplateDetail(template: summary, exercises: exerciseDetails)
    }

    func createTemplate(_ data: TemplateSaveData) async throws -> UUID {
        let template = WorkoutTemplate(name: data.name, notes: data.notes, folder: data.folder)
        try await templateRepo.saveTemplate(template)
        try await templateRepo.replaceTemplateContents(templateId: template.id, exercises: data.exercises)
        return template.id
    }

    func updateTemplate(_ templateId: UUID, data: TemplateSaveData) async throws {
        guard let template = try await templateRepo.fetchTemplate(byId: templateId) else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        template.name = data.name
        template.notes = data.notes
        template.folder = data.folder
        template.updatedAt = Date()
        try await templateRepo.saveTemplate(template)

        // One commit. The old delete-then-insert-per-row sequence could leave the template with zero
        // exercises if anything interrupted it — see TEMPLATES_IMPLEMENTATION_PLAN.md D2.
        try await templateRepo.replaceTemplateContents(templateId: templateId, exercises: data.exercises)
    }

    func deleteTemplate(_ templateId: UUID) async throws {
        guard try await templateRepo.fetchTemplate(byId: templateId) != nil else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        try await templateRepo.deleteTemplateAndContents(templateId: templateId)
    }

    func duplicateTemplate(_ templateId: UUID) async throws -> UUID {
        guard let detail = try await fetchTemplateDetail(templateId) else {
            throw TemplateServiceError.templateNotFound(templateId)
        }

        return try await createTemplate(
            TemplateSaveData(
                name: try await uniqueTemplateName(for: detail.template.name, suffix: "Copy"),
                notes: detail.template.notes,
                folder: detail.template.folder,
                exercises: detail.exercises.map { exercise in
                    TemplateSaveExercise(
                        exerciseId: exercise.exerciseId,
                        orderInTemplate: exercise.orderInTemplate,
                        // Groups are copied as-is. A duplicate is the same session, so its pairs are
                        // the same pairs; new UUIDs would only matter if groups were shared across
                        // templates, and they are not.
                        supersetGroupId: exercise.supersetGroupId,
                        restTimeSeconds: exercise.restTimeSeconds,
                        notes: exercise.notes,
                        sets: exercise.sets.map { set in
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
            )
        )
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
                // Any non-nil set in the exercise defines the group, per SUPERSETS_SCOPING.md §2.1.
                // `sortedSets.first` was wrong whenever the first set predated the grouping — a
                // workout grouped at the rack saved as a template with the grouping dropped.
                supersetGroupId: sortedSets.compactMap(\.supersetGroupId).first,
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
                notes: detail.template.notes,
                folder: detail.template.folder
            ),
            exercises: archiveExercises
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
            folder: importedDocument.folder,
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
                folder: preview.folder,
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
                folder: archive.template.folder,
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

        throw TemplateServiceError.invalidTemplateImportPayload
    }

    private func uniqueImportedTemplateName(for proposedName: String) async throws -> String {
        try await uniqueTemplateName(for: proposedName, suffix: "Imported")
    }

    /// Append a parenthesised suffix until the name is free: "Push Day A (Copy)", then "(Copy 2)".
    private func uniqueTemplateName(for proposedName: String, suffix: String) async throws -> String {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "Untitled Template" : trimmedName

        let existingTemplates = try await templateRepo.fetchAllTemplates()
        let existingNames = Set(existingTemplates.map { normalizeName($0.name) })

        if !existingNames.contains(normalizeName(baseName)) {
            return baseName
        }

        let suffixedName = "\(baseName) (\(suffix))"
        if !existingNames.contains(normalizeName(suffixedName)) {
            return suffixedName
        }

        var index = 2
        while true {
            let candidate = "\(baseName) (\(suffix) \(index))"
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
