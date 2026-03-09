// ExerciseSettingsSheet.swift
// Per-exercise settings sheet for configuring rest time, weight increment,
// and fatigue parameters. Accessible from Active Workout and Exercise Detail.
// Feature: Weight Prescription — exercise-specific overrides

import SwiftUI

/// Sheet for editing per-exercise settings that affect weight prescription and rest timer.
///
/// Settings:
/// - Default rest time (seconds) — overrides global default
/// - Weight increment (kg) — for rounding prescribed weights
///
/// All settings are persisted directly on the Exercise model via the ExerciseService.
struct ExerciseSettingsSheet: View {

    // MARK: - State

    let exercise: Exercise
    let exerciseService: any ExerciseServiceProtocol

    @Environment(\.dismiss) private var dismiss

    @State private var restTimeSeconds: Int
    @State private var weightIncrement: Double
    @State private var isSaving: Bool = false

    // MARK: - Available Increments

    private static let weightIncrements: [Double] = [0.5, 1.0, 1.25, 2.0, 2.5, 5.0, 10.0]
    private static let restTimeOptions: [Int] = [0, 30, 45, 60, 90, 120, 150, 180, 210, 240, 300]

    // MARK: - Init

    init(exercise: Exercise, exerciseService: any ExerciseServiceProtocol) {
        self.exercise = exercise
        self.exerciseService = exerciseService
        _restTimeSeconds = State(initialValue: exercise.defaultRestTime ?? 0)
        _weightIncrement = State(initialValue: exercise.weightIncrement ?? 2.5)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Exercise name header
                Section {
                    HStack {
                        Image(systemName: "dumbbell")
                            .foregroundColor(.accent)
                        Text(exercise.name)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                    }
                }

                // Rest Time
                Section("Rest Timer") {
                    Picker("Default Rest Time", selection: $restTimeSeconds) {
                        Text("Not Set").tag(0)
                        ForEach(Self.restTimeOptions.filter { $0 > 0 }, id: \.self) { seconds in
                            Text(formatRestTime(seconds)).tag(seconds)
                        }
                    }
                    .foregroundColor(.textPrimary)

                    Text("Automatically starts a rest timer when you complete a set")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }

                // Weight Increment
                Section("Weight Increment") {
                    Picker("Increment", selection: $weightIncrement) {
                        ForEach(Self.weightIncrements, id: \.self) { increment in
                            Text(formatIncrement(increment)).tag(increment)
                        }
                    }
                    .foregroundColor(.textPrimary)

                    Text("Used for rounding smart weight suggestions and manual adjustments")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
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
        }
        .presentationDetents([.medium])
    }

    // MARK: - Save

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }

        // Update exercise model directly
        exercise.defaultRestTime = restTimeSeconds > 0 ? restTimeSeconds : nil
        exercise.weightIncrement = weightIncrement
        exercise.updatedAt = Date()

        do {
            try await exerciseService.updateExercise(exercise, originalTrackingType: exercise.trackingType)
        } catch {
            print("[ExerciseSettingsSheet] Failed to save: \(error)")
        }

        dismiss()
    }

    // MARK: - Formatters

    private func formatRestTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if secs == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(secs)s"
    }

    private func formatIncrement(_ value: Double) -> String {
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
