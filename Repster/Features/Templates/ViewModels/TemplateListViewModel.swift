// TemplateListViewModel.swift
// ViewModel for the template selection sheet shown from StartWorkoutSheet.
// Loads template summaries and handles starting a workout from a template.

import SwiftUI

// MARK: - List shaping

/// One folder chip in the filter row. `All` is represented by `id == TemplateFolderChip.allID`.
struct TemplateFolderChip: Identifiable, Equatable {
    static let allID = "__all__"

    let id: String
    let name: String
    let count: Int

    var isAll: Bool { id == Self.allID }
}

/// A run of templates under one heading. `title` is nil when a folder is selected — every row already
/// belongs to the chip the user just tapped, so a header would only repeat it.
struct TemplateSection: Identifiable, Equatable {
    let id: String
    let title: String?
    let templates: [TemplateSummary]

    var count: Int { templates.count }
}

extension TemplateSummary: Equatable {
    static func == (lhs: TemplateSummary, rhs: TemplateSummary) -> Bool { lhs.id == rhs.id }
}

/// Pure filtering and grouping for the templates list.
///
/// Deliberately not on the view model: this is where the rules live that the design argued about
/// (folders order by recency, ungrouped always last, case-folded names are one folder), and keeping
/// it free of the service and the main actor makes each of those a one-line test.
enum TemplateListGrouping {

    static let ungroupedID = "__ungrouped__"
    static let ungroupedTitle = "Not in a folder"

    /// `All` first, then folders ordered exactly as `sections` orders them, so the chip row and the
    /// grouped list agree. Templates with no folder never get a chip — they are reachable via `All`.
    static func chips(for templates: [TemplateSummary]) -> [TemplateFolderChip] {
        guard !templates.isEmpty else { return [] }

        var chips: [TemplateFolderChip] = [
            TemplateFolderChip(id: TemplateFolderChip.allID, name: "All", count: templates.count)
        ]

        for key in orderedFolderKeys(for: templates) {
            let inFolder = templates.filter { TemplateFolder.groupingKey($0.folder) == key }
            guard let displayName = inFolder.first?.folder else { continue }
            chips.append(TemplateFolderChip(id: key, name: displayName, count: inFolder.count))
        }

        return chips
    }

    /// One section per folder when nothing is selected; a single untitled section when one is.
    static func sections(
        for templates: [TemplateSummary],
        selectedFolderID: String?,
        searchText: String
    ) -> [TemplateSection] {
        let matching = filtered(templates, searchText: searchText)

        if let selectedFolderID, selectedFolderID != TemplateFolderChip.allID {
            let inFolder = matching.filter { folderID(for: $0) == selectedFolderID }
            guard !inFolder.isEmpty else { return [] }
            return [TemplateSection(id: selectedFolderID, title: nil, templates: inFolder)]
        }

        var sections: [TemplateSection] = []
        for key in orderedFolderKeys(for: matching) {
            let inFolder = matching.filter { TemplateFolder.groupingKey($0.folder) == key }
            guard let displayName = inFolder.first?.folder else { continue }
            sections.append(TemplateSection(id: key, title: displayName, templates: inFolder))
        }

        let ungrouped = matching.filter { $0.folder == nil }
        if !ungrouped.isEmpty {
            // Always last, and always shown: every template starts here, so it is the resting state
            // rather than an error state.
            sections.append(TemplateSection(id: ungroupedID, title: ungroupedTitle, templates: ungrouped))
        }

        return sections
    }

    static func folderID(for template: TemplateSummary) -> String {
        TemplateFolder.groupingKey(template.folder) ?? ungroupedID
    }

    // MARK: - Internals

    /// Folders order by their most recently used template, matching how the list itself sorts, then
    /// by name so an all-unused library is still stable rather than arbitrary.
    private static func orderedFolderKeys(for templates: [TemplateSummary]) -> [String] {
        var lastUsedByKey: [String: Date] = [:]
        var nameByKey: [String: String] = [:]

        for template in templates {
            guard let key = TemplateFolder.groupingKey(template.folder), let name = template.folder else { continue }
            if nameByKey[key] == nil { nameByKey[key] = name }
            let candidate = template.lastUsedAt ?? .distantPast
            if candidate > (lastUsedByKey[key] ?? .distantPast) {
                lastUsedByKey[key] = candidate
            }
        }

        return nameByKey.keys.sorted { lhs, rhs in
            let lhsDate = lastUsedByKey[lhs] ?? .distantPast
            let rhsDate = lastUsedByKey[rhs] ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return (nameByKey[lhs] ?? "").localizedCaseInsensitiveCompare(nameByKey[rhs] ?? "") == .orderedAscending
        }
    }

    /// Name and folder both match, so searching "deload" finds a Deload folder's templates by name
    /// even when the folder is not the selected chip.
    private static func filtered(_ templates: [TemplateSummary], searchText: String) -> [TemplateSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return templates }
        return templates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.folder?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}

@Observable
@MainActor
final class TemplateListViewModel {

    // MARK: - State

    var templates: [TemplateSummary] = []
    var searchText: String = ""
    /// nil or `TemplateFolderChip.allID` both mean "All"; the grouped view is the fallback.
    var selectedFolderID: String? = nil
    var isLoading: Bool = false
    var showCreateTemplate: Bool = false
    var editingTemplateId: UUID? = nil
    var showDeleteConfirmation: Bool = false
    var templateToDelete: UUID? = nil

    // MARK: - Dependencies

    private let templateService: TemplateServiceProtocol

    init(templateService: TemplateServiceProtocol) {
        self.templateService = templateService
    }

    // MARK: - Derived list state

    var folderChips: [TemplateFolderChip] {
        TemplateListGrouping.chips(for: templates)
    }

    var sections: [TemplateSection] {
        TemplateListGrouping.sections(
            for: templates,
            selectedFolderID: selectedFolderID,
            searchText: searchText
        )
    }

    /// Only worth showing when there is something to filter.
    var showsFolderChips: Bool {
        folderChips.count > 2
    }

    var showsSearchField: Bool {
        templates.count >= 6 || !searchText.isEmpty
    }

    var hasNoMatches: Bool {
        !templates.isEmpty && sections.isEmpty
    }

    // MARK: - Data Loading

    func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }

        do {
            templates = try await templateService.fetchAllTemplates()
            // A folder that no longer exists — its last template moved or was deleted — would
            // otherwise leave the list filtered to nothing with no way back.
            if let selectedFolderID, !folderChips.contains(where: { $0.id == selectedFolderID }) {
                self.selectedFolderID = nil
            }
        } catch {
            dbg("[TemplateListViewModel] Failed to load templates: \(error)")
            templates = []
        }
    }

    // MARK: - Actions

    func startWorkoutFromTemplate(_ templateId: UUID, options: WorkoutStartOptions) async throws -> Workout {
        let workout = try await templateService.startWorkoutFromTemplate(templateId, options: options)
        return workout
    }

    /// Re-file a template without opening the editor. Reads the current detail so the move rewrites
    /// only the folder — everything else round-trips exactly as stored.
    func setFolder(_ folder: String?, for templateId: UUID) async throws {
        guard let detail = try await templateService.fetchTemplateDetail(templateId) else { return }
        try await templateService.updateTemplate(
            templateId,
            data: TemplateSaveData(
                name: detail.template.name,
                notes: detail.template.notes,
                folder: folder,
                exercises: detail.exercises.map { exercise in
                    TemplateSaveExercise(
                        exerciseId: exercise.exerciseId,
                        orderInTemplate: exercise.orderInTemplate,
                        supersetGroupId: exercise.supersetGroupId,
                        restTimeSeconds: exercise.restTimeSeconds,
                        notes: exercise.notes,
                        sets: exercise.sets.map {
                            TemplateSaveSet(
                                setType: $0.setType,
                                targetRepMin: $0.targetRepMin,
                                targetRepMax: $0.targetRepMax,
                                targetRIR: $0.targetRIR,
                                orderInExercise: $0.orderInExercise
                            )
                        }
                    )
                }
            )
        )
        await loadTemplates()
    }

    func duplicateTemplate(_ templateId: UUID) async throws -> UUID {
        let newId = try await templateService.duplicateTemplate(templateId)
        await loadTemplates()
        return newId
    }

    func exportTemplate(_ templateId: UUID) async throws -> Data {
        try await templateService.exportTemplate(templateId)
    }

    func previewTemplateImport(data: Data) async throws -> TemplateImportPreview {
        try await templateService.previewTemplateImport(data: data)
    }

    func finalizeTemplateImport(
        _ preview: TemplateImportPreview,
        resolutions: [TemplateImportExerciseResolution]
    ) async throws -> UUID {
        try await templateService.finalizeTemplateImport(preview, resolutions: resolutions)
    }

    func importTemplate(data: Data) async throws -> UUID {
        try await templateService.importTemplate(data: data)
    }

    func deleteTemplate(_ templateId: UUID) async {
        do {
            try await templateService.deleteTemplate(templateId)
            templates.removeAll { $0.id == templateId }
        } catch {
            dbg("[TemplateListViewModel] Failed to delete template: \(error)")
        }
    }

    func confirmDelete(_ templateId: UUID) {
        templateToDelete = templateId
        showDeleteConfirmation = true
    }

    func performDelete() async {
        guard let id = templateToDelete else { return }
        await deleteTemplate(id)
        templateToDelete = nil
        showDeleteConfirmation = false
    }

    func cancelDelete() {
        templateToDelete = nil
        showDeleteConfirmation = false
    }
}
