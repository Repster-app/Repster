import XCTest
import SwiftData
@testable import Reppo

final class SetServiceTests: XCTestCase {

    func testDeleteRemovesCapturedFatigueData() async throws {
        let context = try makeContext()
        let records = try await seedTrackedCompletedSet(in: context, order: 1)

        try await context.setService.delete(records.set)

        let learningData = try fetchLearningData(from: context.modelContainer)
        XCTAssertTrue(learningData.observations.isEmpty)
        XCTAssertTrue(learningData.audits.isEmpty)
    }

    func testUncompleteRemovesCapturedFatigueData() async throws {
        let context = try makeContext()
        let records = try await seedTrackedCompletedSet(in: context, order: 1)

        _ = try await context.setService.uncomplete(records.set)

        let persistedSet = try await context.setRepo.fetch(byId: records.set.id)
        let learningData = try fetchLearningData(from: context.modelContainer)
        XCTAssertEqual(persistedSet?.completed, false)
        XCTAssertTrue(learningData.observations.isEmpty)
        XCTAssertTrue(learningData.audits.isEmpty)
    }

    func testEditCompletedSetTypeChangeInvalidatesCapturedFatigueData() async throws {
        let context = try makeContext()
        let records = try await seedTrackedCompletedSet(in: context, order: 1)

        records.set.setType = .warmup

        _ = try await context.setService.edit(records.set)

        let learningData = try fetchLearningData(from: context.modelContainer)
        XCTAssertTrue(learningData.observations.isEmpty)
        XCTAssertTrue(learningData.audits.isEmpty)
    }

    func testEditCompletedSetPerformanceFieldChangeInvalidatesCapturedFatigueData() async throws {
        let context = try makeContext()
        let records = try await seedTrackedCompletedSet(in: context, order: 1)

        records.set.reps = 7
        records.set.restDurationSeconds = 180

        _ = try await context.setService.edit(records.set)

        let learningData = try fetchLearningData(from: context.modelContainer)
        XCTAssertTrue(learningData.observations.isEmpty)
        XCTAssertTrue(learningData.audits.isEmpty)
    }

    func testEditCompletedSetNoteOnlyPreservesCapturedFatigueData() async throws {
        let context = try makeContext()
        let records = try await seedTrackedCompletedSet(in: context, order: 1)

        records.set.notes = "Still the same set"

        _ = try await context.setService.edit(records.set)

        let learningData = try fetchLearningData(from: context.modelContainer)
        XCTAssertEqual(learningData.observations.map(\.setId), [records.set.id])
        XCTAssertEqual(learningData.audits.map(\.setId), [records.set.id])
    }

    func testEditCompletedSetReorderOnlyPreservesCapturedFatigueData() async throws {
        let context = try makeContext()
        let records = try await seedTrackedCompletedSet(in: context, order: 1)

        records.set.orderInWorkout = 4
        records.set.orderInExercise = 4

        _ = try await context.setService.edit(records.set)

        let learningData = try fetchLearningData(from: context.modelContainer)
        XCTAssertEqual(learningData.observations.map(\.setId), [records.set.id])
        XCTAssertEqual(learningData.audits.map(\.setId), [records.set.id])
    }

    func testExportBackupKeepsOnlyLearningDataForUntouchedTrackedSets() async throws {
        let context = try makeContext()
        let uncompleted = try await seedTrackedCompletedSet(in: context, order: 1)
        let typeChanged = try await seedTrackedCompletedSet(in: context, order: 2)
        let deleted = try await seedTrackedCompletedSet(in: context, order: 3)
        let untouched = try await seedTrackedCompletedSet(in: context, order: 4)

        _ = try await context.setService.uncomplete(uncompleted.set)

        typeChanged.set.setType = .warmup
        _ = try await context.setService.edit(typeChanged.set)

        try await context.setService.delete(deleted.set)

        let exportedData = try await context.backupService.exportBackup()
        let archive = try decodeBackupArchive(exportedData)

        XCTAssertEqual(archive.fatigueObservations?.map(\.setId) ?? [], [untouched.set.id])
        XCTAssertEqual(archive.fatigueLearningAudits?.map(\.setId) ?? [], [untouched.set.id])
    }

    func testExportBackupPreservesUnilateralFields() async throws {
        let context = try makeContext()
        let exercise = Exercise(
            name: "Split Squat",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            primaryMuscle: "quads",
            unilateral: true
        )
        let workoutDate = makeDate(2026, 3, 22, 11, 30)
        let workout = Workout(
            date: workoutDate,
            title: "Unilateral Session",
            startTime: workoutDate,
            endTime: workoutDate.addingTimeInterval(1_800),
            duration: 1_800,
            status: .completed
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            completedAt: workoutDate.addingTimeInterval(240),
            weight: 20,
            leftReps: 10,
            rightReps: 8,
            leftRIR: 2,
            rightRIR: 3,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        set.syncDerivedPerformanceFields(for: exercise)

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        _ = try await context.setService.save(set)

        let archive = try decodeBackupArchive(try await context.backupService.exportBackup())
        let archivedSet = try XCTUnwrap(archive.sets.first(where: { $0.id == set.id }))

        XCTAssertEqual(archivedSet.leftReps, 10)
        XCTAssertEqual(archivedSet.rightReps, 8)
        XCTAssertEqual(archivedSet.leftRIR, 2)
        XCTAssertEqual(archivedSet.rightRIR, 3)
        XCTAssertEqual(archivedSet.reps, 10)
    }

    private func makeContext() throws -> SetServiceTestContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self,
            Workout.self,
            WorkoutSet.self,
            ExerciseStats.self,
            PerformanceRecord.self,
            BodyweightEntry.self,
            HealthProfile.self,
            FatigueObservation.self,
            FatigueLearningSetAudit.self,
            configurations: configuration
        )

        let exerciseRepo = ExerciseRepository(modelContainer: container)
        let workoutRepo = WorkoutRepository(modelContainer: container)
        let setRepo = SetRepository(modelContainer: container)
        let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
        let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
        let bodyweightRepo = BodyweightEntryRepository(modelContainer: container)
        let healthProfileRepo = HealthProfileRepository(modelContainer: container)
        let fatigueObservationRepo = FatigueObservationRepository(modelContainer: container)
        let fatigueLearningAuditRepo = FatigueLearningSetAuditRepository(modelContainer: container)

        let statsService = StatsService(
            exerciseStatsRepository: exerciseStatsRepo,
            setRepository: setRepo,
            exerciseRepository: exerciseRepo,
            healthProfileRepository: healthProfileRepo,
            performanceRecordRepository: performanceRecordRepo
        )
        let prService = PRService(
            performanceRecordRepository: performanceRecordRepo,
            setRepository: setRepo,
            healthProfileRepository: healthProfileRepo,
            exerciseRepository: exerciseRepo
        )
        let fatigueLearningService = FatigueLearningService(
            observationRepo: fatigueObservationRepo,
            exerciseRepo: exerciseRepo,
            healthProfileRepo: healthProfileRepo,
            auditRepo: fatigueLearningAuditRepo
        )
        let setService = SetService(
            setRepository: setRepo,
            exerciseRepository: exerciseRepo,
            bodyweightEntryRepository: bodyweightRepo,
            healthProfileRepository: healthProfileRepo,
            prService: prService,
            statsService: statsService,
            fatigueLearningService: fatigueLearningService
        )
        let backupService = WorkoutHistoryBackupService(
            workoutRepo: workoutRepo,
            exerciseRepo: exerciseRepo,
            setRepo: setRepo,
            fatigueObservationRepo: fatigueObservationRepo,
            fatigueLearningAuditRepo: fatigueLearningAuditRepo,
            statsService: statsService,
            prService: prService,
            modelContainer: container
        )

        return SetServiceTestContext(
            modelContainer: container,
            setService: setService,
            backupService: backupService,
            exerciseRepo: exerciseRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo
        )
    }

    private func seedTrackedCompletedSet(
        in context: SetServiceTestContext,
        order: Int
    ) async throws -> SeededTrackedSet {
        let exercise = Exercise(
            name: "Bench \(order)",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        let workoutDate = makeDate(2026, 3, 22, 10, order)
        let workout = Workout(
            date: workoutDate,
            title: "Session \(order)",
            startTime: workoutDate,
            endTime: workoutDate.addingTimeInterval(3_600),
            duration: 3_600,
            status: .completed
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            completedAt: workoutDate.addingTimeInterval(300),
            weight: 100,
            reps: 5,
            rir: 1,
            setType: .working,
            orderInWorkout: order,
            orderInExercise: order,
            completed: true,
            restDurationSeconds: 150
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        _ = try await context.setService.save(set)

        let learningContext = ModelContext(context.modelContainer)
        let learningRecords = try insertLearningRecords(
            into: learningContext,
            exerciseId: exercise.id,
            workoutId: workout.id,
            setId: set.id,
            createdAt: workoutDate.addingTimeInterval(600)
        )
        try learningContext.save()

        return SeededTrackedSet(
            exercise: exercise,
            workout: workout,
            set: set,
            observation: learningRecords.observation,
            audit: learningRecords.audit
        )
    }

    private func fetchLearningData(
        from modelContainer: ModelContainer
    ) throws -> (observations: [FatigueObservation], audits: [FatigueLearningSetAudit]) {
        let context = ModelContext(modelContainer)
        let observations = try context.fetch(FetchDescriptor<FatigueObservation>())
            .sorted { $0.createdAt < $1.createdAt }
        let audits = try context.fetch(FetchDescriptor<FatigueLearningSetAudit>())
            .sorted { $0.createdAt < $1.createdAt }
        return (observations, audits)
    }

    private func decodeBackupArchive(_ data: Data) throws -> WorkoutHistoryArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkoutHistoryArchive.self, from: data)
    }

    private func insertLearningRecords(
        into context: ModelContext,
        exerciseId: UUID,
        workoutId: UUID,
        setId: UUID,
        createdAt: Date
    ) throws -> (observation: FatigueObservation, audit: FatigueLearningSetAudit) {
        let observation = FatigueObservation(
            exerciseId: exerciseId,
            workoutId: workoutId,
            setId: setId,
            setIndex: 1,
            predictedEffectiveE1RM: 120,
            actualE1RM: 126,
            normalizedError: -0.04,
            baseE1RM: 130,
            prescribedWeight: 77.5,
            actualWeight: 80,
            actualReps: 8,
            actualRIR: 0,
            restDurationSeconds: 150,
            createdAt: createdAt
        )
        let audit = FatigueLearningSetAudit(
            workoutId: workoutId,
            exerciseId: exerciseId,
            setId: setId,
            visibleSetNumber: 2,
            setType: .working,
            status: .used,
            predictedEffectiveE1RM: 120,
            baseE1RM: 130,
            prescribedWeight: 77.5,
            actualWeight: 80,
            actualReps: 8,
            actualRIR: 0,
            deviationFraction: 0.0323,
            normalizedError: -0.04,
            createdAt: createdAt
        )
        context.insert(observation)
        context.insert(audit)
        return (observation, audit)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}

private struct SetServiceTestContext {
    let modelContainer: ModelContainer
    let setService: SetService
    let backupService: WorkoutHistoryBackupService
    let exerciseRepo: ExerciseRepository
    let workoutRepo: WorkoutRepository
    let setRepo: SetRepository
}

private struct SeededTrackedSet {
    let exercise: Exercise
    let workout: Workout
    let set: WorkoutSet
    let observation: FatigueObservation
    let audit: FatigueLearningSetAudit
}
