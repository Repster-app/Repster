// OnboardingStep.swift
// View-layer step progression tracker for the 4-screen onboarding flow.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T019

import Foundation

enum OnboardingStep: Int, CaseIterable {
    case welcome            = 0
    /// Units and bodyweight share a screen. A bodyweight figure is meaningless without a
    /// unit, so separated, the second screen had to silently assume the first's answer.
    case unitsAndBodyweight = 1
    /// Placed after bodyweight because the calorie estimate depends on it, and late
    /// enough that someone who bounces here has already set everything that matters.
    /// Dropped from the flow entirely when HealthKit is unavailable — see
    /// `OnboardingViewModel.visibleSteps`.
    case appleHealth        = 2
    case importPrompt       = 3

    static var totalSteps: Int { allCases.count }

    var isSkippable: Bool {
        switch self {
        case .welcome:
            return false
        case .unitsAndBodyweight:
            // Units always holds a value, preselected from the device locale, and the
            // bodyweight field is optional within the screen. There is nothing here that
            // skipping would let you avoid answering.
            return false
        case .appleHealth, .importPrompt:
            return true
        }
    }
}
