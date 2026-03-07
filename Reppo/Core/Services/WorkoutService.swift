// WorkoutService.swift
// Workout lifecycle management: create, finish, active detection, cascade deletion
// Spec: FR-001, FR-002, FR-003, FR-004, FR-010
// Source: specdoc S3, S6.2; AGENT_RULES S6, S7.3

import Foundation

actor WorkoutService: WorkoutServiceProtocol {

    // MARK: - Dependencies

    private let workoutRepo: WorkoutRepositoryProtocol
    private let setRepo: SetRepositoryProtocol
    private let prService: PRServiceProtocol
    private let statsService: StatsServiceProtocol

    init(
        workoutRepository: WorkoutRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        prService: PRServiceProtocol,
        statsService: StatsServiceProtocol
    ) {
        self.workoutRepo = workoutRepository
        self.setRepo = setRepository
        self.prService = prService
        self.statsService = statsService
    }

    // MARK: - Workout Lifecycle (FR-001, FR-003, FR-004)

    /// Start a new workout or return the existing active one.
    /// FR-004: Only one active workout at a time — return existing if one is in progress.
    func startWorkout() async throws -> Workout {
        // Check for existing active workout first
        if let existing = try await workoutRepo.fetchInProgress() {
            return existing
        }

        // Create new workout
        let workout = Workout(
            date: Date(),
            startTime: Date(),
            status: .inProgress
        )
        try await workoutRepo.save(workout)
        return workout
    }

    /// Finish an active workout — set status, endTime, calculate duration, store title/notes/RPE.
    func finishWorkout(_ workoutId: UUID, title: String? = nil, notes: String? = nil, perceivedEffort: Double? = nil) async throws {
        guard let workout = try await workoutRepo.fetch(byId: workoutId) else {
            throw WorkoutServiceError.workoutNotFound(workoutId)
        }

        guard workout.status != .completed else {
            throw WorkoutServiceError.workoutAlreadyCompleted(workoutId)
        }

        workout.status = .completed
        workout.endTime = Date()

        // Calculate duration in seconds (specdoc S6.2)
        if let startTime = workout.startTime, let endTime = workout.endTime {
            workout.duration = Int(endTime.timeIntervalSince(startTime))
        }

        // Store optional summary fields from finish sheet
        workout.title = title
        workout.notes = notes
        workout.perceivedEffort = perceivedEffort

        workout.updatedAt = Date()
        try await workoutRepo.save(workout)
    }

    // MARK: - Active Workout (FR-003, AGENT_RULES S7.3)

    /// Fetch the currently active workout (status == .inProgress), if any.
    /// Called at app launch to detect and resume an active workout.
    func getActiveWorkout() async throws -> Workout? {
        return try await workoutRepo.fetchInProgress()
    }

    // MARK: - CRUD

    func fetchWorkout(_ workoutId: UUID) async throws -> Workout? {
        return try await workoutRepo.fetch(byId: workoutId)
    }

    func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout] {
        return try await workoutRepo.fetchWorkouts(for: dateRange)
    }

    func fetchAllWorkouts(limit: Int? = nil, offset: Int? = nil) async throws -> [Workout] {
        return try await workoutRepo.fetchAllWorkouts(limit: limit, offset: offset)
    }

    // MARK: - Metadata Update (FR-009)

    /// Update metadata (notes, perceived effort) on a completed workout.
    func updateWorkoutMetadata(_ workoutId: UUID, notes: String?, perceivedEffort: Double?) async throws {
        guard let workout = try await workoutRepo.fetch(byId: workoutId) else {
            throw WorkoutServiceError.workoutNotFound(workoutId)
        }
        workout.notes = notes
        workout.perceivedEffort = perceivedEffort
        workout.updatedAt = Date()
        try await workoutRepo.save(workout)
    }

    // MARK: - Deletion (FR-010)

    /// Delete a workout with full cascade.
    /// Pipeline: get exerciseIds → bulk delete sets → delete workout → rebuild per exercise.
    func deleteWorkout(_ workoutId: UUID) async throws {
        // 1. Fetch workout
        guard let workout = try await workoutRepo.fetch(byId: workoutId) else {
            throw WorkoutServiceError.workoutNotFound(workoutId)
        }

        // 2. Get affected exerciseIds BEFORE deleting sets
        let affectedExerciseIds = try await setRepo.fetchExerciseIds(for: workoutId)

        // 3. Bulk delete all sets for this workout
        try await setRepo.deleteSets(for: workoutId)

        // 4. Delete the workout itself
        try await workoutRepo.delete(workout)

        // 5. Rebuild PRs + stats for each affected exercise
        for exerciseId in affectedExerciseIds {
            try await prService.rebuild(for: exerciseId)
            try await statsService.rebuild(for: exerciseId)
        }
    }
}
