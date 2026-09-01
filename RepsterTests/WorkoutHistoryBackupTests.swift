import XCTest
import SwiftData
import UniformTypeIdentifiers
@testable import Repster

@MainActor
final class WorkoutHistoryBackupArchiveServiceTests: XCTestCase {
    func testExportBackupPreservesMultipleSameDayWorkoutsAndMetadata() async throws {
        let context = try makeBackupServiceContext()

        let bench = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            bodyweightFactor: 0.35,
            weightIncrement: 2.5,
            defaultRestTime: 180,
            createdAt: makeDate(2026, 3, 18, 9, 0),
            updatedAt: makeDate(2026, 3, 18, 9, 15)
        )
        try await context.exerciseRepo.save(bench)

        let firstStart = makeDate(2026, 3, 19, 0, 30)
        let secondStart = makeDate(2026, 3, 19, 18, 0)

        let midnightWorkout = Workout(
            date: firstStart,
            title: "Midnight Session",
            startTime: firstStart,
            endTime: makeDate(2026, 3, 19, 1, 25),
            duration: 3300,
            perceivedEffort: 8.5,
            notes: "Opened the gym and hit bench",
            status: .completed,
            createdAt: firstStart,
            updatedAt: makeDate(2026, 3, 19, 1, 26)
        )
        let eveningWorkout = Workout(
            date: secondStart,
            title: "Evening Session",
            startTime: secondStart,
            endTime: makeDate(2026, 3, 19, 19, 5),
            duration: 3900,
            perceivedEffort: 7.0,
            notes: "Accessories only",
            status: .completed,
            createdAt: secondStart,
            updatedAt: makeDate(2026, 3, 19, 19, 6)
        )
        try await context.workoutRepo.save(midnightWorkout)
        try await context.workoutRepo.save(eveningWorkout)

        let warmupSet = WorkoutSet(
            workoutId: midnightWorkout.id,
            exerciseId: bench.id,
            date: firstStart,
            completedAt: makeDate(2026, 3, 19, 0, 40),
            weight: 60,
            effectiveWeight: 88,
            reps: 5,
            e1RM: 98,
            e1RMFormulaVersion: "epley",
            setType: .warmup,
            notes: "Quick primer",
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true,
            excludeFromPRs: true,
            createdAt: makeDate(2026, 3, 19, 0, 35),
            updatedAt: makeDate(2026, 3, 19, 0, 40),
            restDurationSeconds: 90
        )
        let placeholderSet = WorkoutSet(
            workoutId: eveningWorkout.id,
            exerciseId: bench.id,
            date: secondStart,
            setType: .working,
            notes: "Left blank intentionally",
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false,
            createdAt: secondStart,
            updatedAt: makeDate(2026, 3, 19, 18, 5)
        )
        try await context.setRepo.save(warmupSet)
        try await context.setRepo.save(placeholderSet)

        let exportedData = try await context.service.exportBackup()
        let archive = try decodeBackupArchive(exportedData)
        let preview = try context.service.previewBackup(data: exportedData)

        XCTAssertEqual(archive.version, WorkoutHistoryArchive.currentVersion)
        XCTAssertEqual(archive.workouts.map(\.id), [midnightWorkout.id, eveningWorkout.id])
        XCTAssertEqual(archive.workouts.first?.title, "Midnight Session")
        XCTAssertEqual(archive.workouts.first?.notes, "Opened the gym and hit bench")
        XCTAssertEqual(archive.workouts.last?.title, "Evening Session")
        XCTAssertEqual(archive.exercises.count, 1)
        XCTAssertEqual(archive.exercises.first?.bodyweightFactor, 0.35)

        let exportedWarmup = try XCTUnwrap(archive.sets.first(where: { $0.id == warmupSet.id }))
        XCTAssertEqual(exportedWarmup.setType, SetType.warmup.rawValue)
        XCTAssertEqual(exportedWarmup.excludeFromPRs, true)
        XCTAssertEqual(exportedWarmup.restDurationSeconds, 90)

        let exportedPlaceholder = try XCTUnwrap(archive.sets.first(where: { $0.id == placeholderSet.id }))
        XCTAssertNil(exportedPlaceholder.weight)
        XCTAssertNil(exportedPlaceholder.reps)
        XCTAssertFalse(exportedPlaceholder.completed)
        XCTAssertEqual(exportedPlaceholder.notes, "Left blank intentionally")

        XCTAssertEqual(preview.workoutCount, 2)
        XCTAssertEqual(preview.exerciseCount, 1)
        XCTAssertEqual(preview.setCount, 2)
        XCTAssertEqual(preview.earliestWorkoutDate, firstStart)
        XCTAssertEqual(preview.latestWorkoutDate, secondStart)
    }

    func testBackupPreservesExerciseFatigueRateSourceMetadata() async throws {
        let context = try makeBackupServiceContext()
        let workoutDate = makeDate(2026, 3, 22, 9, 0)
        let exercise = Exercise(
            name: "Chest Press",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            fatigueRate: 0.041,
            fatigueRateSourceRawValue: ExerciseFatigueRateSource.manualOverride.rawValue
        )
        let workout = Workout(
            date: workoutDate,
            title: "Push Day",
            startTime: workoutDate,
            endTime: makeDate(2026, 3, 22, 10, 0),
            duration: 3600,
            status: .completed
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            completedAt: makeDate(2026, 3, 22, 9, 20),
            weight: 80,
            effectiveWeight: 80,
            reps: 8,
            rir: 0,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)

        let exportedData = try await context.service.exportBackup()
        let archive = try decodeBackupArchive(exportedData)
        let archivedExercise = try XCTUnwrap(archive.exercises.first(where: { $0.id == exercise.id }))
        XCTAssertEqual(archivedExercise.fatigueRateSourceRawValue, ExerciseFatigueRateSource.manualOverride.rawValue)

        let restoredContext = try makeBackupServiceContext()
        _ = try await restoredContext.service.restoreBackup(data: exportedData)
        let restoredExercise = try await restoredContext.exerciseRepo.fetch(byId: exercise.id)
        XCTAssertEqual(restoredExercise?.fatigueRateSourceRawValue, ExerciseFatigueRateSource.manualOverride.rawValue)
    }

    func testBackupPreservesUnilateralRepTargetModeMetadata() async throws {
        let context = try makeBackupServiceContext()
        let workoutDate = Date()
        let exercise = Exercise(
            name: "Dumbbell Lunge",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides
        )
        let workout = Workout(
            date: workoutDate,
            startTime: workoutDate,
            status: .completed
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            weight: 20,
            effectiveWeight: 20,
            reps: 10,
            rir: 0,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)

        let exportedData = try await context.service.exportBackup()
        let archive = try decodeBackupArchive(exportedData)
        let archivedExercise = try XCTUnwrap(archive.exercises.first(where: { $0.id == exercise.id }))
        XCTAssertEqual(archivedExercise.unilateralRepTargetMode, .totalAcrossSides)

        let restoredContext = try makeBackupServiceContext()
        _ = try await restoredContext.service.restoreBackup(data: exportedData)
        let restoredExercise = try await restoredContext.exerciseRepo.fetch(byId: exercise.id)
        XCTAssertEqual(restoredExercise?.unilateralRepTargetMode, .totalAcrossSides)
    }

    func testRestoreBackupReplacesHistoryAndKeepsUnrelatedData() async throws {
        let context = try makeBackupServiceContext()
        let profile = try await context.healthProfileRepo.fetchOrCreate()
        profile.unitPreference = .imperial
        try await context.healthProfileRepo.save(profile)

        let archivedExercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            defaultRestTime: 180
        )
        let unrelatedExercise = Exercise(
            name: "Jogging",
            equipmentType: .bodyweight,
            trackingType: .duration,
            primaryMuscle: "legs"
        )
        try await context.exerciseRepo.save(archivedExercise)
        try await context.exerciseRepo.save(unrelatedExercise)

        let bodyweightEntry = BodyweightEntry(
            healthProfileId: profile.id,
            date: makeDate(2026, 3, 18, 7, 0),
            bodyweightKg: 82.5
        )
        try await context.bodyweightRepo.save(bodyweightEntry)

        let templateContext = ModelContext(context.modelContainer)
        let template = WorkoutTemplate(name: "Push Day", notes: "Leave this alone")
        templateContext.insert(template)
        let templateExercise = TemplateExercise(
            templateId: template.id,
            exerciseId: unrelatedExercise.id,
            orderInTemplate: 1,
            restTimeSeconds: 120,
            notes: "Accessory"
        )
        templateContext.insert(templateExercise)
        let templateSet = TemplateSet(
            templateExerciseId: templateExercise.id,
            setType: .working,
            targetRepMin: 8,
            targetRepMax: 10,
            targetRIR: 2,
            orderInExercise: 1
        )
        templateContext.insert(templateSet)
        try templateContext.save()

        let firstWorkout = Workout(
            date: makeDate(2026, 3, 19, 0, 30),
            title: "Backup A",
            startTime: makeDate(2026, 3, 19, 0, 30),
            endTime: makeDate(2026, 3, 19, 1, 10),
            duration: 2400,
            perceivedEffort: 8,
            notes: "Midnight history",
            status: .completed,
            createdAt: makeDate(2026, 3, 19, 0, 30),
            updatedAt: makeDate(2026, 3, 19, 1, 11)
        )
        let secondWorkout = Workout(
            date: makeDate(2026, 3, 19, 18, 0),
            title: "Backup B",
            startTime: makeDate(2026, 3, 19, 18, 0),
            endTime: makeDate(2026, 3, 19, 18, 50),
            duration: 3000,
            perceivedEffort: 7,
            notes: "Evening history",
            status: .completed,
            createdAt: makeDate(2026, 3, 19, 18, 0),
            updatedAt: makeDate(2026, 3, 19, 18, 55)
        )
        try await context.workoutRepo.save(firstWorkout)
        try await context.workoutRepo.save(secondWorkout)

        let workingSet = WorkoutSet(
            workoutId: firstWorkout.id,
            exerciseId: archivedExercise.id,
            date: firstWorkout.date,
            completedAt: makeDate(2026, 3, 19, 0, 50),
            weight: 100,
            effectiveWeight: 100,
            reps: 5,
            e1RM: 116.7,
            e1RMFormulaVersion: "epley",
            setType: .working,
            notes: "Top set",
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true,
            createdAt: makeDate(2026, 3, 19, 0, 45),
            updatedAt: makeDate(2026, 3, 19, 0, 50)
        )
        let placeholderSet = WorkoutSet(
            workoutId: secondWorkout.id,
            exerciseId: archivedExercise.id,
            date: secondWorkout.date,
            setType: .working,
            notes: "Still blank",
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false,
            createdAt: secondWorkout.date,
            updatedAt: makeDate(2026, 3, 19, 18, 5)
        )
        try await context.setRepo.save(workingSet)
        try await context.setRepo.save(placeholderSet)

        let backupData = try await context.service.exportBackup()

        let replacementWorkout = Workout(
            date: makeDate(2026, 3, 20, 9, 0),
            title: "Current History",
            startTime: makeDate(2026, 3, 20, 9, 0),
            endTime: makeDate(2026, 3, 20, 10, 0),
            duration: 3600,
            status: .completed
        )
        try await context.workoutRepo.save(replacementWorkout)
        let replacementSet = WorkoutSet(
            workoutId: replacementWorkout.id,
            exerciseId: archivedExercise.id,
            date: replacementWorkout.date,
            weight: 80,
            effectiveWeight: 80,
            reps: 8,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        try await context.setRepo.save(replacementSet)

        let replacementWorkoutId = replacementWorkout.id
        let firstWorkoutDate = firstWorkout.date
        let placeholderSetId = placeholderSet.id
        let unrelatedExerciseId = unrelatedExercise.id
        let bodyweightEntryId = bodyweightEntry.id
        let archivedExerciseId = archivedExercise.id
        let templateId = template.id
        let templateExerciseId = templateExercise.id
        let templateSetId = templateSet.id

        let restoreResult = try await context.service.restoreBackup(data: backupData)

        let restoredWorkouts = try await context.workoutRepo.fetchAllWorkouts(limit: nil, offset: nil)
        let restoredSets = try await context.setRepo.fetchSets(from: .distantPast, to: .distantFuture)
        let allExercises = try await context.exerciseRepo.fetchAll()
        let bodyweightEntries = try await context.bodyweightRepo.fetchAll(for: profile.id)
        let stats = try await context.exerciseStatsRepo.fetch(for: archivedExerciseId)
        let records = try await context.performanceRecordRepo.fetchAll(for: archivedExerciseId)
        let settingsAfterRestore = try await context.healthProfileRepo.fetchOrCreate()
        let verificationContext = ModelContext(context.modelContainer)
        let templates = try verificationContext.fetch(FetchDescriptor<WorkoutTemplate>())
        let templateExercises = try verificationContext.fetch(FetchDescriptor<TemplateExercise>())
        let templateSets = try verificationContext.fetch(FetchDescriptor<TemplateSet>())

        XCTAssertEqual(restoreResult.workoutsRestored, 2)
        // Both the trained exercise and "Jogging", which has no sets: the archive now carries the
        // whole library rather than only exercises that appear in one. Covered directly by
        // `testExportBackupIncludesExercisesWithNoLoggedSets`.
        XCTAssertEqual(restoreResult.exercisesUpserted, 2)
        XCTAssertEqual(restoreResult.setsRestored, 2)
        XCTAssertEqual(restoreResult.skippedFatigueObservations, 0)
        XCTAssertEqual(restoreResult.skippedFatigueLearningAudits, 0)
        XCTAssertEqual(restoredWorkouts.count, 2)
        XCTAssertFalse(restoredWorkouts.contains(where: { $0.id == replacementWorkoutId }))
        XCTAssertEqual(restoredWorkouts.filter { Calendar.current.isDate($0.date, inSameDayAs: firstWorkoutDate) }.count, 2)
        XCTAssertEqual(restoredSets.count, 2)
        XCTAssertTrue(restoredSets.contains(where: { $0.id == placeholderSetId && $0.completed == false && $0.weight == nil }))
        XCTAssertTrue(allExercises.contains(where: { $0.id == unrelatedExerciseId }))
        XCTAssertEqual(bodyweightEntries.count, 1)
        XCTAssertEqual(bodyweightEntries.first?.id, bodyweightEntryId)
        XCTAssertEqual(settingsAfterRestore.unitPreference, .imperial)
        XCTAssertEqual(templates.map(\.id), [templateId])
        XCTAssertEqual(templateExercises.map(\.id), [templateExerciseId])
        XCTAssertEqual(templateSets.map(\.id), [templateSetId])
        XCTAssertNotNil(stats)
        XCTAssertEqual(records.count, 1)
    }

    func testBackupExportAndRestorePreservesWorkoutProgressionExclusions() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        try await context.exerciseRepo.save(exercise)

        let workoutDate = makeDate(2026, 3, 20, 9, 0)
        let workout = Workout(
            date: workoutDate,
            title: "Travel Session",
            startTime: workoutDate,
            endTime: makeDate(2026, 3, 20, 10, 0),
            duration: 3600,
            status: .completed,
            excludeFromProgressionHistory: true,
            excludedExerciseIdsFromProgressionHistory: [exercise.id]
        )
        try await context.workoutRepo.save(workout)

        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            completedAt: makeDate(2026, 3, 20, 9, 20),
            weight: 90,
            effectiveWeight: 90,
            reps: 5,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        try await context.setRepo.save(set)

        let backupData = try await context.service.exportBackup()
        let archive = try decodeBackupArchive(backupData)
        let archivedWorkout = try XCTUnwrap(archive.workouts.first(where: { $0.id == workout.id }))

        XCTAssertEqual(archivedWorkout.excludeFromProgressionHistory, true)
        XCTAssertEqual(
            Set(archivedWorkout.excludedExerciseIdsFromProgressionHistory ?? []),
            [exercise.id]
        )

        let restoredContext = try makeBackupServiceContext()
        let restoreResult = try await restoredContext.service.restoreBackup(data: backupData)
        let restoredWorkout = try await restoredContext.workoutRepo.fetch(byId: workout.id)

        XCTAssertEqual(restoreResult.workoutsRestored, 1)
        XCTAssertEqual(restoredWorkout?.excludeFromProgressionHistory, true)
        XCTAssertEqual(
            Set(restoredWorkout?.excludedExerciseIdsFromProgressionHistory ?? []),
            [exercise.id]
        )
        XCTAssertTrue(restoredWorkout?.excludesFromProgressionHistory(exerciseId: exercise.id) == true)
    }

    func testStartWorkoutOptionsPersistProgressionHistoryChoice() async throws {
        let context = try makeBackupServiceContext()

        let workout = try await context.workoutService.startWorkout(
            options: WorkoutStartOptions(countTowardProgressionHistory: false)
        )

        XCTAssertEqual(workout.excludeFromProgressionHistory, true)
        XCTAssertTrue(workout.excludesEntireWorkoutFromProgressionHistory)
    }

    func testTemplateStartWorkoutOptionsPersistProgressionHistoryChoice() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        try await context.exerciseRepo.save(exercise)

        let template = WorkoutTemplate(name: "Push Day")
        try await context.templateRepo.saveTemplate(template)

        let templateExercise = TemplateExercise(
            templateId: template.id,
            exerciseId: exercise.id,
            orderInTemplate: 1
        )
        try await context.templateRepo.saveTemplateExercise(templateExercise)

        let templateSet = TemplateSet(
            templateExerciseId: templateExercise.id,
            setType: .working,
            targetRepMin: 5,
            targetRepMax: 8,
            targetRIR: 2,
            orderInExercise: 1
        )
        try await context.templateRepo.saveTemplateSet(templateSet)

        let workout = try await context.templateService.startWorkoutFromTemplate(
            template.id,
            options: WorkoutStartOptions(countTowardProgressionHistory: false)
        )

        XCTAssertEqual(workout.excludeFromProgressionHistory, true)
        XCTAssertTrue(workout.excludesEntireWorkoutFromProgressionHistory)
    }

    func testBackupRoundTripPreservesFatigueLearningAuditsAndGlobalProfileLearning() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(
            name: "Lat Pulldown",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            defaultRestTime: 150
        )
        try await context.exerciseRepo.save(exercise)

        let workoutDate = makeDate(2026, 3, 20, 17, 0)
        let workout = Workout(
            date: workoutDate,
            title: "Pull Day",
            startTime: workoutDate,
            endTime: makeDate(2026, 3, 20, 18, 0),
            duration: 3600,
            status: .completed
        )
        try await context.workoutRepo.save(workout)

        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            completedAt: makeDate(2026, 3, 20, 17, 20),
            weight: 80,
            effectiveWeight: 80,
            reps: 8,
            rir: 0,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true,
            createdAt: makeDate(2026, 3, 20, 17, 10),
            updatedAt: makeDate(2026, 3, 20, 17, 20),
            restDurationSeconds: 150
        )
        try await context.setRepo.save(set)

        let profile = try await context.healthProfileRepo.fetchOrCreate()
        profile.prescriptionLearnedFatigueRate = 0.047
        profile.prescriptionFatigueLearningSessionCount = 3
        profile.prescriptionFatigueLearningCumulativeError = -0.012
        try await context.healthProfileRepo.save(profile)

        let learningContext = ModelContext(context.modelContainer)
        learningContext.insert(
            FatigueObservation(
                exerciseId: exercise.id,
                workoutId: workout.id,
                setId: set.id,
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
                createdAt: makeDate(2026, 3, 20, 17, 20)
            )
        )
        learningContext.insert(
            FatigueLearningSetAudit(
                workoutId: workout.id,
                exerciseId: exercise.id,
                setId: set.id,
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
                createdAt: makeDate(2026, 3, 20, 17, 20)
            )
        )
        try learningContext.save()

        let backupData = try await context.service.exportBackup()
        let archive = try decodeBackupArchive(backupData)

        XCTAssertEqual(archive.fatigueObservations?.count, 1)
        XCTAssertEqual(archive.fatigueLearningAudits?.count, 1)
        XCTAssertEqual(archive.healthProfileLearning?.prescriptionLearnedFatigueRate ?? 0, 0.047, accuracy: 0.0001)
        XCTAssertEqual(archive.healthProfileLearning?.prescriptionFatigueLearningSessionCount, 3)

        let restoredContext = try makeBackupServiceContext()
        let restoreResult = try await restoredContext.service.restoreBackup(data: backupData)

        let restoredProfile = try await restoredContext.healthProfileRepo.fetchOrCreate()
        let verificationContext = ModelContext(restoredContext.modelContainer)
        let restoredObservations = try verificationContext.fetch(FetchDescriptor<FatigueObservation>())
        let restoredAudits = try verificationContext.fetch(FetchDescriptor<FatigueLearningSetAudit>())

        XCTAssertEqual(restoreResult.skippedFatigueObservations, 0)
        XCTAssertEqual(restoreResult.skippedFatigueLearningAudits, 0)
        XCTAssertEqual(restoredProfile.prescriptionLearnedFatigueRate ?? 0, 0.047, accuracy: 0.0001)
        XCTAssertEqual(restoredProfile.prescriptionFatigueLearningSessionCount, 3)
        XCTAssertEqual(restoredProfile.prescriptionFatigueLearningCumulativeError ?? 0, -0.012, accuracy: 0.0001)
        XCTAssertEqual(restoredObservations.count, 1)
        XCTAssertEqual(restoredObservations.first?.setId, set.id)
        XCTAssertEqual(restoredAudits.count, 1)
        XCTAssertEqual(restoredAudits.first?.status, .used)
        XCTAssertEqual(restoredAudits.first?.setId, set.id)
    }

    func testExportBackupSkipsOrphanedFatigueLearningRows() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(
            name: "Incline Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        let workoutDate = makeDate(2026, 3, 21, 9, 0)
        let workout = Workout(
            date: workoutDate,
            title: "Push Day",
            startTime: workoutDate,
            endTime: makeDate(2026, 3, 21, 10, 0),
            duration: 3600,
            status: .completed
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            completedAt: makeDate(2026, 3, 21, 9, 20),
            weight: 70,
            effectiveWeight: 70,
            reps: 8,
            rir: 1,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)
        let learningContext = ModelContext(context.modelContainer)
        let validRecords = try insertLearningRecords(
            into: learningContext,
            exerciseId: exercise.id,
            workoutId: workout.id,
            setId: set.id,
            createdAt: makeDate(2026, 3, 21, 9, 20)
        )
        learningContext.insert(
            FatigueObservation(
                exerciseId: exercise.id,
                workoutId: UUID(),
                setId: UUID(),
                setIndex: 2,
                predictedEffectiveE1RM: 125,
                actualE1RM: 120,
                normalizedError: 0.04,
                baseE1RM: 130,
                prescribedWeight: 72.5,
                actualWeight: 70,
                actualReps: 8,
                actualRIR: 1,
                createdAt: makeDate(2026, 3, 21, 9, 35)
            )
        )
        learningContext.insert(
            FatigueLearningSetAudit(
                workoutId: workout.id,
                exerciseId: exercise.id,
                setId: UUID(),
                visibleSetNumber: 3,
                setType: .working,
                status: .used,
                predictedEffectiveE1RM: 125,
                baseE1RM: 130,
                prescribedWeight: 72.5,
                actualWeight: 70,
                actualReps: 8,
                actualRIR: 1,
                deviationFraction: 0.03,
                normalizedError: -0.02,
                createdAt: makeDate(2026, 3, 21, 9, 35)
            )
        )
        try learningContext.save()

        let backupData = try await context.service.exportBackup()
        let archive = try decodeBackupArchive(backupData)

        XCTAssertEqual(archive.fatigueObservations?.map(\.id), [validRecords.observation.id])
        XCTAssertEqual(archive.fatigueLearningAudits?.map(\.id), [validRecords.audit.id])
    }

    func testRestoreBackupSkipsOrphanedFatigueLearningRowsAndReturnsWarningCounts() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(
            name: "Row",
            equipmentType: .cable,
            trackingType: .weightReps
        )
        let workoutDate = makeDate(2026, 3, 22, 8, 0)
        let workout = Workout(
            date: workoutDate,
            title: "Back Day",
            startTime: workoutDate,
            endTime: makeDate(2026, 3, 22, 9, 0),
            duration: 3600,
            status: .completed
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            completedAt: makeDate(2026, 3, 22, 8, 15),
            weight: 65,
            effectiveWeight: 65,
            reps: 10,
            rir: 0,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)
        let learningContext = ModelContext(context.modelContainer)
        let validRecords = try insertLearningRecords(
            into: learningContext,
            exerciseId: exercise.id,
            workoutId: workout.id,
            setId: set.id,
            createdAt: makeDate(2026, 3, 22, 8, 15)
        )
        try learningContext.save()

        let backupData = try await context.service.exportBackup()
        let archive = try decodeBackupArchive(backupData)
        let orphanObservation = WorkoutHistoryArchiveFatigueObservation(
            id: UUID(),
            exerciseId: exercise.id,
            workoutId: workout.id,
            setId: UUID(),
            setIndex: 2,
            predictedEffectiveE1RM: 118,
            actualE1RM: 115,
            normalizedError: 0.02,
            baseE1RM: 120,
            prescribedWeight: 67.5,
            actualWeight: 65,
            actualReps: 10,
            actualRIR: 0,
            restDurationSeconds: 150,
            modelEpoch: SuggestionModelEpoch.current,
            setTypeRawValue: SetType.working.rawValue,
            createdAt: makeDate(2026, 3, 22, 8, 25)
        )
        let orphanAudit = WorkoutHistoryArchiveFatigueLearningSetAudit(
            id: UUID(),
            workoutId: UUID(),
            exerciseId: exercise.id,
            setId: set.id,
            visibleSetNumber: 2,
            setType: SetType.working.rawValue,
            status: FatigueLearningAuditStatus.used.rawValue,
            suggestionUnavailableReasonRawValue: nil,
            predictedEffectiveE1RM: 118,
            baseE1RM: 120,
            prescribedWeight: 67.5,
            actualWeight: 65,
            actualReps: 10,
            actualRIR: 0,
            deviationFraction: 0.01,
            normalizedError: -0.01,
            modelEpoch: SuggestionModelEpoch.current,
            createdAt: makeDate(2026, 3, 22, 8, 25)
        )
        let mutatedArchive = WorkoutHistoryArchive(
            version: archive.version,
            exportedAt: archive.exportedAt,
            workouts: archive.workouts,
            exercises: archive.exercises,
            sets: archive.sets,
            fatigueObservations: (archive.fatigueObservations ?? []) + [orphanObservation],
            fatigueLearningAudits: (archive.fatigueLearningAudits ?? []) + [orphanAudit],
            healthProfileLearning: archive.healthProfileLearning
        )

        let restoredContext = try makeBackupServiceContext()
        let restoreResult = try await restoredContext.service.restoreBackup(data: try encodeBackupArchive(mutatedArchive))
        let verificationContext = ModelContext(restoredContext.modelContainer)
        let restoredObservations = try verificationContext.fetch(FetchDescriptor<FatigueObservation>())
        let restoredAudits = try verificationContext.fetch(FetchDescriptor<FatigueLearningSetAudit>())

        XCTAssertEqual(restoreResult.workoutsRestored, 1)
        XCTAssertEqual(restoreResult.exercisesUpserted, 1)
        XCTAssertEqual(restoreResult.setsRestored, 1)
        XCTAssertEqual(restoreResult.skippedFatigueObservations, 1)
        XCTAssertEqual(restoreResult.skippedFatigueLearningAudits, 1)
        XCTAssertTrue(restoreResult.hasSkippedLearningData)
        XCTAssertNotNil(restoreResult.learningDataWarningMessage)
        XCTAssertEqual(restoredObservations.map(\.id), [validRecords.observation.id])
        XCTAssertEqual(restoredAudits.map(\.id), [validRecords.audit.id])
    }

    func testFatigueObservationRepositoryDeletesLegacyRowsWithoutStoredSetId() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(
            name: "Chest Press",
            equipmentType: .machinePin,
            trackingType: .weightReps
        )
        let workout = Workout(
            date: makeDate(2026, 3, 20, 17, 0),
            title: "Legacy Session",
            startTime: makeDate(2026, 3, 20, 17, 0),
            status: .completed
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)

        let observation = FatigueObservation(
            id: UUID(),
            exerciseId: exercise.id,
            workoutId: workout.id,
            setId: UUID(),
            setIndex: 1,
            predictedEffectiveE1RM: 120,
            actualE1RM: 125,
            normalizedError: -0.04,
            baseE1RM: 130,
            prescribedWeight: 80,
            actualWeight: 82.5,
            actualReps: 8,
            actualRIR: 0,
            createdAt: makeDate(2026, 3, 20, 17, 30)
        )
        observation.storedSetId = nil

        let modelContext = ModelContext(context.modelContainer)
        modelContext.insert(observation)
        try modelContext.save()

        let repo = FatigueObservationRepository(modelContainer: context.modelContainer)
        try await repo.deleteObservation(for: observation.id)

        let remaining = try modelContext.fetch(FetchDescriptor<FatigueObservation>())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRestoreBackupRejectsArchiveFromNewerAppVersion() async throws {
        let context = try makeBackupServiceContext()
        let invalidArchive = makeEmptyArchive(version: 99)
        let invalidData = try encodeBackupArchive(invalidArchive)

        do {
            _ = try await context.service.restoreBackup(data: invalidData)
            XCTFail("Expected an archive from a newer app version to fail")
        } catch let error as WorkoutHistoryBackupError {
            guard case .archiveVersionTooNew(let version) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, 99)
            XCTAssertEqual(
                error.errorDescription,
                "This backup was made by a newer version of Repster (backup format 99). "
                    + "Update Repster, then restore it again."
            )
        }
    }

    func testRestoreBackupRejectsArchiveBelowMinimumSupportedVersion() async throws {
        let context = try makeBackupServiceContext()
        let invalidData = try encodeBackupArchive(makeEmptyArchive(version: 0))

        do {
            _ = try await context.service.restoreBackup(data: invalidData)
            XCTFail("Expected a below-minimum archive version to fail")
        } catch let error as WorkoutHistoryBackupError {
            guard case .invalidArchiveVersion(let version) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, 0)
        }
    }

    /// The tripwire for a future format bump.
    ///
    /// Every `.repsterbackup` in the wild today is v1, and restore accepts the whole
    /// `minimumSupportedVersion ... currentVersion` range rather than an exact match — but that
    /// range is a single value right now, so the range check itself is not yet observable. What is
    /// observable is this: a real v1 payload, checked in, must keep decoding. When someone raises
    /// `currentVersion`, this test is what fails if v1 quietly stopped being readable.
    func testCheckedInV1ArchiveStillPreviewsAndRestores() async throws {
        let context = try makeBackupServiceContext()
        let data = try Data(contentsOf: Self.v1FixtureURL)

        let preview = try context.service.previewBackup(data: data)
        XCTAssertEqual(preview.archiveVersion, 1)
        XCTAssertEqual(preview.workoutCount, 2)
        XCTAssertEqual(preview.exerciseCount, 2)
        XCTAssertEqual(preview.setCount, 4)

        let result = try await context.service.restoreBackup(data: data)
        XCTAssertEqual(result.workoutsRestored, 2)
        XCTAssertEqual(result.exercisesUpserted, 2)
        XCTAssertEqual(result.setsRestored, 4)
        XCTAssertFalse(result.hasSkippedLearningData)

        let restoredSets = try await context.setRepo.fetchSets(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(restoredSets.count, 4)
        XCTAssertEqual(restoredSets.compactMap(\.reps).sorted(), [5, 5, 10, 12])

        let profile = try await context.healthProfileRepo.fetchOrCreate()
        XCTAssertEqual(profile.prescriptionLearnedFatigueRate, 0.042)
        XCTAssertEqual(profile.prescriptionFatigueLearningSessionCount, 7)
    }

    /// Pins the archive's ordering contract, which is otherwise only implied by the three
    /// fetch-then-re-sort pipelines in `exportBackup()`.
    ///
    /// Written to guard the Phase 1 read-path refactor: moving those fetches onto a single
    /// `ModelContext` must not reorder anyone's backup. Every case here is a *near*-tie resolved by
    /// the comparator's next key — never a true tie, because `Array.sorted(by:)` is not stable and
    /// pinning an unspecified order would only produce a flaky test.
    func testExportBackupOrderingContract() async throws {
        let context = try makeBackupServiceContext()

        // Saved in an order no sort would reproduce, and cased so a case-*sensitive* sort would put
        // "Zercher Squat" before "bench press".
        let zercher = Exercise(name: "Zercher Squat", equipmentType: .barbell, trackingType: .weightReps)
        let bench = Exercise(name: "bench press", equipmentType: .barbell, trackingType: .weightReps)
        let abWheel = Exercise(name: "Ab Wheel", equipmentType: .other, trackingType: .weightReps)
        try await context.exerciseRepo.save(zercher)
        try await context.exerciseRepo.save(bench)
        try await context.exerciseRepo.save(abWheel)

        // Same date, so only the createdAt tiebreak can separate them — and saved late-first.
        let sharedDate = makeDate(2026, 4, 10, 6, 0)
        let late = Workout(
            date: sharedDate,
            title: "Day1 Late",
            status: .completed,
            createdAt: makeDate(2026, 4, 10, 10, 0),
            updatedAt: makeDate(2026, 4, 10, 10, 0)
        )
        let early = Workout(
            date: sharedDate,
            title: "Day1 Early",
            status: .completed,
            createdAt: makeDate(2026, 4, 10, 9, 0),
            updatedAt: makeDate(2026, 4, 10, 9, 0)
        )
        let nextDay = Workout(
            date: makeDate(2026, 4, 11, 6, 0),
            title: "Day2",
            status: .completed,
            createdAt: makeDate(2026, 4, 11, 9, 0),
            updatedAt: makeDate(2026, 4, 11, 9, 0)
        )
        try await context.workoutRepo.save(late)
        try await context.workoutRepo.save(early)
        try await context.workoutRepo.save(nextDay)

        // Each workout's sets are saved with orderInWorkout descending, so insertion order and
        // archive order disagree.
        for (workout, label) in [(early, "early"), (late, "late"), (nextDay, "day2")] {
            for order in [2, 1] {
                try await context.setRepo.save(
                    WorkoutSet(
                        workoutId: workout.id,
                        exerciseId: bench.id,
                        date: workout.date,
                        weight: 100,
                        effectiveWeight: 100,
                        reps: 5,
                        setType: .working,
                        notes: "\(label)-\(order)",
                        orderInWorkout: order,
                        orderInExercise: order,
                        completed: true
                    )
                )
            }
        }

        let archive = try decodeBackupArchive(try await context.service.exportBackup())

        XCTAssertEqual(archive.exercises.map(\.name), ["Ab Wheel", "bench press", "Zercher Squat"])
        XCTAssertEqual(archive.workouts.map(\.title), ["Day1 Early", "Day1 Late", "Day2"])
        XCTAssertEqual(
            archive.sets.compactMap(\.notes),
            ["early-1", "early-2", "late-1", "late-2", "day2-1", "day2-2"]
        )
    }

    func testExportBackupIncludesExercisesWithNoLoggedSets() async throws {
        let context = try makeBackupServiceContext()

        let trained = Exercise(
            name: "Barbell Row",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        // Built in the library but never trained — the case that used to be dropped on export and
        // so vanished when restoring onto a new device.
        let untrained = Exercise(
            name: "Zercher Squat",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        try await context.exerciseRepo.save(trained)
        try await context.exerciseRepo.save(untrained)

        let workoutDate = makeDate(2026, 4, 2, 7, 0)
        let workout = Workout(
            date: workoutDate,
            title: "Pull",
            startTime: workoutDate,
            status: .completed
        )
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(
            WorkoutSet(
                workoutId: workout.id,
                exerciseId: trained.id,
                date: workoutDate,
                weight: 80,
                effectiveWeight: 80,
                reps: 8,
                setType: .working,
                orderInWorkout: 0,
                orderInExercise: 0,
                completed: true
            )
        )

        let archive = try decodeBackupArchive(try await context.service.exportBackup())

        XCTAssertEqual(archive.exercises.map(\.name), ["Barbell Row", "Zercher Squat"])
        XCTAssertTrue(
            archive.exercises.contains { $0.id == untrained.id },
            "An exercise with no logged sets must still be backed up"
        )
    }

    func testRestoreBackupRejectsArchiveWithSetReferencingMissingWorkout() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(
            name: "Split Squat",
            equipmentType: .dumbbell,
            trackingType: .weightReps
        )
        let workoutDate = makeDate(2026, 3, 23, 7, 0)
        let workout = Workout(
            date: workoutDate,
            title: "Leg Day",
            startTime: workoutDate,
            endTime: makeDate(2026, 3, 23, 8, 0),
            duration: 3600,
            status: .completed
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            weight: 20,
            effectiveWeight: 20,
            reps: 10,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)

        let archive = try decodeBackupArchive(try await context.service.exportBackup())
        let invalidArchive = WorkoutHistoryArchive(
            version: archive.version,
            exportedAt: archive.exportedAt,
            workouts: [],
            exercises: archive.exercises,
            sets: archive.sets,
            fatigueObservations: archive.fatigueObservations,
            fatigueLearningAudits: archive.fatigueLearningAudits,
            healthProfileLearning: archive.healthProfileLearning
        )

        do {
            _ = try await context.service.restoreBackup(data: try encodeBackupArchive(invalidArchive))
            XCTFail("Expected invalid archive to fail")
        } catch let error as WorkoutHistoryBackupError {
            guard case .invalidArchive(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("references a missing workout"))
        }
    }

    func testWorkoutServiceDeleteWorkoutRemovesCapturedLearningData() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        let workoutDate = makeDate(2026, 3, 24, 18, 0)
        let workout = Workout(
            date: workoutDate,
            title: "Push",
            startTime: workoutDate,
            endTime: makeDate(2026, 3, 24, 19, 0),
            duration: 3600,
            status: .completed
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            weight: 100,
            effectiveWeight: 100,
            reps: 5,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)
        let learningContext = ModelContext(context.modelContainer)
        _ = try insertLearningRecords(
            into: learningContext,
            exerciseId: exercise.id,
            workoutId: workout.id,
            setId: set.id,
            createdAt: makeDate(2026, 3, 24, 18, 20)
        )
        try learningContext.save()

        try await context.workoutService.deleteWorkout(workout.id)

        let verificationContext = ModelContext(context.modelContainer)
        let remainingWorkouts = try await context.workoutRepo.fetchAllWorkouts(limit: nil, offset: nil)
        let remainingSets = try await context.setRepo.fetchSets(from: .distantPast, to: .distantFuture)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<FatigueObservation>()).isEmpty)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<FatigueLearningSetAudit>()).isEmpty)
        XCTAssertTrue(remainingWorkouts.isEmpty)
        XCTAssertTrue(remainingSets.isEmpty)
    }

    func testHomeViewModelReloadRemovesDeletedWorkoutFromRecentWorkouts() async throws {
        let context = try makeBackupServiceContext()
        let homeSectionConfigKey = "homeSectionConfig"
        let originalHomeSectionConfig = UserDefaults.standard.data(forKey: homeSectionConfigKey)
        UserDefaults.standard.removeObject(forKey: homeSectionConfigKey)
        defer {
            if let originalHomeSectionConfig {
                UserDefaults.standard.set(originalHomeSectionConfig, forKey: homeSectionConfigKey)
            } else {
                UserDefaults.standard.removeObject(forKey: homeSectionConfigKey)
            }
        }

        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        try await context.exerciseRepo.save(exercise)

        let calendar = Calendar.current
        let newerDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: Date()))
        let olderDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: Date()))

        let newerWorkout = Workout(
            date: newerDate,
            title: "Newest Session",
            startTime: newerDate,
            endTime: try XCTUnwrap(calendar.date(byAdding: .minute, value: 55, to: newerDate)),
            duration: 3300,
            status: .completed
        )
        let olderWorkout = Workout(
            date: olderDate,
            title: "Older Session",
            startTime: olderDate,
            endTime: try XCTUnwrap(calendar.date(byAdding: .minute, value: 45, to: olderDate)),
            duration: 2700,
            status: .completed
        )
        try await context.workoutRepo.save(newerWorkout)
        try await context.workoutRepo.save(olderWorkout)

        try await context.setRepo.save(
            WorkoutSet(
                workoutId: newerWorkout.id,
                exerciseId: exercise.id,
                date: newerDate,
                weight: 100,
                effectiveWeight: 100,
                reps: 5,
                setType: .working,
                orderInWorkout: 1,
                orderInExercise: 1,
                completed: true
            )
        )
        try await context.setRepo.save(
            WorkoutSet(
                workoutId: olderWorkout.id,
                exerciseId: exercise.id,
                date: olderDate,
                weight: 90,
                effectiveWeight: 90,
                reps: 8,
                setType: .working,
                orderInWorkout: 1,
                orderInExercise: 1,
                completed: true
            )
        )

        let viewModel = HomeViewModel(
            workoutService: context.workoutService,
            setService: context.setService,
            exerciseService: context.exerciseService,
            chartDataService: context.chartDataService,
            statsService: context.statsService
        )

        await viewModel.loadData()

        XCTAssertEqual(viewModel.recentWorkouts.map(\.id), [newerWorkout.id, olderWorkout.id])

        try await context.workoutService.deleteWorkout(newerWorkout.id)

        viewModel.lastLoadTime = nil
        await viewModel.loadData()

        XCTAssertEqual(viewModel.recentWorkouts.map(\.id), [olderWorkout.id])
        XCTAssertEqual(viewModel.recentWorkouts.count, 1)
    }

    func testExerciseServiceDeleteExerciseRemovesCapturedLearningData() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(
            name: "Lat Pulldown",
            equipmentType: .machinePin,
            trackingType: .weightReps
        )
        let workoutDate = makeDate(2026, 3, 25, 17, 0)
        let workout = Workout(
            date: workoutDate,
            title: "Pull",
            startTime: workoutDate,
            endTime: makeDate(2026, 3, 25, 18, 0),
            duration: 3600,
            status: .completed
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            weight: 75,
            effectiveWeight: 75,
            reps: 8,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)
        let learningContext = ModelContext(context.modelContainer)
        _ = try insertLearningRecords(
            into: learningContext,
            exerciseId: exercise.id,
            workoutId: workout.id,
            setId: set.id,
            createdAt: makeDate(2026, 3, 25, 17, 25)
        )
        try learningContext.save()

        try await context.exerciseService.deleteExercise(exercise.id)

        let verificationContext = ModelContext(context.modelContainer)
        let deletedExercise = try await context.exerciseRepo.fetch(byId: exercise.id)
        let remainingSets = try await context.setRepo.fetchSets(from: .distantPast, to: .distantFuture)
        let survivingWorkout = try await context.workoutRepo.fetch(byId: workout.id)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<FatigueObservation>()).isEmpty)
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<FatigueLearningSetAudit>()).isEmpty)
        XCTAssertNil(deletedExercise)
        XCTAssertTrue(remainingSets.isEmpty)
        XCTAssertNotNil(survivingWorkout)
    }

    /// Checked in, unlike `Fixtures/Local/` — this one is synthetic precisely so it can live in a
    /// public repo and survive as a format guard.
    private static let v1FixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/archive-v1.repsterbackup")

    private func makeEmptyArchive(version: Int) -> WorkoutHistoryArchive {
        WorkoutHistoryArchive(
            version: version,
            exportedAt: Date(),
            workouts: [],
            exercises: [],
            sets: [],
            fatigueObservations: nil,
            fatigueLearningAudits: nil,
            healthProfileLearning: nil
        )
    }

    // MARK: - Templates in the archive (v2) — TEMPLATES_IMPLEMENTATION_PLAN.md D1

    /// The most important test in the templates plan.
    ///
    /// Restore is a replace, not a merge, and every backup a user owns today is v1. If a v1 archive's
    /// absent `templates` key were ever defaulted to `[]`, restoring an old backup would delete every
    /// template the user has. Absent must mean "this file says nothing about templates".
    func testRestoringV1ArchiveLeavesExistingTemplatesUntouched() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps)
        try await context.exerciseRepo.save(exercise)

        let templateId = try await context.templateService.createTemplate(
            TemplateSaveData(
                name: "Push Day A",
                notes: nil,
                folder: "Mesocycle 3",
                exercises: [
                    TemplateSaveExercise(
                        exerciseId: exercise.id,
                        orderInTemplate: 1,
                        supersetGroupId: nil,
                        restTimeSeconds: nil,
                        notes: nil,
                        sets: [
                            TemplateSaveSet(setType: .working, targetRepMin: 6, targetRepMax: 8, targetRIR: 2, orderInExercise: 1)
                        ]
                    )
                ]
            )
        )

        // A v1 archive: valid, decodable, and with no `templates` key at all.
        let legacyArchive = """
        {
          "version": 1,
          "exportedAt": "2026-01-01T00:00:00Z",
          "workouts": [],
          "exercises": [],
          "sets": []
        }
        """
        let result = try await context.service.restoreBackup(data: Data(legacyArchive.utf8))

        XCTAssertNil(result.templatesRestored, "A v1 archive did not describe templates, so none were restored")

        let surviving = try await context.templateService.fetchAllTemplates()
        XCTAssertEqual(surviving.count, 1, "Restoring a v1 backup must not delete the user's templates")
        XCTAssertEqual(surviving.first?.id, templateId)
        XCTAssertEqual(surviving.first?.name, "Push Day A")
        XCTAssertEqual(surviving.first?.folder, "Mesocycle 3")

        let detail = try await context.templateService.fetchTemplateDetail(templateId)
        XCTAssertEqual(detail?.exercises.count, 1)
        XCTAssertEqual(detail?.exercises.first?.sets.count, 1)
    }

    /// The other half of the contract: a v2 archive that genuinely holds no templates clears them.
    func testRestoringV2ArchiveWithEmptyTemplatesClearsThem() async throws {
        let context = try makeBackupServiceContext()
        let exercise = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps)
        try await context.exerciseRepo.save(exercise)
        _ = try await context.templateService.createTemplate(
            TemplateSaveData(name: "Push Day A", notes: nil, exercises: [])
        )

        let emptyArchive = """
        {
          "version": 2,
          "exportedAt": "2026-01-01T00:00:00Z",
          "workouts": [],
          "exercises": [],
          "sets": [],
          "templates": []
        }
        """
        let result = try await context.service.restoreBackup(data: Data(emptyArchive.utf8))

        XCTAssertEqual(result.templatesRestored, 0)
        let surviving = try await context.templateService.fetchAllTemplates()
        XCTAssertTrue(surviving.isEmpty)
    }

    func testBackupRoundTripsTemplatesWithFoldersAndSupersetGroups() async throws {
        let context = try makeBackupServiceContext()
        let fly = Exercise(name: "Cable Fly", equipmentType: .cable, trackingType: .weightReps)
        let raise = Exercise(name: "Lateral Raise", equipmentType: .dumbbell, trackingType: .weightReps)
        try await context.exerciseRepo.save(fly)
        try await context.exerciseRepo.save(raise)

        let groupId = UUID()
        _ = try await context.templateService.createTemplate(
            TemplateSaveData(
                name: "Push Day A",
                notes: "top set then back off",
                folder: "Mesocycle 3",
                exercises: [
                    TemplateSaveExercise(
                        exerciseId: fly.id, orderInTemplate: 1, supersetGroupId: groupId,
                        restTimeSeconds: 90, notes: "slow eccentric",
                        sets: [TemplateSaveSet(setType: .working, targetRepMin: 12, targetRepMax: 15, targetRIR: 1, orderInExercise: 1)]
                    ),
                    TemplateSaveExercise(
                        exerciseId: raise.id, orderInTemplate: 2, supersetGroupId: groupId,
                        restTimeSeconds: nil, notes: nil,
                        sets: [
                            TemplateSaveSet(setType: .warmup, targetRepMin: nil, targetRepMax: nil, targetRIR: nil, orderInExercise: 1),
                            TemplateSaveSet(setType: .working, targetRepMin: 12, targetRepMax: 15, targetRIR: 1, orderInExercise: 2)
                        ]
                    )
                ]
            )
        )

        let data = try await context.service.exportBackup()
        let archive = try decodeBackupArchive(data)
        XCTAssertEqual(archive.version, 2)
        XCTAssertEqual(archive.templates?.count, 1)

        // Wipe, then restore.
        let restored = try await context.service.restoreBackup(data: data)
        XCTAssertEqual(restored.templatesRestored, 1)

        let templates = try await context.templateService.fetchAllTemplates()
        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates.first?.folder, "Mesocycle 3")
        XCTAssertEqual(templates.first?.notes, "top set then back off")

        let firstId = try XCTUnwrap(templates.first?.id)
        let fetchedDetail = try await context.templateService.fetchTemplateDetail(firstId)
        let detail = try XCTUnwrap(fetchedDetail)
        XCTAssertEqual(detail.exercises.count, 2)
        XCTAssertEqual(detail.exercises.map(\.exerciseName), ["Cable Fly", "Lateral Raise"])
        XCTAssertEqual(Set(detail.exercises.compactMap(\.supersetGroupId)), [groupId])
        XCTAssertEqual(detail.exercises[0].restTimeSeconds, 90)
        XCTAssertEqual(detail.exercises[0].notes, "slow eccentric")
        XCTAssertEqual(detail.exercises[1].sets.count, 2)
        XCTAssertEqual(detail.exercises[1].sets.first?.setType, .warmup)
    }

    func testRestoredTemplateKeepsAnExerciseReferenceThatNoLongerResolves() async throws {
        // D4: restore upserts exercises but never deletes them, so an archived template can point at
        // one that is not present. Keep the row — it renders as "Unknown Exercise" — rather than
        // quietly dropping an exercise out of the user's template.
        let context = try makeBackupServiceContext()
        let ghostId = UUID()
        let archiveJSON = """
        {
          "version": 2,
          "exportedAt": "2026-01-01T00:00:00Z",
          "workouts": [],
          "exercises": [],
          "sets": [],
          "templates": [
            {
              "id": "\(UUID().uuidString)",
              "name": "Ghost",
              "notes": null,
              "folder": null,
              "lastUsedAt": null,
              "createdAt": "2026-01-01T00:00:00Z",
              "updatedAt": "2026-01-01T00:00:00Z",
              "exercises": [
                {
                  "id": "\(UUID().uuidString)",
                  "exerciseId": "\(ghostId.uuidString)",
                  "orderInTemplate": 1,
                  "supersetGroupId": null,
                  "restTimeSeconds": null,
                  "notes": null,
                  "createdAt": "2026-01-01T00:00:00Z",
                  "updatedAt": "2026-01-01T00:00:00Z",
                  "sets": [
                    {
                      "id": "\(UUID().uuidString)",
                      "setType": "working",
                      "targetRepMin": 8,
                      "targetRepMax": 10,
                      "targetRIR": 2,
                      "orderInExercise": 1,
                      "createdAt": "2026-01-01T00:00:00Z",
                      "updatedAt": "2026-01-01T00:00:00Z"
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let result = try await context.service.restoreBackup(data: Data(archiveJSON.utf8))
        XCTAssertEqual(result.templatesRestored, 1)

        let templates = try await context.templateService.fetchAllTemplates()
        let firstId = try XCTUnwrap(templates.first?.id)
        let fetchedDetail = try await context.templateService.fetchTemplateDetail(firstId)
        let detail = try XCTUnwrap(fetchedDetail)
        XCTAssertEqual(detail.exercises.count, 1)
        XCTAssertEqual(detail.exercises.first?.exerciseName, "Unknown Exercise")
    }

    func testPreviewReportsNoTemplateCountForV1Archive() async throws {
        let context = try makeBackupServiceContext()
        let legacyArchive = """
        {"version":1,"exportedAt":"2026-01-01T00:00:00Z","workouts":[],"exercises":[],"sets":[]}
        """
        let preview = try context.service.previewBackup(data: Data(legacyArchive.utf8))
        XCTAssertEqual(preview.archiveVersion, 1)
        XCTAssertNil(preview.templateCount, "v1 says nothing about templates, which is not the same as zero")
    }

    private func makeBackupServiceContext() throws -> WorkoutHistoryBackupArchiveTestContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self,
            Workout.self,
            WorkoutSet.self,
            ExerciseStats.self,
            PerformanceRecord.self,
            BodyweightEntry.self,
            HealthProfile.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateSet.self,
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
        let templateRepo = TemplateRepository(modelContainer: container)
        let fatigueObservationRepo = FatigueObservationRepository(modelContainer: container)
        let fatigueLearningAuditRepo = FatigueLearningSetAuditRepository(modelContainer: container)

        let statsService = StatsService(
            exerciseStatsRepository: exerciseStatsRepo,
            setRepository: setRepo,
            exerciseRepository: exerciseRepo,
            healthProfileRepository: healthProfileRepo,
            performanceRecordRepository: performanceRecordRepo
        )
        let chartDataService = ChartDataService(
            setRepository: setRepo,
            workoutRepository: workoutRepo,
            exerciseRepository: exerciseRepo,
            exerciseStatsRepository: exerciseStatsRepo,
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
        let workoutService = WorkoutService(
            workoutRepository: workoutRepo,
            setRepository: setRepo,
            prService: prService,
            statsService: statsService,
            fatigueLearningService: fatigueLearningService,
            bodyweightService: BodyweightService(
                bodyweightEntryRepository: bodyweightRepo,
                healthProfileRepository: healthProfileRepo
            ),
            healthKitService: NoopHealthKitService()
        )
        let exerciseService = ExerciseService(
            exerciseRepository: exerciseRepo,
            setRepository: setRepo,
            exerciseStatsRepository: exerciseStatsRepo,
            performanceRecordRepository: performanceRecordRepo,
            templateRepository: templateRepo,
            prService: prService,
            statsService: statsService,
            fatigueLearningService: fatigueLearningService
        )
        let templateService = TemplateService(
            templateRepository: templateRepo,
            workoutRepository: workoutRepo,
            setRepository: setRepo,
            exerciseRepository: exerciseRepo
        )
        let service = WorkoutHistoryBackupService(
            statsService: statsService,
            prService: prService,
            modelContainer: container
        )

        return WorkoutHistoryBackupArchiveTestContext(
            modelContainer: container,
            service: service,
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService,
            chartDataService: chartDataService,
            statsService: statsService,
            templateService: templateService,
            exerciseRepo: exerciseRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo,
            templateRepo: templateRepo,
            exerciseStatsRepo: exerciseStatsRepo,
            performanceRecordRepo: performanceRecordRepo,
            bodyweightRepo: bodyweightRepo,
            healthProfileRepo: healthProfileRepo
        )
    }

    private func decodeBackupArchive(_ data: Data) throws -> WorkoutHistoryArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkoutHistoryArchive.self, from: data)
    }

    private func encodeBackupArchive(_ archive: WorkoutHistoryArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
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

@MainActor
final class WorkoutHistoryBackupArchiveViewModelTests: XCTestCase {
    func testSettingsDataDestinationLabelsMatchBackupFlow() {
        XCTAssertEqual(
            SettingsDataDestination.allCases.map(\.title),
            ["Import Data (CSV)", "Export Backup", "Restore Backup", "Reset App Data"]
        )
        XCTAssertEqual(
            SettingsDataDestination.allCases.map(\.systemImage),
            ["square.and.arrow.down", "square.and.arrow.up", "arrow.clockwise.circle", "trash"]
        )
    }

    func testExportViewModelCreatesShareItemAfterSuccessfulExport() async throws {
        let service = BackupServiceStub()
        let viewModel = ExportViewModel(workoutHistoryBackupService: service)

        viewModel.generateExport()

        try await waitUntilOnMainActor {
            viewModel.shareItem != nil && viewModel.isExporting == false
        }

        let shareURL = try XCTUnwrap(viewModel.shareItem?.url)
        XCTAssertEqual(shareURL.pathExtension, "repsterbackup")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testExportViewModelSweepsPreviousTemporaryFiles() async throws {
        let service = BackupServiceStub()
        let viewModel = ExportViewModel(workoutHistoryBackupService: service)
        let fileManager = FileManager.default

        viewModel.generateExport()
        try await waitUntilOnMainActor { viewModel.shareItem != nil && viewModel.isExporting == false }
        let directory = try XCTUnwrap(viewModel.shareItem?.url).deletingLastPathComponent()

        // Planted rather than produced by a second export: the filename is stamped to the second,
        // so two exports inside the same second reuse one name and would hide an absent sweep.
        let stale = directory.appendingPathComponent("stale-export.repsterbackup")
        try Data("stale".utf8).write(to: stale)

        viewModel.generateExport()
        try await waitUntilOnMainActor { viewModel.shareItem != nil && viewModel.isExporting == false }
        let currentURL = try XCTUnwrap(viewModel.shareItem?.url)

        // Exports used to accumulate in tmp forever — ~7 MB apiece for a large history.
        XCTAssertFalse(fileManager.fileExists(atPath: stale.path))
        XCTAssertTrue(fileManager.fileExists(atPath: currentURL.path))
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count,
            1
        )
    }

    func testRestoreBackupViewModelPreviewsBeforeConfirmation() throws {
        let service = BackupServiceStub()
        let viewModel = RestoreBackupViewModel(workoutHistoryBackupService: service)
        let fileURL = try makeBackupFileURL()

        viewModel.handleFileSelected(.success(fileURL))

        XCTAssertEqual(viewModel.state, .previewing)
        XCTAssertEqual(viewModel.preview?.workoutCount, 2)
        viewModel.confirmRestore()
        XCTAssertTrue(viewModel.showReplaceConfirmation)
    }

    func testRestoreBackupViewModelCompletesRestoreAfterConfirmation() async throws {
        let service = BackupServiceStub()
        let viewModel = RestoreBackupViewModel(workoutHistoryBackupService: service)
        let fileURL = try makeBackupFileURL()

        viewModel.handleFileSelected(.success(fileURL))
        viewModel.performRestore()

        try await waitUntilOnMainActor {
            viewModel.state == .completed
        }

        XCTAssertEqual(service.restoreCallCount, 1)
        XCTAssertEqual(viewModel.result?.workoutsRestored, 2)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRestoreBackupViewModelCompletesWithWarningCountsAfterConfirmation() async throws {
        let service = BackupServiceStub()
        service.restoreResult = WorkoutHistoryRestoreResult(
            workoutsRestored: 2,
            exercisesUpserted: 1,
            setsRestored: 3,
            skippedFatigueObservations: 2,
            skippedFatigueLearningAudits: 1,
            duration: 0.4
        )
        let viewModel = RestoreBackupViewModel(workoutHistoryBackupService: service)
        let fileURL = try makeBackupFileURL()

        viewModel.handleFileSelected(.success(fileURL))
        viewModel.performRestore()

        try await waitUntilOnMainActor {
            viewModel.state == .completed
        }

        XCTAssertEqual(viewModel.result?.skippedFatigueObservations, 2)
        XCTAssertEqual(viewModel.result?.skippedFatigueLearningAudits, 1)
        XCTAssertNotNil(viewModel.result?.learningDataWarningMessage)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func makeBackupFileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("repsterbackup")
        try Data("backup".utf8).write(to: url, options: .atomic)
        return url
    }
}

final class RepsterDocumentTypeRegistrationTests: XCTestCase {
    func testCurrentAndLegacyFilenameExtensionsResolveToRegisteredTypes() throws {
        let repsterBackupType = try XCTUnwrap(UTType(filenameExtension: "repsterbackup"))
        let repsterTemplateType = try XCTUnwrap(UTType(filenameExtension: "repstertemplate"))
        let legacyBackupType = try XCTUnwrap(UTType(filenameExtension: "reppobackup"))
        let legacyTemplateType = try XCTUnwrap(UTType(filenameExtension: "reppotemplate"))

        XCTAssertEqual(repsterBackupType.identifier, "com.magnusespensen.repster.workout-history")
        XCTAssertEqual(repsterTemplateType.identifier, "com.magnusespensen.repster.template")
        XCTAssertEqual(legacyBackupType.identifier, "com.magnusespensen.reppo.workout-history")
        XCTAssertEqual(legacyTemplateType.identifier, "com.magnusespensen.reppo.template")
        XCTAssertTrue(repsterBackupType.conforms(to: .json))
        XCTAssertTrue(repsterTemplateType.conforms(to: .json))
        XCTAssertTrue(legacyBackupType.conforms(to: .json))
        XCTAssertTrue(legacyTemplateType.conforms(to: .json))
    }
}

@MainActor
final class SettingsViewModelSummaryTests: XCTestCase {
    func testWorkoutPreferencesSummaryUsesCompactOverviewCopy() {
        let viewModel = SettingsViewModel(settingsService: NoOpSettingsService())
        let profile = HealthProfile(
            includeWarmupsInVolume: false,
            includeWarmupsInPRs: false,
            defaultRestTimeSeconds: 150,
            restTimerAlert: "both"
        )
        viewModel.profile = profile

        XCTAssertEqual(
            viewModel.workoutPreferencesSummary,
            "Rest 2:30 • Alerts Both • Warmups excluded"
        )
    }

    func testWorkoutPreferencesSummaryHandlesMixedWarmupRules() {
        let viewModel = SettingsViewModel(settingsService: NoOpSettingsService())
        let profile = HealthProfile(
            includeWarmupsInVolume: true,
            includeWarmupsInPRs: false,
            defaultRestTimeSeconds: 180,
            restTimerAlert: "sound"
        )
        viewModel.profile = profile

        XCTAssertEqual(
            viewModel.workoutPreferencesSummary,
            "Rest 3:00 • Alerts Sound • Warmups in volume only"
        )
    }

    func testSmartSuggestionsSummaryReflectsEnabledStateAndIncrement() {
        let viewModel = SettingsViewModel(settingsService: NoOpSettingsService())
        let enabledProfile = HealthProfile(
            prescriptionEnabled: true,
            prescriptionDefaultIncrement: 1.25
        )
        viewModel.profile = enabledProfile
        XCTAssertEqual(viewModel.smartSuggestionsSummary, "On • 1.25 kg")

        enabledProfile.prescriptionEnabled = false
        viewModel.profile = enabledProfile
        XCTAssertEqual(viewModel.smartSuggestionsSummary, "Off")
    }
}

final class SettingsResetServiceTests: XCTestCase {
    func testResetAllAppDataClearsLocalDataRestoresDefaultsAndReseedsExercises() async throws {
        let context = try makeResetContext()
        let timestamp = Date(timeIntervalSince1970: 1_710_000_000)

        let profile = try await context.healthProfileRepo.fetchOrCreate()
        profile.unitPreference = .imperial
        profile.e1RMFormula = "brzycki"
        profile.defaultRestTimeSeconds = 240
        try await context.healthProfileRepo.save(profile)

        let customExercise = Exercise(
            name: "Custom Safety Bar Squat",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "legs"
        )
        try await context.exerciseRepo.save(customExercise)

        let workout = Workout(
            date: timestamp,
            title: "Reset Target",
            status: .completed
        )
        try await context.workoutRepo.save(workout)

        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: customExercise.id,
            date: timestamp,
            weight: 100,
            effectiveWeight: 100,
            reps: 5,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        try await context.setRepo.save(set)

        let writeContext = ModelContext(context.modelContainer)
        writeContext.insert(
            ExerciseStats(
                exerciseId: customExercise.id,
                totalWorkouts: 1,
                totalSets: 1,
                totalReps: 5,
                totalVolume: 500
            )
        )
        writeContext.insert(
            PerformanceRecord(
                exerciseId: customExercise.id,
                recordType: .e1RM,
                value: 120,
                setId: set.id,
                date: timestamp
            )
        )
        writeContext.insert(
            BodyweightEntry(
                healthProfileId: profile.id,
                date: timestamp,
                bodyweightKg: 82.4
            )
        )

        let program = Program(name: "Strength Block")
        writeContext.insert(program)
        writeContext.insert(ProgramExercise(programId: program.id, exerciseId: customExercise.id))

        let plannedWorkout = PlannedWorkout(programId: program.id, weekIndex: 1)
        writeContext.insert(plannedWorkout)
        writeContext.insert(
            PlannedSet(
                plannedWorkoutId: plannedWorkout.id,
                exerciseId: customExercise.id,
                targetReps: 5,
                targetWeight: 102.5,
                targetRPE: 8,
                orderInWorkout: 1
            )
        )

        let template = WorkoutTemplate(name: "Push")
        writeContext.insert(template)
        let templateExercise = TemplateExercise(
            templateId: template.id,
            exerciseId: customExercise.id,
            orderInTemplate: 1
        )
        writeContext.insert(templateExercise)
        writeContext.insert(
            TemplateSet(
                templateExerciseId: templateExercise.id,
                setType: .working,
                targetRepMin: 8,
                targetRepMax: 10,
                targetRIR: 2,
                orderInExercise: 1
            )
        )
        try writeContext.save()

        context.userDefaults.set(Data("preset".utf8), forKey: "chartExercisePresets")
        context.userDefaults.set(timestamp, forKey: "restTimerStartDate")
        context.userDefaults.set(180, forKey: "restTimerTotalDuration")
        context.userDefaults.set(true, forKey: "hasCompletedOnboarding")

        try await context.settingsService.resetAllAppData()

        let verificationContext = ModelContext(context.modelContainer)
        let workouts = try verificationContext.fetch(FetchDescriptor<Workout>())
        let sets = try verificationContext.fetch(FetchDescriptor<WorkoutSet>())
        let stats = try verificationContext.fetch(FetchDescriptor<ExerciseStats>())
        let records = try verificationContext.fetch(FetchDescriptor<PerformanceRecord>())
        let bodyweightEntries = try verificationContext.fetch(FetchDescriptor<BodyweightEntry>())
        let programs = try verificationContext.fetch(FetchDescriptor<Program>())
        let programExercises = try verificationContext.fetch(FetchDescriptor<ProgramExercise>())
        let plannedWorkouts = try verificationContext.fetch(FetchDescriptor<PlannedWorkout>())
        let plannedSets = try verificationContext.fetch(FetchDescriptor<PlannedSet>())
        let templates = try verificationContext.fetch(FetchDescriptor<WorkoutTemplate>())
        let templateExercises = try verificationContext.fetch(FetchDescriptor<TemplateExercise>())
        let templateSets = try verificationContext.fetch(FetchDescriptor<TemplateSet>())
        let exercises = try verificationContext.fetch(FetchDescriptor<Exercise>())
        let profiles = try verificationContext.fetch(FetchDescriptor<HealthProfile>())
        let defaultProfile = try XCTUnwrap(profiles.first)

        XCTAssertTrue(workouts.isEmpty)
        XCTAssertTrue(sets.isEmpty)
        XCTAssertTrue(stats.isEmpty)
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(bodyweightEntries.isEmpty)
        XCTAssertTrue(programs.isEmpty)
        XCTAssertTrue(programExercises.isEmpty)
        XCTAssertTrue(plannedWorkouts.isEmpty)
        XCTAssertTrue(plannedSets.isEmpty)
        XCTAssertTrue(templates.isEmpty)
        XCTAssertTrue(templateExercises.isEmpty)
        XCTAssertTrue(templateSets.isEmpty)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(defaultProfile.unitPreference, .metric)
        XCTAssertEqual(defaultProfile.e1RMFormula, "epley")
        XCTAssertEqual(defaultProfile.defaultRestTimeSeconds, 150)
        XCTAssertEqual(exercises.map(\.name), [context.seededExerciseName])
        XCTAssertFalse(exercises.contains(where: { $0.id == customExercise.id }))
        XCTAssertNil(context.userDefaults.object(forKey: "chartExercisePresets"))
        XCTAssertNil(context.userDefaults.object(forKey: "restTimerStartDate"))
        XCTAssertNil(context.userDefaults.object(forKey: "restTimerTotalDuration"))
        XCTAssertEqual(context.userDefaults.bool(forKey: "hasCompletedOnboarding"), true)
    }

    func testResetAllAppDataIsIdempotentWhenStoreIsAlreadyEmpty() async throws {
        let context = try makeResetContext()
        context.userDefaults.set(true, forKey: "hasCompletedOnboarding")

        try await context.settingsService.resetAllAppData()
        try await context.settingsService.resetAllAppData()

        let verificationContext = ModelContext(context.modelContainer)
        let profiles = try verificationContext.fetch(FetchDescriptor<HealthProfile>())
        let exercises = try verificationContext.fetch(FetchDescriptor<Exercise>())

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.unitPreference, .metric)
        XCTAssertEqual(exercises.map(\.name), [context.seededExerciseName])
        XCTAssertEqual(context.userDefaults.bool(forKey: "hasCompletedOnboarding"), true)
    }
}

@MainActor
final class ResetAppDataViewModelTests: XCTestCase {
    func testResetViewModelDoesNotStartDeletionUntilConfirmed() {
        let service = ResetSettingsServiceStub()
        let viewModel = ResetAppDataViewModel(settingsService: service)

        viewModel.confirmReset()

        XCTAssertTrue(viewModel.showDeleteConfirmation)
        XCTAssertEqual(service.resetAllAppDataCallCount, 0)
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testResetViewModelTransitionsToCompletedAfterSuccessfulReset() async throws {
        let service = ResetSettingsServiceStub()
        var completionCallCount = 0
        let viewModel = ResetAppDataViewModel(
            settingsService: service,
            onResetComplete: {
                completionCallCount += 1
            }
        )

        viewModel.confirmReset()
        viewModel.performReset()

        XCTAssertEqual(viewModel.state, .resetting)
        XCTAssertFalse(viewModel.showDeleteConfirmation)

        try await waitUntilOnMainActor {
            viewModel.state == .completed
        }

        XCTAssertEqual(service.resetAllAppDataCallCount, 1)
        XCTAssertEqual(completionCallCount, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testResetViewModelTransitionsToFailedWhenResetThrows() async throws {
        let service = ResetSettingsServiceStub()
        service.resetError = TestResetError.failed
        let viewModel = ResetAppDataViewModel(settingsService: service)

        viewModel.performReset()

        try await waitUntilOnMainActor {
            viewModel.state == .failed
        }

        XCTAssertEqual(service.resetAllAppDataCallCount, 1)
        XCTAssertEqual(viewModel.errorMessage, TestResetError.failed.localizedDescription)
    }
}

private struct WorkoutHistoryBackupArchiveTestContext {
    let modelContainer: ModelContainer
    let service: WorkoutHistoryBackupService
    let workoutService: WorkoutService
    let setService: SetService
    let exerciseService: ExerciseService
    let chartDataService: ChartDataService
    let statsService: StatsService
    let templateService: TemplateService
    let exerciseRepo: ExerciseRepository
    let workoutRepo: WorkoutRepository
    let setRepo: SetRepository
    let templateRepo: TemplateRepository
    let exerciseStatsRepo: ExerciseStatsRepository
    let performanceRecordRepo: PerformanceRecordRepository
    let bodyweightRepo: BodyweightEntryRepository
    let healthProfileRepo: HealthProfileRepository
}

private struct SettingsResetTestContext {
    let modelContainer: ModelContainer
    let settingsService: SettingsService
    let exerciseRepo: ExerciseRepository
    let workoutRepo: WorkoutRepository
    let setRepo: SetRepository
    let healthProfileRepo: HealthProfileRepository
    let userDefaults: UserDefaults
    let seededExerciseName: String
}

private final class BackupServiceStub: @unchecked Sendable, WorkoutHistoryBackupServiceProtocol {
    var exportData = Data("backup".utf8)
    var previewResult = WorkoutHistoryBackupPreview(
        archiveVersion: WorkoutHistoryArchive.currentVersion,
        exportedAt: Date(),
        workoutCount: 2,
        exerciseCount: 1,
        setCount: 3,
        earliestWorkoutDate: Date(timeIntervalSince1970: 1_710_000_000),
        latestWorkoutDate: Date(timeIntervalSince1970: 1_710_086_400)
    )
    var restoreResult = WorkoutHistoryRestoreResult(
        workoutsRestored: 2,
        exercisesUpserted: 1,
        setsRestored: 3,
        skippedFatigueObservations: 0,
        skippedFatigueLearningAudits: 0,
        duration: 0.4
    )
    var restoreCallCount = 0

    func exportBackup() async throws -> Data {
        exportData
    }

    func previewBackup(data: Data) throws -> WorkoutHistoryBackupPreview {
        previewResult
    }

    func restoreBackup(data: Data) async throws -> WorkoutHistoryRestoreResult {
        restoreCallCount += 1
        return restoreResult
    }
}

private final class ResetSettingsServiceStub: @unchecked Sendable, SettingsServiceProtocol {
    var resetAllAppDataCallCount = 0
    var resetError: Error?

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
    func updatePrescriptionCapacityGuardsEnabled(_ enabled: Bool) async throws {}
    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws {}
    func updatePrescriptionAdminModeEnabled(_ enabled: Bool) async throws {}
    func resetAllAppData() async throws {
        resetAllAppDataCallCount += 1
        if let resetError {
            throw resetError
        }
    }
    func rebuildPRs() async throws {}
    func rebuildStats() async throws {}
    func rebuildAll() async throws {}
}

private enum TestResetError: LocalizedError {
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            return "Reset failed."
        }
    }
}

private func waitUntilOnMainActor(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(20),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while !(await condition()) {
        if clock.now >= deadline {
            XCTFail("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: pollInterval)
    }
}

private struct NoOpSettingsService: SettingsServiceProtocol {
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
    func updatePrescriptionCapacityGuardsEnabled(_ enabled: Bool) async throws {}
    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws {}
    func updatePrescriptionAdminModeEnabled(_ enabled: Bool) async throws {}
    func resetAllAppData() async throws {}
    func rebuildPRs() async throws {}
    func rebuildStats() async throws {}
    func rebuildAll() async throws {}
}

private func makeResetContext() throws -> SettingsResetTestContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Exercise.self,
        Workout.self,
        WorkoutSet.self,
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
        configurations: configuration
    )

    let exerciseRepo = ExerciseRepository(modelContainer: container)
    let workoutRepo = WorkoutRepository(modelContainer: container)
    let setRepo = SetRepository(modelContainer: container)
    let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
    let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
    let healthProfileRepo = HealthProfileRepository(modelContainer: container)
    let userDefaults = UserDefaults(suiteName: "SettingsResetServiceTests-\(UUID().uuidString)")!
    let seededExerciseName = "Seeded Bench Press"

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
    let settingsService = SettingsService(
        healthProfileRepository: healthProfileRepo,
        prService: prService,
        statsService: statsService,
        modelContainer: container,
        userDefaults: userDefaults,
        seedExercises: { context in
            guard ((try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0) == 0 else { return }
            context.insert(
                Exercise(
                    name: seededExerciseName,
                    equipmentType: .barbell,
                    trackingType: .weightReps,
                    primaryMuscle: "chest"
                )
            )
            try? context.save()
        }
    )

    return SettingsResetTestContext(
        modelContainer: container,
        settingsService: settingsService,
        exerciseRepo: exerciseRepo,
        workoutRepo: workoutRepo,
        setRepo: setRepo,
        healthProfileRepo: healthProfileRepo,
        userDefaults: userDefaults,
        seededExerciseName: seededExerciseName
    )
}

/// Backward/forward compatibility for the set type added to archived fatigue observations.
///
/// Archives are written by one app version and read by another — including older ones, since a
/// user can restore a new backup onto a device that has not updated. A field added here must
/// degrade to nil rather than failing the whole restore, which would cost the user their entire
/// history over one optional column.
///
/// Background: SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md G8.
final class FatigueObservationArchiveCompatibilityTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func archiveJSON(extraFields: String = "") -> Data {
        Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "exerciseId": "22222222-2222-2222-2222-222222222222",
          "workoutId": "33333333-3333-3333-3333-333333333333",
          "setId": "44444444-4444-4444-4444-444444444444",
          "setIndex": 1,
          "predictedEffectiveE1RM": 118.0,
          "actualE1RM": 115.0,
          "normalizedError": 0.02,
          "baseE1RM": 120.0,
          "prescribedWeight": 67.5,
          "actualWeight": 65.0,
          "actualReps": 10,
          "actualRIR": 0.0,
          "restDurationSeconds": 150,
          \(extraFields)
          "createdAt": "2026-03-22T08:25:00Z"
        }
        """.utf8)
    }

    /// An archive written before per-type instrumentation existed.
    func testLegacyArchiveWithoutSetTypeStillDecodes() throws {
        let observation = try decoder().decode(
            WorkoutHistoryArchiveFatigueObservation.self,
            from: archiveJSON()
        )

        XCTAssertNil(observation.setTypeRawValue, "absent means 'not captured', never a default type")
        XCTAssertEqual(observation.actualReps, 10, "the rest of the row must survive intact")
    }

    /// The reason this is a raw string and not `SetType?`: a backup written by a newer build may
    /// carry a set type this build has never heard of. It must not take the restore down.
    func testUnknownSetTypeFromANewerBuildDoesNotFailTheRestore() throws {
        let observation = try decoder().decode(
            WorkoutHistoryArchiveFatigueObservation.self,
            from: archiveJSON(extraFields: "\"setTypeRawValue\": \"someFutureType\",")
        )

        XCTAssertEqual(observation.setTypeRawValue, "someFutureType")
        XCTAssertNil(
            observation.setTypeRawValue.flatMap(SetType.init(rawValue:)),
            "an unrecognised type resolves to nil at the model boundary"
        )
    }

    func testEverySetTypeSurvivesAnArchiveRoundTrip() throws {
        for type in SetType.allCases {
            let decoded = try decoder().decode(
                WorkoutHistoryArchiveFatigueObservation.self,
                from: archiveJSON(extraFields: "\"setTypeRawValue\": \"\(type.rawValue)\",")
            )

            XCTAssertEqual(decoded.setTypeRawValue.flatMap(SetType.init(rawValue:)), type)
        }
    }

    /// The model side of the same contract: the accessor must never invent a type.
    func testObservationModelResolvesItsStoredRawValue() {
        let observation = FatigueObservation(
            exerciseId: UUID(),
            workoutId: UUID(),
            setId: UUID(),
            setIndex: 0,
            predictedEffectiveE1RM: 100,
            actualE1RM: 98,
            normalizedError: 0.02,
            baseE1RM: 100,
            prescribedWeight: 75,
            actualWeight: 75,
            actualReps: 8,
            actualRIR: 1,
            setType: .dropset
        )
        XCTAssertEqual(observation.setType, .dropset)

        observation.setTypeRawValue = "someFutureType"
        XCTAssertNil(observation.setType)

        observation.setTypeRawValue = nil
        XCTAssertNil(observation.setType)
    }

    /// An observation recorded before instrumentation must stay distinguishable from a working set.
    func testObservationWithoutASetTypeIsNilNotWorking() {
        let observation = FatigueObservation(
            exerciseId: UUID(),
            workoutId: UUID(),
            setId: UUID(),
            setIndex: 0,
            predictedEffectiveE1RM: 100,
            actualE1RM: 98,
            normalizedError: 0.02,
            baseE1RM: 100,
            prescribedWeight: 75,
            actualWeight: 75,
            actualReps: 8,
            actualRIR: 1
        )

        XCTAssertNil(observation.setType)
    }
}

/// Backups must survive schema growth in both directions.
///
/// The archive decodes in a single call, so one unrecognised enum raw value anywhere fails the
/// *entire* restore — the user loses their history because a newer build had one extra label. And
/// the version guard cannot save them: it runs after the decode, so the failure reports a perfectly
/// good file as corrupt.
///
/// Two defences, and they solve different halves. Reading is lenient, which protects this build
/// from future ones. Writing is conservative, which protects already-shipped builds from this one —
/// nothing can be retrofitted into 1.4's decoder, so 1.5 must not emit values it cannot parse.
final class ArchiveEnumCompatibilityTests: XCTestCase {

    /// A status added after 1.4 must reach the archive as something 1.4 can decode.
    func testNewAuditStatusIsWrittenAsAValueOlderBuildsUnderstand() {
        let shippedIn1_4: Set<String> = [
            "used", "warmupNotTracked", "baselineFirstWorkingSet", "suggestionUnavailable",
            "missingRIR", "invalidPerformance", "weightDeviationOver20Percent"
        ]

        for status in FatigueLearningAuditStatus.allCases {
            XCTAssertTrue(
                shippedIn1_4.contains(status.archiveRawValue),
                "\(status.rawValue) reaches an archive as '\(status.archiveRawValue)', which 1.4 "
                + "cannot decode — that fails the whole restore, not just this column"
            )
        }
    }

    /// Specifically the case PR6 added.
    func testNonCapacityStatusIsDowngradedForTheArchive() {
        XCTAssertEqual(
            FatigueLearningAuditStatus.nonCapacitySetType.archiveRawValue,
            FatigueLearningAuditStatus.suggestionUnavailable.rawValue
        )
        XCTAssertEqual(FatigueLearningAuditStatus.used.archiveRawValue, "used")
    }

    /// Reading is the other half: an unknown value from a *newer* build costs one column, never
    /// the archive.
    func testUnknownEnumValuesDecodeRatherThanThrowing() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "workoutId": "22222222-2222-2222-2222-222222222222",
          "exerciseId": "33333333-3333-3333-3333-333333333333",
          "setId": "44444444-4444-4444-4444-444444444444",
          "visibleSetNumber": 2,
          "setType": "aTypeFromTheFuture",
          "status": "aStatusFromTheFuture",
          "createdAt": "2026-03-22T08:25:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let audit = try decoder.decode(
            WorkoutHistoryArchiveFatigueLearningSetAudit.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(audit.setType, "aTypeFromTheFuture", "the raw value survives verbatim")
        XCTAssertEqual(audit.status, "aStatusFromTheFuture")
    }

    /// The same protection over the core data. `SET_TYPES_SCOPING.md` contemplates adding a
    /// `deload` case; if that ever ships, every existing build must still restore the backup.
    func testAnUnknownSetTypeOnACoreSetDoesNotFailTheDecode() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "workoutId": "22222222-2222-2222-2222-222222222222",
          "exerciseId": "33333333-3333-3333-3333-333333333333",
          "date": "2026-03-22T08:25:00Z",
          "setType": "deload",
          "orderInWorkout": 1,
          "orderInExercise": 1,
          "completed": true,
          "createdAt": "2026-03-22T08:25:00Z",
          "updatedAt": "2026-03-22T08:25:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let archived = try decoder.decode(WorkoutHistoryArchiveSet.self, from: Data(json.utf8))

        XCTAssertEqual(archived.setType, "deload")
    }

    /// Every currently-known type must still round-trip exactly — leniency must not become sloppy.
    func testKnownSetTypesStillRoundTripExactly() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for type in SetType.allCases {
            let audit = FatigueLearningSetAudit(
                workoutId: UUID(), exerciseId: UUID(), setId: UUID(),
                visibleSetNumber: 1, setType: type, status: .used
            )
            let archived = WorkoutHistoryArchiveFatigueLearningSetAudit(
                id: audit.id,
                workoutId: audit.workoutId,
                exerciseId: audit.exerciseId,
                setId: audit.setId,
                visibleSetNumber: audit.visibleSetNumber,
                setType: audit.setType.rawValue,
                status: audit.status.archiveRawValue,
                suggestionUnavailableReasonRawValue: nil,
                predictedEffectiveE1RM: nil,
                baseE1RM: nil,
                prescribedWeight: nil,
                actualWeight: nil,
                actualReps: nil,
                actualRIR: nil,
                deviationFraction: nil,
                normalizedError: nil,
                modelEpoch: nil,
                createdAt: audit.createdAt
            )
            let encoded = try encoder.encode(archived)
            let decoded = try decoder.decode(
                WorkoutHistoryArchiveFatigueLearningSetAudit.self, from: encoded
            )

            XCTAssertEqual(SetType(rawValue: decoded.setType), type)
        }
    }
}
