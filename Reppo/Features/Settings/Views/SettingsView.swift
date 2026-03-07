// SettingsView.swift
// Main Settings screen with 5 sections: GENERAL, WORKOUT PREFERENCES, DATA, BODY, ABOUT.
// Spec: FR-010, User Stories 1-2, acceptance scenarios
// Feature: 010-settings-and-onboarding WP02 T007/T011/T012

import SwiftUI

struct SettingsView: View {

    // MARK: - State

    @State private var viewModel: SettingsViewModel
    private let settingsService: any SettingsServiceProtocol
    private let bodyweightService: any BodyweightServiceProtocol
    private let importService: any ImportServiceProtocol
    private let exportService: any ExportServiceProtocol

    // MARK: - Init

    init(settingsService: any SettingsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol,
         importService: any ImportServiceProtocol,
         exportService: any ExportServiceProtocol) {
        _viewModel = State(initialValue: SettingsViewModel(settingsService: settingsService))
        self.settingsService = settingsService
        self.bodyweightService = bodyweightService
        self.importService = importService
        self.exportService = exportService
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                workoutPreferencesSection
                weightPrescriptionSection
                dataSection
                bodySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Settings")
            .task { await viewModel.loadProfile() }
            .overlay {
                if viewModel.isRebuilding {
                    rebuildOverlay
                }
            }
            // Sheets
            .sheet(isPresented: $viewModel.showUnitsSheet) {
                UnitPickerSheet(
                    currentUnit: viewModel.profile?.unitPreference ?? .metric
                ) { unit in
                    Task { await viewModel.updateUnitPreference(unit) }
                }
            }
            .sheet(isPresented: $viewModel.showFormulaSheet) {
                FormulaPickerSheet(
                    currentFormula: E1RMFormula(rawValue: viewModel.profile?.e1RMFormula ?? "epley") ?? .epley
                ) { formula in
                    Task { await viewModel.updateE1RMFormula(formula) }
                }
            }
            .sheet(isPresented: $viewModel.showRestTimeSheet) {
                RestTimePickerSheet(
                    currentSeconds: viewModel.profile?.defaultRestTimeSeconds
                ) { seconds in
                    Task { await viewModel.updateDefaultRestTime(seconds) }
                }
            }
            // Alerts
            .alert("Rebuild Volume Stats?", isPresented: $viewModel.showRebuildVolumeConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Rebuild") {
                    Task { await viewModel.toggleWarmupVolume() }
                }
            } message: {
                Text("This will recompute all volume statistics. This may take a moment.")
            }
            .alert("Rebuild Personal Records?", isPresented: $viewModel.showRebuildPRsConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Rebuild") {
                    Task { await viewModel.toggleWarmupPRs() }
                }
            } message: {
                Text("This will rebuild all personal records. This may take a moment.")
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - GENERAL Section

    private var generalSection: some View {
        Section("General") {
            Button {
                viewModel.showUnitsSheet = true
            } label: {
                HStack {
                    Label("Units", systemImage: "scalemass")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(viewModel.unitDisplayName)
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Button {
                viewModel.showFormulaSheet = true
            } label: {
                HStack {
                    Label("e1RM Formula", systemImage: "function")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(viewModel.formulaDisplayName)
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    // MARK: - WORKOUT PREFERENCES Section

    private var workoutPreferencesSection: some View {
        Section("Workout Preferences") {
            Toggle(isOn: Binding(
                get: { viewModel.profile?.includeWarmupsInVolume ?? false },
                set: { _ in viewModel.confirmToggleWarmupVolume() }
            )) {
                Label("Include Warmups in Volume", systemImage: "flame")
                    .foregroundStyle(Color.textPrimary)
            }

            Toggle(isOn: Binding(
                get: { viewModel.profile?.includeWarmupsInPRs ?? false },
                set: { _ in viewModel.confirmToggleWarmupPRs() }
            )) {
                Label("Include Warmups in PRs", systemImage: "trophy")
                    .foregroundStyle(Color.textPrimary)
            }

            Button {
                viewModel.showRestTimeSheet = true
            } label: {
                HStack {
                    Label("Default Rest Time", systemImage: "timer")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(viewModel.restTimeDisplayName)
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    // MARK: - WEIGHT PRESCRIPTION Section

    private var weightPrescriptionSection: some View {
        Section("Weight Prescription") {
            Toggle(isOn: Binding(
                get: { viewModel.prescriptionEnabled },
                set: { newValue in
                    Task {
                        do {
                            try await settingsService.updatePrescriptionEnabled(newValue)
                            await viewModel.loadProfile()
                        } catch {}
                    }
                }
            )) {
                Label("Smart Suggestions", systemImage: "wand.and.stars")
                    .foregroundStyle(Color.textPrimary)
            }

            if viewModel.prescriptionEnabled {
                HStack {
                    Label("Default Increment", systemImage: "plusminus")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.profile?.prescriptionDefaultIncrement ?? 2.5 },
                        set: { newValue in
                            Task {
                                do {
                                    try await settingsService.updatePrescriptionDefaultIncrement(newValue)
                                    await viewModel.loadProfile()
                                } catch {}
                            }
                        }
                    )) {
                        Text("0.5 kg").tag(0.5)
                        Text("1.0 kg").tag(1.0)
                        Text("1.25 kg").tag(1.25)
                        Text("2.0 kg").tag(2.0)
                        Text("2.5 kg").tag(2.5)
                        Text("5.0 kg").tag(5.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if let profile = viewModel.profile {
                    NavigationLink {
                        PrescriptionAdvancedSettingsView(
                            profile: profile,
                            settingsService: settingsService
                        )
                    } label: {
                        Label("Advanced", systemImage: "slider.horizontal.3")
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - DATA Section

    private var dataSection: some View {
        Section("Data") {
            NavigationLink {
                ImportView(importService: importService)
            } label: {
                Label("Import Data (CSV)", systemImage: "square.and.arrow.down")
                    .foregroundStyle(Color.textPrimary)
            }

            NavigationLink {
                ExportView(exportService: exportService)
            } label: {
                Label("Export Data (CSV)", systemImage: "square.and.arrow.up")
                    .foregroundStyle(Color.textPrimary)
            }

            NavigationLink {
                RebuildStatsView(settingsService: settingsService)
            } label: {
                Label("Rebuild Stats", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    // MARK: - BODY Section

    private var bodySection: some View {
        Section("Body") {
            NavigationLink {
                BodyweightLogView(
                    bodyweightService: bodyweightService,
                    settingsService: settingsService
                )
            } label: {
                Label("Bodyweight Log", systemImage: "figure.stand")
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    // MARK: - ABOUT Section

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Label("Version", systemImage: "info.circle")
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(viewModel.appVersion)
                    .foregroundStyle(Color.textSecondary)
            }

            Button {
                viewModel.sendFeedback()
            } label: {
                Label("Send Feedback", systemImage: "envelope")
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    // MARK: - Rebuild Overlay

    private var rebuildOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.accent)
                Text("Rebuilding…")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(24)
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
