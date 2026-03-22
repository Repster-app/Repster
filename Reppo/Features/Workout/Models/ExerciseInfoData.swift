// ExerciseInfoData.swift
// Transient value types for Exercise Info section display
// Feature: 014-exercise-info-active-workout, WP01-T001

import Foundation

// MARK: - Trend

enum Trend: String, Sendable {
    case positive
    case negative
    case neutral
}

// MARK: - TopSet

struct TopSet: Identifiable, Sendable {
    let id = UUID()
    let weight: Double
    let reps: Int?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let formattedLabel: String
}

// MARK: - E1RMInfo

struct E1RMInfo: Sendable {
    let currentE1RM: Double
    let bestSetWeight: Double
    let bestSetReps: Int
    let historicalE1RM: Double?
    let historicalWeeksAgo: Int?
    let delta: Double?
    let trend: Trend?
}

// MARK: - LastWorkoutInfo

struct LastWorkoutInfo: Sendable {
    let topSets: [TopSet]
    let daysAgo: Int
    let relativeTimeLabel: String
}

// MARK: - EstimatedRepsInfo

struct EstimatedRepsInfo: Sendable {
    let targetReps: Int
    let estimatedWeight: Double
    let sourceLabel: String
}

// MARK: - ExerciseInfoData

struct ExerciseInfoData: Sendable {
    let e1RMInfo: E1RMInfo?
    let lastWorkoutInfo: LastWorkoutInfo?
    let estimatedRepsInfo: EstimatedRepsInfo?
    let trackingType: TrackingType
}
