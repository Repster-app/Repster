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
