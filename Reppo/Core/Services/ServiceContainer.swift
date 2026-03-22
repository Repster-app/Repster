// ServiceContainer.swift
// DI container for service layer
// Spec: FR-011 (PRService wiring), FR-007/008/009 (StatsService), FR-001-006 (SetService)
// Source: AGENT_RULES S6

import Foundation

/// Lightweight container holding all service actors.
/// Created once at app launch after RepositoryContainer, passed to views via SwiftUI environment.
/// Services compose repositories — ServiceContainer takes RepositoryContainer in init.
///
/// Initialization order: StatsService → PRService → BodyweightService → FatigueLearningService → SetService → WorkoutService → ExerciseService
/// (SetService, WorkoutService, and ExerciseService depend on FatigueLearningService)
@Observable
final class ServiceContainer {
    let prService: any PRServiceProtocol
    let statsService: any StatsServiceProtocol
    let setService: any SetServiceProtocol
    let workoutService: any WorkoutServiceProtocol
    let exerciseService: any ExerciseServiceProtocol
    let bodyweightService: any BodyweightServiceProtocol
    let chartDataService: any ChartDataServiceProtocol
    let settingsService: any SettingsServiceProtocol
    let importService: any ImportServiceProtocol
    let workoutHistoryBackupService: any WorkoutHistoryBackupServiceProtocol
    let templateService: any TemplateServiceProtocol
    let loadPrescriptionService: any LoadPrescriptionServiceProtocol
    let fatigueLearningService: FatigueLearningService
    let healthProfileRepo: any HealthProfileRepositoryProtocol

    init(repositoryContainer: RepositoryContainer) {
        // 1. StatsService — depends on repos only
        let statsService = StatsService(
            exerciseStatsRepository: repositoryContainer.exerciseStatsRepository,
            setRepository: repositoryContainer.setRepository,
            exerciseRepository: repositoryContainer.exerciseRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository,
            performanceRecordRepository: repositoryContainer.performanceRecordRepository
        )

        // 2. PRService — depends on repos only
        let prService = PRService(
            performanceRecordRepository: repositoryContainer.performanceRecordRepository,
            setRepository: repositoryContainer.setRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository,
            exerciseRepository: repositoryContainer.exerciseRepository
        )

        // 3. ChartDataService — depends on repos only
        let chartDataService = ChartDataService(
            setRepository: repositoryContainer.setRepository,
            workoutRepository: repositoryContainer.workoutRepository,
            exerciseRepository: repositoryContainer.exerciseRepository,
            exerciseStatsRepository: repositoryContainer.exerciseStatsRepository,
            performanceRecordRepository: repositoryContainer.performanceRecordRepository
        )

        // 4. BodyweightService — depends on repos only
        let bodyweightService = BodyweightService(
            bodyweightEntryRepository: repositoryContainer.bodyweightEntryRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository
        )

        // 5. FatigueLearningService — depends on repos only
        let fatigueLearningService = FatigueLearningService(
            observationRepo: repositoryContainer.fatigueObservationRepository,
            exerciseRepo: repositoryContainer.exerciseRepository,
            healthProfileRepo: repositoryContainer.healthProfileRepository,
            auditRepo: repositoryContainer.fatigueLearningSetAuditRepository
        )

        // 6. SetService — depends on repos + PRService + StatsService + FatigueLearningService
        let setService = SetService(
            setRepository: repositoryContainer.setRepository,
            exerciseRepository: repositoryContainer.exerciseRepository,
            bodyweightEntryRepository: repositoryContainer.bodyweightEntryRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository,
            prService: prService,
            statsService: statsService,
            fatigueLearningService: fatigueLearningService
        )

        // 7. WorkoutService — depends on repos + PRService + StatsService + FatigueLearningService
        let workoutService = WorkoutService(
            workoutRepository: repositoryContainer.workoutRepository,
            setRepository: repositoryContainer.setRepository,
            prService: prService,
            statsService: statsService,
            fatigueLearningService: fatigueLearningService
        )

        // 8. SettingsService — depends on HealthProfileRepository + PRService + StatsService
        let settingsService = SettingsService(
            healthProfileRepository: repositoryContainer.healthProfileRepository,
            prService: prService,
            statsService: statsService,
            modelContainer: repositoryContainer.modelContainer
        )

        // 9. ExerciseService — depends on repos + PRService + StatsService + FatigueLearningService
        let exerciseService = ExerciseService(
            exerciseRepository: repositoryContainer.exerciseRepository,
            setRepository: repositoryContainer.setRepository,
            exerciseStatsRepository: repositoryContainer.exerciseStatsRepository,
            performanceRecordRepository: repositoryContainer.performanceRecordRepository,
            prService: prService,
            statsService: statsService,
            fatigueLearningService: fatigueLearningService
        )

        // 10. ImportService — depends on repos + PRService + StatsService + ModelContainer
        let importService = ImportService(
            exerciseRepo: repositoryContainer.exerciseRepository,
            workoutRepo: repositoryContainer.workoutRepository,
            bodyweightRepo: repositoryContainer.bodyweightEntryRepository,
            healthProfileRepo: repositoryContainer.healthProfileRepository,
            prService: prService,
            statsService: statsService,
            modelContainer: repositoryContainer.modelContainer
        )

        // 11. WorkoutHistoryBackupService — archive export + restore
        let workoutHistoryBackupService = WorkoutHistoryBackupService(
            workoutRepo: repositoryContainer.workoutRepository,
            exerciseRepo: repositoryContainer.exerciseRepository,
            setRepo: repositoryContainer.setRepository,
            fatigueObservationRepo: repositoryContainer.fatigueObservationRepository,
            fatigueLearningAuditRepo: repositoryContainer.fatigueLearningSetAuditRepository,
            statsService: statsService,
            prService: prService,
            modelContainer: repositoryContainer.modelContainer
        )

        // 12. TemplateService — depends on repos only
        let templateService = TemplateService(
            templateRepository: repositoryContainer.templateRepository,
            workoutRepository: repositoryContainer.workoutRepository,
            setRepository: repositoryContainer.setRepository,
            exerciseRepository: repositoryContainer.exerciseRepository,
            exerciseStatsRepository: repositoryContainer.exerciseStatsRepository
        )

        // 13. LoadPrescriptionService — depends on repos only
        let loadPrescriptionService = LoadPrescriptionService(
            setRepository: repositoryContainer.setRepository,
            exerciseRepository: repositoryContainer.exerciseRepository,
            performanceRecordRepository: repositoryContainer.performanceRecordRepository,
            healthProfileRepository: repositoryContainer.healthProfileRepository
        )

        self.prService = prService
        self.statsService = statsService
        self.setService = setService
        self.workoutService = workoutService
        self.exerciseService = exerciseService
        self.bodyweightService = bodyweightService
        self.chartDataService = chartDataService
        self.settingsService = settingsService
        self.importService = importService
        self.workoutHistoryBackupService = workoutHistoryBackupService
        self.templateService = templateService
        self.loadPrescriptionService = loadPrescriptionService
        self.fatigueLearningService = fatigueLearningService
        self.healthProfileRepo = repositoryContainer.healthProfileRepository
    }
}
