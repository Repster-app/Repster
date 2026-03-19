import XCTest
@testable import Reppo

@MainActor
final class ActiveWorkoutViewModelSuggestionRefreshTests: XCTestCase {

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
        XCTAssertEqual(context.viewModel.weightSuggestionData?.suggestions.first?.targetReps, initialSuggestion.targetReps)
        XCTAssertEqual(
            context.viewModel.suggestedWeight(for: context.pendingSet.id),
            initialSuggestion.suggestedWeight
        )

        try await waitUntil {
            context.viewModel.weightSuggestionData?.suggestions.first?.targetReps == 10
        }

        XCTAssertFalse(context.viewModel.isLoadingWeightSuggestions)
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

        context.viewModel.selectedExerciseIndex = 1
        let loadTask = Task {
            await context.viewModel.loadWeightSuggestions()
        }

        await Task.yield()
        XCTAssertTrue(context.viewModel.isLoadingWeightSuggestions)

        await loadTask.value

        XCTAssertFalse(context.viewModel.isLoadingWeightSuggestions)
        XCTAssertEqual(loadPrescriptionService.evaluationCount, 2)
        XCTAssertEqual(context.viewModel.currentExercise?.id, context.secondExercise?.id)
        XCTAssertEqual(context.viewModel.weightSuggestionData?.suggestions.first?.targetReps, 12)
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
            context.viewModel.weightSuggestionData?.suggestions.count == 2
        }

        XCTAssertEqual(loadPrescriptionService.evaluationCount, 2)
        XCTAssertEqual(context.viewModel.currentSets.count, 2)

        let firstSuggestion = try XCTUnwrap(context.viewModel.weightSuggestionData?.suggestions.first)
        XCTAssertEqual(
            context.viewModel.suggestedWeight(for: firstSuggestion.pendingSetId),
            firstSuggestion.suggestedWeight
        )
    }

    private func makeContext(
        loadPrescriptionService: LoadPrescriptionServiceSpy,
        setService: SetServiceStub = SetServiceStub(),
        exerciseCount: Int = 1,
        initialReps: Int = 8,
        secondExerciseReps: Int = 12
    ) -> TestContext {
        let profile = HealthProfile()
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
            loadPrescriptionService: loadPrescriptionService
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

    private func makeExercise(name: String) -> Exercise {
        Exercise(
            name: name,
            equipmentType: .barbell,
            trackingType: .weightReps,
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
        let target = SuggestionTarget(reps: 8, rir: 2.0, repRange: nil, source: .template)
        let pendingSet = SuggestionPendingSetInput(
            setId: availableSetId,
            setIndex: 0,
            setNumber: 1,
            target: target
        )
        let preparation = SuggestionPreparation(
            cacheKey: "mixed-row-states",
            completedSessionSets: [],
            setResolutions: [
                SuggestionSetResolution(
                    setId: availableSetId,
                    setIndex: 0,
                    setNumber: 1,
                    eligibility: .eligible(target: target)
                ),
                SuggestionSetResolution(
                    setId: unavailableSetId,
                    setIndex: 1,
                    setNumber: 2,
                    eligibility: .ineligible(reason: .missingTarget)
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
            evaluation: evaluation
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
        let target = SuggestionTarget(reps: 8, rir: 2.0, repRange: nil, source: .explicitSet)
        let pendingSet = SuggestionPendingSetInput(
            setId: setId,
            setIndex: 0,
            setNumber: 1,
            target: target
        )
        let preparation = SuggestionPreparation(
            cacheKey: "module-failure",
            completedSessionSets: [],
            setResolutions: [
                SuggestionSetResolution(
                    setId: setId,
                    setIndex: 0,
                    setNumber: 1,
                    eligibility: .eligible(target: target)
                )
            ],
            pendingSets: [pendingSet],
            unavailableReason: nil
        )

        let data = SuggestionExplainer.makeWeightSuggestionData(
            preparation: preparation,
            evaluation: .unavailable(.noStrengthData)
        )

        XCTAssertNil(data.suggestion(for: setId))
        XCTAssertEqual(data.rowState(for: setId)?.target?.reps, 8)
        XCTAssertEqual(data.rowState(for: setId)?.unavailableReason, .noStrengthData)
        XCTAssertEqual(data.unavailableReason, .noStrengthData)
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
                freshnessPercent: 0.03
            ),
            calibrationAdjustment: .neutral
        )
    }

    private func makeDecision(
        setId: UUID,
        setIndex: Int,
        setNumber: Int,
        target: SuggestionTarget
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
            effectiveE1RM: 100,
            intensityFactor: 0.8,
            fatigueDiscount: 1.0,
            freshnessApplied: false,
            e1RMSource: .recentPerformance,
            bestReps: nil,
            calibrationAdjustment: .neutral
        )
    }
}

private struct TestContext {
    let viewModel: ActiveWorkoutViewModel
    let exercise: Exercise
    let pendingSet: WorkoutSet
    let secondExercise: Exercise?
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
                freshnessPercent: 0.03
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
                    source: .explicitSet
                )
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
    func updatePrescriptionEnabled(_ enabled: Bool) async throws { let _ = enabled }
    func updatePrescriptionRecencyWeeks(_ weeks: Int) async throws { let _ = weeks }
    func updatePrescriptionDefaultIncrement(_ increment: Double) async throws { let _ = increment }
    func updatePrescriptionFreshnessBonus(enabled: Bool, percent: Double) async throws {
        let _ = enabled
        let _ = percent
    }
    func updatePrescriptionFatigueModelingEnabled(_ enabled: Bool) async throws { let _ = enabled }
    func updatePrescriptionDefaultRecoveryConstant(_ seconds: Double) async throws { let _ = seconds }
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
    func save(_ set: WorkoutSet) async throws -> SetSaveResult {
        SetSaveResult(
            setId: set.id,
            effectiveWeight: set.weight ?? 0,
            prResult: .empty(for: set.id)
        )
    }

    func edit(_ set: WorkoutSet) async throws -> SetSaveResult {
        try await save(set)
    }

    func uncomplete(_ set: WorkoutSet) async throws -> SetSaveResult {
        set.completed = false
        set.completedAt = nil
        return try await save(set)
    }

    func delete(_ set: WorkoutSet) async throws {
        let _ = set
    }

    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet] {
        let _ = workoutId
        return []
    }

    func fetchExerciseIds(for workoutId: UUID) async throws -> Set<UUID> {
        let _ = workoutId
        return []
    }

    func fetchSets(for exerciseId: UUID, limit: Int?) async throws -> [WorkoutSet] {
        let _ = exerciseId
        let _ = limit
        return []
    }
}

private final class WorkoutServiceStub: @unchecked Sendable, WorkoutServiceProtocol {
    func startWorkout() async throws -> Workout { Workout(startTime: Date()) }
    func finishWorkout(_ workoutId: UUID, title: String?, notes: String?, perceivedEffort: Double?) async throws {
        let _ = workoutId
        let _ = title
        let _ = notes
        let _ = perceivedEffort
    }
    func getActiveWorkout() async throws -> Workout? { nil }
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
    func deleteWorkout(_ workoutId: UUID) async throws {
        let _ = workoutId
    }
}

private final class ExerciseServiceStub: @unchecked Sendable, ExerciseServiceProtocol {
    func createExercise(_ exercise: Exercise) async throws { let _ = exercise }
    func updateExercise(_ exercise: Exercise, originalTrackingType: TrackingType) async throws {
        let _ = exercise
        let _ = originalTrackingType
    }
    func fetchExercise(_ exerciseId: UUID) async throws -> Exercise? {
        let _ = exerciseId
        return nil
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
        return false
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
