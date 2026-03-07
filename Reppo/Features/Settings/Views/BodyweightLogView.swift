// BodyweightLogView.swift
// Bodyweight log with trend chart, entry list with swipe-to-delete, and add sheet.
// Spec: FR-008, User Story 3
// Feature: 010-settings-and-onboarding WP03 T015/T016/T018

import SwiftUI
import Charts

struct BodyweightLogView: View {

    // MARK: - State

    @State private var viewModel: BodyweightLogViewModel

    // MARK: - Init

    init(bodyweightService: any BodyweightServiceProtocol,
         settingsService: any SettingsServiceProtocol) {
        _viewModel = State(initialValue: BodyweightLogViewModel(
            bodyweightService: bodyweightService,
            settingsService: settingsService
        ))
    }

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.hasEntries {
                emptyState
            } else {
                List {
                    chartSection
                    entryListSection
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Bodyweight Log")
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { viewModel.showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            AddBodyweightEntrySheet(
                unitPreference: viewModel.unitPreference
            ) { weightKg, date in
                Task { await viewModel.addEntry(weightKg: weightKg, date: date) }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .task { await viewModel.loadEntries() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "scalemass")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No Bodyweight Entries")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Log your bodyweight to track trends and improve accuracy for bodyweight exercises.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add Entry") { viewModel.showAddSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chart Section (T016)

    private var chartSection: some View {
        Section {
            Chart(viewModel.entriesForChart, id: \.id) { entry in
                let weight = viewModel.displayWeight(for: entry)

                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", weight)
                )
                .foregroundStyle(Color.accent)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", weight)
                )
                .foregroundStyle(Color.accent)
                .symbolSize(30)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let weight = value.as(Double.self) {
                            Text("\(weight, specifier: "%.0f") \(viewModel.unitLabel)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(height: 200)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Entry List Section (T018 — swipe-to-delete)

    private var entryListSection: some View {
        Section("Entries") {
            ForEach(viewModel.entries, id: \.id) { entry in
                HStack {
                    Text(entry.date, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(viewModel.displayWeight(for: entry), specifier: "%.1f") \(viewModel.unitLabel)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let entry = viewModel.entries[index]
                    Task { await viewModel.deleteEntry(entry) }
                }
            }
        }
    }
}
