// PrescriptionSettingsView.swift
// Advanced settings for the fatigue-aware weight prescription engine.
// Accessed from Settings → Weight Prescription → Advanced.
// Feature: Weight Prescription

import SwiftUI

/// Advanced settings view for tuning the weight prescription algorithm.
///
/// Provides control over:
/// - Freshness bonus (on/off + percentage)
/// - Fatigue modeling (on/off)
/// - Default recovery constant (seconds)
/// - Recency window (weeks)
struct PrescriptionAdvancedSettingsView: View {

    // MARK: - State

    @State private var freshnessEnabled: Bool
    @State private var freshnessPercent: Double
    @State private var fatigueEnabled: Bool
    @State private var recoveryConstant: Double
    @State private var recencyWeeks: Int

    private let settingsService: any SettingsServiceProtocol

    @Environment(\.dismiss) private var dismiss

    // MARK: - Options

    private static let recencyOptions = [2, 4, 6, 8, 10, 12]
    private static let recoveryOptions: [Double] = [60, 90, 120, 150, 180, 210, 240, 300, 360]

    // MARK: - Init

    init(profile: HealthProfile, settingsService: any SettingsServiceProtocol) {
        _freshnessEnabled = State(initialValue: profile.prescriptionFreshnessBonus ?? false)
        _freshnessPercent = State(initialValue: (profile.prescriptionFreshnessBonusPercent ?? 0.03) * 100)
        _fatigueEnabled = State(initialValue: profile.prescriptionFatigueModelingEnabled ?? true)
        _recoveryConstant = State(initialValue: profile.prescriptionDefaultRecoveryConstant ?? 180)
        _recencyWeeks = State(initialValue: profile.prescriptionRecencyWeeks ?? 6)
        self.settingsService = settingsService
    }

    // MARK: - Body

    var body: some View {
        Form {
            // Recency Window
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

            // Fatigue Modeling
            Section {
                Toggle("Fatigue Modeling", isOn: $fatigueEnabled)
                    .foregroundColor(.textPrimary)
                    .onChange(of: fatigueEnabled) { _, newValue in
                        Task { try? await settingsService.updatePrescriptionFatigueModelingEnabled(newValue) }
                    }

                if fatigueEnabled {
                    Picker("Recovery Time", selection: $recoveryConstant) {
                        ForEach(Self.recoveryOptions, id: \.self) { seconds in
                            Text(formatRecovery(seconds)).tag(seconds)
                        }
                    }
                    .foregroundColor(.textPrimary)
                    .onChange(of: recoveryConstant) { _, newValue in
                        Task { try? await settingsService.updatePrescriptionDefaultRecoveryConstant(newValue) }
                    }
                }
            } footer: {
                Text("When enabled, suggested weights decrease across sets to account for accumulated fatigue. Recovery time controls how quickly fatigue dissipates during rest.")
                    .foregroundColor(.textTertiary)
            }

            // Freshness Bonus
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
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Formatters

    private func formatRecovery(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if secs == 0 {
            return "\(mins) min"
        }
        return "\(mins)m \(secs)s"
    }
}
