// WorkoutsTabViewModel.swift
// ViewModel for the Workouts tab — manages dropdowns, time range, trend line, data navigation.
// Feature: 016-charts-tab-v2 WP07 (T119)

import SwiftUI

@Observable
final class WorkoutsTabViewModel {

    // MARK: - State

    var selectedMetric: WorkoutsMetric = .volume
    var selectedAggregation: WorkoutsAggregation = .perMonth
    var selectedCategory: String = "All"
    var selectedExerciseFilter: WorkoutsFilter = .all
    var selectedTimeRange: WorkoutsTimeRange = .all
    var chartData: [WorkoutsTimeSeriesPoint]?
    var trendLine: TrendLineData?
    var selectedDataIndex: Int?
    var isLoading = false
    var unitPreference: UnitPreference = .metric

    // Filter dropdown data sources
    var availableCategories: [String] = []
    var availableExercises: [(id: UUID, name: String)] = []

    /// Category dropdown options: "All" + available categories
    var categoryOptions: [String] {
        ["All"] + availableCategories
    }

    /// Exercise dropdown options: filtered by selected category
    var exerciseOptions: [WorkoutsFilter] {
        var options: [WorkoutsFilter] = [.all]
        if selectedCategory == "All" {
            options += availableExercises.map { .exercise($0.id, name: $0.name) }
        } else {
            options += availableExercises.map { .exercise($0.id, name: $0.name) }
        }
        return options
    }

    /// The effective filter combining category and exercise selection
    var effectiveFilter: WorkoutsFilter {
        if case .exercise = selectedExerciseFilter {
            return selectedExerciseFilter
        }
        if selectedCategory != "All" {
            return .category(selectedCategory)
        }
        return .all
    }

    // MARK: - Dependencies

    private let chartDataService: any ChartDataServiceProtocol

    // MARK: - Init

    init(chartDataService: any ChartDataServiceProtocol) {
        self.chartDataService = chartDataService
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        do {
            let data = try await chartDataService.fetchWorkoutsTimeSeries(
                metric: selectedMetric,
                aggregation: selectedAggregation,
                filter: effectiveFilter,
                timeRange: selectedTimeRange
            )
            let displayData = data.map { point in
                WorkoutsTimeSeriesPoint(
                    date: point.date,
                    value: displayValue(point.value, for: selectedMetric),
                    label: point.label,
                    workoutId: point.workoutId
                )
            }
            chartData = displayData

            // Compute trend line
            if displayData.count >= 2 {
                trendLine = TrendLineCalculator.compute(values: displayData.map { $0.value })
            } else {
                trendLine = nil
            }

            // Set selected data index to latest point
            selectedDataIndex = data.isEmpty ? nil : data.count - 1
        } catch {
            dbg("[WorkoutsTab] Error loading data: \(error)")
        }
        isLoading = false
    }

    func loadFilterOptions() async {
        do {
            availableCategories = try await chartDataService.fetchAvailableCategories()
            availableExercises = try await chartDataService.fetchPerformedExercises()
        } catch {
            dbg("[WorkoutsTab] Error loading filter options: \(error)")
        }
    }

    func changeMetric(_ metric: WorkoutsMetric) async {
        selectedMetric = metric
        chartData = nil
        await loadData()
    }

    func changeAggregation(_ aggregation: WorkoutsAggregation) async {
        selectedAggregation = aggregation
        chartData = nil
        await loadData()
    }

    func changeCategory(_ category: String) async {
        selectedCategory = category
        selectedExerciseFilter = .all // Reset exercise when category changes
        chartData = nil
        await loadData()
    }

    func changeExerciseFilter(_ filter: WorkoutsFilter) async {
        selectedExerciseFilter = filter
        chartData = nil
        await loadData()
    }

    func changeTimeRange(_ range: WorkoutsTimeRange) async {
        selectedTimeRange = range
        chartData = nil
        await loadData()
    }

    // MARK: - Data Point Navigation

    func navigateDataPoint(direction: NavigationDirection) {
        guard let data = chartData, !data.isEmpty else { return }
        guard let current = selectedDataIndex else {
            selectedDataIndex = data.count - 1
            return
        }
        switch direction {
        case .previous:
            if current > 0 { selectedDataIndex = current - 1 }
        case .next:
            if current < data.count - 1 { selectedDataIndex = current + 1 }
        }
    }

    enum NavigationDirection { case previous, next }

    // MARK: - Workout Navigation (Per Workout mode)

    /// Returns the workoutId of the currently selected data point (only in Per Workout mode)
    var selectedWorkoutId: UUID? {
        guard selectedAggregation == .perWorkout,
              let data = chartData, let index = selectedDataIndex,
              index >= 0, index < data.count else { return nil }
        return data[index].workoutId
    }

    // MARK: - Formatting Helpers

    var yAxisLabel: String {
        switch selectedMetric {
        case .volume: return UnitConversion.weightUnitLabel(for: unitPreference)
        case .sets: return "sets"
        case .reps: return "reps"
        case .workouts: return "workouts"
        case .distance: return UnitConversion.chartDistanceUnitLabel(for: unitPreference)
        case .time: return "min"
        }
    }

    var selectedValueFormatted: String? {
        guard let data = chartData, let index = selectedDataIndex,
              index >= 0, index < data.count else { return nil }
        let point = data[index]
        switch selectedMetric {
        case .volume:
            return "\(UnitConversion.formatWeight(point.value)) \(UnitConversion.weightUnitLabel(for: unitPreference))"
        case .sets:
            return "\(Int(point.value)) sets"
        case .reps:
            return "\(Int(point.value)) reps"
        case .workouts:
            return "\(Int(point.value)) workouts"
        case .distance:
            return String(format: "%.2f %@", point.value, UnitConversion.chartDistanceUnitLabel(for: unitPreference) as NSString)
        case .time:
            return String(format: "%.0f min", point.value)
        }
    }

    var selectedDateFormatted: String? {
        guard let data = chartData, let index = selectedDataIndex,
              index >= 0, index < data.count else { return nil }
        let point = data[index]
        let formatter = DateFormatter()
        switch selectedAggregation {
        case .perWorkout:
            formatter.dateFormat = "MMM d, yyyy"
        case .perWeek:
            formatter.dateFormat = "'Week of' MMM d"
        case .perMonth:
            formatter.dateFormat = "MMM yyyy"
        case .perYear:
            formatter.dateFormat = "yyyy"
        }
        return formatter.string(from: point.date)
    }

    var hasPreviousDataPoint: Bool {
        guard let index = selectedDataIndex else { return false }
        return index > 0
    }

    var hasNextDataPoint: Bool {
        guard let data = chartData, let index = selectedDataIndex else { return false }
        return index < data.count - 1
    }

    private func displayValue(_ value: Double, for metric: WorkoutsMetric) -> Double {
        switch metric {
        case .volume:
            return UnitConversion.displayedWeight(value, unitPreference: unitPreference)
        case .distance:
            return UnitConversion.displayedChartDistance(value, unitPreference: unitPreference)
        case .sets, .reps, .workouts, .time:
            return value
        }
    }
}
