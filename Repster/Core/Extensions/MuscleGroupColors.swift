// MuscleGroupColors.swift
// Static color mapping from muscle group name strings to SwiftUI Colors.
// Reference: research.md RQ-2

import SwiftUI

struct MuscleGroupColors {

    private static let fallbackPalette: [Color] = [
        Color(red: 0.208, green: 0.624, blue: 0.894),
        Color(red: 0.922, green: 0.525, blue: 0.212),
        Color(red: 0.306, green: 0.804, blue: 0.769),
        Color(red: 0.831, green: 0.420, blue: 0.620),
        Color(red: 0.608, green: 0.498, blue: 0.902),
        Color(red: 0.878, green: 0.533, blue: 0.314)
    ]

    /// Returns a color for the given muscle group name (case-insensitive).
    static func color(for muscleGroup: String) -> Color {
        switch ExercisePrimaryGroup.normalizedValue(muscleGroup) ?? muscleGroup.lowercased() {
        case "abs":
            return Color(red: 0.878, green: 0.533, blue: 0.314)
        case "chest", "pectorals":
            return .accent
        case "back", "lats", "upper back":
            return .success
        case "shoulders", "delts", "deltoids":
            return .gold
        case "cardio":
            return Color(red: 0.208, green: 0.624, blue: 0.894)
        case "legs", "quads", "quadriceps":
            return .danger
        case "biceps", "arms":
            return Color(red: 0.608, green: 0.498, blue: 0.902)
        case "forearms":
            return Color(red: 0.831, green: 0.420, blue: 0.620)
        case "triceps":
            return Color(red: 0.306, green: 0.804, blue: 0.769)
        case "glutes":
            return Color(red: 0.831, green: 0.420, blue: 0.620)
        case "hamstrings", "posterior chain":
            return Color(red: 0.482, green: 0.349, blue: 0.824)
        case "full body":
            return Color(red: 0.439, green: 0.710, blue: 0.404)
        default:
            return fallbackColor(for: muscleGroup)
        }
    }

    private static func fallbackColor(for rawValue: String) -> Color {
        let normalized = ExercisePrimaryGroup.normalizedValue(rawValue) ?? rawValue
        let hash = normalized.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            partialResult = ((partialResult << 5) &+ partialResult) &+ Int(scalar.value)
        }
        let index = abs(hash) % fallbackPalette.count
        return fallbackPalette[index]
    }
}
