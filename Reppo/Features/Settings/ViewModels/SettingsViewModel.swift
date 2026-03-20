// SettingsViewModel.swift
// Manages settings state and actions via SettingsService.
// Spec: FR-010, User Stories 1-2
// Feature: 010-settings-and-onboarding WP02 T006

import Foundation
import UIKit

enum SupportEmailComposer {
    static let address = "feedback@reppo.app"

    static func feedbackURL(
        appVersion: String? = nil,
        build: String? = nil,
        systemVersion: String = UIDevice.current.systemVersion
    ) -> URL? {
        makeURL(
            subject: "Reppo Feedback",
            appVersion: appVersion,
            build: build,
            systemVersion: systemVersion
        )
    }

    static func importSupportURL(
        appVersion: String? = nil,
        build: String? = nil,
        systemVersion: String = UIDevice.current.systemVersion
    ) -> URL? {
        makeURL(
            subject: "CSV Import Support",
            appVersion: appVersion,
            build: build,
            systemVersion: systemVersion
        )
    }

    private static func makeURL(
        subject: String,
        appVersion: String?,
        build: String?,
        systemVersion: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(
                name: "body",
                value: "\n\n---\nApp Version: \(resolvedVersion(appVersion, build))\niOS: \(systemVersion)"
            )
        ]
        return components.url
    }

    private static func resolvedVersion(_ appVersion: String?, _ build: String?) -> String {
        let version = appVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        let build = build ?? (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
        return "\(version) (\(build))"
    }
}

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

    var workoutPreferencesSummary: String {
        "Rest \(compactRestSummary) • Alerts \(restTimerAlertDisplayName) • \(warmupSettingsSummary)"
    }

    var smartSuggestionsSummary: String {
        guard smartSuggestionsEnabled else { return "Off" }
        return "On • \(compactIncrementSummary)"
    }

    var dataBackupsSummary: String {
        "Import • Export • Restore • Reset"
    }

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Load

    func loadProfile() async {
        await refreshProfile()
        isLoading = false
    }

    func refreshProfile() async {
        do {
            try await reloadProfile()
        } catch {
            present(error)
        }
    }

    // MARK: - Update Actions

    func updateUnitPreference(_ preference: UnitPreference) async {
        await performUpdate {
            try await settingsService.updateUnitPreference(preference)
        }
    }

    func updateE1RMFormula(_ formula: E1RMFormula) async {
        await performUpdate {
            try await settingsService.updateE1RMFormula(formula)
        }
    }

    func updateDefaultRestTime(_ seconds: Int?) async {
        await performUpdate {
            try await settingsService.updateDefaultRestTime(seconds)
        }
    }

    func updateDefaultWarmupRestTime(_ seconds: Int?) async {
        await performUpdate {
            try await settingsService.updateDefaultWarmupRestTime(seconds)
        }
    }

    func updateRestTimerAlert(_ value: String) async {
        await performUpdate {
            try await settingsService.updateRestTimerAlert(value)
        }
    }

    func updatePrescriptionEnabled(_ enabled: Bool) async {
        await performUpdate {
            try await settingsService.updatePrescriptionEnabled(enabled)
        }
    }

    func updatePrescriptionDefaultIncrement(_ increment: Double) async {
        await performUpdate {
            try await settingsService.updatePrescriptionDefaultIncrement(increment)
        }
    }

    // MARK: - Warmup Toggle Confirmation Flow

    func confirmToggleWarmupVolume() {
        showRebuildVolumeConfirmation = true
    }

    func toggleWarmupVolume() async {
        guard let current = profile?.includeWarmupsInVolume else { return }
        isRebuilding = true
        await performUpdate {
            try await settingsService.updateIncludeWarmupsInVolume(!current)
        }
        isRebuilding = false
    }

    func confirmToggleWarmupPRs() {
        showRebuildPRsConfirmation = true
    }

    func toggleWarmupPRs() async {
        guard let current = profile?.includeWarmupsInPRs else { return }
        isRebuilding = true
        await performUpdate {
            try await settingsService.updateIncludeWarmupsInPRs(!current)
        }
        isRebuilding = false
    }

    // MARK: - About

    func sendFeedback() {
        if let url = SupportEmailComposer.feedbackURL() {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Private

    private var warmupSettingsSummary: String {
        let includesVolume = profile?.includeWarmupsInVolume ?? false
        let includesPRs = profile?.includeWarmupsInPRs ?? false

        switch (includesVolume, includesPRs) {
        case (false, false):
            return "Warmups excluded"
        case (true, true):
            return "Warmups included"
        case (true, false):
            return "Warmups in volume only"
        case (false, true):
            return "Warmups in PRs only"
        }
    }

    private var compactRestSummary: String {
        Self.compactDuration(profile?.defaultRestTimeSeconds ?? 150)
    }

    private var compactIncrementSummary: String {
        guard let increment = profile?.prescriptionDefaultIncrement else { return "2.5 kg" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: increment)) ?? String(format: "%.2f", increment)
        return "\(formatted) kg"
    }

    private func performUpdate(_ update: () async throws -> Void) async {
        do {
            try await update()
            try await reloadProfile()
        } catch {
            present(error)
        }
    }

    private func reloadProfile() async throws {
        profile = try await settingsService.fetchSettings()
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private static func compactDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

@Observable @MainActor
final class ResetAppDataViewModel {
    enum ResetState: Equatable {
        case idle
        case resetting
        case completed
        case failed
    }

    var state: ResetState = .idle
    var showDeleteConfirmation = false
    var errorMessage: String?

    private let settingsService: any SettingsServiceProtocol
    private let onResetComplete: @MainActor @Sendable () async -> Void

    init(
        settingsService: any SettingsServiceProtocol,
        onResetComplete: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.settingsService = settingsService
        self.onResetComplete = onResetComplete
    }

    var isResetting: Bool {
        state == .resetting
    }

    func confirmReset() {
        guard !isResetting else { return }
        showDeleteConfirmation = true
    }

    func performReset() {
        guard !isResetting else { return }

        showDeleteConfirmation = false
        errorMessage = nil
        state = .resetting

        Task {
            do {
                try await settingsService.resetAllAppData()
                await onResetComplete()
                state = .completed
            } catch {
                errorMessage = error.localizedDescription
                state = .failed
            }
        }
    }

    func retry() {
        guard state == .failed else { return }
        errorMessage = nil
        performReset()
    }

    func reviewWarningsAgain() {
        errorMessage = nil
        showDeleteConfirmation = false
        state = .idle
    }
}
