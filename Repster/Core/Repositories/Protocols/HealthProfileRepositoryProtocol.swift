// HealthProfileRepositoryProtocol.swift
// Contract for HealthProfile data access
// Spec: FR-001, FR-002, FR-003
// Source entity: HealthProfile (specdoc S6.7 + AGENT_RULES S8)

import Foundation

/// Repository protocol for HealthProfile entity.
/// HealthProfile is a single-row local table containing user settings:
/// unitPreference, includeWarmupsInVolume, includeWarmupsInPRs, e1RMFormula.
protocol HealthProfileRepositoryProtocol: Sendable {

    // MARK: - CRUD

    func save(_ profile: HealthProfile) async throws

    // MARK: - Queries

    /// Fetch the single HealthProfile, or nil if none exists yet.
    func fetch() async throws -> HealthProfile?

    /// Fetch the HealthProfile, creating one with defaults if none exists.
    /// Defaults: unitPreference = .metric, includeWarmupsInVolume = false,
    /// includeWarmupsInPRs = false, e1RMFormula = "epley".
    func fetchOrCreate() async throws -> HealthProfile
}
