// OnboardingViewModel.swift
// Manages onboarding step progression, user selections, and saves preferences on completion.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T020

import Foundation
import SwiftUI

@Observable @MainActor
final class OnboardingViewModel {
    // MARK: - Step Progression

    var currentStep: OnboardingStep = .welcome

    // MARK: - User Selections (defaults applied)

    /// Seeded from the device locale so the units screen is a confirmation rather than a
    /// decision. The choice is still explicit — this only changes what's preselected.
    var selectedUnit: UnitPreference = UnitPreference.fromCurrentLocale()
    var bodyweightInput: String = ""

    /// No longer asked for. The Smart Suggestions step wanted a target rep count and RIR
    /// before the user had logged a single set, which is a decision with nothing to base
    /// it on — everyone took the default. These are still written on finish so a fresh
    /// install lands in a known state, and `PrescriptionSettingsView` is where they change.
    var defaultTargetReps: Int = 8
    var defaultTargetRIR: Int = 2

    // MARK: - State

    var isSaving = false

    // MARK: - Dependencies

    private let settingsService: any SettingsServiceProtocol
    private let bodyweightService: any BodyweightServiceProtocol
    private let analyticsService: any AnalyticsServiceProtocol

    /// Fixed for the lifetime of the flow so steps can't appear or vanish mid-run.
    /// Note this is availability only, not `shouldOfferConnection`: an onboarding run
    /// that's abandoned halfway must still show the step when the user starts over.
    private let isHealthKitAvailable: Bool

    /// Steps already reported as viewed, so swiping back and forth in the page
    /// TabView doesn't inflate the funnel denominator.
    private var reportedStepViews: Set<OnboardingStep> = []

    init(settingsService: any SettingsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol,
         analyticsService: any AnalyticsServiceProtocol,
         isHealthKitAvailable: Bool) {
        self.settingsService = settingsService
        self.bodyweightService = bodyweightService
        self.analyticsService = analyticsService
        self.isHealthKitAvailable = isHealthKitAvailable
    }

    // MARK: - Computed Helpers

    var isLastStep: Bool { currentStep == .importPrompt }

    var visibleSteps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0 != .appleHealth || isHealthKitAvailable }
    }

    var stepProgress: Double {
        guard let index = visibleSteps.firstIndex(of: currentStep) else { return 0 }
        return Double(index + 1) / Double(visibleSteps.count)
    }

    var canSkip: Bool { currentStep.isSkippable }

    // MARK: - Navigation

    func next() {
        guard let currentIndex = visibleSteps.firstIndex(of: currentStep),
              currentIndex + 1 < visibleSteps.count else { return }
        let nextStep = visibleSteps[currentIndex + 1]
        withAnimation { currentStep = nextStep }
    }

    func skip() {
        analyticsService.onboardingStepSkipped(currentStep)
        next()
    }

    /// Called from the container's `onAppear` / step change. Idempotent per step.
    func trackStepViewed(_ step: OnboardingStep) {
        guard reportedStepViews.insert(step).inserted else { return }
        analyticsService.onboardingStepViewed(step)
    }

    // MARK: - Finish

    /// Save all selections and complete onboarding.
    /// Errors are non-fatal — defaults are applied. The caller sets @AppStorage flag after this returns.
    func finish() async {
        isSaving = true
        do {
            try await settingsService.updateUnitPreference(selectedUnit)
            try await settingsService.updatePrescriptionDefaultTargetReps(defaultTargetReps)
            try await settingsService.updatePrescriptionDefaultTargetRIR(defaultTargetRIR)

            if let weight = Double(bodyweightInput), weight > 0 {
                let weightKg = selectedUnit == .imperial
                    ? UnitConversion.lbsToKg(weight)
                    : weight
                _ = try await bodyweightService.saveEntry(bodyweightKg: weightKg, date: Date())
            }
        } catch {
            // Non-fatal — user can adjust in Settings later
        }
        analyticsService.onboardingCompleted(
            lastStep: currentStep,
            unitSystem: selectedUnit.rawValue
        )
        isSaving = false
    }
}
