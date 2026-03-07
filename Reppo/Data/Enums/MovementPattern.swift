import Foundation

enum MovementPattern: String, Codable, CaseIterable {
    case hinge
    case squat
    case press
    case pull
    case carry
    case rotation
    case other

    var displayName: String {
        switch self {
        case .hinge:    return "Hinge"
        case .squat:    return "Squat"
        case .press:    return "Press"
        case .pull:     return "Pull"
        case .carry:    return "Carry"
        case .rotation: return "Rotation"
        case .other:    return "Other"
        }
    }
}
