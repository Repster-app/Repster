// OnboardingStep.swift
// View-layer step progression tracker for the 5-screen onboarding flow.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T019

import Foundation

enum OnboardingStep: Int, CaseIterable {
    case welcome          = 0
    case units            = 1
    case bodyweight       = 2
    case smartSuggestions = 3
    case importPrompt     = 4

    static var totalSteps: Int { allCases.count }

    var isSkippable: Bool {
        switch self {
        case .welcome: return false
        case .units, .bodyweight, .smartSuggestions, .importPrompt: return true
        }
    }
}
