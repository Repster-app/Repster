import XCTest
import SwiftData
import UniformTypeIdentifiers
@testable import Reppo

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
        XCTAssertEqual(exportedWarmup.setType, .warmup)
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
        XCTAssertEqual(restoreResult.exercisesUpserted, 1)
        XCTAssertEqual(restoreResult.setsRestored, 2)
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

    func testRestoreBackupRejectsUnsupportedArchiveVersion() async throws {
        let context = try makeBackupServiceContext()
        let invalidArchive = WorkoutHistoryArchive(
            version: 99,
            exportedAt: Date(),
            workouts: [],
            exercises: [],
            sets: [],
            fatigueObservations: nil
        )
        let invalidData = try encodeBackupArchive(invalidArchive)

        do {
            _ = try await context.service.restoreBackup(data: invalidData)
            XCTFail("Expected unsupported backup version to fail")
        } catch let error as WorkoutHistoryBackupError {
            guard case .invalidArchiveVersion(let version) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, 99)
        }
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
        let service = WorkoutHistoryBackupService(
            workoutRepo: workoutRepo,
            exerciseRepo: exerciseRepo,
            setRepo: setRepo,
            fatigueObservationRepo: fatigueObservationRepo,
            statsService: statsService,
            prService: prService,
            modelContainer: container
        )

        return WorkoutHistoryBackupArchiveTestContext(
            modelContainer: container,
            service: service,
            exerciseRepo: exerciseRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo,
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
        XCTAssertEqual(shareURL.pathExtension, "reppobackup")
        XCTAssertNil(viewModel.errorMessage)
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

    private func makeBackupFileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("reppobackup")
        try Data("backup".utf8).write(to: url, options: .atomic)
        return url
    }
}

final class ReppoDocumentTypeRegistrationTests: XCTestCase {
    func testCustomFilenameExtensionsResolveToRegisteredReppoTypes() throws {
        let backupType = try XCTUnwrap(UTType(filenameExtension: "reppobackup"))
        let templateType = try XCTUnwrap(UTType(filenameExtension: "reppotemplate"))

        XCTAssertEqual(backupType.identifier, "com.magnusespensen.reppo.workout-history")
        XCTAssertEqual(templateType.identifier, "com.magnusespensen.reppo.template")
        XCTAssertTrue(backupType.conforms(to: .json))
        XCTAssertTrue(templateType.conforms(to: .json))
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
    let exerciseRepo: ExerciseRepository
    let workoutRepo: WorkoutRepository
    let setRepo: SetRepository
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
    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws {}
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
    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws {}
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
