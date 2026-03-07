// ExportViewModel.swift
// ViewModel for CSV export flow.
// Spec: FR-001 through FR-009
// Feature: 011-csv-import-export WP04 T020

import Foundation

@Observable @MainActor
final class ExportViewModel {

    // MARK: - State

    var isExporting = false
    var exportData: Data?
    var errorMessage: String?

    // MARK: - Dependencies

    private let exportService: any ExportServiceProtocol

    // MARK: - Init

    init(exportService: any ExportServiceProtocol) {
        self.exportService = exportService
    }

    // MARK: - Actions

    func generateExport() {
        isExporting = true
        errorMessage = nil

        Task {
            do {
                let data = try await exportService.exportCSV()
                self.exportData = data
                self.isExporting = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isExporting = false
            }
        }
    }

    func reset() {
        exportData = nil
        errorMessage = nil
        isExporting = false
    }
}
