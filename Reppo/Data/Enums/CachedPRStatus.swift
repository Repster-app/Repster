import Foundation

enum CachedPRStatus: String, Codable, CaseIterable {
    /// PR owner AND on the suffix-max capability frontier → shows ★ badge.
    case current
    /// PR owner but dominated by a higher-rep PR at equal or greater weight → no badge.
    case dominated
    /// Ties the current PR (exact weight match at same reps) → shows = badge.
    case matched
    /// Was a PR owner, now beaten by a better set → no badge.
    case previous
}

extension CachedPRStatus {
    /// Whether this status indicates the set owns a PerformanceRecord.
    /// Used by the PR pipeline to identify sets that need recomputation on edit/delete.
    var isPROwner: Bool {
        self == .current || self == .dominated
    }
}
