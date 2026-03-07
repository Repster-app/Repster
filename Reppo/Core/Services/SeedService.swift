import Foundation
import SwiftData

// NOTE: Intentional direct ModelContext access for one-time initialization.
// Normal data access MUST go through repositories per constitution.
// SeedService runs once on first launch and never again.
enum SeedService {
    /// Seeds the exercise library if the database is empty.
    /// Call once during app initialization.
    static func seedIfNeeded(modelContext: ModelContext) {
        // FR-003: Only seed when Exercise table is empty
        let descriptor = FetchDescriptor<Exercise>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0

        guard count == 0 else { return }

        // Load DTOs from bundle
        let dtos: [SeedExerciseDTO]
        do {
            dtos = try SeedDataLoader.loadExercises()
        } catch {
            print("[SeedService] Failed to load seed data: \(error)")
            return
        }

        // Map and insert each exercise
        var inserted = 0
        for dto in dtos {
            do {
                let exercise = try dto.toExercise()
                modelContext.insert(exercise)
                inserted += 1
            } catch {
                // FR-008: Skip invalid entries, log warning
                print("[SeedService] Skipping exercise '\(dto.name)': \(error)")
            }
        }

        // Save all at once (batch insert for performance)
        do {
            try modelContext.save()
            print("[SeedService] Seeded \(inserted) exercises")
        } catch {
            print("[SeedService] Failed to save seed data: \(error)")
        }
    }
}
