// WeightSuggestionData.swift
// Transient display models for the Weight Suggestion module.
// Follows the same pattern as ExerciseInfoData.swift.

import Foundation

/// A single per-set weight suggestion for display.
struct SetSuggestion: Identifiable, Sendable {
    let id = UUID()
    /// 1-indexed set number in the exercise.
    let setNumber: Int
    /// Prescribed weight in kg (views handle unit conversion).
    let suggestedWeight: Double
    /// Target reps used for this prescription.
    let targetReps: Int
    /// Target RIR used for this prescription.
    let targetRIR: Double
    /// Brief context string, e.g. "Based on 104 kg e1RM, -5% fatigue".
    let contextLabel: String
}

/// Container for all weight suggestions for the current exercise.
struct WeightSuggestionData: Sendable {
    /// Per-set suggestions for unfilled working sets.
    let suggestions: [SetSuggestion]
    /// The base e1RM used for all suggestions (for display in header).
    let baseE1RM: Double?
    /// Source of the e1RM estimate.
    let e1RMSource: E1RMSource
}
