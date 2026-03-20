import Foundation

// MARK: - ImportProgress

enum ImportProgress: Sendable {
    case parsing
    case validating(processed: Int, total: Int)
    case importing(inserted: Int, total: Int)
    case rebuilding(phase: RebuildPhase)
    case completed(ImportResult)
    case failed(ImportError)

    enum RebuildPhase: String, Sendable {
        case stats = "Rebuilding statistics..."
        case prs = "Rebuilding personal records..."
    }
}

// MARK: - ImportResult

struct ImportResult: Sendable {
    let setsImported: Int
    let workoutsCreated: Int
    let exercisesCreated: Int
    let rowsSkipped: Int
    let errors: [CSVParser.ValidationError]
    let duration: TimeInterval
}

// MARK: - ImportError

enum ImportError: Error, LocalizedError, Sendable {
    case fileReadFailed(String)
    case invalidEncoding
    case invalidHeader(expected: [String], got: [String])
    case noValidRows
    case insertFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let msg):
            return "Failed to read file: \(msg)"
        case .invalidEncoding:
            return "Unable to read file. Please ensure it is UTF-8 encoded."
        case .invalidHeader:
            return "This CSV doesn't look like a FitNotes export. Reppo currently supports FitNotes CSV imports only."
        case .noValidRows:
            return "No valid data rows found in the CSV file."
        case .insertFailed(let msg):
            return "Database insert failed: \(msg)"
        case .cancelled:
            return "Import was cancelled."
        }
    }
}

// MARK: - ImportServiceProtocol

protocol ImportServiceProtocol: Sendable {

    // MARK: - Preview

    /// Parse first N rows for preview display. Does NOT modify any data.
    func previewCSV(data: Data) throws -> CSVParser.PreviewResult

    // MARK: - Import

    /// Run full import. Returns an AsyncStream of progress updates.
    /// Caller MUST consume the stream to completion.
    func importCSV(data: Data) -> AsyncStream<ImportProgress>
}
