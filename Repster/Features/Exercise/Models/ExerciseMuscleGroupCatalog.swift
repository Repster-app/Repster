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

    struct MuscleArea: Equatable {
        let title: String
        let muscles: [String]
    }

    /// What an exercise can list as secondary, by area. Finer than `supportedEntries` on
    /// purpose: primaries, Insights and filters stay on those ten groups, and
    /// `coverageGroup` says which group each muscle here counts towards.
    static let secondaryMuscleAreas: [MuscleArea] = [
        MuscleArea(title: "Chest", muscles: ["chest"]),
        MuscleArea(title: "Shoulders", muscles: ["shoulders", "front delts", "side delts", "rear delts"]),
        MuscleArea(title: "Arms", muscles: ["biceps", "triceps", "forearms"]),
        MuscleArea(title: "Back", muscles: ["back", "lats", "traps", "lower back"]),
        MuscleArea(title: "Core", muscles: ["abs", "obliques"]),
        MuscleArea(title: "Legs", muscles: ["quads", "glutes", "hamstrings", "calves", "adductors"])
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

    /// `normalizedValue` plus the rollup from a finer muscle to the group it counts
    /// towards: rear delts are shoulders, traps are back, quads are legs.
    ///
    /// Deliberately kept out of `normalizedValue`. Every primary-muscle surface keys off
    /// that (Insights, charts, Home and Calendar dots, filters), and imported or generated
    /// exercises can carry a primary like "quads"; rolling it up there would regroup
    /// numbers users have already seen.
    static func coverageGroup(for rawValue: String?) -> String? {
        guard let normalized = normalizedValue(rawValue) else { return nil }

        switch normalized {
        case "front delts", "side delts", "rear delts":
            return "shoulders"
        case "lats", "traps", "lower back":
            return "back"
        case "obliques":
            return "abs"
        case "quads", "quadriceps", "glutes", "hamstrings", "calves", "adductors":
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

/// The muscles one exercise works, in the catalog's vocabulary.
///
/// Every surface that shows secondary muscles goes through this, so the dedupe rules live
/// in one place (SECONDARY_MUSCLES_SCOPING.md, Decision 2).
struct MuscleAttribution: Equatable, Sendable {
    /// The group the primary counts towards, so a legacy "quads" primary counts as legs.
    let primary: String?
    /// The other muscles worked, in stored order (the seed lists them by involvement).
    /// Never repeats one, and never names the primary, its group, cardio or full body.
    let secondary: [String]

    /// Groups that describe the whole session rather than a muscle.
    private static let nonMuscleGroups: Set<String> = ["cardio", "full body"]

    init(primaryMuscle: String?, secondaryMuscles: [String]) {
        var excluded = Self.nonMuscleGroups.union(Self.namesCoveredByPrimary(primaryMuscle))

        var secondary: [String] = []
        for rawValue in secondaryMuscles {
            guard let muscle = ExerciseMuscleGroupCatalog.normalizedValue(rawValue),
                  excluded.insert(muscle).inserted else { continue }
            secondary.append(muscle)
        }

        self.primary = ExerciseMuscleGroupCatalog.coverageGroup(for: primaryMuscle)
        self.secondary = secondary
    }

    /// The primary itself and the group it counts towards. A "legs" primary only covers
    /// "legs", so "quads" still shows under it: that says something the primary doesn't.
    private static func namesCoveredByPrimary(_ primaryMuscle: String?) -> Set<String> {
        Set([
            ExerciseMuscleGroupCatalog.normalizedValue(primaryMuscle),
            ExerciseMuscleGroupCatalog.coverageGroup(for: primaryMuscle)
        ].compactMap { $0 })
    }

    /// The areas the exercise editor lists: everything except what the primary already
    /// covers, plus an Other area for anything the exercise carries that isn't on the
    /// list (plain "legs" on a Thruster), so it can still be removed.
    static func secondaryAreas(
        primaryMuscle: String?,
        secondaryMuscles: [String]
    ) -> [ExerciseMuscleGroupCatalog.MuscleArea] {
        let covered = namesCoveredByPrimary(primaryMuscle)
        var areas = ExerciseMuscleGroupCatalog.secondaryMuscleAreas.compactMap { area in
            let muscles = area.muscles.filter { !covered.contains($0) }
            return muscles.isEmpty ? nil : ExerciseMuscleGroupCatalog.MuscleArea(title: area.title, muscles: muscles)
        }

        let listed = Set(areas.flatMap(\.muscles))
        let unlisted = MuscleAttribution(primaryMuscle: primaryMuscle, secondaryMuscles: secondaryMuscles)
            .secondary
            .filter { !listed.contains($0) }
        if !unlisted.isEmpty {
            areas.append(ExerciseMuscleGroupCatalog.MuscleArea(title: "Other", muscles: unlisted))
        }

        return areas
    }

    /// Adds `muscle` to a stored secondary list, or removes every spelling of it. Other
    /// tags keep their stored spelling and order.
    static func toggling(_ muscle: String, in secondaryMuscles: [String]) -> [String] {
        let remaining = secondaryMuscles.filter {
            ExerciseMuscleGroupCatalog.normalizedValue($0) != muscle
        }

        return remaining.count < secondaryMuscles.count ? remaining : secondaryMuscles + [muscle]
    }
}
