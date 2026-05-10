// BreakdownTabView.swift
// Breakdown tab composing dropdown + time pills + donut chart + legend + summary stats.
// Feature: 016-charts-tab-v2 WP06 (T116)

import SwiftUI

struct BreakdownTabView: View {

    @Bindable var viewModel: BreakdownTabViewModel
    @State private var selectedSlice: BreakdownDataPoint?

    var body: some View {
        VStack(spacing: 16) {
            // Metric dropdown
            ChartDropdown(
                options: BreakdownMetric.allCases,
                selected: $viewModel.selectedMetric,
                labelFor: { $0.rawValue }
            )
            .onChange(of: viewModel.selectedMetric) { _, newMetric in
                selectedSlice = nil
                Task { await viewModel.changeMetric(newMetric) }
            }

            // Time range pills
            ChartTimePills(
                options: BreakdownTimeRange.allCases,
                selected: $viewModel.selectedTimeRange,
                labelFor: { $0.rawValue }
            )
            .onChange(of: viewModel.selectedTimeRange) { _, newRange in
                selectedSlice = nil
                Task { await viewModel.changeTimeRange(newRange) }
            }

            // Chart card
            VStack(spacing: 16) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let data = viewModel.chartData, !data.isEmpty {
                    // Donut chart with center text + tap-to-select
                    DonutChartView(
                        data: data,
                        centerValue: centerValueText,
                        centerLabel: centerLabelText,
                        selectedSliceLabel: selectedSlice?.label,
                        onSelectSlice: { slice in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSlice = slice
                            }
                        }
                    )

                    // Legend with percentages
                    ChartLegend(
                        items: data.map { point in
                            ChartLegendItem(
                                label: point.label,
                                value: viewModel.percentage(for: point),
                                color: point.color
                            )
                        }
                    )

                    // Date range label
                    Text(viewModel.dateRangeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiary)

                    // Summary stats row (all 4 totals per spec)
                    if let summary = viewModel.summary {
                        summaryStatsRow(summary: summary)
                    }
                } else {
                    // Empty state (T117)
                    emptyState
                }
            }
            .padding(16)
            .background(Color.bgCard)
            .cornerRadius(16)
        }
        .task {
            if viewModel.chartData == nil {
                await viewModel.loadData()
            }
        }
    }

    // MARK: - Center Text (default = total, selected = slice detail)

    private var centerValueText: String {
        if let slice = selectedSlice {
            return viewModel.formattedValue(for: slice)
        }
        // Default: show the relevant total from summary
        guard let summary = viewModel.summary else { return "" }
        switch viewModel.selectedMetric.aggregateType {
        case .volume:
            return formatVolume(summary.totalVolume)
        case .sets:
            return formatIntWithSeparator(summary.totalSets)
        case .reps:
            return formatIntWithSeparator(summary.totalReps)
        case .workouts:
            return formatIntWithSeparator(summary.totalWorkouts)
        }
    }

    private var centerLabelText: String {
        if let slice = selectedSlice {
            return "\(slice.label) · \(viewModel.percentage(for: slice))"
        }
        // Default: show the metric type
        switch viewModel.selectedMetric.aggregateType {
        case .volume: return "Total Volume"
        case .sets: return "Total Sets"
        case .reps: return "Total Reps"
        case .workouts: return "Total Workouts"
        }
    }

    // MARK: - Summary Stats Row (4-column: Volume, Sets, Reps, Workouts)

    private func summaryStatsRow(summary: BreakdownSummary) -> some View {
        HStack(spacing: 0) {
            statItem(label: "Volume", value: formatVolume(summary.totalVolume))
            Spacer()
            statItem(label: "Sets", value: formatIntWithSeparator(summary.totalSets))
            Spacer()
            statItem(label: "Reps", value: formatIntWithSeparator(summary.totalReps))
            Spacer()
            statItem(label: "Workouts", value: formatIntWithSeparator(summary.totalWorkouts))
        }
        .padding(.top, 8)
    }

    private func formatVolume(_ volume: Double) -> String {
        let displayVolume = UnitConversion.displayedWeight(volume, unitPreference: viewModel.unitPreference)
        let unit = UnitConversion.weightUnitLabel(for: viewModel.unitPreference)
        if displayVolume >= 1_000_000 {
            return String(format: "%.1fM %@", displayVolume / 1_000_000, unit as NSString)
        }
        if displayVolume >= 1000 {
            return String(format: "%.0fk %@", displayVolume / 1000, unit as NSString)
        }
        return "\(formatWithSeparator(displayVolume)) \(unit)"
    }

    private func formatWithSeparator(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func formatIntWithSeparator(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Empty State (T117)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("No data for this period")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
