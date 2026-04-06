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

    func testUpdateInProgressTargetRepOverridePersistsWithoutPRsOrStats() async throws {
        let context = try makeContext()
        let workoutDate = makeDate(2026, 3, 22, 8, 0)
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        let workout = Workout(
            date: workoutDate,
            startTime: workoutDate,
            status: .inProgress
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false,
            targetRepMin: 8,
            targetRepMax: 12,
            targetRIR: 2
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)

        try await context.setService.updateInProgressTargetRepOverride(
            setId: set.id,
            min: 6,
            max: 8
        )

        let persistedSet = try await context.setRepo.fetch(byId: set.id)
        let performanceRecords = try await context.performanceRecordRepo.fetchAll(
            for: exercise.id,
            recordType: .repMax
        )
        let stats = try await context.statsService.fetchStats(for: exercise.id)

        XCTAssertEqual(persistedSet?.overrideTargetRepMin, 6)
        XCTAssertEqual(persistedSet?.overrideTargetRepMax, 8)
        XCTAssertEqual(persistedSet?.targetRepMin, 8)
        XCTAssertEqual(persistedSet?.targetRepMax, 12)
        XCTAssertTrue(performanceRecords.isEmpty)
        XCTAssertNil(stats)
    }

    func testBackupRoundTripPreservesTargetRepOverridesOnInProgressSet() async throws {
        let context = try makeContext()
        let workoutDate = makeDate(2026, 3, 22, 8, 30)
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        let workout = Workout(
            date: workoutDate,
            startTime: workoutDate,
            status: .inProgress
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false,
            targetRepMin: 8,
            targetRepMax: 12,
            overrideTargetRepMin: 6,
            overrideTargetRepMax: 8,
            targetRIR: 2
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)

        let exportedData = try await context.backupService.exportBackup()
        let archive = try decodeBackupArchive(exportedData)
        let archivedSet = try XCTUnwrap(archive.sets.first(where: { $0.id == set.id }))

        XCTAssertEqual(archivedSet.overrideTargetRepMin, 6)
        XCTAssertEqual(archivedSet.overrideTargetRepMax, 8)

        let restoredContext = try makeContext()
        _ = try await restoredContext.backupService.restoreBackup(data: exportedData)
        let restoredSet = try await restoredContext.setRepo.fetch(byId: set.id)

        XCTAssertEqual(restoredSet?.overrideTargetRepMin, 6)
        XCTAssertEqual(restoredSet?.overrideTargetRepMax, 8)
        XCTAssertEqual(restoredSet?.targetRepMin, 8)
        XCTAssertEqual(restoredSet?.targetRepMax, 12)
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

    func testSaveWeightRepsSetStillCreatesPRRecord() async throws {
        let context = try makeContext()
        let workoutDate = makeDate(2026, 3, 22, 9, 0)
        let records = try await insertExerciseAndWorkout(
            in: context,
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            date: workoutDate
        )
        let set = WorkoutSet(
            workoutId: records.workout.id,
            exerciseId: records.exercise.id,
            date: workoutDate,
            completedAt: workoutDate.addingTimeInterval(300),
            weight: 100,
            reps: 5,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )

        let result = try await context.setService.save(set)
        let performanceRecords = try await context.performanceRecordRepo.fetchAll(
            for: records.exercise.id,
            recordType: .repMax
        )
        let persistedSet = try await context.setRepo.fetch(byId: set.id)

        XCTAssertEqual(result.prResult.newStatus, .current)
        XCTAssertEqual(performanceRecords.count, 1)
        XCTAssertEqual(performanceRecords.first?.reps, 5)
        XCTAssertEqual(performanceRecords.first?.value ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(persistedSet?.cachedPRStatus, .current)
    }

    func testSaveWeightRepsSetInExcludedWorkoutDoesNotCreatePRRecordOrBadge() async throws {
        let context = try makeContext()
        let workoutDate = makeDate(2026, 3, 22, 9, 10)
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        let workout = Workout(
            date: workoutDate,
            title: "Hotel Gym",
            startTime: workoutDate,
            endTime: workoutDate.addingTimeInterval(1_800),
            duration: 1_800,
            status: .completed,
            excludeFromProgressionHistory: true
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            completedAt: workoutDate.addingTimeInterval(300),
            weight: 100,
            reps: 5,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)

        let result = try await context.setService.save(set)
        let performanceRecords = try await context.performanceRecordRepo.fetchAll(
            for: exercise.id,
            recordType: .repMax
        )
        let persistedSet = try await context.setRepo.fetch(byId: set.id)

        XCTAssertNil(result.prResult.newStatus)
        XCTAssertFalse(result.prResult.prRecordChanged)
        XCTAssertTrue(performanceRecords.isEmpty)
        XCTAssertNil(persistedSet?.cachedPRStatus)
    }

    func testExerciseScopedWorkoutExclusionStillAllowsOtherExercisesToCreatePRs() async throws {
        let context = try makeContext()
        let workoutDate = makeDate(2026, 3, 22, 9, 20)
        let excludedExercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        let allowedExercise = Exercise(
            name: "Barbell Row",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "back"
        )
        let workout = Workout(
            date: workoutDate,
            title: "Mixed Session",
            startTime: workoutDate,
            endTime: workoutDate.addingTimeInterval(1_800),
            duration: 1_800,
            status: .completed,
            excludedExerciseIdsFromProgressionHistory: [excludedExercise.id]
        )
        let excludedSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: excludedExercise.id,
            date: workoutDate,
            completedAt: workoutDate.addingTimeInterval(240),
            weight: 95,
            reps: 5,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        let allowedSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: allowedExercise.id,
            date: workoutDate,
            completedAt: workoutDate.addingTimeInterval(420),
            weight: 85,
            reps: 8,
            setType: .working,
            orderInWorkout: 2,
            orderInExercise: 1,
            completed: true
        )

        try await context.exerciseRepo.save(excludedExercise)
        try await context.exerciseRepo.save(allowedExercise)
        try await context.workoutRepo.save(workout)

        let excludedResult = try await context.setService.save(excludedSet)
        let allowedResult = try await context.setService.save(allowedSet)
        let excludedRecords = try await context.performanceRecordRepo.fetchAll(
            for: excludedExercise.id,
            recordType: .repMax
        )
        let allowedRecords = try await context.performanceRecordRepo.fetchAll(
            for: allowedExercise.id,
            recordType: .repMax
        )
        let persistedExcludedSet = try await context.setRepo.fetch(byId: excludedSet.id)
        let persistedAllowedSet = try await context.setRepo.fetch(byId: allowedSet.id)

        XCTAssertNil(excludedResult.prResult.newStatus)
        XCTAssertFalse(excludedResult.prResult.prRecordChanged)
        XCTAssertTrue(excludedRecords.isEmpty)
        XCTAssertNil(persistedExcludedSet?.cachedPRStatus)

        XCTAssertEqual(allowedResult.prResult.newStatus, .current)
        XCTAssertEqual(allowedRecords.count, 1)
        XCTAssertEqual(allowedRecords.first?.reps, 8)
        XCTAssertEqual(allowedRecords.first?.value ?? 0, 85, accuracy: 0.001)
        XCTAssertEqual(persistedAllowedSet?.cachedPRStatus, .current)
    }

    func testSaveWeightRepsDurationSetDoesNotCreatePRRecordOrBadge() async throws {
        let context = try makeContext()
        let workoutDate = makeDate(2026, 3, 22, 9, 15)
        let records = try await insertExerciseAndWorkout(
            in: context,
            name: "Tempo Row",
            equipmentType: .machinePin,
            trackingType: .weightRepsDuration,
            primaryMuscle: "back",
            date: workoutDate
        )
        let set = WorkoutSet(
            workoutId: records.workout.id,
            exerciseId: records.exercise.id,
            date: workoutDate,
            completedAt: workoutDate.addingTimeInterval(240),
            weight: 45,
            reps: 8,
            durationSeconds: 75,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )

        let result = try await context.setService.save(set)
        let performanceRecords = try await context.performanceRecordRepo.fetchAll(
            for: records.exercise.id,
            recordType: .repMax
        )
        let persistedSet = try await context.setRepo.fetch(byId: set.id)

        XCTAssertNil(result.prResult.newStatus)
        XCTAssertFalse(result.prResult.prRecordChanged)
        XCTAssertTrue(performanceRecords.isEmpty)
        XCTAssertNil(persistedSet?.cachedPRStatus)
    }

    func testFetchPRTableReturnsEmptyForUnsupportedExerciseWithStalePRData() async throws {
        let context = try makeContext()
        let workoutDate = makeDate(2026, 3, 22, 9, 30)
        let records = try await insertExerciseAndWorkout(
            in: context,
            name: "Run",
            equipmentType: .bodyweight,
            trackingType: .durationDistance,
            primaryMuscle: "legs",
            date: workoutDate
        )
        let set = WorkoutSet(
            workoutId: records.workout.id,
            exerciseId: records.exercise.id,
            date: workoutDate,
            durationSeconds: 1_500,
            distanceMeters: 5_000,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        try await context.setRepo.save(set)
        try await context.performanceRecordRepo.save(
            PerformanceRecord(
                exerciseId: records.exercise.id,
                recordType: .repMax,
                reps: 1,
                value: 1,
                setId: set.id,
                date: workoutDate
            )
        )

        let table = try await context.prService.fetchPRTable(for: records.exercise.id)

        XCTAssertTrue(table.isEmpty)
    }

    func testRebuildRemovesStalePRDataForUnsupportedExercise() async throws {
        let context = try makeContext()
        let workoutDate = makeDate(2026, 3, 22, 9, 45)
        let records = try await insertExerciseAndWorkout(
            in: context,
            name: "Interval Run",
            equipmentType: .bodyweight,
            trackingType: .durationDistance,
            primaryMuscle: "legs",
            date: workoutDate
        )
        let set = WorkoutSet(
            workoutId: records.workout.id,
            exerciseId: records.exercise.id,
            date: workoutDate,
            durationSeconds: 600,
            distanceMeters: 1_600,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true,
            cachedPRStatus: .current
        )
        try await context.setRepo.save(set)
        try await context.performanceRecordRepo.save(
            PerformanceRecord(
                exerciseId: records.exercise.id,
                recordType: .repMax,
                reps: 1,
                value: 1,
                setId: set.id,
                date: workoutDate
            )
        )

        try await context.prService.rebuild(for: records.exercise.id)

        let performanceRecords = try await context.performanceRecordRepo.fetchAll(for: records.exercise.id)
        let persistedSet = try await context.setRepo.fetch(byId: set.id)

        XCTAssertTrue(performanceRecords.isEmpty)
        XCTAssertNil(persistedSet?.cachedPRStatus)
    }

    func testFetchRecentPRsIgnoresUnsupportedExercises() async throws {
        let context = try makeContext()
        let supportedDate = makeDate(2026, 3, 22, 10, 0)
        let unsupportedDate = makeDate(2026, 3, 22, 10, 5)

        let supported = try await insertExerciseAndWorkout(
            in: context,
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            date: supportedDate
        )
        let supportedSet = WorkoutSet(
            workoutId: supported.workout.id,
            exerciseId: supported.exercise.id,
            date: supportedDate,
            completedAt: supportedDate.addingTimeInterval(240),
            weight: 110,
            reps: 3,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        _ = try await context.setService.save(supportedSet)

        let unsupported = try await insertExerciseAndWorkout(
            in: context,
            name: "Tempo Row",
            equipmentType: .machinePin,
            trackingType: .weightRepsDuration,
            primaryMuscle: "back",
            date: unsupportedDate
        )
        let unsupportedSet = WorkoutSet(
            workoutId: unsupported.workout.id,
            exerciseId: unsupported.exercise.id,
            date: unsupportedDate,
            weight: 55,
            reps: 10,
            durationSeconds: 60,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        try await context.setRepo.save(unsupportedSet)
        try await context.performanceRecordRepo.save(
            PerformanceRecord(
                exerciseId: unsupported.exercise.id,
                recordType: .repMax,
                reps: 10,
                value: 55,
                setId: unsupportedSet.id,
                date: unsupportedDate
            )
        )

        let recentPRs = try await context.statsService.fetchRecentPRs(
            since: supportedDate.addingTimeInterval(-3_600),
            limit: 3
        )

        XCTAssertEqual(recentPRs.map(\.exerciseId), [supported.exercise.id])
    }

    func testStartupPRRebuildMaintenanceRunsOnceOnSuccess() async throws {
        let suiteName = "StartupPRRebuildMaintenanceRunsOnce-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settingsService = StartupPRRebuildSettingsServiceStub()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        await StartupPRRebuildMaintenance.runIfNeeded(
            settingsService: settingsService,
            userDefaults: userDefaults
        )
        await StartupPRRebuildMaintenance.runIfNeeded(
            settingsService: settingsService,
            userDefaults: userDefaults
        )
        let rebuildCallCount = await settingsService.recordedRebuildPRsCallCount()

        XCTAssertEqual(
            userDefaults.integer(forKey: StartupPRRebuildMaintenance.userDefaultsKey),
            StartupPRRebuildMaintenance.currentVersion
        )
        XCTAssertEqual(rebuildCallCount, 1)
    }

    func testStartupPRRebuildMaintenanceRetriesAfterFailure() async throws {
        let suiteName = "StartupPRRebuildMaintenanceRetries-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settingsService = StartupPRRebuildSettingsServiceStub()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        await settingsService.setRebuildPRsError(StartupPRRebuildTestError.failed)
        await StartupPRRebuildMaintenance.runIfNeeded(
            settingsService: settingsService,
            userDefaults: userDefaults
        )
        let failedCallCount = await settingsService.recordedRebuildPRsCallCount()

        XCTAssertEqual(userDefaults.integer(forKey: StartupPRRebuildMaintenance.userDefaultsKey), 0)
        XCTAssertEqual(failedCallCount, 1)

        await settingsService.setRebuildPRsError(nil)
        await StartupPRRebuildMaintenance.runIfNeeded(
            settingsService: settingsService,
            userDefaults: userDefaults
        )
        let finalCallCount = await settingsService.recordedRebuildPRsCallCount()

        XCTAssertEqual(
            userDefaults.integer(forKey: StartupPRRebuildMaintenance.userDefaultsKey),
            StartupPRRebuildMaintenance.currentVersion
        )
        XCTAssertEqual(finalCallCount, 2)
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
            workoutRepository: workoutRepo,
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
            statsService: statsService,
            prService: prService,
            backupService: backupService,
            exerciseRepo: exerciseRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo,
            performanceRecordRepo: performanceRecordRepo
        )
    }

    private func insertExerciseAndWorkout(
        in context: SetServiceTestContext,
        name: String,
        equipmentType: EquipmentType,
        trackingType: TrackingType,
        primaryMuscle: String,
        date: Date
    ) async throws -> (exercise: Exercise, workout: Workout) {
        let exercise = Exercise(
            name: name,
            equipmentType: equipmentType,
            trackingType: trackingType,
            primaryMuscle: primaryMuscle
        )
        let workout = Workout(
            date: date,
            title: name,
            startTime: date,
            endTime: date.addingTimeInterval(1_800),
            duration: 1_800,
            status: .completed
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)

        return (exercise, workout)
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
    let statsService: StatsService
    let prService: PRService
    let backupService: WorkoutHistoryBackupService
    let exerciseRepo: ExerciseRepository
    let workoutRepo: WorkoutRepository
    let setRepo: SetRepository
    let performanceRecordRepo: PerformanceRecordRepository
}

private struct SeededTrackedSet {
    let exercise: Exercise
    let workout: Workout
    let set: WorkoutSet
    let observation: FatigueObservation
    let audit: FatigueLearningSetAudit
}

private actor StartupPRRebuildSettingsServiceStub: SettingsServiceProtocol {
    private var rebuildPRsCallCount = 0
    private var rebuildPRsError: Error?

    func setRebuildPRsError(_ error: Error?) {
        rebuildPRsError = error
    }

    func recordedRebuildPRsCallCount() -> Int {
        rebuildPRsCallCount
    }

    func fetchSettings() async throws -> HealthProfile { HealthProfile() }
    func updateUnitPreference(_ preference: UnitPreference) async throws {}
    func updateE1RMFormula(_ formula: E1RMFormula) async throws {}
    func updateIncludeWarmupsInVolume(_ include: Bool) async throws {}
    func updateIncludeWarmupsInPRs(_ include: Bool) async throws {}
    func updateDefaultRestTime(_ seconds: Int?) async throws {}
    func updateDefaultWarmupRestTime(_ seconds: Int?) async throws {}
    func updateRestTimerAlert(_ value: String) async throws {}
    func updatePrescriptionEnabled(_ enabled: Bool) async throws {}
    func updatePrescriptionRecencyWeeks(_ weeks: Int) async throws {}
    func updatePrescriptionDefaultIncrement(_ increment: Double) async throws {}
    func updatePrescriptionDefaultTargetReps(_ reps: Int) async throws {}
    func updatePrescriptionDefaultTargetRIR(_ rir: Int) async throws {}
    func updatePrescriptionFreshnessBonus(enabled: Bool, percent: Double) async throws {}
    func updatePrescriptionFatigueModelingEnabled(_ enabled: Bool) async throws {}
    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws {}
    func updatePrescriptionAdminModeEnabled(_ enabled: Bool) async throws {}
    func resetAllAppData() async throws {}

    func rebuildPRs() async throws {
        rebuildPRsCallCount += 1
        if let rebuildPRsError {
            throw rebuildPRsError
        }
    }

    func rebuildStats() async throws {}
    func rebuildAll() async throws {}
}

private enum StartupPRRebuildTestError: Error {
    case failed
}
