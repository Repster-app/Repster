// OnboardingViewModel.swift
// Manages onboarding step progression, user selections, and saves preferences on completion.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T020

import Foundation
import SwiftUI

enum OnboardingSetupMode {
    case quick    // Skips formula step
    case advanced // Full flow including formula selection
}

@Observable @MainActor
final class OnboardingViewModel {
    // MARK: - Step Progression

    var currentStep: OnboardingStep = .welcome
    var setupMode: OnboardingSetupMode = .quick

    // MARK: - User Selections (defaults applied)

    var selectedUnit: UnitPreference = .metric
    var selectedFormula: E1RMFormula = .epley
    var bodyweightInput: String = ""

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

    /// Steps visible for the current setup mode.
    var visibleSteps: [OnboardingStep] {
        OnboardingStep.allCases.filter { step in
            if step == .formula && setupMode == .quick { return false }
            return true
        }
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
        next()
    }

    // MARK: - Finish

    /// Save all selections and complete onboarding.
    /// Errors are non-fatal — defaults are applied. The caller sets @AppStorage flag after this returns.
    func finish() async {
        isSaving = true
        do {
            try await settingsService.updateUnitPreference(selectedUnit)
            try await settingsService.updateE1RMFormula(selectedFormula)

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
