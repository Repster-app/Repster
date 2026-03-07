// TemplateRepositoryProtocol.swift
// Contract for WorkoutTemplate, TemplateExercise, and TemplateSet data access.

import Foundation

/// Repository protocol for template entities (WorkoutTemplate, TemplateExercise, TemplateSet).
/// A single repository handles all three since they are tightly coupled and always used together.
protocol TemplateRepositoryProtocol: Sendable {

    // MARK: - WorkoutTemplate CRUD

    func saveTemplate(_ template: WorkoutTemplate) async throws
    func deleteTemplate(_ template: WorkoutTemplate) async throws
    func fetchTemplate(byId id: UUID) async throws -> WorkoutTemplate?
    func fetchAllTemplates() async throws -> [WorkoutTemplate]

    // MARK: - TemplateExercise CRUD

    func saveTemplateExercise(_ exercise: TemplateExercise) async throws
    func deleteTemplateExercise(_ exercise: TemplateExercise) async throws
    func fetchTemplateExercises(for templateId: UUID) async throws -> [TemplateExercise]
    func deleteTemplateExercises(for templateId: UUID) async throws

    // MARK: - TemplateSet CRUD

    func saveTemplateSet(_ set: TemplateSet) async throws
    func deleteTemplateSet(_ set: TemplateSet) async throws
    func fetchTemplateSets(for templateExerciseId: UUID) async throws -> [TemplateSet]
    func deleteTemplateSets(for templateExerciseId: UUID) async throws
}
