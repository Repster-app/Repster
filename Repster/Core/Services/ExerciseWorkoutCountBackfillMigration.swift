import Foundation
import SwiftData

// One-shot repair for ExerciseStats.totalWorkouts — the "N workouts" counter on the
// exercise list and detail screens.
//
// Until this shipped, the incremental update in StatsService decided "first set of this
// exercise in this workout" by counting rows, while only stats-eligible sets reached that
// code. Any row that contributes nothing — the empty placeholder set created with the
// exercise, a warmup logged before the first working set, a partial — therefore blocked
// the increment for good, and the workout was never counted. Deletes had the mirror
// problem: they only decremented once every row was gone, so warmup leftovers kept a
// workout on the books.
//
// Recomputes the counter from the sets themselves for every exercise that already has a
// stats row. Other fields are left alone — a full recalculation is available in Settings.
//
// NOTE: Intentional direct ModelContext access for one-time recovery, matching the
// pattern in SeedService and GhostSetRepsBackfillMigration. Guarded by a UserDefaults
// flag so it runs at most once.
enum ExerciseWorkoutCountBackfillMigration {
    private static let didRunKey = "didRunExerciseWorkoutCountBackfill_v1"

    static func runIfNeeded(modelContext: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didRunKey) else { return }

        let allStats: [ExerciseStats]
        let sets: [WorkoutSet]
        do {
            allStats = try modelContext.fetch(FetchDescriptor<ExerciseStats>())
            guard !allStats.isEmpty else {
                defaults.set(true, forKey: didRunKey)
                return
            }
            sets = try modelContext.fetch(FetchDescriptor<WorkoutSet>())
        } catch {
            dbg("[ExerciseWorkoutCountBackfillMigration] Failed to fetch: \(error)")
            return
        }

        var profileDescriptor = FetchDescriptor<HealthProfile>()
        profileDescriptor.fetchLimit = 1
        let includeWarmups = (try? modelContext.fetch(profileDescriptor).first)?
            .includeWarmupsInVolume ?? false

        // exerciseId -> workouts the exercise was actually performed in
        var performedWorkouts: [UUID: Set<UUID>] = [:]
        for set in sets {
            guard set.completed, set.hasData else { continue }
            if set.setType == .partial { continue }
            if set.setType == .warmup && !includeWarmups { continue }
            performedWorkouts[set.exerciseId, default: []].insert(set.workoutId)
        }

        var patched = 0
        for stats in allStats {
            let correctCount = performedWorkouts[stats.exerciseId]?.count ?? 0
            guard stats.totalWorkouts != correctCount else { continue }
            stats.totalWorkouts = correctCount
            stats.updatedAt = Date()
            patched += 1
        }

        if patched > 0 {
            do {
                try modelContext.save()
                dbg("[ExerciseWorkoutCountBackfillMigration] Corrected totalWorkouts on \(patched) exercises")
            } catch {
                dbg("[ExerciseWorkoutCountBackfillMigration] Failed to save: \(error)")
                return
            }
        }

        defaults.set(true, forKey: didRunKey)
    }
}
