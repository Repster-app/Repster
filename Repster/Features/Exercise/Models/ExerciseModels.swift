// ExerciseModels.swift
// Supporting types for Exercise Detail views.
// Used by ExerciseDetailViewModel for data passing.
// Contract: view-contracts.md WorkoutHistoryGroup
// Feature: 007-exercise-list-and-detail WP02/WP04

import Foundation

/// Groups sets by workout for the History tab display.
///
/// Snapshots, not live models. `ExerciseHistoryView` renders these in a view body on the main
/// actor, and it is shown on **two** screens — exercise detail *and* the History sub-tab of the
/// active workout screen (`ActiveWorkoutView:242`). A live `WorkoutSet` there faults its
/// properties back through `SetRepository`'s background context while that context may be
/// saving, which is exactly crash B (`SetTableView.inputHeaders` faulting `Exercise.trackingType`
/// during layout). See STEP5_SCOPE_AND_TEST_STRATEGY.md §0.3.
struct WorkoutHistoryGroup: Identifiable {
    let id: UUID
    let date: Date
    let sets: [ChartSetData]
    /// Whether this session is ignored for PRs and future suggestions **for the exercise being
    /// viewed** — the whole-workout flag or an exercise-scoped one naming it.
    ///
    /// Resolved per exercise rather than per workout: a session excluded for only some of its
    /// exercises must mark those and leave the rest clean.
    let isExcludedFromProgression: Bool
}
