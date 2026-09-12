import Foundation

/// Service for reading/writing user settings on HealthProfile
/// and orchestrating side effects (rebuilds) when settings change.
///
/// SettingsService does NOT:
/// - Own PR logic (delegates to PRService)
/// - Own stats logic (delegates to StatsService)
/// - Own view/UI state
protocol SettingsServiceProtocol: Sendable {

    // MARK: - Read

    func fetchSettingsSnapshot() async throws -> HealthProfileSnapshot

    // MARK: - Write

    func updateUnitPreference(_ preference: UnitPreference) async throws -> HealthProfileSnapshot
    func updateE1RMFormula(_ formula: E1RMFormula) async throws -> HealthProfileSnapshot
    func updateIncludeWarmupsInVolume(_ include: Bool) async throws -> HealthProfileSnapshot
    func updateIncludeWarmupsInPRs(_ include: Bool) async throws -> HealthProfileSnapshot
    func updateDefaultRestTime(_ seconds: Int?) async throws -> HealthProfileSnapshot
    func updateDefaultWarmupRestTime(_ seconds: Int?) async throws -> HealthProfileSnapshot
    func updateRestTimerAlert(_ value: String) async throws -> HealthProfileSnapshot

    // MARK: - Smart Suggestions Settings

    func updatePrescriptionEnabled(_ enabled: Bool) async throws -> HealthProfileSnapshot
    func updatePrescriptionRecencyWeeks(_ weeks: Int) async throws -> HealthProfileSnapshot
    func updatePrescriptionDefaultIncrement(_ increment: Double) async throws -> HealthProfileSnapshot
    func updatePrescriptionDefaultTargetReps(_ reps: Int) async throws -> HealthProfileSnapshot
    func updatePrescriptionDefaultTargetRIR(_ rir: Int) async throws -> HealthProfileSnapshot
    func updatePrescriptionFreshnessBonus(enabled: Bool, percent: Double) async throws -> HealthProfileSnapshot
    func updatePrescriptionFatigueModelingEnabled(_ enabled: Bool) async throws -> HealthProfileSnapshot
    /// Kill switch for the epoch-2 capacity guards. See
    /// ``HealthProfile/prescriptionCapacityGuardsEnabled``.
    func updatePrescriptionCapacityGuardsEnabled(_ enabled: Bool) async throws -> HealthProfileSnapshot
    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws -> HealthProfileSnapshot
    func updatePrescriptionAdminModeEnabled(_ enabled: Bool) async throws -> HealthProfileSnapshot

    // MARK: - Data Reset

    func resetAllAppData() async throws

    // MARK: - Rebuild Operations

    func rebuildPRs() async throws
    func rebuildStats() async throws
    func rebuildAll() async throws
}
