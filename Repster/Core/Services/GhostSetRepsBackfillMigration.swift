import Foundation
import SwiftData

// One-shot migration to recover sets persisted with reps=nil because the user tapped
// the checkmark while the reps field was empty (target shown only as a placeholder).
// For sets with a single-value rep target (overrideTargetRepMin == overrideTargetRepMax),
// restore reps from that target. Range/no-target ghost rows are left alone — there is
// no defensible default rep count and the user can fix them via the edit-workout flow.
//
// NOTE: Intentional direct ModelContext access for one-time recovery, matching the
// pattern in SeedService. Guarded by a UserDefaults flag so it runs at most once.
enum GhostSetRepsBackfillMigration {
    private static let didRunKey = "didRunGhostSetRepsBackfill_v1"

    static func runIfNeeded(modelContext: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didRunKey) else { return }

        let sets: [WorkoutSet]
        do {
            sets = try modelContext.fetch(FetchDescriptor<WorkoutSet>())
        } catch {
            dbg("[GhostSetRepsBackfillMigration] Failed to fetch sets: \(error)")
            return
        }

        var patched = 0
        for set in sets {
            guard set.completed,
                  set.reps == nil,
                  (set.weight ?? 0) > 0,
                  (set.durationSeconds ?? 0) == 0,
                  (set.distanceMeters ?? 0) == 0
            else { continue }

            guard let lo = set.overrideTargetRepMin,
                  let hi = set.overrideTargetRepMax,
                  lo == hi, lo > 0
            else { continue }

            set.reps = lo
            set.updatedAt = Date()
            patched += 1
        }

        if patched > 0 {
            do {
                try modelContext.save()
                dbg("[GhostSetRepsBackfillMigration] Restored reps on \(patched) sets")
            } catch {
                dbg("[GhostSetRepsBackfillMigration] Failed to save: \(error)")
                return
            }
        }

        defaults.set(true, forKey: didRunKey)
    }
}
