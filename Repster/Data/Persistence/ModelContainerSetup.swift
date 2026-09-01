import Foundation
import SwiftData

enum ModelContainerSetup {
    static func createContainer() throws -> ModelContainer {
        let schema = Schema([
            WorkoutSet.self,
            Workout.self,
            Exercise.self,
            ExerciseStats.self,
            PerformanceRecord.self,
            BodyweightEntry.self,
            HealthProfile.self,
            Program.self,
            ProgramExercise.self,
            PlannedWorkout.self,
            PlannedSet.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateSet.self,
            FatigueObservation.self,
            FatigueLearningSetAudit.self,
            InsightRecord.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        // Deliberately NO `migrationPlan:`.
        //
        // It was wired here on 2026-09-01 and reverted the same day. `SchemaV1.models` returns the
        // LIVE model types, so it is not a frozen v1 schema — it is "whatever the models are now,
        // labelled 1.0.0". Passing it tells SwiftData that 1.0.0 is the only schema that has ever
        // existed and that it looks like the current types, with no stage to reach it from an older
        // store. Implicit lightweight migration, which is what has always run here, handles added
        // optional properties correctly and needs none of that.
        //
        // A real plan needs a genuinely frozen SchemaV1 — model definitions copied as they were at
        // v1, not references to the live types — plus a SchemaV2 and a stage between them. Until that
        // exists, wiring the plan is strictly worse than not wiring it.
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
