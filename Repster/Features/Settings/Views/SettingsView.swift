// SettingsView.swift
// Main Settings overview screen with 5 sections and navigable detail screens.
// Spec: FR-010, User Stories 1-2, acceptance scenarios
// Feature: 010-settings-and-onboarding WP02 T007/T011/T012

import SwiftUI
import RevenueCat
import RevenueCatUI

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
    @State private var pendingMuscleAssignmentCount: Int = 0
    @Environment(ServiceContainer.self) private var services
    @Binding private var accessSnapshot: AccessSnapshot
    private let settingsService: any SettingsServiceProtocol
    private let bodyweightService: any BodyweightServiceProtocol
    private let importService: any ImportServiceProtocol
    private let workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol
    private let subscriptionService: any SubscriptionServiceProtocol
    private let accessControlService: any AccessControlServiceProtocol
    private let analyticsService: any AnalyticsServiceProtocol
    private let fatigueLearningService: FatigueLearningService

    // MARK: - Init

    init(accessSnapshot: Binding<AccessSnapshot>,
         settingsService: any SettingsServiceProtocol,
         bodyweightService: any BodyweightServiceProtocol,
         importService: any ImportServiceProtocol,
         workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol,
         subscriptionService: any SubscriptionServiceProtocol,
         accessControlService: any AccessControlServiceProtocol,
         analyticsService: any AnalyticsServiceProtocol,
         fatigueLearningService: FatigueLearningService) {
        _viewModel = State(initialValue: SettingsViewModel(settingsService: settingsService))
        _accessSnapshot = accessSnapshot
        self.settingsService = settingsService
        self.bodyweightService = bodyweightService
        self.importService = importService
        self.workoutHistoryBackupService = workoutHistoryBackupService
        self.subscriptionService = subscriptionService
        self.accessControlService = accessControlService
        self.analyticsService = analyticsService
        self.fatigueLearningService = fatigueLearningService
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                workoutSection
                membershipSection
                dataSection
                bodySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Settings")
            .task {
                await viewModel.loadProfile()
                await refreshMembershipStatus(forceSubscriptionRefresh: true)
                await refreshPendingMuscleAssignmentCount()
            }
            .onAppear {
                guard viewModel.profile != nil else { return }
                Task {
                    await viewModel.refreshProfile()
                    await refreshMembershipStatus(forceSubscriptionRefresh: true)
                    await refreshPendingMuscleAssignmentCount()
                }
            }
            .sheet(isPresented: $viewModel.showUnitsSheet) {
                UnitPickerSheet(
                    currentUnit: viewModel.profile?.unitPreference ?? .metric
                ) { unit in
                    let previousUnit = viewModel.profile?.unitPreference
                    Task {
                        await viewModel.updateUnitPreference(unit)
                        if viewModel.profile?.unitPreference == unit {
                            services.updateCachedUnitPreference(unit)
                            if previousUnit != unit {
                                services.analyticsService.unitSystemToggled(unitSystem: unit.rawValue)
                            }
                        }
                    }
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

            NavigationLink {
                ExerciseListView(mode: .manage, services: services)
            } label: {
                SettingsNavigationRow(
                    title: "Exercise Library",
                    systemImage: "figure.strengthtraining.traditional",
                    summary: pendingMuscleAssignmentCount > 0
                        ? "\(pendingMuscleAssignmentCount) unassigned"
                        : nil,
                    summaryColor: pendingMuscleAssignmentCount > 0 ? .accent : .textSecondary,
                    showChevron: false
                )
            }
        }
    }

    private func refreshPendingMuscleAssignmentCount() async {
        guard let exercises = try? await services.exerciseService.fetchAllExercises() else { return }
        pendingMuscleAssignmentCount = exercises.reduce(into: 0) { count, exercise in
            let normalized = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle)
            if normalized == nil || normalized?.isEmpty == true {
                count += 1
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

    // MARK: - MEMBERSHIP Section

    private var membershipSection: some View {
        Section("Membership") {
            NavigationLink {
                MembershipSettingsView(
                    accessSnapshot: $accessSnapshot,
                    subscriptionService: subscriptionService,
                    accessControlService: accessControlService,
                    analyticsService: analyticsService
                )
            } label: {
                SettingsNavigationRow(
                    title: "Membership",
                    systemImage: accessSnapshot.hasFullAccess ? "checkmark.seal" : "lock",
                    summary: membershipSummary,
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

            Link(destination: BrandingConfiguration.privacyPolicyURL) {
                SettingsNavigationRow(
                    title: "Privacy Policy",
                    systemImage: "hand.raised"
                )
            }

            Link(destination: BrandingConfiguration.termsOfUseURL) {
                SettingsNavigationRow(
                    title: "Terms of Use",
                    systemImage: "doc.text"
                )
            }
        }
    }

    private var membershipSummary: String {
        switch accessSnapshot.state {
        case .subscribed:
            return "Unlocked"
        case .free(let remaining):
            return remaining == 1 ? "1 free workout left" : "\(remaining) free workouts left"
        case .paywallRequired:
            return "Unlock required"
        }
    }

    @MainActor
    private func refreshMembershipStatus(forceSubscriptionRefresh: Bool) async {
        if forceSubscriptionRefresh {
            _ = await subscriptionService.refreshSubscriptionStatus()
        } else {
            _ = await subscriptionService.currentSubscriptionSnapshot()
        }
        accessSnapshot = await accessControlService.currentAccessSnapshot()
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

private struct MembershipSettingsView: View {
    @Binding var accessSnapshot: AccessSnapshot
    let subscriptionService: any SubscriptionServiceProtocol
    let accessControlService: any AccessControlServiceProtocol
    let analyticsService: any AnalyticsServiceProtocol

    @State private var subscriptionSnapshot = SubscriptionSnapshot.unknown(
        entitlementIdentifier: RevenueCatConfiguration.entitlementIdentifier
    )
    @State private var showPaywall = false
    @State private var showLifetimeConfirmation = false
    @State private var showMembershipAlert = false
    @State private var membershipAlertTitle = ""
    @State private var membershipAlertMessage = ""
    @State private var showManageSubscriptionAction = false
    @State private var isPurchasingLifetime = false
    @State private var isRestoringPurchases = false

    var body: some View {
        Form {
            Section {
                SettingsNavigationRow(
                    title: "Access",
                    systemImage: accessSnapshot.hasFullAccess ? "checkmark.seal" : "lock",
                    summary: membershipSummary,
                    showChevron: false
                )

                if shouldShowLifetimePurchase {
                    Button {
                        showLifetimeConfirmation = true
                    } label: {
                        SettingsNavigationRow(
                            title: "Buy Lifetime",
                            systemImage: "infinity.circle"
                        )
                    }
                    .disabled(isWorking)
                }

                if !accessSnapshot.hasFullAccess {
                    Button {
                        showPaywall = true
                    } label: {
                        SettingsNavigationRow(
                            title: "Unlock Repster",
                            systemImage: "sparkles"
                        )
                    }
                }

                Button {
                    Task { await restorePurchases() }
                } label: {
                    SettingsNavigationRow(
                        title: "Restore Purchases",
                        systemImage: "arrow.clockwise.circle"
                    )
                }
                .disabled(isWorking)

                Button {
                    Task { await subscriptionService.openManageSubscriptions() }
                } label: {
                    SettingsNavigationRow(
                        title: "Manage Subscription",
                        systemImage: "creditcard"
                    )
                }
            }

            if shouldShowSubscriptionCancellationReminder {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Lifetime access is active", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Text("Your subscription can still renew until you cancel it in Apple subscriptions.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Membership")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshMembershipStatus(forceSubscriptionRefresh: true)
        }
        .task {
            await observeCustomerInfoUpdates()
        }
        .alert(membershipAlertTitle, isPresented: $showMembershipAlert) {
            if showManageSubscriptionAction {
                Button("Manage Subscription") {
                    Task { await subscriptionService.openManageSubscriptions() }
                }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: {
            Text(membershipAlertMessage)
        }
        .confirmationDialog(
            "Buy Lifetime",
            isPresented: $showLifetimeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Buy Lifetime") {
                Task { await purchaseLifetime() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Lifetime access unlocks Repster permanently. Your subscription will keep renewing until you cancel it in Apple subscriptions.")
        }
        .sheet(isPresented: $showPaywall, onDismiss: {
            analyticsService.paywallDismissed(source: .paywall)
            Task { await refreshMembershipStatus(forceSubscriptionRefresh: true) }
        }) {
            PaywallView()
                .onPurchaseStarted { _ in
                    analyticsService.purchaseStarted(source: .paywall)
                }
                .onPurchaseCompleted { _ in
                    analyticsService.purchaseCompleted(source: .paywall)
                }
                .onPurchaseCancelled {
                    analyticsService.purchaseCancelled(source: .paywall)
                }
                .onRestoreStarted {
                    analyticsService.restorePurchasesTapped(source: .paywall)
                }
                .onAppear {
                    analyticsService.paywallShown(source: .paywall)
                }
        }
    }

    private var isWorking: Bool {
        isPurchasingLifetime || isRestoringPurchases
    }

    private var shouldShowLifetimePurchase: Bool {
        subscriptionSnapshot.accessSource == .subscription
    }

    private var shouldShowSubscriptionCancellationReminder: Bool {
        subscriptionSnapshot.requiresSubscriptionCancellationReminder
    }

    private var membershipSummary: String {
        switch accessSnapshot.state {
        case .subscribed:
            switch subscriptionSnapshot.accessSource {
            case .subscription:
                return "Subscription active"
            case .lifetime:
                return "Lifetime active"
            case .subscriptionAndLifetime:
                return "Lifetime active"
            case .none:
                return "Unlocked"
            }
        case .free(let remaining):
            return remaining == 1 ? "1 free workout left" : "\(remaining) free workouts left"
        case .paywallRequired:
            return "Unlock required"
        }
    }

    @MainActor
    private func refreshMembershipStatus(forceSubscriptionRefresh: Bool) async {
        let subscription: SubscriptionSnapshot
        if forceSubscriptionRefresh {
            subscription = await subscriptionService.refreshSubscriptionStatus()
        } else {
            subscription = await subscriptionService.currentSubscriptionSnapshot()
        }
        subscriptionSnapshot = subscription
        accessSnapshot = await accessControlService.currentAccessSnapshot()
    }

    @MainActor
    private func restorePurchases() async {
        guard !isRestoringPurchases else { return }
        analyticsService.restorePurchasesTapped(source: .settings)
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        showManageSubscriptionAction = false

        do {
            let subscriptionSnapshot = try await subscriptionService.restorePurchases()
            self.subscriptionSnapshot = subscriptionSnapshot
            accessSnapshot = await accessControlService.currentAccessSnapshot()

            if subscriptionSnapshot.hasFullAccess {
                membershipAlertTitle = "Purchases Restored"
                membershipAlertMessage = "Repster is now unlocked on this device."
            } else {
                membershipAlertTitle = "No Purchases Found"
                membershipAlertMessage = "No active Repster purchase was found for this Apple ID."
            }
        } catch {
            membershipAlertTitle = "Restore Failed"
            membershipAlertMessage = error.localizedDescription
        }

        showMembershipAlert = true
    }

    @MainActor
    private func purchaseLifetime() async {
        guard !isPurchasingLifetime else { return }
        analyticsService.purchaseStarted(source: .membershipSettings)
        isPurchasingLifetime = true
        defer { isPurchasingLifetime = false }
        showManageSubscriptionAction = false

        do {
            let subscriptionSnapshot = try await subscriptionService.purchaseLifetime()
            self.subscriptionSnapshot = subscriptionSnapshot
            accessSnapshot = await accessControlService.currentAccessSnapshot()
            analyticsService.purchaseCompleted(source: .membershipSettings)
            showManageSubscriptionAction = true
            membershipAlertTitle = "Lifetime Access Active"
            membershipAlertMessage = "Repster now has lifetime access. Your subscription may still renew until you cancel it in Apple subscriptions."
            showMembershipAlert = true
        } catch MonetizationError.purchaseCancelled {
            analyticsService.purchaseCancelled(source: .membershipSettings)
            await refreshMembershipStatus(forceSubscriptionRefresh: true)
        } catch {
            showManageSubscriptionAction = false
            membershipAlertTitle = "Lifetime Purchase Failed"
            membershipAlertMessage = error.localizedDescription
            showMembershipAlert = true
        }
    }

    @MainActor
    private func observeCustomerInfoUpdates() async {
        for await _ in Purchases.shared.customerInfoStream {
            await refreshMembershipStatus(forceSubscriptionRefresh: false)
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

    private var unitPreference: UnitPreference {
        viewModel.profile?.unitPreference ?? .metric
    }

    private var incrementOptions: [(display: Double, storedKg: Double)] {
        UnitConversion.displayWeightIncrementOptions(for: unitPreference)
    }

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
                            get: {
                                let stored = viewModel.profile?.prescriptionDefaultIncrement
                                    ?? UnitConversion.defaultStoredWeightIncrement(for: unitPreference)
                                return UnitConversion.normalizedWeightIncrementOption(
                                    storedKg: stored,
                                    unitPreference: unitPreference,
                                    options: incrementOptions
                                ).storedKg
                            },
                            set: { newValue in
                                Task { await viewModel.updatePrescriptionDefaultIncrement(newValue) }
                            }
                        )) {
                            ForEach(incrementOptions, id: \.storedKg) { option in
                                Text(incrementLabel(forDisplayValue: option.display)).tag(option.storedKg)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    Toggle(isOn: Binding(
                        get: { viewModel.smartSuggestionsAdminModeEnabled },
                        set: { newValue in
                            Task { await viewModel.updatePrescriptionAdminModeEnabled(newValue) }
                        }
                    )) {
                        Label("Admin Mode", systemImage: "wrench.and.screwdriver")
                            .foregroundStyle(Color.textPrimary)
                    }
                }

            } footer: {
                Text(
                    viewModel.smartSuggestionsEnabled
                        ? "Default increment controls how suggested weights are rounded before they appear in your workout. Admin Mode exposes Smart Suggestions diagnostics and troubleshooting screens."
                        : "Enable Smart Suggestions to show recommendations during workouts."
                )
                    .foregroundStyle(Color.textTertiary)
            }

            if let profile = viewModel.profile, viewModel.smartSuggestionsEnabled {
                SmartSuggestionsAdvancedSections(
                    profile: profile,
                    settingsService: settingsService,
                    fatigueLearningService: fatigueLearningService,
                    isAdminModeEnabled: viewModel.smartSuggestionsAdminModeEnabled
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

    private func incrementLabel(forDisplayValue value: Double) -> String {
        UnitConversion.formatWeightIncrementLabel(displayValue: value, unitPreference: unitPreference)
    }
}

private struct DataBackupsView: View {
    let importService: any ImportServiceProtocol
    let workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let onDataReset: @MainActor @Sendable () async -> Void
    @State private var shareAnonymousAnalytics = true
    @Environment(ServiceContainer.self) private var services

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ImportView(
                        importService: importService,
                        defaultUnitPreference: services.unitPreference,
                        analyticsService: services.analyticsService,
                        exerciseService: services.exerciseService
                    )
                } label: {
                    SettingsNavigationRow(
                        title: SettingsDataDestination.importCSV.title,
                        systemImage: SettingsDataDestination.importCSV.systemImage,
                        showChevron: false
                    )
                }

                NavigationLink {
                    ExportView(
                        workoutHistoryBackupService: workoutHistoryBackupService,
                        analyticsService: services.analyticsService
                    )
                } label: {
                    SettingsNavigationRow(
                        title: SettingsDataDestination.exportBackup.title,
                        systemImage: SettingsDataDestination.exportBackup.systemImage,
                        showChevron: false
                    )
                }

                NavigationLink {
                    RestoreBackupView(
                        workoutHistoryBackupService: workoutHistoryBackupService,
                        analyticsService: services.analyticsService
                    )
                } label: {
                    SettingsNavigationRow(
                        title: SettingsDataDestination.restoreBackup.title,
                        systemImage: SettingsDataDestination.restoreBackup.systemImage,
                        showChevron: false
                    )
                }
            } footer: {
                Text("Import training data from a CSV file, create a Repster backup archive, or restore workout history. Restoring replaces workout history only. Templates, programs, bodyweight logs, and settings stay untouched.")
                    .foregroundStyle(Color.textTertiary)
            }

            anonymousAnalyticsSection

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
        .task {
            shareAnonymousAnalytics = services.analyticsService.isCollectionEnabled
        }
    }

    private var anonymousAnalyticsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { shareAnonymousAnalytics },
                set: { enabled in
                    shareAnonymousAnalytics = enabled
                    // When disabling, the event must fire before the opt-out
                    // takes effect or it is dropped.
                    if !enabled {
                        services.analyticsService.analyticsOptOutToggled(enabled: enabled)
                        services.analyticsService.setCollectionEnabled(enabled)
                    } else {
                        services.analyticsService.setCollectionEnabled(enabled)
                        services.analyticsService.analyticsOptOutToggled(enabled: enabled)
                    }
                }
            )) {
                Label("Share Anonymous Analytics", systemImage: "chart.bar")
                    .foregroundStyle(Color.textPrimary)
            }
        } footer: {
            Text("Shares anonymous product usage only. Workout notes, exercise names, set weights, reps, CSV contents, and bodyweight values are never sent.")
                .foregroundStyle(Color.textTertiary)
        }
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

                Text("Delete all local Repster data from this device. Onboarding stays completed, your settings return to defaults, and the built-in exercise library is restored automatically.")
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
