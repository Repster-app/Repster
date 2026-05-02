// ProgramRepositoryProtocol.swift
// Contract for Program data access
// Spec: FR-001, FR-002, FR-003
// Source entity: Program (specdoc S6.8)

import Foundation

/// Repository protocol for Program entity.
/// Programs tab is v1.1 (empty state placeholder in v1).
/// Basic CRUD only — expanded in feature implementing Programs functionality.
protocol ProgramRepositoryProtocol: Sendable {

    // MARK: - CRUD

    func save(_ program: Program) async throws
    func delete(_ program: Program) async throws
    func fetch(byId id: UUID) async throws -> Program?

    // MARK: - Queries

    /// Fetch all programs, ordered by name ASC.
    func fetchAll() async throws -> [Program]
}
