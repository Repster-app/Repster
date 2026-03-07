// BodyweightLogViewModel.swift
// Manages bodyweight entry CRUD, chart data, and unit conversion.
// Spec: FR-008, User Story 3
// Feature: 010-settings-and-onboarding WP03 T014

import Foundation

@Observable @MainActor
final class BodyweightLogViewModel {
    // MARK: - State

    var entries: [BodyweightEntry] = []
    var isLoading = true
    var showAddSheet = false
    var showError = false
    var errorMessage = ""
    var unitPreference: UnitPreference = .metric

    // MARK: - Dependencies

    private let bodyweightService: any BodyweightServiceProtocol
    private let settingsService: any SettingsServiceProtocol

    init(bodyweightService: any BodyweightServiceProtocol,
         settingsService: any SettingsServiceProtocol) {
        self.bodyweightService = bodyweightService
        self.settingsService = settingsService
    }

    // MARK: - Computed Helpers

    var hasEntries: Bool { !entries.isEmpty }

    var unitLabel: String {
        unitPreference == .metric ? "kg" : "lbs"
    }

    /// Entries sorted date-ascending for chart rendering (left-to-right).
    var entriesForChart: [BodyweightEntry] {
        entries.sorted { $0.date < $1.date }
    }

    func displayWeight(for entry: BodyweightEntry) -> Double {
        unitPreference == .imperial
            ? UnitConversion.kgToLbs(entry.bodyweightKg)
            : entry.bodyweightKg
    }

    // MARK: - Load

    func loadEntries() async {
        do {
            let profile = try await settingsService.fetchSettings()
            unitPreference = profile.unitPreference
            entries = try await bodyweightService.fetchAllEntries()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }

    // MARK: - CRUD

    func addEntry(weightKg: Double, date: Date) async {
        do {
            _ = try await bodyweightService.saveEntry(bodyweightKg: weightKg, date: date)
            entries = try await bodyweightService.fetchAllEntries()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func deleteEntry(_ entry: BodyweightEntry) async {
        do {
            try await bodyweightService.deleteEntry(entry.id)
            entries = try await bodyweightService.fetchAllEntries()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
