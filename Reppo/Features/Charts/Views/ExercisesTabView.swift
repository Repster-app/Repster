// ExercisesTabView.swift
// Exercises tab composing metric dropdown + exercise trigger + time pills + line chart + legend.
// Feature: 016-charts-tab-v2 WP08 (T127), WP09 (T133)

import SwiftUI

struct ExercisesTabView: View {

    @Bindable var viewModel: ExercisesTabViewModel
    @Environment(ServiceContainer.self) private var services
    @State private var workoutIdForDetail: UUID?

    var body: some View {
        VStack(spacing: 16) {
            // Metric dropdown
            ChartDropdown(
                options: ExerciseMetric.allCases,
                selected: $viewModel.selectedMetric,
                labelFor: { $0.rawValue }
            )
            .onChange(of: viewModel.selectedMetric) { _, newMetric in
                Task { await viewModel.changeMetric(newMetric) }
            }

            // Exercise selection trigger button (WP09 T133) — hidden in embedded mode
            if !viewModel.isEmbeddedMode {
                Button {
                    viewModel.showExerciseSelector = true
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12, weight: .semibold))
                        Text(viewModel.exerciseSelectionLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(viewModel.selectedExercises.isEmpty ? Color.textSecondary : Color.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(viewModel.selectedExercises.isEmpty ? Color.border : Color.accent.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            // Time range pills
            ChartTimePills(
                options: WorkoutsTimeRange.allCases,
                selected: $viewModel.selectedTimeRange,
                labelFor: { $0.rawValue }
            )
            .onChange(of: viewModel.selectedTimeRange) { _, newRange in
                Task { await viewModel.changeTimeRange(newRange) }
            }

            // Chart card
            VStack(spacing: 12) {
                if viewModel.selectedExercises.isEmpty {
                    // Prompt state (T128)
                    promptState
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let data = viewModel.chartData, !data.isEmpty {
                    // Multi-line chart (tap dots to select)
                    MultiLineChart(
                        series: data,
                        trendLine: viewModel.trendLine,
                        yAxisLabel: viewModel.yAxisLabel,
                        selectedIndex: viewModel.selectedDataIndex,
                        onSelectIndex: { index in
                            viewModel.selectedDataIndex = index
                        }
                    )

                    // Slope badge
                    if let trendLine = viewModel.trendLine {
                        HStack {
                            SlopeBadge(trendLine: trendLine)
                            Spacer()
                        }
                    }

                    // Data point navigator
                    DataPointNavigator(
                        value: viewModel.selectedValueFormatted,
                        subtitle: viewModel.selectedDateFormatted,
                        promptText: "Browse data points",
                        hasPrevious: viewModel.hasPreviousDataPoint,
                        hasNext: viewModel.hasNextDataPoint,
                        onPrevious: { viewModel.navigateDataPoint(direction: .previous) },
                        onNext: { viewModel.navigateDataPoint(direction: .next) }
                    )

                    // "View Workout" button when a data point with workoutId is selected
                    if let workoutId = viewModel.selectedWorkoutId {
                        Button {
                            workoutIdForDetail = workoutId
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("View Workout")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(Color.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.accent.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }

                    // Exercise color legend
                    ChartLegend(
                        items: data.map { series in
                            ChartLegendItem(
                                label: series.name,
                                value: series.points.last.map { formatValue($0.value) },
                                color: series.color
                            )
                        }
                    )
                } else {
                    // No data for selected exercises + metric
                    emptyState
                }
            }
            .padding(16)
            .background(Color.bgCard)
            .cornerRadius(16)
        }
        .sheet(isPresented: $viewModel.showExerciseSelector) {
            ExerciseSelectionSheet(
                selectedExercises: $viewModel.selectedExercises,
                isPresented: $viewModel.showExerciseSelector,
                onApply: {
                    Task { await viewModel.loadData() }
                },
                exerciseService: viewModel.exerciseService
            )
        }
        .sheet(isPresented: Binding(
            get: { workoutIdForDetail != nil },
            set: { if !$0 { workoutIdForDetail = nil } }
        )) {
            if let workoutId = workoutIdForDetail {
                NavigationStack {
                    WorkoutDetailFromHomeView(
                        workoutId: workoutId,
                        workoutService: services.workoutService,
                        setService: services.setService,
                        exerciseService: services.exerciseService,
                        statsService: services.statsService
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                workoutIdForDetail = nil
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Prompt State (no exercises selected)

    private var promptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("Select exercises to view progress")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Empty State (exercises selected but no data)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("No data for this period")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func formatValue(_ value: Double) -> String {
        switch viewModel.selectedMetric {
        case .estimatedOneRM, .maxWeight, .maxWeightForReps, .personalRecords:
            return String(format: "%.1f kg", value)
        case .maxVolume, .workoutVolume:
            return String(format: "%.0f kg", value)
        case .maxReps, .workoutReps:
            return "\(Int(value))"
        case .maxDistance:
            if value >= 1000 { return String(format: "%.1f km", value / 1000) }
            return String(format: "%.0f m", value)
        case .maxTime:
            return String(format: "%.0fs", value)
        case .minPace:
            return String(format: "%.2f m/s", value)
        }
    }
}
