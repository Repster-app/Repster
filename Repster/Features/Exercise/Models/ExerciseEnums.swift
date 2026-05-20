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
/// - `.browse`: Standalone screen from FAB. Tap card body -> start flow. Tap trailing info -> detail/manage.
/// - `.addToWorkout`: Sheet from Active Workout. Tap anywhere toggles selection. "Add (N)" button.
/// - `.manage`: Pushed from Settings. Tap card -> exercise detail. No selection, no start, no close toolbar.
enum ExerciseListMode {
    case browse
    case addToWorkout
    case manage
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
    case abs
    case back
    case biceps
    case cardio
    case chest
    case forearms
    case legs
    case shoulders
    case triceps
    case fullBody = "full body"

    var id: String { rawValue }

    var displayName: String {
        ExerciseMuscleGroupCatalog.displayName(for: rawValue)
    }

    static func normalizedValue(_ rawValue: String?) -> String? {
        ExerciseMuscleGroupCatalog.normalizedValue(rawValue)
    }

    static func options(including currentValue: String?) -> [String] {
        ExerciseMuscleGroupCatalog.supportedValues(including: currentValue)
    }

    static func displayName(for rawValue: String) -> String {
        ExerciseMuscleGroupCatalog.displayName(for: rawValue)
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
