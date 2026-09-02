import XCTest
import SwiftData
import UserNotifications
@testable import Repster

@MainActor
final class ActiveWorkoutViewModelSuggestionRefreshTests: XCTestCase {

    // MARK: - Rest timer visibility
    //
    // The timer had a full and a compact height, and these tests pinned which one the keyboard
    // selected. It is one height now, so the only rule left to protect is the `.finished` one —
    // and that is the rule most easily lost, because it looks like sizing logic and isn't.

    func testRunningTimerIsVisibleWhenKeyboardHidden() {
        XCTAssertTrue(
            ActiveWorkoutBottomAccessoryLayout.shouldShowRestTimer(
                for: .running(remaining: 90, total: 120),
                isKeyboardVisible: false
            )
        )
    }

    func testRunningTimerStaysVisibleWhenKeyboardVisible() {
        XCTAssertTrue(
            ActiveWorkoutBottomAccessoryLayout.shouldShowRestTimer(
                for: .running(remaining: 90, total: 120),
                isKeyboardVisible: true
            )
        )
    }

    func testPausedTimerIsVisibleWhenKeyboardHidden() {
        XCTAssertTrue(
            ActiveWorkoutBottomAccessoryLayout.shouldShowRestTimer(
                for: .paused(remaining: 90, total: 120, source: .manual),
                isKeyboardVisible: false
            )
        )
    }

    func testPausedTimerStaysVisibleWhenKeyboardVisible() {
        XCTAssertTrue(
            ActiveWorkoutBottomAccessoryLayout.shouldShowRestTimer(
                for: .paused(remaining: 90, total: 120, source: .manual),
                isKeyboardVisible: true
            )
        )
    }

    func testIdleTimerIsHidden() {
        XCTAssertFalse(
            ActiveWorkoutBottomAccessoryLayout.shouldShowRestTimer(
                for: .idle,
                isKeyboardVisible: false
            )
        )
    }

    func testFinishedTimerIsVisibleWhenKeyboardHidden() {
        XCTAssertTrue(
            ActiveWorkoutBottomAccessoryLayout.shouldShowRestTimer(
                for: .finished,
                isKeyboardVisible: false
            )
        )
    }

    /// "Rest complete" must not appear while the set keypad is open: the message is redundant
    /// mid-entry, and the bar sliding in would push the keypad under a thumb already in motion.
    func testFinishedTimerIsHiddenWhenKeyboardVisible() {
        XCTAssertFalse(
            ActiveWorkoutBottomAccessoryLayout.shouldShowRestTimer(
                for: .finished,
                isKeyboardVisible: true
            )
        )
    }

    // MARK: - Reindexing is one batched write, not N pipeline runs (Stage 2 step 4)
    //
    // Adding or deleting a set used to persist each reindexed set through
    // `SetService.edit()` — the full effectiveWeight → PR → stats → fatigue pipeline — in its
    // own unawaited `Task`. That is the concurrent writer from §5.3 of the crash analysis.
    // These pin both halves of the replacement: one batch, and the same resulting order.

    @MainActor
    private func makeOrderingViewModel(
        setService: SetServiceStub
    ) -> ActiveWorkoutViewModel {
        let profile = HealthProfile()
        return ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: setService,
            exerciseService: ExerciseServiceStub(),
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            analyticsService: AnalyticsServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )
    }

    // MARK: - Superset rest behaviour (PR4)
    //
    // The whole feature, in one branch: a working set inside a group starts no rest timer, and
    // records that it did not. See SUPERSETS_SCOPING.md §2.2 and §4.

    /// Builds a two-exercise superset plus one ungrouped exercise, in display order.
    @MainActor
    private func makeSupersetViewModel(
        setService: SetServiceStub,
        preGrouped: Bool = true
    ) -> (viewModel: ActiveWorkoutViewModel, bench: UUID, incline: UUID, fly: UUID, group: UUID) {
        let viewModel = makeOrderingViewModel(setService: setService)
        let workoutId = UUID()
        viewModel.workout = Workout(id: workoutId, date: Date(), status: .inProgress)

        let bench = makeExercise(name: "Bench Press")
        let incline = makeExercise(name: "Incline DB Press")
        let fly = makeExercise(name: "Cable Fly")
        viewModel.exercises = [bench, incline, fly].map(ChartExerciseData.init(from:))

        let group = UUID()
        func row(_ exerciseId: UUID, _ order: Int, _ groupId: UUID?, _ type: SetType = .working) -> WorkoutSet {
            WorkoutSet(
                workoutId: workoutId,
                exerciseId: exerciseId,
                weight: 80,
                reps: 8,
                rir: 2,
                setType: type,
                orderInWorkout: order,
                orderInExercise: 1,
                supersetGroupId: groupId,
                completed: false
            )
        }

        let pairGroup = preGrouped ? group : nil
        let benchSet = row(bench.id, 1, pairGroup)
        let benchWarmup = row(bench.id, 2, pairGroup, .warmup)
        let inclineSet = row(incline.id, 3, pairGroup)
        let flySet = row(fly.id, 4, nil)

        viewModel.setsByExercise = [
            bench.id: [benchWarmup, benchSet],
            incline.id: [inclineSet],
            fly.id: [flySet]
        ]
        setService.workoutSets[workoutId] = [benchSet, benchWarmup, inclineSet, flySet]

        return (viewModel, bench.id, incline.id, fly.id, group)
    }

    /// The first member of a pair: no timer, and the zero is written down.
    func testCompletingASetMidSupersetStartsNoTimerAndRecordsZeroRest() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        let benchSet = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )

        await viewModel.completeSet(benchSet, input: SetCompletionInput(weight: 80, reps: 8, rir: 2))

        let timer = viewModel.restTimer
        XCTAssertEqual(timer, .idle, "a superset transition must not start a rest countdown")

        XCTAssertEqual(
            setService.recordedRestDurations.map(\.seconds), [0],
            """
            Zero must be written explicitly. Left nil, LoadPrescriptionService reads
            `restDurationSeconds ?? configuredRestSeconds` and decays fatigue as though a full
            two-minute rest happened — over-estimating readiness on exactly the sets where the
            lifter is most cooked.
            """
        )
        XCTAssertEqual(setService.recordedRestDurations.first?.setId, benchSet.id)
    }

    /// Closing a round earns rest **and** points back to the top of the group — both at once.
    func testClosingARoundStartsRestAndPointsBackToTheTop() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel
        viewModel.selectedExerciseIndex = 1

        let inclineSet = try XCTUnwrap(viewModel.setsByExercise[context.incline]?.first)
        await viewModel.completeSet(inclineSet, input: SetCompletionInput(weight: 30, reps: 10, rir: 2))

        let timer = viewModel.restTimer
        guard case .running = timer else {
            return XCTFail("closing a round rests normally, got \(timer)")
        }
        XCTAssertTrue(
            setService.recordedRestDurations.isEmpty,
            "a real timer records its own duration when it finishes — this path must not pre-empt it"
        )
        XCTAssertEqual(
            viewModel.supersetPrompt?.nextExerciseId, context.bench,
            "and the prompt wraps back so the next round is one tap, not a hunt"
        )
        XCTAssertTrue(
            ActiveWorkoutBottomAccessoryLayout.shouldShowSupersetPrompt(
                hasPrompt: true, restTimerState: timer, isKeyboardVisible: false
            ),
            "the two stack — the timer says how long, the prompt says where"
        )
    }

    /// Warm-ups are excluded by set type, not by grouping — the row still carries the group id.
    func testWarmupInsideASupersetStillRests() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        let warmup = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .warmup }
        )
        XCTAssertNotNil(warmup.supersetGroupId, "fixture: warm-ups carry the group id")

        await viewModel.completeSet(warmup, input: SetCompletionInput(weight: 40, reps: 10))

        let timer = viewModel.restTimer
        guard case .running = timer else {
            return XCTFail("a warm-up rests on the warm-up time even inside a group, got \(timer)")
        }
        XCTAssertTrue(setService.recordedRestDurations.isEmpty)
    }

    /// The path every existing user is on.
    func testUngroupedExerciseRestsExactlyAsBefore() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel
        viewModel.selectedExerciseIndex = 2

        let flySet = try XCTUnwrap(viewModel.setsByExercise[context.fly]?.first)
        await viewModel.completeSet(flySet, input: SetCompletionInput(weight: 17.5, reps: 15, rir: 3))

        let timer = viewModel.restTimer
        guard case .running = timer else {
            return XCTFail("an ungrouped set must rest, got \(timer)")
        }
        XCTAssertTrue(setService.recordedRestDurations.isEmpty)
    }

    // MARK: - Superset authoring (PR9)

    func testCreatingASupersetStampsEverySetOfBothExercises() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService, preGrouped: false)
        let viewModel = context.viewModel

        await viewModel.createSuperset(anchorExerciseId: context.bench, partnerExerciseId: context.incline)

        let benchGroups = Set((viewModel.setsByExercise[context.bench] ?? []).map(\.supersetGroupId))
        let inclineGroups = Set((viewModel.setsByExercise[context.incline] ?? []).map(\.supersetGroupId))

        XCTAssertEqual(benchGroups.count, 1, "every set of the anchor agrees")
        XCTAssertEqual(inclineGroups, benchGroups, "and the partner shares it")
        XCTAssertNotNil(benchGroups.first ?? nil)

        // Warm-ups included: "every set of this exercise agrees" has to stay true.
        XCTAssertEqual(
            (viewModel.setsByExercise[context.bench] ?? []).filter { $0.setType == .warmup }
                .compactMap(\.supersetGroupId).count,
            1,
            "a warm-up carries the group too — PR4 excludes it by set type, not by grouping"
        )
        XCTAssertTrue(viewModel.isInSuperset(context.bench))
    }

    func testCreatingASupersetLeavesUnrelatedExercisesAlone() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService, preGrouped: false)
        let viewModel = context.viewModel

        await viewModel.createSuperset(anchorExerciseId: context.bench, partnerExerciseId: context.incline)

        XCTAssertTrue(
            (viewModel.setsByExercise[context.fly] ?? []).allSatisfy { $0.supersetGroupId == nil }
        )
        XCTAssertFalse(viewModel.isInSuperset(context.fly))
    }

    /// A container cannot wrap two tabs with a third between them, so a distant partner moves.
    func testCreatingASupersetWithANonAdjacentPartnerMakesThemAdjacent() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService, preGrouped: false)
        let viewModel = context.viewModel

        // Bench is at 0, Cable Fly at 2 — Incline sits between them.
        await viewModel.createSuperset(anchorExerciseId: context.bench, partnerExerciseId: context.fly)

        let order = viewModel.exercises.map(\.id)
        XCTAssertEqual(order, [context.bench, context.fly, context.incline])

        let runs = SupersetGrouping.runs(
            exercises: viewModel.exercises,
            setsByExercise: viewModel.setsByExercise
        )
        XCTAssertTrue(runs[0].isMarked, "and the pair now draws as one container")
    }

    func testRemovingFromASupersetClearsEverySetIncludingCompletedOnes() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        // Log into the group first — the decision is that dissolving clears these too.
        let benchSet = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )
        await viewModel.completeSet(benchSet, input: SetCompletionInput(weight: 80, reps: 8, rir: 2))
        XCTAssertTrue(benchSet.completed)

        await viewModel.removeFromSuperset(exerciseId: context.bench)

        XCTAssertTrue(
            (viewModel.setsByExercise[context.bench] ?? []).allSatisfy { $0.supersetGroupId == nil },
            "Remove from Superset must mean the exercise is not in a superset — completed rows included"
        )
        XCTAssertFalse(viewModel.isInSuperset(context.bench))
    }

    /// Dissolving one half is enough: the survivor becomes a group of one, which every reader
    /// already treats as ungrouped. No second write.
    func testRemovingOneHalfLeavesTheOtherUngrouped() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        await viewModel.removeFromSuperset(exerciseId: context.bench)

        XCTAssertNotNil(
            viewModel.supersetGroupId(for: context.incline),
            "the survivor's rows are untouched — only their interpretation changes"
        )
        XCTAssertFalse(viewModel.isInSuperset(context.incline))
        XCTAssertEqual(setService.supersetGroupWrites.count, 1, "one write, not two")

        let runs = SupersetGrouping.runs(
            exercises: viewModel.exercises,
            setsByExercise: viewModel.setsByExercise
        )
        XCTAssertTrue(runs.allSatisfy { !$0.isMarked })
    }

    func testCreatingASupersetWithItselfIsARefusal() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService, preGrouped: false)
        let viewModel = context.viewModel

        await viewModel.createSuperset(anchorExerciseId: context.bench, partnerExerciseId: context.bench)

        XCTAssertTrue(setService.supersetGroupWrites.isEmpty)
        XCTAssertFalse(viewModel.isInSuperset(context.bench))
    }

    /// Do all of Incline first, then go back to Bench: every remaining Bench set points at an
    /// exercise with nothing left to do, and gets no rest for it.
    func testCompletingASetWhenThePartnerIsAlreadyFinishedStillRests() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        let inclineSet = try XCTUnwrap(viewModel.setsByExercise[context.incline]?.first)
        inclineSet.completed = true

        let benchSet = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )
        await viewModel.completeSet(benchSet, input: SetCompletionInput(weight: 80, reps: 8, rir: 2))

        guard case .running = viewModel.restTimer else {
            return XCTFail("nothing left to alternate with, so rest is earned — got \(viewModel.restTimer)")
        }
        XCTAssertNil(viewModel.supersetPrompt, "and nowhere to point")
    }

    // MARK: - Superset prompt lifecycle (PR5)

    func testCompletingASetMidSupersetRaisesThePromptNamingThePartner() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        let benchSet = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )
        await viewModel.completeSet(benchSet, input: SetCompletionInput(weight: 80, reps: 8, rir: 2))

        XCTAssertEqual(viewModel.supersetPrompt?.nextExerciseId, context.incline)
        XCTAssertEqual(viewModel.supersetPrompt?.nextExerciseName, "Incline DB Press")
    }

    func testTakingThePromptSwitchesExerciseAndClearsIt() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        let benchSet = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )
        await viewModel.completeSet(benchSet, input: SetCompletionInput(weight: 80, reps: 8, rir: 2))

        viewModel.goToSupersetPartner()

        XCTAssertEqual(viewModel.currentExercise?.id, context.incline)
        XCTAssertNil(viewModel.supersetPrompt, "the prompt has done its job once it is taken")
    }

    /// Walking over via the tab strip is the same outcome by a different route — the prompt is an
    /// offer, and navigating at all retires it.
    func testSwitchingExerciseByTabClearsThePrompt() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        let benchSet = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )
        await viewModel.completeSet(benchSet, input: SetCompletionInput(weight: 80, reps: 8, rir: 2))
        XCTAssertNotNil(viewModel.supersetPrompt)

        viewModel.selectedExerciseIndex = 2

        XCTAssertNil(viewModel.supersetPrompt)
    }

    /// Un-ticking is a correction: whatever the completion said to do next no longer follows.
    func testUncompletingTheSetClearsThePrompt() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        let benchSet = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )
        await viewModel.completeSet(benchSet, input: SetCompletionInput(weight: 80, reps: 8, rir: 2))
        XCTAssertNotNil(viewModel.supersetPrompt)

        await viewModel.uncompleteSet(benchSet)

        XCTAssertNil(viewModel.supersetPrompt)
    }

    func testDismissingThePromptLeavesTheExerciseAlone() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        let benchSet = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )
        await viewModel.completeSet(benchSet, input: SetCompletionInput(weight: 80, reps: 8, rir: 2))

        viewModel.dismissSupersetPrompt()

        XCTAssertNil(viewModel.supersetPrompt)
        XCTAssertEqual(viewModel.currentExercise?.id, context.bench, "dismiss must not navigate")
    }

    /// With the group finished there is nowhere left to send anyone.
    func testAFinishedGroupRaisesNoPrompt() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel
        viewModel.selectedExerciseIndex = 1

        // Bench's only working set is already done, so closing Incline closes the group.
        let benchWorking = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )
        benchWorking.completed = true

        let inclineSet = try XCTUnwrap(viewModel.setsByExercise[context.incline]?.first)
        await viewModel.completeSet(inclineSet, input: SetCompletionInput(weight: 30, reps: 10, rir: 2))

        XCTAssertNil(viewModel.supersetPrompt)
        guard case .running = viewModel.restTimer else {
            return XCTFail("and rest runs as it would for any ungrouped exercise")
        }
    }

    /// The prompt must not outlive the workout it belongs to.
    func testDiscardingTheWorkoutClearsThePrompt() async throws {
        let setService = SetServiceStub()
        let context = makeSupersetViewModel(setService: setService)
        let viewModel = context.viewModel

        let benchSet = try XCTUnwrap(
            viewModel.setsByExercise[context.bench]?.first { $0.setType == .working }
        )
        await viewModel.completeSet(benchSet, input: SetCompletionInput(weight: 80, reps: 8, rir: 2))
        XCTAssertNotNil(viewModel.supersetPrompt)

        await viewModel.discardWorkout()

        XCTAssertNil(viewModel.supersetPrompt)
        XCTAssertEqual(viewModel.restTimer, .idle, "and the slot's other occupant goes too")
    }

    // MARK: - Accessory slot arbitration

    func testSupersetPromptIsSuppressedWhileTheKeypadIsOpen() {
        XCTAssertTrue(
            ActiveWorkoutBottomAccessoryLayout.shouldShowSupersetPrompt(
                hasPrompt: true, restTimerState: .idle, isKeyboardVisible: false
            )
        )
        XCTAssertFalse(
            ActiveWorkoutBottomAccessoryLayout.shouldShowSupersetPrompt(
                hasPrompt: true, restTimerState: .idle, isKeyboardVisible: true
            ),
            "same rule as a finished rest — a bar appearing under a thumb mid-entry shifts the keypad"
        )
    }

    func testThePromptStacksAboveARunningRestTimer() {
        XCTAssertTrue(
            ActiveWorkoutBottomAccessoryLayout.shouldShowSupersetPrompt(
                hasPrompt: true,
                restTimerState: .running(remaining: 60, total: 120),
                isKeyboardVisible: false
            ),
            "closing a round makes both answers live at once"
        )
        XCTAssertFalse(
            ActiveWorkoutBottomAccessoryLayout.shouldShowSupersetPrompt(
                hasPrompt: false, restTimerState: .idle, isKeyboardVisible: false
            )
        )
    }

    func testAddingWarmupSetReindexesInOneBatchAndPutsWarmupFirst() async throws {
        let setService = SetServiceStub()
        let viewModel = makeOrderingViewModel(setService: setService)

        let exercise = makeExercise(name: "Back Squat")
        let workoutId = UUID()
        viewModel.workout = Workout(id: workoutId, date: Date(), status: .inProgress)
        viewModel.exercises = [ChartExerciseData(from: exercise)]

        let working1 = makeSet(exerciseId: exercise.id, order: 1, reps: 5)
        let working2 = makeSet(exerciseId: exercise.id, order: 2, reps: 5)
        working2.orderInWorkout = 2
        viewModel.setsByExercise = [exercise.id: [working1, working2]]

        await viewModel.addWarmupSet(for: exercise.id)

        // The warmup lands ahead of both working sets, and orderInExercise is contiguous.
        let sets = try XCTUnwrap(viewModel.setsByExercise[exercise.id])
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.map(\.setType), [.warmup, .working, .working])
        XCTAssertEqual(sets.map(\.orderInExercise), [1, 2, 3])

        // The whole reindex is persisted as batches, not one write per changed set. The old
        // code issued an unawaited edit() per set; anything above a couple of batches means
        // the fan-out is back.
        XCTAssertFalse(setService.orderingBatches.isEmpty, "ordering was never persisted")
        XCTAssertLessThanOrEqual(
            setService.orderingBatches.count,
            2,
            "reindex should batch, not issue one write per set"
        )
        XCTAssertTrue(
            setService.editedSetIds.isEmpty,
            "ordering must not run the PR/stats/fatigue pipeline via edit()"
        )
    }

    /// Deleting a PR owner re-badges the set that inherits the record.
    ///
    /// `SetService.delete` used to return `Void` — it computed `prService.handleDeletion(...)`
    /// and discarded it, so `deleteSet` had no way to apply the result. The promoted set's badge
    /// still reached the screen, but only because `PRService` mutated the very `@Model` instance
    /// the ViewModel held. Once `setsByExercise` holds value types that stops working, and the
    /// badge would stay wrong until relaunch.
    ///
    /// This has to be a **stub** test. Against the real stack it proves nothing: `PRService`
    /// writes the status onto the shared instance before `applyAffectedSets` ever runs, so the
    /// assertion passes with or without the fix — measured in
    /// `AffectedSetsPreconditionTests`. The stub touches no models, so `applyAffectedSets` is
    /// the only route by which this badge can change.
    func testDeletingAPROwnerAppliesTheBadgeChangeReportedByTheService() async throws {
        let setService = SetServiceStub()
        let viewModel = makeOrderingViewModel(setService: setService)

        let exercise = makeExercise(name: "Bench Press")
        viewModel.workout = Workout(id: UUID(), date: Date(), status: .inProgress)
        viewModel.exercises = [ChartExerciseData(from: exercise)]

        let holder = makeSet(exerciseId: exercise.id, order: 1, reps: 5)
        let inheritor = makeSet(exerciseId: exercise.id, order: 2, reps: 5)
        inheritor.completed = true
        inheritor.prStatus = nil
        viewModel.setsByExercise = [exercise.id: [holder, inheritor]]

        // The pipeline reports that deleting `holder` promoted `inheritor`.
        setService.deleteAffectedSetIds = [inheritor.id: .current]

        await viewModel.deleteSet(holder)

        let remaining = try XCTUnwrap(viewModel.setsByExercise[exercise.id])
        XCTAssertEqual(remaining.map(\.id), [inheritor.id])
        XCTAssertEqual(
            remaining.first?.prStatus,
            .current,
            "the surviving set never received the badge the delete pipeline reported — "
                + "SetService.delete's PREvaluationResult is being dropped again"
        )
    }

    func testDeletingSetReindexesRemainingSetsContiguouslyInOneBatch() async throws {
        let setService = SetServiceStub()
        let viewModel = makeOrderingViewModel(setService: setService)

        let exercise = makeExercise(name: "Bench Press")
        viewModel.workout = Workout(id: UUID(), date: Date(), status: .inProgress)
        viewModel.exercises = [ChartExerciseData(from: exercise)]

        let set1 = makeSet(exerciseId: exercise.id, order: 1, reps: 5)
        let set2 = makeSet(exerciseId: exercise.id, order: 2, reps: 5)
        let set3 = makeSet(exerciseId: exercise.id, order: 3, reps: 5)
        viewModel.setsByExercise = [exercise.id: [set1, set2, set3]]

        await viewModel.deleteSet(set2)

        let sets = try XCTUnwrap(viewModel.setsByExercise[exercise.id])
        XCTAssertEqual(sets.map(\.id), [set1.id, set3.id])
        XCTAssertEqual(sets.map(\.orderInExercise), [1, 2], "orders must close the gap")
        XCTAssertEqual(setService.deletedSetIds, [set2.id])
        XCTAssertEqual(
            setService.orderingBatches.count,
            1,
            "one reindex should be one batched write"
        )
        XCTAssertEqual(
            setService.orderingBatches.first?.count,
            1,
            "only the set whose order actually changed should be written"
        )
    }

    // MARK: - Exercise snapshots must not go stale mid-workout (Stage 2 step 1 follow-up)

    /// An exercise edited while the workout is open has to reach `exercises`.
    ///
    /// That array is otherwise written only on load and on add, so a frozen snapshot leaves
    /// the rest timer reading the old `defaultRestTime` and `loadExerciseInfo` plus the
    /// suggestion inputs reading the old `weightIncrement` — which are exactly the two fields
    /// `ExerciseSettingsSheet` edits. Before the snapshot conversion this array held the live
    /// `Exercise` the sheet mutated, so it refreshed for free.
    func testRefreshingConfigurationRereadsTheCurrentExerciseSnapshot() async throws {
        let exerciseService = ExerciseServiceStub()
        let profile = HealthProfile()
        let exercise = Exercise(
            name: "Back Squat",
            equipmentType: .barbell,
            trackingType: .weightReps,
            weightIncrement: 2.5,
            defaultRestTime: 90
        )
        exerciseService.fetchedExercises[exercise.id] = exercise

        let viewModel = ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: SetServiceStub(),
            exerciseService: exerciseService,
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            analyticsService: AnalyticsServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )
        viewModel.workout = Workout(id: UUID(), date: Date(), status: .inProgress)
        viewModel.exercises = [ChartExerciseData(from: exercise)]
        viewModel.setsByExercise = [exercise.id: []]

        XCTAssertEqual(viewModel.currentExercise?.defaultRestTime, 90)

        // The settings sheet persists through the service, so the store now holds new values
        // while the ViewModel still holds the snapshot it loaded with.
        exercise.defaultRestTime = 180
        exercise.weightIncrement = 5

        await viewModel.refreshCurrentExerciseConfigurationData()

        XCTAssertEqual(
            viewModel.currentExercise?.defaultRestTime,
            180,
            "the rest timer would keep starting at the pre-edit duration"
        )
        XCTAssertEqual(
            viewModel.currentExercise?.weightIncrement,
            5,
            "exercise info and the suggestion inputs would recompute from the pre-edit increment"
        )
    }

    func testBackgroundRestTimerNotificationUsesSystemSoundForVibrationMode() {
        XCTAssertTrue(
            RestTimerAlarmCoordinator.usesSystemSound(for: "vibration")
        )
    }

    func testBackgroundRestTimerNotificationDisablesSystemSoundWhenAlertsAreOff() {
        XCTAssertFalse(
            RestTimerAlarmCoordinator.usesSystemSound(for: "off")
        )
    }

    // MARK: - Rest timer alarm: foreground presentation
    //
    // The rule these pin down: a rest alarm arriving while Repster is in the foreground becomes
    // a banner *unless* something in-app is about to alert for the same event. The tick and the
    // notification trigger are scheduled for the same instant and race every set, so getting
    // this wrong is either a double alert or — as shipped — total silence.

    func testForegroundAlarmIsSuppressedWhileARunningTimerWillAlertInApp() {
        RestTimerAlarmCoordinator.shared.resetInAppAlertMarker()
        let alerter = StubForegroundAlerter(willAlert: true)
        RestTimerAlarmCoordinator.shared.registerForegroundAlerter(alerter)
        defer { RestTimerAlarmCoordinator.shared.resignForegroundAlerter(alerter) }

        XCTAssertEqual(RestTimerAlarmCoordinator.shared.currentPresentationOptions(), [])
    }

    func testForegroundAlarmPresentsWhenTheRegisteredHandlerWillNotAlert() {
        RestTimerAlarmCoordinator.shared.resetInAppAlertMarker()
        let alerter = StubForegroundAlerter(willAlert: false)
        RestTimerAlarmCoordinator.shared.registerForegroundAlerter(alerter)
        defer { RestTimerAlarmCoordinator.shared.resignForegroundAlerter(alerter) }

        XCTAssertEqual(
            RestTimerAlarmCoordinator.shared.currentPresentationOptions(),
            [.banner, .sound, .list]
        )
    }

    /// The back-button case, and the reason the reference is weak rather than a flag someone
    /// has to remember to clear: the ViewModel simply goes away with the workout cover.
    func testForegroundAlarmPresentsOnceTheHandlerHasBeenDeallocated() {
        RestTimerAlarmCoordinator.shared.resetInAppAlertMarker()
        do {
            let alerter = StubForegroundAlerter(willAlert: true)
            RestTimerAlarmCoordinator.shared.registerForegroundAlerter(alerter)
            XCTAssertEqual(RestTimerAlarmCoordinator.shared.currentPresentationOptions(), [])
        }

        XCTAssertEqual(
            RestTimerAlarmCoordinator.shared.currentPresentationOptions(),
            [.banner, .sound, .list],
            "A deallocated handler must not keep suppressing the alarm"
        )
    }

    /// SwiftUI can hold the outgoing and incoming ViewModel at once across a cover transition.
    func testResigningAnOlderHandlerDoesNotClearItsReplacement() {
        RestTimerAlarmCoordinator.shared.resetInAppAlertMarker()
        let outgoing = StubForegroundAlerter(willAlert: false)
        let incoming = StubForegroundAlerter(willAlert: true)

        RestTimerAlarmCoordinator.shared.registerForegroundAlerter(outgoing)
        RestTimerAlarmCoordinator.shared.registerForegroundAlerter(incoming)
        RestTimerAlarmCoordinator.shared.resignForegroundAlerter(outgoing)
        defer { RestTimerAlarmCoordinator.shared.resignForegroundAlerter(incoming) }

        XCTAssertEqual(RestTimerAlarmCoordinator.shared.currentPresentationOptions(), [])
    }

    // MARK: - Rest timer alarm: the double-alert race
    //
    // Reported after the delegate shipped: one observed instance of both a banner and the in-app
    // alert, not reproducible by hand. `timerTick()` sets `restTimer = .finished` before firing
    // the alert, so a notification iOS had already committed to delivering reaches `willPresent`
    // with the state no longer `.running` — the handler truthfully answers "nothing will alert",
    // about an alert that just happened.

    func testNotificationArrivingJustAfterTheInAppAlertIsSuppressed() {
        let alertedAt = Date()

        XCTAssertEqual(
            RestTimerAlarmCoordinator.presentationOptions(
                // False exactly as the real handler reports it once state is `.finished`.
                hasInAppAlerter: false,
                lastInAppAlertAt: alertedAt,
                now: alertedAt.addingTimeInterval(0.2)
            ),
            []
        )
    }

    func testAnOldInAppAlertDoesNotSuppressALaterAlarm() {
        let alertedAt = Date()

        XCTAssertEqual(
            RestTimerAlarmCoordinator.presentationOptions(
                hasInAppAlerter: false,
                lastInAppAlertAt: alertedAt,
                now: alertedAt.addingTimeInterval(60)
            ),
            [.banner, .sound, .list]
        )
    }

    /// The fix must not re-break the back-button case it was built on top of.
    func testNoInAppAlertEverMeansTheAlarmStillPresents() {
        XCTAssertEqual(
            RestTimerAlarmCoordinator.presentationOptions(
                hasInAppAlerter: false,
                lastInAppAlertAt: nil
            ),
            [.banner, .sound, .list]
        )
    }

    func testMarkingAnInAppAlertSuppressesThroughTheLiveCoordinator() {
        RestTimerAlarmCoordinator.shared.resetInAppAlertMarker()
        defer { RestTimerAlarmCoordinator.shared.resetInAppAlertMarker() }

        // No handler registered — the back-button shape, which must present.
        XCTAssertEqual(
            RestTimerAlarmCoordinator.shared.currentPresentationOptions(),
            [.banner, .sound, .list]
        )

        RestTimerAlarmCoordinator.shared.noteInAppAlertFired()

        XCTAssertEqual(
            RestTimerAlarmCoordinator.shared.currentPresentationOptions(),
            [],
            "A notification landing right after the in-app alert is the same event"
        )
    }

    // MARK: - Rest timer alarm: what the ViewModel promises the coordinator

    func testViewModelOnlyClaimsTheInAppAlertWhileTheTimerIsRunning() async throws {
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

        XCTAssertFalse(viewModel.willAlertRestTimerInApp, "idle")

        viewModel.startRestTimer(duration: 30)
        XCTAssertTrue(viewModel.willAlertRestTimerInApp, "running")

        viewModel.toggleRestTimerPause()
        XCTAssertFalse(viewModel.willAlertRestTimerInApp, "paused — no tick will fire")

        viewModel.toggleRestTimerPause()
        XCTAssertTrue(viewModel.willAlertRestTimerInApp, "resumed")

        viewModel.dismissTimer()
        XCTAssertFalse(viewModel.willAlertRestTimerInApp, "dismissed")
    }

    /// L2: the band and the start-date maths used to disagree after a clamped subtraction.
    func testSubtractingPastZeroKeepsTheDisplayedAndAuthoritativeClocksInAgreement() async throws {
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
        viewModel.subtractTime(15)

        guard case .running(let remaining, let total) = viewModel.restTimer else {
            return XCTFail("Expected the timer to still be running after a clamped subtraction")
        }
        XCTAssertEqual(remaining, 1, "clamped to the 1s floor")

        // total - elapsed is what `recalculateTimerAfterBackground` recomputes from. With
        // elapsed ~0 immediately after starting, it has to land on the displayed remaining.
        XCTAssertEqual(total, remaining, "total must equal elapsed + remaining, and elapsed is ~0")
    }

    // MARK: - Rest alarm authorization

    private func clearRestAlarmPreferences() {
        let d = UserDefaults.standard
        d.removeObject(forKey: RestTimerAlarmPreferences.authorizationKey)
        d.removeObject(forKey: RestTimerAlarmPreferences.hasBeenOfferedKey)
    }

    func testAuthorizationMappingTreatsProvisionalAsUnableToAlert() {
        XCTAssertEqual(RestTimerAlarmCoordinator.authorization(for: .notDetermined), .notDetermined)
        XCTAssertEqual(RestTimerAlarmCoordinator.authorization(for: .denied), .denied)
        XCTAssertEqual(RestTimerAlarmCoordinator.authorization(for: .authorized), .authorized)
        XCTAssertEqual(RestTimerAlarmCoordinator.authorization(for: .ephemeral), .authorized)

        // Provisional delivers silently to Notification Centre. For "will the user be told rest
        // is over", silent delivery is not reaching them.
        XCTAssertEqual(RestTimerAlarmCoordinator.authorization(for: .provisional), .denied)
    }

    /// The flag `recalculateTimerAfterBackground` consults before deciding to stay quiet.
    func testCanAlertFromBackgroundOnlyWhenAuthorized() {
        clearRestAlarmPreferences()
        defer { clearRestAlarmPreferences() }

        XCTAssertFalse(RestTimerAlarmCoordinator.canAlertFromBackground, "notDetermined")

        RestTimerAlarmPreferences.store(.denied)
        XCTAssertFalse(RestTimerAlarmCoordinator.canAlertFromBackground, "denied")

        RestTimerAlarmPreferences.store(.authorized)
        XCTAssertTrue(RestTimerAlarmCoordinator.canAlertFromBackground, "authorized")
    }

    private func makeTimerViewModel() -> ActiveWorkoutViewModel {
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
        return viewModel
    }

    func testFirstRestTimerRaisesTheExplainerWhenPermissionIsUndecided() {
        clearActiveWorkoutSessionDefaults()
        clearRestAlarmPreferences()
        defer { clearActiveWorkoutSessionDefaults(); clearRestAlarmPreferences() }

        let viewModel = makeTimerViewModel()
        viewModel.startRestTimer(duration: 30)

        XCTAssertTrue(viewModel.showRestAlarmPrompt)
    }

    func testExplainerIsNotRaisedTwice() {
        clearActiveWorkoutSessionDefaults()
        clearRestAlarmPreferences()
        defer { clearActiveWorkoutSessionDefaults(); clearRestAlarmPreferences() }

        RestTimerAlarmPreferences.markOffered()

        let viewModel = makeTimerViewModel()
        viewModel.startRestTimer(duration: 30)

        XCTAssertFalse(viewModel.showRestAlarmPrompt)
    }

    /// Someone who answered iOS's prompt in an older build has already spent it; re-explaining
    /// would be noise with nothing to offer.
    func testExplainerIsSkippedWhenPermissionWasAlreadyDecided() {
        clearActiveWorkoutSessionDefaults()
        clearRestAlarmPreferences()
        defer { clearActiveWorkoutSessionDefaults(); clearRestAlarmPreferences() }

        RestTimerAlarmPreferences.store(.denied)

        let viewModel = makeTimerViewModel()
        viewModel.startRestTimer(duration: 30)

        XCTAssertFalse(viewModel.showRestAlarmPrompt)
    }

    func testDecliningTheExplainerSpendsTheOfferButNotTheSystemPrompt() {
        clearActiveWorkoutSessionDefaults()
        clearRestAlarmPreferences()
        defer { clearActiveWorkoutSessionDefaults(); clearRestAlarmPreferences() }

        let viewModel = makeTimerViewModel()
        viewModel.startRestTimer(duration: 30)
        viewModel.declineRestAlarmAuthorization()

        XCTAssertFalse(viewModel.showRestAlarmPrompt)
        XCTAssertTrue(RestTimerAlarmPreferences.hasBeenOffered)
        XCTAssertEqual(
            RestTimerAlarmPreferences.lastKnownAuthorization,
            .notDetermined,
            "iOS must not have been asked — Settings has to stay able to turn this on later"
        )
    }

    // MARK: - Live Activity rest display
    //
    // The widget's two view chains are unreachable from a test (`ActivityViewContext` has no
    // public initialiser), so the branch logic lives on `ContentState` and is pinned here.

    private func restState(
        running: Bool = false,
        paused: Bool = false,
        workoutPaused: Bool = false,
        finished: Bool = false,
        endDate: Date? = nil
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: "Bench Press",
            currentSetNumber: 2,
            totalSets: 4,
            setTypeLabel: "Working",
            elapsedTimerReferenceDate: Date(),
            isWorkoutPaused: workoutPaused,
            pausedElapsedSeconds: 0,
            isRestTimerRunning: running,
            isRestTimerPaused: paused,
            restTimerEndDate: endDate,
            restTimerTotalSeconds: 120,
            restTimerRemainingSeconds: 60,
            isRestTimerFinished: finished
        )
    }

    /// The bug: while the app is suspended nothing pushes `isRestTimerFinished`, so a timer
    /// whose end date has passed used to fall through to `.ready` — "Ready for next set".
    func testExpiredRestTimerReadsAsCompleteWithoutAPush() {
        let now = Date()
        let state = restState(running: true, endDate: now.addingTimeInterval(-1))

        XCTAssertEqual(state.restDisplay(at: now), .complete)
    }

    func testRunningRestTimerCountsDownUntilItsEndDate() {
        let now = Date()
        let end = now.addingTimeInterval(45)

        XCTAssertEqual(
            restState(running: true, endDate: end).restDisplay(at: now),
            .counting(until: end)
        )
    }

    func testPushedFinishedFlagStillReadsAsComplete() {
        XCTAssertEqual(restState(finished: true).restDisplay(at: Date()), .complete)
    }

    func testNoTimerReadsAsReady() {
        XCTAssertEqual(restState().restDisplay(at: Date()), .ready)
    }

    /// Pauses outrank the countdown: a paused timer has no meaningful end date.
    func testPausedStatesOutrankAnExpiredEndDate() {
        let now = Date()
        let stale = now.addingTimeInterval(-30)

        XCTAssertEqual(
            restState(running: true, paused: true, endDate: stale).restDisplay(at: now),
            .restPaused
        )
        XCTAssertEqual(
            restState(running: true, paused: true, workoutPaused: true, endDate: stale).restDisplay(at: now),
            .workoutPaused
        )
    }

    // MARK: - Rest timer alarm: shared teardown

    /// `SettingsService.clearStoredAppState` and `ContentView.discardActiveAndCopy` both clear
    /// this state from outside the ViewModel, and disagreed about which keys existed.
    func testClearRestTimerStateRemovesEveryRestTimerKey() {
        let defaults = UserDefaults.standard
        defaults.set("workout-id", forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId)
        defaults.set(Date(), forKey: ActiveWorkoutSessionDefaultsKeys.restTimerStartDate)
        defaults.set(180, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration)
        defaults.set(90, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration)
        defaults.set(true, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused)
        defaults.set("manual", forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource)

        ActiveWorkoutSessionDefaultsKeys.clearRestTimerState()

        XCTAssertNil(defaults.object(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId))
        XCTAssertNil(defaults.object(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerStartDate))
        XCTAssertNil(defaults.object(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration))
        XCTAssertNil(defaults.object(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration))
        XCTAssertNil(defaults.object(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused))
        XCTAssertNil(defaults.object(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource))
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
        viewModel.exercises = [ChartExerciseData(from: makeExercise(name: "Back Squat"))]
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
        XCTAssertEqual(completionEvent.properties[.durationBucket], .string("15-30m"))
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

        let createdExercise = try XCTUnwrap(exerciseService.createdExerciseFields.last)
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
            exercise: ChartExerciseData(from: existingExercise),
            exerciseService: exerciseService,
            settingsService: SettingsServiceStub(profile: HealthProfile())
        )

        viewModel.name = "Incline DB Press"
        viewModel.primaryMuscle = ExercisePrimaryGroup.fullBody.rawValue

        try await viewModel.save()

        let updatedExercise = try XCTUnwrap(exerciseService.updatedExerciseFields.last?.fields)
        XCTAssertEqual(updatedExercise.primaryMuscle, "full body")
        XCTAssertEqual(updatedExercise.secondaryMuscles, ["shoulders", "triceps"])
        XCTAssertEqual(existingExercise.secondaryMuscles, ["shoulders", "triceps"])
    }

    func testCreateEditExerciseViewModelKeepsLegacyPrimaryGroupSelectableDuringEdit() {
        let viewModel = CreateEditExerciseViewModel(
            exercise: ChartExerciseData(from: Exercise(
                name: "Hammer Curl",
                equipmentType: .dumbbell,
                trackingType: .weightReps,
                primaryMuscle: "arms"
            )),
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
            exercise: ChartExerciseData(from: Exercise(
                name: "Run",
                equipmentType: .bodyweight,
                trackingType: .duration
            )),
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
            exercise: ChartExerciseData(from: Exercise(
                name: "Run",
                equipmentType: .bodyweight,
                trackingType: .durationDistance
            )),
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
        viewModel.exercises = [ChartExerciseData(from: existingExercise)]
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

        viewModel.exercises = [ChartExerciseData(from: exerciseA), ChartExerciseData(from: exerciseB), ChartExerciseData(from: exerciseC)]
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

        // Ordering is persisted as ONE batched `applyOrdering`, never per-set `edit()`.
        // This assertion replaced an `editedSetIds` one that pinned the fan-out this migration
        // removed — see EXERCISE_REPLACE_AND_REORDER_DESIGN.md §2.
        try await waitUntil {
            !setService.orderingBatches.isEmpty
        }

        XCTAssertEqual(
            setService.orderingBatches.count,
            1,
            "one reorder should be one batched write, not one per set"
        )
        XCTAssertTrue(
            setService.editedSetIds.isEmpty,
            "ordering must not run the PR/stats/fatigue pipeline via edit()"
        )
        XCTAssertEqual(
            setService.orderingBatches.first?.map(\.setId),
            [cWorking.id, bWarmup.id, bWorking.id],
            "only the sets whose orderInWorkout actually moved should be written"
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

    // MARK: - Identity-based selection (EXERCISE_REPLACE_AND_REORDER_DESIGN.md §3)

    /// One exercise per name, one working set each, contiguous `orderInWorkout` from 1.
    ///
    /// `spares` are registered with the exercise service but left *out* of the workout — the pool a
    /// replacement can be picked from.
    private func makeStripFixture(
        names: [String],
        selecting selectedIndex: Int,
        spares: [String] = []
    ) -> (
        viewModel: ActiveWorkoutViewModel,
        exercises: [Exercise],
        spares: [Exercise],
        setService: SetServiceStub
    ) {
        let profile = HealthProfile()
        let setService = SetServiceStub()
        let exerciseService = ExerciseServiceStub()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: WorkoutServiceStub(),
            setService: setService,
            exerciseService: exerciseService,
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )

        let exercises = names.map { makeExercise(name: $0) }
        let spareExercises = spares.map { makeExercise(name: $0) }
        for exercise in exercises + spareExercises {
            exerciseService.fetchedExercises[exercise.id] = exercise
        }

        let workoutId = UUID()
        viewModel.workout = Workout(id: workoutId, date: Date(), status: .inProgress)
        viewModel.exercises = exercises.map { ChartExerciseData(from: $0) }

        var sets: [UUID: [WorkoutSet]] = [:]
        for (offset, exercise) in exercises.enumerated() {
            sets[exercise.id] = [
                WorkoutSet(
                    workoutId: workoutId,
                    exerciseId: exercise.id,
                    reps: 8,
                    rir: 2.0,
                    orderInWorkout: offset + 1,
                    orderInExercise: 1,
                    completed: false
                )
            ]
        }
        viewModel.setsByExercise = sets
        viewModel.selectedExerciseIndex = selectedIndex

        return (viewModel, exercises, spareExercises, setService)
    }

    private var persistedSelectedExerciseId: UUID? {
        UserDefaults.standard
            .string(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseId)
            .flatMap(UUID.init(uuidString:))
    }

    /// Defect B. Moving a *non-selected* exercise across the selection shifted the array underneath
    /// a fixed integer, switching the user to a different exercise mid-set. Fails before the fix.
    func testReorderingANonSelectedExerciseKeepsTheUserOnTheirExercise() throws {
        let (viewModel, exercises, _, _) = makeStripFixture(names: ["A", "B", "C"], selecting: 1)
        XCTAssertEqual(viewModel.currentExercise?.id, exercises[1].id, "precondition: on B")

        // Move C in front of B. The user is on B and never touched C.
        viewModel.reorderExercises(from: IndexSet(integer: 2), to: 1)

        XCTAssertEqual(viewModel.exercises.map(\.id), [exercises[0].id, exercises[2].id, exercises[1].id])
        XCTAssertEqual(
            viewModel.currentExercise?.id,
            exercises[1].id,
            "selection must follow the exercise, not the slot"
        )
        XCTAssertEqual(viewModel.selectedExerciseId, exercises[1].id)
        XCTAssertEqual(viewModel.selectedExerciseIndex, 2, "index re-derived from identity")
    }

    /// The case the old code got right. Must keep working.
    func testReorderingTheSelectedExerciseKeepsSelectionOnIt() throws {
        let (viewModel, exercises, _, _) = makeStripFixture(names: ["A", "B", "C"], selecting: 1)

        viewModel.reorderExercises(from: IndexSet(integer: 1), to: 3)

        XCTAssertEqual(viewModel.exercises.map(\.id), [exercises[0].id, exercises[2].id, exercises[1].id])
        XCTAssertEqual(viewModel.currentExercise?.id, exercises[1].id)
        XCTAssertEqual(viewModel.selectedExerciseIndex, 2)
    }

    /// Defect B at a third call site, found while implementing the fix. Removing an exercise
    /// *before* the selected one shifts the array left, and the old clamp only fired when the index
    /// ran off the end — so the user silently landed on the exercise *after* the one they were on,
    /// while the persisted resume state still pointed at the right one. Fails before the fix.
    func testRemovingAnExerciseBeforeTheSelectedOneKeepsTheUserOnTheirExercise() async throws {
        let (viewModel, exercises, _, _) = makeStripFixture(names: ["A", "B", "C"], selecting: 1)
        XCTAssertEqual(viewModel.currentExercise?.id, exercises[1].id, "precondition: on B")

        await viewModel.removeExercise(at: 0)

        XCTAssertEqual(viewModel.exercises.map(\.id), [exercises[1].id, exercises[2].id])
        XCTAssertEqual(
            viewModel.currentExercise?.id,
            exercises[1].id,
            "selection must follow the exercise, not the slot"
        )
        XCTAssertEqual(viewModel.selectedExerciseIndex, 0)
        XCTAssertEqual(
            persistedSelectedExerciseId,
            exercises[1].id,
            "screen and persisted resume state must agree"
        )
    }

    /// Removing the exercise you are *on* has no anchor to return to, so it clamps — the old
    /// behaviour, and the right one here.
    func testRemovingTheSelectedExerciseClampsIntoRange() async throws {
        let (viewModel, exercises, _, _) = makeStripFixture(names: ["A", "B", "C"], selecting: 2)

        await viewModel.removeExercise(at: 2)

        XCTAssertEqual(viewModel.exercises.map(\.id), [exercises[0].id, exercises[1].id])
        XCTAssertEqual(viewModel.selectedExerciseIndex, 1)
        XCTAssertEqual(viewModel.currentExercise?.id, exercises[1].id)
        XCTAssertEqual(persistedSelectedExerciseId, exercises[1].id)
    }

    // MARK: - Replace exercise (EXERCISE_REPLACE_AND_REORDER_DESIGN.md §4)

    /// The guard from §4.4.1. The strip's `ForEach` is keyed by exercise ID, so a duplicate would
    /// give undefined selection and animation.
    func testReplacingWithAnExerciseAlreadyInTheWorkoutIsRejected() async throws {
        let (viewModel, exercises, _, setService) = makeStripFixture(names: ["A", "B", "C"], selecting: 1)

        await viewModel.replaceExercise(at: 0, with: exercises[2].id)

        XCTAssertEqual(viewModel.exercises.map(\.id), exercises.map(\.id), "nothing may move")
        XCTAssertTrue(setService.deletedSetIds.isEmpty, "nothing may be deleted")
    }

    /// §4.4.2 — fetch before mutating, so a failed lookup is a no-op rather than a workout with a
    /// hole in it.
    func testReplacingWhenTheSnapshotFetchFailsDeletesNothing() async throws {
        let (viewModel, exercises, _, setService) = makeStripFixture(names: ["A", "B", "C"], selecting: 1)

        // An ID the exercise service has never heard of — the stub returns nil.
        await viewModel.replaceExercise(at: 0, with: UUID())

        XCTAssertEqual(viewModel.exercises.map(\.id), exercises.map(\.id))
        XCTAssertTrue(setService.deletedSetIds.isEmpty, "a failed fetch must not delete anything")
    }

    /// Position held, old rows gone, one empty set seeded.
    func testReplacingAMiddleExerciseHoldsItsPositionAndSeedsOneSet() async throws {
        let (viewModel, exercises, spares, setService) = makeStripFixture(
            names: ["A", "B", "C"],
            selecting: 0,
            spares: ["Replacement"]
        )
        let outgoingSetIds = viewModel.setsByExercise[exercises[1].id]?.map(\.id) ?? []
        XCTAssertFalse(outgoingSetIds.isEmpty, "precondition: the outgoing exercise has rows")

        await viewModel.replaceExercise(at: 1, with: spares[0].id)

        XCTAssertEqual(
            viewModel.exercises.map(\.id),
            [exercises[0].id, spares[0].id, exercises[2].id],
            "the replacement takes the same slot"
        )
        XCTAssertEqual(setService.deletedSetIds, outgoingSetIds, "the outgoing rows are deleted")
        XCTAssertNil(viewModel.setsByExercise[exercises[1].id], "outgoing sets are dropped from state")
        XCTAssertEqual(viewModel.setsByExercise[spares[0].id]?.count, 1, "exactly one seeded set")
        XCTAssertFalse(
            setService.orderingBatches.isEmpty,
            "the seeded set lands at the global tail, so a reindex is mandatory"
        )
    }

    /// §4.4.8. Replacing the exercise you are *on* changes the identity while the index stays put,
    /// so the switch side effects have to fire off identity rather than the integer.
    func testReplacingTheSelectedExerciseMovesSelectionOntoTheReplacement() async throws {
        let (viewModel, exercises, spares, _) = makeStripFixture(
            names: ["A", "B", "C"],
            selecting: 1,
            spares: ["Replacement"]
        )

        await viewModel.replaceExercise(at: 1, with: spares[0].id)

        XCTAssertEqual(viewModel.selectedExerciseIndex, 1, "the integer does not move")
        XCTAssertEqual(viewModel.currentExercise?.id, spares[0].id, "but the exercise does")
        XCTAssertEqual(viewModel.selectedExerciseId, spares[0].id)
        XCTAssertEqual(
            persistedSelectedExerciseId,
            spares[0].id,
            "persisted resume state must follow the identity, not the index"
        )
        _ = exercises
    }

    /// Replacing someone else's slot must not move the user.
    func testReplacingANonSelectedExerciseLeavesSelectionAlone() async throws {
        let (viewModel, exercises, spares, _) = makeStripFixture(
            names: ["A", "B", "C"],
            selecting: 1,
            spares: ["Replacement"]
        )

        await viewModel.replaceExercise(at: 2, with: spares[0].id)

        XCTAssertEqual(viewModel.selectedExerciseIndex, 1)
        XCTAssertEqual(viewModel.currentExercise?.id, exercises[1].id, "the user does not move")
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

        // The spy records the call on entry, so `evaluationCount` rises when the refresh is
        // *dispatched* — the applied state lands later. Waiting on the count alone and then
        // asserting on the state races that gap, which is a sub-millisecond window in isolation and
        // a real one under full-suite load.
        try await waitUntil {
            loadPrescriptionService.evaluationCount == 2 &&
            context.viewModel.suggestionState(for: context.pendingSet.id)?.target?.repRange == 8...12
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

        // Same dispatch-vs-applied race as the manual-draft test above.
        try await waitUntil {
            loadPrescriptionService.evaluationCount == 2 &&
            context.viewModel.suggestionState(for: context.pendingSet.id)?.target?.repRange == 8...12
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
        viewModel.exercises = [ChartExerciseData(from: exercise)]
        viewModel.setsByExercise = [exercise.id: [uncompletedSet, deletedSet, typeChangedSet]]
        // The stub models the store, and `changeSetType` now applies its field writes there
        // rather than to the caller's instance — so the sets have to actually be in it.
        setService.workoutSets[workout.id] = [uncompletedSet, deletedSet, typeChangedSet]

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

        viewModel.exercises = [ChartExerciseData(from: exercise)]
        viewModel.selectedExerciseIndex = 0
        viewModel.setsByExercise = [exercise.id: [pendingSet]]

        var secondExercise: Exercise?
        if exerciseCount > 1 {
            let otherExercise = makeExercise(name: "Exercise 2")
            let otherSet = makeSet(exerciseId: otherExercise.id, order: 1, reps: secondExerciseReps)
            viewModel.exercises.append(ChartExerciseData(from: otherExercise))
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
            exercise: ChartExerciseData(from: exercise),
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
            "Based on your recent performance for this rep target. Missing targets used your Smart Suggestions defaults."
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
            "Easing off slightly to manage session fatigue."
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
            exercise: ChartExerciseData(from: exercise),
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
            exercise: ChartExerciseData(from: exercise),
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
            exercise: ChartExerciseData(from: exercise),
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
            exercise: ChartExerciseData(from: exercise),
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

        let presentation = SetTableView.unilateralTargetPresentation(for: set, exercise: ChartExerciseData(from: exercise))

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
            exercise: ChartExerciseData(from: exercise),
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
            exercise: ChartExerciseData(from: exercise),
            workout: includedWorkout,
            sets: [set],
            profile: profile
        )
        let excluded = SuggestionCoordinator.prepare(
            exercise: ChartExerciseData(from: exercise),
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
            exercise: ChartExerciseData(from: excludedExercise),
            workout: workout,
            sets: [excludedSet],
            profile: profile
        )
        let allowed = SuggestionCoordinator.prepare(
            exercise: ChartExerciseData(from: allowedExercise),
            workout: workout,
            sets: [allowedSet],
            profile: profile
        )

        XCTAssertNil(excluded.unavailableReason)
        XCTAssertEqual(excluded.pendingSets.count, 1)
        XCTAssertNil(allowed.unavailableReason)
    }

    func testFirstSetRepRangeProgressionPricesNineRepsNotEight() throws {
        // Reported 2026-08-26: after 60 kg x 8 @ RIR 0 in two consecutive
        // sessions, widening the target to 6-10 suggested 58.75 kg, which reads
        // as a step down from 60. It is not: the engine priced 9 reps, where
        // 58.75 implies an e1RM of 76.375 against the 76.0 baseline.
        let setId = UUID()
        let target = SuggestionTarget(
            reps: 8,
            rir: 0,
            repRange: 6...10,
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
        let input = SuggestionEngineInput(
            baseE1RM: 76.0, // Epley from 60 kg x 8
            baseSource: .recentPerformance,
            completedSessionSets: [],
            pendingSets: [pendingSet],
            settings: SuggestionSettingsSnapshot(
                formula: .epley,
                restTimerSeconds: 120,
                weightIncrement: 1.25,
                fatigueEnabled: true,
                freshnessEnabled: false,
                freshnessPercent: 0.03,
                baseFatigueRate: 0.04,
                recoveryConstant: 180.0,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: .neutral
        )

        let decision = try XCTUnwrap(SuggestionEngine.evaluate(input).first)

        XCTAssertEqual(decision.prescribedWeight, 58.75, accuracy: 0.001)
        XCTAssertEqual(decision.bestReps, 9)
        XCTAssertEqual(decision.selectionPolicy, .firstSetProgressionAboveRecentPeak)
    }

    func testRepRangeSuggestionLabelsThePrescribedRepCountNotTheRange() throws {
        let setId = UUID()
        let target = SuggestionTarget(
            reps: 8,
            rir: 0,
            repRange: 6...10,
            repsSource: .explicitSet,
            rirSource: .explicitSet
        )
        let suggestion = try makeSuggestion(setId: setId, target: target, bestReps: 9)

        XCTAssertEqual(suggestion.prescribedDisplayLabel, "9 reps")
        XCTAssertEqual(suggestion.targetDisplayLabel, "6-10 reps")
        XCTAssertEqual(suggestion.targetReps, 9)
    }

    func testFixedRepTargetLabelsAreUnchangedByThePrescribedRepCount() throws {
        let setId = UUID()
        let target = SuggestionTarget(
            reps: 8,
            rir: 0,
            repRange: nil,
            repsSource: .explicitSet,
            rirSource: .explicitSet
        )
        let suggestion = try makeSuggestion(setId: setId, target: target, bestReps: nil)

        XCTAssertEqual(suggestion.prescribedDisplayLabel, "8 reps")
        XCTAssertEqual(suggestion.targetDisplayLabel, "8 reps")
    }

    func testUnilateralRepRangeSuggestionKeepsPerSideWordingOnThePrescribedCount() throws {
        let setId = UUID()
        let target = SuggestionTarget(
            reps: 8,
            rir: 0,
            repRange: 6...10,
            repsSource: .template,
            rirSource: .template,
            displayReps: 8,
            displayRepRange: 6...10,
            repTargetMode: .perSide
        )
        let suggestion = try makeSuggestion(setId: setId, target: target, bestReps: 9)

        XCTAssertEqual(suggestion.prescribedDisplayLabel, "9 reps each side")
        XCTAssertEqual(suggestion.targetDisplayLabel, "6-10 reps each side")
    }

    private func makeSuggestion(
        setId: UUID,
        target: SuggestionTarget,
        bestReps: Int?
    ) throws -> SetSuggestion {
        let pendingSet = SuggestionPendingSetInput(
            setId: setId,
            setIndex: 0,
            setNumber: 1,
            target: target,
            setType: .working
        )
        let preparation = SuggestionPreparation(
            cacheKey: "prescribed-rep-label",
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
                    bestReps: bestReps
                )
            ],
            unavailableReason: nil
        )

        let data = SuggestionExplainer.makeWeightSuggestionData(
            preparation: preparation,
            evaluation: evaluation,
            unitPreference: .metric
        )
        return try XCTUnwrap(data.suggestion(for: setId))
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
        projectedSessionFatigue: Double = 0.0,
        bestReps: Int? = nil
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
            e1RMSourceWorkoutDate: nil,
            e1RMSourceTopSet: nil,
            sessionCapabilitySourceLabel: SessionCapabilityPolicy.observed.label,
            bestReps: bestReps,
            selectionPolicy: selectionPolicy,
            selectionReferenceE1RM: selectionReferenceE1RM,
            calibrationAdjustment: .neutral,
            projectedSessionFatigue: projectedSessionFatigue,
            appliedFloor: nil
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

/// Regression coverage for rebuild detection on exercise metadata edits (FR-006,
/// specdoc S5.6).
///
/// The original implementation compared the edited exercise against a re-fetch of
/// itself. Both came from the same repository context, so SwiftData returned the
/// same instance and every comparison was a value against itself — rebuilds never
/// ran. The pre-edit values now have to be captured by the caller.
final class ExerciseRebuildDetectionTests: XCTestCase {

    private func makeLoggedSet(for exerciseId: UUID) -> WorkoutSet {
        WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseId,
            weight: 100,
            reps: 5,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
    }

    func testEquipmentTypeChangeRebuildsPRsAndStats() async throws {
        let context = try makeExerciseRebuildServiceContext()
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        try await context.exerciseRepo.save(exercise)
        try await context.setRepo.save(makeLoggedSet(for: exercise.id))

        var fields = ExerciseEditableFields(from: exercise)
        fields.equipmentType = .bodyweight

        try await context.service.updateExercise(id: exercise.id, fields: fields)

        XCTAssertEqual(context.prService.rebuiltExerciseIds, [exercise.id])
        XCTAssertEqual(context.statsService.rebuiltExerciseIds, [exercise.id])
    }

    func testUnilateralAndBodyweightFactorChangesRebuild() async throws {
        let context = try makeExerciseRebuildServiceContext()
        let exercise = Exercise(
            name: "Split Squat",
            equipmentType: .dumbbell,
            trackingType: .weightReps
        )
        try await context.exerciseRepo.save(exercise)
        try await context.setRepo.save(makeLoggedSet(for: exercise.id))

        var fields = ExerciseEditableFields(from: exercise)
        fields.unilateral = !fields.unilateral
        fields.bodyweightFactor = 0.65

        try await context.service.updateExercise(id: exercise.id, fields: fields)

        XCTAssertEqual(context.prService.rebuiltExerciseIds, [exercise.id])
        XCTAssertEqual(context.statsService.rebuiltExerciseIds, [exercise.id])
    }

    func testNonCalculationFieldEditDoesNotRebuild() async throws {
        let context = try makeExerciseRebuildServiceContext()
        let exercise = Exercise(
            name: "Overhead Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        try await context.exerciseRepo.save(exercise)
        try await context.setRepo.save(makeLoggedSet(for: exercise.id))

        var fields = ExerciseEditableFields(from: exercise)
        fields.defaultRestTime = 180
        fields.primaryMuscle = "Shoulders"

        try await context.service.updateExercise(id: exercise.id, fields: fields)

        XCTAssertTrue(context.prService.rebuiltExerciseIds.isEmpty)
        XCTAssertTrue(context.statsService.rebuiltExerciseIds.isEmpty)
    }

    // MARK: - Value-based exercise editing (Stage 2 step 1)
    //
    // `updateExercise` used to take the live `Exercise` the UI was rendering and save it on
    // the repository actor — the write half of crash B. It now takes plain values and the
    // mutation happens inside the owning actor. These pin the behaviour that has to survive.

    func testUpdateExercisePersistsEveryEditableField() async throws {
        let context = try makeExerciseRebuildServiceContext()
        let exercise = Exercise(
            name: "Old Name",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            secondaryMuscles: ["triceps"],
            movementPattern: .press,
            unilateral: false,
            bilateralLoadFactor: 1.0,
            bodyweightFactor: 0,
            weightIncrement: 2.5,
            defaultRestTime: 60
        )
        try await context.exerciseRepo.save(exercise)

        var fields = ExerciseEditableFields(from: exercise)
        fields.name = "New Name"
        fields.equipmentType = .dumbbell
        fields.trackingType = .weightRepsDuration
        fields.primaryMuscle = "shoulders"
        fields.secondaryMuscles = ["chest", "core"]
        fields.movementPattern = .squat
        fields.unilateral = true
        fields.unilateralRepTargetMode = .totalAcrossSides
        fields.bilateralLoadFactor = 2.0
        fields.bodyweightFactor = 0.4
        fields.weightIncrement = 1.25
        fields.defaultRestTime = 150

        try await context.service.updateExercise(id: exercise.id, fields: fields)

        let persistedFetched = try await context.exerciseRepo.fetchChartExercise(byId: exercise.id)
        let persisted = try XCTUnwrap(persistedFetched)
        XCTAssertEqual(persisted.name, "New Name")
        XCTAssertEqual(persisted.equipmentType, .dumbbell)
        XCTAssertEqual(persisted.trackingType, .weightRepsDuration)
        XCTAssertEqual(persisted.primaryMuscle, "shoulders")
        XCTAssertEqual(persisted.secondaryMuscles, ["chest", "core"])
        XCTAssertEqual(persisted.movementPattern, .squat)
        XCTAssertTrue(persisted.unilateral)
        XCTAssertEqual(persisted.unilateralRepTargetMode, .totalAcrossSides)
        XCTAssertEqual(persisted.bilateralLoadFactor, 2.0)
        XCTAssertEqual(persisted.bodyweightFactor, 0.4)
        XCTAssertEqual(persisted.weightIncrement, 1.25)
        XCTAssertEqual(persisted.defaultRestTime, 150)
    }

    /// A metadata edit must not wipe the adaptive-fatigue state, which is owned by
    /// FatigueLearningService and deliberately absent from `ExerciseEditableFields`.
    func testUpdateExercisePreservesFatigueLearningState() async throws {
        let context = try makeExerciseRebuildServiceContext()
        let exercise = Exercise(
            name: "Chest Press",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            fatigueRate: 0.026,
            fatigueRateSourceRawValue: ExerciseFatigueRateSource.learned.rawValue,
            recoveryConstant: 240,
            fatigueLearningSessionCount: 5,
            fatigueLearningCumulativeError: -0.031
        )
        try await context.exerciseRepo.save(exercise)
        let createdAt = exercise.createdAt

        var fields = ExerciseEditableFields(from: exercise)
        fields.name = "Chest Press (Machine)"
        try await context.service.updateExercise(id: exercise.id, fields: fields)

        let persistedFetched = try await context.exerciseRepo.fetchChartExercise(byId: exercise.id)
        let persisted = try XCTUnwrap(persistedFetched)
        XCTAssertEqual(persisted.name, "Chest Press (Machine)")
        XCTAssertEqual(persisted.fatigueRate, 0.026)
        XCTAssertEqual(persisted.fatigueRateSourceRawValue, ExerciseFatigueRateSource.learned.rawValue)
        XCTAssertEqual(persisted.recoveryConstant, 240)
        XCTAssertEqual(persisted.fatigueLearningSessionCount, 5)
        XCTAssertEqual(persisted.fatigueLearningCumulativeError, -0.031)
        XCTAssertEqual(persisted.createdAt, createdAt, "createdAt must not be rewritten by an edit")
        XCTAssertGreaterThanOrEqual(persisted.updatedAt, createdAt)
    }

    /// An edit that changes one field must leave every other field alone. This is what the
    /// old code got for free by mutating the model field by field.
    func testUpdateExerciseLeavesUntouchedFieldsAlone() async throws {
        let context = try makeExerciseRebuildServiceContext()
        let exercise = Exercise(
            name: "Incline Dumbbell Press",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            secondaryMuscles: ["shoulders", "triceps"],
            movementPattern: .press,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides,
            bilateralLoadFactor: 1.75,
            bodyweightFactor: 0.15,
            weightIncrement: 1.25,
            defaultRestTime: 105
        )
        try await context.exerciseRepo.save(exercise)
        let beforeFetched = try await context.exerciseRepo.fetchChartExercise(byId: exercise.id)
        let before = try XCTUnwrap(beforeFetched)

        var fields = ExerciseEditableFields(from: before)
        fields.primaryMuscle = "full body"
        try await context.service.updateExercise(id: exercise.id, fields: fields)

        let afterFetched = try await context.exerciseRepo.fetchChartExercise(byId: exercise.id)
        let after = try XCTUnwrap(afterFetched)
        XCTAssertEqual(after.primaryMuscle, "full body")
        XCTAssertEqual(after.secondaryMuscles, before.secondaryMuscles)
        XCTAssertEqual(after.movementPattern, before.movementPattern)
        XCTAssertEqual(after.unilateralRepTargetMode, before.unilateralRepTargetMode)
        XCTAssertEqual(after.bilateralLoadFactor, before.bilateralLoadFactor)
        XCTAssertEqual(after.bodyweightFactor, before.bodyweightFactor)
        XCTAssertEqual(after.weightIncrement, before.weightIncrement)
        XCTAssertEqual(after.defaultRestTime, before.defaultRestTime)
        XCTAssertEqual(after.name, before.name)
        XCTAssertEqual(after.equipmentType, before.equipmentType)
        XCTAssertEqual(after.trackingType, before.trackingType)
    }

    func testCreateExercisePersistsEveryField() async throws {
        let context = try makeExerciseRebuildServiceContext()

        let fields = ExerciseEditableFields(
            name: "Cable Fly",
            equipmentType: .cable,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            secondaryMuscles: ["shoulders"],
            movementPattern: .press,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides,
            bilateralLoadFactor: 1.5,
            bodyweightFactor: 0.1,
            weightIncrement: 2.5,
            defaultRestTime: 75
        )
        let id = try await context.service.createExercise(fields: fields)

        let persistedFetched = try await context.exerciseRepo.fetchChartExercise(byId: id)
        let persisted = try XCTUnwrap(persistedFetched)
        XCTAssertEqual(ExerciseEditableFields(from: persisted), fields)
    }

    /// The pre-edit state is now read from the store rather than supplied by the caller.
    /// Editing an id that no longer exists must fail loudly rather than silently no-op.
    func testUpdateExerciseThrowsWhenExerciseIsMissing() async throws {
        let context = try makeExerciseRebuildServiceContext()
        let fields = ExerciseEditableFields(
            name: "Ghost",
            equipmentType: .barbell,
            trackingType: .weightReps
        )

        do {
            try await context.service.updateExercise(id: UUID(), fields: fields)
            XCTFail("Expected updateExercise to throw for a missing exercise")
        } catch let error as ExerciseServiceError {
            guard case .exerciseNotFound = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testEquipmentTypeChangeDoesNotRebuildWithoutLoggedSetData() async throws {
        let context = try makeExerciseRebuildServiceContext()
        let exercise = Exercise(
            name: "Landmine Press",
            equipmentType: .barbell,
            trackingType: .weightReps
        )
        try await context.exerciseRepo.save(exercise)

        var fields = ExerciseEditableFields(from: exercise)
        fields.equipmentType = .machinePin

        try await context.service.updateExercise(id: exercise.id, fields: fields)

        XCTAssertTrue(context.prService.rebuiltExerciseIds.isEmpty)
        XCTAssertTrue(context.statsService.rebuiltExerciseIds.isEmpty)
    }

    /// `deleteExercise` describes itself as a full cascade and did not touch templates, so every
    /// template using the exercise kept a row pointing at an id that no longer resolved — shown as
    /// "Unknown Exercise" and still counted in the template's set total. The removal semantics are
    /// covered in TemplateServiceTests; this asserts the cascade actually reaches them.
    func testDeleteExerciseRemovesTheTemplateRowsThatPointAtIt() async throws {
        let context = try makeExerciseRebuildServiceContext()
        let doomed = Exercise(name: "Wrist Cur", equipmentType: .other, trackingType: .weightReps)
        let kept = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps)
        try await context.exerciseRepo.save(doomed)
        try await context.exerciseRepo.save(kept)

        let template = WorkoutTemplate(name: "Upper Body 2")
        try await context.templateRepo.saveTemplate(template)
        try await context.templateRepo.replaceTemplateContents(
            templateId: template.id,
            exercises: [
                TemplateSaveExercise(
                    exerciseId: kept.id,
                    orderInTemplate: 1,
                    supersetGroupId: nil,
                    restTimeSeconds: nil,
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
                ),
                TemplateSaveExercise(
                    exerciseId: doomed.id,
                    orderInTemplate: 2,
                    supersetGroupId: nil,
                    restTimeSeconds: nil,
                    notes: nil,
                    sets: [
                        TemplateSaveSet(
                            setType: .working,
                            targetRepMin: nil,
                            targetRepMax: nil,
                            targetRIR: nil,
                            orderInExercise: 1
                        )
                    ]
                )
            ]
        )

        try await context.service.deleteExercise(doomed.id)

        let rows = try await context.templateRepo.fetchTemplateExercises(for: template.id)
        XCTAssertEqual(rows.map(\.exerciseId), [kept.id])
        XCTAssertEqual(rows.map(\.orderInTemplate), [1])
        let keptSets = try await context.templateRepo.fetchTemplateSets(for: rows[0].id)
        XCTAssertEqual(keptSets.count, 1)
        XCTAssertEqual(keptSets.first?.targetRepMin, 6)
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

        var fields = ExerciseEditableFields(from: exercise)
        fields.trackingType = .durationDistance

        try await context.service.updateExercise(id: exercise.id, fields: fields)

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

        var fields = ExerciseEditableFields(from: exercise)
        fields.trackingType = .durationDistance

        try await context.service.updateExercise(id: exercise.id, fields: fields)

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

        var fields = ExerciseEditableFields(from: exercise)
        fields.trackingType = .durationDistance

        do {
            try await context.service.updateExercise(id: exercise.id, fields: fields)
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
        // Includes the exercise with no logged sets: the archive carries the whole library now.
        XCTAssertEqual(restoreResult.exercisesUpserted, 2)
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
            // A version above `currentVersion` is a stale app, not a bad file.
            guard case .archiveVersionTooNew(let version) = error else {
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

// MARK: - Delete Ordering

/// The screen must stop pointing at a row *before* the row leaves the store.
///
/// A deleted SwiftData model traps inside `getValue` on any persisted-property read, and the main
/// actor keeps rendering throughout a delete: the workout clock invalidates every observer once a
/// second, and the summary sheet's own `isDiscarding` write queues a re-render immediately before
/// the await. Shipped as an `EXC_BREAKPOINT` in 1.4 (4) — discard from the summary sheet,
/// `computeSummary()` mapped `setsByExercise` into `ChartSetData` mid-delete, and
/// `WorkoutSet.setType` trapped.
///
/// These tests observe the ViewModel from *inside* the service call, because the ordering is only
/// visible while the delete is in flight; asserting on the end state passes either way.
/// Background in `DISCARD_USE_AFTER_DELETE_SCOPING.md`.
@MainActor
final class DeleteOrderingTests: XCTestCase {

    /// What the screen held while a delete was in flight.
    private final class MidDeleteObservation {
        var observed = false
        var workoutIsNil = false
        var exercisesAreEmpty = false
        var setsAreEmpty = false
        var exerciseIdsOnScreen: [UUID] = []
        var setIdsOnScreen: [UUID] = []
    }

    private struct DeleteFailure: Error {}

    // MARK: Discard

    func testDiscardDropsScreenStateBeforeTheWorkoutIsDeleted() async throws {
        let harness = makeHarness()
        let seeded = seed(into: harness)

        let observation = MidDeleteObservation()
        harness.workoutService.onDeleteWorkout = { [viewModel = harness.viewModel] _ in
            observation.observed = true
            observation.workoutIsNil = viewModel.workout == nil
            observation.exercisesAreEmpty = viewModel.exercises.isEmpty
            observation.setsAreEmpty = viewModel.setsByExercise.isEmpty
        }

        await harness.viewModel.discardWorkout()

        XCTAssertTrue(observation.observed, "deleteWorkout was never reached")
        XCTAssertTrue(
            observation.workoutIsNil,
            "The sheet could still read a live Workout (title, id) while its row was being deleted"
        )
        XCTAssertTrue(observation.exercisesAreEmpty, "The tab strip could still read the exercises")
        XCTAssertTrue(
            observation.setsAreEmpty,
            "computeSummary() could still map sets whose rows are gone — this is the shipped crash"
        )
        XCTAssertEqual(harness.workoutService.deletedWorkoutIds, [seeded.workoutId])
        XCTAssertTrue(harness.viewModel.isWorkoutFinished)
    }

    func testAFailedDiscardPutsTheWorkoutBackOnScreen() async throws {
        let harness = makeHarness()
        let seeded = seed(into: harness)
        harness.workoutService.deleteWorkoutError = DeleteFailure()

        await harness.viewModel.discardWorkout()

        XCTAssertFalse(harness.viewModel.isWorkoutFinished, "A failed discard must not dismiss the screen")
        XCTAssertEqual(
            harness.viewModel.workout?.id,
            seeded.workoutId,
            "State is cleared before the delete, so a failure has to reload it from the store"
        )
        XCTAssertEqual(harness.viewModel.setsByExercise[seeded.exerciseId]?.count, 2)
        XCTAssertEqual(harness.viewModel.exercises.count, 2)
    }

    // MARK: Exercise removal

    func testRemovingAnExerciseTakesItOffScreenBeforeDeletingItsSets() async throws {
        let harness = makeHarness()
        let seeded = seed(into: harness)

        // The loop awaits once per set; the first call is the earliest observable point.
        let observation = MidDeleteObservation()
        harness.setService.onDelete = { [viewModel = harness.viewModel] _ in
            guard !observation.observed else { return }
            observation.observed = true
            observation.exerciseIdsOnScreen = viewModel.exercises.map(\.id)
            observation.setIdsOnScreen = viewModel.setsByExercise.values.flatMap { $0 }.map(\.id)
        }

        await harness.viewModel.removeExercise(at: 0)

        XCTAssertTrue(observation.observed, "no set was deleted")
        XCTAssertFalse(
            observation.exerciseIdsOnScreen.contains(seeded.exerciseId),
            "ExerciseTabStripView reads every exercise's sets on every render, including mid-loop"
        )
        XCTAssertTrue(
            Set(observation.setIdsOnScreen).isDisjoint(with: seeded.setIds),
            "The removed exercise's rows were still reachable while they were being deleted"
        )
        XCTAssertEqual(harness.setService.deletedSetIds.count, 2)
    }

    // MARK: Single set

    func testDeletingASetTakesItOffScreenBeforeTheServiceCall() async throws {
        let harness = makeHarness()
        let seeded = seed(into: harness)
        let target = try XCTUnwrap(harness.viewModel.setsByExercise[seeded.exerciseId]?.first)

        let observation = MidDeleteObservation()
        harness.setService.onDelete = { [viewModel = harness.viewModel] _ in
            observation.observed = true
            observation.setIdsOnScreen = viewModel.currentSets.map(\.id)
        }

        await harness.viewModel.deleteSet(target)

        XCTAssertTrue(observation.observed, "delete was never reached")
        XCTAssertFalse(
            observation.setIdsOnScreen.contains(target.id),
            "SetTableView could still render the row while its PR and stats pipeline ran"
        )
        XCTAssertEqual(observation.setIdsOnScreen.count, 1, "the surviving row should still be on screen")
    }

    // MARK: - Harness

    private struct Harness {
        let viewModel: ActiveWorkoutViewModel
        let workoutService: WorkoutServiceStub
        let setService: SetServiceStub
        let exerciseService: ExerciseServiceStub
    }

    private struct Seeded {
        let workoutId: UUID
        let exerciseId: UUID
        let setIds: Set<UUID>
    }

    private func makeHarness() -> Harness {
        let profile = HealthProfile()
        let workoutService = WorkoutServiceStub()
        let setService = SetServiceStub()
        let exerciseService = ExerciseServiceStub()
        let viewModel = ActiveWorkoutViewModel(
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService,
            statsService: StatsServiceStub(),
            prService: PRServiceStub(),
            healthProfileRepo: HealthProfileRepositoryStub(profile: profile),
            settingsService: SettingsServiceStub(profile: profile),
            loadPrescriptionService: LoadPrescriptionServiceSpy(),
            analyticsService: AnalyticsServiceSpy(),
            fatigueLearningService: makeStubFatigueLearningService()
        )
        return Harness(
            viewModel: viewModel,
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService
        )
    }

    /// Two exercises, two sets on the first and one on the second, in both the ViewModel and the
    /// stubs — the stub side is what the failure path reloads from.
    private func seed(into harness: Harness) -> Seeded {
        let workout = Workout(id: UUID(), date: Date(), status: .inProgress)
        let first = makeExercise(name: "Back Squat")
        let second = makeExercise(name: "Bench Press")

        let firstSets = [
            makeSet(workoutId: workout.id, exerciseId: first.id, order: 1),
            makeSet(workoutId: workout.id, exerciseId: first.id, order: 2)
        ]
        let secondSets = [makeSet(workoutId: workout.id, exerciseId: second.id, order: 3)]

        harness.workoutService.activeWorkout = workout
        harness.setService.workoutSets[workout.id] = firstSets + secondSets
        harness.exerciseService.fetchedExercises[first.id] = first
        harness.exerciseService.fetchedExercises[second.id] = second

        harness.viewModel.workout = workout
        harness.viewModel.exercises = [ChartExerciseData(from: first), ChartExerciseData(from: second)]
        harness.viewModel.setsByExercise = [first.id: firstSets, second.id: secondSets]
        harness.viewModel.selectedExerciseIndex = 0

        return Seeded(workoutId: workout.id, exerciseId: first.id, setIds: Set(firstSets.map(\.id)))
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

    private func makeSet(workoutId: UUID, exerciseId: UUID, order: Int) -> WorkoutSet {
        WorkoutSet(
            workoutId: workoutId,
            exerciseId: exerciseId,
            weight: 100,
            reps: 5,
            rir: 2.0,
            orderInWorkout: order,
            orderInExercise: order,
            completed: true
        )
    }
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
    func updatePrescriptionCapacityGuardsEnabled(_ enabled: Bool) async throws {}
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
    var targetOverrideUpdates: [(setId: UUID, min: Int?, max: Int?, clearsInheritedTarget: Bool)] = []
    var workoutSets: [UUID: [WorkoutSet]] = [:]
    var exerciseSets: [UUID: [WorkoutSet]] = [:]
    var fetchSetsForExerciseCallCount = 0
    /// One entry per `applyOrdering` call — reindexing must issue a single batch, not N.
    var orderingBatches: [[SetOrderUpdate]] = []
    /// Runs on the main actor *inside* `delete`, before it returns. The only way to observe what
    /// the screen still holds while a delete is in flight — which is where the row is already gone
    /// from the store but the ViewModel may still be handing it to a view body.
    var onDelete: (@MainActor (UUID) async -> Void)?
    /// When set, `delete` throws it after the gate runs, to drive the failure path.
    var deleteError: Error?

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

    /// Returns whatever `deleteAffectedSetIds` is primed with, so a test can drive the badge
    /// side of a deletion without a real `PRService`.
    var deleteAffectedSetIds: [UUID: CachedPRStatus?] = [:]

    /// Records creations and behaves like the real service: the new set lands in the stub's
    /// own store so later fetches see it.
    var createdSets: [WorkoutSet] = []

    /// Mirrors the real service: applies the typed values and completion stamps to the stored
    /// set, so ViewModel tests still observe a completed row after calling through.
    var completionInputs: [UUID: SetCompletionInput] = [:]

    var noteUpdates: [UUID: String?] = [:]
    var setTypeChanges: [UUID: SetType] = [:]

    private func storedSet(_ setId: UUID) -> WorkoutSet? {
        workoutSets.values.flatMap { $0 }.first { $0.id == setId }
    }

    private func emptyResult(_ setId: UUID) -> SetSaveResult {
        SetSaveResult(setId: setId, effectiveWeight: 0, prResult: .empty(for: setId))
    }

    func updateNote(setId: UUID, note: String?) async throws -> SetSaveResult {
        noteUpdates[setId] = note
        storedSet(setId)?.notes = note
        editedSetIds.append(setId)
        return emptyResult(setId)
    }

    func changeSetType(setId: UUID, to type: SetType) async throws -> SetSaveResult {
        setTypeChanges[setId] = type
        storedSet(setId)?.setType = type
        editedSetIds.append(setId)
        return emptyResult(setId)
    }

    /// Every `recordRestDuration` call, in order. A superset transition must produce `0` here —
    /// the absence of a call is the bug, not just a wrong value.
    var recordedRestDurations: [(setId: UUID, seconds: Int)] = []

    /// Canned partner names per workout, for history-chip tests.
    var supersetPartnersByWorkout: [UUID: [String]] = [:]

    func supersetPartnerNames(workoutIds: Set<UUID>, exerciseId: UUID) async throws -> [UUID: [String]] {
        supersetPartnersByWorkout.filter { workoutIds.contains($0.key) }
    }

    /// Every `applySupersetGroup` call, in order.
    var supersetGroupWrites: [(setIds: [UUID], groupId: UUID?)] = []

    func applySupersetGroup(setIds: [UUID], groupId: UUID?) async throws {
        supersetGroupWrites.append((setIds, groupId))
        for set in workoutSets.values.flatMap({ $0 }) where setIds.contains(set.id) {
            set.supersetGroupId = groupId
        }
    }

    func recordRestDuration(setId: UUID, seconds: Int) async throws {
        recordedRestDurations.append((setId, seconds))
        if let set = workoutSets.values.flatMap({ $0 }).first(where: { $0.id == setId }) {
            set.restDurationSeconds = seconds
        }
    }

    func save(setId: UUID, input: SetCompletionInput) async throws -> SetSaveResult {
        completionInputs[setId] = input
        let stored = workoutSets.values.flatMap { $0 }.first { $0.id == setId }
        if let set = stored {
            set.weight = input.weight
            set.durationSeconds = input.durationSeconds
            set.distanceMeters = input.distanceMeters
            set.leftReps = input.leftReps
            set.rightReps = input.rightReps
            set.leftRIR = input.leftRIR
            set.rightRIR = input.rightRIR
            set.reps = input.reps
            set.rir = input.rir
            set.completed = true
            set.completedAt = Date()
            set.updatedAt = Date()
        }
        return SetSaveResult(
            setId: setId,
            effectiveWeight: input.weight ?? 0,
            prResult: .empty(for: setId)
        )
    }

    func create(
        workoutId: UUID,
        exerciseId: UUID,
        date: Date,
        setType: SetType,
        orderInWorkout: Int,
        orderInExercise: Int,
        weight: Double?,
        reps: Int?,
        leftReps: Int?,
        rightReps: Int?,
        rir: Double?,
        leftRIR: Double?,
        rightRIR: Double?,
        supersetGroupId: UUID?
    ) async throws -> WorkoutSet {
        let set = WorkoutSet(
            workoutId: workoutId,
            exerciseId: exerciseId,
            date: date,
            weight: weight,
            reps: reps,
            leftReps: leftReps,
            rightReps: rightReps,
            rir: rir,
            leftRIR: leftRIR,
            rightRIR: rightRIR,
            setType: setType,
            orderInWorkout: orderInWorkout,
            orderInExercise: orderInExercise,
            supersetGroupId: supersetGroupId,
            completed: false
        )
        createdSets.append(set)
        workoutSets[workoutId, default: []].append(set)
        return set
    }

    func delete(_ set: WorkoutSet) async throws -> PREvaluationResult {
        deletedSetIds.append(set.id)
        await onDelete?(set.id)
        if let deleteError { throw deleteError }
        return PREvaluationResult(
            setId: set.id,
            newStatus: nil,
            affectedSetIds: deleteAffectedSetIds,
            prRecordChanged: false
        )
    }

    func updateInProgressTargetRepOverride(
        setId: UUID,
        min: Int?,
        max: Int?,
        clearsInheritedTarget: Bool
    ) async throws {
        targetOverrideUpdates.append((setId, min, max, clearsInheritedTarget))

        for sets in workoutSets.values {
            if let set = sets.first(where: { $0.id == setId }) {
                apply(min: min, max: max, clearsInheritedTarget: clearsInheritedTarget, to: set)
            }
        }

        for sets in exerciseSets.values {
            if let set = sets.first(where: { $0.id == setId }) {
                apply(min: min, max: max, clearsInheritedTarget: clearsInheritedTarget, to: set)
            }
        }
    }

    private func apply(min: Int?, max: Int?, clearsInheritedTarget: Bool, to set: WorkoutSet) {
        set.overrideTargetRepMin = min
        set.overrideTargetRepMax = max
        if clearsInheritedTarget {
            set.targetRepMin = nil
            set.targetRepMax = nil
        }
    }

    func fetchSets(for workoutId: UUID) async throws -> [WorkoutSet] {
        workoutSets[workoutId] ?? []
    }

    func fetchSetSnapshots(for workoutId: UUID) async throws -> [ChartSetData] {
        (workoutSets[workoutId] ?? []).map(ChartSetData.init(from:))
    }

    func applyOrdering(_ updates: [SetOrderUpdate]) async throws {
        orderingBatches.append(updates)
        for update in updates {
            guard let set = workoutSets.values.flatMap({ $0 }).first(where: { $0.id == update.setId })
            else { continue }
            if let orderInExercise = update.orderInExercise { set.orderInExercise = orderInExercise }
            if let orderInWorkout = update.orderInWorkout { set.orderInWorkout = orderInWorkout }
        }
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

    /// Shares `fetchSets(for:limit:)`'s bookkeeping deliberately: the two differ only in the
    /// type they hand back, so a test asserting on `fetchSetsForExerciseCallCount` keeps
    /// counting the same fetches after a caller moves to the snapshot variant.
    func fetchSetSnapshots(for exerciseId: UUID, limit: Int?) async throws -> [ChartSetData] {
        try await fetchSets(for: exerciseId, limit: limit).map(ChartSetData.init(from:))
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
    var deletedWorkoutIds: [UUID] = []
    /// Runs on the main actor *inside* `deleteWorkout`. See `SetServiceStub.onDelete`.
    var onDeleteWorkout: (@MainActor (UUID) async -> Void)?
    /// When set, `deleteWorkout` throws it after the gate runs, to drive the failure path.
    var deleteWorkoutError: Error?
    /// Workout ids the stub reports as excluded from progression history, so the in-workout
    /// History sub-tab can be driven without a real store.
    var excludedProgressionWorkoutIds: Set<UUID> = []
    /// Arguments the last `excludedWorkoutIdsForProgressionHistory` call received.
    var lastProgressionExclusionQuery: (workoutIds: Set<UUID>, exerciseId: UUID)?

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
    func getActiveWorkoutSummary() async throws -> WorkoutSnapshot? {
        activeWorkout.map(WorkoutSnapshot.init(from:))
    }
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
    func fetchWorkoutSummary(_ workoutId: UUID) async throws -> WorkoutSnapshot? {
        let _ = workoutId
        return nil
    }
    func fetchWorkoutSummaries(for dateRange: ClosedRange<Date>) async throws -> [WorkoutSnapshot] {
        let _ = dateRange
        return []
    }
    func fetchAllWorkoutSummaries(limit: Int?, offset: Int?) async throws -> [WorkoutSnapshot] {
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
    func excludedWorkoutIdsForProgressionHistory(
        workoutIds: Set<UUID>,
        exerciseId: UUID
    ) async throws -> Set<UUID> {
        lastProgressionExclusionQuery = (workoutIds, exerciseId)
        return excludedProgressionWorkoutIds.intersection(workoutIds)
    }
    func deleteWorkout(_ workoutId: UUID) async throws {
        deletedWorkoutIds.append(workoutId)
        await onDeleteWorkout?(workoutId)
        if let deleteWorkoutError { throw deleteWorkoutError }
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
    var createdExerciseFields: [ExerciseEditableFields] = []
    var updatedExerciseFields: [(id: UUID, fields: ExerciseEditableFields)] = []
    var fetchedExercises: [UUID: Exercise] = [:]
    var hasSets = false
    var hasLoggedSetData = false

    @discardableResult
    func createExercise(fields: ExerciseEditableFields) async throws -> UUID {
        createdExerciseFields.append(fields)
        return UUID()
    }
    func updateExercise(id: UUID, fields: ExerciseEditableFields) async throws {
        updatedExerciseFields.append((id, fields))
    }
    func fetchExercise(_ exerciseId: UUID) async throws -> Exercise? {
        fetchedExercises[exerciseId]
    }
    func fetchExerciseSnapshot(_ exerciseId: UUID) async throws -> ChartExerciseData? {
        fetchedExercises[exerciseId].map(ChartExerciseData.init(from:))
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
    var rebuiltExerciseIds: [UUID] = []

    func updateStats(for exerciseId: UUID, event: StatsUpdateEvent) async throws {
        let _ = exerciseId
        let _ = event
    }
    func rebuildAll() async throws {}
    func rebuild(for exerciseId: UUID) async throws { rebuiltExerciseIds.append(exerciseId) }
    func fetchStats(for exerciseId: UUID) async throws -> ExerciseStats? {
        let _ = exerciseId
        return nil
    }
    func fetchStatsSnapshot(for exerciseId: UUID) async throws -> ChartExerciseStatsData? {
        let _ = exerciseId
        return nil
    }
    func fetchAllStats() async throws -> [UUID: ExerciseStats] { [:] }
    func fetchRecentPRs(since: Date, limit: Int, scope: RecentPRScope) async throws -> [PerformanceRecordSummaryData] {
        let _ = since
        let _ = limit
        let _ = scope
        return []
    }
}

private final class PRServiceStub: @unchecked Sendable, PRServiceProtocol {
    var rebuiltExerciseIds: [UUID] = []

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
    func rebuild(for exerciseId: UUID) async throws { rebuiltExerciseIds.append(exerciseId) }
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
    func fetchChartExercise(byId id: UUID) async throws -> ChartExerciseData? {
        let _ = id
        return nil
    }
    func fetchMetadataSnapshot(byId id: UUID) async throws -> ExerciseMetadataSnapshot? {
        let _ = id
        return nil
    }
    func applyEdit(id: UUID, fields: ExerciseEditableFields) async throws {
        let _ = id
        let _ = fields
    }
    func create(fields: ExerciseEditableFields) async throws -> UUID {
        let _ = fields
        return UUID()
    }
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
    func fetchWorkoutSummary(byId id: UUID) async throws -> WorkoutSnapshot? {
        let _ = id
        return nil
    }
    func fetchInProgressSummary() async throws -> WorkoutSnapshot? { nil }
    func fetchWorkoutSummaries(for dateRange: ClosedRange<Date>) async throws -> [WorkoutSnapshot] {
        let _ = dateRange
        return []
    }
    func fetchAllWorkoutSummaries(limit: Int?, offset: Int?) async throws -> [WorkoutSnapshot] {
        let _ = limit
        let _ = offset
        return []
    }
    func setHealthKitUUID(_ uuid: UUID, forWorkoutId id: UUID) async throws {
        let _ = uuid
        let _ = id
    }
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

    func testStaleRecentPerformanceSourceDoesNotUseFirstSetBias() {
        // First-set progression bias should only fire when the base e1RM is from
        // in-window recent performance. Out-of-window (stale) data is anchored on
        // an old workout and shouldn't be pushed above the (stale) peak.
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
            baseSource: .staleRecentPerformance,
            baseSourceWorkoutDate: Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()),
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
        XCTAssertEqual(decision.e1RMSource, .staleRecentPerformance)
        XCTAssertNotNil(decision.e1RMSourceWorkoutDate)
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

    func testSessionCapabilityIgnoresHighRIRSets() {
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
        // RIR 4 set is weak capability evidence (gated at RIR ≥ 3), so sessionCapabilityE1RM
        // stays at the historical baseE1RM of 50.67 instead of moving to the observed 56.0.
        XCTAssertEqual(decision.sessionCapabilityE1RM, 50.67, accuracy: 0.001)
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

private struct ExerciseRebuildServiceContext {
    let service: ExerciseService
    let exerciseRepo: ExerciseRepository
    let setRepo: SetRepository
    let templateRepo: TemplateRepository
    let prService: PRServiceStub
    let statsService: StatsServiceStub
}

/// Like `makeExerciseTrackingTypeServiceContext`, but with stubbed PR/stats
/// services so tests can observe whether a rebuild was actually requested.
private func makeExerciseRebuildServiceContext() throws -> ExerciseRebuildServiceContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Exercise.self,
        WorkoutSet.self,
        ExerciseStats.self,
        PerformanceRecord.self,
        HealthProfile.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateSet.self,
        configurations: configuration
    )

    let exerciseRepo = ExerciseRepository(modelContainer: container)
    let setRepo = SetRepository(modelContainer: container)
    let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
    let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
    let templateRepo = TemplateRepository(modelContainer: container)
    let prService = PRServiceStub()
    let statsService = StatsServiceStub()
    let service = ExerciseService(
        exerciseRepository: exerciseRepo,
        setRepository: setRepo,
        exerciseStatsRepository: exerciseStatsRepo,
        performanceRecordRepository: performanceRecordRepo,
        templateRepository: templateRepo,
        prService: prService,
        statsService: statsService,
        fatigueLearningService: makeStubFatigueLearningService()
    )

    return ExerciseRebuildServiceContext(
        service: service,
        exerciseRepo: exerciseRepo,
        setRepo: setRepo,
        templateRepo: templateRepo,
        prService: prService,
        statsService: statsService
    )
}

private func makeExerciseTrackingTypeServiceContext() throws -> ExerciseTrackingTypeServiceContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Exercise.self,
        WorkoutSet.self,
        ExerciseStats.self,
        PerformanceRecord.self,
        HealthProfile.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateSet.self,
        configurations: configuration
    )

    let exerciseRepo = ExerciseRepository(modelContainer: container)
    let setRepo = SetRepository(modelContainer: container)
    let workoutRepo = WorkoutRepository(modelContainer: container)
    let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
    let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
    let healthProfileRepo = HealthProfileRepository(modelContainer: container)
    let templateRepo = TemplateRepository(modelContainer: container)
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
        templateRepository: templateRepo,
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

/// Stands in for `ActiveWorkoutViewModel` in the coordinator's presentation tests.
@MainActor
private final class StubForegroundAlerter: RestTimerForegroundAlerting {
    let willAlertRestTimerInApp: Bool
    init(willAlert: Bool) { self.willAlertRestTimerInApp = willAlert }
}
