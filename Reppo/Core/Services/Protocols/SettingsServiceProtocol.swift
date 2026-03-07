import Foundation

/// Service for reading/writing user settings on HealthProfile
/// and orchestrating side effects (rebuilds) when settings change.
///
/// SettingsService does NOT:
/// - Own PR logic (delegates to PRService)
/// - Own stats logic (delegates to StatsService)
/// - Access ModelContext directly (uses HealthProfileRepository)
protocol SettingsServiceProtocol: Sendable {

    // MARK: - Read

    func fetchSettings() async throws -> HealthProfile

    // MARK: - Write

    func updateUnitPreference(_ preference: UnitPreference) async throws
    func updateE1RMFormula(_ formula: E1RMFormula) async throws
    func updateIncludeWarmupsInVolume(_ include: Bool) async throws
    func updateIncludeWarmupsInPRs(_ include: Bool) async throws
    func updateDefaultRestTime(_ seconds: Int?) async throws

    // MARK: - Weight Prescription Settings

    func updatePrescriptionEnabled(_ enabled: Bool) async throws
    func updatePrescriptionRecencyWeeks(_ weeks: Int) async throws
    func updatePrescriptionDefaultIncrement(_ increment: Double) async throws
    func updatePrescriptionFreshnessBonus(enabled: Bool, percent: Double) async throws
    func updatePrescriptionFatigueModelingEnabled(_ enabled: Bool) async throws
    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws

    // MARK: - Rebuild Operations

    func rebuildPRs() async throws
    func rebuildStats() async throws
    func rebuildAll() async throws
}
