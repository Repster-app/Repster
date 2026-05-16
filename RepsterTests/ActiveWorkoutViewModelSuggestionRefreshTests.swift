import XCTest
import SwiftData
@testable import Repster

@MainActor
final class ActiveWorkoutViewModelSuggestionRefreshTests: XCTestCase {

    func testRunningTimerUsesFullPresentationWhenKeyboardHidden() {
        let mode = ActiveWorkoutBottomAccessoryLayout.timerPresentationMode(
            for: .running(remaining: 90, total: 120),
            isKeyboardVisible: false
        )

        XCTAssertEqual(mode, .full)
    }

    func testRunningTimerUsesCompactPresentationWhenKeyboardVisible() {
        let mode = ActiveWorkoutBottomAccessoryLayout.timerPresentationMode(
            for: .running(remaining: 90, total: 120),
            isKeyboardVisible: true
        )

        XCTAssertEqual(mode, .compact)
    }

    func testPausedTimerUsesFullPresentationWhenKeyboardHidden() {
        let mode = ActiveWorkoutBottomAccessoryLayout.timerPresentationMode(
            for: .paused(remaining: 90, total: 120, source: .manual),
            isKeyboardVisible: false
        )

        XCTAssertEqual(mode, .full)
    }

    func testPausedTimerUsesCompactPresentationWhenKeyboardVisible() {
        let mode = ActiveWorkoutBottomAccessoryLayout.timerPresentationMode(
            for: .paused(remaining: 90, total: 120, source: .manual),
            isKeyboardVisible: true
        )

        XCTAssertEqual(mode, .compact)
    }

    func testFinishedTimerUsesFullPresentationWhenKeyboardHidden() {
        let mode = ActiveWorkoutBottomAccessoryLayout.timerPresentationMode(
            for: .finished,
            isKeyboardVisible: false
        )

        XCTAssertEqual(mode, .full)
    }

    func testFinishedTimerIsHiddenWhenKeyboardVisible() {
        let mode = ActiveWorkoutBottomAccessoryLayout.timerPresentationMode(
            for: .finished,
            isKeyboardVisible: true
        )

        XCTAssertNil(mode)
    }

    func testBackgroundRestTimerNotificationUsesSystemSoundForVibrationMode() {
        XCTAssertTrue(
            ActiveWorkoutViewModel.restTimerBackgroundNotificationUsesSystemSound(for: "vibration")
        )
    }

    func testBackgroundRestTimerNotificationDisablesSystemSoundWhenAlertsAreOff() {
        XCTAssertFalse(
            ActiveWorkoutViewModel.restTimerBackgroundNotificationUsesSystemSound(for: "off")
        )
    }

    func testFinishWorkoutForwardsSummaryMetadataAndMarksWorkoutFinished() async throws {
        let workoutService = WorkoutServiceStub()
        let analyticsService = AnalyticsServiceSpy()
        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: SetServiceStub(),
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            analyticsService: analyticsService,
            fatigueLearningService: makeStubFatigueLearningService()
        )

        let workoutId = UUID()
        viewModel.workout = Workout(
            id: workoutId,
            date: Date(),
            startTime: Date().addingTimeInterval(-900),
            status: .inProgress
        )
        viewModel.exercises = [makeExercise(name: "Back Squat")]
        let completedSet = makeSet(exerciseId: viewModel.exercises[0].id, order: 1, reps: 5)
        completedSet.completed = true
        viewModel.setsByExercise = [viewModel.exercises[0].id: [completedSet]]

        await viewModel.finishWorkout(
            title: "Leg Day",
            notes: "Strong session",
            perceivedEffort: 8
        )

        XCTAssertEqual(workoutService.lastFinishedWorkoutId, workoutId)
        XCTAssertEqual(workoutService.lastFinishTitle, "Leg Day")
        XCTAssertEqual(workoutService.lastFinishNotes, "Strong session")
        XCTAssertEqual(workoutService.lastFinishPerceivedEffort, 8)
        XCTAssertGreaterThanOrEqual(workoutService.lastFinishDurationSecondsOverride ?? 0, 899)
        XCTAssertTrue(viewModel.isWorkoutFinished)
        XCTAssertNil(viewModel.workout)
        XCTAssertTrue(viewModel.exercises.isEmpty)
        XCTAssertTrue(viewModel.setsByExercise.isEmpty)

        let completionEvent = try XCTUnwrap(analyticsService.events.first { $0.event == .workoutCompleted })
        XCTAssertEqual(completionEvent.properties[.durationBucket], .string("under_30m"))
        XCTAssertEqual(completionEvent.properties[.setCountBucket], .string("1"))
        XCTAssertEqual(completionEvent.properties[.exerciseCountBucket], .string("1"))
        XCTAssertEqual(completionEvent.properties[.perceivedEffortEntered], .bool(true))
        XCTAssertEqual(completionEvent.properties[.notesEntered], .bool(true))
        XCTAssertEqual(completionEvent.properties[.excludedFromProgression], .bool(false))
    }

    func testLoadActiveWorkoutRestoresPausedElapsedTimeForMatchingWorkout() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let workoutId = UUID()
        let workoutService = WorkoutServiceStub()
        workoutService.activeWorkout = Workout(
            id: workoutId,
            date: Date(),
            startTime: Date().addingTimeInterval(-900),
            status: .inProgress
        )
        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: SetServiceStub(),
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        UserDefaults.standard.set(
            workoutId.uuidString,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockWorkoutId
        )
        UserDefaults.standard.set(
            123.0,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockAccumulatedElapsedSeconds
        )
        UserDefaults.standard.set(
            true,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockIsPaused
        )

        await viewModel.loadActiveWorkout()

        XCTAssertTrue(viewModel.isWorkoutPaused)
        XCTAssertEqual(Int(viewModel.elapsedTime), 123)
        XCTAssertEqual(Int(try XCTUnwrap(viewModel.computeSummary()).duration), 123)
    }

    func testLoadActiveWorkoutIgnoresStalePersistedPausedState() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let workout = Workout(
            id: UUID(),
            date: Date(),
            startTime: Date().addingTimeInterval(-5),
            status: .inProgress
        )
        let workoutService = WorkoutServiceStub()
        workoutService.activeWorkout = workout
        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: SetServiceStub(),
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        UserDefaults.standard.set(
            UUID().uuidString,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockWorkoutId
        )
        UserDefaults.standard.set(
            500.0,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockAccumulatedElapsedSeconds
        )
        UserDefaults.standard.set(
            true,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockIsPaused
        )

        await viewModel.loadActiveWorkout()

        XCTAssertFalse(viewModel.isWorkoutPaused)
        XCTAssertGreaterThanOrEqual(Int(viewModel.elapsedTime), 4)
        XCTAssertLessThan(Int(viewModel.elapsedTime), 10)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockWorkoutId),
            workout.id.uuidString
        )
    }

    func testLoadActiveWorkoutRestoresPersistedSelectedExerciseForMatchingWorkout() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let workout = Workout(
            id: UUID(),
            date: Date(),
            startTime: Date().addingTimeInterval(-900),
            status: .inProgress
        )
        let firstExercise = makeExercise(name: "Bench Press")
        let secondExercise = makeExercise(name: "Incline Dumbbell Press")
        let firstSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: firstExercise.id,
            reps: 8,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        let secondSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: secondExercise.id,
            reps: 10,
            orderInWorkout: 2,
            orderInExercise: 1,
            completed: false
        )

        let workoutService = WorkoutServiceStub()
        workoutService.activeWorkout = workout
        let setService = SetServiceStub()
        setService.workoutSets[workout.id] = [firstSet, secondSet]
        let exerciseService = ExerciseServiceStub()
        exerciseService.fetchedExercises[firstExercise.id] = firstExercise
        exerciseService.fetchedExercises[secondExercise.id] = secondExercise
        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService,
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        UserDefaults.standard.set(
            workout.id.uuidString,
            forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseWorkoutId
        )
        UserDefaults.standard.set(
            secondExercise.id.uuidString,
            forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseId
        )

        await viewModel.loadActiveWorkout()

        XCTAssertEqual(viewModel.selectedExerciseIndex, 1)
        XCTAssertEqual(viewModel.currentExercise?.id, secondExercise.id)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseId),
            secondExercise.id.uuidString
        )
    }

    func testLoadActiveWorkoutFallsBackToFirstExerciseWithIncompleteWork() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let workout = Workout(
            id: UUID(),
            date: Date(),
            startTime: Date().addingTimeInterval(-900),
            status: .inProgress
        )
        let firstExercise = makeExercise(name: "Back Squat")
        let secondExercise = makeExercise(name: "Romanian Deadlift")
        let thirdExercise = makeExercise(name: "Leg Press")
        let completedSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: firstExercise.id,
            reps: 5,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        let currentSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: secondExercise.id,
            reps: 8,
            orderInWorkout: 2,
            orderInExercise: 1,
            completed: false
        )
        let laterSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: thirdExercise.id,
            reps: 12,
            orderInWorkout: 3,
            orderInExercise: 1,
            completed: false
        )

        let workoutService = WorkoutServiceStub()
        workoutService.activeWorkout = workout
        let setService = SetServiceStub()
        setService.workoutSets[workout.id] = [completedSet, currentSet, laterSet]
        let exerciseService = ExerciseServiceStub()
        exerciseService.fetchedExercises[firstExercise.id] = firstExercise
        exerciseService.fetchedExercises[secondExercise.id] = secondExercise
        exerciseService.fetchedExercises[thirdExercise.id] = thirdExercise
        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService,
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        await viewModel.loadActiveWorkout()

        XCTAssertEqual(viewModel.selectedExerciseIndex, 1)
        XCTAssertEqual(viewModel.currentExercise?.id, secondExercise.id)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseWorkoutId),
            workout.id.uuidString
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseId),
            secondExercise.id.uuidString
        )
    }

    func testFinishWorkoutUsesPausedDurationOverrideWhenRestoredFromPersistence() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let workoutId = UUID()
        let workoutService = WorkoutServiceStub()
        workoutService.activeWorkout = Workout(
            id: workoutId,
            date: Date(),
            startTime: Date().addingTimeInterval(-900),
            status: .inProgress
        )
        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: SetServiceStub(),
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        UserDefaults.standard.set(
            workoutId.uuidString,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockWorkoutId
        )
        UserDefaults.standard.set(
            187.0,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockAccumulatedElapsedSeconds
        )
        UserDefaults.standard.set(
            true,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockIsPaused
        )

        await viewModel.loadActiveWorkout()
        await viewModel.finishWorkout(title: nil, notes: nil, perceivedEffort: nil)

        XCTAssertEqual(workoutService.lastFinishDurationSecondsOverride, 187)
    }

    func testPausingWorkoutFreezesAndResumesRestTimer() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: SetServiceStub(),
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        viewModel.workout = Workout(
            id: UUID(),
            date: Date(),
            startTime: Date().addingTimeInterval(-30),
            status: .inProgress
        )

        viewModel.startRestTimer(duration: 4)
        try await Task.sleep(for: .milliseconds(1100))

        viewModel.toggleWorkoutPause()
        XCTAssertTrue(viewModel.isWorkoutPaused)

        let pausedRemaining: Int
        switch viewModel.restTimer {
        case .paused(let remaining, _, let source):
            XCTAssertEqual(source, .workout)
            pausedRemaining = remaining
        default:
            return XCTFail("Expected paused rest timer to remain visible")
        }

        try await Task.sleep(for: .milliseconds(1100))

        switch viewModel.restTimer {
        case .paused(let remaining, _, let source):
            XCTAssertEqual(source, .workout)
            XCTAssertEqual(remaining, pausedRemaining)
        default:
            XCTFail("Expected paused timer state to remain paused")
        }

        viewModel.toggleWorkoutPause()
        try await Task.sleep(for: .milliseconds(1100))

        switch viewModel.restTimer {
        case .running(let remaining, _):
            XCTAssertLessThan(remaining, pausedRemaining)
        case .finished:
            XCTAssertLessThan(0, pausedRemaining)
        default:
            XCTFail("Expected rest timer to resume after unpausing workout")
        }
    }

    func testManualRestPauseFreezesAndResumesWithoutPausingWorkout() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: SetServiceStub(),
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        viewModel.workout = Workout(
            id: UUID(),
            date: Date(),
            startTime: Date().addingTimeInterval(-30),
            status: .inProgress
        )

        viewModel.startRestTimer(duration: 4)
        try await Task.sleep(for: .milliseconds(1100))

        viewModel.toggleRestTimerPause()
        XCTAssertFalse(viewModel.isWorkoutPaused)

        let pausedRemaining: Int
        switch viewModel.restTimer {
        case .paused(let remaining, _, let source):
            XCTAssertEqual(source, .manual)
            pausedRemaining = remaining
        default:
            return XCTFail("Expected manually paused rest timer")
        }

        try await Task.sleep(for: .milliseconds(1100))

        switch viewModel.restTimer {
        case .paused(let remaining, _, let source):
            XCTAssertEqual(source, .manual)
            XCTAssertEqual(remaining, pausedRemaining)
        default:
            XCTFail("Expected manually paused rest timer to stay frozen")
        }

        viewModel.toggleRestTimerPause()
        try await Task.sleep(for: .milliseconds(1100))

        switch viewModel.restTimer {
        case .running(let remaining, _):
            XCTAssertLessThan(remaining, pausedRemaining)
        case .finished:
            XCTAssertLessThan(0, pausedRemaining)
        default:
            XCTFail("Expected rest timer to resume after manual pause toggle")
        }
    }

    func testLoadActiveWorkoutRestoresManualPausedRestTimerForMatchingWorkout() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let workoutId = UUID()
        let workoutService = WorkoutServiceStub()
        workoutService.activeWorkout = Workout(
            id: workoutId,
            date: Date(),
            startTime: Date().addingTimeInterval(-900),
            status: .inProgress
        )
        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: SetServiceStub(),
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        UserDefaults.standard.set(
            workoutId.uuidString,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId
        )
        UserDefaults.standard.set(
            180,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration
        )
        UserDefaults.standard.set(
            75,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration
        )
        UserDefaults.standard.set(
            true,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused
        )
        UserDefaults.standard.set(
            RestTimerPauseSource.manual.rawValue,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource
        )

        await viewModel.loadActiveWorkout()

        switch viewModel.restTimer {
        case .paused(let remaining, let total, let source):
            XCTAssertEqual(remaining, 75)
            XCTAssertEqual(total, 180)
            XCTAssertEqual(source, .manual)
        default:
            XCTFail("Expected manual paused timer to restore for matching workout")
        }
    }

    func testLoadActiveWorkoutClearsStaleManualPausedRestTimerState() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let workout = Workout(
            id: UUID(),
            date: Date(),
            startTime: Date().addingTimeInterval(-10),
            status: .inProgress
        )
        let workoutService = WorkoutServiceStub()
        workoutService.activeWorkout = workout
        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: SetServiceStub(),
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        UserDefaults.standard.set(
            UUID().uuidString,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId
        )
        UserDefaults.standard.set(
            120,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration
        )
        UserDefaults.standard.set(
            50,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration
        )
        UserDefaults.standard.set(
            true,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused
        )
        UserDefaults.standard.set(
            RestTimerPauseSource.manual.rawValue,
            forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource
        )

        await viewModel.loadActiveWorkout()

        XCTAssertEqual(viewModel.restTimer, .idle)
        XCTAssertNil(UserDefaults.standard.string(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId))
    }

    func testManualRestPauseStaysPausedAcrossWorkoutPauseAndResume() async throws {
        clearActiveWorkoutSessionDefaults()
        defer { clearActiveWorkoutSessionDefaults() }

        let profile = HealthProfile()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: SetServiceStub(),
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        viewModel.workout = Workout(
            id: UUID(),
            date: Date(),
            startTime: Date().addingTimeInterval(-30),
            status: .inProgress
        )

        viewModel.startRestTimer(duration: 5)
        try await Task.sleep(for: .milliseconds(1100))
        viewModel.toggleRestTimerPause()

        let manuallyPausedRemaining: Int
        switch viewModel.restTimer {
        case .paused(let remaining, _, let source):
            XCTAssertEqual(source, .manual)
            manuallyPausedRemaining = remaining
        default:
            return XCTFail("Expected manual paused timer before workout pause")
        }

        viewModel.toggleWorkoutPause()
        XCTAssertTrue(viewModel.isWorkoutPaused)

        switch viewModel.restTimer {
        case .paused(let remaining, _, let source):
            XCTAssertEqual(source, .manual)
            XCTAssertEqual(remaining, manuallyPausedRemaining)
        default:
            XCTFail("Expected manual paused timer to remain manual during workout pause")
        }

        viewModel.toggleWorkoutPause()
        XCTAssertFalse(viewModel.isWorkoutPaused)

        switch viewModel.restTimer {
        case .paused(let remaining, _, let source):
            XCTAssertEqual(source, .manual)
            XCTAssertEqual(remaining, manuallyPausedRemaining)
        default:
            XCTFail("Expected manual paused timer to stay paused after workout resume")
        }
    }

    func testCreateEditExerciseViewModelNormalizesPrimaryGroupAndDefaultsSecondaryMusclesOnCreate() async throws {
        let exerciseService = ExerciseServiceStub()
        let viewModel = CreateEditExerciseViewModel(
            exercise: nil,
            exerciseService: exerciseService,
            settingsService: SettingsServiceStub(profile: HealthProfile())
        )

        viewModel.name = "Burpee"
        viewModel.primaryMuscle = ExercisePrimaryGroup.fullBody.rawValue

        try await viewModel.save()

        let createdExercise = try XCTUnwrap(exerciseService.createdExercises.last)
        XCTAssertEqual(createdExercise.primaryMuscle, "full body")
        XCTAssertEqual(createdExercise.secondaryMuscles, [])
    }

    func testCreateEditExerciseViewModelPreservesHiddenSecondaryMusclesOnEdit() async throws {
        let exerciseService = ExerciseServiceStub()
        let existingExercise = Exercise(
            name: "Incline Dumbbell Press",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            secondaryMuscles: ["shoulders", "triceps"],
            unilateral: false
        )
        let viewModel = CreateEditExerciseViewModel(
            exercise: existingExercise,
            exerciseService: exerciseService,
            settingsService: SettingsServiceStub(profile: HealthProfile())
        )

        viewModel.name = "Incline DB Press"
        viewModel.primaryMuscle = ExercisePrimaryGroup.fullBody.rawValue

        try await viewModel.save()

        let updatedExercise = try XCTUnwrap(exerciseService.updatedExercises.last)
        XCTAssertEqual(updatedExercise.primaryMuscle, "full body")
        XCTAssertEqual(updatedExercise.secondaryMuscles, ["shoulders", "triceps"])
        XCTAssertEqual(existingExercise.secondaryMuscles, ["shoulders", "triceps"])
    }

    func testCreateEditExerciseViewModelKeepsLegacyPrimaryGroupSelectableDuringEdit() {
        let viewModel = CreateEditExerciseViewModel(
            exercise: Exercise(
                name: "Hammer Curl",
                equipmentType: .dumbbell,
                trackingType: .weightReps,
                primaryMuscle: "arms"
            ),
            exerciseService: ExerciseServiceStub(),
            settingsService: SettingsServiceStub(profile: HealthProfile())
        )

        XCTAssertEqual(viewModel.primaryMuscle, "arms")
        XCTAssertTrue(viewModel.primaryMuscleOptions.contains("arms"))
        XCTAssertEqual(viewModel.primaryMuscleDisplayName, "Arms")
    }

    func testCreateEditExerciseViewModelDoesNotLockTrackingTypeForPlaceholderSets() async {
        let exerciseService = ExerciseServiceStub()
        exerciseService.hasSets = true
        exerciseService.hasLoggedSetData = false

        let viewModel = CreateEditExerciseViewModel(
            exercise: Exercise(
                name: "Run",
                equipmentType: .bodyweight,
                trackingType: .duration
            ),
            exerciseService: exerciseService,
            settingsService: SettingsServiceStub(profile: HealthProfile())
        )

        await viewModel.checkTrackingTypeLock()

        XCTAssertFalse(viewModel.isTrackingTypeLocked)
    }

    func testCreateEditExerciseViewModelLocksTrackingTypeAfterLoggedSetData() async {
        let exerciseService = ExerciseServiceStub()
        exerciseService.hasLoggedSetData = true

        let viewModel = CreateEditExerciseViewModel(
            exercise: Exercise(
                name: "Run",
                equipmentType: .bodyweight,
                trackingType: .durationDistance
            ),
            exerciseService: exerciseService,
            settingsService: SettingsServiceStub(profile: HealthProfile())
        )

        await viewModel.checkTrackingTypeLock()

        XCTAssertTrue(viewModel.isTrackingTypeLocked)
    }

    func testWeightEditDoesNotTriggerSuggestionRefresh() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        let context = makeContext(loadPrescriptionService: loadPrescriptionService)

        await context.viewModel.loadWeightSuggestions()
        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)

        context.pendingSet.weight = 100
        context.viewModel.markSetDirty(context.pendingSet, field: .weight)

        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)
        XCTAssertEqual(context.viewModel.weightSuggestionData?.suggestions.first?.targetReps, 8)
    }

    func testRapidRepsEditsCoalesceIntoOneDebouncedRefresh() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        let context = makeContext(loadPrescriptionService: loadPrescriptionService)

        await context.viewModel.loadWeightSuggestions()
        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)

        for reps in [9, 10, 11] {
            context.pendingSet.reps = reps
            context.viewModel.markSetDirty(context.pendingSet, field: .reps)
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)

        try await waitUntil {
            loadPrescriptionService.evaluationCount == 2 &&
            context.viewModel.weightSuggestionData?.suggestions.first?.targetReps == 11
        }

        XCTAssertEqual(loadPrescriptionService.lastRecordedTargetReps, [11])
    }

    func testSilentRefreshKeepsExistingSuggestionVisibleUntilReplacementArrives() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        loadPrescriptionService.setDelay(.milliseconds(200), forFirstTargetReps: 10)
        let context = makeContext(loadPrescriptionService: loadPrescriptionService)

        await context.viewModel.loadWeightSuggestions()
        let initialSuggestion = try XCTUnwrap(context.viewModel.weightSuggestionData?.suggestions.first)

        context.pendingSet.reps = 10
        context.viewModel.markSetDirty(context.pendingSet, field: .reps)

        XCTAssertFalse(context.viewModel.isLoadingWeightSuggestions)
        XCTAssertTrue(context.viewModel.isRefreshingWeightSuggestions)
        XCTAssertEqual(context.viewModel.weightSuggestionData?.suggestions.first?.targetReps, initialSuggestion.targetReps)
        XCTAssertEqual(
            context.viewModel.suggestedWeight(for: context.pendingSet.id),
            initialSuggestion.suggestedWeight
        )

        try await waitUntil {
            context.viewModel.weightSuggestionData?.suggestions.first?.targetReps == 10
        }

        XCTAssertFalse(context.viewModel.isLoadingWeightSuggestions)
        XCTAssertFalse(context.viewModel.isRefreshingWeightSuggestions)
        XCTAssertEqual(
            context.viewModel.suggestedWeight(for: context.pendingSet.id),
            context.viewModel.weightSuggestionData?.suggestion(for: context.pendingSet.id)?.suggestedWeight
        )
    }

    func testSuggestionStateAccessorMatchesSuggestedWeightAccessor() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        let context = makeContext(loadPrescriptionService: loadPrescriptionService)

        await context.viewModel.loadWeightSuggestions()

        let rowState = try XCTUnwrap(context.viewModel.suggestionState(for: context.pendingSet.id))
        let rowSuggestion = try XCTUnwrap(rowState.suggestion)

        XCTAssertEqual(rowState.setId, context.pendingSet.id)
        XCTAssertEqual(rowSuggestion.suggestedWeight, context.viewModel.suggestedWeight(for: context.pendingSet.id))
    }

    func testNewerRefreshResultWinsWhenOlderAsyncEvaluationFinishesLater() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        loadPrescriptionService.setDelay(.milliseconds(700), forFirstTargetReps: 8)
        let context = makeContext(loadPrescriptionService: loadPrescriptionService, initialReps: 6)

        await context.viewModel.loadWeightSuggestions()

        context.pendingSet.reps = 8
        context.viewModel.markSetDirty(context.pendingSet, field: .reps)
        try await Task.sleep(for: .milliseconds(350))

        context.pendingSet.reps = 10
        context.viewModel.markSetDirty(context.pendingSet, field: .reps)

        try await waitUntil {
            context.viewModel.weightSuggestionData?.suggestions.first?.targetReps == 10
        }

        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(loadPrescriptionService.evaluationCount, 3)
        XCTAssertEqual(context.viewModel.weightSuggestionData?.suggestions.first?.targetReps, 10)
    }

    func testExerciseSwitchCancelsPendingDraftRefreshAndPerformsBlockingLoadForNewExercise() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        loadPrescriptionService.setDelay(.milliseconds(200), forExerciseName: "Exercise 2")
        let context = makeContext(
            loadPrescriptionService: loadPrescriptionService,
            exerciseCount: 2,
            initialReps: 8,
            secondExerciseReps: 12
        )

        await context.viewModel.loadWeightSuggestions()
        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)

        context.pendingSet.reps = 9
        context.viewModel.markSetDirty(context.pendingSet, field: .reps)
        XCTAssertTrue(context.viewModel.isRefreshingWeightSuggestions)

        context.viewModel.selectedExerciseIndex = 1
        let loadTask = Task {
            await context.viewModel.loadWeightSuggestions()
        }

        await Task.yield()
        XCTAssertTrue(context.viewModel.isLoadingWeightSuggestions)

        await loadTask.value

        XCTAssertFalse(context.viewModel.isLoadingWeightSuggestions)
        XCTAssertFalse(context.viewModel.isRefreshingWeightSuggestions)
        XCTAssertEqual(loadPrescriptionService.evaluationCount, 2)
        XCTAssertEqual(context.viewModel.currentExercise?.id, context.secondExercise?.id)
        XCTAssertEqual(context.viewModel.weightSuggestionData?.suggestions.first?.targetReps, 12)
    }

    func testAddExercisesSelectsFirstNewlyAddedExercise() async throws {
        let profile = HealthProfile()
        let workout = Workout(startTime: Date())
        let existingExercise = makeExercise(name: "Existing")
        let firstAddedExercise = makeExercise(name: "First Added")
        let secondAddedExercise = makeExercise(name: "Second Added")
        let exerciseService = ExerciseServiceStub()
        exerciseService.fetchedExercises[firstAddedExercise.id] = firstAddedExercise
        exerciseService.fetchedExercises[secondAddedExercise.id] = secondAddedExercise

        let viewModel = ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: SetServiceStub(),
            exerciseService: exerciseService,
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        viewModel.workout = workout
        viewModel.exercises = [existingExercise]
        viewModel.selectedExerciseIndex = 0
        viewModel.setsByExercise = [
            existingExercise.id: [makeSet(exerciseId: existingExercise.id, order: 1, reps: 8)]
        ]

        await viewModel.addExercises([firstAddedExercise.id, secondAddedExercise.id])

        XCTAssertEqual(
            viewModel.exercises.map(\.id),
            [existingExercise.id, firstAddedExercise.id, secondAddedExercise.id]
        )
        XCTAssertEqual(viewModel.selectedExerciseIndex, 1)
        XCTAssertEqual(viewModel.currentExercise?.id, firstAddedExercise.id)
        XCTAssertEqual(viewModel.setsByExercise[firstAddedExercise.id]?.count, 1)
        XCTAssertEqual(viewModel.setsByExercise[secondAddedExercise.id]?.count, 1)
    }

    func testReorderExercisesPreservesMovedSelectionAndPersistsContiguousOrder() async throws {
        let profile = HealthProfile()
        let setService = SetServiceStub()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: setService,
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        let exerciseA = makeExercise(name: "Exercise A")
        let exerciseB = makeExercise(name: "Exercise B")
        let exerciseC = makeExercise(name: "Exercise C")

        let aWarmup = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseA.id,
            reps: 5,
            rir: 2.0,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        let aWorking = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseA.id,
            reps: 8,
            rir: 2.0,
            orderInWorkout: 2,
            orderInExercise: 2,
            completed: false
        )
        let bWarmup = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseB.id,
            reps: 5,
            rir: 2.0,
            orderInWorkout: 3,
            orderInExercise: 1,
            completed: false
        )
        let bWorking = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseB.id,
            reps: 8,
            rir: 2.0,
            orderInWorkout: 4,
            orderInExercise: 2,
            completed: false
        )
        let cWorking = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseC.id,
            reps: 10,
            rir: 2.0,
            orderInWorkout: 5,
            orderInExercise: 1,
            completed: false
        )

        viewModel.exercises = [exerciseA, exerciseB, exerciseC]
        viewModel.selectedExerciseIndex = 1
        viewModel.setsByExercise = [
            exerciseA.id: [aWarmup, aWorking],
            exerciseB.id: [bWarmup, bWorking],
            exerciseC.id: [cWorking]
        ]

        viewModel.reorderExercises(from: IndexSet(integer: 1), to: 3)

        XCTAssertEqual(viewModel.exercises.map(\.id), [exerciseA.id, exerciseC.id, exerciseB.id])
        XCTAssertEqual(viewModel.selectedExerciseIndex, 2)
        XCTAssertEqual(viewModel.currentExercise?.id, exerciseB.id)

        try await waitUntil {
            setService.editedSetIds.count == 5
        }

        XCTAssertEqual(
            setService.editedSetIds,
            [aWarmup.id, aWorking.id, cWorking.id, bWarmup.id, bWorking.id]
        )
        XCTAssertEqual(
            [aWarmup.orderInWorkout, aWorking.orderInWorkout, cWorking.orderInWorkout, bWarmup.orderInWorkout, bWorking.orderInWorkout],
            [1, 2, 3, 4, 5]
        )
        XCTAssertEqual(
            viewModel.setsByExercise[exerciseB.id]?.sorted { $0.orderInExercise < $1.orderInExercise }.map(\.orderInWorkout),
            [4, 5]
        )
    }

    func testAddSetTriggersImmediateSilentRefreshForCurrentExercise() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        let setService = SetServiceStub()
        let context = makeContext(
            loadPrescriptionService: loadPrescriptionService,
            setService: setService
        )

        context.viewModel.workout = Workout(startTime: Date())
        await context.viewModel.loadWeightSuggestions()
        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)

        await context.viewModel.addSet(for: context.exercise.id)

        XCTAssertFalse(context.viewModel.isLoadingWeightSuggestions)

        try await waitUntil {
            context.viewModel.currentSets.count == 2 &&
            context.viewModel.weightSuggestionData?.rowStates.count == 2
        }

        XCTAssertEqual(loadPrescriptionService.evaluationCount, 2)
        XCTAssertEqual(context.viewModel.currentSets.count, 2)
        XCTAssertEqual(context.viewModel.weightSuggestionData?.suggestions.count, 2)

        let firstSuggestion = try XCTUnwrap(context.viewModel.weightSuggestionData?.suggestions.first)
        XCTAssertEqual(
            context.viewModel.suggestedWeight(for: firstSuggestion.pendingSetId),
            firstSuggestion.suggestedWeight
        )

        let newlyAddedSet = try XCTUnwrap(context.viewModel.currentSets.last)
        XCTAssertNotNil(context.viewModel.suggestionState(for: newlyAddedSet.id)?.suggestion)
    }

    func testManualRepRangeDraftTriggersDebouncedRefresh() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        let context = makeContext(loadPrescriptionService: loadPrescriptionService)

        await context.viewModel.loadWeightSuggestions()
        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)

        context.pendingSet.reps = nil
        context.pendingSet.overrideTargetRepMin = 8
        context.pendingSet.overrideTargetRepMax = 12
        context.viewModel.markSetDirty(context.pendingSet, field: .reps)

        try await waitUntil {
            loadPrescriptionService.evaluationCount == 2
        }

        XCTAssertEqual(loadPrescriptionService.lastRecordedTargetReps, [10])
        XCTAssertEqual(context.viewModel.suggestionState(for: context.pendingSet.id)?.target?.repRange, 8...12)
    }

    func testCustomKeyboardRepRangeCommitTriggersDebouncedRefresh() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        let context = makeContext(loadPrescriptionService: loadPrescriptionService)

        await context.viewModel.loadWeightSuggestions()
        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)

        context.pendingSet.reps = nil
        let didCommit = CustomRepRangeCommitter.commit(min: 8, max: 12, to: context.pendingSet)
        XCTAssertTrue(didCommit)
        context.viewModel.markSetDirty(context.pendingSet, field: .reps)

        try await waitUntil {
            loadPrescriptionService.evaluationCount == 2
        }

        XCTAssertEqual(context.viewModel.suggestionState(for: context.pendingSet.id)?.target?.repRange, 8...12)
        XCTAssertEqual(loadPrescriptionService.lastRecordedTargetReps, [10])
    }

    func testLoadActiveWorkoutRestoresOverrideTargetsAndSuggestionsUseExplicitRepSource() async throws {
        let workout = Workout(
            id: UUID(),
            date: Date(),
            startTime: Date().addingTimeInterval(-900),
            status: .inProgress
        )
        let exercise = makeExercise(name: "Bench Press")
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        set.targetRepMin = 8
        set.targetRepMax = 12
        set.overrideTargetRepMin = 6
        set.overrideTargetRepMax = 8
        set.targetRIR = 2

        let workoutService = WorkoutServiceStub()
        workoutService.activeWorkout = workout
        let setService = SetServiceStub()
        setService.workoutSets[workout.id] = [set]
        let exerciseService = ExerciseServiceStub()
        exerciseService.fetchedExercises[exercise.id] = exercise
        let profile = HealthProfile()
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        loadPrescriptionService.exerciseNames[exercise.id] = exercise.name
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService,
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: loadPrescriptionService,
            fatigueLearningService: makeStubFatigueLearningService()
        )

        await viewModel.loadActiveWorkout()

        let restoredSet = try XCTUnwrap(viewModel.currentSets.first)
        XCTAssertEqual(restoredSet.preferredTargetRepBounds.min, 6)
        XCTAssertEqual(restoredSet.preferredTargetRepBounds.max, 8)
        XCTAssertEqual(restoredSet.targetRepMin, 8)
        XCTAssertEqual(restoredSet.targetRepMax, 12)

        await viewModel.loadWeightSuggestions()

        let target = try XCTUnwrap(viewModel.suggestionState(for: restoredSet.id)?.target)
        XCTAssertEqual(target.repRange, 6...8)
        XCTAssertEqual(target.repsSource, .explicitSet)
        XCTAssertEqual(target.rirSource, .template)
    }

    func testManualRefreshInvalidatesSuggestionCacheEvenWhenInputsAreUnchanged() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        let context = makeContext(loadPrescriptionService: loadPrescriptionService)

        await context.viewModel.loadWeightSuggestions()
        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)

        await context.viewModel.refreshWeightSuggestions(
            invalidateCache: true,
            presentation: .preserveExisting
        )

        XCTAssertEqual(loadPrescriptionService.evaluationCount, 2)
        XCTAssertFalse(context.viewModel.isRefreshingWeightSuggestions)
    }

    func testExerciseConfigurationRefreshReloadsSuggestionsAndExerciseInfo() async throws {
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        let setService = SetServiceStub()
        let context = makeContext(
            loadPrescriptionService: loadPrescriptionService,
            setService: setService
        )

        context.viewModel.workout = Workout(startTime: Date())
        await context.viewModel.loadWeightSuggestions()
        await context.viewModel.loadExerciseInfo()

        XCTAssertEqual(loadPrescriptionService.evaluationCount, 1)
        XCTAssertEqual(setService.fetchSetsForExerciseCallCount, 1)
        XCTAssertNotNil(context.viewModel.exerciseInfoData)

        context.exercise.weightIncrement = 5.0
        await context.viewModel.refreshCurrentExerciseConfigurationData()

        XCTAssertEqual(loadPrescriptionService.evaluationCount, 2)
        XCTAssertEqual(setService.fetchSetsForExerciseCallCount, 2)
        XCTAssertNotNil(context.viewModel.exerciseInfoData)
    }

    func testLoadWeightSuggestionsPropagatesAdminModeFromProfile() async throws {
        let profile = HealthProfile(prescriptionAdminModeEnabled: true)
        let loadPrescriptionService = LoadPrescriptionServiceSpy()
        let context = makeContext(
            loadPrescriptionService: loadPrescriptionService,
            profile: profile
        )

        XCTAssertFalse(context.viewModel.suggestionAdminModeEnabled)

        await context.viewModel.loadWeightSuggestions()

        XCTAssertTrue(context.viewModel.suggestionAdminModeEnabled)
    }

    func testAdminModeDoesNotChangeSuggestionOutputs() async throws {
        let userContext = makeContext(
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            profile: HealthProfile(prescriptionAdminModeEnabled: false)
        )
        let adminContext = makeContext(
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            profile: HealthProfile(prescriptionAdminModeEnabled: true)
        )

        await userContext.viewModel.loadWeightSuggestions()
        await adminContext.viewModel.loadWeightSuggestions()

        let userSuggestion = try XCTUnwrap(userContext.viewModel.weightSuggestionData?.suggestions.first)
        let adminSuggestion = try XCTUnwrap(adminContext.viewModel.weightSuggestionData?.suggestions.first)

        XCTAssertEqual(userSuggestion.suggestedWeight, adminSuggestion.suggestedWeight)
        XCTAssertEqual(userSuggestion.targetReps, adminSuggestion.targetReps)
        XCTAssertEqual(
            userContext.viewModel.weightSuggestionData?.unavailableReason,
            adminContext.viewModel.weightSuggestionData?.unavailableReason
        )
        XCTAssertFalse(userContext.viewModel.suggestionAdminModeEnabled)
        XCTAssertTrue(adminContext.viewModel.suggestionAdminModeEnabled)
    }

    func testSetMutationFlowsStillSucceedThroughSetService() async throws {
        let profile = HealthProfile()
        let setService = SetServiceStub()
        let exercise = makeExercise(name: "Bench Press")
        let workout = Workout(
            date: Date(),
            startTime: Date(),
            status: .inProgress
        )
        let uncompletedSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            weight: 100,
            reps: 5,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        let deletedSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            weight: 90,
            reps: 8,
            setType: .working,
            orderInWorkout: 2,
            orderInExercise: 2,
            completed: true
        )
        let typeChangedSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            weight: 80,
            reps: 10,
            setType: .working,
            orderInWorkout: 3,
            orderInExercise: 3,
            completed: true
        )

        let viewModel = ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: setService,
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )
        viewModel.workout = workout
        viewModel.exercises = [exercise]
        viewModel.setsByExercise = [exercise.id: [uncompletedSet, deletedSet, typeChangedSet]]

        await viewModel.uncompleteSet(uncompletedSet)
        await viewModel.deleteSet(deletedSet)
        await viewModel.changeSetType(typeChangedSet, to: .warmup)

        XCTAssertEqual(setService.uncompletedSetIds, [uncompletedSet.id])
        XCTAssertEqual(setService.deletedSetIds, [deletedSet.id])
        XCTAssertTrue(setService.editedSetIds.contains(typeChangedSet.id))
        XCTAssertFalse(uncompletedSet.completed)
        XCTAssertEqual(typeChangedSet.setType, SetType.warmup)
        XCTAssertEqual(viewModel.currentSets.map(\.id), [uncompletedSet.id, typeChangedSet.id])
    }

    private func makeContext(
        loadPrescriptionService: LoadPrescriptionServiceSpy,
        setService: SetServiceStub = SetServiceStub(),
        profile: HealthProfile = HealthProfile(),
        exerciseCount: Int = 1,
        initialReps: Int = 8,
        secondExerciseReps: Int = 12
    ) -> TestContext {
        let exercise = makeExercise(name: "Exercise 1")
        let pendingSet = makeSet(exerciseId: exercise.id, order: 1, reps: initialReps)

        let viewModel = ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: setService,
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: loadPrescriptionService,
            fatigueLearningService: makeStubFatigueLearningService()
        )

        viewModel.exercises = [exercise]
        viewModel.selectedExerciseIndex = 0
        viewModel.setsByExercise = [exercise.id: [pendingSet]]

        var secondExercise: Exercise?
        if exerciseCount > 1 {
            let otherExercise = makeExercise(name: "Exercise 2")
            let otherSet = makeSet(exerciseId: otherExercise.id, order: 1, reps: secondExerciseReps)
            viewModel.exercises.append(otherExercise)
            viewModel.setsByExercise[otherExercise.id] = [otherSet]
            loadPrescriptionService.exerciseNames[otherExercise.id] = otherExercise.name
            secondExercise = otherExercise
        }
        loadPrescriptionService.exerciseNames[exercise.id] = exercise.name

        return TestContext(
            viewModel: viewModel,
            exercise: exercise,
            pendingSet: pendingSet,
            secondExercise: secondExercise
        )
    }

    private func makeExercise(
        name: String,
        unilateral: Bool = false,
        unilateralRepTargetMode: UnilateralRepTargetMode? = nil
    ) -> Exercise {
        Exercise(
            name: name,
            equipmentType: .barbell,
            trackingType: .weightReps,
            unilateral: unilateral,
            unilateralRepTargetMode: unilateralRepTargetMode,
            weightIncrement: 2.5,
            defaultRestTime: 120
        )
    }

    private func makeSet(exerciseId: UUID, order: Int, reps: Int) -> WorkoutSet {
        WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseId,
            reps: reps,
            rir: 2.0,
            orderInWorkout: order,
            orderInExercise: order,
            completed: false
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while !condition() {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: pollInterval)
        }
    }
}

final class WeightSuggestionDataRowStateTests: XCTestCase {

    func testMixedRowStatesPreserveAvailableAndUnavailableRows() {
        let availableSetId = UUID()
        let unavailableSetId = UUID()
        let target = SuggestionTarget(
            reps: 8,
            rir: 2.0,
            repRange: nil,
            repsSource: .template,
            rirSource: .template
        )
        let pendingSet = SuggestionPendingSetInput(
            setId: availableSetId,
            setIndex: 0,
            setNumber: 1,
            target: target,
            setType: .working
        )
        let preparation = SuggestionPreparation(
            cacheKey: "mixed-row-states",
            completedSessionSets: [],
            setResolutions: [
                SuggestionSetResolution(
                    setId: availableSetId,
                    setIndex: 0,
                    setNumber: 1,
                    eligibility: .eligible(target: target),
                    setType: .working
                ),
                SuggestionSetResolution(
                    setId: unavailableSetId,
                    setIndex: 1,
                    setNumber: 2,
                    eligibility: .ineligible(reason: .missingTarget),
                    setType: .working
                )
            ],
            pendingSets: [pendingSet],
            unavailableReason: nil
        )

        let input = makeInput(pendingSets: [pendingSet])
        let evaluation = SuggestionEvaluation(
            input: input,
            decisions: [
                makeDecision(
                    setId: availableSetId,
                    setIndex: 0,
                    setNumber: 1,
                    target: target
                )
            ],
            unavailableReason: nil
        )

        let data = SuggestionExplainer.makeWeightSuggestionData(
            preparation: preparation,
            evaluation: evaluation,
            unitPreference: .metric
        )

        XCTAssertEqual(data.rowStates.count, 2)
        XCTAssertEqual(data.suggestions.count, 1)
        XCTAssertEqual(data.rowState(for: availableSetId)?.suggestion?.suggestedWeight, 80)
        XCTAssertEqual(data.rowState(for: unavailableSetId)?.unavailableReason, .missingTarget)

        guard case .available = data.availability else {
            return XCTFail("Expected module availability to remain available when at least one row has a suggestion")
        }
    }

    func testEligibleRowsReceiveModuleUnavailableReasonWhenEvaluationFails() {
        let setId = UUID()
        let target = SuggestionTarget(
            reps: 8,
            rir: 2.0,
            repRange: nil,
            repsSource: .explicitSet,
            rirSource: .explicitSet
        )
        let pendingSet = SuggestionPendingSetInput(
            setId: setId,
            setIndex: 0,
            setNumber: 1,
            target: target,
            setType: .working
        )
        let preparation = SuggestionPreparation(
            cacheKey: "module-failure",
            completedSessionSets: [],
            setResolutions: [
                SuggestionSetResolution(
                    setId: setId,
                    setIndex: 0,
                    setNumber: 1,
                    eligibility: .eligible(target: target),
                    setType: .working
                )
            ],
            pendingSets: [pendingSet],
            unavailableReason: nil
        )

        let data = SuggestionExplainer.makeWeightSuggestionData(
            preparation: preparation,
            evaluation: .unavailable(.noStrengthData),
            unitPreference: .metric
        )

        XCTAssertNil(data.suggestion(for: setId))
        XCTAssertEqual(data.rowState(for: setId)?.target?.reps, 8)
        XCTAssertEqual(data.rowState(for: setId)?.unavailableReason, .noStrengthData)
        XCTAssertEqual(data.unavailableReason, .noStrengthData)
    }

    func testMissingTargetUsesSmartSuggestionsDefaultTarget() throws {
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        let profile = HealthProfile()

        let preparation = SuggestionCoordinator.prepare(
            exercise: exercise,
            sets: [set],
            profile: profile
        )

        XCTAssertEqual(preparation.pendingSets.count, 1)
        XCTAssertNil(preparation.unavailableReason)

        let target = try XCTUnwrap(preparation.pendingSets.first?.target)
        XCTAssertEqual(target.reps, 8)
        XCTAssertEqual(target.rir, 2.0)
        XCTAssertEqual(target.repsSource, .smartDefault)
        XCTAssertEqual(target.rirSource, .smartDefault)

        let evaluation = SuggestionEvaluation(
            input: makeInput(pendingSets: preparation.pendingSets),
            decisions: [
                makeDecision(
                    setId: set.id,
                    setIndex: 0,
                    setNumber: 1,
                    target: preparation.pendingSets[0].target
                )
            ],
            unavailableReason: nil
        )

        let data = SuggestionExplainer.makeWeightSuggestionData(
            preparation: preparation,
            evaluation: evaluation,
            unitPreference: .metric
        )

        XCTAssertEqual(data.suggestion(for: set.id)?.explanation.defaultUsageLabel, "using default target")
        XCTAssertEqual(
            data.suggestion(for: set.id)?.explanation.userSummary,
            "Based on your recent performance and this set's target. Missing targets used your Smart Suggestions defaults."
        )
        XCTAssertTrue(
            data.suggestion(for: set.id)?.explanation.adminSummary.contains("target from Smart Suggestions default") == true
        )
        XCTAssertEqual(data.rowState(for: set.id)?.target?.sourceLabel, "Smart Suggestions default")
    }

    func testSuggestionExplanationSeparatesUserAndAdminSummaryCopy() throws {
        let setId = UUID()
        let target = SuggestionTarget(
            reps: 8,
            rir: 2.0,
            repRange: nil,
            repsSource: .template,
            rirSource: .template
        )
        let pendingSet = SuggestionPendingSetInput(
            setId: setId,
            setIndex: 0,
            setNumber: 1,
            target: target,
            setType: .working
        )
        let preparation = SuggestionPreparation(
            cacheKey: "summary-copy",
            completedSessionSets: [],
            setResolutions: [
                SuggestionSetResolution(
                    setId: setId,
                    setIndex: 0,
                    setNumber: 1,
                    eligibility: .eligible(target: target),
                    setType: .working
                )
            ],
            pendingSets: [pendingSet],
            unavailableReason: nil
        )
        let evaluation = SuggestionEvaluation(
            input: makeInput(pendingSets: [pendingSet]),
            decisions: [
                makeDecision(
                    setId: setId,
                    setIndex: 0,
                    setNumber: 1,
                    target: target,
                    historicalBaseE1RM: 100,
                    sessionCapabilityE1RM: 104,
                    effectiveE1RM: 101,
                    fatigueDiscount: 0.96,
                    projectedSessionFatigue: 0.12
                )
            ],
            unavailableReason: nil
        )

        let data = SuggestionExplainer.makeWeightSuggestionData(
            preparation: preparation,
            evaluation: evaluation,
            unitPreference: .metric
        )
        let suggestion = try XCTUnwrap(data.suggestion(for: setId))

        XCTAssertEqual(
            suggestion.explanation.userSummary,
            "Based on your recent performance and adjusted for this workout."
        )
        XCTAssertTrue(suggestion.explanation.adminSummary.contains("capacity from"))
        XCTAssertTrue(suggestion.explanation.adminSummary.contains("readiness"))
        XCTAssertNotEqual(suggestion.explanation.userSummary, suggestion.explanation.adminSummary)
    }

    func testDiagnosticsCarryFirstSetProgressionBiasMetadata() throws {
        let setId = UUID()
        let target = SuggestionTarget(
            reps: 9,
            rir: 0.0,
            repRange: 5...10,
            repsSource: .template,
            rirSource: .template
        )
        let pendingSet = SuggestionPendingSetInput(
            setId: setId,
            setIndex: 0,
            setNumber: 1,
            target: target,
            setType: .working
        )
        let preparation = SuggestionPreparation(
            cacheKey: "selection-bias",
            completedSessionSets: [],
            setResolutions: [
                SuggestionSetResolution(
                    setId: setId,
                    setIndex: 0,
                    setNumber: 1,
                    eligibility: .eligible(target: target),
                    setType: .working
                )
            ],
            pendingSets: [pendingSet],
            unavailableReason: nil
        )
        let evaluation = SuggestionEvaluation(
            input: makeInput(pendingSets: [pendingSet]),
            decisions: [
                makeDecision(
                    setId: setId,
                    setIndex: 0,
                    setNumber: 1,
                    target: target,
                    selectionPolicy: .firstSetProgressionAboveRecentPeak,
                    selectionReferenceE1RM: 104
                )
            ],
            unavailableReason: nil
        )

        let data = SuggestionExplainer.makeWeightSuggestionData(
            preparation: preparation,
            evaluation: evaluation,
            unitPreference: .metric
        )
        let suggestion = try XCTUnwrap(data.suggestion(for: setId))
        let selectionReferenceE1RM = try XCTUnwrap(suggestion.diagnostics.selectionReferenceE1RM)

        XCTAssertEqual(suggestion.diagnostics.selectionPolicy, .firstSetProgressionAboveRecentPeak)
        XCTAssertEqual(selectionReferenceE1RM, 104, accuracy: 0.001)
    }

    func testPartialTargetUsesDefaultForMissingPiece() throws {
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            reps: 10,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        let profile = HealthProfile()

        let preparation = SuggestionCoordinator.prepare(
            exercise: exercise,
            sets: [set],
            profile: profile
        )

        let target = try XCTUnwrap(preparation.pendingSets.first?.target)
        XCTAssertEqual(target.reps, 10)
        XCTAssertEqual(target.rir, 2.0)
        XCTAssertEqual(target.repsSource, .explicitSet)
        XCTAssertEqual(target.rirSource, .smartDefault)
    }

    func testManualRangeUsesExplicitSetSourceAndDefaultRIR() throws {
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        set.overrideTargetRepMin = 8
        set.overrideTargetRepMax = 12
        let profile = HealthProfile()

        let preparation = SuggestionCoordinator.prepare(
            exercise: exercise,
            sets: [set],
            profile: profile
        )

        let target = try XCTUnwrap(preparation.pendingSets.first?.target)
        XCTAssertEqual(target.repRange, 8...12)
        XCTAssertEqual(target.reps, 10)
        XCTAssertEqual(target.repsSource, .explicitSet)
        XCTAssertEqual(target.rirSource, .smartDefault)
    }

    func testTotalAcrossSidesTargetNormalizesPendingSuggestionReps() throws {
        let exercise = Exercise(
            name: "Dumbbell Lunge",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        set.targetRepMin = 20
        set.targetRepMax = 20
        let profile = HealthProfile()

        let preparation = SuggestionCoordinator.prepare(
            exercise: exercise,
            sets: [set],
            profile: profile
        )

        let target = try XCTUnwrap(preparation.pendingSets.first?.target)
        XCTAssertEqual(target.reps, 10)
        XCTAssertEqual(target.displayReps, 20)
        XCTAssertEqual(target.displayTargetLabel, "20 total reps")
        XCTAssertEqual(target.normalizedTargetLabel, "normalized to 10 reps each side")
    }

    func testTotalAcrossSidesRepRangeNormalizesBoundByBound() throws {
        let exercise = Exercise(
            name: "Dumbbell Lunge",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        set.overrideTargetRepMin = 20
        set.overrideTargetRepMax = 24
        let profile = HealthProfile()

        let preparation = SuggestionCoordinator.prepare(
            exercise: exercise,
            sets: [set],
            profile: profile
        )

        let target = try XCTUnwrap(preparation.pendingSets.first?.target)
        XCTAssertEqual(target.reps, 11)
        XCTAssertEqual(target.repRange, 10...12)
        XCTAssertEqual(target.displayRepRange, 20...24)
    }

    func testTotalAcrossSidesSuggestionCarriesDisplayAndNormalizedTargetLabels() throws {
        let setId = UUID()
        let target = SuggestionTarget(
            reps: 10,
            rir: 2.0,
            repRange: nil,
            repsSource: .template,
            rirSource: .template,
            displayReps: 20,
            displayRepRange: nil,
            repTargetMode: .totalAcrossSides
        )
        let pendingSet = SuggestionPendingSetInput(
            setId: setId,
            setIndex: 0,
            setNumber: 1,
            target: target,
            setType: .working
        )
        let preparation = SuggestionPreparation(
            cacheKey: "total-across-sides",
            completedSessionSets: [],
            setResolutions: [
                SuggestionSetResolution(
                    setId: setId,
                    setIndex: 0,
                    setNumber: 1,
                    eligibility: .eligible(target: target),
                    setType: .working
                )
            ],
            pendingSets: [pendingSet],
            unavailableReason: nil
        )
        let evaluation = SuggestionEvaluation(
            input: makeInput(pendingSets: [pendingSet]),
            decisions: [
                makeDecision(
                    setId: setId,
                    setIndex: 0,
                    setNumber: 1,
                    target: target
                )
            ],
            unavailableReason: nil
        )

        let data = SuggestionExplainer.makeWeightSuggestionData(
            preparation: preparation,
            evaluation: evaluation,
            unitPreference: .metric
        )
        let suggestion = try XCTUnwrap(data.suggestion(for: setId))

        XCTAssertEqual(suggestion.targetReps, 20)
        XCTAssertEqual(suggestion.targetDisplayLabel, "20 total reps")
        XCTAssertEqual(suggestion.normalizedTargetLabel, "normalized to 10 reps each side")
        XCTAssertEqual(suggestion.diagnostics.normalizedTargetReps, 10)
        XCTAssertEqual(suggestion.diagnostics.targetDisplayLabel, "20 total reps")
        XCTAssertTrue(suggestion.explanation.adminSummary.contains("normalized to 10 reps each side"))
    }

    func testTotalAcrossSidesUnilateralRowUsesSharedHintInsteadOfDuplicatedPlaceholders() {
        let exercise = Exercise(
            name: "Dumbbell Lunge",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            orderInWorkout: 1,
            orderInExercise: 1
        )
        set.targetRepMin = 20
        set.targetRepMax = 20

        let presentation = SetTableView.unilateralTargetPresentation(for: set, exercise: exercise)

        XCTAssertEqual(presentation.leftPlaceholder, "0")
        XCTAssertEqual(presentation.rightPlaceholder, "0")
        XCTAssertEqual(presentation.sharedHint, "20 total")
    }

    func testInvalidDefaultsStillYieldMissingTarget() {
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        let profile = HealthProfile()
        profile.prescriptionDefaultTargetReps = 0
        profile.prescriptionDefaultTargetRIR = nil

        let preparation = SuggestionCoordinator.prepare(
            exercise: exercise,
            sets: [set],
            profile: profile
        )

        XCTAssertTrue(preparation.pendingSets.isEmpty)
        XCTAssertEqual(preparation.unavailableReason, .missingTarget)
    }

    func testWholeWorkoutExclusionStillAllowsSuggestionsAndChangesCacheKey() {
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        let workoutId = UUID()
        let set = WorkoutSet(
            workoutId: workoutId,
            exerciseId: exercise.id,
            reps: 8,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        let profile = HealthProfile()
        let includedWorkout = Workout(
            id: workoutId,
            date: Date(),
            excludeFromProgressionHistory: false
        )
        let excludedWorkout = Workout(
            id: workoutId,
            date: Date(),
            excludeFromProgressionHistory: true
        )

        let included = SuggestionCoordinator.prepare(
            exercise: exercise,
            workout: includedWorkout,
            sets: [set],
            profile: profile
        )
        let excluded = SuggestionCoordinator.prepare(
            exercise: exercise,
            workout: excludedWorkout,
            sets: [set],
            profile: profile
        )

        XCTAssertNil(included.unavailableReason)
        XCTAssertNil(excluded.unavailableReason)
        XCTAssertEqual(excluded.pendingSets.count, 1)
        XCTAssertNotEqual(included.cacheKey, excluded.cacheKey)
    }

    func testExerciseScopedExclusionStillAllowsSuggestions() {
        let excludedExercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        let allowedExercise = Exercise(
            name: "Incline Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        let workoutId = UUID()
        let workout = Workout(
            id: workoutId,
            date: Date(),
            excludedExerciseIdsFromProgressionHistory: [excludedExercise.id]
        )
        let excludedSet = WorkoutSet(
            workoutId: workoutId,
            exerciseId: excludedExercise.id,
            reps: 8,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        let allowedSet = WorkoutSet(
            workoutId: workoutId,
            exerciseId: allowedExercise.id,
            reps: 8,
            orderInWorkout: 2,
            orderInExercise: 1,
            completed: false
        )
        let profile = HealthProfile()

        let excluded = SuggestionCoordinator.prepare(
            exercise: excludedExercise,
            workout: workout,
            sets: [excludedSet],
            profile: profile
        )
        let allowed = SuggestionCoordinator.prepare(
            exercise: allowedExercise,
            workout: workout,
            sets: [allowedSet],
            profile: profile
        )

        XCTAssertNil(excluded.unavailableReason)
        XCTAssertEqual(excluded.pendingSets.count, 1)
        XCTAssertNil(allowed.unavailableReason)
    }

    private func makeInput(pendingSets: [SuggestionPendingSetInput]) -> SuggestionEngineInput {
        SuggestionEngineInput(
            baseE1RM: 100,
            baseSource: .recentPerformance,
            completedSessionSets: [],
            pendingSets: pendingSets,
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )
    }

    private func makeDecision(
        setId: UUID,
        setIndex: Int,
        setNumber: Int,
        target: SuggestionTarget,
        historicalBaseE1RM: Double = 100,
        sessionCapabilityE1RM: Double = 100,
        effectiveE1RM: Double = 100,
        fatigueDiscount: Double = 1.0,
        freshnessApplied: Bool = false,
        selectionPolicy: SuggestionSelectionPolicy = .closestMatch,
        selectionReferenceE1RM: Double? = nil,
        projectedSessionFatigue: Double = 0.0
    ) -> SuggestionDecision {
        SuggestionDecision(
            setId: setId,
            setIndex: setIndex,
            setNumber: setNumber,
            target: target,
            prescribedWeight: 80,
            rawWeight: 79.4,
            weightIncrement: 2.5,
            baseE1RM: 100,
            historicalBaseE1RM: historicalBaseE1RM,
            sessionCapabilityE1RM: sessionCapabilityE1RM,
            effectiveE1RM: effectiveE1RM,
            intensityFactor: 0.8,
            fatigueDiscount: fatigueDiscount,
            freshnessApplied: freshnessApplied,
            e1RMSource: .recentPerformance,
            sessionCapabilitySourceLabel: SessionCapabilityPolicy.observed.label,
            bestReps: nil,
            selectionPolicy: selectionPolicy,
            selectionReferenceE1RM: selectionReferenceE1RM,
            calibrationAdjustment: .neutral,
            projectedSessionFatigue: projectedSessionFatigue
        )
    }
}

final class RepsTargetInputParserTests: XCTestCase {
    func testParseManualRepRange() {
        XCTAssertEqual(RepsTargetInputParser.parse("8-12"), .range(8, 12))
        XCTAssertEqual(RepsTargetInputParser.parse(" 8 - 12 "), .range(8, 12))
    }

    func testParseSingleRepValue() {
        XCTAssertEqual(RepsTargetInputParser.parse("10"), .single(10))
    }

    func testParseInvalidPartialRange() {
        XCTAssertEqual(RepsTargetInputParser.parse("8-"), .invalid)
        XCTAssertEqual(RepsTargetInputParser.parse("8-8"), .invalid)
    }
}

final class SmartSuggestionSettingsTests: XCTestCase {
    func testSettingsServiceClampsDefaultTargets() async throws {
        let profile = HealthProfile()
        let repo = HealthProfileRepositoryStub(profile: profile)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
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
            configurations: config
        )
        let service = SettingsService(
            healthProfileRepository: repo,
            prService: PRServiceStub(),
            statsService: StatsServiceStub(),
            modelContainer: container,
            seedExercises: { _ in }
        )

        try await service.updatePrescriptionDefaultTargetReps(99)
        try await service.updatePrescriptionDefaultTargetRIR(-2)

        XCTAssertEqual(profile.prescriptionDefaultTargetReps, 30)
        XCTAssertEqual(profile.prescriptionDefaultTargetRIR, 0)
    }

    func testSettingsServicePersistsAdminModeAndUpdatesTimestamp() async throws {
        let initialUpdatedAt = Date(timeIntervalSince1970: 1_000)
        let profile = HealthProfile(
            prescriptionAdminModeEnabled: false,
            updatedAt: initialUpdatedAt
        )
        let repo = HealthProfileRepositoryStub(profile: profile)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
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
            configurations: config
        )
        let service = SettingsService(
            healthProfileRepository: repo,
            prService: PRServiceStub(),
            statsService: StatsServiceStub(),
            modelContainer: container,
            seedExercises: { _ in }
        )

        try await service.updatePrescriptionAdminModeEnabled(true)
        XCTAssertEqual(profile.prescriptionAdminModeEnabled, true)
        XCTAssertGreaterThan(profile.updatedAt, initialUpdatedAt)

        let updatedAfterEnable = profile.updatedAt
        try await service.updatePrescriptionAdminModeEnabled(false)

        XCTAssertEqual(profile.prescriptionAdminModeEnabled, false)
        XCTAssertGreaterThanOrEqual(profile.updatedAt, updatedAfterEnable)
    }

    func testHealthProfileRepositoryBackfillsDefaultTargetsAndAdminMode() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: HealthProfile.self, configurations: config)
        let context = ModelContext(container)
        let existing = HealthProfile()
        existing.prescriptionDefaultTargetReps = nil
        existing.prescriptionDefaultTargetRIR = nil
        existing.prescriptionAdminModeEnabled = nil
        context.insert(existing)
        try context.save()

        let repo = HealthProfileRepository(modelContainer: container)
        let profile = try await repo.fetchOrCreate()

        XCTAssertEqual(profile.prescriptionDefaultTargetReps, 8)
        XCTAssertEqual(profile.prescriptionDefaultTargetRIR, 2)
        XCTAssertEqual(profile.prescriptionAdminModeEnabled, false)
    }
}

final class ExerciseTrackingTypeTests: XCTestCase {
    func testExerciseServiceAllowsTrackingTypeChangeWhenNoSetsExist() async throws {
        let context = try makeExerciseTrackingTypeServiceContext()
        let exercise = Exercise(
            name: "Treadmill",
            equipmentType: .bodyweight,
            trackingType: .duration
        )
        try await context.exerciseRepo.save(exercise)

        exercise.trackingType = .durationDistance

        try await context.service.updateExercise(exercise, originalTrackingType: .duration)

        let persisted = try await context.exerciseRepo.fetch(byId: exercise.id)
        XCTAssertEqual(persisted?.trackingType, .durationDistance)
    }

    func testExerciseServiceAllowsTrackingTypeChangeWhenOnlyPlaceholderSetsExist() async throws {
        let context = try makeExerciseTrackingTypeServiceContext()
        let exercise = Exercise(
            name: "Treadmill",
            equipmentType: .bodyweight,
            trackingType: .duration
        )
        try await context.exerciseRepo.save(exercise)
        try await context.setRepo.save(
            WorkoutSet(
                workoutId: UUID(),
                exerciseId: exercise.id,
                orderInWorkout: 1,
                orderInExercise: 1,
                completed: false
            )
        )

        exercise.trackingType = .durationDistance

        try await context.service.updateExercise(exercise, originalTrackingType: .duration)

        let persisted = try await context.exerciseRepo.fetch(byId: exercise.id)
        XCTAssertEqual(persisted?.trackingType, .durationDistance)
    }

    func testExerciseServiceRejectsTrackingTypeChangeWhenLoggedSetDataExists() async throws {
        let context = try makeExerciseTrackingTypeServiceContext()
        let exercise = Exercise(
            name: "Treadmill",
            equipmentType: .bodyweight,
            trackingType: .duration
        )
        try await context.exerciseRepo.save(exercise)
        try await context.setRepo.save(
            WorkoutSet(
                workoutId: UUID(),
                exerciseId: exercise.id,
                durationSeconds: 900,
                distanceMeters: 2400,
                orderInWorkout: 1,
                orderInExercise: 1,
                completed: true
            )
        )

        exercise.trackingType = .durationDistance

        do {
            try await context.service.updateExercise(exercise, originalTrackingType: .duration)
            XCTFail("Expected tracking type change to be rejected once logged data exists")
        } catch let error as ExerciseServiceError {
            guard case .trackingTypeImmutable(let exerciseId) = error else {
                return XCTFail("Unexpected exercise service error: \(error)")
            }
            XCTAssertEqual(exerciseId, exercise.id)
        }
    }
}

@MainActor
final class TemplateImportExportTests: XCTestCase {
    func testExportAITemplateContextIncludesMetadataAndStats() async throws {
        let context = try makeTemplateServiceContext()
        let exercise = Exercise(
            name: "Dumbbell Lunge",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            primaryMuscle: "legs",
            secondaryMuscles: ["glutes", "core"],
            movementPattern: .squat,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides,
            bodyweightFactor: 0.35,
            weightIncrement: 2.5,
            defaultRestTime: 180
        )
        try await context.exerciseRepo.save(exercise)
        try await context.exerciseStatsRepo.save(
            ExerciseStats(
                exerciseId: exercise.id,
                totalWorkouts: 12,
                totalSets: 36,
                maxWeight: 102.5,
                bestE1RM: 118.4,
                lastPerformedDate: makeDate(2026, 3, 20, 9, 0)
            )
        )

        let exportedData = try await context.service.exportAITemplateContext()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(AITemplateContextArchive.self, from: exportedData)
        let exportedExercise = try XCTUnwrap(archive.exercises.first(where: { $0.exerciseId == exercise.id }))

        XCTAssertEqual(archive.version, AITemplateContextArchive.currentVersion)
        XCTAssertEqual(exportedExercise.exerciseName, "Dumbbell Lunge")
        XCTAssertEqual(exportedExercise.equipmentType, .dumbbell)
        XCTAssertEqual(exportedExercise.trackingType, .weightReps)
        XCTAssertEqual(exportedExercise.primaryMuscle, "legs")
        XCTAssertEqual(exportedExercise.secondaryMuscles, ["glutes", "core"])
        XCTAssertEqual(exportedExercise.movementPattern, .squat)
        XCTAssertEqual(exportedExercise.unilateralRepTargetMode, .totalAcrossSides)
        XCTAssertEqual(exportedExercise.stats.totalWorkouts, 12)
        XCTAssertEqual(exportedExercise.stats.totalSets, 36)
        XCTAssertEqual(exportedExercise.stats.maxWeight, 102.5)
        XCTAssertEqual(exportedExercise.stats.bestE1RM, 118.4)
        XCTAssertEqual(exportedExercise.stats.lastPerformedDate, makeDate(2026, 3, 20, 9, 0))
    }

    func testExportImportRoundtripPreservesTemplateStructure() async throws {
        let context = try makeTemplateServiceContext()
        let squat = makeExercise(name: "Back Squat", primaryMuscle: "legs", defaultRestTime: 180)
        let bench = makeExercise(
            name: "Bench Press",
            primaryMuscle: "chest",
            defaultRestTime: 120,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides
        )
        try await context.exerciseRepo.save(squat)
        try await context.exerciseRepo.save(bench)

        let supersetGroupId = UUID()
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Strength Day",
                notes: "Heavy compounds",
                exercises: [
                    TemplateSaveExercise(
                        exerciseId: squat.id,
                        orderInTemplate: 1,
                        supersetGroupId: supersetGroupId,
                        restTimeSeconds: 180,
                        notes: "Brace hard",
                        sets: [
                            TemplateSaveSet(
                                setType: .warmup,
                                targetRepMin: 5,
                                targetRepMax: 5,
                                targetRIR: 4,
                                orderInExercise: 1
                            ),
                            TemplateSaveSet(
                                setType: .working,
                                targetRepMin: 3,
                                targetRepMax: 5,
                                targetRIR: 2,
                                orderInExercise: 2
                            )
                        ]
                    ),
                    TemplateSaveExercise(
                        exerciseId: bench.id,
                        orderInTemplate: 2,
                        supersetGroupId: supersetGroupId,
                        restTimeSeconds: 120,
                        notes: "Pause first rep",
                        sets: [
                            TemplateSaveSet(
                                setType: .working,
                                targetRepMin: 6,
                                targetRepMax: 8,
                                targetRIR: 1,
                                orderInExercise: 1
                            )
                        ]
                    )
                ]
            )
        )

        let exportedData = try await context.service.exportTemplate(templateId)
        let exportedArchive = try JSONDecoder().decode(TemplateArchive.self, from: exportedData)
        let importedTemplateId = try await context.service.importTemplate(data: exportedData)
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)
        let exercises = try await context.exerciseRepo.fetchAll()
        let exportedBench = try XCTUnwrap(exportedArchive.exercises.last)

        XCTAssertEqual(importedDetail.template.name, "Strength Day (Imported)")
        XCTAssertEqual(importedDetail.template.notes, "Heavy compounds")
        XCTAssertEqual(importedDetail.exercises.count, 2)
        XCTAssertEqual(exercises.count, 2, "Import should reuse existing exercises via UUID match.")
        XCTAssertEqual(exportedBench.exercise.id, bench.id)
        XCTAssertEqual(exportedBench.exercise.unilateralRepTargetMode, .totalAcrossSides)

        let importedSquat = try XCTUnwrap(importedDetail.exercises.first)
        XCTAssertEqual(importedSquat.exerciseId, squat.id)
        XCTAssertEqual(importedSquat.orderInTemplate, 1)
        XCTAssertEqual(importedSquat.restTimeSeconds, 180)
        XCTAssertEqual(importedSquat.notes, "Brace hard")
        XCTAssertEqual(importedSquat.sets.map(\.orderInExercise), [1, 2])
        XCTAssertEqual(importedSquat.sets.map(\.setType), [.warmup, .working])
        XCTAssertEqual(importedSquat.sets.map(\.targetRepMin), [5 as Int?, 3])
        XCTAssertEqual(importedSquat.sets.map(\.targetRepMax), [5 as Int?, 5])
        XCTAssertEqual(importedSquat.sets.map(\.targetRIR), [4 as Int?, 2])

        let importedBench = try XCTUnwrap(importedDetail.exercises.last)
        XCTAssertEqual(importedBench.exerciseId, bench.id)
        XCTAssertEqual(importedBench.orderInTemplate, 2)
        XCTAssertEqual(importedBench.restTimeSeconds, 120)
        XCTAssertEqual(importedBench.notes, "Pause first rep")
        XCTAssertEqual(importedBench.sets.count, 1)
        XCTAssertEqual(importedBench.sets.first?.targetRepMin, 6)
        XCTAssertEqual(importedBench.sets.first?.targetRepMax, 8)
        XCTAssertEqual(importedBench.sets.first?.targetRIR, 1)
        XCTAssertEqual(importedSquat.supersetGroupId, importedBench.supersetGroupId)
    }

    func testImportMatchesExistingExerciseByNormalizedName() async throws {
        let context = try makeTemplateServiceContext()
        let existingExercise = makeExercise(name: "Incline Bench Press", primaryMuscle: "chest", defaultRestTime: 90)
        try await context.exerciseRepo.save(existingExercise)

        let archiveData = try makeArchiveData(
            templateName: "Upper Builder",
            exercises: [
                makeArchiveExercise(
                    exerciseId: UUID(),
                    exerciseName: "  incline   bench press  ",
                    primaryMuscle: "chest",
                    defaultRestTime: 90,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 8,
                            targetRepMax: 10,
                            targetRIR: 2,
                            orderInExercise: 1
                        )
                    ]
                )
            ]
        )

        let importedTemplateId = try await context.service.importTemplate(data: archiveData)
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)
        let exercises = try await context.exerciseRepo.fetchAll()

        XCTAssertEqual(importedDetail.exercises.first?.exerciseId, existingExercise.id)
        XCTAssertEqual(exercises.count, 1, "Import should reuse an existing exercise matched by name.")
    }

    func testPreviewAndFinalizeCanCreateMissingExerciseFromArchiveMetadata() async throws {
        let context = try makeTemplateServiceContext()
        let archivedExerciseId = UUID()

        let archiveData = try makeArchiveData(
            templateName: "Travel Workout",
            exercises: [
                makeArchiveExercise(
                    exerciseId: archivedExerciseId,
                    exerciseName: "Single Arm Cable Row",
                    primaryMuscle: "back",
                    defaultRestTime: 75,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 10,
                            targetRepMax: 12,
                            targetRIR: 1,
                            orderInExercise: 1
                        )
                    ],
                    unilateral: true,
                    unilateralRepTargetMode: .totalAcrossSides,
                    trackingType: .weightReps,
                    equipmentType: .cable
                )
            ]
        )

        let preview = try await context.service.previewTemplateImport(data: archiveData)
        XCTAssertEqual(preview.unresolvedExercises.count, 1)
        XCTAssertEqual(preview.unresolvedExercises.first?.exercise.name, "Single Arm Cable Row")
        XCTAssertEqual(preview.unresolvedExercises.first?.exercise.unilateralRepTargetMode, .totalAcrossSides)

        do {
            _ = try await context.service.importTemplate(data: archiveData)
            XCTFail("Expected direct import to require exercise resolution")
        } catch let error as TemplateServiceError {
            guard case .importRequiresResolution(let unresolvedCount) = error else {
                return XCTFail("Unexpected template service error: \(error)")
            }
            XCTAssertEqual(unresolvedCount, 1)
        }

        let importedTemplateId = try await context.service.finalizeTemplateImport(
            preview,
            resolutions: [
                TemplateImportExerciseResolution(
                    previewExerciseId: try XCTUnwrap(preview.unresolvedExercises.first?.id),
                    action: .createNew
                )
            ]
        )
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)
        let createdExercise = try await context.exerciseRepo.fetch(byId: archivedExerciseId)

        XCTAssertEqual(importedDetail.exercises.first?.exerciseId, archivedExerciseId)
        XCTAssertEqual(createdExercise?.name, "Single Arm Cable Row")
        XCTAssertEqual(createdExercise?.primaryMuscle, "back")
        XCTAssertEqual(createdExercise?.defaultRestTime, 75)
        XCTAssertEqual(createdExercise?.unilateral, true)
        XCTAssertEqual(createdExercise?.unilateralRepTargetMode, .totalAcrossSides)
        XCTAssertEqual(createdExercise?.equipmentType, .cable)
    }

    func testFinalizeImportCanMapMissingExerciseToExistingExercise() async throws {
        let context = try makeTemplateServiceContext()
        let existingExercise = Exercise(
            name: "Cable Row",
            equipmentType: .cable,
            trackingType: .weightReps,
            primaryMuscle: "back",
            unilateral: false,
            defaultRestTime: 75
        )
        try await context.exerciseRepo.save(existingExercise)

        let archiveData = try makeArchiveData(
            templateName: "Travel Workout",
            exercises: [
                makeArchiveExercise(
                    exerciseId: UUID(),
                    exerciseName: "Single Arm Cable Row",
                    primaryMuscle: "back",
                    defaultRestTime: 75,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 10,
                            targetRepMax: 12,
                            targetRIR: 1,
                            orderInExercise: 1
                        )
                    ],
                    unilateral: true,
                    trackingType: .weightReps,
                    equipmentType: .cable
                )
            ]
        )

        let preview = try await context.service.previewTemplateImport(data: archiveData)
        let importedTemplateId = try await context.service.finalizeTemplateImport(
            preview,
            resolutions: [
                TemplateImportExerciseResolution(
                    previewExerciseId: try XCTUnwrap(preview.unresolvedExercises.first?.id),
                    action: .mapToExisting,
                    existingExerciseId: existingExercise.id
                )
            ]
        )
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)
        let exercises = try await context.exerciseRepo.fetchAll()

        XCTAssertEqual(importedDetail.exercises.first?.exerciseId, existingExercise.id)
        XCTAssertEqual(exercises.count, 1, "Manual mapping should reuse the chosen exercise instead of creating a new one.")
    }

    func testPreviewAITemplateDraftMatchesExistingExerciseByID() async throws {
        let context = try makeTemplateServiceContext()
        let exercise = makeExercise(name: "Dumbbell Press", primaryMuscle: "chest", defaultRestTime: 90)
        try await context.exerciseRepo.save(exercise)

        let draftData = try makeAIDraftData(
            templateName: "Upper Push",
            exercises: [
                makeAIDraftExercise(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    primaryMuscle: "chest",
                    defaultRestTime: 90,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 8,
                            targetRepMax: 10,
                            targetRIR: 2,
                            orderInExercise: 1
                        )
                    ],
                    supersetGroupKey: "A",
                    equipmentType: .dumbbell
                )
            ]
        )

        let preview = try await context.service.previewTemplateImport(data: draftData)
        XCTAssertEqual(preview.source, .aiTemplateDraft)
        XCTAssertTrue(preview.unresolvedExercises.isEmpty)
        XCTAssertEqual(preview.resolvedExercises.first?.matchedExercise?.method, .exerciseId)

        let importedTemplateId = try await context.service.finalizeTemplateImport(preview, resolutions: [])
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)

        XCTAssertEqual(importedDetail.exercises.first?.exerciseId, exercise.id)
        XCTAssertEqual(importedDetail.exercises.first?.sets.first?.targetRepMin, 8)
    }

    func testPreviewAndFinalizeCanCreateMissingExerciseFromAIDraftMetadata() async throws {
        let context = try makeTemplateServiceContext()
        let draftExerciseId = UUID()

        let draftData = try makeAIDraftData(
            templateName: "Lower Unilateral",
            exercises: [
                makeAIDraftExercise(
                    exerciseId: draftExerciseId,
                    exerciseName: "Dumbbell Lunge",
                    primaryMuscle: "legs",
                    defaultRestTime: 90,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 10,
                            targetRepMax: 12,
                            targetRIR: 2,
                            orderInExercise: 1
                        )
                    ],
                    unilateral: true,
                    unilateralRepTargetMode: .totalAcrossSides,
                    equipmentType: .dumbbell
                )
            ]
        )

        let preview = try await context.service.previewTemplateImport(data: draftData)
        XCTAssertEqual(preview.source, .aiTemplateDraft)
        XCTAssertEqual(preview.unresolvedExercises.count, 1)
        XCTAssertEqual(preview.unresolvedExercises.first?.exercise.unilateralRepTargetMode, .totalAcrossSides)

        let importedTemplateId = try await context.service.finalizeTemplateImport(
            preview,
            resolutions: [
                TemplateImportExerciseResolution(
                    previewExerciseId: try XCTUnwrap(preview.unresolvedExercises.first?.id),
                    action: .createNew
                )
            ]
        )
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)
        let createdExercise = try await context.exerciseRepo.fetch(byId: draftExerciseId)

        XCTAssertEqual(importedDetail.exercises.first?.exerciseId, draftExerciseId)
        XCTAssertEqual(createdExercise?.name, "Dumbbell Lunge")
        XCTAssertEqual(createdExercise?.unilateral, true)
        XCTAssertEqual(createdExercise?.unilateralRepTargetMode, .totalAcrossSides)
        XCTAssertEqual(createdExercise?.equipmentType, .dumbbell)
    }

    func testImportAddsImportedSuffixForTemplateNameCollisions() async throws {
        let context = try makeTemplateServiceContext()
        let exercise = makeExercise(name: "Pull-Up", primaryMuscle: "back", defaultRestTime: 90)
        try await context.exerciseRepo.save(exercise)

        _ = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Pull Day",
                notes: nil,
                exercises: [
                    TemplateSaveExercise(
                        exerciseId: exercise.id,
                        orderInTemplate: 1,
                        supersetGroupId: nil,
                        restTimeSeconds: 90,
                        notes: nil,
                        sets: [
                            TemplateSaveSet(
                                setType: .working,
                                targetRepMin: 6,
                                targetRepMax: 8,
                                targetRIR: 2,
                                orderInExercise: 1
                            )
                        ]
                    )
                ]
            )
        )

        let archiveData = try makeArchiveData(
            templateName: "Pull Day",
            exercises: [
                makeArchiveExercise(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    primaryMuscle: "back",
                    defaultRestTime: 90,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 6,
                            targetRepMax: 8,
                            targetRIR: 2,
                            orderInExercise: 1
                        )
                    ]
                )
            ]
        )

        let firstImportedId = try await context.service.importTemplate(data: archiveData)
        let secondImportedId = try await context.service.importTemplate(data: archiveData)

        let firstImportedValue = try await context.service.fetchTemplateDetail(firstImportedId)
        let secondImportedValue = try await context.service.fetchTemplateDetail(secondImportedId)
        let firstImported = try XCTUnwrap(firstImportedValue)
        let secondImported = try XCTUnwrap(secondImportedValue)

        XCTAssertEqual(firstImported.template.name, "Pull Day (Imported)")
        XCTAssertEqual(secondImported.template.name, "Pull Day (Imported 2)")
    }

    func testCreateTemplateFromWorkoutPrefersPersistedTargetOverrideBounds() async throws {
        let context = try makeTemplateServiceContext()
        let exercise = makeExercise(name: "Bench Press", primaryMuscle: "chest", defaultRestTime: 120)
        let workoutDate = makeDate(2026, 3, 22, 7, 0)
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
            completed: false
        )
        set.targetRepMin = 8
        set.targetRepMax = 12
        set.overrideTargetRepMin = 6
        set.overrideTargetRepMax = 8
        set.targetRIR = 2

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)

        let templateId = try await context.service.createTemplateFromWorkout(workout.id, name: "Bench Override")
        let detail = try await context.service.fetchTemplateDetail(templateId)
        let unwrappedDetail = try XCTUnwrap(detail)
        let savedSet = try XCTUnwrap(unwrappedDetail.exercises.first?.sets.first)

        XCTAssertEqual(savedSet.targetRepMin, 6)
        XCTAssertEqual(savedSet.targetRepMax, 8)
        XCTAssertEqual(savedSet.targetRIR, 2)
    }

    private func makeTemplateServiceContext() throws -> TemplateServiceTestContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self,
            ExerciseStats.self,
            Workout.self,
            WorkoutSet.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateSet.self,
            configurations: configuration
        )

        let exerciseRepo = ExerciseRepository(modelContainer: container)
        let workoutRepo = WorkoutRepository(modelContainer: container)
        let setRepo = SetRepository(modelContainer: container)
        let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
        let templateRepo = TemplateRepository(modelContainer: container)
        let service = TemplateService(
            templateRepository: templateRepo,
            workoutRepository: workoutRepo,
            setRepository: setRepo,
            exerciseRepository: exerciseRepo,
            exerciseStatsRepository: exerciseStatsRepo
        )

        return TemplateServiceTestContext(
            service: service,
            exerciseRepo: exerciseRepo,
            exerciseStatsRepo: exerciseStatsRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo
        )
    }

    private func makeExercise(
        name: String,
        primaryMuscle: String,
        defaultRestTime: Int,
        unilateral: Bool = false,
        unilateralRepTargetMode: UnilateralRepTargetMode? = nil
    ) -> Exercise {
        Exercise(
            name: name,
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: primaryMuscle,
            unilateral: unilateral,
            unilateralRepTargetMode: unilateralRepTargetMode,
            defaultRestTime: defaultRestTime
        )
    }

    private func makeArchiveData(
        templateName: String,
        exercises: [TemplateArchiveExercise]
    ) throws -> Data {
        try JSONEncoder().encode(
            TemplateArchive(
                version: TemplateArchive.currentVersion,
                template: TemplateArchiveTemplate(
                    id: UUID(),
                    name: templateName,
                    notes: nil
                ),
                exercises: exercises
            )
        )
    }

    private func makeArchiveExercise(
        exerciseId: UUID,
        exerciseName: String,
        primaryMuscle: String,
        defaultRestTime: Int,
        orderInTemplate: Int,
        sets: [TemplateArchiveSet],
        unilateral: Bool = false,
        unilateralRepTargetMode: UnilateralRepTargetMode? = nil,
        trackingType: TrackingType = .weightReps,
        equipmentType: EquipmentType = .barbell
    ) -> TemplateArchiveExercise {
        TemplateArchiveExercise(
            exercise: TemplateArchiveExerciseMetadata(
                id: exerciseId,
                name: exerciseName,
                equipmentType: equipmentType,
                trackingType: trackingType,
                primaryMuscle: primaryMuscle,
                secondaryMuscles: [],
                movementPattern: nil,
                unilateral: unilateral,
                unilateralRepTargetMode: unilateralRepTargetMode,
                bilateralLoadFactor: nil,
                bodyweightFactor: 0,
                weightIncrement: 2.5,
                defaultRestTime: defaultRestTime,
                fatigueRate: nil,
                recoveryConstant: nil
            ),
            orderInTemplate: orderInTemplate,
            supersetGroupId: nil,
            restTimeSeconds: defaultRestTime,
            notes: nil,
            sets: sets
        )
    }

    private func makeAIDraftData(
        templateName: String,
        exercises: [AITemplateDraftExercise]
    ) throws -> Data {
        try JSONEncoder().encode(
            AITemplateDraft(
                version: AITemplateDraft.currentVersion,
                templateName: templateName,
                notes: nil,
                exercises: exercises
            )
        )
    }

    private func makeAIDraftExercise(
        exerciseId: UUID,
        exerciseName: String,
        primaryMuscle: String,
        defaultRestTime: Int,
        orderInTemplate: Int,
        sets: [TemplateArchiveSet],
        supersetGroupKey: String? = nil,
        unilateral: Bool = false,
        unilateralRepTargetMode: UnilateralRepTargetMode? = nil,
        trackingType: TrackingType = .weightReps,
        equipmentType: EquipmentType = .barbell
    ) -> AITemplateDraftExercise {
        AITemplateDraftExercise(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            equipmentType: equipmentType,
            trackingType: trackingType,
            primaryMuscle: primaryMuscle,
            secondaryMuscles: [],
            movementPattern: nil,
            unilateral: unilateral,
            unilateralRepTargetMode: unilateralRepTargetMode,
            bilateralLoadFactor: nil,
            bodyweightFactor: 0,
            weightIncrement: 2.5,
            defaultRestTime: defaultRestTime,
            fatigueRate: nil,
            recoveryConstant: nil,
            orderInTemplate: orderInTemplate,
            supersetGroupKey: supersetGroupKey,
            restTimeSeconds: defaultRestTime,
            notes: nil,
            sets: sets
        )
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
final class WorkoutHistoryBackupServiceTests: XCTestCase {
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

        let restoreResult = try await context.service.restoreBackup(data: backupData)

        let restoredWorkouts = try await context.workoutRepo.fetchAllWorkouts(limit: nil, offset: nil)
        let restoredSets = try await context.setRepo.fetchSets(from: .distantPast, to: .distantFuture)
        let allExercises = try await context.exerciseRepo.fetchAll()
        let bodyweightEntries = try await context.bodyweightRepo.fetchAll(for: profile.id)
        let stats = try await context.exerciseStatsRepo.fetch(for: archivedExerciseId)
        let records = try await context.performanceRecordRepo.fetchAll(for: archivedExerciseId)

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
            fatigueObservations: nil,
            fatigueLearningAudits: nil,
            healthProfileLearning: nil
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

    private func makeBackupServiceContext() throws -> WorkoutHistoryBackupServiceTestContext {
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
        let service = WorkoutHistoryBackupService(
            workoutRepo: workoutRepo,
            exerciseRepo: exerciseRepo,
            setRepo: setRepo,
            fatigueObservationRepo: fatigueObservationRepo,
            fatigueLearningAuditRepo: fatigueLearningAuditRepo,
            statsService: statsService,
            prService: prService,
            modelContainer: container
        )

        return WorkoutHistoryBackupServiceTestContext(
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
final class WorkoutHistoryBackupViewModelTests: XCTestCase {
    func testExportViewModelCreatesShareItemAfterSuccessfulExport() async throws {
        let service = WorkoutHistoryBackupServiceStub()
        let viewModel = ExportViewModel(workoutHistoryBackupService: service)

        viewModel.generateExport()

        try await waitUntilOnMainActor {
            viewModel.shareItem != nil && viewModel.isExporting == false
        }

        let shareURL = try XCTUnwrap(viewModel.shareItem?.url)
        XCTAssertEqual(shareURL.pathExtension, "repsterbackup")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRestoreBackupViewModelPreviewsBeforeConfirmation() throws {
        let service = WorkoutHistoryBackupServiceStub()
        let viewModel = RestoreBackupViewModel(workoutHistoryBackupService: service)
        let fileURL = try makeBackupFileURL()

        viewModel.handleFileSelected(.success(fileURL))

        XCTAssertEqual(viewModel.state, .previewing)
        XCTAssertEqual(viewModel.preview?.workoutCount, 2)
        viewModel.confirmRestore()
        XCTAssertTrue(viewModel.showReplaceConfirmation)
    }

    func testRestoreBackupViewModelCompletesRestoreAfterConfirmation() async throws {
        let service = WorkoutHistoryBackupServiceStub()
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
        let service = WorkoutHistoryBackupServiceStub()
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

private struct TemplateServiceTestContext {
    let service: TemplateService
    let exerciseRepo: ExerciseRepository
    let exerciseStatsRepo: ExerciseStatsRepository
    let workoutRepo: WorkoutRepository
    let setRepo: SetRepository
}

private struct WorkoutHistoryBackupServiceTestContext {
    let service: WorkoutHistoryBackupService
    let exerciseRepo: ExerciseRepository
    let workoutRepo: WorkoutRepository
    let setRepo: SetRepository
    let exerciseStatsRepo: ExerciseStatsRepository
    let performanceRecordRepo: PerformanceRecordRepository
    let bodyweightRepo: BodyweightEntryRepository
    let healthProfileRepo: HealthProfileRepository
}

private struct TestContext {
    let viewModel: ActiveWorkoutViewModel
    let exercise: Exercise
    let pendingSet: WorkoutSet
    let secondExercise: Exercise?
}

private final class WorkoutHistoryBackupServiceStub: @unchecked Sendable, WorkoutHistoryBackupServiceProtocol {
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

private final class LoadPrescriptionServiceSpy: @unchecked Sendable, LoadPrescriptionServiceProtocol {
    struct RecordedEvaluation: Sendable {
        let exerciseId: UUID
        let targetReps: [Int]
    }

    private let lock = NSLock()
    private var recordedEvaluationsStorage: [RecordedEvaluation] = []
    private var delayByFirstTargetReps: [Int: Duration] = [:]
    var exerciseNames: [UUID: String] = [:]
    private var delayByExerciseName: [String: Duration] = [:]

    var evaluationCount: Int {
        lock.withLock { recordedEvaluationsStorage.count }
    }

    var lastRecordedTargetReps: [Int] {
        lock.withLock { recordedEvaluationsStorage.last?.targetReps ?? [] }
    }

    func setDelay(_ delay: Duration, forFirstTargetReps reps: Int) {
        lock.withLock {
            delayByFirstTargetReps[reps] = delay
        }
    }

    func setDelay(_ delay: Duration, forExerciseName name: String) {
        lock.withLock {
            delayByExerciseName[name] = delay
        }
    }

    func estimateBaseE1RM(
        exerciseId: UUID,
        completedSessionSets: [SessionSetContext]
    ) async throws -> BaseE1RMEstimate {
        let _ = completedSessionSets
        let _ = exerciseId
        return BaseE1RMEstimate(value: 100, source: .recentPerformance)
    }

    func evaluateSuggestions(
        exerciseId: UUID,
        pendingSets: [SuggestionPendingSetInput],
        completedSessionSets: [SessionSetContext]
    ) async throws -> SuggestionEvaluation {
        let firstTargetReps = pendingSets.first?.targetReps ?? 0
        let targetReps = pendingSets.map(\.targetReps)

        let delay: Duration? = lock.withLock {
            recordedEvaluationsStorage.append(
                RecordedEvaluation(exerciseId: exerciseId, targetReps: targetReps)
            )

            if let exerciseName = exerciseNames[exerciseId], let namedDelay = delayByExerciseName[exerciseName] {
                return namedDelay
            }

            return delayByFirstTargetReps[firstTargetReps]
        }

        if let delay {
            try? await Task.sleep(for: delay)
        }

        let input = SuggestionEngineInput(
            baseE1RM: 100,
            baseSource: .recentPerformance,
            completedSessionSets: completedSessionSets,
            pendingSets: pendingSets,
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        return SuggestionEvaluation(
            input: input,
            decisions: SuggestionEngine.evaluate(input),
            unavailableReason: pendingSets.isEmpty ? .noPendingSets : nil
        )
    }

    func prescribe(_ request: PrescriptionRequest) async throws -> PrescriptionResult? {
        let result = try await prescribeBatch(
            exerciseId: request.exerciseId,
            sets: [(request.targetReps, request.targetRIR, request.setIndex, nil)],
            completedSessionSets: request.completedSessionSets
        )
        return result.first ?? nil
    }

    func prescribeBatch(
        exerciseId: UUID,
        sets: [(targetReps: Int, targetRIR: Double, setIndex: Int, repRange: ClosedRange<Int>?)],
        completedSessionSets: [SessionSetContext]
    ) async throws -> [PrescriptionResult?] {
        let pendingSets = sets.enumerated().map { index, item in
            SuggestionPendingSetInput(
                setId: UUID(),
                setIndex: item.setIndex,
                setNumber: index + 1,
                target: SuggestionTarget(
                    reps: item.targetReps,
                    rir: item.targetRIR,
                    repRange: item.repRange,
                    repsSource: .explicitSet,
                    rirSource: .explicitSet
                ),
                setType: .working
            )
        }

        let evaluation = try await evaluateSuggestions(
            exerciseId: exerciseId,
            pendingSets: pendingSets,
            completedSessionSets: completedSessionSets
        )

        return evaluation.decisions.map { decision in
            PrescriptionResult(
                prescribedWeight: decision.prescribedWeight,
                rawWeight: decision.rawWeight,
                weightIncrement: decision.weightIncrement,
                baseE1RM: decision.baseE1RM,
                effectiveE1RM: decision.effectiveE1RM,
                intensityFactor: decision.intensityFactor,
                fatigueDiscount: decision.fatigueDiscount,
                freshnessApplied: decision.freshnessApplied,
                e1RMSource: decision.e1RMSource,
                bestReps: decision.bestReps
            )
        }
    }
}

private final class SettingsServiceStub: @unchecked Sendable, SettingsServiceProtocol {
    private let profile: HealthProfile

    init(profile: HealthProfile) {
        self.profile = profile
    }

    func fetchSettings() async throws -> HealthProfile { profile }
    func updateUnitPreference(_ preference: UnitPreference) async throws { let _ = preference }
    func updateE1RMFormula(_ formula: E1RMFormula) async throws { let _ = formula }
    func updateIncludeWarmupsInVolume(_ include: Bool) async throws { let _ = include }
    func updateIncludeWarmupsInPRs(_ include: Bool) async throws { let _ = include }
    func updateDefaultRestTime(_ seconds: Int?) async throws { let _ = seconds }
    func updateDefaultWarmupRestTime(_ seconds: Int?) async throws { let _ = seconds }
    func updateRestTimerAlert(_ value: String) async throws { let _ = value }
    func updatePrescriptionEnabled(_ enabled: Bool) async throws { let _ = enabled }
    func updatePrescriptionRecencyWeeks(_ weeks: Int) async throws { let _ = weeks }
    func updatePrescriptionDefaultIncrement(_ increment: Double) async throws { let _ = increment }
    func updatePrescriptionDefaultTargetReps(_ reps: Int) async throws { let _ = reps }
    func updatePrescriptionDefaultTargetRIR(_ rir: Int) async throws { let _ = rir }
    func updatePrescriptionFreshnessBonus(enabled: Bool, percent: Double) async throws {
        let _ = enabled
        let _ = percent
    }
    func updatePrescriptionFatigueModelingEnabled(_ enabled: Bool) async throws { let _ = enabled }
    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws { let _ = seconds }
    func updatePrescriptionAdminModeEnabled(_ enabled: Bool) async throws { let _ = enabled }
    func resetAllAppData() async throws {}
    func rebuildPRs() async throws {}
    func rebuildStats() async throws {}
    func rebuildAll() async throws {}
}

private final class HealthProfileRepositoryStub: @unchecked Sendable, HealthProfileRepositoryProtocol {
    private let profile: HealthProfile

    init(profile: HealthProfile) {
        self.profile = profile
    }

    func save(_ profile: HealthProfile) async throws { let _ = profile }
    func fetch() async throws -> HealthProfile? { profile }
    func fetchOrCreate() async throws -> HealthProfile { profile }
}

private final class SetServiceStub: @unchecked Sendable, SetServiceProtocol {
    var editedSetIds: [UUID] = []
    var uncompletedSetIds: [UUID] = []
    var deletedSetIds: [UUID] = []
    var targetOverrideUpdates: [(setId: UUID, min: Int?, max: Int?)] = []
    var workoutSets: [UUID: [WorkoutSet]] = [:]
    var exerciseSets: [UUID: [WorkoutSet]] = [:]
    var fetchSetsForExerciseCallCount = 0

    func save(_ set: WorkoutSet) async throws -> SetSaveResult {
        SetSaveResult(
            setId: set.id,
            effectiveWeight: set.weight ?? 0,
            prResult: .empty(for: set.id)
        )
    }

    func edit(
        _ set: WorkoutSet,
        previousContribution: SetContributionSnapshot? = nil
    ) async throws -> SetSaveResult {
        let _ = previousContribution
        editedSetIds.append(set.id)
        return try await save(set)
    }

    func uncomplete(
        _ set: WorkoutSet,
        previousContribution: SetContributionSnapshot? = nil
    ) async throws -> SetSaveResult {
        let _ = previousContribution
        uncompletedSetIds.append(set.id)
        set.completed = false
        set.completedAt = nil
        return try await save(set)
    }

    func delete(_ set: WorkoutSet) async throws {
        deletedSetIds.append(set.id)
    }

    func updateInProgressTargetRepOverride(
        setId: UUID,
        min: Int?,
        max: Int?
    ) async throws {
        targetOverrideUpdates.append((setId, min, max))

        for sets in workoutSets.values {
            if let set = sets.first(where: { $0.id == setId }) {
                set.overrideTargetRepMin = min
                set.overrideTargetRepMax = max
            }
        }

        for sets in exerciseSets.values {
            if let set = sets.first(where: { $0.id == setId }) {
                set.overrideTargetRepMin = min
                set.overrideTargetRepMax = max
            }
        }
    }

    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet] {
        workoutSets[workoutId] ?? []
    }

    func fetchExerciseIds(for workoutId: UUID) async throws -> Set<UUID> {
        Set((workoutSets[workoutId] ?? []).map(\.exerciseId))
    }

    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet] {
        fetchSetsForExerciseCallCount += 1
        let sets = exerciseSets[exerciseId] ?? workoutSets.values.flatMap { workoutSets in
            workoutSets.filter { $0.exerciseId == exerciseId }
        }
        if let limit {
            return Array(sets.prefix(limit))
        }
        return sets
    }
}

private final class WorkoutServiceStub: @unchecked Sendable, WorkoutServiceProtocol {
    var activeWorkout: Workout?
    var lastFinishedWorkoutId: UUID?
    var lastFinishTitle: String?
    var lastFinishNotes: String?
    var lastFinishPerceivedEffort: Double?
    var lastFinishDurationSecondsOverride: Int?
    var finishCallCount = 0

    func startWorkout(options: WorkoutStartOptions) async throws -> Workout {
        Workout(
            startTime: Date(),
            excludeFromProgressionHistory: options.excludeFromProgressionHistory
        )
    }
    func finishWorkout(
        _ workoutId: UUID,
        title: String?,
        notes: String?,
        perceivedEffort: Double?,
        durationSecondsOverride: Int?
    ) async throws {
        finishCallCount += 1
        lastFinishedWorkoutId = workoutId
        lastFinishTitle = title
        lastFinishNotes = notes
        lastFinishPerceivedEffort = perceivedEffort
        lastFinishDurationSecondsOverride = durationSecondsOverride
    }
    func getActiveWorkout() async throws -> Workout? { activeWorkout }
    func fetchWorkout(_ workoutId: UUID) async throws -> Workout? {
        let _ = workoutId
        return nil
    }
    func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout] {
        let _ = dateRange
        return []
    }
    func fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout] {
        let _ = limit
        let _ = offset
        return []
    }
    func updateWorkoutMetadata(_ workoutId: UUID, notes: String?, perceivedEffort: Double?) async throws {
        let _ = workoutId
        let _ = notes
        let _ = perceivedEffort
    }
    func updateProgressionHistoryExclusions(
        _ workoutId: UUID,
        excludeWorkout: Bool,
        excludedExerciseIds: Set<UUID>
    ) async throws {
        let _ = workoutId
        let _ = excludeWorkout
        let _ = excludedExerciseIds
    }
    func deleteWorkout(_ workoutId: UUID) async throws {
        let _ = workoutId
    }
}

private final class AnalyticsServiceSpy: AnalyticsServiceProtocol {
    var isCollectionEnabled = true
    private(set) var screens: [(screen: AnalyticsScreen, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue])] = []
    private(set) var events: [(event: AnalyticsEvent, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue])] = []

    func configure() {}

    func setCollectionEnabled(_ enabled: Bool) {
        isCollectionEnabled = enabled
    }

    func screen(_ screen: AnalyticsScreen, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) {
        screens.append((screen, properties))
    }

    func track(_ event: AnalyticsEvent, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) {
        guard isCollectionEnabled else { return }
        events.append((event, properties))
    }
}

private final class ExerciseServiceStub: @unchecked Sendable, ExerciseServiceProtocol {
    var createdExercises: [Exercise] = []
    var updatedExercises: [Exercise] = []
    var fetchedExercises: [UUID: Exercise] = [:]
    var hasSets = false
    var hasLoggedSetData = false

    func createExercise(_ exercise: Exercise) async throws {
        createdExercises.append(exercise)
    }
    func updateExercise(_ exercise: Exercise, originalTrackingType: TrackingType) async throws {
        updatedExercises.append(exercise)
        let _ = originalTrackingType
    }
    func fetchExercise(_ exerciseId: UUID) async throws -> Exercise? {
        fetchedExercises[exerciseId]
    }
    func fetchAllExercises() async throws -> [Exercise] { [] }
    func searchExercises(name query: String) async throws -> [Exercise] {
        let _ = query
        return []
    }
    func deleteExercise(_ exerciseId: UUID) async throws {
        let _ = exerciseId
    }
    func exerciseHasSets(_ exerciseId: UUID) async throws -> Bool {
        let _ = exerciseId
        return hasSets
    }

    func exerciseHasLoggedSetData(_ exerciseId: UUID) async throws -> Bool {
        let _ = exerciseId
        return hasLoggedSetData
    }
}

private final class StatsServiceStub: @unchecked Sendable, StatsServiceProtocol {
    func updateStats(for exerciseId: UUID, event: StatsUpdateEvent) async throws {
        let _ = exerciseId
        let _ = event
    }
    func rebuildAll() async throws {}
    func rebuild(for exerciseId: UUID) async throws { let _ = exerciseId }
    func fetchStats(for exerciseId: UUID) async throws -> ExerciseStats? {
        let _ = exerciseId
        return nil
    }
    func fetchAllStats() async throws -> [UUID: ExerciseStats] { [:] }
    func fetchRecentPRs(since: Date, limit: Int) async throws -> [PerformanceRecord] {
        let _ = since
        let _ = limit
        return []
    }
}

private final class PRServiceStub: @unchecked Sendable, PRServiceProtocol {
    func evaluate(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        effectiveWeight: Double,
        workoutId: UUID,
        setType: SetType,
        hasData: Bool,
        excludeFromPRs: Bool,
        date: Date
    ) async throws -> PREvaluationResult {
        let _ = exerciseId
        let _ = reps
        let _ = effectiveWeight
        let _ = workoutId
        let _ = setType
        let _ = hasData
        let _ = excludeFromPRs
        let _ = date
        return .empty(for: setId)
    }

    func evaluateAfterEdit(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        effectiveWeight: Double,
        workoutId: UUID,
        setType: SetType,
        hasData: Bool,
        excludeFromPRs: Bool,
        previousCachedPRStatus: CachedPRStatus?,
        date: Date
    ) async throws -> PREvaluationResult {
        let _ = exerciseId
        let _ = reps
        let _ = effectiveWeight
        let _ = workoutId
        let _ = setType
        let _ = hasData
        let _ = excludeFromPRs
        let _ = previousCachedPRStatus
        let _ = date
        return .empty(for: setId)
    }

    func handleDeletion(
        setId: UUID,
        exerciseId: UUID,
        reps: Int,
        cachedPRStatus: CachedPRStatus?
    ) async throws -> PREvaluationResult {
        let _ = exerciseId
        let _ = reps
        let _ = cachedPRStatus
        return .empty(for: setId)
    }

    func fetchPRTable(for exerciseId: UUID) async throws -> [PRTableEntry] {
        let _ = exerciseId
        return []
    }

    func rebuildAll() async throws {}
    func rebuild(for exerciseId: UUID) async throws { let _ = exerciseId }
}

final class ImportSupportTests: XCTestCase {
    func testPreviewCSVAcceptsFitNotesHeaders() throws {
        let context = try makeImportContext()

        let preview = try context.service.previewImport(
            data: Data(validFitNotesCSV.utf8),
            source: .fitNotes,
            unitSystem: nil
        )

        XCTAssertEqual(preview.headers.first, "Date")
        XCTAssertEqual(preview.sampleRows.count, 1)
        XCTAssertEqual(preview.estimatedTotalRows, 1)
    }

    func testPreviewCSVRejectsUnsupportedHeaders() throws {
        let context = try makeImportContext()

        XCTAssertThrowsError(try context.service.previewImport(
            data: Data(unsupportedCSV.utf8),
            source: .fitNotes,
            unitSystem: nil
        )) { error in
            guard let importError = error as? ImportError else {
                return XCTFail("Expected ImportError, got \(type(of: error))")
            }

            guard case .invalidHeader(let source, _, _) = importError else {
                return XCTFail("Expected invalidHeader, got \(importError)")
            }

            XCTAssertEqual(source, .fitNotes)
            XCTAssertEqual(
                importError.errorDescription,
                "This CSV doesn't look like a FitNotes export. Repster currently supports FitNotes and Strong CSV imports."
            )
        }
    }

    func testPreviewImportAcceptsStrongHeaders() throws {
        let context = try makeImportContext()

        let preview = try context.service.previewImport(
            data: strongFixtureData(),
            source: .strong,
            unitSystem: .metric
        )

        XCTAssertEqual(preview.headers, [
            "Date", "Workout Name", "Duration", "Exercise Name", "Set Order",
            "Weight", "Reps", "Distance", "Seconds", "RPE"
        ])
        XCTAssertEqual(preview.sampleRows.count, 5)
        XCTAssertEqual(preview.estimatedTotalRows, 7)
    }

    func testPreviewImportRequiresUnitSelectionForStrong() throws {
        let context = try makeImportContext()

        XCTAssertThrowsError(try context.service.previewImport(
            data: strongFixtureData(),
            source: .strong,
            unitSystem: nil
        )) { error in
            guard let importError = error as? ImportError else {
                return XCTFail("Expected ImportError, got \(type(of: error))")
            }

            guard case .missingUnitSystem(let source) = importError else {
                return XCTFail("Expected missingUnitSystem, got \(importError)")
            }

            XCTAssertEqual(source, .strong)
        }
    }

    func testStrongImportPreservesSeparateWorkoutsPerTimestamp() async throws {
        let context = try makeImportContext()

        let result = try await consumeImport(
            context.service.importData(
                data: strongFixtureData(),
                source: .strong,
                unitSystem: .metric
            )
        )

        XCTAssertEqual(result.setsImported, 7)
        XCTAssertEqual(result.workoutsCreated, 2)
        XCTAssertEqual(result.rowsSkipped, 0)
        XCTAssertEqual(result.warnings.count, 1)

        let verificationContext = ModelContext(context.modelContainer)
        let workouts = try verificationContext.fetch(
            FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )

        XCTAssertEqual(workouts.count, 2)
        XCTAssertEqual(workouts.map(\.title), ["Morning Workout", "Morning Workout"])
        XCTAssertEqual(workouts.map(\.duration), [4380, 4380])

        let firstStart = try XCTUnwrap(workouts[0].startTime)
        let secondStart = try XCTUnwrap(workouts[1].startTime)
        XCTAssertNotEqual(firstStart, secondStart)
        XCTAssertEqual(Calendar.current.component(.hour, from: firstStart), 9)
        XCTAssertEqual(Calendar.current.component(.hour, from: secondStart), 17)
    }

    func testStrongImportMapsSetTagsAndWarnings() async throws {
        let context = try makeImportContext()

        let result = try await consumeImport(
            context.service.importData(
                data: strongFixtureData(),
                source: .strong,
                unitSystem: .metric
            )
        )

        XCTAssertEqual(result.rowsSkipped, 0)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.rowNumber, 8)
        XCTAssertTrue(result.warnings.first?.reason.contains("Unknown set marker") == true)

        let verificationContext = ModelContext(context.modelContainer)
        let exercises = try verificationContext.fetch(FetchDescriptor<Exercise>())
        let sets = try verificationContext.fetch(
            FetchDescriptor<WorkoutSet>(sortBy: [SortDescriptor(\.orderInWorkout, order: .forward)])
        )

        XCTAssertEqual(sets.count, 7)

        let exerciseById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        let cyclingSet = try XCTUnwrap(sets.first(where: { exerciseById[$0.exerciseId]?.name == "Cycling (Indoor)" }))
        XCTAssertEqual(cyclingSet.setType, .warmup)
        XCTAssertEqual(cyclingSet.durationSeconds, 600)
        XCTAssertEqual(cyclingSet.distanceMeters ?? 0, 5000, accuracy: 0.001)
        XCTAssertEqual(exerciseById[cyclingSet.exerciseId]?.trackingType, .durationDistance)

        let frontSquatWarmup = try XCTUnwrap(sets.first(where: {
            exerciseById[$0.exerciseId]?.name == "Front Squat (Barbell)" && $0.setType == .warmup
        }))
        XCTAssertEqual(frontSquatWarmup.weight ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(frontSquatWarmup.reps, 10)

        let frontSquatWorking = try XCTUnwrap(sets.first(where: {
            exerciseById[$0.exerciseId]?.name == "Front Squat (Barbell)" && $0.setType == .working
        }))
        XCTAssertEqual(frontSquatWorking.rpe ?? 0, 7.5, accuracy: 0.001)
        XCTAssertEqual(exerciseById[frontSquatWorking.exerciseId]?.trackingType, .weightReps)

        let dropSet = try XCTUnwrap(sets.first(where: {
            exerciseById[$0.exerciseId]?.name == "Bench Press (Dumbbell)"
        }))
        XCTAssertEqual(dropSet.setType, .dropset)
        XCTAssertEqual(dropSet.weight ?? 0, 76, accuracy: 0.001)

        let failureSet = try XCTUnwrap(sets.first(where: {
            exerciseById[$0.exerciseId]?.name == "Snatch (Barbell)"
        }))
        XCTAssertEqual(failureSet.setType, .failure)
        XCTAssertEqual(failureSet.weight ?? 0, 72.5, accuracy: 0.001)
        XCTAssertEqual(failureSet.reps, 1)

        let unknownMarkerSet = try XCTUnwrap(sets.first(where: {
            exerciseById[$0.exerciseId]?.name == "Triceps Pushdown (Cable - Straight Bar)"
        }))
        XCTAssertEqual(unknownMarkerSet.setType, .working)
    }

    func testStrongImportConvertsImperialUnits() async throws {
        let context = try makeImportContext()

        _ = try await consumeImport(
            context.service.importData(
                data: strongFixtureData(),
                source: .strong,
                unitSystem: .imperial
            )
        )

        let verificationContext = ModelContext(context.modelContainer)
        let exercises = try verificationContext.fetch(FetchDescriptor<Exercise>())
        let sets = try verificationContext.fetch(FetchDescriptor<WorkoutSet>())
        let exerciseById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        let benchSet = try XCTUnwrap(sets.first(where: {
            exerciseById[$0.exerciseId]?.name == "Bench Press (Dumbbell)"
        }))
        XCTAssertEqual(benchSet.weight ?? 0, UnitConversion.lbsToKg(76), accuracy: 0.0001)

        let rowingSet = try XCTUnwrap(sets.first(where: {
            exerciseById[$0.exerciseId]?.name == "Rowing (Machine)"
        }))
        XCTAssertEqual(rowingSet.distanceMeters ?? 0, 2 * 1609.34, accuracy: 0.001)
    }

    func testFitNotesImportUsesPreferredKgColumnAndFallsBackToLbs() async throws {
        let context = try makeImportContext()
        let csv = """
        Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind
        2026-03-20,Squat,Legs,100,,5,,,,,wr
        2026-03-20,Bench Press,Chest,,225,5,,,,,wr
        2026-03-20,Deadlift,Back,140,315,3,,,,,wr
        """

        let result = try await consumeImport(
            context.service.importData(
                data: Data(csv.utf8),
                source: .fitNotes,
                unitSystem: .metric
            )
        )

        XCTAssertEqual(result.setsImported, 3)
        XCTAssertEqual(result.rowsSkipped, 0)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.rowNumber, 3)
        XCTAssertTrue(result.warnings.first?.reason.contains("Weight (lbs)") == true)

        let setsByExercise = try fetchImportedSetsByExerciseName(context.modelContainer)
        XCTAssertEqual(setsByExercise["Squat"]?.weight ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(setsByExercise["Bench Press"]?.weight ?? 0, UnitConversion.lbsToKg(225), accuracy: 0.0001)
        XCTAssertEqual(setsByExercise["Deadlift"]?.weight ?? 0, 140, accuracy: 0.0001)
    }

    func testFitNotesImportUsesPreferredLbsColumnAndFallsBackToKg() async throws {
        let context = try makeImportContext()
        let csv = """
        Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind
        2026-03-20,Squat,Legs,100,,5,,,,,wr
        2026-03-20,Bench Press,Chest,,225,5,,,,,wr
        2026-03-20,Deadlift,Back,140,315,3,,,,,wr
        """

        let result = try await consumeImport(
            context.service.importData(
                data: Data(csv.utf8),
                source: .fitNotes,
                unitSystem: .imperial
            )
        )

        XCTAssertEqual(result.setsImported, 3)
        XCTAssertEqual(result.rowsSkipped, 0)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.rowNumber, 2)
        XCTAssertTrue(result.warnings.first?.reason.contains("Weight (kg)") == true)

        let setsByExercise = try fetchImportedSetsByExerciseName(context.modelContainer)
        XCTAssertEqual(setsByExercise["Squat"]?.weight ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(setsByExercise["Bench Press"]?.weight ?? 0, UnitConversion.lbsToKg(225), accuracy: 0.0001)
        XCTAssertEqual(setsByExercise["Deadlift"]?.weight ?? 0, UnitConversion.lbsToKg(315), accuracy: 0.0001)
    }

    func testImportSupportEmailUsesFeedbackInboxAndImportSubject() throws {
        let url = try XCTUnwrap(
            SupportEmailComposer.importSupportURL(
                appVersion: "1.2.3",
                build: "45",
                systemVersion: "18.0"
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, SupportEmailComposer.address)
        XCTAssertEqual(queryItems["subject"], "CSV Import Support")
        XCTAssertTrue(queryItems["body"]?.contains("App Version: 1.2.3 (45)") == true)
        XCTAssertTrue(queryItems["body"]?.contains("iOS: 18.0") == true)
    }

    private func makeImportContext() throws -> ImportTestContext {
        let container = try ModelContainer(
            for: Workout.self, WorkoutSet.self, Exercise.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ImportTestContext(
            service: ImportService(
                exerciseRepo: ImportExerciseRepositoryStub(),
                workoutRepo: ImportWorkoutRepositoryStub(),
                bodyweightRepo: ImportBodyweightRepositoryStub(),
                healthProfileRepo: HealthProfileRepositoryStub(profile: HealthProfile()),
                prService: PRServiceStub(),
                statsService: StatsServiceStub(),
                modelContainer: container
            ),
            modelContainer: container
        )
    }

    private var validFitNotesCSV: String {
        """
        Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind
        2026-03-20,Squat,Legs,100,,5,,,,,wr
        """
    }

    private var unsupportedCSV: String {
        """
        Workout Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind
        2026-03-20,Squat,Legs,100,,5,,,,,wr
        """
    }

    private func strongFixtureData() throws -> Data {
        try Data(contentsOf: fixtureURL(named: "strong_workouts_sanitized.csv"))
    }

    private func fixtureURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    private func consumeImport(_ stream: AsyncStream<ImportProgress>) async throws -> ImportResult {
        for await progress in stream {
            switch progress {
            case .completed(let result):
                return result
            case .failed(let error):
                throw error
            default:
                continue
            }
        }

        XCTFail("Import stream finished without a terminal event")
        throw ImportError.cancelled
    }

    private func fetchImportedSetsByExerciseName(_ modelContainer: ModelContainer) throws -> [String: WorkoutSet] {
        let verificationContext = ModelContext(modelContainer)
        let exercises = try verificationContext.fetch(FetchDescriptor<Exercise>())
        let sets = try verificationContext.fetch(FetchDescriptor<WorkoutSet>())
        let exerciseById = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        return Dictionary(uniqueKeysWithValues: sets.compactMap { set in
            guard let exerciseName = exerciseById[set.exerciseId]?.name else { return nil }
            return (exerciseName, set)
        })
    }

    private struct ImportTestContext {
        let service: ImportService
        let modelContainer: ModelContainer
    }
}

private final class ImportExerciseRepositoryStub: @unchecked Sendable, ExerciseRepositoryProtocol {
    func save(_ exercise: Exercise) async throws { let _ = exercise }
    func delete(_ exercise: Exercise) async throws { let _ = exercise }
    func fetch(byId id: UUID) async throws -> Exercise? {
        let _ = id
        return nil
    }
    func fetchAll() async throws -> [Exercise] { [] }
    func fetchAllChartExercises() async throws -> [ChartExerciseData] { [] }
    func search(name: String) async throws -> [Exercise] {
        let _ = name
        return []
    }
    func hasAssociatedSets(_ exerciseId: UUID) async throws -> Bool {
        let _ = exerciseId
        return false
    }
    func hasLoggedSetData(_ exerciseId: UUID) async throws -> Bool {
        let _ = exerciseId
        return false
    }
}

private final class ImportWorkoutRepositoryStub: @unchecked Sendable, WorkoutRepositoryProtocol {
    func save(_ workout: Workout) async throws { let _ = workout }
    func delete(_ workout: Workout) async throws { let _ = workout }
    func fetch(byId id: UUID) async throws -> Workout? {
        let _ = id
        return nil
    }
    func fetch(byIds ids: Set<UUID>) async throws -> [Workout] {
        let _ = ids
        return []
    }
    func fetchInProgress() async throws -> Workout? { nil }
    func fetchWorkouts(for dateRange: ClosedRange<Date>) async throws -> [Workout] {
        let _ = dateRange
        return []
    }
    func fetchAllWorkouts(limit: Int?, offset: Int?) async throws -> [Workout] {
        let _ = limit
        let _ = offset
        return []
    }
    func fetchEarliestCompletedWorkoutDate() async throws -> Date? { nil }
}

private final class ImportBodyweightRepositoryStub: @unchecked Sendable, BodyweightEntryRepositoryProtocol {
    func save(_ entry: BodyweightEntry) async throws { let _ = entry }
    func delete(_ entry: BodyweightEntry) async throws { let _ = entry }
    func fetchAll(for healthProfileId: UUID) async throws -> [BodyweightEntry] {
        let _ = healthProfileId
        return []
    }
    func fetch(byId id: UUID) async throws -> BodyweightEntry? {
        let _ = id
        return nil
    }
    func fetchClosest(to date: Date, healthProfileId: UUID) async throws -> BodyweightEntry? {
        let _ = date
        let _ = healthProfileId
        return nil
    }
}

// MARK: - Fatigue Model v2 Tests

final class FatigueModelV2Tests: XCTestCase {

    func testFirstSetRepRangeBiasesAboveRecentPeakWhenClosestMatchEqualsBaseline() {
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 0,
            setNumber: 1,
            target: SuggestionTarget(
                reps: 9,
                rir: 0.0,
                repRange: 5...10,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )
        let input = SuggestionEngineInput(
            baseE1RM: 104,
            baseSource: .recentPerformance,
            completedSessionSets: [],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.03,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try! XCTUnwrap(SuggestionEngine.evaluate(input).first)
        let selectionReferenceE1RM = try! XCTUnwrap(decision.selectionReferenceE1RM)

        XCTAssertEqual(decision.prescribedWeight, 82.5, accuracy: 0.001)
        XCTAssertEqual(decision.bestReps, 8)
        XCTAssertEqual(decision.selectionPolicy, .firstSetProgressionAboveRecentPeak)
        XCTAssertEqual(selectionReferenceE1RM, 104, accuracy: 0.001)
    }

    func testFirstSetBiasDoesNotDoublePushWhenFreshnessAlreadyLiftsAboveBaseline() {
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 0,
            setNumber: 1,
            target: SuggestionTarget(
                reps: 9,
                rir: 0.0,
                repRange: 5...10,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )
        let input = SuggestionEngineInput(
            baseE1RM: 104,
            baseSource: .recentPerformance,
            completedSessionSets: [],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: true,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.03,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try! XCTUnwrap(SuggestionEngine.evaluate(input).first)

        XCTAssertEqual(decision.prescribedWeight, 82.5, accuracy: 0.001)
        XCTAssertEqual(decision.bestReps, 9)
        XCTAssertEqual(decision.selectionPolicy, .closestMatch)
        XCTAssertNil(decision.selectionReferenceE1RM)
    }

    func testFirstSetBiasFallsBackToClosestMatchWhenNoHigherRoundedCandidateExists() {
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 0,
            setNumber: 1,
            target: SuggestionTarget(
                reps: 6,
                rir: 0.0,
                repRange: 5...6,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )
        let input = SuggestionEngineInput(
            baseE1RM: 50,
            baseSource: .recentPerformance,
            completedSessionSets: [],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 10,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.03,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try! XCTUnwrap(SuggestionEngine.evaluate(input).first)

        XCTAssertEqual(decision.prescribedWeight, 40, accuracy: 0.001)
        XCTAssertEqual(decision.bestReps, 6)
        XCTAssertEqual(decision.selectionPolicy, .closestMatch)
        XCTAssertNil(decision.selectionReferenceE1RM)
    }

    func testFirstSetFixedRepPrescriptionsRemainClosestMatch() {
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 0,
            setNumber: 1,
            target: SuggestionTarget(
                reps: 9,
                rir: 0.0,
                repRange: nil,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )
        let input = SuggestionEngineInput(
            baseE1RM: 104,
            baseSource: .recentPerformance,
            completedSessionSets: [],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.03,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try! XCTUnwrap(SuggestionEngine.evaluate(input).first)

        XCTAssertEqual(decision.prescribedWeight, 80, accuracy: 0.001)
        XCTAssertNil(decision.bestReps)
        XCTAssertEqual(decision.selectionPolicy, .closestMatch)
        XCTAssertNil(decision.selectionReferenceE1RM)
    }

    func testHistoricalPRSourceDoesNotUseFirstSetBias() {
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 0,
            setNumber: 1,
            target: SuggestionTarget(
                reps: 9,
                rir: 0.0,
                repRange: 5...10,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )
        let input = SuggestionEngineInput(
            baseE1RM: 104,
            baseSource: .historicalPR,
            completedSessionSets: [],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.03,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try! XCTUnwrap(SuggestionEngine.evaluate(input).first)

        XCTAssertEqual(decision.prescribedWeight, 80, accuracy: 0.001)
        XCTAssertEqual(decision.bestReps, 9)
        XCTAssertEqual(decision.selectionPolicy, .closestMatch)
        XCTAssertNil(decision.selectionReferenceE1RM)
    }

    func testLaterSetsDoNotUseFirstSetBias() {
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 1,
            setNumber: 2,
            target: SuggestionTarget(
                reps: 9,
                rir: 0.0,
                repRange: 5...10,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )
        let completedSet = SessionSetContext(
            weight: 80,
            reps: 9,
            rir: 0.0,
            completedAt: Date(),
            completed: true,
            setType: .working,
            restDurationSeconds: 120
        )
        let input = SuggestionEngineInput(
            baseE1RM: 104,
            baseSource: .recentPerformance,
            completedSessionSets: [completedSet],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 2.5,
                fatigueEnabled: false,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.03,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try! XCTUnwrap(SuggestionEngine.evaluate(input).first)

        XCTAssertEqual(decision.prescribedWeight, 80, accuracy: 0.001)
        XCTAssertEqual(decision.bestReps, 9)
        XCTAssertEqual(decision.selectionPolicy, .closestMatch)
        XCTAssertNil(decision.selectionReferenceE1RM)
    }

    // MARK: - Set-type multipliers

    func testWarmupMultiplierIsZero() {
        XCTAssertEqual(SuggestionEngine.setTypeMultiplier(.warmup), 0.0)
    }

    func testAMRAPMultiplierIsHigherThanWorking() {
        XCTAssertGreaterThan(
            SuggestionEngine.setTypeMultiplier(.amrap),
            SuggestionEngine.setTypeMultiplier(.working)
        )
    }

    func testBackoffMultiplierIsLowerThanWorking() {
        XCTAssertLessThan(
            SuggestionEngine.setTypeMultiplier(.backoff),
            SuggestionEngine.setTypeMultiplier(.working)
        )
    }

    // MARK: - Per-set fatigue formula

    func testComputeSetFatigueWithWorkingSet() {
        // baseFatigueRate(0.04) * typeMultiplier(1.0) * effortScale(1.15 at RIR 2) * repScale(1.0 at 8 reps)
        let fatigue = SuggestionEngine.computeSetFatigue(
            reps: 8, rir: 2.0, setType: .working, baseFatigueRate: 0.04
        )
        XCTAssertEqual(fatigue, 0.04 * 1.0 * 1.15 * 1.0, accuracy: 0.0001)
    }

    func testComputeSetFatigueWarmupIsZero() {
        let fatigue = SuggestionEngine.computeSetFatigue(
            reps: 8, rir: 3.0, setType: .warmup, baseFatigueRate: 0.04
        )
        XCTAssertEqual(fatigue, 0.0)
    }

    func testRepScaleFloorAt0_6() {
        // 1 rep: reps/8 = 0.125, but floor is 0.6
        let fatigue = SuggestionEngine.computeSetFatigue(
            reps: 1, rir: 2.0, setType: .working, baseFatigueRate: 0.04
        )
        let expected = 0.04 * 1.0 * 1.15 * 0.6
        XCTAssertEqual(fatigue, expected, accuracy: 0.0001)
    }

    func testEffortScaleAtDifferentRIRs() {
        // RIR 3+: effortScale = 1.0
        let fatigueRIR3 = SuggestionEngine.computeSetFatigue(
            reps: 8, rir: 3.0, setType: .working, baseFatigueRate: 0.04
        )
        let fatigueRIR0 = SuggestionEngine.computeSetFatigue(
            reps: 8, rir: 0.0, setType: .working, baseFatigueRate: 0.04
        )
        // RIR 0: effortScale = 1.45, RIR 3: effortScale = 1.0
        XCTAssertGreaterThan(fatigueRIR0, fatigueRIR3)
        XCTAssertEqual(fatigueRIR0 / fatigueRIR3, 1.45, accuracy: 0.01)
    }

    func testMissingRIRDefaultsTo1() {
        // Missing RIR defaults to 1.0, effortScale = 1.0 + max(0, 3.0 - 1.0) * 0.15 = 1.30
        let fatigueNilRIR = SuggestionEngine.computeSetFatigue(
            reps: 8, rir: nil, setType: .working, baseFatigueRate: 0.04
        )
        let fatigueRIR1 = SuggestionEngine.computeSetFatigue(
            reps: 8, rir: 1.0, setType: .working, baseFatigueRate: 0.04
        )
        XCTAssertEqual(fatigueNilRIR, fatigueRIR1, accuracy: 0.0001)
    }

    // MARK: - Session capability blend

    func testSessionCapabilityBlendRaisesRecommendationAfterEasyTopSet() {
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 1,
            setNumber: 2,
            target: SuggestionTarget(
                reps: 7,
                rir: 0,
                repRange: 6...8,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )
        let input = SuggestionEngineInput(
            baseE1RM: 50.67,
            baseSource: .recentPerformance,
            completedSessionSets: [
                SessionSetContext(
                    weight: 40,
                    reps: 8,
                    rir: 4.0,
                    completedAt: Date(),
                    completed: true,
                    setType: .working,
                    restDurationSeconds: nil
                )
            ],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 150,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try! XCTUnwrap(SuggestionEngine.evaluate(input).first)
        // With .observed policy, sessionCapability = observed e1RM directly (no blend with prior)
        // 40kg × (8+4) reps Epley = 40 × (1 + 12/30) = 56.0
        XCTAssertEqual(decision.sessionCapabilityE1RM, 56.0, accuracy: 0.001)
        XCTAssertEqual(decision.bestReps, 8)
    }

    func testSessionCapabilityBlendLowersRecommendationAfterMissedTopSet() {
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 1,
            setNumber: 2,
            target: SuggestionTarget(
                reps: 7,
                rir: 0,
                repRange: 6...8,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )
        let input = SuggestionEngineInput(
            baseE1RM: 86.67,
            baseSource: .recentPerformance,
            completedSessionSets: [
                SessionSetContext(
                    weight: 65,
                    reps: 8,
                    rir: 0.0,
                    completedAt: Date(),
                    completed: true,
                    setType: .working,
                    restDurationSeconds: nil
                )
            ],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try! XCTUnwrap(SuggestionEngine.evaluate(input).first)
        // With .observed policy: 65kg × (8+0) reps Epley = 65 × (1 + 8/30) = 82.333
        XCTAssertEqual(decision.sessionCapabilityE1RM, 82.333, accuracy: 0.001)
    }

    func testSessionCapabilityBlendMovesUpAndDownSymmetrically() {
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 1,
            setNumber: 2,
            target: SuggestionTarget(
                reps: 8,
                rir: 0,
                repRange: nil,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )

        let stronger = SuggestionEngineInput(
            baseE1RM: 100,
            baseSource: .recentPerformance,
            completedSessionSets: [
                SessionSetContext(
                    weight: 78.75,
                    reps: 10,
                    rir: 0.0,
                    completedAt: Date(),
                    completed: true,
                    setType: .working,
                    restDurationSeconds: nil
                )
            ],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 2.5,
                fatigueEnabled: false,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )
        let weaker = SuggestionEngineInput(
            baseE1RM: 100,
            baseSource: .recentPerformance,
            completedSessionSets: [
                SessionSetContext(
                    weight: 71.25,
                    reps: 10,
                    rir: 0.0,
                    completedAt: Date(),
                    completed: true,
                    setType: .working,
                    restDurationSeconds: nil
                )
            ],
            pendingSets: [pendingSet],
            settings: stronger.settings,
            calibrationAdjustment: .neutral
        )

        let strongerDecision = try! XCTUnwrap(SuggestionEngine.evaluate(stronger).first)
        let weakerDecision = try! XCTUnwrap(SuggestionEngine.evaluate(weaker).first)

        // With .observed: stronger = 78.75 × (1 + 10/30) = 105.0, weaker = 71.25 × (1 + 10/30) = 95.0
        XCTAssertEqual(strongerDecision.sessionCapabilityE1RM, 105.0, accuracy: 0.001)
        XCTAssertEqual(weakerDecision.sessionCapabilityE1RM, 95.0, accuracy: 0.001)
        XCTAssertEqual(
            strongerDecision.sessionCapabilityE1RM - 100,
            100 - weakerDecision.sessionCapabilityE1RM,
            accuracy: 0.001
        )
    }

    func testObservedPerformanceIsDefatiguedBeforeBlending() {
        let completedSets = [
            SessionSetContext(
                weight: 78.9474,
                reps: 8,
                rir: 0.0,
                completedAt: Date(),
                completed: true,
                setType: .working,
                restDurationSeconds: 180
            ),
            SessionSetContext(
                weight: 77.2625,
                reps: 8,
                rir: 0.0,
                completedAt: Date(),
                completed: true,
                setType: .working,
                restDurationSeconds: nil
            )
        ]
        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 2,
            setNumber: 3,
            target: SuggestionTarget(
                reps: 8,
                rir: 0.0,
                repRange: nil,
                repsSource: .template,
                rirSource: .template
            ),
            setType: .working
        )
        let input = SuggestionEngineInput(
            baseE1RM: 100,
            baseSource: .recentPerformance,
            completedSessionSets: completedSets,
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 180,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try! XCTUnwrap(SuggestionEngine.evaluate(input).first)
        XCTAssertEqual(decision.sessionCapabilityE1RM, 100, accuracy: 0.05)
    }

    // MARK: - Forward projection

    func testForwardProjectionDecreasesSuggestions() {
        let pendingSets = (0..<3).map { i in
            SuggestionPendingSetInput(
                setId: UUID(),
                setIndex: i,
                setNumber: i + 1,
                target: SuggestionTarget(
                    reps: 8, rir: 2.0, repRange: nil,
                    repsSource: .template, rirSource: .template
                ),
                setType: .working
            )
        }

        let input = SuggestionEngineInput(
            baseE1RM: 140,
            baseSource: .recentPerformance,
            completedSessionSets: [
                SessionSetContext(
                    weight: 100, reps: 8, rir: 2.0,
                    completedAt: Date(), completed: true,
                    setType: .working, restDurationSeconds: nil
                )
            ],
            pendingSets: pendingSets,
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 150,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decisions = SuggestionEngine.evaluate(input)
        XCTAssertEqual(decisions.count, 3)

        // Each successive pending set should have higher projected fatigue
        XCTAssertGreaterThan(decisions[1].projectedSessionFatigue, decisions[0].projectedSessionFatigue)
        XCTAssertGreaterThan(decisions[2].projectedSessionFatigue, decisions[1].projectedSessionFatigue)

        // And lower prescribed weights
        XCTAssertGreaterThanOrEqual(decisions[0].prescribedWeight, decisions[1].prescribedWeight)
        XCTAssertGreaterThanOrEqual(decisions[1].prescribedWeight, decisions[2].prescribedWeight)
    }

    // MARK: - Rest timer duration fallback

    func testRestTimerDurationUsedForDecay() {
        // With captured rest duration of 300s, fatigue should decay more than with 60s
        let longRest = [
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: 300
            ),
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: nil
            )
        ]
        let shortRest = [
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: 60
            ),
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: nil
            )
        ]

        let fatigueLongRest = SuggestionEngine.computeSessionFatigue(
            completedSets: longRest,
            configuredRestSeconds: 150,
            recoveryConstant: 180,
            baseFatigueRate: 0.04
        )
        let fatigueShortRest = SuggestionEngine.computeSessionFatigue(
            completedSets: shortRest,
            configuredRestSeconds: 150,
            recoveryConstant: 180,
            baseFatigueRate: 0.04
        )

        // Long rest → more decay → lower accumulated fatigue
        XCTAssertLessThan(fatigueLongRest, fatigueShortRest)
    }

    func testNilRestDurationFallsBackToConfigured() {
        let setsWithNil = [
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: nil
            ),
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: nil
            )
        ]
        let setsWithExplicit = [
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: 150
            ),
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: nil
            )
        ]

        let fatigueNil = SuggestionEngine.computeSessionFatigue(
            completedSets: setsWithNil,
            configuredRestSeconds: 150,
            recoveryConstant: 180,
            baseFatigueRate: 0.04
        )
        let fatigueExplicit = SuggestionEngine.computeSessionFatigue(
            completedSets: setsWithExplicit,
            configuredRestSeconds: 150,
            recoveryConstant: 180,
            baseFatigueRate: 0.04
        )

        // Both should be identical since nil falls back to configuredRestSeconds=150
        XCTAssertEqual(fatigueNil, fatigueExplicit, accuracy: 0.0001)
    }

    func testRestDurationOnCompletedSetAffectsTransitionIntoNextSet() {
        let restOnCompletedSetOne = [
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: 300
            ),
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: nil
            )
        ]
        let restShiftedToSetTwo = [
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: nil
            ),
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: 300
            )
        ]

        let firstTransitionFatigue = SuggestionEngine.computeSessionFatigue(
            completedSets: restOnCompletedSetOne,
            configuredRestSeconds: 150,
            recoveryConstant: 180,
            baseFatigueRate: 0.04
        )
        let shiftedTransitionFatigue = SuggestionEngine.computeSessionFatigue(
            completedSets: restShiftedToSetTwo,
            configuredRestSeconds: 150,
            recoveryConstant: 180,
            baseFatigueRate: 0.04
        )

        XCTAssertLessThan(firstTransitionFatigue, shiftedTransitionFatigue)
    }

    // MARK: - Readiness (no clamp)

    func testReadinessCanDropBelowOldClampFloor() {
        // Without readiness clamp, fatigue can push readiness below the old 88% floor
        let completedSets = (0..<5).map { _ in
            SessionSetContext(
                weight: 100, reps: 8, rir: 0.0,
                completedAt: Date(), completed: true,
                setType: .amrap, restDurationSeconds: 60
            )
        }

        let pendingSet = SuggestionPendingSetInput(
            setId: UUID(),
            setIndex: 5,
            setNumber: 1,
            target: SuggestionTarget(
                reps: 8, rir: 2.0, repRange: nil,
                repsSource: .template, rirSource: .template
            ),
            setType: .working
        )

        let input = SuggestionEngineInput(
            baseE1RM: 100,
            baseSource: .recentPerformance,
            completedSessionSets: completedSets,
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 60,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decisions = SuggestionEngine.evaluate(input)
        let decision = decisions[0]
        let readinessPercent = decision.effectiveE1RM / decision.baseE1RM

        // With no clamp, heavy fatigue can push readiness well below the old 88% floor
        XCTAssertLessThan(readinessPercent, 0.88)
    }

    // MARK: - Worked example from design doc

    func testWorkedExampleFromDesignDoc() {
        // Barbell squat, baseE1RM = 140kg, 5×8 @ RIR 2, 150s rest, recovery τ = 210s
        // Two completed sets, three pending
        let completedSets = [
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: 150
            ),
            SessionSetContext(
                weight: 100, reps: 8, rir: 2.0,
                completedAt: Date(), completed: true,
                setType: .working, restDurationSeconds: 150
            )
        ]

        let pendingSets = (0..<3).map { i in
            SuggestionPendingSetInput(
                setId: UUID(),
                setIndex: 2 + i,
                setNumber: i + 1,
                target: SuggestionTarget(
                    reps: 8, rir: 2.0, repRange: nil,
                    repsSource: .template, rirSource: .template
                ),
                setType: .working
            )
        }

        let input = SuggestionEngineInput(
            baseE1RM: 140,
            baseSource: .recentPerformance,
            completedSessionSets: completedSets,
            pendingSets: pendingSets,
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 150,
                weightIncrement: 2.5,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 210.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decisions = SuggestionEngine.evaluate(input)
        XCTAssertEqual(decisions.count, 3)

        // Progressive fatigue should increase
        XCTAssertGreaterThan(decisions[1].projectedSessionFatigue, decisions[0].projectedSessionFatigue)
        XCTAssertGreaterThan(decisions[2].projectedSessionFatigue, decisions[1].projectedSessionFatigue)

        // Effective e1RM should be less than base for all pending sets
        for decision in decisions {
            XCTAssertLessThan(decision.effectiveE1RM, 140)
        }
    }
}

@MainActor
final class TemplateMuscleTagLayoutTests: XCTestCase {

    func testNoMusclesShowsNoVisibleTagsAndNoOverflow() {
        let layout = TemplateMuscleTagLayout(muscleGroups: [])

        XCTAssertEqual(layout.visibleMuscleGroups, [])
        XCTAssertEqual(layout.hiddenMuscleGroupCount, 0)
    }

    func testUpToThreeMusclesShowsAllWithoutOverflow() {
        let muscles = ["chest", "back", "shoulders"]
        let layout = TemplateMuscleTagLayout(muscleGroups: muscles)

        XCTAssertEqual(layout.visibleMuscleGroups, muscles)
        XCTAssertEqual(layout.hiddenMuscleGroupCount, 0)
    }

    func testFourMusclesShowsFirstThreeAndPlusOne() {
        let layout = TemplateMuscleTagLayout(
            muscleGroups: ["chest", "back", "shoulders", "biceps"]
        )

        XCTAssertEqual(layout.visibleMuscleGroups, ["chest", "back", "shoulders"])
        XCTAssertEqual(layout.hiddenMuscleGroupCount, 1)
    }

    func testSixMusclesShowsFirstThreeAndPlusThree() {
        let layout = TemplateMuscleTagLayout(
            muscleGroups: ["chest", "back", "shoulders", "biceps", "triceps", "legs"]
        )

        XCTAssertEqual(layout.visibleMuscleGroups, ["chest", "back", "shoulders"])
        XCTAssertEqual(layout.hiddenMuscleGroupCount, 3)
    }
}

private extension PREvaluationResult {
    static func empty(for setId: UUID) -> PREvaluationResult {
        PREvaluationResult(
            setId: setId,
            newStatus: nil,
            affectedSetIds: [:],
            prRecordChanged: false
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private final class FatigueObservationRepositoryStub: @unchecked Sendable, FatigueObservationRepositoryProtocol {
    func upsert(_ observation: FatigueObservation) async throws {
        let _ = observation
    }
    func fetchObservations(for workoutId: UUID) async throws -> [FatigueObservation] {
        let _ = workoutId
        return []
    }
    func fetchObservations(exerciseId: UUID, limit: Int?) async throws -> [FatigueObservation] {
        let _ = exerciseId
        let _ = limit
        return []
    }
    func distinctWorkoutCount(exerciseId: UUID) async throws -> Int {
        let _ = exerciseId
        return 0
    }
    func deleteObservation(for setId: UUID) async throws {
        let _ = setId
    }
    @discardableResult
    func pruneObservations(exerciseId: UUID, keepRecentSessions: Int) async throws -> Int {
        let _ = exerciseId
        let _ = keepRecentSessions
        return 0
    }
}

private final class FatigueLearningSetAuditRepositoryStub: @unchecked Sendable, FatigueLearningSetAuditRepositoryProtocol {
    func upsert(_ audit: FatigueLearningSetAudit) async throws {
        let _ = audit
    }

    func fetchAudits(for workoutId: UUID) async throws -> [FatigueLearningSetAudit] {
        let _ = workoutId
        return []
    }

    func fetchAudits(workoutId: UUID, exerciseId: UUID) async throws -> [FatigueLearningSetAudit] {
        let _ = workoutId
        let _ = exerciseId
        return []
    }

    func fetchAudits(exerciseId: UUID, limit: Int?) async throws -> [FatigueLearningSetAudit] {
        let _ = exerciseId
        let _ = limit
        return []
    }

    func exerciseIdsWithAudits() async throws -> [UUID] {
        []
    }

    func deleteAudit(for setId: UUID) async throws {
        let _ = setId
    }

    func deleteAudits(workoutId: UUID) async throws {
        let _ = workoutId
    }

    func deleteAudits(exerciseId: UUID) async throws {
        let _ = exerciseId
    }

    func deleteAll() async throws {}
}

private func clearActiveWorkoutSessionDefaults() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockWorkoutId)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockAccumulatedElapsedSeconds)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockLastResumedAt)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockIsPaused)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseWorkoutId)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseId)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerStartDate)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused)
    defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource)
}

private func makeStubFatigueLearningService() -> FatigueLearningService {
    FatigueLearningService(
        observationRepo: FatigueObservationRepositoryStub(),
        exerciseRepo: ImportExerciseRepositoryStub(),
        healthProfileRepo: HealthProfileRepositoryStub(profile: HealthProfile()),
        auditRepo: FatigueLearningSetAuditRepositoryStub()
    )
}

private struct ExerciseTrackingTypeServiceContext {
    let service: ExerciseService
    let exerciseRepo: ExerciseRepository
    let setRepo: SetRepository
}

private func makeExerciseTrackingTypeServiceContext() throws -> ExerciseTrackingTypeServiceContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Exercise.self,
        WorkoutSet.self,
        ExerciseStats.self,
        PerformanceRecord.self,
        HealthProfile.self,
        configurations: configuration
    )

    let exerciseRepo = ExerciseRepository(modelContainer: container)
    let setRepo = SetRepository(modelContainer: container)
    let workoutRepo = WorkoutRepository(modelContainer: container)
    let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
    let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
    let healthProfileRepo = HealthProfileRepository(modelContainer: container)
    let prService = PRService(
        performanceRecordRepository: performanceRecordRepo,
        setRepository: setRepo,
        workoutRepository: workoutRepo,
        healthProfileRepository: healthProfileRepo,
        exerciseRepository: exerciseRepo
    )
    let statsService = StatsService(
        exerciseStatsRepository: exerciseStatsRepo,
        setRepository: setRepo,
        exerciseRepository: exerciseRepo,
        healthProfileRepository: healthProfileRepo,
        performanceRecordRepository: performanceRecordRepo
    )
    let service = ExerciseService(
        exerciseRepository: exerciseRepo,
        setRepository: setRepo,
        exerciseStatsRepository: exerciseStatsRepo,
        performanceRecordRepository: performanceRecordRepo,
        prService: prService,
        statsService: statsService,
        fatigueLearningService: makeStubFatigueLearningService()
    )

    return ExerciseTrackingTypeServiceContext(
        service: service,
        exerciseRepo: exerciseRepo,
        setRepo: setRepo
    )
}
