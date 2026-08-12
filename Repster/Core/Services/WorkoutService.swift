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
    private let fatigueLearningService: FatigueLearningService
    private let bodyweightService: BodyweightServiceProtocol
    private let healthKitService: HealthKitServiceProtocol

    init(
        workoutRepository: WorkoutRepositoryProtocol,
        setRepository: SetRepositoryProtocol,
        prService: PRServiceProtocol,
        statsService: StatsServiceProtocol,
        fatigueLearningService: FatigueLearningService,
        bodyweightService: BodyweightServiceProtocol,
        healthKitService: HealthKitServiceProtocol
    ) {
        self.workoutRepo = workoutRepository
        self.setRepo = setRepository
        self.prService = prService
        self.statsService = statsService
        self.fatigueLearningService = fatigueLearningService
        self.bodyweightService = bodyweightService
        self.healthKitService = healthKitService
    }

    // MARK: - Workout Lifecycle (FR-001, FR-003, FR-004)

    /// Start a new workout or return the existing active one.
    /// FR-004: Only one active workout at a time — return existing if one is in progress.
    func startWorkout(options: WorkoutStartOptions) async throws -> Workout {
        // Check for existing active workout first
        if let existing = try await workoutRepo.fetchInProgress() {
            return existing
        }

        // Create new workout
        let workout = Workout(
            date: Date(),
            startTime: Date(),
            status: .inProgress,
            excludeFromProgressionHistory: options.excludeFromProgressionHistory
        )
        try await workoutRepo.save(workout)
        return workout
    }

    /// Finish an active workout — set status, endTime, calculate duration, store title/notes/RPE.
    func finishWorkout(
        _ workoutId: UUID,
        title: String? = nil,
        notes: String? = nil,
        perceivedEffort: Double? = nil,
        durationSecondsOverride: Int? = nil
    ) async throws {
        guard let workout = try await workoutRepo.fetch(byId: workoutId) else {
            throw WorkoutServiceError.workoutNotFound(workoutId)
        }

        guard workout.status != .completed else {
            throw WorkoutServiceError.workoutAlreadyCompleted(workoutId)
        }

        workout.status = .completed
        workout.endTime = Date()

        // Calculate duration in seconds (specdoc S6.2)
        if let durationSecondsOverride {
            workout.duration = max(0, durationSecondsOverride)
        } else if let startTime = workout.startTime, let endTime = workout.endTime {
            workout.duration = Int(endTime.timeIntervalSince(startTime))
        }

        // Store optional summary fields from finish sheet
        workout.title = title
        workout.notes = notes
        workout.perceivedEffort = perceivedEffort

        workout.updatedAt = Date()
        try await workoutRepo.save(workout)

        // Mirror into Apple Health. Read the dates out here, inside this actor, so only a
        // plain value crosses the boundary — never the live model (that's the 1.3
        // EXC_BAD_ACCESS crash class).
        if let start = workout.startTime, let end = workout.endTime {
            scheduleHealthKitMirror(workoutId: workoutId, start: start, end: end)
        }
    }

    // MARK: - Apple Health Mirroring

    /// Kick off the Health write without blocking the finish.
    ///
    /// Fire-and-forget by design, for two reasons:
    /// 1. `finishWorkout` throwing on a HealthKit error would turn a permissions hiccup
    ///    into a *lost workout* — `ActiveWorkoutViewModel` awaits this before clearing
    ///    local state and dismissing.
    /// 2. It keeps HealthKit latency out of the tap-to-dismiss path.
    ///
    /// Note this is reached only from `finishWorkout`, never from a "workout became
    /// completed" observation — `ImportService` creates completed workouts directly, and
    /// restoring a backup must not dump a user's entire history into Apple Health.
    private func scheduleHealthKitMirror(workoutId: UUID, start: Date, end: Date) {
        guard healthKitService.isAvailable, healthKitService.isEnabled else { return }

        Task {
            await self.mirrorToHealthKit(workoutId: workoutId, start: start, end: end)
        }
    }

    private func mirrorToHealthKit(workoutId: UUID, start: Date, end: Date) async {
        // No bodyweight logged is a normal state (onboarding lets users skip it), not an
        // error: the workout is still written, just without an energy sample.
        let closestEntry = try? await bodyweightService.closestBodyweight(to: start)
        let payload = HealthKitWorkoutPayload(
            start: start,
            end: end,
            bodyweightKg: closestEntry?.bodyweightKg
        )

        guard let healthKitUUID = await healthKitService.saveWorkout(payload) else { return }

        // Fetch, mutate and save entirely inside the repository actor — this executor
        // must never touch a model that another context owns (see §5.5 of the crash analysis).
        try? await workoutRepo.setHealthKitUUID(healthKitUUID, forWorkoutId: workoutId)
    }

    // MARK: - Active Workout (FR-003, AGENT_RULES S7.3)

    /// Fetch the currently active workout (status == .inProgress), if any.
    /// Called at app launch to detect and resume an active workout.
    func getActiveWorkout() async throws -> Workout? {
        return try await workoutRepo.fetchInProgress()
    }

    func getActiveWorkoutSummary() async throws -> WorkoutSnapshot? {
        return try await workoutRepo.fetchInProgressSummary()
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

    // MARK: - Snapshot Reads

    func fetchWorkoutSummary(_ workoutId: UUID) async throws -> WorkoutSnapshot? {
        return try await workoutRepo.fetchWorkoutSummary(byId: workoutId)
    }

    func fetchWorkoutSummaries(for dateRange: ClosedRange<Date>) async throws -> [WorkoutSnapshot] {
        return try await workoutRepo.fetchWorkoutSummaries(for: dateRange)
    }

    func fetchAllWorkoutSummaries(limit: Int? = nil, offset: Int? = nil) async throws -> [WorkoutSnapshot] {
        return try await workoutRepo.fetchAllWorkoutSummaries(limit: limit, offset: offset)
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

    func updateProgressionHistoryExclusions(
        _ workoutId: UUID,
        excludeWorkout: Bool,
        excludedExerciseIds: Set<UUID>
    ) async throws {
        guard let workout = try await workoutRepo.fetch(byId: workoutId) else {
            throw WorkoutServiceError.workoutNotFound(workoutId)
        }

        let workoutExerciseIds = try await setRepo.fetchExerciseIds(for: workoutId)
        let sanitizedExcludedExerciseIds = workoutExerciseIds.intersection(excludedExerciseIds)

        let previousExcludedExerciseIds = workout.excludedExerciseIdsForProgressionHistory
        let previousExcludeWorkout = workout.excludesEntireWorkoutFromProgressionHistory

        workout.excludeFromProgressionHistory = excludeWorkout
        workout.excludedExerciseIdsFromProgressionHistory = Array(sanitizedExcludedExerciseIds).sorted {
            $0.uuidString < $1.uuidString
        }
        workout.updatedAt = Date()
        try await workoutRepo.save(workout)

        let affectedExerciseIds: Set<UUID>
        if previousExcludeWorkout != excludeWorkout {
            affectedExerciseIds = workoutExerciseIds
        } else {
            affectedExerciseIds = previousExcludedExerciseIds.symmetricDifference(sanitizedExcludedExerciseIds)
        }

        guard !affectedExerciseIds.isEmpty else { return }

        for exerciseId in affectedExerciseIds {
            try await prService.rebuild(for: exerciseId)
        }
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

        // 2b. Remove the mirrored Health sample, if we wrote one. Read the UUID out before
        // the model is deleted. Fire-and-forget — a Health failure must not block deletion.
        if let healthKitUUID = workout.healthKitWorkoutUUID {
            Task { await self.healthKitService.deleteWorkout(healthKitUUID: healthKitUUID) }
        }

        // 3. Remove fatigue learning rows tied to this workout before deleting core history.
        try await fatigueLearningService.removeCapturedWorkoutData(workoutId: workoutId)

        // 4. Bulk delete all sets for this workout
        try await setRepo.deleteSets(for: workoutId)

        // 5. Delete the workout itself
        try await workoutRepo.delete(workout)

        // 6. Rebuild PRs + stats for each affected exercise
        for exerciseId in affectedExerciseIds {
            try await prService.rebuild(for: exerciseId)
            try await statsService.rebuild(for: exerciseId)
        }
    }
}
