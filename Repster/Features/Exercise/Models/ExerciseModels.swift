// ExerciseModels.swift
// Supporting types for Exercise Detail views.
// Used by ExerciseDetailViewModel for data passing.
// Contract: view-contracts.md WorkoutHistoryGroup
// Feature: 007-exercise-list-and-detail WP02/WP04

import Foundation

/// Groups sets by workout for the History tab display.
struct WorkoutHistoryGroup: Identifiable {
    let id: UUID
    let date: Date
    let sets: [WorkoutSet]
}
