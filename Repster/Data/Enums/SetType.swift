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

enum FatigueLearningAuditStatus: String, Codable, CaseIterable, Sendable {
    case used
    case warmupNotTracked
    case baselineFirstWorkingSet
    case suggestionUnavailable
    case missingRIR
    case invalidPerformance
    case weightDeviationOver20Percent

    var displayTitle: String {
        switch self {
        case .used:
            return "Used for learning"
        case .warmupNotTracked:
            return "Warm-up not tracked"
        case .baselineFirstWorkingSet:
            return "Baseline set"
        case .suggestionUnavailable:
            return "Suggestion unavailable"
        case .missingRIR:
            return "Missing RIR"
        case .invalidPerformance:
            return "Invalid performance data"
        case .weightDeviationOver20Percent:
            return "Weight changed too much"
        }
    }

    var detail: String {
        switch self {
        case .used:
            return "This set contributed to fatigue learning."
        case .warmupNotTracked:
            return "Warm-up sets never contribute to fatigue learning."
        case .baselineFirstWorkingSet:
            return "The first working set establishes a fatigue-free baseline."
        case .suggestionUnavailable:
            return "No Smart Suggestion snapshot was available for comparison."
        case .missingRIR:
            return "RIR is required to estimate actual performance."
        case .invalidPerformance:
            return "Valid completed reps and weight are required."
        case .weightDeviationOver20Percent:
            return "The completed weight deviated by more than 20% from the suggestion."
        }
    }
}
