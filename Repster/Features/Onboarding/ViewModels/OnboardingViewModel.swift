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

    /// Step 2's answer. Three states on purpose — "nothing chosen yet" and "build my own" are
    /// different, and the CTA is only enabled for the second.
    ///
    /// Held rather than materialised on the spot: writing templates the moment a card is tapped
    /// would leave an orphaned folder behind every time someone changed their mind. The write
    /// happens once, in `finish()`.
    var programChoice: ProgramChoice = .undecided

    var selectedProgram: ProgramSeedDTO? { programChoice.program }

    /// The catalogue, loaded once for the picker. Empty if the bundled file is unreadable, which
    /// leaves the user with "build my own" rather than a broken step.
    private(set) var availablePrograms: [ProgramSeedDTO] = []

    /// Set by `finish()` so the caller can tell the user what landed. Nil when "build my own"
    /// was chosen, or when materialisation failed.
    private(set) var materialisedProgram: ProgramMaterialisationResult?

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
    private let programCatalogService: any ProgramCatalogServiceProtocol

    /// Steps already reported as viewed, so swiping back and forth in the page
    /// TabView doesn't inflate the funnel denominator.
    private var reportedStepViews: Set<OnboardingStep> = []

    init(settingsService: any SettingsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol,
         analyticsService: any AnalyticsServiceProtocol,
         programCatalogService: any ProgramCatalogServiceProtocol) {
        self.settingsService = settingsService
        self.bodyweightService = bodyweightService
        self.analyticsService = analyticsService
        self.programCatalogService = programCatalogService
    }

    // MARK: - Computed Helpers

    var isLastStep: Bool { currentStep == .extras }

    /// Every step is unconditional now that the Apple Health step — the only one that
    /// could be absent on a given device — has moved out of the flow. Kept as a property
    /// rather than inlined because the container and the progress dots both count off it.
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
        analyticsService.onboardingStepSkipped(currentStep)
        next()
    }

    /// Loads the bundled catalogue. Safe to call more than once.
    func loadProgramsIfNeeded() {
        guard availablePrograms.isEmpty else { return }
        availablePrograms = (try? programCatalogService.availablePrograms()) ?? []
    }

    /// Step 2's continue action. Records the choice; the templates are written in `finish()`.
    func confirmProgramSelection() {
        if let program = selectedProgram {
            analyticsService.programSelected(
                programId: program.id,
                sessionCount: program.sessionCount
            )
        } else {
            analyticsService.programSelected(programId: "own", sessionCount: 0)
        }
        next()
    }

    /// A tap on one of the final step's optional extras.
    func trackExtraTapped(_ extra: String) {
        analyticsService.onboardingExtraTapped(extra: extra)
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

        // Write the chosen program's sessions as templates. Deliberately after the preference
        // writes and deliberately non-fatal: a user must never be trapped on the last screen
        // because template writing failed, and the picker is reachable again from Templates.
        if let program = selectedProgram {
            do {
                materialisedProgram = try await programCatalogService.materialise(programId: program.id)
            } catch {
                materialisedProgram = nil
                analyticsService.captureError(error, context: .programMaterialisation)
            }
        }

        analyticsService.onboardingCompleted(
            lastStep: currentStep,
            unitSystem: selectedUnit.rawValue
        )
        isSaving = false
    }
}
