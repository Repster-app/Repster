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

/// A pairing option in the "Superset with…" sheet.
struct SupersetCandidate: Identifiable {
    let id: UUID
    let index: Int
    let name: String
    let setSummary: String
    /// Non-nil when this exercise is already in a group, which makes the row unselectable.
    let existingGroupLabel: String?
    let wouldMove: Bool
    let subjectName: String

    var isSelectable: Bool { existingGroupLabel == nil }

    var detailText: String {
        if let existingGroupLabel {
            return "Already in Superset \(existingGroupLabel)"
        }
        if wouldMove {
            return "Moves up to sit next to \(subjectName)"
        }
        return setSummary
    }
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
    var templateFolder: String? = nil
    var exercises: [EditorExercise] = []
    var isLoading: Bool = false
    var isSaving: Bool = false
    var showExercisePicker: Bool = false

    /// If non-nil, we're editing an existing template. Otherwise creating new.
    var editingTemplateId: UUID? = nil

    // MARK: - Superset Colors

    /// Maps superset group UUIDs to color labels (A, B, C).
    private var supersetGroupLabels: [UUID: String] = [:]
    /// Group letters offered in the editor.
    ///
    /// The letter is the identity; colour is only reinforcement, so this is the single limit —
    /// `supersetColor` cycles rather than capping. Wanting more is a change to this array and
    /// nothing else. See SUPERSETS_SCOPING.md §6.
    let supersetLetters = ["A", "B", "C", "D", "E"]

    // MARK: - Dependencies

    private let templateService: TemplateServiceProtocol
    private let exerciseService: ExerciseServiceProtocol
    private let analyticsService: any AnalyticsServiceProtocol

    init(
        templateService: TemplateServiceProtocol,
        exerciseService: ExerciseServiceProtocol,
        editingTemplateId: UUID? = nil,
        analyticsService: any AnalyticsServiceProtocol = NoopAnalyticsService()
    ) {
        self.templateService = templateService
        self.exerciseService = exerciseService
        self.editingTemplateId = editingTemplateId
        self.analyticsService = analyticsService
    }

    /// Re-initializes editor state for the current presentation and loads template data if editing.
    func prepareForPresentation(editingTemplateId: UUID?) async {
        self.editingTemplateId = editingTemplateId
        resetEditorState()
        await loadIfEditing()
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
            guard let detail = try await fetchTemplateDetailWithRetry(templateId) else { return }
            applyTemplateDetail(detail)
        } catch {
            dbg("[CreateEditTemplateViewModel] Failed to load template: \(error)")
        }
    }

    private func fetchTemplateDetailWithRetry(_ templateId: UUID) async throws -> TemplateDetail? {
        let firstResult = try await templateService.fetchTemplateDetail(templateId)
        if let firstResult, !firstResult.exercises.isEmpty {
            return firstResult
        }

        // Guard against transient empty reads when opening editor immediately after sheet transition.
        try? await Task.sleep(for: .milliseconds(120))
        return try await templateService.fetchTemplateDetail(templateId)
    }

    private func applyTemplateDetail(_ detail: TemplateDetail) {
        templateName = detail.template.name
        templateNotes = detail.template.notes
        templateFolder = detail.template.folder

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
    }

    private func resetEditorState() {
        templateName = ""
        templateNotes = nil
        templateFolder = nil
        exercises = []
        supersetGroupLabels = [:]
    }

    // MARK: - Save

    func save() async throws {
        isSaving = true
        defer { isSaving = false }

        let data = buildSaveData()

        if let templateId = editingTemplateId {
            try await templateService.updateTemplate(templateId, data: data)
            analyticsService.templateEdited(
                exerciseCount: exercises.count,
                inFolder: data.folder != nil
            )
        } else {
            _ = try await templateService.createTemplate(data)
            // Building a template is a commitment signal — it means the user
            // intends to come back and repeat this session.
            analyticsService.templateCreated(
                exerciseCount: exercises.count,
                source: "create_template_form"
            )
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
            folder: templateFolder,
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
                dbg("[CreateEditTemplateViewModel] Failed to add exercise: \(error)")
            }
        }
    }

    /// By id, not position. The card that renders these buttons captured its index when it was built,
    /// and `moveExercise` mutates the array on every `dropEntered` during a drag — so a tap arriving
    /// after a reorder acted on whatever had moved into that slot.
    func removeExercise(id: UUID) {
        exercises.removeAll { $0.id == id }
    }

    func moveExercise(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
    }

    func moveExercise(draggedExerciseId: UUID, toDropTargetExerciseId targetExerciseId: UUID) {
        guard draggedExerciseId != targetExerciseId,
              let sourceIndex = exercises.firstIndex(where: { $0.id == draggedExerciseId }),
              let targetIndex = exercises.firstIndex(where: { $0.id == targetExerciseId }) else { return }

        let draggedExercise = exercises.remove(at: sourceIndex)
        if targetIndex >= exercises.count {
            exercises.append(draggedExercise)
            return
        }

        let adjustedTargetIndex = sourceIndex < targetIndex ? max(targetIndex - 1, 0) : targetIndex
        exercises.insert(draggedExercise, at: adjustedTargetIndex)
    }

    func toggleExpanded(id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        exercises[index].isExpanded.toggle()
    }

    // MARK: - Identity-addressed set edits

    /// Mutate a set by **id**, never by position.
    ///
    /// The editor's rows capture `exerciseIndex` / `setIndex` when they render, and the array moves
    /// underneath them: drag-reorder mutates it on every `dropEntered`, and pairing a non-adjacent
    /// superset partner moves an exercise outright. A row whose `onChange` fires after either one
    /// would write into whatever now sits at its old index — a different exercise's set.
    func updateSet(exerciseId: UUID, setId: UUID, _ mutate: (inout EditorSet) -> Void) {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else { return }
        mutate(&exercises[exerciseIndex].sets[setIndex])
    }

    func duplicateSet(exerciseId: UUID, setId: UUID) {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else { return }
        let source = exercises[exerciseIndex].sets[setIndex]
        exercises[exerciseIndex].sets.insert(
            EditorSet(
                id: UUID(),
                setType: source.setType,
                targetRepMin: source.targetRepMin,
                targetRepMax: source.targetRepMax,
                targetRIR: source.targetRIR
            ),
            at: setIndex + 1
        )
    }

    func removeSet(exerciseId: UUID, setId: UUID) {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        exercises[exerciseIndex].sets.removeAll { $0.id == setId }
    }

    // MARK: - Set Operations

    func addWorkingSet(toExerciseId exerciseId: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        exercises[index].sets.append(
            EditorSet(id: UUID(), setType: .working, targetRepMin: nil, targetRepMax: nil, targetRIR: nil)
        )
    }

    func addWarmupSet(toExerciseId exerciseId: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }

        // Insert before the first non-warmup
        let insertIndex = exercises[index].sets.firstIndex(where: { $0.setType != .warmup })
            ?? exercises[index].sets.count

        exercises[index].sets.insert(
            EditorSet(id: UUID(), setType: .warmup, targetRepMin: nil, targetRepMax: nil, targetRIR: nil),
            at: insertIndex
        )
    }

    // MARK: - Superset Operations

    func supersetLabel(for groupId: UUID?) -> String? {
        guard let groupId else { return nil }
        return supersetGroupLabels[groupId]
    }

    /// Colours a group by its letter's position, cycling.
    ///
    /// Four hues, because the rest of the palette is spoken for: green means completed, red means
    /// delete, gold means PR and orange is the note-indicator dot. Five letters over four colours
    /// means E reuses A's blue, which is fine — the letters are what tell them apart, and the
    /// previous `textTertiary` fallback rendered a real group as unlabelled grey instead.
    func supersetColor(for groupId: UUID?) -> Color {
        guard let groupId, let label = supersetGroupLabels[groupId],
              let position = supersetLetters.firstIndex(of: label)
        else { return .textTertiary }
        return Self.supersetPalette[position % Self.supersetPalette.count]
    }

    private static let supersetPalette: [Color] = [.accent, .chart5, .chart7, .chart8]

    /// Exercises this one can be paired with: everything else that is not already in a group.
    ///
    /// Already-grouped exercises are returned too, flagged, so the picker can show them disabled
    /// rather than hiding them — the model stays visible instead of silently shrinking the list.
    func supersetCandidates(forExerciseId exerciseId: UUID) -> [SupersetCandidate] {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }) else { return [] }
        let subject = exercises[exerciseIndex]

        return exercises.enumerated().compactMap { index, candidate in
            guard index != exerciseIndex else { return nil }
            let partnerLabel = supersetLabel(for: candidate.supersetGroupId)
            return SupersetCandidate(
                id: candidate.id,
                index: index,
                name: candidate.exerciseName,
                setSummary: setSummary(for: candidate),
                existingGroupLabel: partnerLabel,
                // §6 constraint 1: a group must be contiguous, so a non-adjacent partner moves. The
                // picker says so on the row rather than letting it happen silently.
                wouldMove: abs(index - exerciseIndex) > 1,
                subjectName: subject.exerciseName
            )
        }
    }

    /// The letter the next group would take. The app assigns it; the user picks a partner.
    var nextSupersetLetter: String {
        let used = Set(supersetGroupLabels.values)
        return supersetLetters.first { !used.contains($0) } ?? supersetLetters[supersetGroupLabels.count % supersetLetters.count]
    }

    /// Pair two exercises into a new group, moving the partner adjacent if it is not already.
    ///
    /// Replaces a menu of letters assigned one exercise at a time. That flow needed the same letter
    /// picked twice on two different exercises with nothing saying a second step existed, and it left
    /// a group of one whenever the second step was missed. Picking a partner makes that unreachable.
    func pairExercise(exerciseId subjectId: UUID, withPartnerId partnerId: UUID) {
        guard subjectId != partnerId,
              exercises.contains(where: { $0.id == subjectId }),
              exercises.contains(where: { $0.id == partnerId }) else { return }

        let groupId = UUID()
        supersetGroupLabels[groupId] = nextSupersetLetter

        // Dissolve whatever either was in first, so nothing is left in a group of one.
        for id in [subjectId, partnerId] {
            if let index = exercises.firstIndex(where: { $0.id == id }) {
                dissolveGroup(containing: index)
            }
        }

        guard let subjectIndex = exercises.firstIndex(where: { $0.id == subjectId }),
              let currentPartnerIndex = exercises.firstIndex(where: { $0.id == partnerId }) else { return }

        exercises[subjectIndex].supersetGroupId = groupId
        exercises[currentPartnerIndex].supersetGroupId = groupId

        if currentPartnerIndex != subjectIndex + 1 {
            let partner = exercises.remove(at: currentPartnerIndex)
            let insertionIndex = (exercises.firstIndex(where: { $0.id == subjectId }) ?? subjectIndex) + 1
            exercises.insert(partner, at: min(insertionIndex, exercises.count))
        }
    }

    /// Remove an exercise from its superset, dissolving the whole group.
    ///
    /// Groups are pairs for now (§6 constraint 2), so clearing one side would leave the other in a
    /// group of one — the exact state the pairing flow exists to prevent.
    func removeFromSuperset(exerciseId: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        dissolveGroup(containing: index)
    }

    private func dissolveGroup(containing exerciseIndex: Int) {
        guard exercises.indices.contains(exerciseIndex),
              let groupId = exercises[exerciseIndex].supersetGroupId else { return }

        for index in exercises.indices where exercises[index].supersetGroupId == groupId {
            exercises[index].supersetGroupId = nil
        }
        supersetGroupLabels[groupId] = nil
    }

    /// Members of the same group, in list order, for rendering a block.
    func supersetPartners(of exerciseIndex: Int) -> [EditorExercise] {
        guard exercises.indices.contains(exerciseIndex),
              let groupId = exercises[exerciseIndex].supersetGroupId else { return [] }
        return exercises.filter { $0.supersetGroupId == groupId }
    }

    private func setSummary(for exercise: EditorExercise) -> String {
        let warmups = exercise.sets.filter { $0.setType == .warmup }.count
        let working = exercise.sets.count - warmups
        var parts: [String] = []
        if warmups > 0 { parts.append("\(warmups) warmup") }
        parts.append("\(working) working")
        return parts.joined(separator: " · ")
    }

    func currentSupersetLabel(for exerciseIndex: Int) -> String? {
        guard exerciseIndex >= 0, exerciseIndex < exercises.count else { return nil }
        return supersetLabel(for: exercises[exerciseIndex].supersetGroupId)
    }
}
