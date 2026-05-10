// ChartsTabViewModel.swift
// Coordinator ViewModel that owns the 3 sub-tab ViewModels and manages active tab state.
// Feature: 016-charts-tab-v2 WP05 (T104), WP07, WP08

import SwiftUI

@Observable
final class ChartsTabViewModel {

    enum SubTab: Int, CaseIterable {
        case breakdown = 0
        case workouts = 1
        case exercises = 2

        var title: String {
            switch self {
            case .breakdown: return "Breakdown"
            case .workouts: return "Workouts"
            case .exercises: return "Exercises"
            }
        }
    }

    // MARK: - State

    var activeTab: SubTab = .breakdown

    // MARK: - Child ViewModels

    let breakdownVM: BreakdownTabViewModel
    let workoutsVM: WorkoutsTabViewModel
    let exercisesVM: ExercisesTabViewModel

    // MARK: - Dependencies

    let chartDataService: any ChartDataServiceProtocol
    let exerciseService: any ExerciseServiceProtocol

    // MARK: - Init

    init(chartDataService: any ChartDataServiceProtocol,
         exerciseService: any ExerciseServiceProtocol) {
        self.chartDataService = chartDataService
        self.exerciseService = exerciseService
        self.breakdownVM = BreakdownTabViewModel(chartDataService: chartDataService)
        self.workoutsVM = WorkoutsTabViewModel(chartDataService: chartDataService)
        self.exercisesVM = ExercisesTabViewModel(chartDataService: chartDataService, exerciseService: exerciseService)
    }

    func updateUnitPreference(_ unitPreference: UnitPreference) {
        breakdownVM.unitPreference = unitPreference
        workoutsVM.unitPreference = unitPreference
        exercisesVM.unitPreference = unitPreference
    }

    func reloadVisibleData() async {
        switch activeTab {
        case .breakdown:
            await breakdownVM.loadData()
        case .workouts:
            await workoutsVM.loadData()
        case .exercises:
            await exercisesVM.loadData()
        }
    }
}
