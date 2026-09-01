import SwiftData

// NOT WIRED INTO THE CONTAINER, and must not be until it is rebuilt properly. See the comment in
// ModelContainerSetup.swift.
//
// The flaw: `models` below returns the live model types, so this "v1" schema silently tracks every
// change made to those models. It describes the present, not version 1. A migration plan built on it
// tells SwiftData the store should already look like today's types, with no stage to get there.

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
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
            InsightRecord.self,
        ]
    }
}

enum RepsterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // Empty, and the plan is not passed to the container. Every change so far has been an added
        // optional property, which implicit lightweight migration handles.
        []
    }
}
