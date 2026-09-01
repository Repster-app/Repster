// TemplateRepository.swift
// Data access for WorkoutTemplate, TemplateExercise, and TemplateSet entities.
// Uses @ModelActor for SwiftData thread-safe access (same pattern as WorkoutRepository).

import SwiftData
import Foundation

@ModelActor
actor TemplateRepository: TemplateRepositoryProtocol {

    // MARK: - WorkoutTemplate CRUD

    func saveTemplate(_ template: WorkoutTemplate) throws {
        modelContext.insert(template)
        try modelContext.save()
    }

    func deleteTemplate(_ template: WorkoutTemplate) throws {
        modelContext.delete(template)
        try modelContext.save()
    }

    func fetchTemplate(byId id: UUID) throws -> WorkoutTemplate? {
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchAllTemplates() throws -> [WorkoutTemplate] {
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - List reads

    func fetchTemplateListRows() throws -> [TemplateListRow] {
        let templates = try modelContext.fetch(
            FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )
        let allExercises = try modelContext.fetch(
            FetchDescriptor<TemplateExercise>(sortBy: [SortDescriptor(\.orderInTemplate)])
        )
        let allSets = try modelContext.fetch(FetchDescriptor<TemplateSet>())

        let exercisesByTemplate = Dictionary(grouping: allExercises, by: \.templateId)
        var setCountByExercise: [UUID: Int] = [:]
        for set in allSets {
            setCountByExercise[set.templateExerciseId, default: 0] += 1
        }

        return templates.map { template in
            let exercises = (exercisesByTemplate[template.id] ?? [])
                .sorted { $0.orderInTemplate < $1.orderInTemplate }
            return TemplateListRow(
                id: template.id,
                name: template.name,
                notes: template.notes,
                folder: template.folder,
                lastUsedAt: template.lastUsedAt,
                createdAt: template.createdAt,
                exerciseCount: exercises.count,
                totalSetCount: exercises.reduce(0) { $0 + (setCountByExercise[$1.id] ?? 0) },
                exerciseIds: exercises.map(\.exerciseId),
                hasSuperset: exercises.contains { $0.supersetGroupId != nil }
            )
        }
    }

    /// See the protocol. Three fetches, grouped in memory, nothing handed out but values.
    func fetchTemplateDetailRows(templateId: UUID) throws -> TemplateDetailRows? {
        guard let template = try modelContext.fetch(
            FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == templateId })
        ).first else { return nil }

        let exercises = try modelContext.fetch(
            FetchDescriptor<TemplateExercise>(
                predicate: #Predicate { $0.templateId == templateId },
                sortBy: [SortDescriptor(\.orderInTemplate)]
            )
        )
        let exerciseIds = Set(exercises.map(\.id))
        let setsByExercise = Dictionary(
            grouping: try modelContext.fetch(FetchDescriptor<TemplateSet>())
                .filter { exerciseIds.contains($0.templateExerciseId) },
            by: \.templateExerciseId
        )

        return TemplateDetailRows(
            id: template.id,
            name: template.name,
            notes: template.notes,
            folder: template.folder,
            lastUsedAt: template.lastUsedAt,
            createdAt: template.createdAt,
            exercises: exercises.map { exercise in
                TemplateExerciseRow(
                    id: exercise.id,
                    exerciseId: exercise.exerciseId,
                    orderInTemplate: exercise.orderInTemplate,
                    supersetGroupId: exercise.supersetGroupId,
                    restTimeSeconds: exercise.restTimeSeconds,
                    notes: exercise.notes,
                    sets: (setsByExercise[exercise.id] ?? [])
                        .sorted { $0.orderInExercise < $1.orderInExercise }
                        .map { set in
                            TemplateSetRowData(
                                id: set.id,
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
    }

    // MARK: - Atomic whole-template writes

    /// Replace a template's exercises and sets in one commit. See the protocol for why.
    ///
    /// Models are constructed **inside** the actor rather than handed in, so nothing crosses a context
    /// boundary — the pattern SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md exists about.
    func replaceTemplateContents(templateId: UUID, exercises: [TemplateSaveExercise]) throws {
        do {
            for existing in try fetchTemplateExercises(for: templateId) {
                for set in try fetchTemplateSets(for: existing.id) {
                    modelContext.delete(set)
                }
                modelContext.delete(existing)
            }

            for exerciseData in exercises {
                let templateExercise = TemplateExercise(
                    templateId: templateId,
                    exerciseId: exerciseData.exerciseId,
                    orderInTemplate: exerciseData.orderInTemplate,
                    supersetGroupId: exerciseData.supersetGroupId,
                    restTimeSeconds: exerciseData.restTimeSeconds,
                    notes: exerciseData.notes
                )
                modelContext.insert(templateExercise)

                for setData in exerciseData.sets {
                    modelContext.insert(
                        TemplateSet(
                            templateExerciseId: templateExercise.id,
                            setType: setData.setType,
                            targetRepMin: setData.targetRepMin,
                            targetRepMax: setData.targetRepMax,
                            targetRIR: setData.targetRIR,
                            orderInExercise: setData.orderInExercise
                        )
                    )
                }
            }

            try modelContext.save()
        } catch {
            // Without this the failed batch stays pending and a later unrelated save could commit
            // a half-replaced template.
            modelContext.rollback()
            throw error
        }
    }

    /// See the protocol for why this exists. Everything is read **before** anything is deleted:
    /// re-fetching after a delete can hand back rows whose attributes are unresolved faults, and
    /// touching one of those is fatal (SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md).
    @discardableResult
    func deleteTemplateReferences(toExerciseId exerciseId: UUID) throws -> Int {
        do {
            let doomed = try modelContext.fetch(
                FetchDescriptor<TemplateExercise>(
                    predicate: #Predicate { $0.exerciseId == exerciseId }
                )
            )
            guard !doomed.isEmpty else { return 0 }

            let doomedIds = Set(doomed.map(\.id))
            var survivorsByTemplate: [UUID: [TemplateExercise]] = [:]
            for templateId in Set(doomed.map(\.templateId)) {
                survivorsByTemplate[templateId] = try fetchTemplateExercises(for: templateId)
                    .filter { !doomedIds.contains($0.id) }
            }

            for templateExercise in doomed {
                for set in try fetchTemplateSets(for: templateExercise.id) {
                    modelContext.delete(set)
                }
                modelContext.delete(templateExercise)
            }

            let now = Date()
            for (templateId, survivors) in survivorsByTemplate {
                var membersByGroup: [UUID: Int] = [:]
                for survivor in survivors {
                    guard let groupId = survivor.supersetGroupId else { continue }
                    membersByGroup[groupId, default: 0] += 1
                }

                for (index, survivor) in survivors.enumerated() {
                    survivor.orderInTemplate = index + 1
                    if let groupId = survivor.supersetGroupId, membersByGroup[groupId] == 1 {
                        survivor.supersetGroupId = nil
                    }
                    survivor.updatedAt = now
                }

                for template in try modelContext.fetch(
                    FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == templateId })
                ) {
                    template.updatedAt = now
                }
            }

            try modelContext.save()
            return doomed.count
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// See the protocol for why this is not a `replaceTemplateContents` round trip.
    func updateTemplateFolder(templateId: UUID, folder: String?) throws {
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.id == templateId }
        )
        guard let template = try modelContext.fetch(descriptor).first else { return }

        template.folder = folder
        template.updatedAt = Date()
        try modelContext.save()
    }

    func deleteTemplateAndContents(templateId: UUID) throws {
        do {
            for existing in try fetchTemplateExercises(for: templateId) {
                for set in try fetchTemplateSets(for: existing.id) {
                    modelContext.delete(set)
                }
                modelContext.delete(existing)
            }

            let descriptor = FetchDescriptor<WorkoutTemplate>(
                predicate: #Predicate { $0.id == templateId }
            )
            for template in try modelContext.fetch(descriptor) {
                modelContext.delete(template)
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - TemplateExercise CRUD

    func saveTemplateExercise(_ exercise: TemplateExercise) throws {
        modelContext.insert(exercise)
        try modelContext.save()
    }

    func deleteTemplateExercise(_ exercise: TemplateExercise) throws {
        modelContext.delete(exercise)
        try modelContext.save()
    }

    func fetchTemplateExercises(for templateId: UUID) throws -> [TemplateExercise] {
        let descriptor = FetchDescriptor<TemplateExercise>(
            predicate: #Predicate { $0.templateId == templateId },
            sortBy: [SortDescriptor(\.orderInTemplate)]
        )
        return try modelContext.fetch(descriptor)
    }

    func deleteTemplateExercises(for templateId: UUID) throws {
        let exercises = try fetchTemplateExercises(for: templateId)
        for exercise in exercises {
            // Delete all sets for this exercise first
            try deleteTemplateSets(for: exercise.id)
            modelContext.delete(exercise)
        }
        try modelContext.save()
    }

    // MARK: - TemplateSet CRUD

    func saveTemplateSet(_ set: TemplateSet) throws {
        modelContext.insert(set)
        try modelContext.save()
    }

    func deleteTemplateSet(_ set: TemplateSet) throws {
        modelContext.delete(set)
        try modelContext.save()
    }

    func fetchTemplateSets(for templateExerciseId: UUID) throws -> [TemplateSet] {
        let descriptor = FetchDescriptor<TemplateSet>(
            predicate: #Predicate { $0.templateExerciseId == templateExerciseId },
            sortBy: [SortDescriptor(\.orderInExercise)]
        )
        return try modelContext.fetch(descriptor)
    }

    func deleteTemplateSets(for templateExerciseId: UUID) throws {
        let sets = try fetchTemplateSets(for: templateExerciseId)
        for set in sets {
            modelContext.delete(set)
        }
        try modelContext.save()
    }
}
