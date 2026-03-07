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
