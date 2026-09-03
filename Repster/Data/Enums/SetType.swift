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

// MARK: - Semantic predicates
//
// Ten call sites used to answer "does this set count?" with an inline comparison, and they
// did not agree: some used the denylist (everything but warm-up and partial), some used
// `== .working` exactly, so a drop set counted toward volume and PRs while vanishing from
// Copy Previous and the Home card. Nobody chose that. These predicates exist so each call
// site has to state which question it is asking.
//
// Background: DROP_SETS_SCOPING.md Decision 3, SUGGESTION_ENGINE_PROGRAM.md §R2.
extension SetType {

    /// Real work the lifter performed: counts toward volume, PRs, e1RM baselines and history.
    ///
    /// The denylist, named. Warm-ups are preparation, not work; partial-ROM reps are not
    /// comparable to full-ROM ones. Everything else happened and counts.
    var countsAsPerformedWork: Bool {
        self != .warmup && self != .partial
    }

    /// An ordinary straight set, with no annotation about how it was taken.
    ///
    /// For the places that genuinely mean "a normal set" — e.g. rest/rep pair analysis, where
    /// a drop set's near-zero rest is noise rather than signal.
    var isStraightWorkingSet: Bool {
        self == .working
    }

    /// Trustworthy evidence of *what this lifter can currently lift* — a point estimate.
    ///
    /// Deliberately narrower than ``countsAsPerformedWork``:
    /// - `amrap` / `failure` are the **best** evidence available and must stay in.
    /// - `dropset` / `backoff` are submaximal by definition.
    /// - `myo` / `restpause` / `cluster` are fragmented reps; e1RM formulas do not apply.
    /// - `tempo` / `isometric` / `eccentric` — a five-second isometric "rep" is not a rep.
    var isCapacityPointEstimate: Bool {
        switch self {
        case .working, .amrap, .failure:
            return true
        default:
            return false
        }
    }

    /// Evidence of what this lifter can *at least* lift — a lower bound, not a point estimate.
    ///
    /// Wider than ``isCapacityPointEstimate`` on purpose. A back-off set at RIR 5 is a poor
    /// estimate of capacity but a perfectly good floor: it happened, with reps to spare. Used
    /// by the suggestion floor, which may never price below a weight already completed with
    /// reserve.
    var isCapacityLowerBound: Bool {
        switch self {
        case .working, .backoff:
            return true
        default:
            return false
        }
    }

    /// The types a user may newly assign from the set-type picker.
    ///
    /// The enum keeps all 13 cases — raw values are persisted in SwiftData, written to the JSON
    /// archive and produced by both CSV importers, so removing one means a migration. Only the
    /// *offer* is narrowed, to the types that have a feature behind them. A set that already
    /// carries a hidden type keeps it, and the picker still shows it.
    static var userSelectable: [SetType] {
        [.warmup, .working, .dropset]
    }

    /// What a set-type picker should offer for a set that is currently `current`.
    ///
    /// The supported types, plus `current` when it is not one of them. Imported sets can carry
    /// a type the picker no longer offers — both CSV importers emit `failure` — and rendering
    /// such a set as "Working" would misreport stored data. The user can move off it, they just
    /// cannot newly assign it.
    static func pickerOptions(current: SetType) -> [SetType] {
        var types = userSelectable
        if !types.contains(current) {
            types.append(current)
        }
        return types
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
    case nonCapacitySetType

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
        case .nonCapacitySetType:
            return "Not a capacity set"
        }
    }

    /// The raw value written into a backup archive.
    ///
    /// Deliberately not always `rawValue`. Shipped builds decode this field as a typed enum, so a
    /// value they have never heard of fails their *entire* restore — a user would lose their whole
    /// history because a newer build had one extra diagnostic label. Cases added after 1.4 are
    /// therefore written as the nearest value 1.4 already knows.
    ///
    /// The local database keeps the true status; only the archived copy is conservative, and the
    /// cost is one diagnostics label on restored rows. Once no supported build predates a case,
    /// its mapping can be dropped.
    var archiveRawValue: String {
        switch self {
        case .nonCapacitySetType:
            // Added in 1.5. Closest thing 1.4 understands: the model made no comparison here.
            return FatigueLearningAuditStatus.suggestionUnavailable.rawValue
        default:
            return rawValue
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
        case .nonCapacitySetType:
            return "Drop sets and other submaximal or fragmented sets don't grade the model."
        }
    }
}
