// CreateEditExerciseSheet.swift
// Full form for creating/editing exercises with all fields from specdoc S6.3.
// Spec: FR-008, FR-009, SC-003, User Story 4
// Contract: view-contracts.md CreateEditExerciseSheet
// Feature: 007-exercise-list-and-detail WP05 T022-T024

import SwiftUI

struct CreateEditExerciseSheet: View {

    private enum FocusField: Hashable {
        case name
        case bodyweightFactor
    }

    // MARK: - State

    @State private var viewModel: CreateEditExerciseViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusField?
    var onSave: (() -> Void)?

    // MARK: - Init

    init(
        exercise: ChartExerciseData?,
        services: ServiceContainer,
        onSave: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: CreateEditExerciseViewModel(
            exercise: exercise,
            exerciseService: services.exerciseService,
            settingsService: services.settingsService,
            analyticsService: services.analyticsService
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
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { handleCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveExercise() }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
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
                // Masked while typed; the saved name is content, shown on every screen
                // the exercise appears on.
                .replayMasked()
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
                .onSubmit {
                    focusedField = nil
                }

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
                    Toggle(isOn: primaryMuscleSelection(muscle)) {
                        Label {
                            Text(ExercisePrimaryGroup.displayName(for: muscle))
                        } icon: {
                            Image(uiImage: MuscleGroupColors.dotImage(for: muscle))
                                .renderingMode(.original)
                        }
                    }
                }
            } label: {
                // Fixed Colors, not `.primary` and `.secondary`: a menu label draws in the tint.
                HStack {
                    Text("Primary Muscle")
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if !viewModel.primaryMuscle.isEmpty {
                        Circle()
                            .fill(MuscleGroupColors.color(for: viewModel.primaryMuscle))
                            .frame(width: 8, height: 8)
                    }
                    Text(viewModel.primaryMuscleDisplayName)
                        .foregroundStyle(
                            viewModel.primaryMuscle.isEmpty
                            ? Color.textTertiary
                            : Color.secondary
                        )
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { _ in
                focusedField = nil
            })

            NavigationLink {
                // Cleared here, not with a tap gesture on the link: that swallows quick taps,
                // so the row only opens on a long press.
                SecondaryMusclesScreen(viewModel: viewModel)
                    .onAppear { focusedField = nil }
            } label: {
                HStack {
                    Text("Secondary Muscles")
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer()
                    Text(viewModel.secondaryMusclesSummary)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
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

    /// A Toggle gives the menu's own checkmark and leaves the icon slot free for the dot.
    private func primaryMuscleSelection(_ muscle: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.primaryMuscle == muscle },
            set: { isSelected in
                if isSelected {
                    viewModel.primaryMuscle = muscle
                }
            }
        )
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

            if viewModel.supportsUnilateral && viewModel.unilateral {
                Picker("Rep Target Mode", selection: $viewModel.unilateralRepTargetMode) {
                    ForEach(UnilateralRepTargetMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Text(viewModel.unilateralRepTargetMode.helpText)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            HStack {
                Text("Bodyweight Factor")
                Spacer()
                TextField("0.0", value: $viewModel.bodyweightFactor,
                          format: .number)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .bodyweightFactor)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }

            Picker("Weight Increment", selection: weightIncrementSelection) {
                Text("App Default (\(viewModel.defaultIncrementDisplay))")
                    .tag(Optional<Double>.none)
                ForEach(weightIncrementOptions, id: \.storedKg) { option in
                    Text(formatIncrement(displayValue: option.display))
                        .tag(Optional(option.storedKg))
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

    private var weightIncrementOptions: [(display: Double, storedKg: Double)] {
        UnitConversion.exerciseWeightIncrementOptions(for: viewModel.unitPreference)
    }

    private var restTimeOptions: [Int] {
        [30, 45, 60, 90, 120, 150, 180, 210, 240, 300]
    }

    private func formatIncrement(displayValue value: Double) -> String {
        UnitConversion.formatWeightIncrementLabel(displayValue: value, unitPreference: viewModel.unitPreference)
    }

    private var weightIncrementSelection: Binding<Double?> {
        Binding(
            get: {
                viewModel.weightIncrement.map {
                    UnitConversion.normalizedWeightIncrementOption(
                        storedKg: $0,
                        unitPreference: viewModel.unitPreference,
                        options: weightIncrementOptions
                    ).storedKg
                }
            },
            set: { viewModel.weightIncrement = $0 }
        )
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

    private func handleCancel() {
        focusedField = nil
        dismiss()
    }

    private func saveExercise() {
        focusedField = nil

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
}

// MARK: - Secondary Muscles Screen

/// The full muscle list by area, pushed from the form's Secondary Muscles row. Picks land on
/// the form's view model straight away, so Back keeps them and Cancel still discards them.
private struct SecondaryMusclesScreen: View {
    let viewModel: CreateEditExerciseViewModel

    var body: some View {
        Form {
            ForEach(viewModel.secondaryMuscleAreas, id: \.title) { area in
                Section(area.title) {
                    ForEach(area.muscles, id: \.self) { muscle in
                        muscleRow(muscle)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Secondary Muscles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func muscleRow(_ muscle: String) -> some View {
        let isSelected = viewModel.isSecondaryMuscleSelected(muscle)

        return Button {
            viewModel.toggleSecondaryMuscle(muscle)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(MuscleGroupColors.groupColor(for: muscle))
                    .frame(width: 8, height: 8)
                Text(ExercisePrimaryGroup.displayName(for: muscle))
                    .foregroundStyle(Color.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
