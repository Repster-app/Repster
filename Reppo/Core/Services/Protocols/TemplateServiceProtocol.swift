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
    let exerciseCount: Int
    let totalSetCount: Int
    let muscleGroups: [String]
    let lastUsedAt: Date?
    let createdAt: Date
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
    let exercises: [TemplateSaveExercise]
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

    // MARK: - Start Workout from Template

    /// Create a new Workout from a template's structure.
    /// Creates WorkoutSets with targets (targetRepMin, targetRepMax, targetRIR) from the template.
    /// Updates the template's lastUsedAt timestamp.
    /// Returns the created Workout.
    func startWorkoutFromTemplate(_ templateId: UUID) async throws -> Workout

    // MARK: - Save as Template from Workout

    /// Create a template from a completed workout's exercise/set structure.
    /// Copies exercises, set types, and set counts. Does NOT copy weights.
    /// Returns the created template's ID.
    func createTemplateFromWorkout(_ workoutId: UUID, name: String) async throws -> UUID
}
