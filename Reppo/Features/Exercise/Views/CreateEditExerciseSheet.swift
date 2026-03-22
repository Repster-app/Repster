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
            exerciseService: services.exerciseService
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

            HStack {
                Text("Bodyweight Factor")
                Spacer()
                TextField("0.0", value: $viewModel.bodyweightFactor,
                          format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }

            HStack {
                Text("Weight Increment")
                Spacer()
                TextField("kg", value: $viewModel.weightIncrement,
                          format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }

            HStack {
                Text("Default Rest (sec)")
                Spacer()
                TextField("sec", value: $viewModel.defaultRestTime,
                          format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
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
}
