// EditWorkoutViewModel.swift
// ViewModel for editing completed workouts.
// Mirrors ActiveWorkoutViewModel pattern but without timer, finish flow, or sub-tabs.
// Spec: 015-edit-historic-workout, FR-001 through FR-012

import SwiftUI

@Observable
@MainActor
final class EditWorkoutViewModel {

    // MARK: - Dependencies

    private let workoutId: UUID
    private let workoutService: any WorkoutServiceProtocol
    private let setService: any SetServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol
    private let statsService: any StatsServiceProtocol

    // MARK: - State

    var workout: Workout?
    var exercises: [Exercise] = []
    var selectedExerciseIndex: Int = 0
    var setsByExercise: [UUID: [WorkoutSet]] = [:]
    var notesText: String = ""
    var isLoading: Bool = true
    var showAddExerciseSheet: Bool = false

    // MARK: - Internal Tracking

    /// IDs of sets added during this edit session.
    /// Used by completeSet() to choose save() vs edit().
    private var newSetIds: Set<UUID> = []

    /// IDs of sets whose text fields have been edited but not yet persisted.
    private var dirtySetIds: Set<UUID> = []

    // MARK: - Init

    init(
        workoutId: UUID,
        workoutService: any WorkoutServiceProtocol,
        setService: any SetServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        statsService: any StatsServiceProtocol
    ) {
        self.workoutId = workoutId
        self.workoutService = workoutService
        self.setService = setService
        self.exerciseService = exerciseService
        self.statsService = statsService
    }

    // MARK: - Load

    /// Load a completed workout with all its exercises and sets.
    func loadWorkout() async {
        isLoading = true
        do {
            // 1. Fetch workout
            guard let workout = try await workoutService.fetchWorkout(workoutId) else {
                isLoading = false
                return
            }
            self.workout = workout
            self.notesText = workout.notes ?? ""

            // 2. Fetch all sets for this workout
            let sets = try await setService.fetchSets(for: workout.id)

            // 3. Group sets by exerciseId
            var exerciseSetMap: [UUID: [WorkoutSet]] = [:]
            for set in sets {
                exerciseSetMap[set.exerciseId, default: []].append(set)
            }

            // 4. Fetch each unique exercise and sort sets within each group
            var loadedExercises: [(exercise: Exercise, firstOrder: Int)] = []
            for (exerciseId, exerciseSets) in exerciseSetMap {
                guard let exercise = try await exerciseService.fetchExercise(exerciseId) else {
                    continue
                }
                let sorted = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }
                exerciseSetMap[exerciseId] = sorted
                let firstOrder = sorted.first?.orderInWorkout ?? Int.max
                loadedExercises.append((exercise, firstOrder))
            }

            // 5. Sort exercises by their first set's orderInWorkout
            loadedExercises.sort { $0.firstOrder < $1.firstOrder }

            // 6. Populate state
            self.exercises = loadedExercises.map(\.exercise)
            self.setsByExercise = exerciseSetMap
            self.selectedExerciseIndex = 0
            self.isLoading = false
        } catch {
            print("[EditWorkoutViewModel] Load failed: \(error)")
            isLoading = false
        }
    }

    // MARK: - Set Actions

    /// Complete or update a set with the given values.
    ///
    /// For new sets (added during this edit session): calls setService.save().
    /// For existing sets: calls setService.edit().
    func completeSet(
        _ set: WorkoutSet,
        weight: Double?,
        reps: Int?,
        durationSeconds: Int?,
        distanceMeters: Double?
    ) async {
        // Update set values
        set.weight = weight
        set.reps = reps
        set.durationSeconds = durationSeconds
        set.distanceMeters = distanceMeters
        set.completed = true
        set.completedAt = Date()
        set.updatedAt = Date()

        do {
            let result: SetSaveResult

            if newSetIds.contains(set.id) {
                // New set added during this edit session → save()
                result = try await setService.save(set)
            } else {
                // Existing set being edited → edit()
                result = try await setService.edit(set)
            }

            // Apply pipeline results to local state
            set.effectiveWeight = result.effectiveWeight
            set.cachedPRStatus = result.prResult.newStatus

            // Apply affected sets (PR status changes on other sets)
            applyAffectedSets(result.prResult.affectedSetIds)

            // Reassign array to trigger @Observable update for UI
            if let sets = setsByExercise[set.exerciseId] {
                setsByExercise[set.exerciseId] = sets
            }

            // Already persisted — no longer dirty
            dirtySetIds.remove(set.id)

        } catch {
            print("[EditWorkoutViewModel] completeSet failed: \(error)")
        }
    }

    /// Uncomplete a set, flipping it back to incomplete state.
    ///
    /// Uses setService.uncomplete() which models uncompleting as "removing a set's
    /// contribution" — demotes PRs and decrements stats without deleting the set.
    func uncompleteSet(_ set: WorkoutSet) async {
        let exerciseId = set.exerciseId
        let oldCompleted = set.completed

        do {
            let result = try await setService.uncomplete(set)
            set.effectiveWeight = result.effectiveWeight
            set.cachedPRStatus = result.prResult.newStatus
            applyAffectedSets(result.prResult.affectedSetIds)

            // Reassign array to trigger @Observable update
            if let sets = setsByExercise[exerciseId] {
                setsByExercise[exerciseId] = sets
            }

            // Already persisted — no longer dirty
            dirtySetIds.remove(set.id)
        } catch {
            // Revert on failure
            set.completed = oldCompleted
            print("[EditWorkoutViewModel] uncompleteSet failed: \(error)")
        }
    }

    /// Add a new working set for the given exercise.
    func addSet(for exerciseId: UUID) async {
        guard workout != nil else { return }

        let totalSets = setsByExercise.values.flatMap { $0 }.count
        let exerciseSets = setsByExercise[exerciseId] ?? []

        let newSet = WorkoutSet(
            workoutId: workoutId,
            exerciseId: exerciseId,
            date: workout?.date ?? Date(),
            setType: .working,
            orderInWorkout: totalSets + 1,
            orderInExercise: exerciseSets.count + 1,
            completed: false
        )

        do {
            _ = try await setService.save(newSet)
            newSetIds.insert(newSet.id)
            setsByExercise[exerciseId, default: []].append(newSet)
        } catch {
            print("[EditWorkoutViewModel] addSet failed: \(error)")
        }
    }

    /// Add a new warmup set for the given exercise.
    ///
    /// Inserts before the first non-warmup set and reindexes.
    func addWarmupSet(for exerciseId: UUID) async {
        guard workout != nil else { return }

        let totalSets = setsByExercise.values.flatMap { $0 }.count

        let newSet = WorkoutSet(
            workoutId: workoutId,
            exerciseId: exerciseId,
            date: workout?.date ?? Date(),
            setType: .warmup,
            orderInWorkout: totalSets + 1,
            orderInExercise: 1,
            completed: false
        )

        do {
            _ = try await setService.save(newSet)
            newSetIds.insert(newSet.id)

            // Insert before the first non-warmup set and reindex
            var sets = setsByExercise[exerciseId] ?? []
            let insertIndex = sets.firstIndex(where: { $0.setType != .warmup }) ?? sets.count
            sets.insert(newSet, at: insertIndex)
            reindexOrderInExercise(&sets)
            setsByExercise[exerciseId] = sets
        } catch {
            print("[EditWorkoutViewModel] addWarmupSet failed: \(error)")
        }
    }

    /// Delete a set from the workout.
    func deleteSet(_ set: WorkoutSet) async {
        let exerciseId = set.exerciseId

        do {
            try await setService.delete(set)

            // Remove from local state
            setsByExercise[exerciseId]?.removeAll { $0.id == set.id }

            // Reindex remaining sets
            if var sets = setsByExercise[exerciseId] {
                reindexOrderInExercise(&sets)
                setsByExercise[exerciseId] = sets
            }

            // Remove from newSetIds if it was added during this session
            newSetIds.remove(set.id)

        } catch {
            print("[EditWorkoutViewModel] deleteSet failed: \(error)")
        }
    }

    /// Change a set's type (e.g., warmup -> working -> dropset).
    func changeSetType(_ set: WorkoutSet, to type: SetType) async {
        set.setType = type
        set.updatedAt = Date()

        do {
            let result = try await setService.edit(set)
            set.effectiveWeight = result.effectiveWeight
            set.cachedPRStatus = result.prResult.newStatus
            applyAffectedSets(result.prResult.affectedSetIds)
        } catch {
            print("[EditWorkoutViewModel] changeSetType failed: \(error)")
        }
    }

    // MARK: - Exercise Actions

    /// Add exercises to the workout via the exercise picker.
    func addExercises(_ exerciseIds: [UUID]) async {
        for exerciseId in exerciseIds {
            do {
                guard let exercise = try await exerciseService.fetchExercise(exerciseId) else {
                    continue
                }
                exercises.append(exercise)
                setsByExercise[exerciseId] = []

                // Create initial empty working set
                await addSet(for: exerciseId)
            } catch {
                print("[EditWorkoutViewModel] addExercise failed: \(error)")
            }
        }

        // Switch to the last added exercise
        if !exercises.isEmpty {
            selectedExerciseIndex = exercises.count - 1
        }
    }

    /// Reorder exercises by moving from source indices to destination.
    func reorderExercises(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)

        // Update selectedExerciseIndex to follow the moved exercise
        if let sourceIndex = source.first {
            if sourceIndex == selectedExerciseIndex {
                if destination > sourceIndex {
                    selectedExerciseIndex = destination - 1
                } else {
                    selectedExerciseIndex = destination
                }
            }
        }
    }

    /// Remove the exercise at the given index and delete all its sets.
    func removeExercise(at index: Int) async {
        guard index >= 0, index < exercises.count else { return }

        let exercise = exercises[index]
        let exerciseSets = setsByExercise[exercise.id] ?? []

        // Delete all sets for this exercise
        for set in exerciseSets {
            do {
                try await setService.delete(set)
                newSetIds.remove(set.id)
            } catch {
                print("[EditWorkoutViewModel] delete set during removeExercise failed: \(error)")
            }
        }

        // Remove from local state
        exercises.remove(at: index)
        setsByExercise.removeValue(forKey: exercise.id)

        // Clamp selectedExerciseIndex
        if selectedExerciseIndex >= exercises.count {
            selectedExerciseIndex = max(0, exercises.count - 1)
        }
    }

    // MARK: - Notes

    /// Save notes via WorkoutService, only when changed.
    func saveNotes() async {
        guard let workout else { return }

        // Only save if notes actually changed
        let currentNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalNotes = (workout.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentNotes != originalNotes else { return }

        do {
            try await workoutService.updateWorkoutMetadata(
                workout.id,
                notes: currentNotes.isEmpty ? nil : currentNotes,
                perceivedEffort: workout.perceivedEffort
            )
        } catch {
            print("[EditWorkoutViewModel] saveNotes failed: \(error)")
        }
    }

    // MARK: - Dirty Set Tracking

    /// Mark a set as having unsaved text changes.
    func markSetDirty(_ set: WorkoutSet) {
        dirtySetIds.insert(set.id)
    }

    /// Save all sets that have been edited via text fields but not yet persisted.
    /// Called when the user taps "Done" to dismiss the edit view.
    func saveDirtySets() async {
        guard !dirtySetIds.isEmpty else { return }

        let allSets = setsByExercise.values.flatMap { $0 }
        for set in allSets where dirtySetIds.contains(set.id) {
            set.updatedAt = Date()
            do {
                let result: SetSaveResult
                if newSetIds.contains(set.id) {
                    result = try await setService.save(set)
                } else {
                    result = try await setService.edit(set)
                }
                set.effectiveWeight = result.effectiveWeight
                set.cachedPRStatus = result.prResult.newStatus
                applyAffectedSets(result.prResult.affectedSetIds)
            } catch {
                print("[EditWorkoutViewModel] saveDirtySets failed for \(set.id): \(error)")
            }
        }
        dirtySetIds.removeAll()
    }

    // MARK: - Computed

    var currentExercise: Exercise? {
        guard selectedExerciseIndex >= 0,
              selectedExerciseIndex < exercises.count else { return nil }
        return exercises[selectedExerciseIndex]
    }

    var currentSets: [WorkoutSet] {
        guard let exercise = currentExercise else { return [] }
        return setsByExercise[exercise.id] ?? []
    }

    // MARK: - Private Helpers

    /// Apply PR status changes to other sets affected by a save/edit/delete.
    /// For completed sets, only applies demotions (not promotions) to avoid
    /// confusing retroactive badge changes during editing.
    private func applyAffectedSets(_ affectedSetIds: [UUID: CachedPRStatus?]) {
        guard !affectedSetIds.isEmpty else { return }

        for (exerciseId, sets) in setsByExercise {
            var updatedSets = sets
            var changed = false
            for (index, set) in updatedSets.enumerated() {
                if let newStatus = affectedSetIds[set.id] {
                    if set.completed, isStatusUpgrade(from: set.cachedPRStatus, to: newStatus) {
                        continue
                    }
                    updatedSets[index].cachedPRStatus = newStatus
                    changed = true
                }
            }
            if changed {
                setsByExercise[exerciseId] = updatedSets
            }
        }
    }

    /// Returns true if the new status is a "promotion" (more prominent badge).
    private func isStatusUpgrade(from old: CachedPRStatus?, to new: CachedPRStatus?) -> Bool {
        func rank(_ status: CachedPRStatus?) -> Int {
            switch status {
            case .current: return 3
            case .matched: return 2
            case .dominated, .previous: return 1
            case nil: return 0
            }
        }
        return rank(new) > rank(old)
    }

    /// Reindex orderInExercise for a set array after insertion/deletion.
    private func reindexOrderInExercise(_ sets: inout [WorkoutSet]) {
        for (index, set) in sets.enumerated() {
            set.orderInExercise = index + 1
        }
    }
}

// MARK: - SetTableDataSource Conformance

extension EditWorkoutViewModel: SetTableDataSource {
    /// Update the note on a set and persist via the edit pipeline.
    func updateSetNote(_ set: WorkoutSet, note: String?) async {
        set.notes = note
        set.updatedAt = Date()

        do {
            let result: SetSaveResult
            if newSetIds.contains(set.id) {
                result = try await setService.save(set)
            } else {
                result = try await setService.edit(set)
            }
            set.effectiveWeight = result.effectiveWeight
            set.cachedPRStatus = result.prResult.newStatus
            applyAffectedSets(result.prResult.affectedSetIds)

            // Reassign array to trigger @Observable update for UI
            if let sets = setsByExercise[set.exerciseId] {
                setsByExercise[set.exerciseId] = sets
            }
        } catch {
            print("[EditWorkoutViewModel] Failed to update set note: \(error)")
        }
    }
}
