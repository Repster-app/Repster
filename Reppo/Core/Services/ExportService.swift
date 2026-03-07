// ExportService.swift
// Generates CSV export of all workout data.
// Spec: FR-001 through FR-009, SC-004 round-trip
// Feature: 011-csv-import-export WP04 T017-T019

import Foundation

actor ExportService: ExportServiceProtocol {

    // MARK: - Dependencies

    private let exerciseRepo: any ExerciseRepositoryProtocol
    private let setRepo: any SetRepositoryProtocol

    // MARK: - Constants

    private let header = "Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind"
    private let kgToLbs = 2.20462

    // MARK: - Init

    init(
        exerciseRepo: any ExerciseRepositoryProtocol,
        setRepo: any SetRepositoryProtocol
    ) {
        self.exerciseRepo = exerciseRepo
        self.setRepo = setRepo
    }

    // MARK: - ExportServiceProtocol

    func exportCSV() async throws -> Data {
        // Fetch all exercises and build lookup
        let exercises = try await exerciseRepo.fetchAll()
        let exerciseLookup = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        // Fetch all sets using full date range
        let allSets = try await setRepo.fetchSets(from: .distantPast, to: .distantFuture)

        // Sort by date ASC → orderInWorkout ASC
        let sortedSets = allSets.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.orderInWorkout < b.orderInWorkout
        }

        // Build CSV
        var csv = header + "\n"

        // Date formatter: yyyy-MM-dd in UTC
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        for set in sortedSets {
            let exercise = exerciseLookup[set.exerciseId]

            let dateStr = dateFormatter.string(from: set.date)
            let exerciseName = escapeCSVField(exercise?.name ?? "Unknown")
            let category = escapeCSVField(exercise?.primaryMuscle ?? "")

            let weightKg: String
            let weightLbs: String
            if let w = set.weight {
                weightKg = formatWeight(w)
                weightLbs = formatWeight(w * kgToLbs)
            } else {
                weightKg = ""
                weightLbs = ""
            }

            let reps = set.reps.map { String($0) } ?? ""
            let distance = set.distanceMeters.map { formatWeight($0) } ?? ""
            let distanceUnit = set.distanceMeters != nil ? "m" : ""
            let time = set.durationSeconds.map { String($0) } ?? ""
            let notes = escapeCSVField(set.notes ?? "")
            let kind = reverseKindMapping(exercise?.trackingType)

            let row = [dateStr, exerciseName, category, weightKg, weightLbs,
                        reps, distance, distanceUnit, time, notes, kind]
            csv += row.joined(separator: ",") + "\n"
        }

        guard let data = csv.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    // MARK: - Reverse Kind Mapping (T019)

    private func reverseKindMapping(_ trackingType: TrackingType?) -> String {
        switch trackingType {
        case .weightReps:         return "wr"
        case .duration:           return "d"
        case .weightDistance:     return "wd"
        case .weightRepsDuration: return "wrd"
        case .custom:             return "wr"
        case nil:                 return "wr"
        }
    }

    // MARK: - CSV Helpers

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    private func formatWeight(_ value: Double) -> String {
        // Remove trailing zeros: 50.00 → "50", 50.50 → "50.5"
        let formatted = String(format: "%.2f", value)
        if formatted.hasSuffix(".00") {
            return String(formatted.dropLast(3))
        } else if formatted.hasSuffix("0") {
            return String(formatted.dropLast())
        }
        return formatted
    }
}

// MARK: - ExportError

enum ExportError: Error, LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode CSV data."
        }
    }
}
