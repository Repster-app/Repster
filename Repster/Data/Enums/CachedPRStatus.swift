import Foundation

enum CachedPRStatus: String, Codable, CaseIterable {
    /// PR owner AND on the suffix-max capability frontier → shows ★ badge.
    case current
    /// PR owner but dominated by a higher-rep PR at equal or greater weight → no badge.
    case dominated
    /// Ties a visible frontier PR (exact weight match at same reps) → shows = badge.
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

    /// Returns the effective display status for a set, suppressing `.matched` when
    /// another set in the same workout dominates it (same/higher weight, more reps).
    static func effectiveStatus(for set: WorkoutSet, among siblings: [WorkoutSet]) -> CachedPRStatus? {
        effectiveStatus(
            status: set.prStatus,
            id: set.id,
            weight: set.weight,
            reps: set.reps,
            siblings: siblings.map { (id: $0.id, weight: $0.weight, reps: $0.reps) }
        )
    }

    /// Snapshot overload — same rule, on value types that carry no `ModelContext`.
    static func effectiveStatus(for set: ChartSetData, among siblings: [ChartSetData]) -> CachedPRStatus? {
        effectiveStatus(
            status: set.prStatus,
            id: set.id,
            weight: set.weight,
            reps: set.reps,
            siblings: siblings.map { (id: $0.id, weight: $0.weight, reps: $0.reps) }
        )
    }

    private static func effectiveStatus(
        status: CachedPRStatus?,
        id: UUID,
        weight: Double?,
        reps: Int?,
        siblings: [(id: UUID, weight: Double?, reps: Int?)]
    ) -> CachedPRStatus? {
        guard status == .matched,
              let weight,
              let reps else {
            return status
        }
        let dominated = siblings.contains { sibling in
            sibling.id != id &&
            (sibling.weight ?? 0) >= weight &&
            (sibling.reps ?? 0) > reps
        }
        return dominated ? nil : .matched
    }
}
