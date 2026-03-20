// PrescriptionSettingsView.swift
// Advanced settings for Smart Suggestions.
// Feature: Smart Suggestions

import SwiftUI

struct SmartSuggestionsAdvancedSettingsView: View {
    let profile: HealthProfile
    private let settingsService: any SettingsServiceProtocol

    init(profile: HealthProfile, settingsService: any SettingsServiceProtocol) {
        self.profile = profile
        self.settingsService = settingsService
    }

    var body: some View {
        Form {
            SmartSuggestionsAdvancedSections(
                profile: profile,
                settingsService: settingsService
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

    @State private var freshnessEnabled: Bool
    @State private var freshnessPercent: Double
    @State private var fatigueEnabled: Bool
    @State private var recencyWeeks: Int
    @State private var defaultTargetReps: Int
    @State private var defaultTargetRIR: Int

    private let settingsService: any SettingsServiceProtocol
    private let firstSectionTitle: String?

    // MARK: - Options

    private static let recencyOptions = [2, 4, 6, 8, 10, 12]

    // MARK: - Init

    init(profile: HealthProfile,
         settingsService: any SettingsServiceProtocol,
         firstSectionTitle: String? = nil) {
        _freshnessEnabled = State(initialValue: profile.prescriptionFreshnessBonus ?? false)
        _freshnessPercent = State(initialValue: (profile.prescriptionFreshnessBonusPercent ?? 0.03) * 100)
        _fatigueEnabled = State(initialValue: profile.prescriptionFatigueModelingEnabled ?? true)
        _recencyWeeks = State(initialValue: profile.prescriptionRecencyWeeks ?? 6)
        _defaultTargetReps = State(initialValue: profile.prescriptionDefaultTargetReps ?? 8)
        _defaultTargetRIR = State(initialValue: profile.prescriptionDefaultTargetRIR ?? 2)
        self.settingsService = settingsService
        self.firstSectionTitle = firstSectionTitle
    }

    // MARK: - Body

    var body: some View {
        Group {
            defaultsSection
            recencySection
            fatigueSection
            freshnessSection
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
            Toggle("Fatigue Modeling", isOn: $fatigueEnabled)
                .foregroundColor(.textPrimary)
                .onChange(of: fatigueEnabled) { _, newValue in
                    Task { try? await settingsService.updatePrescriptionFatigueModelingEnabled(newValue) }
                }
        } footer: {
            Text("When enabled, suggested weights decrease across sets to account for accumulated fatigue. Uses your rest timer duration to model recovery between sets.")
                .foregroundColor(.textTertiary)
        }
    }

    private var freshnessSection: some View {
        Section {
            Toggle("First Set Bonus", isOn: $freshnessEnabled)
                .foregroundColor(.textPrimary)
                .onChange(of: freshnessEnabled) { _, newValue in
                    Task {
                        try? await settingsService.updatePrescriptionFreshnessBonus(
                            enabled: newValue,
                            percent: freshnessPercent / 100.0
                        )
                    }
                }

            if freshnessEnabled {
                HStack {
                    Text("Bonus")
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("\(Int(freshnessPercent))%")
                        .foregroundColor(.textSecondary)
                        .frame(width: 40)
                }

                Slider(value: $freshnessPercent, in: 1...10, step: 1)
                    .tint(.accent)
                    .onChange(of: freshnessPercent) { _, newValue in
                        Task {
                            try? await settingsService.updatePrescriptionFreshnessBonus(
                                enabled: freshnessEnabled,
                                percent: newValue / 100.0
                            )
                        }
                    }
            }
        } footer: {
            Text("Adds a small weight increase on the first set of each exercise to probe your capacity when you're fresh.")
                .foregroundColor(.textTertiary)
        }
    }
}
