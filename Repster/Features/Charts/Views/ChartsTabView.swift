// ChartsTabView.swift
// Top-level Charts tab view with 3-tab picker and content switching.
// Replaces ChartsDashboardView as the Charts tab root.
// Feature: 016-charts-tab-v2 WP05 (T105), WP07, WP08

import SwiftUI

struct ChartsTabView: View {

    @State private var viewModel: ChartsTabViewModel

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
