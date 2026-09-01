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

        // The plan was declared but never passed, so it has never actually run. Wiring it now costs
        // nothing while every change is lightweight, and means the first stage that IS needed takes
        // effect instead of being silently ignored. See TEMPLATES_IMPLEMENTATION_PLAN.md G2.
        return try ModelContainer(
            for: schema,
            migrationPlan: RepsterMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
