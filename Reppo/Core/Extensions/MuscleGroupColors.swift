// MuscleGroupColors.swift
// Static color mapping from muscle group name strings to SwiftUI Colors.
// Reference: research.md RQ-2

import SwiftUI

struct MuscleGroupColors {

    /// Returns a color for the given muscle group name (case-insensitive).
    static func color(for muscleGroup: String) -> Color {
        switch muscleGroup.lowercased() {
        case "chest", "pectorals":
            return .accent
        case "back", "lats", "upper back":
            return .success
        case "shoulders", "delts", "deltoids":
            return .gold
        case "legs", "quads", "quadriceps":
            return .danger
        case "biceps", "arms":
            return Color(red: 0.608, green: 0.498, blue: 0.902)
        case "triceps":
            return Color(red: 0.306, green: 0.804, blue: 0.769)
        case "core", "abs", "abdominals":
            return Color(red: 0.878, green: 0.533, blue: 0.314)
        case "glutes", "hamstrings", "posterior chain":
            return Color(red: 0.831, green: 0.420, blue: 0.620)
        default:
            return .textTertiary
        }
    }
}
