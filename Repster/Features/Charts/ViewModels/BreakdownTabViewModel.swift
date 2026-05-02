// BreakdownTabViewModel.swift
// ViewModel for the Breakdown tab — manages metric/time range state, loads donut chart data.
// Feature: 016-charts-tab-v2 WP06 (T114)

import SwiftUI

@Observable
final class BreakdownTabViewModel {

    // MARK: - State

    var selectedMetric: BreakdownMetric = .volumeByCategory
    var selectedTimeRange: BreakdownTimeRange = .all
    var chartData: [BreakdownDataPoint]?
    var summary: BreakdownSummary?
    var isLoading = false
    var dateRangeLabel: String = ""
    private var earliestWorkoutDate: Date?

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
            let data = try await chartDataService.fetchBreakdownData(
                metric: selectedMetric, timeRange: selectedTimeRange
            )
            chartData = data
            summary = try await chartDataService.fetchBreakdownSummary(timeRange: selectedTimeRange)
            if earliestWorkoutDate == nil {
                earliestWorkoutDate = try await chartDataService.fetchEarliestWorkoutDate()
            }
            updateDateRangeLabel()
        } catch {
            print("[BreakdownTab] Error loading data: \(error)")
        }
        isLoading = false
    }

    func changeMetric(_ metric: BreakdownMetric) async {
        selectedMetric = metric
        chartData = nil
        await loadData()
    }

    func changeTimeRange(_ range: BreakdownTimeRange) async {
        selectedTimeRange = range
        chartData = nil
        await loadData()
    }

    // MARK: - Helpers

    private func updateDateRangeLabel() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let start = selectedTimeRange.startDate ?? earliestWorkoutDate ?? Date()
        dateRangeLabel = "\(formatter.string(from: start)) → \(formatter.string(from: Date()))"
    }

    /// Compute percentage for a data point relative to total
    func percentage(for point: BreakdownDataPoint) -> String {
        guard let data = chartData else { return "" }
        let total = data.reduce(0) { $0 + $1.value }
        guard total > 0 else { return "0%" }
        let pct = (point.value / total) * 100
        return String(format: "%.0f%%", pct)
    }

    /// Format the value based on current metric type (with thousand separators)
    func formattedValue(for point: BreakdownDataPoint) -> String {
        let formatted = formatNumber(point.value)
        switch selectedMetric.aggregateType {
        case .volume:
            return "\(formatted) kg"
        case .sets:
            return "\(formatted) sets"
        case .reps:
            return "\(formatted) reps"
        case .workouts:
            return "\(formatted)"
        }
    }

    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}
