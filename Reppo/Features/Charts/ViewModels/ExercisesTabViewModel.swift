// ExercisesTabViewModel.swift
// ViewModel for the Exercises tab — manages metric, exercise selection, time range, trend, navigation.
// Feature: 016-charts-tab-v2 WP08 (T125)

import SwiftUI

@Observable
final class ExercisesTabViewModel {

    // MARK: - State

    var selectedMetric: ExerciseMetric = .estimatedOneRM
    var selectedExercises: [(id: UUID, name: String, category: String)] = []
    var selectedTimeRange: WorkoutsTimeRange = .all
    var chartData: [ExerciseProgressSeries]?
    var trendLine: TrendLineData?
    var selectedDataIndex: Int?
    var isLoading = false
    var showExerciseSelector = false

    // MARK: - Configuration

    /// When true, the exercise selector is hidden and selection is locked.
    let isEmbeddedMode: Bool

    // MARK: - Dependencies

    private let chartDataService: any ChartDataServiceProtocol
    let exerciseService: any ExerciseServiceProtocol

    // MARK: - Init

    /// Standard init for the Charts tab (multi-exercise selection mode).
    init(chartDataService: any ChartDataServiceProtocol,
         exerciseService: any ExerciseServiceProtocol) {
        self.chartDataService = chartDataService
        self.exerciseService = exerciseService
        self.isEmbeddedMode = false
    }

    /// Embedded init for ActiveWorkout / ExerciseDetail — pre-selects a single exercise.
    init(chartDataService: any ChartDataServiceProtocol,
         exerciseService: any ExerciseServiceProtocol,
         preselectedExercise: (id: UUID, name: String, category: String)) {
        self.chartDataService = chartDataService
        self.exerciseService = exerciseService
        self.isEmbeddedMode = true
        self.selectedExercises = [(id: preselectedExercise.id, name: preselectedExercise.name, category: preselectedExercise.category)]
    }

    // MARK: - Data Loading

    func loadData() async {
        guard !selectedExercises.isEmpty else {
            chartData = nil
            trendLine = nil
            selectedDataIndex = nil
            return
        }

        isLoading = true
        do {
            let exerciseIds = selectedExercises.map { $0.id }
            let data = try await chartDataService.fetchExerciseProgress(
                metric: selectedMetric,
                exerciseIds: exerciseIds,
                timeRange: selectedTimeRange
            )
            chartData = data

            // Compute trend line for first series only
            if let firstSeries = data.first, firstSeries.points.count >= 2 {
                trendLine = TrendLineCalculator.compute(values: firstSeries.points.map { $0.value })
            } else {
                trendLine = nil
            }

            // Set selected data index to latest point of first series
            if let firstSeries = data.first, !firstSeries.points.isEmpty {
                selectedDataIndex = firstSeries.points.count - 1
            } else {
                selectedDataIndex = nil
            }
        } catch {
            print("[ExercisesTab] Error loading data: \(error)")
        }
        isLoading = false
    }

    func changeMetric(_ metric: ExerciseMetric) async {
        selectedMetric = metric
        chartData = nil
        await loadData()
    }

    func updateExercises(_ newSelection: [(id: UUID, name: String, category: String)]) async {
        selectedExercises = newSelection
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
        guard let data = chartData, let firstSeries = data.first,
              !firstSeries.points.isEmpty else { return }
        guard let current = selectedDataIndex else {
            selectedDataIndex = firstSeries.points.count - 1
            return
        }
        switch direction {
        case .previous:
            if current > 0 { selectedDataIndex = current - 1 }
        case .next:
            if current < firstSeries.points.count - 1 { selectedDataIndex = current + 1 }
        }
    }

    enum NavigationDirection { case previous, next }

    // MARK: - Formatting Helpers

    var yAxisLabel: String {
        switch selectedMetric {
        case .estimatedOneRM, .maxWeight, .maxVolume, .maxWeightForReps, .workoutVolume, .personalRecords:
            return "kg"
        case .maxReps, .workoutReps:
            return "reps"
        case .maxDistance:
            return "m"
        case .maxTime:
            return "sec"
        case .minPace:
            return "m/s"
        }
    }

    var selectedValueFormatted: String? {
        guard let data = chartData, let firstSeries = data.first,
              let index = selectedDataIndex,
              index >= 0, index < firstSeries.points.count else { return nil }
        let point = firstSeries.points[index]
        switch selectedMetric {
        case .estimatedOneRM, .maxWeight, .maxWeightForReps, .personalRecords:
            return String(format: "%.1f kg", point.value)
        case .maxVolume, .workoutVolume:
            return String(format: "%.0f kg", point.value)
        case .maxReps, .workoutReps:
            return "\(Int(point.value)) reps"
        case .maxDistance:
            if point.value >= 1000 {
                return String(format: "%.2f km", point.value / 1000)
            }
            return String(format: "%.0f m", point.value)
        case .maxTime:
            let minutes = Int(point.value) / 60
            let seconds = Int(point.value) % 60
            return String(format: "%d:%02d", minutes, seconds)
        case .minPace:
            return String(format: "%.2f m/s", point.value)
        }
    }

    var selectedDateFormatted: String? {
        guard let data = chartData, let firstSeries = data.first,
              let index = selectedDataIndex,
              index >= 0, index < firstSeries.points.count else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: firstSeries.points[index].date)
    }

    /// Weight x reps detail for the selected data point (e.g. "85 kg x 8 reps").
    var selectedDetailFormatted: String? {
        guard let data = chartData, let firstSeries = data.first,
              let index = selectedDataIndex,
              index >= 0, index < firstSeries.points.count else { return nil }
        let point = firstSeries.points[index]
        guard let weight = point.topWeight, let reps = point.topReps else { return nil }
        if weight == weight.rounded() && weight == Double(Int(weight)) {
            return "\(Int(weight)) kg \u{00D7} \(reps) reps"
        }
        return String(format: "%.1f kg \u{00D7} %d reps", weight, reps)
    }

    /// The workoutId of the currently selected data point, if available.
    var selectedWorkoutId: UUID? {
        guard let data = chartData, let firstSeries = data.first,
              let index = selectedDataIndex,
              index >= 0, index < firstSeries.points.count else { return nil }
        return firstSeries.points[index].workoutId
    }

    var hasPreviousDataPoint: Bool {
        guard let index = selectedDataIndex else { return false }
        return index > 0
    }

    var hasNextDataPoint: Bool {
        guard let data = chartData, let firstSeries = data.first,
              let index = selectedDataIndex else { return false }
        return index < firstSeries.points.count - 1
    }

    /// Display text for the exercise selection button
    var exerciseSelectionLabel: String {
        if selectedExercises.isEmpty {
            return "Select Exercises"
        }
        let names = selectedExercises.map { $0.name }
        if names.count <= 2 {
            return names.joined(separator: ", ")
        }
        return "\(names[0]), \(names[1]) +\(names.count - 2) more"
    }
}
