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

    var stepProgress: Double {
        Double(currentStep.rawValue + 1) / Double(OnboardingStep.totalSteps)
    }

    var canSkip: Bool { currentStep.isSkippable }

    // MARK: - Navigation

    func next() {
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
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
