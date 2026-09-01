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
