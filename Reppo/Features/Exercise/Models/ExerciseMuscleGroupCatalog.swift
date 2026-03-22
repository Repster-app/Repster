import Foundation

struct ExerciseMuscleGroupCatalog {
    struct Entry: Equatable {
        let value: String
        let displayName: String
    }

    static let supportedEntries: [Entry] = [
        Entry(value: "abs", displayName: "Abs"),
        Entry(value: "back", displayName: "Back"),
        Entry(value: "biceps", displayName: "Biceps"),
        Entry(value: "cardio", displayName: "Cardio"),
        Entry(value: "chest", displayName: "Chest"),
        Entry(value: "forearms", displayName: "Forearms"),
        Entry(value: "full body", displayName: "Full Body"),
        Entry(value: "legs", displayName: "Legs"),
        Entry(value: "shoulders", displayName: "Shoulders"),
        Entry(value: "triceps", displayName: "Triceps")
    ]

    static func normalizedValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case "core", "abdominals":
            return "abs"
        case "forearm":
            return "forearms"
        default:
            return normalized
        }
    }

    static func supportedValues(including currentValue: String?) -> [String] {
        let supportedValues = supportedEntries.map(\.value)

        guard let currentValue = normalizedValue(currentValue),
              !supportedValues.contains(currentValue) else {
            return supportedValues
        }

        return supportedValues + [currentValue]
    }

    static func displayName(for rawValue: String) -> String {
        let normalized = normalizedValue(rawValue) ?? rawValue

        if let entry = supportedEntries.first(where: { $0.value == normalized }) {
            return entry.displayName
        }

        return normalized
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    static func orderedValues(from rawValues: [String]) -> [String] {
        let availableValues = Set(rawValues.compactMap(normalizedValue))

        return supportedEntries
            .map(\.value)
            .filter { availableValues.contains($0) }
            .sorted { displayName(for: $0) < displayName(for: $1) }
    }
}
