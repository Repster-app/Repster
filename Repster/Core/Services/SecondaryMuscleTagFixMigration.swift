import Foundation
import SwiftData

// One-shot correction of three library exercises' secondary muscles, for the release that first
// shows them.
//
// The seed has carried secondary muscles since the library was written, but nothing displayed
// them before 1.6, so three wrong ones went unnoticed: Hip Adductor Machine listed Glutes rather
// than Adductors, and Farmer's Walk and Dead Hang left out Forearms. The seed file now has the
// right tags, but SeedService only seeds an empty store, so existing installs would keep the old
// ones without this.
//
// An exercise changes only while it still has its library name and exactly the original tags, so
// a renamed exercise, a custom one with other tags, or anything edited in the 1.6 editor is left
// alone.
//
// NOTE: Intentional direct ModelContext access for one-time recovery, matching the pattern in
// SeedService and AdminModeResetMigration. Guarded by a UserDefaults flag so it runs at most once,
// and never overrides a choice made after it ran.
enum SecondaryMuscleTagFixMigration {
    static let didRunKey = "didRunSecondaryMuscleTagFix_v1"

    struct Correction: Equatable {
        let name: String
        let original: [String]
        let corrected: [String]
    }

    /// A test holds the seed file to `corrected`, so the two can't drift apart.
    static let corrections: [Correction] = [
        Correction(name: "Hip Adductor Machine", original: ["glutes"], corrected: ["adductors"]),
        Correction(
            name: "Farmer's Walk",
            original: ["shoulders", "back"],
            corrected: ["forearms", "shoulders", "back"]
        ),
        Correction(name: "Dead Hang", original: ["shoulders"], corrected: ["forearms", "shoulders"])
    ]

    static func runIfNeeded(modelContext: ModelContext, userDefaults: UserDefaults = .standard) {
        guard !userDefaults.bool(forKey: didRunKey) else { return }

        let exercises: [Exercise]
        do {
            exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
        } catch {
            dbg("[SecondaryMuscleTagFixMigration] Failed to fetch exercises: \(error)")
            return
        }

        var patched = 0
        for exercise in exercises {
            guard let correction = correction(forName: exercise.name),
                  exercise.secondaryMuscles == correction.original else { continue }
            exercise.secondaryMuscles = correction.corrected
            exercise.updatedAt = Date()
            patched += 1
        }

        if patched > 0 {
            do {
                try modelContext.save()
                dbg("[SecondaryMuscleTagFixMigration] Corrected secondary muscles on \(patched) exercises")
            } catch {
                dbg("[SecondaryMuscleTagFixMigration] Failed to save: \(error)")
                return
            }
        }

        userDefaults.set(true, forKey: didRunKey)
    }

    private static func correction(forName name: String) -> Correction? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return corrections.first { $0.name.lowercased() == key }
    }
}
