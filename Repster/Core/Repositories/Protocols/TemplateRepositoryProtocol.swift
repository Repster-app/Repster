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

    // MARK: - List reads

    /// Everything the templates list needs, assembled **inside** the actor in a fixed number of
    /// fetches.
    ///
    /// Replaces a `1 + T + 2TE` query pattern — per template a fetch for its exercises, then per
    /// exercise a fetch for its sets *and* a fetch for the `Exercise` — which was 426 actor hops at
    /// 25 templates × 8 exercises, on every appearance and every pull-to-refresh.
    ///
    /// Returns value types rather than `@Model` objects for the same reason `exportBackup` does:
    /// faulting dozens of properties off models handed across an actor boundary is the crash class in
    /// SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md.
    func fetchTemplateListRows() async throws -> [TemplateListRow]

    // MARK: - Atomic whole-template writes

    /// Replace every exercise and set belonging to a template in a **single commit**.
    ///
    /// The previous sequence — `deleteTemplateExercises` (which committed) followed by a `save()` per
    /// inserted row — left a window where the template was alive with zero exercises. A throw, crash or
    /// background kill inside that window destroyed the user's template with nothing to recover it.
    /// See TEMPLATES_IMPLEMENTATION_PLAN.md D2.
    func replaceTemplateContents(templateId: UUID, exercises: [TemplateSaveExercise]) async throws

    /// Delete a template together with all its exercises and sets in a **single commit**.
    /// Same window as `replaceTemplateContents`, same fix.
    func deleteTemplateAndContents(templateId: UUID) async throws

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
