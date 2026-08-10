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
    /// Placed after bodyweight because the calorie estimate depends on it, and late
    /// enough that someone who bounces here has already set everything that matters.
    /// Dropped from the flow entirely when HealthKit is unavailable — see
    /// `OnboardingViewModel.visibleSteps`.
    case appleHealth      = 4
    case importPrompt     = 5

    static var totalSteps: Int { allCases.count }

    var isSkippable: Bool {
        switch self {
        case .welcome: return false
        case .units, .bodyweight, .smartSuggestions, .appleHealth, .importPrompt: return true
        }
    }
}
