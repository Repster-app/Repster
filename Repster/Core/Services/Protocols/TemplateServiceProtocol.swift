// TemplateServiceProtocol.swift
// Contract for workout template management.
// Handles CRUD for templates, starting workouts from templates,
// and creating templates from completed workouts.

import Foundation

/// Lightweight DTO for template list display (avoids exposing SwiftData models to views).
struct TemplateSummary: Identifiable, Sendable {
    let id: UUID
    let name: String
    let notes: String?
    let folder: String?
    let exerciseCount: Int
    let totalSetCount: Int
    let muscleGroups: [String]
    let lastUsedAt: Date?
    let createdAt: Date
    /// Drives the link glyph on the row, so a supersetted session is legible before you open it.
    var hasSuperset: Bool = false
}

/// One template's list-facing facts, computed inside the repository actor.
/// `exerciseIds` is in template order so the service can resolve muscle groups without another fetch.
struct TemplateListRow: Sendable {
    let id: UUID
    let name: String
    let notes: String?
    let folder: String?
    let lastUsedAt: Date?
    let createdAt: Date
    let exerciseCount: Int
    let totalSetCount: Int
    let exerciseIds: [UUID]
    let hasSuperset: Bool
}

/// Full template detail including all exercises and sets.
struct TemplateDetail: Sendable {
    let template: TemplateSummary
    let exercises: [TemplateExerciseDetail]
}

/// A single exercise within a template, with its sets.
struct TemplateExerciseDetail: Identifiable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String
    let primaryMuscle: String?
    let orderInTemplate: Int
    let supersetGroupId: UUID?
    let restTimeSeconds: Int?
    let notes: String?
    let sets: [TemplateSetDetail]
}

/// A single set prescription within a template exercise.
struct TemplateSetDetail: Identifiable, Sendable {
    let id: UUID
    let setType: SetType
    let targetRepMin: Int?
    let targetRepMax: Int?
    let targetRIR: Int?
    let orderInExercise: Int
}

/// Data needed to save or update a template from the editor.
struct TemplateSaveData: Sendable {
    let name: String
    let notes: String?
    let folder: String?
    let exercises: [TemplateSaveExercise]

    init(name: String, notes: String?, folder: String? = nil, exercises: [TemplateSaveExercise]) {
        self.name = name
        self.notes = notes
        self.folder = TemplateFolder.normalized(folder)
        self.exercises = exercises
    }
}

/// Folder names are user-authored text, so they need one normalisation rule and one comparison rule.
enum TemplateFolder {
    /// Trim, and treat whitespace-only as "no folder" so an empty field never creates a ghost folder.
    static func normalized(_ folder: String?) -> String? {
        guard let folder else { return nil }
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Group key. "Deload" and "deload" are one folder; the first spelling seen supplies the display name.
    static func groupingKey(_ folder: String?) -> String? {
        normalized(folder)?.lowercased()
    }
}

struct TemplateSaveExercise: Sendable {
    let exerciseId: UUID
    let orderInTemplate: Int
    let supersetGroupId: UUID?
    let restTimeSeconds: Int?
    let notes: String?
    let sets: [TemplateSaveSet]
}

struct TemplateSaveSet: Sendable {
    let setType: SetType
    let targetRepMin: Int?
    let targetRepMax: Int?
    let targetRIR: Int?
    let orderInExercise: Int
}

/// Versioned archive payload for template import/export.
struct TemplateArchive: Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let template: TemplateArchiveTemplate
    let exercises: [TemplateArchiveExercise]
}

struct TemplateArchiveTemplate: Codable, Sendable {
    let id: UUID
    let name: String
    let notes: String?
    /// Absent in archives written before folders existed; decodes as nil, which is "Not in a folder".
    let folder: String?

    init(id: UUID, name: String, notes: String?, folder: String? = nil) {
        self.id = id
        self.name = name
        self.notes = notes
        self.folder = folder
    }
}

struct TemplateArchiveExercise: Codable, Sendable {
    let exercise: TemplateArchiveExerciseMetadata
    let orderInTemplate: Int
    let supersetGroupId: UUID?
    let restTimeSeconds: Int?
    let notes: String?
    let sets: [TemplateArchiveSet]
}

struct TemplateArchiveExerciseMetadata: Codable, Sendable {
    let id: UUID
    let name: String
    let equipmentType: EquipmentType
    let trackingType: TrackingType
    let primaryMuscle: String?
    let secondaryMuscles: [String]
    let movementPattern: MovementPattern?
    let unilateral: Bool
    let unilateralRepTargetMode: UnilateralRepTargetMode?
    let bilateralLoadFactor: Double?
    let bodyweightFactor: Double
    let weightIncrement: Double?
    let defaultRestTime: Int?
    let fatigueRate: Double?
    let recoveryConstant: Double?
}

struct TemplateArchiveSet: Codable, Sendable {
    let setType: SetType
    let targetRepMin: Int?
    let targetRepMax: Int?
    let targetRIR: Int?
    let orderInExercise: Int
}

enum TemplateImportSource: String, Sendable {
    case templateArchive
}

enum TemplateExerciseMatchMethod: String, Sendable {
    case exerciseId
    case normalizedName
    case manualMapping
    case createNew
}

struct TemplateImportMatchedExercise: Identifiable, Sendable {
    let id: UUID
    let name: String
    let method: TemplateExerciseMatchMethod
}

struct TemplateImportExercisePreview: Identifiable, Sendable {
    let id: UUID
    let proposedExerciseId: UUID
    let exercise: TemplateArchiveExerciseMetadata
    let orderInTemplate: Int
    let supersetGroupKey: String?
    let restTimeSeconds: Int?
    let notes: String?
    let sets: [TemplateArchiveSet]
    let matchedExercise: TemplateImportMatchedExercise?
}

struct TemplateImportPreview: Sendable {
    let source: TemplateImportSource
    let templateName: String
    let notes: String?
    let folder: String?
    let exercises: [TemplateImportExercisePreview]

    var unresolvedExercises: [TemplateImportExercisePreview] {
        exercises.filter { $0.matchedExercise == nil }
    }

    var resolvedExercises: [TemplateImportExercisePreview] {
        exercises.filter { $0.matchedExercise != nil }
    }
}

enum TemplateImportResolutionAction: String, Sendable {
    case mapToExisting
    case createNew
}

struct TemplateImportExerciseResolution: Sendable {
    let previewExerciseId: UUID
    let action: TemplateImportResolutionAction
    let existingExerciseId: UUID?

    init(
        previewExerciseId: UUID,
        action: TemplateImportResolutionAction,
        existingExerciseId: UUID? = nil
    ) {
        self.previewExerciseId = previewExerciseId
        self.action = action
        self.existingExerciseId = existingExerciseId
    }
}

/// TemplateService owns all template operations.
///
/// Responsibilities:
/// - CRUD for templates (create, read, update, delete)
/// - Start a workout from a template (creates Workout + WorkoutSets with targets)
/// - Create a template from a completed workout's structure
protocol TemplateServiceProtocol: Sendable {

    // MARK: - Template CRUD

    /// Fetch all templates as lightweight summaries, sorted by lastUsedAt DESC then createdAt DESC.
    func fetchAllTemplates() async throws -> [TemplateSummary]

    /// Fetch full template detail including exercises and sets.
    func fetchTemplateDetail(_ templateId: UUID) async throws -> TemplateDetail?

    /// Create a new template from the editor data.
    /// Returns the created template's ID.
    func createTemplate(_ data: TemplateSaveData) async throws -> UUID

    /// Update an existing template with new editor data.
    /// Replaces all exercises and sets (delete-and-recreate strategy).
    func updateTemplate(_ templateId: UUID, data: TemplateSaveData) async throws

    /// Delete a template and all its exercises and sets.
    func deleteTemplate(_ templateId: UUID) async throws

    /// Copy a template, its exercises, its sets, its folder and its superset groups under a new name.
    /// Returns the new template's ID.
    func duplicateTemplate(_ templateId: UUID) async throws -> UUID

    // MARK: - Start Workout from Template

    /// Create a new Workout from a template's structure.
    /// Creates WorkoutSets with targets (targetRepMin, targetRepMax, targetRIR) from the template.
    /// Updates the template's lastUsedAt timestamp.
    /// Returns the created Workout.
    func startWorkoutFromTemplate(_ templateId: UUID, options: WorkoutStartOptions) async throws -> Workout

    // MARK: - Save as Template from Workout

    /// Create a template from a completed workout's exercise/set structure.
    /// Copies exercises, set types, and set counts. Does NOT copy weights.
    /// Returns the created template's ID.
    func createTemplateFromWorkout(_ workoutId: UUID, name: String) async throws -> UUID

    // MARK: - Import / Export

    /// Export a single template as a versioned archive payload.
    func exportTemplate(_ templateId: UUID) async throws -> Data

    /// Preview a template import without mutating stored templates or exercises.
    /// Supports native `.repstertemplate` archives and legacy `.reppotemplate` archives.
    func previewTemplateImport(data: Data) async throws -> TemplateImportPreview

    /// Finalize a previewed template import after all unresolved exercises have explicit resolutions.
    func finalizeTemplateImport(
        _ preview: TemplateImportPreview,
        resolutions: [TemplateImportExerciseResolution]
    ) async throws -> UUID

    /// Import a single template archive and return the created template ID.
    /// This convenience path only succeeds when every exercise resolves automatically.
    func importTemplate(data: Data) async throws -> UUID
}

extension TemplateServiceProtocol {
    func startWorkoutFromTemplate(_ templateId: UUID) async throws -> Workout {
        try await startWorkoutFromTemplate(templateId, options: .default)
    }
}
