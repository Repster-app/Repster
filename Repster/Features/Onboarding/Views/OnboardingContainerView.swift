// OnboardingContainerView.swift
// Top-level TabView container with progress dots and step navigation.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T021

import SwiftUI

struct OnboardingContainerView: View {
    @State private var viewModel: OnboardingViewModel
    @State private var showingImport = false
    @State private var showingWalkthrough = false
    @Environment(ServiceContainer.self) private var services
    let importService: any ImportServiceProtocol
    let onComplete: () -> Void

    init(settingsService: any SettingsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol,
         importService: any ImportServiceProtocol,
         analyticsService: any AnalyticsServiceProtocol,
         programCatalogService: any ProgramCatalogServiceProtocol,
         onComplete: @escaping () -> Void) {
        _viewModel = State(initialValue: OnboardingViewModel(
            settingsService: settingsService,
            bodyweightService: bodyweightService,
            analyticsService: analyticsService,
            programCatalogService: programCatalogService
        ))
        self.importService = importService
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            progressDots

            TabView(selection: $viewModel.currentStep) {
                WelcomeStepView(
                    onNext: { viewModel.next() }
                )
                    .tag(OnboardingStep.welcome)

                UnitsBodyweightStepView(
                    selectedUnit: $viewModel.selectedUnit,
                    bodyweightInput: $viewModel.bodyweightInput,
                    onNext: { viewModel.next() }
                )
                .tag(OnboardingStep.unitsAndBodyweight)

                ProgramPickerView(
                    programs: viewModel.availablePrograms,
                    choice: $viewModel.programChoice,
                    onContinue: { viewModel.confirmProgramSelection() }
                )
                .tag(OnboardingStep.program)

                ExtrasStepView(
                    selectedProgram: viewModel.selectedProgram,
                    isSaving: viewModel.isSaving,
                    onOpenImport: {
                        viewModel.trackExtraTapped("import")
                        showingImport = true
                    },
                    onOpenWalkthrough: {
                        viewModel.trackExtraTapped("walkthrough")
                        showingWalkthrough = true
                    },
                    onFinish: {
                        Task {
                            await viewModel.finish()
                            services.updateCachedUnitPreference(viewModel.selectedUnit)
                            onComplete()
                        }
                    }
                )
                .tag(OnboardingStep.extras)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: viewModel.currentStep)
        }
        .background(Color.bg)
        .onAppear {
            viewModel.loadProgramsIfNeeded()
            trackStep(viewModel.currentStep)
        }
        .onChange(of: viewModel.currentStep) { _, step in
            trackStep(step)
        }
        // Both extras are sub-screens, not steps. Nobody has to pass through either one, and
        // dismissing returns to the final step rather than completing onboarding.
        .sheet(isPresented: $showingImport) {
            NavigationStack {
                ImportStepView(
                    importService: importService,
                    defaultUnitPreference: viewModel.selectedUnit,
                    exerciseService: services.exerciseService,
                    isSaving: false,
                    onFinish: { showingImport = false },
                    onSkip: { showingImport = false }
                )
            }
        }
        .sheet(isPresented: $showingWalkthrough) {
            HowItWorksView(analyticsService: services.analyticsService)
        }
    }

    private func trackStep(_ step: OnboardingStep) {
        viewModel.trackStepViewed(step)
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
