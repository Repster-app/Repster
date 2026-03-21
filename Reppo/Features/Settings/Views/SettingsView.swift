// SettingsView.swift
// Main Settings overview screen with 5 sections and navigable detail screens.
// Spec: FR-010, User Stories 1-2, acceptance scenarios
// Feature: 010-settings-and-onboarding WP02 T007/T011/T012

import SwiftUI

enum SettingsDataDestination: CaseIterable {
    case importCSV
    case exportBackup
    case restoreBackup
    case resetAppData

    var title: String {
        switch self {
        case .importCSV:
            return "Import Data (CSV)"
        case .exportBackup:
            return "Export Backup"
        case .restoreBackup:
            return "Restore Backup"
        case .resetAppData:
            return "Reset App Data"
        }
    }

    var systemImage: String {
        switch self {
        case .importCSV:
            return "square.and.arrow.down"
        case .exportBackup:
            return "square.and.arrow.up"
        case .restoreBackup:
            return "arrow.clockwise.circle"
        case .resetAppData:
            return "trash"
        }
    }
}

struct SettingsView: View {

    // MARK: - State

    @State private var viewModel: SettingsViewModel
    private let settingsService: any SettingsServiceProtocol
    private let bodyweightService: any BodyweightServiceProtocol
    private let importService: any ImportServiceProtocol
    private let workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol
    private let fatigueLearningService: FatigueLearningService

    // MARK: - Init

    init(settingsService: any SettingsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol,
         importService: any ImportServiceProtocol,
         workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol,
         fatigueLearningService: FatigueLearningService) {
        _viewModel = State(initialValue: SettingsViewModel(settingsService: settingsService))
        self.settingsService = settingsService
        self.bodyweightService = bodyweightService
        self.importService = importService
        self.workoutHistoryBackupService = workoutHistoryBackupService
        self.fatigueLearningService = fatigueLearningService
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                workoutSection
                dataSection
                bodySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Settings")
            .task { await viewModel.loadProfile() }
            .onAppear {
                guard viewModel.profile != nil else { return }
                Task { await viewModel.refreshProfile() }
            }
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
                SettingsNavigationRow(
                    title: "Units",
                    systemImage: "scalemass"
                )
            }

            Button {
                viewModel.showFormulaSheet = true
            } label: {
                SettingsNavigationRow(
                    title: "e1RM Formula",
                    systemImage: "function"
                )
            }
        }
    }

    // MARK: - WORKOUT Section

    private var workoutSection: some View {
        Section("Workout") {
            NavigationLink {
                WorkoutPreferencesView(viewModel: viewModel)
            } label: {
                SettingsNavigationRow(
                    title: "Workout Preferences",
                    systemImage: "timer",
                    showChevron: false
                )
            }

            NavigationLink {
                SmartSuggestionsSettingsView(
                    viewModel: viewModel,
                    settingsService: settingsService,
                    fatigueLearningService: fatigueLearningService
                )
            } label: {
                SettingsNavigationRow(
                    title: "Smart Suggestions",
                    systemImage: "wand.and.stars",
                    showChevron: false
                )
            }
        }
    }

    // MARK: - DATA Section

    private var dataSection: some View {
        Section("Data") {
            NavigationLink {
                DataBackupsView(
                    importService: importService,
                    workoutHistoryBackupService: workoutHistoryBackupService,
                    settingsService: settingsService,
                    onDataReset: {
                        await viewModel.refreshProfile()
                        LiveActivityManager().cleanupStaleActivities()
                    }
                )
            } label: {
                SettingsNavigationRow(
                    title: "Data & Backups",
                    systemImage: "externaldrive.badge.icloud",
                    showChevron: false
                )
            }

            NavigationLink {
                RebuildStatsView(settingsService: settingsService)
            } label: {
                SettingsNavigationRow(
                    title: "Rebuild Stats",
                    systemImage: "arrow.triangle.2.circlepath",
                    showChevron: false
                )
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
                SettingsNavigationRow(
                    title: "Bodyweight Log",
                    systemImage: "figure.stand",
                    showChevron: false
                )
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
                SettingsNavigationRow(
                    title: "Send Feedback",
                    systemImage: "envelope"
                )
            }
        }
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let systemImage: String
    var summary: String? = nil
    var titleColor: Color = .textPrimary
    var summaryColor: Color = .textSecondary
    var showChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(titleColor)

            Spacer(minLength: 12)

            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(summaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

private struct WorkoutPreferencesView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
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
                    SettingsNavigationRow(
                        title: "Default Rest Time",
                        systemImage: "timer",
                        summary: viewModel.restTimeDisplayName
                    )
                }

                Button {
                    viewModel.showWarmupRestTimeSheet = true
                } label: {
                    SettingsNavigationRow(
                        title: "Warmup Rest Time",
                        systemImage: "timer",
                        summary: viewModel.warmupRestTimeDisplayName
                    )
                }

                HStack {
                    Label("Timer Alert", systemImage: "bell")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.profile?.restTimerAlert ?? "both" },
                        set: { newValue in
                            Task { await viewModel.updateRestTimerAlert(newValue) }
                        }
                    )) {
                        Text("Off").tag("off")
                        Text("Vibration").tag("vibration")
                        Text("Sound").tag("sound")
                        Text("Both").tag("both")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            } footer: {
                Text("Warmup changes rebuild affected records so the rest of the app stays consistent.")
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Workout Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await viewModel.refreshProfile() }
        }
        .sheet(isPresented: $viewModel.showRestTimeSheet) {
            RestTimePickerSheet(
                currentSeconds: viewModel.profile?.defaultRestTimeSeconds ?? 150
            ) { seconds in
                Task { await viewModel.updateDefaultRestTime(seconds) }
            }
        }
        .sheet(isPresented: $viewModel.showWarmupRestTimeSheet) {
            RestTimePickerSheet(
                currentSeconds: viewModel.profile?.defaultWarmupRestTimeSeconds,
                title: "Warmup Rest Time"
            ) { seconds in
                Task { await viewModel.updateDefaultWarmupRestTime(seconds) }
            }
        }
        .overlay {
            if viewModel.isRebuilding {
                SettingsRebuildOverlay()
            }
        }
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

private struct SmartSuggestionsSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let settingsService: any SettingsServiceProtocol
    let fatigueLearningService: FatigueLearningService

    private static let incrementOptions = [0.5, 1.0, 1.25, 2.0, 2.5, 5.0]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.smartSuggestionsEnabled },
                    set: { newValue in
                        Task { await viewModel.updatePrescriptionEnabled(newValue) }
                    }
                )) {
                    Label("Enable Smart Suggestions", systemImage: "wand.and.stars")
                        .foregroundStyle(Color.textPrimary)
                }

                if viewModel.smartSuggestionsEnabled {
                    HStack {
                        Label("Default Increment", systemImage: "plusminus")
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { viewModel.profile?.prescriptionDefaultIncrement ?? 2.5 },
                            set: { newValue in
                                Task { await viewModel.updatePrescriptionDefaultIncrement(newValue) }
                            }
                        )) {
                            ForEach(Self.incrementOptions, id: \.self) { increment in
                                Text(incrementLabel(for: increment)).tag(increment)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

            } footer: {
                Text("Default increment controls how suggested weights are rounded before they appear in your workout.")
                    .foregroundStyle(Color.textTertiary)
            }

            if let profile = viewModel.profile, viewModel.smartSuggestionsEnabled {
                SmartSuggestionsAdvancedSections(
                    profile: profile,
                    settingsService: settingsService,
                    fatigueLearningService: fatigueLearningService
                )
            }

            Section { EmptyView() }
                .listRowBackground(Color.clear)
                .frame(height: 80)
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Smart Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await viewModel.refreshProfile() }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private func incrementLabel(for increment: Double) -> String {
        if increment.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f kg", increment)
        }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: increment)) ?? String(format: "%.2f", increment)
        return "\(formatted) kg"
    }
}

private struct DataBackupsView: View {
    let importService: any ImportServiceProtocol
    let workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let onDataReset: @MainActor @Sendable () async -> Void

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ImportView(importService: importService)
                } label: {
                    SettingsNavigationRow(
                        title: SettingsDataDestination.importCSV.title,
                        systemImage: SettingsDataDestination.importCSV.systemImage,
                        showChevron: false
                    )
                }

                NavigationLink {
                    ExportView(workoutHistoryBackupService: workoutHistoryBackupService)
                } label: {
                    SettingsNavigationRow(
                        title: SettingsDataDestination.exportBackup.title,
                        systemImage: SettingsDataDestination.exportBackup.systemImage,
                        showChevron: false
                    )
                }

                NavigationLink {
                    RestoreBackupView(workoutHistoryBackupService: workoutHistoryBackupService)
                } label: {
                    SettingsNavigationRow(
                        title: SettingsDataDestination.restoreBackup.title,
                        systemImage: SettingsDataDestination.restoreBackup.systemImage,
                        showChevron: false
                    )
                }
            } footer: {
                Text("Import training data from a CSV file, create a Reppo backup archive, or restore workout history. Restoring replaces workout history only. Templates, programs, bodyweight logs, and settings stay untouched.")
                    .foregroundStyle(Color.textTertiary)
            }

            Section {
                NavigationLink {
                    ResetAppDataView(
                        settingsService: settingsService,
                        onResetComplete: onDataReset
                    )
                } label: {
                    SettingsNavigationRow(
                        title: SettingsDataDestination.resetAppData.title,
                        systemImage: SettingsDataDestination.resetAppData.systemImage,
                        titleColor: .danger,
                        showChevron: false
                    )
                }
            } footer: {
                Text("Reset deletes all local app data, restores the built-in exercise library, and keeps onboarding completed.")
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Data & Backups")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ResetAppDataView: View {
    @State private var viewModel: ResetAppDataViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        settingsService: any SettingsServiceProtocol,
        onResetComplete: @escaping @MainActor @Sendable () async -> Void
    ) {
        _viewModel = State(
            initialValue: ResetAppDataViewModel(
                settingsService: settingsService,
                onResetComplete: onResetComplete
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .resetting:
                resettingView
            case .completed:
                completedView
            case .failed:
                failedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle("Reset App Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Everything?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                viewModel.performReset()
            }
        } message: {
            Text("This permanently deletes all local app data, resets settings to defaults, and restores the built-in exercise library. This cannot be undone.")
        }
    }

    private var idleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.danger)

                Text("Reset App Data")
                    .font(.title2.bold())
                    .foregroundStyle(Color.textPrimary)

                Text("Delete all local Reppo data from this device. Onboarding stays completed, your settings return to defaults, and the built-in exercise library is restored automatically.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)

                warningCard(
                    title: "Everything removed",
                    items: [
                        "Workout history and current workout data",
                        "Custom exercises, templates, programs, and planned workouts",
                        "Bodyweight log, stats, and PR records",
                        "Saved chart presets, timer state, and settings"
                    ]
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label("Export a backup first if you may want this data later.", systemImage: "externaldrive.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Reset is permanent. Exporting a backup now gives you something to restore later.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgCard)
                .cornerRadius(16)

                Button {
                    viewModel.confirmReset()
                } label: {
                    Label("Delete Everything", systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.danger)
            }
            .padding()
        }
    }

    private var resettingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.danger)

            Text("Deleting app data...")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            Text("Built-in exercises and default settings will be restored automatically.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)

            Spacer()
        }
    }

    private var completedView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.success)

            Text("App Data Deleted")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text("All local data has been removed. Default settings and the built-in exercise library are ready to use.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    private var failedView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.danger)

            Text("Reset Failed")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text(viewModel.errorMessage ?? "Something went wrong while deleting app data.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                viewModel.retry()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.danger)

            Button("Review Warnings") {
                viewModel.reviewWarningsAgain()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }

    private func warningCard(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "minus.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(16)
    }
}

private struct SettingsRebuildOverlay: View {
    var body: some View {
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
