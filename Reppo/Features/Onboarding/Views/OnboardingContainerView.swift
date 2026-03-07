// OnboardingContainerView.swift
// Top-level TabView container with progress dots and step navigation.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T021

import SwiftUI

struct OnboardingContainerView: View {
    @State private var viewModel: OnboardingViewModel
    let onComplete: () -> Void

    init(settingsService: any SettingsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol,
         onComplete: @escaping () -> Void) {
        _viewModel = State(initialValue: OnboardingViewModel(
            settingsService: settingsService,
            bodyweightService: bodyweightService
        ))
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            progressDots

            TabView(selection: $viewModel.currentStep) {
                WelcomeStepView(onNext: { viewModel.next() })
                    .tag(OnboardingStep.welcome)

                UnitsStepView(
                    selectedUnit: $viewModel.selectedUnit,
                    onNext: { viewModel.next() }
                )
                .tag(OnboardingStep.units)

                FormulaStepView(
                    selectedFormula: $viewModel.selectedFormula,
                    onNext: { viewModel.next() }
                )
                .tag(OnboardingStep.formula)

                BodyweightStepView(
                    bodyweightInput: $viewModel.bodyweightInput,
                    unitPreference: viewModel.selectedUnit,
                    onNext: { viewModel.next() },
                    onSkip: { viewModel.skip() }
                )
                .tag(OnboardingStep.bodyweight)

                ImportStepView(
                    isSaving: viewModel.isSaving,
                    onFinish: {
                        Task {
                            await viewModel.finish()
                            onComplete()
                        }
                    },
                    onSkip: {
                        Task {
                            await viewModel.finish()
                            onComplete()
                        }
                    }
                )
                .tag(OnboardingStep.importPrompt)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: viewModel.currentStep)
        }
        .background(Color.bg)
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= viewModel.currentStep.rawValue
                          ? Color.accent
                          : Color.textSecondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 16)
    }
}
