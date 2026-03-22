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

    @Environment(\.dismiss) private var dismiss

    @State private var restTimeSeconds: Int?
    @State private var weightIncrement: Double?
    @State private var appDefaultRestTime: Int?
    @State private var appDefaultIncrement: Double?
    @State private var isSaving: Bool = false
    @State private var showFullSettings: Bool = false

    // MARK: - Available Increments

    private static let weightIncrements: [Double] = [0.5, 1.0, 1.25, 2.0, 2.5, 5.0, 10.0]
    private static let restTimeOptions: [Int] = [30, 45, 60, 90, 120, 150, 180, 210, 240, 300]

    // MARK: - Init

    init(exercise: Exercise, services: ServiceContainer) {
        self.exercise = exercise
        self.services = services
        _restTimeSeconds = State(initialValue: exercise.defaultRestTime)
        _weightIncrement = State(initialValue: exercise.weightIncrement)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Rest Time") {
                    Picker("Default Rest Time", selection: $restTimeSeconds) {
                        Text("App Default (\(formatRestTime(appDefaultRestTime)))")
                            .tag(Optional<Int>.none)
                        ForEach(Self.restTimeOptions, id: \.self) { seconds in
                            Text(formatRestTime(seconds)).tag(Optional(seconds))
                        }
                    }
                    .foregroundColor(.textPrimary)
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
        .sheet(isPresented: $showFullSettings) {
            CreateEditExerciseSheet(
                exercise: exercise,
                services: services
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

        dismiss()
    }

    private func loadDefaults() async {
        guard let profile = try? await services.settingsService.fetchSettings() else { return }
        appDefaultRestTime = profile.defaultRestTimeSeconds
        appDefaultIncrement = profile.prescriptionDefaultIncrement
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
