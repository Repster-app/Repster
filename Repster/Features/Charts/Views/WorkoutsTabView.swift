// WorkoutsTabView.swift
// Workouts tab composing dropdowns + time pills + line chart + slope badge + data navigator.
// Feature: 016-charts-tab-v2 WP07 (T121)

import SwiftUI

struct WorkoutsTabView: View {

    @Bindable var viewModel: WorkoutsTabViewModel
    @Environment(ServiceContainer.self) private var services

    var body: some View {
        VStack(spacing: 16) {
            // Metric + Aggregation dropdowns (side by side)
            HStack(spacing: 8) {
                ChartDropdown(
                    options: WorkoutsMetric.allCases,
                    selected: $viewModel.selectedMetric,
                    labelFor: { $0.rawValue }
                )
                .onChange(of: viewModel.selectedMetric) { _, newMetric in
                    Task { await viewModel.changeMetric(newMetric) }
                }

                ChartDropdown(
                    options: WorkoutsAggregation.allCases,
                    selected: $viewModel.selectedAggregation,
                    labelFor: { $0.rawValue }
                )
                .onChange(of: viewModel.selectedAggregation) { _, newAgg in
                    Task { await viewModel.changeAggregation(newAgg) }
                }
            }

            // Category + Exercise filter dropdowns (side by side)
            HStack(spacing: 8) {
                // Category dropdown
                ChartDropdown(
                    options: viewModel.categoryOptions,
                    selected: $viewModel.selectedCategory,
                    labelFor: { $0 == "All" ? "Category" : $0 }
                )
                .onChange(of: viewModel.selectedCategory) { _, newCat in
                    Task { await viewModel.changeCategory(newCat) }
                }

                // Exercise dropdown
                ChartDropdown(
                    options: viewModel.exerciseOptions,
                    selected: $viewModel.selectedExerciseFilter,
                    labelFor: { $0.displayName == "All" ? "Exercise" : $0.displayName }
                )
                .onChange(of: viewModel.selectedExerciseFilter) { _, newFilter in
                    Task { await viewModel.changeExerciseFilter(newFilter) }
                }
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
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let data = viewModel.chartData, !data.isEmpty {
                    // Line+Point chart (tap dots to select)
                    TimeSeriesBarChart(
                        data: data,
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

                    // Data point navigator — clickable in Per Workout mode
                    if let workoutId = viewModel.selectedWorkoutId {
                        // Per Workout mode: tappable to navigate to workout detail
                        NavigationLink(value: workoutId) {
                            dataPointContent
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Other modes: non-clickable
                        dataPointContent
                    }
                } else {
                    emptyState
                }
            }
            .padding(16)
            .background(Color.bgCard)
            .cornerRadius(16)
        }
        .navigationDestination(for: UUID.self) { workoutId in
            WorkoutDetailFromHomeView(
                workoutId: workoutId,
                workoutService: services.workoutService,
                setService: services.setService,
                exerciseService: services.exerciseService,
                statsService: services.statsService
            )
        }
        .task {
            if viewModel.chartData == nil {
                await viewModel.loadFilterOptions()
                await viewModel.loadData()
            }
        }
    }

    // MARK: - Data Point Navigator Content

    private var dataPointContent: some View {
        VStack(spacing: 0) {
            DataPointNavigator(
                value: viewModel.selectedValueFormatted,
                subtitle: viewModel.selectedDateFormatted,
                promptText: "Select a data point",
                hasPrevious: viewModel.hasPreviousDataPoint,
                hasNext: viewModel.hasNextDataPoint,
                onPrevious: { viewModel.navigateDataPoint(direction: .previous) },
                onNext: { viewModel.navigateDataPoint(direction: .next) }
            )

            // Show "Tap to view workout" hint in Per Workout mode
            if viewModel.selectedWorkoutId != nil {
                Text("Tap to view workout →")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
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

// MARK: - String + Identifiable for ChartDropdown

extension String: @retroactive Identifiable {
    public var id: String { self }
}
