// ExerciseEnums.swift
// Shared enums for Feature 007: Exercise List + Detail
// Used across ExerciseListView, ExerciseDetailView, ActiveWorkoutView, and ContentView.

import Foundation

// MARK: - Navigation

/// The four real tabs in the main TabView. FAB is an overlay, not a tab.
enum MainTab: Int, CaseIterable {
    case home = 0
    case calendar = 1
    case charts = 2
    case settings = 3
}

// MARK: - Exercise List

/// Determines how the Exercise List behaves.
/// - `.browse`: Standalone screen from FAB. Tap card body -> detail. Tap selection circle -> toggle.
/// - `.addToWorkout`: Sheet from Active Workout. Tap anywhere toggles selection. "Add (N)" button.
enum ExerciseListMode {
    case browse
    case addToWorkout
}

/// Sort options for the exercise list.
enum ExerciseListSortOrder: String, CaseIterable {
    case alphabetical = "A-Z"
    case mostRecent = "Most Recent"
    case mostUsed = "Most Used"
}

/// Supported primary muscle groups for the create/edit exercise form.
///
/// Values are stored in lowercase to match existing persisted exercise data.
enum ExercisePrimaryGroup: String, CaseIterable, Identifiable {
    case back
    case biceps
    case chest
    case core
    case legs
    case shoulders
    case triceps
    case fullBody = "full body"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullBody:
            return "Full Body"
        default:
            return rawValue.capitalized
        }
    }

    static func normalizedValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalized.isEmpty ? nil : normalized
    }

    static func options(including currentValue: String?) -> [String] {
        let supportedValues = allCases.map(\.rawValue)

        guard let currentValue = normalizedValue(currentValue),
              !supportedValues.contains(currentValue) else {
            return supportedValues
        }

        return supportedValues + [currentValue]
    }

    static func displayName(for rawValue: String) -> String {
        let normalized = normalizedValue(rawValue) ?? rawValue

        if let group = allCases.first(where: { $0.rawValue == normalized }) {
            return group.displayName
        }

        return normalized
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Exercise Detail

/// Tabs within the Exercise Detail view.
enum ExerciseDetailTab: String, CaseIterable {
    case history = "History"
    case prs = "PRs"
    case charts = "Charts"
}

// MARK: - Active Workout Sub-Tabs

/// Sub-tabs within the Active Workout per-exercise view.
enum ExerciseSubTab: String, CaseIterable {
    case sets = "Sets"
    case history = "History"
    case prs = "PRs"
    case charts = "Charts"
}
