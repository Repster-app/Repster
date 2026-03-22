// ChartModels.swift
// Chart data structures used across the Charts feature.
// Spec: FR-009, data-model.md
// Feature: 009-charts-tab WP01

import SwiftUI

// MARK: - Charts Tab v2 Enums
// Feature: 016-charts-tab-v2 WP05 (T101)

enum BreakdownMetric: String, CaseIterable, Identifiable {
    case volumeByCategory = "Volume by Category"
    case setsByCategory = "Sets by Category"
    case repsByCategory = "Reps by Category"
    case workoutsByCategory = "Workouts by Category"
    case volumeByExercise = "Volume by Exercise"
    case setsByExercise = "Sets by Exercise"
    case repsByExercise = "Reps by Exercise"
    case workoutsByExercise = "Workouts by Exercise"

    var id: String { rawValue }

    var groupBy: BreakdownGroupBy {
        switch self {
        case .volumeByCategory, .setsByCategory, .repsByCategory, .workoutsByCategory: return .category
        case .volumeByExercise, .setsByExercise, .repsByExercise, .workoutsByExercise: return .exercise
        }
    }

    var aggregateType: BreakdownAggregateType {
        switch self {
        case .volumeByCategory, .volumeByExercise: return .volume
        case .setsByCategory, .setsByExercise: return .sets
        case .repsByCategory, .repsByExercise: return .reps
        case .workoutsByCategory, .workoutsByExercise: return .workouts
        }
    }
}

enum BreakdownGroupBy { case category, exercise }

enum BreakdownAggregateType { case volume, sets, reps, workouts }

enum BreakdownTimeRange: String, CaseIterable, Identifiable {
    case all = "All"
    case year = "Year"
    case month = "Month"
    case week = "Week"
    case day = "Day"

    var id: String { rawValue }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .year: return cal.date(byAdding: .year, value: -1, to: Date())
        case .month: return cal.date(byAdding: .month, value: -1, to: Date())
        case .week: return cal.date(byAdding: .weekOfYear, value: -1, to: Date())
        case .day: return cal.startOfDay(for: Date())
        }
    }
}

enum WorkoutsMetric: String, CaseIterable, Identifiable {
    case reps = "Reps"
    case sets = "Sets"
    case volume = "Volume"
    case workouts = "Workouts"
    case distance = "Distance"
    case time = "Time"

    var id: String { rawValue }
}

enum WorkoutsAggregation: String, CaseIterable, Identifiable {
    case perWorkout = "Per Workout"
    case perWeek = "Per Week"
    case perMonth = "Per Month"
    case perYear = "Per Year"

    var id: String { rawValue }
}

enum WorkoutsFilter: Identifiable, Equatable, Hashable {
    case all
    case category(String)
    case exercise(UUID, name: String)

    var id: String {
        switch self {
        case .all: return "all"
        case .category(let name): return "cat:\(name)"
        case .exercise(let id, _): return "ex:\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .category(let name): return name
        case .exercise(_, let name): return name
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum WorkoutsTimeRange: String, CaseIterable, Identifiable {
    case all = "All"
    case oneYear = "1y"
    case sixMonths = "6mo"
    case threeMonths = "3mo"
    case oneMonth = "1mo"

    var id: String { rawValue }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .oneYear: return cal.date(byAdding: .year, value: -1, to: Date())
        case .sixMonths: return cal.date(byAdding: .month, value: -6, to: Date())
        case .threeMonths: return cal.date(byAdding: .month, value: -3, to: Date())
        case .oneMonth: return cal.date(byAdding: .month, value: -1, to: Date())
        }
    }
}

enum ExerciseMetric: String, CaseIterable, Identifiable {
    case estimatedOneRM = "Estimated 1RM"
    case maxWeight = "Max Weight"
    case maxReps = "Max Reps"
    case maxVolume = "Max Volume"
    case maxWeightForReps = "Max Weight for Reps"
    case workoutVolume = "Workout Volume"
    case workoutReps = "Workout Reps"
    case personalRecords = "Personal Records"
    case maxDistance = "Max Distance"
    case maxTime = "Max Time"
    case minPace = "Min Pace"

    var id: String { rawValue }

    var isWeightBased: Bool {
        switch self {
        case .maxDistance, .maxTime, .minPace: return false
        default: return true
        }
    }
}

// MARK: - Charts Tab v2 Data Structures
// Feature: 016-charts-tab-v2 WP05 (T102)

struct BreakdownDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

/// Summary stats for the Breakdown tab — all 4 totals for the selected time range.
struct BreakdownSummary {
    let totalVolume: Double   // sum(effectiveWeight × reps)
    let totalSets: Int        // count of eligible sets
    let totalReps: Int        // sum(reps)
    let totalWorkouts: Int    // count of distinct workoutIds
}

struct WorkoutsTimeSeriesPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String?
    let workoutId: UUID?  // Only populated in "Per Workout" mode
}

struct ExerciseProgressSeries: Identifiable {
    let id: UUID          // exerciseId
    let name: String
    let color: Color
    let points: [ExerciseProgressPoint]
}

struct ExerciseProgressPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let workoutId: UUID?
    /// Top weight from the best set (for display under chart data point).
    let topWeight: Double?
    /// Reps from the best set (for display under chart data point).
    let topReps: Int?
    /// Formatter-backed detail label for the representative top set.
    let detailLabel: String?

    init(
        date: Date,
        value: Double,
        workoutId: UUID?,
        topWeight: Double? = nil,
        topReps: Int? = nil,
        detailLabel: String? = nil
    ) {
        self.date = date
        self.value = value
        self.workoutId = workoutId
        self.topWeight = topWeight
        self.topReps = topReps
        self.detailLabel = detailLabel
    }
}

struct TrendLineData {
    let slope: Double
    let intercept: Double
    let startPoint: (x: Double, y: Double)
    let endPoint: (x: Double, y: Double)
    let meanValue: Double

    var isPositive: Bool { slope > 0 }
    var isNegative: Bool { slope < 0 }

    /// Slope as percentage change per period relative to the mean
    var percentagePerPeriod: Double {
        guard meanValue > 0 else { return 0 }
        return (slope / meanValue) * 100
    }

    /// Formatted as "↓ 25%/period" style
    var formattedSlope: String {
        let pct = abs(percentagePerPeriod)
        if pct < 0.1 { return "~0%" }
        if pct < 10 {
            return String(format: "%.1f%%", pct)
        }
        return String(format: "%.0f%%", pct)
    }
}
