// PRFrontier.swift
// Shared suffix-max "capability frontier" filter for rep-max PRs.
// Spec: specdoc S7.4, FR-008

import Foundation

/// The capability frontier over an exercise's rep-max records.
///
/// A rep-max record only says something new about capability if no higher-rep
/// record was hit at the same or greater weight — 60 kg x 7 adds nothing once
/// 60 kg x 8 is on the board. Walking rep counts from high to low and keeping
/// only the entries that beat the running max weight leaves exactly those
/// records; the rest are dominated and stay hidden across the app.
enum PRFrontier {

    /// Rep counts whose records sit on the capability frontier.
    ///
    /// Expects at most one entry per rep count — the rep-max record invariant.
    /// Weights are compared as integer grams, never as raw floats (specdoc S8.3).
    static func frontierReps(_ entries: [(reps: Int, value: Double)]) -> Set<Int> {
        var maxWeightSeenGrams = 0
        var frontier = Set<Int>()

        for entry in entries.sorted(by: { $0.reps > $1.reps }) {
            let valueGrams = UnitConversion.toGrams(entry.value)
            if valueGrams > maxWeightSeenGrams {
                frontier.insert(entry.reps)
                maxWeightSeenGrams = valueGrams
            }
            // Else: dominated by a higher-rep entry — off the frontier
        }

        return frontier
    }
}
