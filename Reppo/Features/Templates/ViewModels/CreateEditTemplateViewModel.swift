// CreateEditTemplateViewModel.swift
// ViewModel for creating or editing a workout template.
// Manages in-memory editor state (exercises, sets, superset groups, etc.)
// and persists via TemplateService on save.

import SwiftUI

// MARK: - Editor State Types

/// In-memory representation of an exercise in the template editor.
struct EditorExercise: Identifiable {
    let id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var primaryMuscle: String?
    var sets: [EditorSet]
    var supersetGroupId: UUID?
    var restTimeSeconds: Int?
    var notes: String?
    var isExpanded: Bool = false
}

/// In-memory representation of a set in the template editor.
struct EditorSet: Identifiable {
    let id: UUID
    var setType: SetType
    var targetRepMin: Int?
    var targetRepMax: Int?
    var targetRIR: Int?
}

// MARK: - ViewModel

@Observable
@MainActor
final class CreateEditTemplateViewModel {

    // MARK: - State

    var templateName: String = ""
    var templateNotes: String? = nil
    var exercises: [EditorExercise] = []
    var isLoading: Bool = false
    var isSaving: Bool = false
    var showExercisePicker: Bool = false

    /// If non-nil, we're editing an existing template. Otherwise creating new.
    var editingTemplateId: UUID? = nil

    // MARK: - Superset Colors

    /// Maps superset group UUIDs to color labels (A, B, C).
    private var supersetGroupLabels: [UUID: String] = [:]
    private let supersetLetters = ["A", "B", "C", "D", "E"]

    // MARK: - Dependencies

    private let templateService: TemplateServiceProtocol
    private let exerciseService: ExerciseServiceProtocol

    init(
        templateService: TemplateServiceProtocol,
        exerciseService: ExerciseServiceProtocol,
        editingTemplateId: UUID? = nil
    ) {
        self.templateService = templateService
        self.exerciseService = exerciseService
        self.editingTemplateId = editingTemplateId
    }

    // MARK: - Computed

    var canSave: Bool {
        !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !exercises.isEmpty
    }

    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    // MARK: - Loading

    func loadIfEditing() async {
        guard let templateId = editingTemplateId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            guard let detail = try await templateService.fetchTemplateDetail(templateId) else { return }

            templateName = detail.template.name
            templateNotes = detail.template.notes

            exercises = detail.exercises.map { ex in
                // Track superset groups
                if let groupId = ex.supersetGroupId {
                    if supersetGroupLabels[groupId] == nil {
                        let nextIndex = supersetGroupLabels.count
                        if nextIndex < supersetLetters.count {
                            supersetGroupLabels[groupId] = supersetLetters[nextIndex]
                        }
                    }
                }

                return EditorExercise(
                    id: ex.id,
                    exerciseId: ex.exerciseId,
                    exerciseName: ex.exerciseName,
                    primaryMuscle: ex.primaryMuscle,
                    sets: ex.sets.map { s in
                        EditorSet(
                            id: s.id,
                            setType: s.setType,
                            targetRepMin: s.targetRepMin,
                            targetRepMax: s.targetRepMax,
                            targetRIR: s.targetRIR
                        )
                    },
                    supersetGroupId: ex.supersetGroupId,
                    restTimeSeconds: ex.restTimeSeconds,
                    notes: ex.notes
                )
            }
        } catch {
            print("[CreateEditTemplateViewModel] Failed to load template: \(error)")
        }
    }

    // MARK: - Save

    func save() async throws {
        isSaving = true
        defer { isSaving = false }

        let data = buildSaveData()

        if let templateId = editingTemplateId {
            try await templateService.updateTemplate(templateId, data: data)
        } else {
            _ = try await templateService.createTemplate(data)
        }
    }

    private func buildSaveData() -> TemplateSaveData {
        let exerciseSaveData: [TemplateSaveExercise] = exercises.enumerated().map { index, exercise in
            let setSaveData: [TemplateSaveSet] = exercise.sets.enumerated().map { setIndex, set in
                TemplateSaveSet(
                    setType: set.setType,
                    targetRepMin: set.targetRepMin,
                    targetRepMax: set.targetRepMax,
                    targetRIR: set.targetRIR,
                    orderInExercise: setIndex + 1
                )
            }

            return TemplateSaveExercise(
                exerciseId: exercise.exerciseId,
                orderInTemplate: index + 1,
                supersetGroupId: exercise.supersetGroupId,
                restTimeSeconds: exercise.restTimeSeconds,
                notes: exercise.notes?.isEmpty == true ? nil : exercise.notes,
                sets: setSaveData
            )
        }

        return TemplateSaveData(
            name: templateName.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: templateNotes?.isEmpty == true ? nil : templateNotes,
            exercises: exerciseSaveData
        )
    }

    // MARK: - Exercise Operations

    func addExercises(_ exerciseIds: [UUID]) async {
        for exerciseId in exerciseIds {
            do {
                guard let exercise = try await exerciseService.fetchExercise(exerciseId) else { continue }

                // Auto-add a default working set so the exercise isn't empty
                let defaultSet = EditorSet(
                    id: UUID(),
                    setType: .working,
                    targetRepMin: nil,
                    targetRepMax: nil,
                    targetRIR: nil
                )

                let editorExercise = EditorExercise(
                    id: UUID(),
                    exerciseId: exerciseId,
                    exerciseName: exercise.name,
                    primaryMuscle: exercise.primaryMuscle,
                    sets: [defaultSet],
                    restTimeSeconds: exercise.defaultRestTime,
                    isExpanded: exercises.isEmpty // Expand if first exercise
                )

                exercises.append(editorExercise)
            } catch {
                print("[CreateEditTemplateViewModel] Failed to add exercise: \(error)")
            }
        }
    }

    func removeExercise(at index: Int) {
        guard index >= 0, index < exercises.count else { return }
        exercises.remove(at: index)
    }

    func moveExercise(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
    }

    func toggleExpanded(at index: Int) {
        guard index >= 0, index < exercises.count else { return }
        exercises[index].isExpanded.toggle()
    }

    // MARK: - Set Operations

    func addWorkingSet(to exerciseIndex: Int) {
        guard exerciseIndex >= 0, exerciseIndex < exercises.count else { return }
        let newSet = EditorSet(id: UUID(), setType: .working, targetRepMin: nil, targetRepMax: nil, targetRIR: nil)
        exercises[exerciseIndex].sets.append(newSet)
    }

    func addWarmupSet(to exerciseIndex: Int) {
        guard exerciseIndex >= 0, exerciseIndex < exercises.count else { return }

        // Insert before first non-warmup
        let insertIndex = exercises[exerciseIndex].sets.firstIndex(where: { $0.setType != .warmup })
            ?? exercises[exerciseIndex].sets.count

        let newSet = EditorSet(id: UUID(), setType: .warmup, targetRepMin: nil, targetRepMax: nil, targetRIR: nil)
        exercises[exerciseIndex].sets.insert(newSet, at: insertIndex)
    }

    func duplicateSet(exerciseIndex: Int, setIndex: Int) {
        guard exerciseIndex >= 0, exerciseIndex < exercises.count,
              setIndex >= 0, setIndex < exercises[exerciseIndex].sets.count else { return }
        let source = exercises[exerciseIndex].sets[setIndex]
        let copy = EditorSet(
            id: UUID(),
            setType: source.setType,
            targetRepMin: source.targetRepMin,
            targetRepMax: source.targetRepMax,
            targetRIR: source.targetRIR
        )
        exercises[exerciseIndex].sets.insert(copy, at: setIndex + 1)
    }

    func removeSet(exerciseIndex: Int, setIndex: Int) {
        guard exerciseIndex >= 0, exerciseIndex < exercises.count,
              setIndex >= 0, setIndex < exercises[exerciseIndex].sets.count else { return }
        exercises[exerciseIndex].sets.remove(at: setIndex)
    }

    // MARK: - Superset Operations

    func supersetLabel(for groupId: UUID?) -> String? {
        guard let groupId else { return nil }
        return supersetGroupLabels[groupId]
    }

    func supersetColor(for groupId: UUID?) -> Color {
        guard let groupId, let label = supersetGroupLabels[groupId] else { return .textTertiary }
        switch label {
        case "A": return .accent
        case "B": return .chart5
        case "C": return .chart7
        case "D": return .chart8
        default: return .textTertiary
        }
    }

    func setSupersetGroup(for exerciseIndex: Int, label: String?) {
        guard exerciseIndex >= 0, exerciseIndex < exercises.count else { return }

        if let label {
            // Find existing group with this label, or create new
            let existingGroupId = supersetGroupLabels.first(where: { $0.value == label })?.key
            let groupId = existingGroupId ?? UUID()

            if existingGroupId == nil {
                supersetGroupLabels[groupId] = label
            }

            exercises[exerciseIndex].supersetGroupId = groupId
        } else {
            exercises[exerciseIndex].supersetGroupId = nil
        }
    }

    func currentSupersetLabel(for exerciseIndex: Int) -> String? {
        guard exerciseIndex >= 0, exerciseIndex < exercises.count else { return nil }
        return supersetLabel(for: exercises[exerciseIndex].supersetGroupId)
    }
}
