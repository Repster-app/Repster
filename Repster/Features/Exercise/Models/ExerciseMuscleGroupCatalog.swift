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

    /// `normalizedValue` plus the leg rollup the seeded secondary tags need: glutes,
    /// quads, hamstrings and calves all count as `legs`.
    ///
    /// Deliberately kept out of `normalizedValue`. Every primary-muscle surface keys off
    /// that (Insights, charts, Home and Calendar dots, filters), and imported or generated
    /// exercises can carry a primary like "quads"; rolling it up there would regroup
    /// numbers users have already seen.
    static func coverageGroup(for rawValue: String?) -> String? {
        guard let normalized = normalizedValue(rawValue) else { return nil }

        switch normalized {
        case "glutes", "quads", "quadriceps", "hamstrings", "calves":
            return "legs"
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

/// The muscle groups one exercise works, in the catalog's vocabulary.
///
/// Every surface that shows secondary muscles goes through this, so the rollup and
/// dedupe rules live in one place (SECONDARY_MUSCLES_SCOPING.md, Decision 2).
struct MuscleAttribution: Equatable, Sendable {
    /// The primary's coverage group, so a legacy "quads" primary counts as legs here.
    let primary: String?
    /// The other groups worked, in stored order (the seed lists them by involvement).
    /// Never repeats a group, never includes the primary's group, cardio or full body.
    let secondary: [String]

    /// Groups that describe the whole session rather than a muscle.
    private static let nonMuscleGroups: Set<String> = ["cardio", "full body"]

    init(primaryMuscle: String?, secondaryMuscles: [String]) {
        let primary = ExerciseMuscleGroupCatalog.coverageGroup(for: primaryMuscle)
        var excluded = Self.nonMuscleGroups
        if let primary {
            excluded.insert(primary)
        }

        var secondary: [String] = []
        for rawValue in secondaryMuscles {
            guard let group = ExerciseMuscleGroupCatalog.coverageGroup(for: rawValue),
                  excluded.insert(group).inserted else { continue }
            secondary.append(group)
        }

        self.primary = primary
        self.secondary = secondary
    }

    /// Groups the exercise editor offers as secondaries: the catalog minus cardio, full
    /// body and the primary's group, plus any off-catalog group the exercise already
    /// carries so it can still be removed.
    static func secondaryOptions(primaryMuscle: String?, secondaryMuscles: [String]) -> [String] {
        let attribution = MuscleAttribution(primaryMuscle: primaryMuscle, secondaryMuscles: secondaryMuscles)
        let catalogOptions = ExerciseMuscleGroupCatalog.supportedEntries
            .map(\.value)
            .filter { !nonMuscleGroups.contains($0) && $0 != attribution.primary }

        return catalogOptions + attribution.secondary.filter { !catalogOptions.contains($0) }
    }

    /// Adds `group` to a stored secondary list, or removes every tag that rolls up to it.
    /// Other tags keep their stored spelling, so an edit never flattens a library
    /// exercise's "hamstrings, glutes" into "legs".
    static func toggling(_ group: String, in secondaryMuscles: [String]) -> [String] {
        let remaining = secondaryMuscles.filter {
            ExerciseMuscleGroupCatalog.coverageGroup(for: $0) != group
        }

        return remaining.count < secondaryMuscles.count ? remaining : secondaryMuscles + [group]
    }
}
