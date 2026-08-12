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

    /// Snapshot, not a live model — this sheet is presented from the active workout while
    /// the set table is rendering the same exercise (crash B's exact path).
    @State private var exercise: ChartExerciseData
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

    static func weightIncrementOptions(for unitPreference: UnitPreference) -> [(display: Double, storedKg: Double)] {
        UnitConversion.exerciseWeightIncrementOptions(for: unitPreference)
    }

    private var weightIncrements: [(display: Double, storedKg: Double)] {
        Self.weightIncrementOptions(for: services.unitPreference)
    }

    // MARK: - Init

    init(
        exercise: ChartExerciseData,
        services: ServiceContainer,
        onSave: (() -> Void)? = nil
    ) {
        _exercise = State(initialValue: exercise)
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
                    Picker("Increment", selection: weightIncrementSelection) {
                        Text("App Default (\(formatAppDefaultIncrement(appDefaultIncrement)))")
                            .tag(Optional<Double>.none)
                        ForEach(weightIncrements, id: \.storedKg) { option in
                            Text(formatIncrement(displayValue: option.display)).tag(Optional(option.storedKg))
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

        // Send values; the mutation happens inside the repository actor. Seeding from the
        // snapshot keeps every field this sheet doesn't edit exactly as it was.
        var fields = ExerciseEditableFields(from: exercise)
        fields.defaultRestTime = restTimeSeconds
        fields.weightIncrement = weightIncrement

        do {
            try await services.exerciseService.updateExercise(id: exercise.id, fields: fields)
            if let refreshed = try await services.exerciseService.fetchExerciseSnapshot(exercise.id) {
                exercise = refreshed
            }
        } catch {
            dbg("[ExerciseSettingsSheet] Failed to save: \(error)")
        }

        onSave?()
        dismiss()
    }

    /// Re-read after the nested full-settings sheet saved.
    ///
    /// This used to read straight off the live `Exercise`, which reflected the nested
    /// sheet's write for free. A snapshot is frozen, so the refresh has to be explicit —
    /// without it the rest-time and increment rows would silently show pre-edit values.
    private func handleNestedExerciseSave() {
        Task {
            if let refreshed = try? await services.exerciseService.fetchExerciseSnapshot(exercise.id) {
                exercise = refreshed
                restTimeSeconds = refreshed.defaultRestTime
                weightIncrement = refreshed.weightIncrement
            }
            onSave?()
        }
    }

    private func loadDefaults() async {
        guard let profile = try? await services.settingsService.fetchSettings() else { return }
        appDefaultRestTime = profile.defaultRestTimeSeconds
        appDefaultIncrement = profile.prescriptionDefaultIncrement
            ?? UnitConversion.defaultStoredWeightIncrement(for: profile.unitPreference)
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

    private func formatAppDefaultIncrement(_ value: Double?) -> String {
        UnitConversion.formatWeightIncrementLabel(
            storedKg: value,
            unitPreference: services.unitPreference,
            options: UnitConversion.displayWeightIncrementOptions(for: services.unitPreference)
        )
    }

    private func formatIncrement(displayValue value: Double) -> String {
        UnitConversion.formatWeightIncrementLabel(displayValue: value, unitPreference: services.unitPreference)
    }

    private var weightIncrementSelection: Binding<Double?> {
        Binding(
            get: {
                weightIncrement.map {
                    UnitConversion.normalizedWeightIncrementOption(
                        storedKg: $0,
                        unitPreference: services.unitPreference,
                        options: weightIncrements
                    ).storedKg
                }
            },
            set: { weightIncrement = $0 }
        )
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
