import Foundation

enum SetType: String, Codable, CaseIterable {
    case warmup
    case working
    case partial
    case dropset
    case restpause
    case cluster
    case myo
    case amrap
    case backoff
    case failure
    case tempo
    case isometric
    case eccentric

    /// Human-readable display name for UI labels and context menus.
    var displayName: String {
        switch self {
        case .warmup:    return "Warm-up"
        case .working:   return "Working"
        case .partial:   return "Partial"
        case .dropset:   return "Drop Set"
        case .restpause: return "Rest-Pause"
        case .cluster:   return "Cluster"
        case .myo:       return "Myo-Rep"
        case .amrap:     return "AMRAP"
        case .backoff:   return "Back-off"
        case .failure:   return "Failure"
        case .tempo:     return "Tempo"
        case .isometric: return "Isometric"
        case .eccentric: return "Eccentric"
        }
    }
}
