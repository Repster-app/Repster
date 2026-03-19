// SettingsViewModel.swift
// Manages settings state and actions via SettingsService.
// Spec: FR-010, User Stories 1-2
// Feature: 010-settings-and-onboarding WP02 T006

import Foundation
import UIKit

@Observable @MainActor
final class SettingsViewModel {
    // MARK: - State

    var profile: HealthProfile?
    var isLoading = true
    var isRebuilding = false
    var showError = false
    var errorMessage = ""

    // MARK: - Sheet/Alert Presentation

    var showUnitsSheet = false
    var showFormulaSheet = false
    var showRestTimeSheet = false
    var showWarmupRestTimeSheet = false
    var showRebuildVolumeConfirmation = false
    var showRebuildPRsConfirmation = false

    // MARK: - Dependencies

    private let settingsService: any SettingsServiceProtocol

    init(settingsService: any SettingsServiceProtocol) {
        self.settingsService = settingsService
    }

    // MARK: - Computed Helpers

    var unitDisplayName: String {
        profile?.unitPreference.rawValue.capitalized ?? "Metric"
    }

    var formulaDisplayName: String {
        E1RMFormula(rawValue: profile?.e1RMFormula ?? "epley")?.displayName ?? "Epley"
    }

    var restTimeDisplayName: String {
        UnitConversion.formatDuration(profile?.defaultRestTimeSeconds ?? 150)
    }

    var warmupRestTimeDisplayName: String {
        if let seconds = profile?.defaultWarmupRestTimeSeconds {
            return UnitConversion.formatDuration(seconds)
        }
        return "Same as working"
    }

    var restTimerAlertDisplayName: String {
        switch profile?.restTimerAlert ?? "vibration" {
        case "off": return "Off"
        case "vibration": return "Vibration"
        case "sound": return "Sound"
        case "both": return "Both"
        default: return "Vibration"
        }
    }

    // MARK: - Smart Suggestions Computed Helpers

    var smartSuggestionsEnabled: Bool {
        profile?.prescriptionEnabled ?? true
    }

    var prescriptionIncrementDisplayName: String {
        guard let increment = profile?.prescriptionDefaultIncrement else { return "2.5 kg" }
        if increment.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f kg", increment)
        }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: increment)) ?? String(format: "%.2f", increment)
        return "\(formatted) kg"
    }

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Load

    func loadProfile() async {
        do {
            profile = try await settingsService.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }

    // MARK: - Update Actions

    func updateUnitPreference(_ preference: UnitPreference) async {
        do {
            try await settingsService.updateUnitPreference(preference)
            profile = try await settingsService.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func updateE1RMFormula(_ formula: E1RMFormula) async {
        do {
            try await settingsService.updateE1RMFormula(formula)
            profile = try await settingsService.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func updateDefaultRestTime(_ seconds: Int?) async {
        do {
            try await settingsService.updateDefaultRestTime(seconds)
            profile = try await settingsService.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func updateDefaultWarmupRestTime(_ seconds: Int?) async {
        do {
            try await settingsService.updateDefaultWarmupRestTime(seconds)
            profile = try await settingsService.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func updateRestTimerAlert(_ value: String) async {
        do {
            try await settingsService.updateRestTimerAlert(value)
            profile = try await settingsService.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Warmup Toggle Confirmation Flow

    func confirmToggleWarmupVolume() {
        showRebuildVolumeConfirmation = true
    }

    func toggleWarmupVolume() async {
        guard let current = profile?.includeWarmupsInVolume else { return }
        isRebuilding = true
        do {
            try await settingsService.updateIncludeWarmupsInVolume(!current)
            profile = try await settingsService.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isRebuilding = false
    }

    func confirmToggleWarmupPRs() {
        showRebuildPRsConfirmation = true
    }

    func toggleWarmupPRs() async {
        guard let current = profile?.includeWarmupsInPRs else { return }
        isRebuilding = true
        do {
            try await settingsService.updateIncludeWarmupsInPRs(!current)
            profile = try await settingsService.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isRebuilding = false
    }

    // MARK: - About

    func sendFeedback() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let subject = "Reppo Feedback"
        let body = "\n\n---\nApp Version: \(version) (\(build))\niOS: \(UIDevice.current.systemVersion)"

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:feedback@reppo.app?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
}
