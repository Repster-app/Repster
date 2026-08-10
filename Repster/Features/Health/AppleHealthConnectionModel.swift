// AppleHealthConnectionModel.swift
// The connect flow behind every surface that offers Apple Health.
//
// Three surfaces need this — the onboarding step, Settings, and (once it exists) the
// What's New sheet. They differ only in chrome and in the `source` they report, so the
// authorization call, the preference write and the analytics all live here once.

import Foundation

@Observable @MainActor
final class AppleHealthConnectionModel {

    /// Set while the system sheet is up, so callers can disable their button.
    private(set) var isConnecting = false

    /// Non-nil when the attempt failed in a way worth explaining. Presented as an alert.
    var alertMessage: String?

    private let healthKitService: any HealthKitServiceProtocol
    private let analyticsService: any AnalyticsServiceProtocol
    private let source: AppleHealthPromptSource
    private var hasReportedPromptShown = false

    init(healthKitService: any HealthKitServiceProtocol,
         analyticsService: any AnalyticsServiceProtocol,
         source: AppleHealthPromptSource) {
        self.healthKitService = healthKitService
        self.analyticsService = analyticsService
        self.source = source
    }

    /// Report that Repster's own pre-permission UI appeared. Idempotent, so swiping back
    /// and forth in onboarding can't inflate the denominator.
    ///
    /// Deliberately does NOT mark the offer as spent: an onboarding run that's abandoned
    /// halfway should still show the step when the user comes back.
    func promptShown() {
        guard !hasReportedPromptShown else { return }
        hasReportedPromptShown = true
        analyticsService.appleHealthPromptShown(source: source)
    }

    /// The user declined in Repster's UI. HealthKit is never touched, so iOS's one-shot
    /// permission sheet stays unspent and Settings can still connect later.
    func decline() {
        HealthKitPreferences.markOffered()
        analyticsService.appleHealthPromptAnswered(source: source, result: .notNow)
    }

    /// Call only from an explicit "connect" tap. Returns true when the integration is on.
    @discardableResult
    func connect() async -> Bool {
        isConnecting = true
        defer { isConnecting = false }

        let result = await healthKitService.requestAuthorization()

        // Answered — whichever way — so no other surface should raise it again.
        HealthKitPreferences.markOffered()
        analyticsService.appleHealthPromptAnswered(source: source, result: result.promptResult)

        switch result {
        case .authorized:
            HealthKitPreferences.setEnabled(true)
            return true
        case .denied:
            HealthKitPreferences.setEnabled(false)
            alertMessage = "Repster doesn't have permission to add workouts. You can grant it in the Health app under Sharing → Apps → Repster."
        case .unavailable:
            HealthKitPreferences.setEnabled(false)
            alertMessage = "Apple Health isn't available on this device."
        case .failed(let message):
            HealthKitPreferences.setEnabled(false)
            alertMessage = message
        }
        return false
    }

    /// Turning it off leaves already-written workouts in Health: it's the user's health
    /// data, and silently deleting history on a toggle-off would surprise.
    func disable() {
        HealthKitPreferences.setEnabled(false)
        analyticsService.appleHealthDisabled(source: source)
    }
}
