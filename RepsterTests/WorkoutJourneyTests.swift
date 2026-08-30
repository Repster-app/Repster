import XCTest
import SwiftData
@testable import Repster

/// Journey tests — the real stack, entered where the view enters it.
///
/// Every other test in this suite enters below the level where the 2026-08-12 defects lived:
/// repository tests call the repository directly and cannot see what the *caller* did first;
/// ViewModel tests use `SetServiceStub`, which always "saves". Both defects (a reindex that was
/// never committed, an exercise snapshot that never refreshed) were invisible at those seams
/// while 391 tests stayed green.
///
/// So these drive `ActiveWorkoutViewModel` exactly as `SetTableView` does, with **real**
/// services and **real** repositories over a real `ModelContainer`. Only HealthKit, analytics
/// and access control are stubbed — none of them touch workout data.
///
/// Each journey asserts up to three things after a user action:
///
///  1. **What the view sees** — `currentSets`, ordering, badges.
///  2. **What was committed** — read through a *separate* `ModelContext`, which cannot see
///     another context's pending changes. This is what proves a write reached the store.
///  3. **What survives a relaunch** — a brand-new ViewModel over the same container, loading
///     from scratch. This is the cheap stand-in for quitting and reopening the app, and it is
///     what would have caught the ordering defect on its own.
///
/// See STEP5_SCOPE_AND_TEST_STRATEGY.md §4.3. These must pass *before* the step 5 conversion
/// and unchanged *after* it — that is what makes them a regression net rather than a
/// description of whatever the new code happens to do.
@MainActor
final class WorkoutJourneyTests: XCTestCase {

    // MARK: - Harness

    /// The real object graph, built once per journey over one in-memory store.
    private final class Stack {
        let container: ModelContainer
        let exerciseRepo: ExerciseRepository
        let workoutRepo: WorkoutRepository
        let setRepo: SetRepository
        let bodyweightRepo: BodyweightEntryRepository
        let healthProfileRepo: HealthProfileRepository
        let setService: SetService
        let workoutService: WorkoutService
        let exerciseService: ExerciseService
        let statsService: StatsService
        let prService: PRService
        let settingsService: SettingsService
        let loadPrescriptionService: LoadPrescriptionService
        let fatigueLearningService: FatigueLearningService
        let chartDataService: ChartDataService

        init() throws {
            container = try ModelContainer(
                for: Exercise.self, Workout.self, WorkoutSet.self, ExerciseStats.self,
                PerformanceRecord.self, BodyweightEntry.self, HealthProfile.self,
                FatigueObservation.self, FatigueLearningSetAudit.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )

            exerciseRepo = ExerciseRepository(modelContainer: container)
            workoutRepo = WorkoutRepository(modelContainer: container)
            setRepo = SetRepository(modelContainer: container)
            bodyweightRepo = BodyweightEntryRepository(modelContainer: container)
            healthProfileRepo = HealthProfileRepository(modelContainer: container)

            let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
            let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
            let fatigueObservationRepo = FatigueObservationRepository(modelContainer: container)
            let fatigueLearningAuditRepo = FatigueLearningSetAuditRepository(modelContainer: container)

            statsService = StatsService(
                exerciseStatsRepository: exerciseStatsRepo,
                setRepository: setRepo,
                exerciseRepository: exerciseRepo,
                healthProfileRepository: healthProfileRepo,
                performanceRecordRepository: performanceRecordRepo
            )
            prService = PRService(
                performanceRecordRepository: performanceRecordRepo,
                setRepository: setRepo,
                workoutRepository: workoutRepo,
                healthProfileRepository: healthProfileRepo,
                exerciseRepository: exerciseRepo
            )
            fatigueLearningService = FatigueLearningService(
                observationRepo: fatigueObservationRepo,
                exerciseRepo: exerciseRepo,
                healthProfileRepo: healthProfileRepo,
                auditRepo: fatigueLearningAuditRepo
            )
            setService = SetService(
                setRepository: setRepo,
                exerciseRepository: exerciseRepo,
                bodyweightEntryRepository: bodyweightRepo,
                healthProfileRepository: healthProfileRepo,
                prService: prService,
                statsService: statsService,
                fatigueLearningService: fatigueLearningService
            )
            exerciseService = ExerciseService(
                exerciseRepository: exerciseRepo,
                setRepository: setRepo,
                exerciseStatsRepository: exerciseStatsRepo,
                performanceRecordRepository: performanceRecordRepo,
                prService: prService,
                statsService: statsService,
                fatigueLearningService: fatigueLearningService
            )
            workoutService = WorkoutService(
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
            loadPrescriptionService = LoadPrescriptionService(
                setRepository: setRepo,
                exerciseRepository: exerciseRepo,
                workoutRepository: workoutRepo,
                healthProfileRepository: healthProfileRepo
            )
            chartDataService = ChartDataService(
                setRepository: setRepo,
                workoutRepository: workoutRepo,
                exerciseRepository: exerciseRepo,
                exerciseStatsRepository: exerciseStatsRepo,
                performanceRecordRepository: performanceRecordRepo
            )
            settingsService = SettingsService(
                healthProfileRepository: healthProfileRepo,
                prService: prService,
                statsService: statsService,
                modelContainer: container,
                userDefaults: UserDefaults(suiteName: "journey-\(UUID().uuidString)")!,
                // The seeded library is 170+ exercises of noise for these tests.
                seedExercises: { _ in }
            )
        }

        /// A brand-new ViewModel over the same store.
        ///
        /// Used both for the first load and, mid-journey, as a stand-in for quitting and
        /// reopening the app: it shares nothing with the previous instance except the store,
        /// so anything it reads back had to have been committed.
        @MainActor
        func makeViewModel() -> ActiveWorkoutViewModel {
            ActiveWorkoutViewModel(
                workoutService: workoutService,
                setService: setService,
                exerciseService: exerciseService,
                statsService: statsService,
                prService: prService,
                healthProfileRepo: healthProfileRepo,
                settingsService: settingsService,
                loadPrescriptionService: loadPrescriptionService,
                fatigueLearningService: fatigueLearningService
            )
        }

        /// The Home screen over the same store — for journeys that cross screens.
        @MainActor
        func makeHomeViewModel() -> HomeViewModel {
            HomeViewModel(
                workoutService: workoutService,
                setService: setService,
                exerciseService: exerciseService,
                chartDataService: chartDataService,
                statsService: statsService
            )
        }

        /// The edit screen for a finished workout.
        @MainActor
        func makeEditViewModel(workoutId: UUID) -> EditWorkoutViewModel {
            EditWorkoutViewModel(
                workoutId: workoutId,
                workoutService: workoutService,
                setService: setService,
                exerciseService: exerciseService,
                statsService: statsService,
                settingsService: settingsService
            )
        }

        /// Reads through a separate `ModelContext` — sees only committed data, never another
        /// context's pending changes.
        func committedSets(for workoutId: UUID) throws -> [WorkoutSet] {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<WorkoutSet>(
                predicate: #Predicate { $0.workoutId == workoutId },
                sortBy: [SortDescriptor(\.orderInExercise)]
            )
            return try context.fetch(descriptor)
        }

        func committedStats(for exerciseId: UUID) throws -> ExerciseStats? {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ExerciseStats>(
                predicate: #Predicate { $0.exerciseId == exerciseId }
            )
            return try context.fetch(descriptor).first
        }

        func committedRecordCount() throws -> Int {
            let context = ModelContext(container)
            return try context.fetch(FetchDescriptor<PerformanceRecord>()).count
        }
    }

    // MARK: - Fixtures
    //
    // Deliberately non-default in every field a screen renders. All five misses in the
    // 2026-08-12 mutation sweep were cases the fixtures did not contain, not logic errors —
    // so these carry a bodyweight-style exercise (where `effectiveWeight != weight`), a
    // unilateral exercise that resolves through the name-based rep-target fallback, and a
    // non-rep-PR tracking type.

    private enum Fixture {
        static func barbell() -> Exercise {
            Exercise(
                name: "Flat Barbell Bench Press",
                equipmentType: .barbell,
                trackingType: .weightReps,
                primaryMuscle: "chest",
                weightIncrement: 2.5,
                defaultRestTime: 90
            )
        }

        /// `bodyweightFactor > 0`, so `effectiveWeight = weight + bodyweight` and the two
        /// genuinely differ — the case every previous fixture was missing.
        static func bodyweightStyle() -> Exercise {
            Exercise(
                name: "Pull Up",
                equipmentType: .bodyweight,
                trackingType: .weightReps,
                primaryMuscle: "back",
                bodyweightFactor: 1.0,
                weightIncrement: 2.5,
                defaultRestTime: 120
            )
        }

        /// The one exercise whose rep-target mode comes from the name-based fallback.
        static func unilateral() -> Exercise {
            Exercise(
                name: "Dumbbell Lunge",
                equipmentType: .dumbbell,
                trackingType: .weightReps,
                primaryMuscle: "legs",
                unilateral: true,
                weightIncrement: 2.0,
                defaultRestTime: 60
            )
        }
    }

    /// Start a workout and load it, exactly as the screen does on appear.
    private func startWorkout(
        _ stack: Stack,
        with exercises: [Exercise]
    ) async throws -> ActiveWorkoutViewModel {
        for exercise in exercises {
            try await stack.exerciseRepo.save(exercise)
        }
        _ = try await stack.workoutService.startWorkout()

        let viewModel = stack.makeViewModel()
        await viewModel.loadActiveWorkout()
        await viewModel.addExercises(exercises.map(\.id))
        return viewModel
    }

    /// The invariant every journey depends on: **what the table shows equals what is stored.**
    ///
    /// Reads the store through a separate context, so anything the ViewModel is showing that
    /// was never committed shows up as a mismatch. This is the general form of the 2026-08-12
    /// ordering defect — the screen said `[1, 2, 3]` while the store said `[1, 1, 2]`.
    ///
    /// It is also the assertion that will discriminate a broken `applyAffectedSets` after
    /// step 5: today PR demotions reach the screen either way, because `PRService` mutates
    /// the very object the ViewModel holds (`PRService.swift:113`). Once sets are value types
    /// that shared-instance path is gone, and a missed badge update becomes a divergence
    /// between screen and store — which is precisely what this catches.
    private func assertScreenMatchesStore(
        _ viewModel: ActiveWorkoutViewModel,
        _ stack: Stack,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let workoutId = try XCTUnwrap(viewModel.workout?.id, file: file, line: line)
        let stored = Dictionary(
            uniqueKeysWithValues: try stack.committedSets(for: workoutId).map { ($0.id, $0) }
        )

        for shown in viewModel.setsByExercise.values.flatMap({ $0 }) {
            guard let row = stored[shown.id] else {
                XCTFail("set \(shown.id) is on screen but not in the store", file: file, line: line)
                continue
            }
            XCTAssertEqual(shown.completed, row.completed, "completed differs from the store", file: file, line: line)
            XCTAssertEqual(shown.weight, row.weight, "weight differs from the store", file: file, line: line)
            XCTAssertEqual(shown.effectiveWeight, row.effectiveWeight, "effectiveWeight differs from the store", file: file, line: line)
            XCTAssertEqual(shown.reps, row.reps, "reps differs from the store", file: file, line: line)
            XCTAssertEqual(shown.prStatus, row.prStatus, "PR badge differs from the store", file: file, line: line)
            XCTAssertEqual(shown.setType, row.setType, "set type differs from the store", file: file, line: line)
            XCTAssertEqual(shown.orderInExercise, row.orderInExercise, "orderInExercise differs from the store", file: file, line: line)
            XCTAssertEqual(shown.orderInWorkout, row.orderInWorkout, "orderInWorkout differs from the store", file: file, line: line)
        }

        XCTAssertEqual(
            viewModel.setsByExercise.values.flatMap({ $0 }).count,
            stored.count,
            "the screen and the store disagree on how many sets exist",
            file: file,
            line: line
        )
    }

    /// Complete the first pending set of the current exercise with the given values.
    private func completeNextSet(
        _ viewModel: ActiveWorkoutViewModel,
        weight: Double,
        reps: Int,
        rir: Double? = nil
    ) async throws {
        let pending = try XCTUnwrap(
            viewModel.currentSets.first(where: { !$0.completed }),
            "no pending set to complete"
        )
        await viewModel.completeSet(
            pending,
            input: SetCompletionInput(weight: weight, reps: reps, rir: rir)
        )
    }

    // MARK: - Journey: logging sets

    /// Log three sets, then relaunch. The core path, and the one every other journey builds on.
    func testLoggingThreeSetsPersistsAndSurvivesRelaunch() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        try await completeNextSet(viewModel, weight: 100, reps: 5)
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 102.5, reps: 5)
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 105, reps: 3)

        // 1. What the view sees.
        XCTAssertEqual(viewModel.currentSets.count, 3)
        XCTAssertEqual(viewModel.currentSets.map(\.completed), [true, true, true])
        XCTAssertEqual(viewModel.currentSets.compactMap(\.weight), [100, 102.5, 105])
        XCTAssertEqual(viewModel.currentSets.compactMap(\.reps), [5, 5, 3])

        // 2. What was committed.
        let committed = try stack.committedSets(for: workoutId)
        XCTAssertEqual(committed.count, 3)
        XCTAssertEqual(committed.compactMap(\.weight), [100, 102.5, 105])
        XCTAssertEqual(
            committed.compactMap(\.effectiveWeight),
            [100, 102.5, 105],
            "a non-bodyweight exercise has effectiveWeight == weight"
        )

        try assertScreenMatchesStore(viewModel, stack)

        // 3. What survives a relaunch.
        let relaunched = stack.makeViewModel()
        await relaunched.loadActiveWorkout()
        XCTAssertEqual(relaunched.currentSets.count, 3)
        XCTAssertEqual(relaunched.currentSets.compactMap(\.weight), [100, 102.5, 105])
        XCTAssertEqual(relaunched.currentSets.map(\.orderInExercise), [1, 2, 3])
    }

    // MARK: - Journey: ordering

    /// A warmup set inserted mid-exercise goes to the top **and stays there** across a relaunch.
    ///
    /// The relaunch half is the part that matters: on 2026-08-12 the reindex updated the
    /// ViewModel but was never committed, because the repository compared against values the
    /// caller had already applied. In-memory assertions alone all passed.
    func testWarmupSetIsPlacedFirstAndTheReindexSurvivesRelaunch() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        try await completeNextSet(viewModel, weight: 100, reps: 5)
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 100, reps: 5)

        await viewModel.addWarmupSet(for: exercise.id)

        // 1. The warmup is first on screen.
        XCTAssertEqual(viewModel.currentSets.map(\.setType), [.warmup, .working, .working])
        XCTAssertEqual(viewModel.currentSets.map(\.orderInExercise), [1, 2, 3])

        // 2. The reindex was committed, not left pending.
        let committed = try stack.committedSets(for: workoutId)
        XCTAssertEqual(
            committed.map(\.setType),
            [.warmup, .working, .working],
            "the reindex must reach the store, not sit in the repository's context"
        )
        XCTAssertEqual(committed.map(\.orderInExercise), [1, 2, 3])

        try assertScreenMatchesStore(viewModel, stack)

        // 3. And it is what the user gets back.
        let relaunched = stack.makeViewModel()
        await relaunched.loadActiveWorkout()
        XCTAssertEqual(relaunched.currentSets.map(\.setType), [.warmup, .working, .working])
        XCTAssertEqual(relaunched.currentSets.map(\.orderInExercise), [1, 2, 3])
    }

    /// Deleting a middle set closes the gap, and the renumbering is committed.
    func testDeletingAMiddleSetClosesTheOrderGapAndSurvivesRelaunch() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        try await completeNextSet(viewModel, weight: 100, reps: 5)
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 110, reps: 5)
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 120, reps: 5)

        let middle = viewModel.currentSets[1]
        await viewModel.deleteSet(middle)

        XCTAssertEqual(viewModel.currentSets.compactMap(\.weight), [100, 120])
        XCTAssertEqual(viewModel.currentSets.map(\.orderInExercise), [1, 2])

        let committed = try stack.committedSets(for: workoutId)
        XCTAssertEqual(committed.count, 2)
        XCTAssertEqual(committed.compactMap(\.weight), [100, 120])
        XCTAssertEqual(committed.map(\.orderInExercise), [1, 2], "orders must close the gap in the store")
        try assertScreenMatchesStore(viewModel, stack)

        let relaunched = stack.makeViewModel()
        await relaunched.loadActiveWorkout()
        XCTAssertEqual(relaunched.currentSets.compactMap(\.weight), [100, 120])
        XCTAssertEqual(relaunched.currentSets.map(\.orderInExercise), [1, 2])
    }

    // MARK: - Exercise ordering (EXERCISE_REPLACE_AND_REORDER_DESIGN.md §1, §2, §3)
    //
    // There was no journey test for reorder at all until 2026-08-29, which is why both of its
    // defects shipped: the ViewModel tests use `SetServiceStub`, which always "saves", and the
    // damage from a bad reorder is invisible on screen by construction — the strip renders the
    // in-memory array, so the store and the screen only have to agree once the array is rebuilt.

    /// The exercise order the strip will show after a rebuild: exercises sorted by the lowest
    /// `orderInWorkout` among their sets, which is exactly `loadActiveWorkout`'s sort key.
    private func committedExerciseOrder(_ stack: Stack, workoutId: UUID) throws -> [UUID] {
        let sets = try stack.committedSets(for: workoutId)
        return Dictionary(grouping: sets, by: \.exerciseId)
            .mapValues { $0.map(\.orderInWorkout).min() ?? Int.max }
            .sorted { $0.value < $1.value }
            .map(\.key)
    }

    /// `reorderExercises` renumbers synchronously but persists in an unawaited `Task`, so the
    /// screen leads the store by a beat. Poll rather than sleep — neither flaky nor slow.
    private func waitForCommittedExerciseOrder(
        _ stack: Stack,
        workoutId: UUID,
        equals expected: [UUID],
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last: [UUID] = []
        while Date() < deadline {
            last = try committedExerciseOrder(stack, workoutId: workoutId)
            if last == expected { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail(
            "ordering never committed. expected \(expected), store has \(last)",
            file: file,
            line: line
        )
    }

    /// What the strip shows must equal what a rebuild would show. This is the §1.1 invariant in
    /// its user-facing form, and the single assertion that would have caught both defects.
    private func assertStripOrderMatchesStore(
        _ viewModel: ActiveWorkoutViewModel,
        _ stack: Stack,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let workoutId = try XCTUnwrap(viewModel.workout?.id, file: file, line: line)
        XCTAssertEqual(
            try committedExerciseOrder(stack, workoutId: workoutId),
            viewModel.exercises.map(\.id),
            "the strip and the store disagree — the order will change on the next rebuild",
            file: file,
            line: line
        )
    }

    /// The headline ordering journey. A reorder that renumbers only in memory looks perfect until
    /// the array is rebuilt from the store — which is a back-tap and a resume away, not a relaunch
    /// away (§1.2). Building a fresh ViewModel over the same container is exactly that round trip.
    func testReorderingExercisesSurvivesResume() async throws {
        let stack = try Stack()
        let a = Fixture.barbell()
        let b = Fixture.bodyweightStyle()
        let c = Fixture.unilateral()
        let viewModel = try await startWorkout(stack, with: [a, b, c])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        XCTAssertEqual(viewModel.exercises.map(\.id), [a.id, b.id, c.id], "precondition")

        // Walk the last exercise to the front — what Move Left does, twice over.
        viewModel.reorderExercises(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(viewModel.exercises.map(\.id), [c.id, a.id, b.id], "screen updates at once")

        try await waitForCommittedExerciseOrder(stack, workoutId: workoutId, equals: [c.id, a.id, b.id])
        try assertStripOrderMatchesStore(viewModel, stack)

        let resumed = stack.makeViewModel()
        await resumed.loadActiveWorkout()
        XCTAssertEqual(
            resumed.exercises.map(\.id),
            [c.id, a.id, b.id],
            "order must survive backing out of the workout and resuming it"
        )
    }

    /// Defect B as a journey. Moving an exercise the user never touched, past the one they are
    /// working on, used to shift the array underneath a fixed index and swap the set table to a
    /// different exercise mid-set — taking their logged rows off screen with it.
    func testReorderingAnEarlierExerciseKeepsTheUserOnTheirCurrentSet() async throws {
        let stack = try Stack()
        let a = Fixture.barbell()
        let b = Fixture.bodyweightStyle()
        let c = Fixture.unilateral()
        let viewModel = try await startWorkout(stack, with: [a, b, c])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        // The user is on the first exercise and has logged a set there.
        viewModel.selectedExerciseIndex = 0
        try await completeNextSet(viewModel, weight: 100, reps: 5)
        XCTAssertEqual(viewModel.currentExercise?.id, a.id, "precondition")

        // They now move the *last* exercise to the front. They never touched the one they are on.
        viewModel.reorderExercises(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(
            viewModel.currentExercise?.id,
            a.id,
            "the user must stay on the exercise they were logging"
        )
        XCTAssertEqual(viewModel.selectedExerciseIndex, 1, "index re-derived from identity")
        XCTAssertEqual(
            viewModel.currentSets.compactMap(\.weight),
            [100],
            "their logged set must still be the one on screen"
        )

        try await waitForCommittedExerciseOrder(stack, workoutId: workoutId, equals: [c.id, a.id, b.id])

        // And the resume lands them back on the same exercise, because selection persists by ID.
        let resumed = stack.makeViewModel()
        await resumed.loadActiveWorkout()
        XCTAssertEqual(resumed.currentExercise?.id, a.id, "persisted selection must agree with the screen")
    }

    /// The §8 migration risk. Reorder used to run the full `SetService.edit` pipeline per set,
    /// which re-evaluated PRs; it now writes ordering only. `SetRepository.applyOrdering`'s doc
    /// comment argues that pipeline was a no-op with unchanged values — but "documented as a
    /// no-op" is exactly what `PRBadgeApplier` said about a rule that turned out never to fire,
    /// so this pins the badges rather than trusting the argument.
    func testReorderingDoesNotDisturbPRBadges() async throws {
        let stack = try Stack()
        let a = Fixture.barbell()
        let b = Fixture.unilateral()
        let viewModel = try await startWorkout(stack, with: [a, b])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        // Log real work on both, including a heavier second set so at least one badge moves.
        viewModel.selectedExerciseIndex = 0
        try await completeNextSet(viewModel, weight: 100, reps: 5)
        await viewModel.addSet(for: a.id)
        try await completeNextSet(viewModel, weight: 120, reps: 5)

        viewModel.selectedExerciseIndex = 1
        try await completeNextSet(viewModel, weight: 40, reps: 10)

        let before = try stack.committedSets(for: workoutId)
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { ($0.id, $0.prStatus) }
        XCTAssertTrue(
            before.contains { $0.1 != nil },
            "fixture must actually produce a badge, or this test proves nothing"
        )

        viewModel.reorderExercises(from: IndexSet(integer: 1), to: 0)
        try await waitForCommittedExerciseOrder(stack, workoutId: workoutId, equals: [b.id, a.id])

        let after = try stack.committedSets(for: workoutId)
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { ($0.id, $0.prStatus) }

        XCTAssertEqual(before.map(\.0), after.map(\.0), "no set may appear or vanish")
        XCTAssertEqual(
            before.map(\.1),
            after.map(\.1),
            "reordering must not re-evaluate PRs"
        )
        XCTAssertEqual(try stack.committedRecordCount(), 2, "no PerformanceRecord churn")
    }

    /// The §1.1 invariant across the whole strip API, in one journey. Only two operations can
    /// break it — moving an exercise, and introducing one whose sets are all at the global tail —
    /// but the cheapest guard against a future mutation site forgetting is to drive them all and
    /// assert screen-equals-store after each.
    func testOrderingInvariantHoldsAfterEveryStripMutation() async throws {
        let stack = try Stack()
        let a = Fixture.barbell()
        let b = Fixture.bodyweightStyle()
        let c = Fixture.unilateral()

        let viewModel = try await startWorkout(stack, with: [a, b])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)
        try assertStripOrderMatchesStore(viewModel, stack)

        // add
        try await stack.exerciseRepo.save(c)
        await viewModel.addExercises([c.id])
        XCTAssertEqual(viewModel.exercises.map(\.id), [a.id, b.id, c.id])
        try assertStripOrderMatchesStore(viewModel, stack)

        // reorder
        viewModel.reorderExercises(from: IndexSet(integer: 2), to: 0)
        try await waitForCommittedExerciseOrder(stack, workoutId: workoutId, equals: [c.id, a.id, b.id])
        try assertStripOrderMatchesStore(viewModel, stack)

        // replace — the only operation that introduces an exercise at a non-tail position whose
        // whole set list is at the global tail, i.e. the second of the two §1.1 breakers
        let d = Exercise(
            name: "Cable Fly",
            equipmentType: .cable,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            weightIncrement: 2.5,
            defaultRestTime: 60
        )
        try await stack.exerciseRepo.save(d)
        await viewModel.replaceExercise(at: 1, with: d.id)
        XCTAssertEqual(viewModel.exercises.map(\.id), [c.id, d.id, b.id])
        try assertStripOrderMatchesStore(viewModel, stack)

        // remove — deliberately one *before* the selection, the case that used to move the user
        viewModel.selectedExerciseIndex = 1
        await viewModel.removeExercise(at: 0)
        XCTAssertEqual(viewModel.exercises.map(\.id), [d.id, b.id])
        XCTAssertEqual(viewModel.currentExercise?.id, d.id, "selection follows the exercise")
        try assertStripOrderMatchesStore(viewModel, stack)

        // Removal leaves gaps in `orderInWorkout` and that is fine — the invariant is about the
        // *relative* order of each exercise's minimum, not contiguity. The resume proves it.
        let resumed = stack.makeViewModel()
        await resumed.loadActiveWorkout()
        XCTAssertEqual(resumed.exercises.map(\.id), [d.id, b.id])
        _ = a
    }

    /// The §8 headline risk, and the reason replace needed a journey test rather than a unit test.
    ///
    /// `addSet` seeds at the **global tail**, so the replacement's only set has the highest
    /// `orderInWorkout` in the workout while sitting mid-array. Order is reconstructed from
    /// `MIN(orderInWorkout)` per exercise, so a replace that skips the reindex renders perfectly and
    /// then jumps to the end of the strip the next time the array is rebuilt. A ViewModel test
    /// cannot see this — `SetServiceStub` always "saves".
    func testReplacingAMiddleExerciseKeepsItsPositionAcrossResume() async throws {
        let stack = try Stack()
        let a = Fixture.barbell()
        let b = Fixture.bodyweightStyle()
        let c = Fixture.unilateral()
        let replacement = Exercise(
            name: "Cable Fly",
            equipmentType: .cable,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            weightIncrement: 2.5,
            defaultRestTime: 60
        )
        let viewModel = try await startWorkout(stack, with: [a, b, c])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)
        try await stack.exerciseRepo.save(replacement)

        await viewModel.replaceExercise(at: 1, with: replacement.id)

        XCTAssertEqual(
            viewModel.exercises.map(\.id),
            [a.id, replacement.id, c.id],
            "the replacement holds the middle slot on screen"
        )
        try assertStripOrderMatchesStore(viewModel, stack)

        let resumed = stack.makeViewModel()
        await resumed.loadActiveWorkout()
        XCTAssertEqual(
            resumed.exercises.map(\.id),
            [a.id, replacement.id, c.id],
            "and holds it across a resume — this is the assertion the whole reindex exists for"
        )
        _ = workoutId
    }

    /// Replace deletes the outgoing exercise's rows rather than retargeting them, so nothing the
    /// user logged for the old movement can end up attributed to the new one. Verified through a
    /// separate `ModelContext`, so it is the store talking and not the screen.
    func testReplacingAnExerciseRemovesItsSetsFromTheStore() async throws {
        let stack = try Stack()
        let a = Fixture.barbell()
        let b = Fixture.unilateral()
        let replacement = Exercise(
            name: "Cable Fly",
            equipmentType: .cable,
            trackingType: .weightReps,
            primaryMuscle: "chest",
            weightIncrement: 2.5,
            defaultRestTime: 60
        )
        let viewModel = try await startWorkout(stack, with: [a, b])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)
        try await stack.exerciseRepo.save(replacement)

        // Log real work on the exercise that is about to be replaced.
        viewModel.selectedExerciseIndex = 1
        try await completeNextSet(viewModel, weight: 60, reps: 8)
        let doomed = try stack.committedSets(for: workoutId).filter { $0.exerciseId == b.id }
        XCTAssertEqual(doomed.count, 1, "precondition: the outgoing exercise has a committed row")

        await viewModel.replaceExercise(at: 1, with: replacement.id)

        let committed = try stack.committedSets(for: workoutId)
        XCTAssertTrue(
            committed.allSatisfy { $0.exerciseId != b.id },
            "no row may survive attributed to the replaced exercise"
        )
        XCTAssertFalse(
            committed.contains { $0.exerciseId == replacement.id && $0.weight != nil },
            "and none of the old numbers may be carried over onto the replacement"
        )
        XCTAssertEqual(
            committed.filter { $0.exerciseId == replacement.id }.count,
            1,
            "exactly one empty seeded set — an exercise with no sets does not exist"
        )
    }

    // MARK: - Journey: discarding and removing

    /// Discarding takes the whole session with it, PR records included.
    ///
    /// The end state is only half of what matters here. The other half — that the ViewModel stops
    /// pointing at these rows *before* they are deleted — is not observable from outside the call,
    /// so it lives in `DeleteOrderingTests`. This journey is what proves the reordering did not
    /// break the delete itself.
    func testDiscardingAWorkoutLeavesNothingBehind() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        try await completeNextSet(viewModel, weight: 100, reps: 5)
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 110, reps: 5)
        XCTAssertEqual(try stack.committedSets(for: workoutId).count, 2)
        XCTAssertGreaterThan(try stack.committedRecordCount(), 0, "the session should have set a PR to clean up")

        await viewModel.discardWorkout()

        XCTAssertNil(viewModel.workout)
        XCTAssertTrue(viewModel.exercises.isEmpty)
        XCTAssertTrue(viewModel.setsByExercise.isEmpty)
        XCTAssertTrue(viewModel.isWorkoutFinished)

        XCTAssertTrue(try stack.committedSets(for: workoutId).isEmpty)
        XCTAssertEqual(try stack.committedRecordCount(), 0, "records must be rebuilt away with the sets")

        let relaunched = stack.makeViewModel()
        await relaunched.loadActiveWorkout()
        XCTAssertNil(relaunched.workout, "a discarded workout must not come back as the active one")
        XCTAssertTrue(relaunched.currentSets.isEmpty)
    }

    /// Removing one exercise mid-workout leaves the other exactly as it was.
    func testRemovingAnExerciseMidWorkoutLeavesTheOtherIntact() async throws {
        let stack = try Stack()
        let bench = Fixture.barbell()
        let pullUp = Fixture.bodyweightStyle()
        let viewModel = try await startWorkout(stack, with: [bench, pullUp])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        try await completeNextSet(viewModel, weight: 100, reps: 5)
        viewModel.selectedExerciseIndex = 1
        try await completeNextSet(viewModel, weight: 10, reps: 8)
        viewModel.selectedExerciseIndex = 0

        await viewModel.removeExercise(at: 0)

        XCTAssertEqual(viewModel.exercises.map(\.id), [pullUp.id])
        XCTAssertNil(viewModel.setsByExercise[bench.id])
        XCTAssertEqual(viewModel.currentSets.count, 1, "the surviving exercise should be selected and intact")
        XCTAssertEqual(viewModel.currentSets.compactMap(\.reps), [8])

        let committed = try stack.committedSets(for: workoutId)
        XCTAssertEqual(committed.map(\.exerciseId), [pullUp.id])
        try assertScreenMatchesStore(viewModel, stack)

        let relaunched = stack.makeViewModel()
        await relaunched.loadActiveWorkout()
        XCTAssertEqual(relaunched.exercises.map(\.id), [pullUp.id])
        XCTAssertEqual(relaunched.currentSets.compactMap(\.reps), [8])
    }

    // MARK: - Journey: PR badges across sets

    /// Beating a PR demotes the set that held it.
    ///
    /// This is `applyAffectedSets`, which today works partly because every set in
    /// `setsByExercise` is the same object the pipeline mutated. Step 5 replaces those with
    /// value types, so the update has to be applied by id explicitly — §15 Q4 calls this the
    /// single most likely place for a silent bug in the conversion.
    func testBeatingAPRDemotesTheSetThatHeldIt() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        try await completeNextSet(viewModel, weight: 100, reps: 5)
        let firstSetId = viewModel.currentSets[0].id
        XCTAssertEqual(
            viewModel.currentSets[0].prStatus,
            .current,
            "the first 5-rep set in an empty history is the PR"
        )

        // A heavier set at the same reps takes the record.
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 120, reps: 5)

        let held = try XCTUnwrap(viewModel.currentSets.first(where: { $0.id == firstSetId }))
        XCTAssertNotEqual(held.prStatus, .current, "the old PR must not still claim the badge")
        XCTAssertEqual(viewModel.currentSets[1].prStatus, .current, "the heavier set takes it")

        // The demotion is persisted, not just on screen.
        let committed = try stack.committedSets(for: workoutId)
        let committedFirst = try XCTUnwrap(committed.first(where: { $0.id == firstSetId }))
        XCTAssertNotEqual(committedFirst.prStatus, .current)
        try assertScreenMatchesStore(viewModel, stack)

        let relaunched = stack.makeViewModel()
        await relaunched.loadActiveWorkout()
        let reloadedFirst = try XCTUnwrap(relaunched.currentSets.first(where: { $0.id == firstSetId }))
        XCTAssertNotEqual(reloadedFirst.prStatus, .current)
        XCTAssertEqual(relaunched.currentSets[1].prStatus, .current)
    }

    // MARK: - Journey: uncomplete round trip

    /// Uncompleting a set removes its contribution; re-completing restores it.
    ///
    /// Asserts on stats and PR records, which is where a double-count or a lost decrement
    /// would show up — neither is visible in the set table.
    func testUncompletingThenRecompletingASetRestoresStatsAndPR() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])

        try await completeNextSet(viewModel, weight: 100, reps: 5)
        let statsAfterFirst = try XCTUnwrap(try stack.committedStats(for: exercise.id))
        let volumeAfterFirst = statsAfterFirst.totalVolume
        let recordsAfterFirst = try stack.committedRecordCount()

        let set = viewModel.currentSets[0]
        await viewModel.uncompleteSet(set, previousContribution: nil)

        XCTAssertFalse(viewModel.currentSets[0].completed)
        let statsAfterUncomplete = try XCTUnwrap(try stack.committedStats(for: exercise.id))
        XCTAssertLessThan(
            statsAfterUncomplete.totalVolume,
            volumeAfterFirst,
            "uncompleting must remove the set's contribution"
        )

        await viewModel.completeSet(
            viewModel.currentSets[0],
            input: SetCompletionInput(weight: 100, reps: 5)
        )

        let statsAfterRedo = try XCTUnwrap(try stack.committedStats(for: exercise.id))
        XCTAssertEqual(
            statsAfterRedo.totalVolume,
            volumeAfterFirst,
            accuracy: 0.001,
            "re-completing the same set must land back where it started, not double-count"
        )
        XCTAssertEqual(
            try stack.committedRecordCount(),
            recordsAfterFirst,
            "the PR record count must not drift across an uncomplete/recomplete cycle"
        )
        try assertScreenMatchesStore(viewModel, stack)
    }

    // MARK: - Journey: fixture diversity

    /// A bodyweight-style exercise, where `effectiveWeight != weight`.
    ///
    /// Every fixture in the suite before 2026-08-12 used barbell or dumbbell, where the two are
    /// equal — so a regression rendering `weight` instead of `effectiveWeight` was invisible
    /// (mutation sweep miss #1). The whole pipeline reads `effectiveWeight`, so this also
    /// covers stats and PR evaluation using the right number.
    func testBodyweightExerciseComputesEffectiveWeightFromBodyweight() async throws {
        let stack = try Stack()
        let profile = try await stack.healthProfileRepo.fetchOrCreate()
        _ = try await stack.bodyweightRepo.save(
            BodyweightEntry(healthProfileId: profile.id, date: Date(), bodyweightKg: 80)
        )

        let exercise = Fixture.bodyweightStyle()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        // 10 kg of added load on top of 80 kg of bodyweight.
        try await completeNextSet(viewModel, weight: 10, reps: 6)

        let committed = try stack.committedSets(for: workoutId)
        let logged = try XCTUnwrap(committed.first)
        XCTAssertEqual(logged.weight, 10, "the raw weight is the added load")
        XCTAssertEqual(
            try XCTUnwrap(logged.effectiveWeight),
            90,
            accuracy: 0.001,
            "effectiveWeight = added load + (bodyweight x bodyweightFactor)"
        )

        // The rendered column must use effectiveWeight, not weight.
        let rendered = WorkoutSetPerformanceFormatter.fieldDisplay(
            for: .weight,
            set: ChartSetData(from: logged),
            exercise: ChartExerciseData(from: exercise),
            unitPreference: .metric
        )
        XCTAssertTrue(
            rendered.text.contains("90"),
            "the weight column renders effectiveWeight, got '\(rendered.text)'"
        )
    }

    // MARK: - Journey: the completion write path

    /// Every field a completion carries reaches the store — including RIR.
    ///
    /// Added after a mutation survived: deleting the `rir` write from
    /// `SetRepository.applyCompletion` broke nothing, because every journey completed sets with
    /// weight and reps only, and the differential never runs the write path at all. That is the
    /// §16 fixture-poverty lesson recurring on the surface step 5 is converting.
    func testCompletingASetPersistsEveryTypedFieldIncludingRIR() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        let pending = try XCTUnwrap(viewModel.currentSets.first(where: { !$0.completed }))
        await viewModel.completeSet(
            pending,
            input: SetCompletionInput(weight: 100, reps: 5, rir: 2)
        )

        let stored = try XCTUnwrap(try stack.committedSets(for: workoutId).first)
        XCTAssertEqual(stored.weight, 100)
        XCTAssertEqual(stored.reps, 5)
        XCTAssertEqual(stored.rir, 2, "RIR must reach the store, not just the screen")
        XCTAssertTrue(stored.completed)
        XCTAssertNotNil(stored.completedAt, "completedAt is part of the completion stamp")
        XCTAssertNil(stored.side, "a bilateral exercise clears side")

        try assertScreenMatchesStore(viewModel, stack)
    }

    /// The unilateral branch of the completion write: per-side values drive the derivation.
    ///
    /// `applyCompletion` either runs `syncDerivedPerformanceFields` (unilateral) or clears
    /// `side` (bilateral). Nothing covered the unilateral half, which is the riskiest part of
    /// moving those writes into the repository actor.
    func testCompletingAUnilateralSetDerivesRepsAndSideFromBothSides() async throws {
        let stack = try Stack()
        let exercise = Fixture.unilateral()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        let pending = try XCTUnwrap(viewModel.currentSets.first(where: { !$0.completed }))
        await viewModel.completeSet(
            pending,
            input: SetCompletionInput(
                weight: 24,
                leftReps: 12,
                rightReps: 10,
                leftRIR: 2,
                rightRIR: 3
            )
        )

        let stored = try XCTUnwrap(try stack.committedSets(for: workoutId).first)
        XCTAssertEqual(stored.leftReps, 12)
        XCTAssertEqual(stored.rightReps, 10)
        XCTAssertEqual(stored.leftRIR, 2)
        XCTAssertEqual(stored.rightRIR, 3)
        XCTAssertEqual(stored.side, .both, "the derivation marks a two-sided set")
        XCTAssertEqual(stored.prReps, 12, "PR reps come from the stronger side")
        XCTAssertEqual(stored.totalReps, 22, "stats reps are the sum of both sides")

        try assertScreenMatchesStore(viewModel, stack)
    }

    /// Flipping an exercise to bilateral clears `side` when its sets are re-completed.
    ///
    /// The narrow case that makes the `side = nil` write in `applyCompletion` load-bearing.
    /// `side` defaults to nil on a new set, so clearing it is a no-op unless the set already
    /// holds `.both` — which only happens when the exercise *was* unilateral. Found by mutation:
    /// deleting that write broke nothing until this journey existed.
    func testFlippingAnExerciseToBilateralClearsSideOnRecompletion() async throws {
        let stack = try Stack()
        let exercise = Fixture.unilateral()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        let pending = try XCTUnwrap(viewModel.currentSets.first(where: { !$0.completed }))
        await viewModel.completeSet(
            pending,
            input: SetCompletionInput(weight: 24, leftReps: 12, rightReps: 10)
        )
        XCTAssertEqual(
            try XCTUnwrap(try stack.committedSets(for: workoutId).first).side,
            .both,
            "setup: the unilateral derivation must have marked this set"
        )

        // The user un-ticks the row, then turns off per-side logging for the exercise.
        await viewModel.uncompleteSet(viewModel.currentSets[0], previousContribution: nil)
        var fields = ExerciseEditableFields(from: ChartExerciseData(from: exercise))
        fields.unilateral = false
        try await stack.exerciseService.updateExercise(id: exercise.id, fields: fields)
        await viewModel.refreshCurrentExerciseConfigurationData()

        // Re-completing with a plain rep count must drop the stale per-side marker.
        await viewModel.completeSet(
            viewModel.currentSets[0],
            input: SetCompletionInput(weight: 24, reps: 10)
        )

        XCTAssertNil(
            try XCTUnwrap(try stack.committedSets(for: workoutId).first).side,
            "a bilateral exercise must not leave a stale per-side marker on its sets"
        )
    }

    // MARK: - Journey: the History sub-tab

    /// Past sessions show up on the History sub-tab of the active workout screen.
    ///
    /// This surface was live models until 2026-08-13: `WorkoutHistoryGroup.sets` was
    /// `[WorkoutSet]`, fetched at `ActiveWorkoutViewModel:1523` and rendered by
    /// `ExerciseHistoryView:58` **in a view body on the main actor** — the same shape as crash B,
    /// on the same screen, and missing from every earlier scope list.
    ///
    /// Uses the bodyweight fixture so the rendered label has to come from `effectiveWeight`
    /// (90 kg) rather than `weight` (10 kg): the history path builds its own snapshots, so a
    /// mirror or formatter mistake here would not be caught by the set-table journeys.
    func testHistorySubTabShowsPastSessionsNewestFirst() async throws {
        let stack = try Stack()
        let exercise = Fixture.bodyweightStyle()
        let profile = try await stack.healthProfileRepo.fetchOrCreate()
        _ = try await stack.bodyweightRepo.save(
            BodyweightEntry(healthProfileId: profile.id, date: Date(), bodyweightKg: 80)
        )

        // Session one: two sets, then finish.
        let first = try await startWorkout(stack, with: [exercise])
        try await completeNextSet(first, weight: 10, reps: 6)
        await first.addSet(for: exercise.id)
        try await completeNextSet(first, weight: 15, reps: 5)
        await first.finishWorkout(title: "Pull Day", notes: nil, perceivedEffort: nil)

        // Session two: same exercise, one set logged.
        _ = try await stack.workoutService.startWorkout()
        let second = stack.makeViewModel()
        await second.loadActiveWorkout()
        await second.addExercises([exercise.id])
        try await completeNextSet(second, weight: 20, reps: 4)

        await second.loadHistoryForCurrentExercise()

        XCTAssertEqual(
            second.subTabHistory.count,
            2,
            "history covers every workout containing this exercise, including the current one"
        )

        let dates = second.subTabHistory.map(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >), "history is newest-first")

        let older = try XCTUnwrap(second.subTabHistory.last)
        XCTAssertEqual(older.sets.count, 2)
        XCTAssertEqual(
            older.sets.map(\.orderInExercise),
            [1, 2],
            "sets within a session are ordered by orderInExercise"
        )
        XCTAssertEqual(older.sets.compactMap(\.weight), [10, 15])
        let effective = older.sets.compactMap(\.effectiveWeight)
        XCTAssertEqual(effective.count, 2)
        for (actual, expected) in zip(effective, [90.0, 95.0]) {
            XCTAssertEqual(
                actual,
                expected,
                accuracy: 0.001,
                "history carries effectiveWeight, not the raw added load"
            )
        }

        // What the row actually renders — pinned, because it is *not* what the workout-detail
        // card renders for the same set.
        //
        // `ExerciseHistoryView` calls `display(for:exercise:unitPreference:)`, whose
        // `performanceLabel` is built from the raw `weight` plus an `isBodyweightStyle` marker
        // (`WorkoutSetPerformanceFormatter:314`). The detail cards call `fieldDisplay(...)`,
        // which resolves `effectiveWeight ?? weight` (`:171`). So the same set reads "10 kg × 6"
        // in history and "90" on the detail card.
        //
        // That predates this conversion and is deliberately left alone — a refactor is the wrong
        // place to change what a screen shows. Pinned here so that if anyone does change it, it
        // registers as a behaviour change rather than a tidy-up.
        let rendered = WorkoutSetPerformanceFormatter.display(
            for: try XCTUnwrap(older.sets.first),
            exercise: ChartExerciseData(from: exercise),
            unitPreference: .metric
        )
        let label = try XCTUnwrap(rendered.performanceLabel)
        XCTAssertTrue(
            label.contains("10"),
            "the history row renders the added load, not effectiveWeight, got '\(label)'"
        )
    }

    /// Viewing History, deleting a set, then going back shows the set is gone.
    ///
    /// The History sub-tab caches per exercise (`historyLoadedForExerciseId`) and includes the
    /// *current* workout's sets, so anything that changes them makes it stale. Four of the seven
    /// mutation paths — `deleteSet`, `changeSetType`, `addSet`, `addWarmupSet` — invalidated only
    /// the PR cache, so a deleted set stayed on the History tab until the user switched exercise.
    ///
    /// Survivable while that tab held live models (a deleted `WorkoutSet` renders undefined
    /// values, which merely *looked* stale); with snapshots it is deterministic staleness. Fixed
    /// by routing every path through `invalidateSetDerivedSubTabCaches()`.
    func testDeletingASetRemovesItFromTheHistoryTabWithoutSwitchingExercise() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])

        try await completeNextSet(viewModel, weight: 100, reps: 5)
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 110, reps: 5)

        // The user opens History — this populates the cache for this exercise.
        await viewModel.loadHistoryForCurrentExercise()
        XCTAssertEqual(
            viewModel.subTabHistory.flatMap(\.sets).count,
            2,
            "both sets of the in-progress workout show in history"
        )

        // Back to Sets, delete one.
        let doomed = viewModel.currentSets[1]
        await viewModel.deleteSet(doomed)

        // Back to History, same exercise — no switch, so only invalidation can refresh this.
        await viewModel.loadHistoryForCurrentExercise()

        let shown = viewModel.subTabHistory.flatMap(\.sets)
        XCTAssertEqual(shown.count, 1, "the deleted set must not still be listed in history")
        XCTAssertFalse(
            shown.contains { $0.id == doomed.id },
            "history is showing a set that no longer exists"
        )
        XCTAssertEqual(shown.first?.weight, 100)
    }

    // MARK: - Journey: exercise settings mid-workout

    /// Editing rest time mid-workout takes effect without leaving the screen.
    ///
    /// The snapshot conversion froze `exercises`, so this needed an explicit refetch
    /// (fixed 2026-08-13). Covered at the stub level too; here it runs through the real
    /// `ExerciseService` and repository, so it also proves the edit was actually persisted.
    func testEditingRestTimeMidWorkoutTakesEffectImmediately() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])

        XCTAssertEqual(viewModel.currentExercise?.defaultRestTime, 90)

        var fields = ExerciseEditableFields(from: ChartExerciseData(from: exercise))
        fields.defaultRestTime = 180
        try await stack.exerciseService.updateExercise(id: exercise.id, fields: fields)

        await viewModel.refreshCurrentExerciseConfigurationData()

        XCTAssertEqual(
            viewModel.currentExercise?.defaultRestTime,
            180,
            "the rest timer would keep starting at the pre-edit duration"
        )
    }
}

// MARK: - Cross-screen journeys

extension WorkoutJourneyTests {

    /// Finish a workout and see it on Home.
    ///
    /// The finish path is `WorkoutSummarySheet` territory (step 7) and reads live workout
    /// fields *during* `finishWorkout`'s save, so it is the other half of the crash surface.
    /// Crossing into Home also covers what Stage 1 converted, from the write side: whatever
    /// the logging path committed is what the recent-workouts list has to render.
    func testFinishingAWorkoutMovesItOutOfProgressAndOntoHome() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(viewModel.workout?.id)

        try await completeNextSet(viewModel, weight: 100, reps: 5)
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 100, reps: 5)

        await viewModel.finishWorkout(title: "Push Day", notes: "felt strong", perceivedEffort: 8)

        // No workout is active any more — a fresh screen finds nothing to resume.
        let resumed = stack.makeViewModel()
        await resumed.loadActiveWorkout()
        XCTAssertNil(resumed.workout, "the finished workout must not still be in progress")

        // It is committed as completed, with the metadata from the summary sheet.
        let context = ModelContext(stack.container)
        let stored = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutId })).first
        )
        XCTAssertEqual(stored.status, .completed)
        XCTAssertEqual(stored.title, "Push Day")
        XCTAssertEqual(stored.notes, "felt strong")
        XCTAssertEqual(stored.perceivedEffort, 8)

        // And Home renders it.
        let home = stack.makeHomeViewModel()
        await home.loadData()
        let recent = try XCTUnwrap(
            home.recentWorkouts.first(where: { $0.id == workoutId }),
            "the finished workout must appear in Home's recent list"
        )
        XCTAssertEqual(recent.displayTitle, "Push Day")
        XCTAssertEqual(recent.setCount, 2, "Home counts the working sets that have data")
        XCTAssertEqual(recent.exerciseCount, 1)

        let stats = try XCTUnwrap(try stack.committedStats(for: exercise.id))
        XCTAssertEqual(stats.totalSets, 2)
        XCTAssertEqual(stats.totalVolume, 1000, accuracy: 0.001, "2 x 100 kg x 5 reps")
    }

    /// Edit a set on a finished workout, from the edit screen.
    ///
    /// `EditWorkoutViewModel` conforms to the same `SetTableDataSource`, so step 5 changes it
    /// whether or not that was planned (§6). It also holds live `Workout`, `[Exercise]` and
    /// `[UUID: [WorkoutSet]]`, and the crash analysis nominates this exact flow as the
    /// staleness risk — so it needs a journey of its own before the conversion.
    func testEditingAFinishedWorkoutUpdatesTheSetAndItsStats() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let active = try await startWorkout(stack, with: [exercise])
        let workoutId = try XCTUnwrap(active.workout?.id)

        try await completeNextSet(active, weight: 100, reps: 5)
        await active.finishWorkout(title: nil, notes: nil, perceivedEffort: nil)

        let volumeBefore = try XCTUnwrap(try stack.committedStats(for: exercise.id)).totalVolume
        XCTAssertEqual(volumeBefore, 500, accuracy: 0.001)

        // Reopen it for editing, as the user does from Calendar or Home.
        let edit = stack.makeEditViewModel(workoutId: workoutId)
        await edit.loadWorkout()

        XCTAssertEqual(edit.currentSets.count, 1)
        let set = try XCTUnwrap(edit.currentSets.first)
        XCTAssertEqual(set.weight, 100)

        // Correct the weight — the user mistyped it.
        await edit.completeSet(set, input: SetCompletionInput(weight: 120, reps: 5))

        let committed = try stack.committedSets(for: workoutId)
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(try XCTUnwrap(committed.first).weight, 120, "the correction must persist")

        let volumeAfter = try XCTUnwrap(try stack.committedStats(for: exercise.id)).totalVolume
        XCTAssertEqual(
            volumeAfter,
            600,
            accuracy: 0.001,
            "stats must follow the edit — 120 x 5, applied as a delta rather than added twice"
        )

        // Reopening shows the corrected value, not the one it was loaded with.
        let reopened = stack.makeEditViewModel(workoutId: workoutId)
        await reopened.loadWorkout()
        XCTAssertEqual(reopened.currentSets.first?.weight, 120)
    }

    // MARK: - Baseline selection across a switch to bodyweight

    /// A 0 kg set can never satisfy the capacity filter — every e1RM formula is
    /// `weight * repFactor`. The stale fallback therefore walked straight past a bodyweight
    /// era to the last weighted session and offered a year-old load as a current suggestion.
    func testStaleWeightedBaselineIsWithheldOnceTheExerciseIsLoggedAtBodyweight() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        try await stack.exerciseRepo.save(exercise)

        try await seedCompletedSet(
            stack,
            exercise: exercise,
            date: Date().addingTimeInterval(-400 * 86_400),
            weight: 100,
            reps: 5
        )
        // Logged since, at bodyweight — real, completed, and inside the recency window.
        try await seedCompletedSet(
            stack,
            exercise: exercise,
            date: Date().addingTimeInterval(-2 * 86_400),
            weight: 0,
            reps: 8
        )

        let estimate = try await stack.loadPrescriptionService.estimateBaseE1RM(
            exerciseId: exercise.id,
            completedSessionSets: []
        )

        XCTAssertEqual(estimate.source, .noData)
        XCTAssertNil(estimate.value)
        XCTAssertNil(estimate.sourceWorkoutDate, "no date to anchor a 'based on...' banner to")
        XCTAssertTrue(estimate.suppressedForBodyweightHistory)
    }

    /// The counterpart: without newer bodyweight logging, the stale fallback is still correct
    /// and must keep working. Withholding is meant to be narrow.
    func testStaleWeightedBaselineStillAppliesWithoutNewerBodyweightLogging() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        try await stack.exerciseRepo.save(exercise)

        try await seedCompletedSet(
            stack,
            exercise: exercise,
            date: Date().addingTimeInterval(-400 * 86_400),
            weight: 100,
            reps: 5
        )

        let estimate = try await stack.loadPrescriptionService.estimateBaseE1RM(
            exerciseId: exercise.id,
            completedSessionSets: []
        )

        XCTAssertEqual(estimate.source, .staleRecentPerformance)
        XCTAssertNotNil(estimate.value)
        XCTAssertFalse(estimate.suppressedForBodyweightHistory)
    }

    /// Seed one completed set in its own finished workout at an explicit date.
    private func seedCompletedSet(
        _ stack: Stack,
        exercise: Exercise,
        date: Date,
        weight: Double,
        reps: Int
    ) async throws {
        let workout = Workout(
            date: date,
            title: "Session",
            startTime: date,
            endTime: date.addingTimeInterval(1_800),
            duration: 1_800,
            status: .completed
        )
        try await stack.workoutRepo.save(workout)

        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: date,
            completedAt: date,
            weight: weight,
            reps: reps,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        )
        _ = try await stack.setService.save(set)
    }

    // MARK: - Journey: the capacity baseline reads reps in reserve

    /// Logging a set with reps to spare must not make the app ask for *less* next time.
    ///
    /// This is the round trip no other test covers, because the two halves live on opposite sides
    /// of a wall: `SetService` stores `e1RM` from reps alone, while every engine calculation uses
    /// `reps + RIR`. The suggestion scenario harness injects `baseE1RM` directly, so it is
    /// structurally blind to the seam. Only a real logged set, read back through the real service,
    /// exercises it.
    ///
    /// Before the fix: 60 x 8 @ RIR 2 stored an e1RM of 76.0, and a fixed target of 8 @ RIR 2
    /// priced at 76.0 / (1 + 10/30) = 57.0 -> 57.5 kg. Follow that and next session it says 55.0.
    /// A ratchet down of about 4% per session, on the first set of every session, for anyone who
    /// does not train to failure.
    func testASetLoggedWithRepsInReserveDoesNotLowerTheNextSuggestion() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])

        try await completeNextSet(viewModel, weight: 60, reps: 8, rir: 2)

        // The stored value keeps the display convention — charts and PRs must not move.
        let committed = try XCTUnwrap(stack.committedSets(for: XCTUnwrap(viewModel.workout?.id)).first)
        XCTAssertEqual(try XCTUnwrap(committed.e1RM), 76.0, accuracy: 0.01,
                       "stored e1RM stays reps-only: it is what charts and PRs render")

        // The capacity baseline must read the reserve.
        let estimate = try await stack.loadPrescriptionService.estimateBaseE1RM(
            exerciseId: exercise.id,
            completedSessionSets: []
        )
        XCTAssertEqual(try XCTUnwrap(estimate.value), 80.0, accuracy: 0.01,
                       "capacity is Epley over reps + RIR = 10, not reps = 8")
    }

    /// The user-visible half of the same round trip: what the card would say next session.
    func testNextSessionDoesNotPriceBelowTheWeightJustCompleted() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])

        try await completeNextSet(viewModel, weight: 60, reps: 8, rir: 2)

        // Empty completed sets = a fresh session, so this is entirely the historical baseline.
        let evaluation = try await stack.loadPrescriptionService.evaluateSuggestions(
            exerciseId: exercise.id,
            pendingSets: [
                SuggestionPendingSetInput(
                    setId: UUID(),
                    setIndex: 0,
                    setNumber: 1,
                    target: SuggestionTarget(
                        reps: 8,
                        rir: 2,
                        repRange: nil,
                        repsSource: .explicitSet,
                        rirSource: .explicitSet
                    ),
                    setType: .working
                )
            ],
            completedSessionSets: []
        )

        let prescribed = try XCTUnwrap(evaluation.decisions.first?.prescribedWeight)
        XCTAssertGreaterThanOrEqual(
            prescribed, 60.0,
            "prescribing under 60 kg for the same 8 @ RIR 2 the lifter just did is a regression, "
            + "not a suggestion (was 57.5 before the capacity baseline read RIR)"
        )
    }

    /// A history with no RIR must be completely unaffected — the fallback is the stored value,
    /// which is the same number as before, so imported Strong/Hevy data does not shift.
    func testHistoryWithoutRIRIsUnchanged() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])

        try await completeNextSet(viewModel, weight: 60, reps: 8, rir: nil)

        let estimate = try await stack.loadPrescriptionService.estimateBaseE1RM(
            exerciseId: exercise.id,
            completedSessionSets: []
        )
        XCTAssertEqual(try XCTUnwrap(estimate.value), 76.0, accuracy: 0.01,
                       "no RIR, no reserve to credit — identical to the old behaviour")
    }

    /// A set taken to failure is already at its capacity, so RIR 0 must change nothing either.
    func testRIRZeroIsUnchanged() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])

        try await completeNextSet(viewModel, weight: 60, reps: 8, rir: 0)

        let estimate = try await stack.loadPrescriptionService.estimateBaseE1RM(
            exerciseId: exercise.id,
            completedSessionSets: []
        )
        XCTAssertEqual(try XCTUnwrap(estimate.value), 76.0, accuracy: 0.01)
    }

    /// The peak must be chosen on capacity, not on the stored figure: a lighter set with more
    /// reserve can genuinely be the better evidence, and ranking on one number while reporting
    /// another would let a set win the comparison and then contribute a different value.
    func testThePeakIsChosenOnCapacityNotOnTheStoredValue() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        let viewModel = try await startWorkout(stack, with: [exercise])

        // Stored: 80 x 5 -> 93.3, beats 70 x 8 -> 88.7.
        // Capacity: 80 x 5 @ RIR 0 -> 93.3, but 70 x 8 @ RIR 4 -> 70 x (1 + 12/30) = 98.0.
        try await completeNextSet(viewModel, weight: 80, reps: 5, rir: 0)
        await viewModel.addSet(for: exercise.id)
        try await completeNextSet(viewModel, weight: 70, reps: 8, rir: 4)

        let estimate = try await stack.loadPrescriptionService.estimateBaseE1RM(
            exerciseId: exercise.id,
            completedSessionSets: []
        )
        XCTAssertEqual(try XCTUnwrap(estimate.value), 98.0, accuracy: 0.01,
                       "the set with reserve is the stronger capacity evidence")
    }

    // MARK: - Journey: an excluded session says so, on both history screens

    /// `WorkoutHistoryGroup` is built in two places — `ExerciseDetailViewModel.loadHistory` and
    /// `ActiveWorkoutViewModel.loadHistoryForCurrentExercise` — that render the *same*
    /// `ExerciseHistoryView`. Two independent groupings feeding one view is exactly the shape
    /// that drifts, and a chip that appears on one screen but not the other is worse than none:
    /// it teaches people the signal is unreliable.
    ///
    /// So this asserts both loaders, on one store, agree per session.
    func testBothHistoryLoadersMarkTheSameExcludedSession() async throws {
        let stack = try Stack()
        let exercise = Fixture.barbell()
        try await stack.exerciseRepo.save(exercise)

        let excludedDate = Date().addingTimeInterval(-14 * 86_400)
        let countedDate = Date().addingTimeInterval(-7 * 86_400)
        let excludedWorkoutId = try await seedSession(
            stack, exercise: exercise, date: excludedDate, weight: 55, reps: 8,
            excludeFromProgressionHistory: true
        )
        let countedWorkoutId = try await seedSession(
            stack, exercise: exercise, date: countedDate, weight: 55, reps: 6,
            excludeFromProgressionHistory: false
        )

        // Loader 1 — the exercise detail screen.
        let detailViewModel = ExerciseDetailViewModel(
            exerciseId: exercise.id,
            exerciseService: stack.exerciseService,
            prService: stack.prService,
            setService: stack.setService,
            statsService: stack.statsService,
            workoutService: stack.workoutService
        )
        await detailViewModel.loadHistory()

        // Loader 2 — the same view, rendered inside a live workout.
        let activeViewModel = try await startWorkout(stack, with: [exercise])
        await activeViewModel.loadHistoryForCurrentExercise()

        func flags(_ groups: [WorkoutHistoryGroup]) -> [UUID: Bool] {
            Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.isExcludedFromProgression) })
        }

        let detailFlags = flags(detailViewModel.historyWorkouts)
        let activeFlags = flags(activeViewModel.subTabHistory)

        XCTAssertEqual(detailFlags[excludedWorkoutId], true)
        XCTAssertEqual(detailFlags[countedWorkoutId], false)
        XCTAssertEqual(
            activeFlags[excludedWorkoutId], detailFlags[excludedWorkoutId],
            "the two history loaders disagree about the excluded session"
        )
        XCTAssertEqual(
            activeFlags[countedWorkoutId], detailFlags[countedWorkoutId],
            "the two history loaders disagree about the counted session"
        )
    }

    /// The chip is resolved per exercise, so a session excluded for *one* exercise must leave the
    /// others in that same session unmarked.
    func testExerciseScopedExclusionMarksOnlyTheNamedExercise() async throws {
        let stack = try Stack()
        let bench = Fixture.barbell()
        let row = Exercise(
            name: "Barbell Row",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "back"
        )
        try await stack.exerciseRepo.save(bench)
        try await stack.exerciseRepo.save(row)

        let date = Date().addingTimeInterval(-10 * 86_400)
        let workout = Workout(
            date: date, startTime: date, endTime: date.addingTimeInterval(1_800),
            duration: 1_800, status: .completed,
            excludedExerciseIdsFromProgressionHistory: [bench.id]
        )
        try await stack.workoutRepo.save(workout)
        for (index, exercise) in [bench, row].enumerated() {
            _ = try await stack.setService.save(WorkoutSet(
                workoutId: workout.id, exerciseId: exercise.id, date: date, completedAt: date,
                weight: 60, reps: 8, setType: .working,
                orderInWorkout: index + 1, orderInExercise: 1, completed: true
            ))
        }

        func historyFlag(for exerciseId: UUID) async -> Bool? {
            let viewModel = ExerciseDetailViewModel(
                exerciseId: exerciseId,
                exerciseService: stack.exerciseService,
                prService: stack.prService,
                setService: stack.setService,
                statsService: stack.statsService,
                workoutService: stack.workoutService
            )
            await viewModel.loadHistory()
            return viewModel.historyWorkouts.first { $0.id == workout.id }?.isExcludedFromProgression
        }

        let benchFlag = await historyFlag(for: bench.id)
        let rowFlag = await historyFlag(for: row.id)

        XCTAssertEqual(benchFlag, true)
        XCTAssertEqual(
            rowFlag, false,
            "the row's history must stay unmarked — the exclusion did not name it"
        )
    }

    @discardableResult
    private func seedSession(
        _ stack: Stack,
        exercise: Exercise,
        date: Date,
        weight: Double,
        reps: Int,
        excludeFromProgressionHistory: Bool
    ) async throws -> UUID {
        let workout = Workout(
            date: date,
            startTime: date,
            endTime: date.addingTimeInterval(1_800),
            duration: 1_800,
            status: .completed,
            excludeFromProgressionHistory: excludeFromProgressionHistory
        )
        try await stack.workoutRepo.save(workout)

        _ = try await stack.setService.save(WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: date,
            completedAt: date,
            weight: weight,
            reps: reps,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: true
        ))
        return workout.id
    }

}
