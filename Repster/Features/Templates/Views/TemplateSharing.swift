// TemplateSharing.swift
// Share-sheet plumbing and formatting shared by the templates screens.
//
// Prefixed with `Template` because these were file-private inside the old TemplateListSheet.swift and
// had to become internal to be shared across the split. Settings and Exercise each have their own
// private `ActivityShareSheet` / `temporaryShareURL` / `formatRestTime`; consolidating those is a
// separate job, so these stay namespaced rather than claiming the general names.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TemplateShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension UTType {
    static let repsterTemplate = UTType(exportedAs: "com.magnusespensen.repster.template", conformingTo: .json)
    static let legacyReppoTemplate = UTType(importedAs: "com.magnusespensen.reppo.template", conformingTo: .json)
    static let templateImportTypes: [UTType] = [
        .repsterTemplate,
        .legacyReppoTemplate,
    ]
}

func matchDescription(_ method: TemplateExerciseMatchMethod) -> String {
    switch method {
    case .exerciseId:
        return "exercise ID"
    case .normalizedName:
        return "normalized name"
    case .manualMapping:
        return "manual mapping"
    case .createNew:
        return "new exercise creation"
    }
}

func exerciseMetadataSummary(_ exercise: TemplateImportExercisePreview) -> String {
    var parts: [String] = [
        exercise.exercise.equipmentType.displayName,
        exercise.exercise.trackingType.displayName
    ]

    if let primaryMuscle = ExercisePrimaryGroup.normalizedValue(exercise.exercise.primaryMuscle) {
        parts.append(ExercisePrimaryGroup.displayName(for: primaryMuscle))
    }

    if let restTime = exercise.restTimeSeconds {
        parts.append(templateFormatRestTime(restTime))
    }

    parts.append("\(exercise.sets.count) set\(exercise.sets.count == 1 ? "" : "s")")
    return parts.joined(separator: " | ")
}

func templateFormatRestTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainder = seconds % 60
    if minutes > 0, remainder > 0 {
        return "\(minutes)m \(remainder)s rest"
    }
    if minutes > 0 {
        return "\(minutes)m rest"
    }
    return "\(seconds)s rest"
}

func templateTemporaryShareURL(
    filename: String,
    fileExtension: String,
    data: Data
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(filename)
        .appendingPathExtension(fileExtension)
    try data.write(to: url, options: .atomic)
    return url
}

func sanitizedFilename(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = trimmed.isEmpty ? "template" : trimmed
    let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    let components = fallback.components(separatedBy: invalidCharacters)
    return components.joined(separator: "-")
}

func timestampString() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}
