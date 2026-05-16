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

    var selectedUnit: UnitPreference = .metric
    var bodyweightInput: String = ""
    var defaultTargetReps: Int = 8
    var defaultTargetRIR: Int = 2

    // MARK: - State

    var isSaving = false

    // MARK: - Dependencies

    private let settingsService: any SettingsServiceProtocol
    private let bodyweightService: any BodyweightServiceProtocol

    init(settingsService: any SettingsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol) {
        self.settingsService = settingsService
        self.bodyweightService = bodyweightService
    }

    // MARK: - Computed Helpers

    var isLastStep: Bool { currentStep == .importPrompt }

    var visibleSteps: [OnboardingStep] { OnboardingStep.allCases }

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
        next()
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
        isSaving = false
    }
}
