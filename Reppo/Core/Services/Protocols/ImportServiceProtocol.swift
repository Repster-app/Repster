import Foundation

// MARK: - ImportSource

enum ImportSource: String, CaseIterable, Identifiable, Sendable {
    case fitNotes
    case strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fitNotes:
            return "FitNotes"
        case .strong:
            return "Strong"
        }
    }

    var systemImageName: String {
        switch self {
        case .fitNotes:
            return "list.bullet.rectangle"
        case .strong:
            return "bolt.heart"
        }
    }

    var fileSelectionTitle: String {
        switch self {
        case .fitNotes:
            return "Select FitNotes CSV"
        case .strong:
            return "Select Strong CSV"
        }
    }

    var idleDescription: String {
        switch self {
        case .fitNotes:
            return "Imports FitNotes workout exports with date, exercise, category, weight, reps, distance, time, notes, and kind columns."
        case .strong:
            return "Imports Strong workout history exports with workout time, workout duration, set markers, weight, reps, distance, seconds, and optional RPE."
        }
    }

    var requiresUnitSystem: Bool {
        self == .strong
    }
}

// MARK: - ImportUnitSystem

enum ImportUnitSystem: String, CaseIterable, Identifiable, Sendable {
    case metric
    case imperial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metric:
            return "Metric"
        case .imperial:
            return "Imperial"
        }
    }

    var subtitle: String {
        switch self {
        case .metric:
            return "Kilograms (kg) and kilometers (km)"
        case .imperial:
            return "Pounds (lb) and miles (mi)"
        }
    }

    var summaryLabel: String {
        switch self {
        case .metric:
            return "Metric (kg, km)"
        case .imperial:
            return "Imperial (lb, mi)"
        }
    }
}

// MARK: - ImportPreview

struct ImportPreview: Sendable {
    let headers: [String]
    let sampleRows: [[String]]
    let estimatedTotalRows: Int
}

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
    let warnings: [CSVParser.ValidationError]
    let duration: TimeInterval
}

// MARK: - ImportError

enum ImportError: Error, LocalizedError, Sendable {
    case fileReadFailed(String)
    case invalidEncoding
    case invalidHeader(source: ImportSource, expected: [String], got: [String])
    case missingUnitSystem(source: ImportSource)
    case noValidRows
    case insertFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let msg):
            return "Failed to read file: \(msg)"
        case .invalidEncoding:
            return "Unable to read file. Please ensure it is UTF-8 encoded."
        case .invalidHeader(let source, _, _):
            return "This CSV doesn't look like a \(source.displayName) export. Reppo currently supports FitNotes and Strong CSV imports."
        case .missingUnitSystem(let source):
            return "Choose whether the \(source.displayName) export uses metric or imperial units before importing."
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
    func previewImport(data: Data, source: ImportSource, unitSystem: ImportUnitSystem?) throws -> ImportPreview

    // MARK: - Import

    /// Run full import. Returns an AsyncStream of progress updates.
    /// Caller MUST consume the stream to completion.
    func importData(data: Data, source: ImportSource, unitSystem: ImportUnitSystem?) -> AsyncStream<ImportProgress>
}
