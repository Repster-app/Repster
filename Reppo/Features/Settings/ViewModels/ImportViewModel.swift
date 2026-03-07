// ImportViewModel.swift
// ViewModel for CSV import flow with state machine.
// Spec: FR-001 through FR-009
// Feature: 011-csv-import-export WP03 T011

import Foundation
import SwiftUI

@Observable @MainActor
final class ImportViewModel {

    // MARK: - State Machine

    enum ImportState {
        case idle
        case previewing
        case importing
        case rebuilding
        case completed
        case failed
    }

    // MARK: - State

    var state: ImportState = .idle
    var showFilePicker = false

    // Preview
    var previewHeaders: [String] = []
    var previewRows: [[String]] = []
    var estimatedTotalRows: Int = 0

    // Progress
    var progressFraction: Double = 0
    var progressLabel: String = ""
    var setsInserted: Int = 0
    var totalSets: Int = 0

    // Result
    var result: ImportResult?

    // Error
    var errorMessage: String?

    // MARK: - Dependencies

    private let importService: any ImportServiceProtocol
    private var importData: Data?

    // MARK: - Init

    init(importService: any ImportServiceProtocol) {
        self.importService = importService
    }

    // MARK: - File Selection

    func handleFileSelected(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            state = .failed

        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                self.importData = data

                let preview = try importService.previewCSV(data: data)
                self.previewHeaders = preview.headers
                self.previewRows = preview.sampleRows
                self.estimatedTotalRows = preview.estimatedTotalRows
                self.state = .previewing
            } catch {
                errorMessage = error.localizedDescription
                state = .failed
            }
        }
    }

    // MARK: - Import

    func confirmImport() {
        guard let data = importData else { return }

        state = .importing
        progressFraction = 0
        setsInserted = 0

        Task {
            let stream = importService.importCSV(data: data)

            for await progress in stream {
                handleProgress(progress)
            }
        }
    }

    private func handleProgress(_ progress: ImportProgress) {
        switch progress {
        case .parsing:
            progressLabel = "Parsing CSV..."
            progressFraction = 0

        case .validating(let processed, let total):
            progressLabel = "Validating row \(processed) of \(total)..."
            progressFraction = Double(processed) / Double(max(total, 1)) * 0.1
            totalSets = total

        case .importing(let inserted, let total):
            state = .importing
            progressLabel = "Importing set \(inserted) of \(total)..."
            progressFraction = 0.1 + (Double(inserted) / Double(max(total, 1)) * 0.7)
            setsInserted = inserted
            totalSets = total

        case .rebuilding(let phase):
            state = .rebuilding
            progressLabel = phase.rawValue
            progressFraction = phase == .stats ? 0.8 : 0.9

        case .completed(let result):
            self.result = result
            state = .completed
            progressFraction = 1.0

        case .failed(let error):
            errorMessage = error.localizedDescription
            state = .failed
        }
    }

    // MARK: - Reset / Retry

    func reset() {
        state = .idle
        importData = nil
        previewHeaders = []
        previewRows = []
        estimatedTotalRows = 0
        progressFraction = 0
        progressLabel = ""
        setsInserted = 0
        totalSets = 0
        result = nil
        errorMessage = nil
    }

    func retry() {
        errorMessage = nil
        state = .idle
        showFilePicker = true
    }
}
