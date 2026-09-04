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
    /// Pick a program, which writes its sessions as templates in a folder.
    ///
    /// Replaces the old `importPrompt` at this index. That screen was the last thing between the
    /// user and the app, and five people stopped there for good without one recorded skip — see
    /// ONBOARDING_REDESIGN_SCOPING.md.
    case program            = 2

    /// Completion screen offering the two optional extras: import, and the walkthrough.
    /// Import moved here so nobody has to pass through it to reach the app.
    case extras             = 3

    static var totalSteps: Int { allCases.count }

    /// Nothing is skippable any more, and that is deliberate rather than incidental.
    ///
    /// `import_prompt` was marked skippable and recorded zero skips across the 53 people who saw
    /// it, which left an unwired control and an unfindable one indistinguishable. Step 2 always
    /// resolves to a choice (including "build my own") and step 3's way out is its primary
    /// button, so there is no skip control left to under-report.
    var isSkippable: Bool { false }
}
