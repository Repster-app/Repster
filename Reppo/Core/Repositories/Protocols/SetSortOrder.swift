import Foundation

/// Sort order options for set queries.
/// Used by `SetRepositoryProtocol.fetchSets(for:reps:orderedBy:)`.
enum SetSortOrder: Sendable {
    case effectiveWeightDesc
    case dateAsc
    case dateDesc
}
