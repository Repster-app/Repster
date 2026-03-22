// TemplateListViewModel.swift
// ViewModel for the template selection sheet shown from StartWorkoutSheet.
// Loads template summaries and handles starting a workout from a template.

import SwiftUI

@Observable
@MainActor
final class TemplateListViewModel {

    // MARK: - State

    var templates: [TemplateSummary] = []
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

    // MARK: - Data Loading

    func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }

        do {
            templates = try await templateService.fetchAllTemplates()
        } catch {
            print("[TemplateListViewModel] Failed to load templates: \(error)")
            templates = []
        }
    }

    // MARK: - Actions

    func startWorkoutFromTemplate(_ templateId: UUID) async throws -> Workout {
        let workout = try await templateService.startWorkoutFromTemplate(templateId)
        return workout
    }

    func exportTemplate(_ templateId: UUID) async throws -> Data {
        try await templateService.exportTemplate(templateId)
    }

    func exportAITemplateContext() async throws -> Data {
        try await templateService.exportAITemplateContext()
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
            print("[TemplateListViewModel] Failed to delete template: \(error)")
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
