// OnboardingContainerView.swift
// Top-level TabView container with progress dots and step navigation.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T021

import SwiftUI

struct OnboardingContainerView: View {
    @State private var viewModel: OnboardingViewModel
    let importService: any ImportServiceProtocol
    let onComplete: () -> Void

    init(settingsService: any SettingsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol,
         importService: any ImportServiceProtocol,
         onComplete: @escaping () -> Void) {
        _viewModel = State(initialValue: OnboardingViewModel(
            settingsService: settingsService,
            bodyweightService: bodyweightService
        ))
        self.importService = importService
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            progressDots

            TabView(selection: $viewModel.currentStep) {
                WelcomeStepView(
                    setupMode: $viewModel.setupMode,
                    onNext: { viewModel.next() }
                )
                    .tag(OnboardingStep.welcome)

                UnitsStepView(
                    selectedUnit: $viewModel.selectedUnit,
                    onNext: { viewModel.next() }
                )
                .tag(OnboardingStep.units)

                if viewModel.setupMode == .advanced {
                    FormulaStepView(
                        selectedFormula: $viewModel.selectedFormula,
                        onNext: { viewModel.next() }
                    )
                    .tag(OnboardingStep.formula)
                }

                BodyweightStepView(
                    bodyweightInput: $viewModel.bodyweightInput,
                    unitPreference: viewModel.selectedUnit,
                    onNext: { viewModel.next() },
                    onSkip: { viewModel.skip() }
                )
                .tag(OnboardingStep.bodyweight)

                ImportStepView(
                    importService: importService,
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
            ForEach(viewModel.visibleSteps, id: \.self) { step in
                let currentIndex = viewModel.visibleSteps.firstIndex(of: viewModel.currentStep) ?? 0
                let stepIndex = viewModel.visibleSteps.firstIndex(of: step) ?? 0
                Circle()
                    .fill(stepIndex <= currentIndex
                          ? Color.accent
                          : Color.textSecondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 16)
    }
}
