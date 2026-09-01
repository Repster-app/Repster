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

    /// One template's whole contents, assembled **inside** the actor in three fetches.
    ///
    /// Same reason as `fetchTemplateListRows`, and more urgent: the caller previously read
    /// `templateExercise.id` off a `@Model` on its own actor and used it to look up that exercise's
    /// sets. Returns nil when the template does not exist.
    func fetchTemplateDetailRows(templateId: UUID) async throws -> TemplateDetailRows?

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

    /// Move a template between folders without touching its contents.
    ///
    /// Filing a template used to go through `replaceTemplateContents`: the caller read the whole
    /// detail and pushed it back to change one nullable string, deleting and recreating every
    /// exercise and set with new ids and fresh timestamps. The round trip was correct, but a gesture
    /// that changes a label has no business running the most destructive write in the feature — and
    /// it is what made per-row timestamps useless as evidence.
    ///
    /// The mutation happens **inside** the actor, so no `@Model` is edited across a context boundary.
    func updateTemplateFolder(templateId: UUID, folder: String?) async throws

    /// Remove every template reference to an exercise that is being deleted, in a **single commit**.
    ///
    /// `ExerciseService.deleteExercise` called itself a full cascade and was not one: it cleared
    /// sets, stats, PRs and fatigue rows, then left `TemplateExercise` rows pointing at an id that no
    /// longer resolves. Those render as "Unknown Exercise" forever, still count toward the template's
    /// set total, and nothing in the app explains where they came from.
    ///
    /// Surviving exercises are renumbered so `orderInTemplate` has no gap, and a superset left with a
    /// single member is dissolved — a group of one is the state SUPERSETS_SCOPING.md §6 exists to
    /// prevent.
    ///
    /// Returns the number of template exercise rows removed.
    @discardableResult
    func deleteTemplateReferences(toExerciseId exerciseId: UUID) async throws -> Int

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
