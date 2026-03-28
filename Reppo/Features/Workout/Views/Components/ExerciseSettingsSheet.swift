// ExerciseSettingsSheet.swift
// Per-exercise settings sheet for configuring rest time, weight increment,
// and fatigue parameters. Accessible from Active Workout and Exercise Detail.
// Feature: Smart Suggestions — exercise-specific overrides

import SwiftUI

/// Sheet for editing per-exercise settings that affect Smart Suggestions and the rest timer.
///
/// Settings:
/// - Default rest time (seconds) — overrides global default
/// - Weight increment (kg) — for rounding prescribed weights
///
/// All settings are persisted directly on the Exercise model via the ExerciseService.
struct ExerciseSettingsSheet: View {

    // MARK: - State

    let exercise: Exercise
    let services: ServiceContainer
    let onSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var restTimeSeconds: Int?
    @State private var weightIncrement: Double?
    @State private var appDefaultRestTime: Int?
    @State private var appDefaultIncrement: Double?
    @State private var isSaving: Bool = false
    @State private var showRestTimeSheet: Bool = false
    @State private var showFullSettings: Bool = false

    // MARK: - Available Increments

    private static let weightIncrements: [Double] = [0.5, 1.0, 1.25, 2.0, 2.5, 5.0, 10.0]

    // MARK: - Init

    init(
        exercise: Exercise,
        services: ServiceContainer,
        onSave: (() -> Void)? = nil
    ) {
        self.exercise = exercise
        self.services = services
        self.onSave = onSave
        _restTimeSeconds = State(initialValue: exercise.defaultRestTime)
        _weightIncrement = State(initialValue: exercise.weightIncrement)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Rest Time") {
                    Button {
                        showRestTimeSheet = true
                    } label: {
                        ExerciseQuickSettingRow(
                            title: "Default Rest Time",
                            summary: restTimeSummary
                        )
                    }
                }

                Section("Weight Increment") {
                    Picker("Increment", selection: $weightIncrement) {
                        Text("App Default (\(formatIncrement(appDefaultIncrement)))")
                            .tag(Optional<Double>.none)
                        ForEach(Self.weightIncrements, id: \.self) { increment in
                            Text(formatIncrement(increment)).tag(Optional(increment))
                        }
                    }
                    .foregroundColor(.textPrimary)
                }

                Section("More") {
                    Button("More Exercise Settings") {
                        showFullSettings = true
                    }
                    .foregroundColor(.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Exercise Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveSettings()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .task {
                await loadDefaults()
            }
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $showRestTimeSheet) {
            RestTimePickerSheet(
                currentSeconds: restTimeSeconds,
                title: "Default Rest Time",
                noneOptionLabel: "App Default (\(formatRestTime(appDefaultRestTime)))"
            ) { seconds in
                restTimeSeconds = seconds
            }
        }
        .sheet(isPresented: $showFullSettings) {
            CreateEditExerciseSheet(
                exercise: exercise,
                services: services,
                onSave: handleNestedExerciseSave
            )
        }
    }

    // MARK: - Save

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }

        // Update exercise model directly
        exercise.defaultRestTime = restTimeSeconds
        exercise.weightIncrement = weightIncrement
        exercise.updatedAt = Date()

        do {
            try await services.exerciseService.updateExercise(exercise, originalTrackingType: exercise.trackingType)
        } catch {
            print("[ExerciseSettingsSheet] Failed to save: \(error)")
        }

        onSave?()
        dismiss()
    }

    private func handleNestedExerciseSave() {
        restTimeSeconds = exercise.defaultRestTime
        weightIncrement = exercise.weightIncrement
        onSave?()
    }

    private func loadDefaults() async {
        guard let profile = try? await services.settingsService.fetchSettings() else { return }
        appDefaultRestTime = profile.defaultRestTimeSeconds
        appDefaultIncrement = profile.prescriptionDefaultIncrement
    }

    private var restTimeSummary: String {
        if let restTimeSeconds {
            return formatRestTime(restTimeSeconds)
        }
        return "App Default (\(formatRestTime(appDefaultRestTime)))"
    }

    // MARK: - Formatters

    private func formatRestTime(_ seconds: Int?) -> String {
        guard let seconds else { return "Not Set" }
        let minutes = seconds / 60
        let secs = seconds % 60
        if secs == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(secs)s"
    }

    private func formatIncrement(_ value: Double?) -> String {
        guard let value else { return "Not Set" }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f kg", value)
        }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(formatted) kg"
    }
}

private struct ExerciseQuickSettingRow: View {
    let title: String
    let summary: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 12)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
