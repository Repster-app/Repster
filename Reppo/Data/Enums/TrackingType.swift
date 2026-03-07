import Foundation

enum TrackingType: String, Codable, CaseIterable {
    case weightReps
    case duration
    case weightDistance
    case weightRepsDuration
    case custom

    var displayName: String {
        switch self {
        case .weightReps:         return "Weight & Reps"
        case .duration:           return "Duration"
        case .weightDistance:     return "Weight & Distance"
        case .weightRepsDuration: return "Weight, Reps & Duration"
        case .custom:             return "Custom"
        }
    }
}
