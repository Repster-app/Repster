import Foundation
import SwiftData

enum SettingsResetError: LocalizedError {
    case seedLibraryUnavailable

    var errorDescription: String? {
        switch self {
        case .seedLibraryUnavailable:
            return "Reset completed, but the built-in exercise library could not be restored."
        }
    }
}

actor SettingsService: SettingsServiceProtocol {
    private let healthProfileRepository: any HealthProfileRepositoryProtocol
    private let prService: any PRServiceProtocol
    private let statsService: any StatsServiceProtocol
    private let modelContainer: ModelContainer
    private let userDefaults: UserDefaults
    private let seedExercises: @Sendable (ModelContext) -> Void

    init(
        healthProfileRepository: any HealthProfileRepositoryProtocol,
        prService: any PRServiceProtocol,
        statsService: any StatsServiceProtocol,
        modelContainer: ModelContainer,
        userDefaults: UserDefaults = .standard,
        seedExercises: @escaping @Sendable (ModelContext) -> Void = { context in
            SeedService.seedIfNeeded(modelContext: context)
        }
    ) {
        self.healthProfileRepository = healthProfileRepository
        self.prService = prService
        self.statsService = statsService
        self.modelContainer = modelContainer
        self.userDefaults = userDefaults
        self.seedExercises = seedExercises
    }

    // MARK: - Read

    func fetchSettingsSnapshot() async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.fetchSnapshotOrCreate()
    }

    // MARK: - Write

    func updateUnitPreference(_ preference: UnitPreference) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update { $0.unitPreference = preference }
    }

    func updateE1RMFormula(_ formula: E1RMFormula) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update { $0.e1RMFormula = formula.rawValue }
    }

    func updateIncludeWarmupsInVolume(_ include: Bool) async throws -> HealthProfileSnapshot {
        let snapshot = try await healthProfileRepository.update { $0.includeWarmupsInVolume = include }
        try await statsService.rebuildAll()
        return snapshot
    }

    func updateIncludeWarmupsInPRs(_ include: Bool) async throws -> HealthProfileSnapshot {
        let snapshot = try await healthProfileRepository.update { $0.includeWarmupsInPRs = include }
        try await prService.rebuildAll()
        return snapshot
    }

    func updateDefaultRestTime(_ seconds: Int?) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update { $0.defaultRestTimeSeconds = seconds }
    }

    func updateDefaultWarmupRestTime(_ seconds: Int?) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update { $0.defaultWarmupRestTimeSeconds = seconds }
    }

    func updateRestTimerAlert(_ value: String) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update { $0.restTimerAlert = value }
    }

    // MARK: - Smart Suggestions Settings

    func updatePrescriptionEnabled(_ enabled: Bool) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update { $0.prescriptionEnabled = enabled }
    }

    func updatePrescriptionRecencyWeeks(_ weeks: Int) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update {
            $0.prescriptionRecencyWeeks = max(2, min(12, weeks))
        }
    }

    func updatePrescriptionDefaultIncrement(_ increment: Double) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update { $0.prescriptionDefaultIncrement = increment }
    }

    func updatePrescriptionDefaultTargetReps(_ reps: Int) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update {
            $0.prescriptionDefaultTargetReps = max(1, min(30, reps))
        }
    }

    func updatePrescriptionDefaultTargetRIR(_ rir: Int) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update {
            $0.prescriptionDefaultTargetRIR = max(0, min(5, rir))
        }
    }

    func updatePrescriptionFreshnessBonus(enabled: Bool, percent: Double) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update {
            $0.prescriptionFreshnessBonus = enabled
            $0.prescriptionFreshnessBonusPercent = max(0.0, min(0.10, percent))
        }
    }

    func updatePrescriptionFatigueModelingEnabled(_ enabled: Bool) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update {
            $0.prescriptionFatigueModelingEnabled = enabled
        }
    }

    func updatePrescriptionCapacityGuardsEnabled(_ enabled: Bool) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update {
            $0.prescriptionCapacityGuardsEnabled = enabled
        }
    }

    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update {
            $0.prescriptionDefaultRecoveryConstant = max(60, min(600, seconds))
        }
    }

    func updatePrescriptionAdminModeEnabled(_ enabled: Bool) async throws -> HealthProfileSnapshot {
        try await healthProfileRepository.update {
            $0.prescriptionAdminModeEnabled = enabled
        }
    }

    // MARK: - Data Reset

    func resetAllAppData() async throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        try deleteAll(WorkoutSet.self, in: context)
        try deleteAll(Workout.self, in: context)
        try deleteAll(ExerciseStats.self, in: context)
        try deleteAll(PerformanceRecord.self, in: context)
        try deleteAll(FatigueObservation.self, in: context)
        try deleteAll(FatigueLearningSetAudit.self, in: context)
        try deleteAll(BodyweightEntry.self, in: context)
        try deleteAll(HealthProfile.self, in: context)
        try deleteAll(ProgramExercise.self, in: context)
        try deleteAll(Program.self, in: context)
        try deleteAll(PlannedSet.self, in: context)
        try deleteAll(PlannedWorkout.self, in: context)
        try deleteAll(TemplateSet.self, in: context)
        try deleteAll(TemplateExercise.self, in: context)
        try deleteAll(WorkoutTemplate.self, in: context)
        try deleteAll(Exercise.self, in: context)
        try context.save()

        clearStoredAppState()
        seedExercises(context)

        guard try context.fetchCount(FetchDescriptor<Exercise>()) > 0 else {
            throw SettingsResetError.seedLibraryUnavailable
        }

        _ = try await healthProfileRepository.fetchSnapshotOrCreate()
    }

    // MARK: - Rebuild Operations

    func rebuildPRs() async throws {
        try await prService.rebuildAll()
    }

    func rebuildStats() async throws {
        try await statsService.rebuildAll()
    }

    func rebuildAll() async throws {
        try await prService.rebuildAll()
        try await statsService.rebuildAll()
    }

    // MARK: - Helpers

    private func deleteAll<Model: PersistentModel>(_ modelType: Model.Type, in context: ModelContext) throws {
        let models = try context.fetch(FetchDescriptor<Model>())
        for model in models {
            context.delete(model)
        }
    }

    private func clearStoredAppState() {
        userDefaults.removeObject(forKey: "chartExercisePresets")
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockWorkoutId)
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockAccumulatedElapsedSeconds)
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockLastResumedAt)
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockIsPaused)
        ActiveWorkoutSessionDefaultsKeys.clearRestTimerState(in: userDefaults)

        // Clearing the keys is not enough on its own: the alarm is scheduled with iOS, not
        // stored here, so wiping the state without this left a pending "rest is over" to fire
        // for a workout that no longer exists.
        RestTimerAlarmCoordinator.cancel()
    }
}
