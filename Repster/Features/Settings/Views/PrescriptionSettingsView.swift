// PrescriptionSettingsView.swift
// Advanced settings for Smart Suggestions.
// Feature: Smart Suggestions

import SwiftUI

struct SmartSuggestionsAdvancedSettingsView: View {
    let profile: HealthProfile
    private let settingsService: any SettingsServiceProtocol
    let fatigueLearningService: FatigueLearningService

    init(profile: HealthProfile, settingsService: any SettingsServiceProtocol, fatigueLearningService: FatigueLearningService) {
        self.profile = profile
        self.settingsService = settingsService
        self.fatigueLearningService = fatigueLearningService
    }

    var body: some View {
        Form {
            SmartSuggestionsAdvancedSections(
                profile: profile,
                settingsService: settingsService,
                fatigueLearningService: fatigueLearningService,
                isAdminModeEnabled: profile.prescriptionAdminModeEnabled ?? false
            )
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Smart Suggestions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Reusable advanced Smart Suggestions sections.
struct SmartSuggestionsAdvancedSections: View {

    // MARK: - State

    @State private var fatigueEnabled: Bool
    @State private var recencyWeeks: Int
    @State private var defaultTargetReps: Int
    @State private var defaultTargetRIR: Int

    private let settingsService: any SettingsServiceProtocol
    private let fatigueLearningService: FatigueLearningService
    private let firstSectionTitle: String?
    private let isAdminModeEnabled: Bool

    // MARK: - Options

    private static let recencyOptions = [2, 4, 6, 8, 10, 12]

    // MARK: - Init

    init(profile: HealthProfile,
         settingsService: any SettingsServiceProtocol,
         fatigueLearningService: FatigueLearningService,
         isAdminModeEnabled: Bool = false,
         firstSectionTitle: String? = nil) {
        _fatigueEnabled = State(initialValue: profile.prescriptionFatigueModelingEnabled ?? true)
        _recencyWeeks = State(initialValue: profile.prescriptionRecencyWeeks ?? 6)
        _defaultTargetReps = State(initialValue: profile.prescriptionDefaultTargetReps ?? 8)
        _defaultTargetRIR = State(initialValue: profile.prescriptionDefaultTargetRIR ?? 2)
        self.settingsService = settingsService
        self.fatigueLearningService = fatigueLearningService
        self.isAdminModeEnabled = isAdminModeEnabled
        self.firstSectionTitle = firstSectionTitle
    }

    // MARK: - Body

    var body: some View {
        Group {
            defaultsSection
            recencySection
            fatigueSection
        }
    }

    @ViewBuilder
    private var defaultsSection: some View {
        if let firstSectionTitle {
            Section {
                defaultsSectionContent
            } header: {
                Text(firstSectionTitle)
            } footer: {
                Text("Used when a set is missing reps guidance, RIR guidance, or both. Smart Suggestions will fill only the missing piece.")
                    .foregroundColor(.textTertiary)
            }
        } else {
            Section {
                defaultsSectionContent
            } footer: {
                Text("Used when a set is missing reps guidance, RIR guidance, or both. Smart Suggestions will fill only the missing piece.")
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var defaultsSectionContent: some View {
        Group {
            Stepper(value: $defaultTargetReps, in: 1...30) {
                HStack {
                    Text("Default Reps")
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("\(defaultTargetReps)")
                        .foregroundColor(.textSecondary)
                }
            }
            .onChange(of: defaultTargetReps) { _, newValue in
                Task { try? await settingsService.updatePrescriptionDefaultTargetReps(newValue) }
            }

            Picker("Default RIR", selection: $defaultTargetRIR) {
                ForEach(0...5, id: \.self) { rir in
                    Text(rir == 5 ? "5+" : "\(rir)").tag(rir)
                }
            }
            .foregroundColor(.textPrimary)
            .pickerStyle(.menu)
            .onChange(of: defaultTargetRIR) { _, newValue in
                Task { try? await settingsService.updatePrescriptionDefaultTargetRIR(newValue) }
            }
        }
    }

    private var recencySection: some View {
        Section {
            Picker("Recency Window", selection: $recencyWeeks) {
                ForEach(Self.recencyOptions, id: \.self) { weeks in
                    Text("\(weeks) weeks").tag(weeks)
                }
            }
            .foregroundColor(.textPrimary)
            .onChange(of: recencyWeeks) { _, newValue in
                Task { try? await settingsService.updatePrescriptionRecencyWeeks(newValue) }
            }
        } footer: {
            Text("How far back to look for performance data. Shorter windows adapt faster to strength changes.")
                .foregroundColor(.textTertiary)
        }
    }

    private var fatigueSection: some View {
        Section {
            Toggle("Fatigue", isOn: $fatigueEnabled)
                .foregroundColor(.textPrimary)
                .onChange(of: fatigueEnabled) { _, newValue in
                    Task { try? await settingsService.updatePrescriptionFatigueModelingEnabled(newValue) }
                }

            if fatigueEnabled && isAdminModeEnabled {
                NavigationLink {
                    FatigueLearningAdminView(fatigueLearningService: fatigueLearningService)
                } label: {
                    Label("Fatigue Learning", systemImage: "brain.head.profile")
                        .foregroundStyle(Color.textPrimary)
                }
            }
        } footer: {
            Text(
                isAdminModeEnabled
                    ? "When enabled, suggested weights decrease across sets to account for accumulated fatigue. Uses your rest timer duration to model recovery between sets."
                    : "When enabled, suggested weights decrease across sets to account for accumulated fatigue. Turn on Admin Mode to access troubleshooting diagnostics."
            )
                .foregroundColor(.textTertiary)
        }
    }
}
