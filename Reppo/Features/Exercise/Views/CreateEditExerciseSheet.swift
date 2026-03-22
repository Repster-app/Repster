// CreateEditExerciseSheet.swift
// Full form for creating/editing exercises with all fields from specdoc S6.3.
// Spec: FR-008, FR-009, SC-003, User Story 4
// Contract: view-contracts.md CreateEditExerciseSheet
// Feature: 007-exercise-list-and-detail WP05 T022-T024

import SwiftUI

struct CreateEditExerciseSheet: View {

    // MARK: - State

    @State private var viewModel: CreateEditExerciseViewModel
    @Environment(\.dismiss) private var dismiss
    var onSave: (() -> Void)?

    // MARK: - Init

    init(
        exercise: Exercise?,
        services: ServiceContainer,
        onSave: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: CreateEditExerciseViewModel(
            exercise: exercise,
            exerciseService: services.exerciseService,
            settingsService: services.settingsService
        ))
        self.onSave = onSave
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                musclesSection
                advancedSection

                if viewModel.isTrackingTypeLocked {
                    trackingTypeLockNotice
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await viewModel.save()
                                onSave?()
                                dismiss()
                            } catch {
                                viewModel.errorMessage = error.localizedDescription
                                viewModel.showError = true
                            }
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .task {
                await viewModel.checkTrackingTypeLock()
                await viewModel.loadDefaults()
            }
        }
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        Section("Basic Info") {
            TextField("Exercise Name", text: $viewModel.name)

            Picker("Equipment", selection: $viewModel.equipmentType) {
                ForEach(EquipmentType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }

            Picker("Tracking Type", selection: $viewModel.trackingType) {
                ForEach(TrackingType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .disabled(viewModel.isTrackingTypeLocked)
        }
    }

    // MARK: - Muscles Section

    private var musclesSection: some View {
        Section("Muscles") {
            Menu {
                ForEach(viewModel.primaryMuscleOptions, id: \.self) { muscle in
                    Button {
                        viewModel.primaryMuscle = muscle
                    } label: {
                        if viewModel.primaryMuscle == muscle {
                            Label(ExercisePrimaryGroup.displayName(for: muscle), systemImage: "checkmark")
                        } else {
                            Text(ExercisePrimaryGroup.displayName(for: muscle))
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Primary Muscle")
                    Spacer()
                    Text(viewModel.primaryMuscleDisplayName)
                        .foregroundStyle(
                            viewModel.primaryMuscle.isEmpty
                            ? Color.textTertiary
                            : Color.textSecondary
                        )
                }
            }

            Picker("Movement Pattern", selection: $viewModel.movementPattern) {
                Text("None").tag(Optional<MovementPattern>.none)
                ForEach(MovementPattern.allCases, id: \.self) { pattern in
                    Text(pattern.displayName).tag(Optional(pattern))
                }
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Unilateral", isOn: $viewModel.unilateral)
                .disabled(!viewModel.supportsUnilateral)

            if !viewModel.supportsUnilateral {
                Text("Unilateral logging is only available for rep-based tracking types.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            HStack {
                Text("Bodyweight Factor")
                Spacer()
                TextField("0.0", value: $viewModel.bodyweightFactor,
                          format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }

            Picker("Weight Increment", selection: $viewModel.weightIncrement) {
                Text("App Default (\(viewModel.defaultIncrementDisplay))")
                    .tag(Optional<Double>.none)
                ForEach(weightIncrementOptions, id: \.self) { increment in
                    Text(formatIncrement(increment))
                        .tag(Optional(increment))
                }
            }

            Picker("Default Rest", selection: $viewModel.defaultRestTime) {
                Text("App Default (\(viewModel.defaultRestTimeDisplay))")
                    .tag(Optional<Int>.none)
                ForEach(restTimeOptions, id: \.self) { seconds in
                    Text(formatRestTime(seconds))
                        .tag(Optional(seconds))
                }
            }
        }
    }

    // MARK: - TrackingType Lock Notice

    private var trackingTypeLockNotice: some View {
        Section {
            Label(
                "Tracking type cannot be changed because this exercise has logged data.",
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(Color.textTertiary)
        }
    }

    private var weightIncrementOptions: [Double] {
        [0.5, 1.0, 1.25, 2.0, 2.5, 5.0, 10.0]
    }

    private var restTimeOptions: [Int] {
        [30, 45, 60, 90, 120, 150, 180, 210, 240, 300]
    }

    private func formatIncrement(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f kg", value)
        }
        return String(format: "%.2f kg", value)
    }

    private func formatRestTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes > 0, remainder > 0 {
            return "\(minutes)m \(remainder)s"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(seconds) sec"
    }
}
