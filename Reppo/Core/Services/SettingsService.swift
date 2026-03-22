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
        seedExercises: @escaping @Sendable (ModelContext) -> Void = SeedService.seedIfNeeded
    ) {
        self.healthProfileRepository = healthProfileRepository
        self.prService = prService
        self.statsService = statsService
        self.modelContainer = modelContainer
        self.userDefaults = userDefaults
        self.seedExercises = seedExercises
    }

    // MARK: - Read

    func fetchSettings() async throws -> HealthProfile {
        try await healthProfileRepository.fetchOrCreate()
    }

    // MARK: - Write

    func updateUnitPreference(_ preference: UnitPreference) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.unitPreference = preference
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updateE1RMFormula(_ formula: E1RMFormula) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.e1RMFormula = formula.rawValue
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updateIncludeWarmupsInVolume(_ include: Bool) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.includeWarmupsInVolume = include
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
        try await statsService.rebuildAll()
    }

    func updateIncludeWarmupsInPRs(_ include: Bool) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.includeWarmupsInPRs = include
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
        try await prService.rebuildAll()
    }

    func updateDefaultRestTime(_ seconds: Int?) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.defaultRestTimeSeconds = seconds
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updateDefaultWarmupRestTime(_ seconds: Int?) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.defaultWarmupRestTimeSeconds = seconds
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updateRestTimerAlert(_ value: String) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.restTimerAlert = value
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    // MARK: - Smart Suggestions Settings

    func updatePrescriptionEnabled(_ enabled: Bool) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.prescriptionEnabled = enabled
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updatePrescriptionRecencyWeeks(_ weeks: Int) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.prescriptionRecencyWeeks = max(2, min(12, weeks))
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updatePrescriptionDefaultIncrement(_ increment: Double) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.prescriptionDefaultIncrement = increment
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updatePrescriptionDefaultTargetReps(_ reps: Int) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.prescriptionDefaultTargetReps = max(1, min(30, reps))
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updatePrescriptionDefaultTargetRIR(_ rir: Int) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.prescriptionDefaultTargetRIR = max(0, min(5, rir))
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updatePrescriptionFreshnessBonus(enabled: Bool, percent: Double) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.prescriptionFreshnessBonus = enabled
        profile.prescriptionFreshnessBonusPercent = max(0.0, min(0.10, percent))
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updatePrescriptionFatigueModelingEnabled(_ enabled: Bool) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.prescriptionFatigueModelingEnabled = enabled
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
    }

    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws {
        let profile = try await healthProfileRepository.fetchOrCreate()
        profile.prescriptionDefaultRecoveryConstant = max(60, min(600, seconds))
        profile.updatedAt = Date()
        try await healthProfileRepository.save(profile)
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

        _ = try await healthProfileRepository.fetchOrCreate()
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
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId)
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerStartDate)
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration)
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration)
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused)
        userDefaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource)
    }
}
