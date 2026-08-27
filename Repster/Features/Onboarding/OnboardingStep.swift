// OnboardingStep.swift
// View-layer step progression tracker for the 3-screen onboarding flow.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T019

import Foundation

enum OnboardingStep: Int, CaseIterable {
    case welcome            = 0
    /// Units and bodyweight share a screen. A bodyweight figure is meaningless without a
    /// unit, so separated, the second screen had to silently assume the first's answer.
    case unitsAndBodyweight = 1
    /// Was index 3, behind an Apple Health step that 1.4 shipped here and 1.5 moved to
    /// the first workout finish. `step_index` therefore drops by one across that release;
    /// `step` is the stable dimension to funnel on.
    case importPrompt       = 2

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
        case .importPrompt:
            return true
        }
    }
}
