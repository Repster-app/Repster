import SwiftData
import Foundation

/// Lightweight container holding all repository actors.
/// Created once at app launch, passed to views via SwiftUI environment.
@Observable
final class RepositoryContainer {
    let modelContainer: ModelContainer
    let setRepository: SetRepository
    let workoutRepository: WorkoutRepository
    let exerciseRepository: ExerciseRepository
    let exerciseStatsRepository: ExerciseStatsRepository
    let performanceRecordRepository: PerformanceRecordRepository
    let bodyweightEntryRepository: BodyweightEntryRepository
    let healthProfileRepository: HealthProfileRepository
    let programRepository: ProgramRepository
    let templateRepository: TemplateRepository
    let fatigueObservationRepository: FatigueObservationRepository
    let fatigueLearningSetAuditRepository: FatigueLearningSetAuditRepository

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.setRepository = SetRepository(modelContainer: modelContainer)
        self.workoutRepository = WorkoutRepository(modelContainer: modelContainer)
        self.exerciseRepository = ExerciseRepository(modelContainer: modelContainer)
        self.exerciseStatsRepository = ExerciseStatsRepository(modelContainer: modelContainer)
        self.performanceRecordRepository = PerformanceRecordRepository(modelContainer: modelContainer)
        self.bodyweightEntryRepository = BodyweightEntryRepository(modelContainer: modelContainer)
        self.healthProfileRepository = HealthProfileRepository(modelContainer: modelContainer)
        self.programRepository = ProgramRepository(modelContainer: modelContainer)
        self.templateRepository = TemplateRepository(modelContainer: modelContainer)
        self.fatigueObservationRepository = FatigueObservationRepository(modelContainer: modelContainer)
        self.fatigueLearningSetAuditRepository = FatigueLearningSetAuditRepository(modelContainer: modelContainer)
    }
}
