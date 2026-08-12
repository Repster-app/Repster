// CreateEditExerciseViewModel.swift
// Form state, validation, and save logic for creating/editing exercises.
// Spec: FR-008, FR-009, SC-003, User Story 4
// Contract: view-contracts.md CreateEditExerciseViewModel
// Feature: 007-exercise-list-and-detail WP05 T021

import Foundation

@Observable @MainActor
final class CreateEditExerciseViewModel {

    // MARK: - Dependencies

    private let exerciseService: any ExerciseServiceProtocol
    private let settingsService: any SettingsServiceProtocol
    private let analyticsService: any AnalyticsServiceProtocol
    /// Snapshot, never a live model: mutating the very `Exercise` the active-workout
    /// set table renders, then saving it on the repository actor, was crash B.
    private let existingExercise: ChartExerciseData?

    // MARK: - Form Fields

    var name: String = ""
    var equipmentType: EquipmentType = .barbell
    var trackingType: TrackingType = .weightReps
    var primaryMuscle: String = ""
    /// Hidden from the current form, but preserved for existing exercises.
    var secondaryMuscles: [String] = []
    var movementPattern: MovementPattern? = nil
    var unilateral: Bool = false
    var unilateralRepTargetMode: UnilateralRepTargetMode = .perSide
    var bilateralLoadFactor: Double? = nil
    var bodyweightFactor: Double = 0.0
    var weightIncrement: Double? = nil
    var defaultRestTime: Int? = nil

    // MARK: - UI State

    let isEditing: Bool
    var isTrackingTypeLocked: Bool = false
    var isSaving: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var appDefaultRestTime: Int? = nil
    var appDefaultWeightIncrement: Double? = nil
    var unitPreference: UnitPreference = .metric

    // MARK: - Computed

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var navigationTitle: String {
        isEditing ? "Edit Exercise" : "New Exercise"
    }

    var primaryMuscleOptions: [String] {
        ExercisePrimaryGroup.options(including: primaryMuscle)
    }

    var primaryMuscleDisplayName: String {
        guard let primaryMuscle = ExercisePrimaryGroup.normalizedValue(primaryMuscle) else {
            return "Select Group"
        }

        return ExercisePrimaryGroup.displayName(for: primaryMuscle)
    }

    var supportsUnilateral: Bool {
        trackingType == .weightReps || trackingType == .weightRepsDuration
    }

    var defaultRestTimeDisplay: String {
        formatSeconds(appDefaultRestTime)
    }

    var defaultIncrementDisplay: String {
        UnitConversion.formatWeightIncrementLabel(
            storedKg: appDefaultWeightIncrement,
            unitPreference: unitPreference,
            options: UnitConversion.displayWeightIncrementOptions(for: unitPreference)
        )
    }

    // MARK: - Init

    init(
        exercise: ChartExerciseData?,
        exerciseService: any ExerciseServiceProtocol,
        settingsService: any SettingsServiceProtocol,
        analyticsService: any AnalyticsServiceProtocol = NoopAnalyticsService()
    ) {
        self.exerciseService = exerciseService
        self.settingsService = settingsService
        self.analyticsService = analyticsService
        self.existingExercise = exercise
        self.isEditing = exercise != nil

        if let exercise {
            name = exercise.name
            equipmentType = exercise.equipmentType
            trackingType = exercise.trackingType
            primaryMuscle = ExercisePrimaryGroup.normalizedValue(exercise.primaryMuscle) ?? ""
            secondaryMuscles = exercise.secondaryMuscles
            movementPattern = exercise.movementPattern
            unilateral = exercise.unilateral
            unilateralRepTargetMode = exercise.unilateralRepTargetMode
            bilateralLoadFactor = exercise.bilateralLoadFactor
            bodyweightFactor = exercise.bodyweightFactor
            weightIncrement = exercise.weightIncrement
            defaultRestTime = exercise.defaultRestTime
        }
    }

    // MARK: - TrackingType Lock (FR-009)

    func checkTrackingTypeLock() async {
        guard let exercise = existingExercise else { return }
        isTrackingTypeLocked = (try? await exerciseService.exerciseHasLoggedSetData(exercise.id)) ?? false
    }

    func loadDefaults() async {
        guard let profile = try? await settingsService.fetchSettings() else { return }
        unitPreference = profile.unitPreference
        appDefaultRestTime = profile.defaultRestTimeSeconds
        appDefaultWeightIncrement = profile.prescriptionDefaultIncrement
            ?? UnitConversion.defaultStoredWeightIncrement(for: profile.unitPreference)
    }

    // MARK: - Save

    func save() async throws {
        guard isValid else { return }

        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let muscle = ExercisePrimaryGroup.normalizedValue(primaryMuscle)
        let resolvedUnilateral = supportsUnilateral ? self.unilateral : false
        let resolvedUnilateralRepTargetMode: UnilateralRepTargetMode = resolvedUnilateral
            ? unilateralRepTargetMode
            : .perSide

        // Seed from the existing snapshot so fields this form doesn't expose survive the
        // edit, then overwrite exactly what the form owns. Preserves the previous
        // behaviour of mutating the live model field by field.
        var fields = existingExercise.map(ExerciseEditableFields.init(from:))
            ?? ExerciseEditableFields(name: trimmedName, equipmentType: equipmentType, trackingType: trackingType)
        fields.name = trimmedName
        fields.equipmentType = equipmentType
        if !isTrackingTypeLocked {
            fields.trackingType = trackingType
        }
        fields.primaryMuscle = muscle
        fields.secondaryMuscles = secondaryMuscles
        fields.movementPattern = movementPattern
        fields.unilateral = resolvedUnilateral
        fields.unilateralRepTargetMode = resolvedUnilateralRepTargetMode
        fields.bilateralLoadFactor = bilateralLoadFactor
        fields.bodyweightFactor = bodyweightFactor
        fields.weightIncrement = weightIncrement
        fields.defaultRestTime = defaultRestTime

        if isEditing, let existing = existingExercise {
            try await exerciseService.updateExercise(id: existing.id, fields: fields)
        } else {
            try await exerciseService.createExercise(fields: fields)
            // Creating a custom exercise is one of the strongest activation
            // signals available: it means the seeded library didn't cover what
            // the user trains, and they cared enough to fix that.
            analyticsService.exerciseCreated(source: "create_exercise_form")
        }
    }

    private func formatSeconds(_ seconds: Int?) -> String {
        guard let seconds else { return "Not Set" }
        if seconds == 0 {
            return "0 sec"
        }
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
