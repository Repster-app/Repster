import Foundation

enum TrackingType: String, Codable, CaseIterable {
    case weightReps
    case duration
    case durationDistance
    case weightDistance
    case weightDuration
    case weightRepsDuration
    case custom

    var displayName: String {
        switch self {
        case .weightReps:         return "Weight & Reps"
        case .duration:           return "Duration"
        case .durationDistance:   return "Distance & Duration"
        case .weightDistance:     return "Weight & Distance"
        case .weightDuration:    return "Weight & Duration"
        case .weightRepsDuration: return "Weight, Reps & Duration"
        case .custom:             return "Custom"
        }
    }

    var supportsRepPRs: Bool {
        self == .weightReps
    }

    /// Whether per-side logging is offered for exercises with this tracking type.
    ///
    /// Lives here rather than on `Exercise` because it is derived purely from the
    /// tracking type, and both `Exercise` and `ChartExerciseData` need it — two
    /// copies of the rule would be free to drift.
    var supportsUnilateralLogging: Bool {
        self == .weightReps || self == .weightRepsDuration
    }
}
