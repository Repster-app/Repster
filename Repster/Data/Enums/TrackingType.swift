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
}
