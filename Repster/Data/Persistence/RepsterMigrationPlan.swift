import SwiftData

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
        // No stages yet. Every change so far has been an added optional property, which SwiftData
        // handles as a lightweight migration — `WorkoutTemplate.folder` is the most recent.
        // A rename, a type change or a required property needs a SchemaV2 and a stage here.
        []
    }
}
