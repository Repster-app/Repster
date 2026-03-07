import Foundation

// MARK: - ExportServiceProtocol

protocol ExportServiceProtocol: Sendable {

    // MARK: - Export

    /// Generate CSV data for all workouts, exercises, and sets.
    /// Returns UTF-8 encoded CSV data ready for file sharing.
    func exportCSV() async throws -> Data
}
