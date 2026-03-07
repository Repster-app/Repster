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
    private let existingExercise: Exercise?

    // MARK: - Form Fields

    var name: String = ""
    var equipmentType: EquipmentType = .barbell
    var trackingType: TrackingType = .weightReps
    var primaryMuscle: String = ""
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

    // MARK: - Computed

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var navigationTitle: String {
        isEditing ? "Edit Exercise" : "New Exercise"
    }

    // MARK: - Init

    init(exercise: Exercise?, exerciseService: any ExerciseServiceProtocol) {
        self.exerciseService = exerciseService
        self.existingExercise = exercise
        self.isEditing = exercise != nil

        if let exercise {
            name = exercise.name
            equipmentType = exercise.equipmentType
            trackingType = exercise.trackingType
            primaryMuscle = exercise.primaryMuscle ?? ""
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
        isTrackingTypeLocked = (try? await exerciseService.exerciseHasSets(exercise.id)) ?? false
    }

    // MARK: - Save

    func save() async throws {
        guard isValid else { return }

        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedMuscle = primaryMuscle.trimmingCharacters(in: .whitespaces)
        let muscle: String? = trimmedMuscle.isEmpty ? nil : trimmedMuscle.lowercased()

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
            existing.unilateral = unilateral
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
                unilateral: unilateral,
                bilateralLoadFactor: bilateralLoadFactor,
                bodyweightFactor: bodyweightFactor,
                weightIncrement: weightIncrement,
                defaultRestTime: defaultRestTime
            )
            try await exerciseService.createExercise(exercise)
        }
    }
}
