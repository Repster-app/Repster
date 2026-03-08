import Foundation

actor SettingsService: SettingsServiceProtocol {
    private let healthProfileRepository: any HealthProfileRepositoryProtocol
    private let prService: any PRServiceProtocol
    private let statsService: any StatsServiceProtocol

    init(
        healthProfileRepository: any HealthProfileRepositoryProtocol,
        prService: any PRServiceProtocol,
        statsService: any StatsServiceProtocol
    ) {
        self.healthProfileRepository = healthProfileRepository
        self.prService = prService
        self.statsService = statsService
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

    // MARK: - Weight Prescription Settings

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
}
