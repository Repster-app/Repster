// ImportViewModel.swift
// ViewModel for the source-aware import flow.

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
    var selectedSource: ImportSource = .fitNotes
    var selectedFitNotesUnitSystem: ImportUnitSystem
    var selectedStrongUnitSystem: ImportUnitSystem?

    // Preview
    var previewHeaders: [String] = []
    var previewRows: [[String]] = []
    var estimatedTotalRows: Int = 0
    private(set) var activeSource: ImportSource = .fitNotes
    private(set) var activeUnitSystem: ImportUnitSystem?

    // Progress
    var progressFraction: Double = 0
    var progressLabel: String = ""
    var setsInserted: Int = 0
    var totalSets: Int = 0

    // Result
    var result: ImportResult?

    // Error
    var errorMessage: String?
    private(set) var importError: ImportError?

    // MARK: - Dependencies

    private let importService: any ImportServiceProtocol
    private let analyticsService: any AnalyticsServiceProtocol
    private var importData: Data?

    // MARK: - Init

    init(
        importService: any ImportServiceProtocol,
        defaultUnitPreference: UnitPreference = .metric,
        analyticsService: any AnalyticsServiceProtocol = NoopAnalyticsService()
    ) {
        self.importService = importService
        self.analyticsService = analyticsService
        self.selectedFitNotesUnitSystem = defaultUnitPreference == .imperial ? .imperial : .metric
    }

    // MARK: - Derived State

    var shouldShowSupportCTA: Bool {
        if case .some(.invalidHeader(_, _, _)) = importError {
            return true
        }
        return false
    }

    var canSelectFile: Bool {
        !selectedSource.requiresUnitSystem || selectedStrongUnitSystem != nil
    }

    var selectedUnitSystem: ImportUnitSystem? {
        switch selectedSource {
        case .fitNotes:
            return selectedFitNotesUnitSystem
        case .strong:
            return selectedStrongUnitSystem
        }
    }

    var activeUnitSummary: String? {
        activeUnitSystem?.summaryLabel
    }

    var activeSourceSummary: String {
        activeSource.displayName
    }

    // MARK: - Selection

    func chooseSource(_ source: ImportSource) {
        selectedSource = source
    }

    func chooseFitNotesUnitSystem(_ unitSystem: ImportUnitSystem) {
        selectedFitNotesUnitSystem = unitSystem
    }

    func chooseStrongUnitSystem(_ unitSystem: ImportUnitSystem) {
        selectedStrongUnitSystem = unitSystem
    }

    // MARK: - File Selection

    func handleFileSelected(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            setFailure(error)

        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                errorMessage = nil
                importError = nil

                let data = try Data(contentsOf: url)
                let unitSystem = selectedUnitSystem
                let preview = try importService.previewImport(
                    data: data,
                    source: selectedSource,
                    unitSystem: unitSystem
                )

                importData = data
                activeSource = selectedSource
                activeUnitSystem = unitSystem
                previewHeaders = preview.headers
                previewRows = preview.sampleRows
                estimatedTotalRows = preview.estimatedTotalRows
                state = .previewing
            } catch {
                setFailure(error)
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
            let stream = importService.importData(
                data: data,
                source: activeSource,
                unitSystem: activeUnitSystem
            )

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
            analyticsService.track(.importCompleted, properties: importProperties(result: result, outcome: "success"))

        case .failed(let error):
            analyticsService.track(.importCompleted, properties: importProperties(error: error))
            setFailure(error)
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
        importError = nil
        activeSource = selectedSource
        activeUnitSystem = selectedUnitSystem
    }

    func retry() {
        reset()
        showFilePicker = true
    }

    private func setFailure(_ error: Error) {
        importError = error as? ImportError
        errorMessage = error.localizedDescription
        state = .failed
    }

    private func importProperties(
        result: ImportResult? = nil,
        outcome: String? = nil,
        error: Error? = nil
    ) -> [AnalyticsPropertyKey: AnalyticsPropertyValue] {
        var properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [
            .sourceType: .string(activeSource.rawValue)
        ]

        if let activeUnitSystem {
            properties[.unitSystem] = .string(activeUnitSystem.rawValue)
        }

        if estimatedTotalRows > 0 {
            properties[.rowCountBucket] = .string(AnalyticsBuckets.count(estimatedTotalRows))
        }

        if let result {
            properties[.setCountBucket] = .string(AnalyticsBuckets.count(result.setsImported))
            properties[.workoutCountBucket] = .string(AnalyticsBuckets.count(result.workoutsCreated))
            properties[.exerciseCountBucket] = .string(AnalyticsBuckets.count(result.exercisesCreated))
        }

        if let outcome {
            properties[.result] = .string(outcome)
        }

        if let error {
            properties[.result] = .string("failure")
            properties[.errorType] = .string(String(describing: type(of: error)))
        }

        return properties
    }
}
