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
    private let existingExercise: Exercise?

    // MARK: - Form Fields

    var name: String = ""
    var equipmentType: EquipmentType = .barbell
    var trackingType: TrackingType = .weightReps
    var primaryMuscle: String = ""
    /// Hidden from the current form, but preserved for existing exercises.
    var secondaryMuscles: [String] = []
    var movementPattern: MovementPattern? = nil
    var unilateral: Bool = false
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
        formatIncrement(appDefaultWeightIncrement)
    }

    // MARK: - Init

    init(
        exercise: Exercise?,
        exerciseService: any ExerciseServiceProtocol,
        settingsService: any SettingsServiceProtocol
    ) {
        self.exerciseService = exerciseService
        self.settingsService = settingsService
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
        appDefaultRestTime = profile.defaultRestTimeSeconds
        appDefaultWeightIncrement = profile.prescriptionDefaultIncrement
    }

    // MARK: - Save

    func save() async throws {
        guard isValid else { return }

        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let muscle = ExercisePrimaryGroup.normalizedValue(primaryMuscle)
        let resolvedUnilateral = supportsUnilateral ? self.unilateral : false

        if isEditing, let existing = existingExercise {
            let originalTrackingType = existing.trackingType
            existing.name = trimmedName
            existing.equipmentType = equipmentType
            if !isTrackingTypeLocked {
                existing.trackingType = trackingType
            }
            existing.primaryMuscle = muscle
            existing.secondaryMuscles = secondaryMuscles
            existing.movementPattern = movementPattern
            existing.unilateral = resolvedUnilateral
            existing.bilateralLoadFactor = bilateralLoadFactor
            existing.bodyweightFactor = bodyweightFactor
            existing.weightIncrement = weightIncrement
            existing.defaultRestTime = defaultRestTime
            existing.updatedAt = Date()

            try await exerciseService.updateExercise(existing, originalTrackingType: originalTrackingType)
        } else {
            let exercise = Exercise(
                name: trimmedName,
                equipmentType: equipmentType,
                trackingType: trackingType,
                primaryMuscle: muscle,
                secondaryMuscles: secondaryMuscles,
                movementPattern: movementPattern,
                unilateral: resolvedUnilateral,
                bilateralLoadFactor: bilateralLoadFactor,
                bodyweightFactor: bodyweightFactor,
                weightIncrement: weightIncrement,
                defaultRestTime: defaultRestTime
            )
            try await exerciseService.createExercise(exercise)
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

    private func formatIncrement(_ value: Double?) -> String {
        guard let value else { return "Not Set" }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f kg", value)
        }
        return String(format: "%.2f kg", value)
    }
}
