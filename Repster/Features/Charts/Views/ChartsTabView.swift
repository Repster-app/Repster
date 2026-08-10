// ChartsTabView.swift
// Top-level Charts tab view with 3-tab picker and content switching.
// Replaces ChartsDashboardView as the Charts tab root.
// Feature: 016-charts-tab-v2 WP05 (T105), WP07, WP08

import SwiftUI

struct ChartsTabView: View {

    @Environment(ServiceContainer.self) private var services
    @State private var viewModel: ChartsTabViewModel

    /// Charts is reported once per view lifetime — the tab is re-entered often
    /// and repeat reports would drown the empty-state signal.
    @State private var hasReportedChartsData = false

    init(chartDataService: any ChartDataServiceProtocol,
         exerciseService: any ExerciseServiceProtocol) {
        _viewModel = State(initialValue: ChartsTabViewModel(
            chartDataService: chartDataService,
            exerciseService: exerciseService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Page header
                HStack {
                    Text("Charts")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Sub-tab picker
                ChartSubTabPicker(
                    selectedTab: $viewModel.activeTab
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Tab content
                ScrollView {
                    tabContent
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100) // Bottom nav clearance
                }
            }
            .background(Color.bg)
        }
        .onAppear {
            viewModel.updateUnitPreference(services.unitPreference)
        }
        // Reported once the first load resolves rather than on appear, so an
        // in-flight load isn't miscounted as an empty state. "Opened Charts and
        // found nothing" is a prime suspect for a silent first-session bounce.
        // Only the empty case is reported — `ContentView` owns `$screen` for the
        // tabs, and a screen call here would double-count Charts traffic.
        .onChange(of: viewModel.breakdownHasData) { _, hasData in
            guard let hasData, !hasReportedChartsData else { return }
            hasReportedChartsData = true
            guard !hasData else { return }
            services.analyticsService.emptyStateShown(screen: .charts)
        }
        .onChange(of: services.unitPreference) { _, newValue in
            viewModel.updateUnitPreference(newValue)
            Task {
                await viewModel.reloadVisibleData()
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab {
        case .breakdown:
            BreakdownTabView(viewModel: viewModel.breakdownVM)
        case .workouts:
            WorkoutsTabView(viewModel: viewModel.workoutsVM)
        case .exercises:
            ExercisesTabView(viewModel: viewModel.exercisesVM)
        }
    }
}
