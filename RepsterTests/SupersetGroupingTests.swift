import XCTest
import SwiftData
@testable import Repster

/// Grouping derivation and the create-path plumbing that feeds it.
///
/// There is no historic coverage to lean on here: `supersetGroupId` appears in **zero sets** of the
/// real 11,785-set history (STEP5_SCOPE_AND_TEST_STRATEGY.md §5.2), so the golden master and the
/// differential tests protect none of this. Everything is built from fixtures.
final class SupersetGroupingTests: XCTestCase {

    // MARK: - Derivation

    func testUngroupedExerciseHasNoGroup() {
        let bench = makeExercise("Bench Press")
        let sets = [bench.id: [makeSet(exerciseId: bench.id, group: nil)]]

        XCTAssertNil(SupersetGrouping.groupId(for: bench.id, in: sets))
        XCTAssertFalse(SupersetGrouping.isGrouped(bench.id, exercises: [bench], setsByExercise: sets))
        XCTAssertNil(SupersetGrouping.next(after: bench.id, exercises: [bench], setsByExercise: sets))
        XCTAssertFalse(SupersetGrouping.isLastMember(bench.id, exercises: [bench], setsByExercise: sets))
    }

    func testCleanPairResolvesOrderAndLastMember() {
        let group = UUID()
        let bench = makeExercise("Bench Press")
        let incline = makeExercise("Incline DB Press")
        let sets = [
            bench.id: [makeSet(exerciseId: bench.id, group: group), makeSet(exerciseId: bench.id, group: group)],
            incline.id: [makeSet(exerciseId: incline.id, group: group)]
        ]
        let exercises = [bench, incline]

        XCTAssertEqual(SupersetGrouping.groupId(for: bench.id, in: sets), group)
        XCTAssertTrue(SupersetGrouping.isGrouped(bench.id, exercises: exercises, setsByExercise: sets))

        XCTAssertEqual(
            SupersetGrouping.next(after: bench.id, exercises: exercises, setsByExercise: sets)?.id,
            incline.id,
            "the first member's next is the second"
        )
        XCTAssertNil(
            SupersetGrouping.next(after: incline.id, exercises: exercises, setsByExercise: sets),
            "the last member has no next — this is where rest resumes"
        )

        XCTAssertFalse(SupersetGrouping.isLastMember(bench.id, exercises: exercises, setsByExercise: sets))
        XCTAssertTrue(SupersetGrouping.isLastMember(incline.id, exercises: exercises, setsByExercise: sets))
    }

    /// Reachable four ways: delete or replace one half of a pair, import a template whose group
    /// names one exercise, or dissolve from one side. The survivor keeps its id and must read as
    /// ungrouped everywhere. SUPERSETS_IMPLEMENTATION_PLAN.md G5.
    func testGroupOfOneReadsAsUngrouped() {
        let group = UUID()
        let bench = makeExercise("Bench Press")
        let sets = [bench.id: [makeSet(exerciseId: bench.id, group: group)]]
        let exercises = [bench]

        XCTAssertEqual(
            SupersetGrouping.groupId(for: bench.id, in: sets), group,
            "the raw field is unchanged — only the interpretation of it is"
        )
        XCTAssertFalse(SupersetGrouping.isGrouped(bench.id, exercises: exercises, setsByExercise: sets))
        XCTAssertNil(SupersetGrouping.next(after: bench.id, exercises: exercises, setsByExercise: sets))
        XCTAssertFalse(
            SupersetGrouping.isLastMember(bench.id, exercises: exercises, setsByExercise: sets),
            "a group of one has no last member — otherwise it would start a rest it never suppressed"
        )
        XCTAssertFalse(
            SupersetGrouping.runs(exercises: exercises, setsByExercise: sets)[0].isMarked,
            "and it must not draw a container"
        )
    }

    /// Defensive. Unreachable once `SetService.create` carries the field, because writes are
    /// all-or-nothing per exercise — asserted so a future write path cannot reintroduce it quietly.
    func testHalfTaggedExerciseStillResolvesToItsGroup() {
        let group = UUID()
        let bench = makeExercise("Bench Press")
        let sets = [bench.id: [
            makeSet(exerciseId: bench.id, group: nil),
            makeSet(exerciseId: bench.id, group: group),
            makeSet(exerciseId: bench.id, group: nil)
        ]]

        XCTAssertEqual(
            SupersetGrouping.groupId(for: bench.id, in: sets), group,
            "any non-nil set decides it — `sets.first?.supersetGroupId` would have returned nil here"
        )
    }

    // MARK: - Runs

    /// The overwhelmingly common case, and the one a regression would hurt: nobody has a superset.
    /// Every exercise must come back as its own unmarked run so the strip renders exactly as it
    /// did before any of this existed.
    func testWorkoutWithNoSupersetsProducesOneUnmarkedRunPerExercise() {
        let exercises = ["Squat", "Bench Press", "Row", "Curl"].map(makeExercise)
        let sets = Dictionary(uniqueKeysWithValues: exercises.map {
            ($0.id, [makeSet(exerciseId: $0.id, group: nil)])
        })

        let runs = SupersetGrouping.runs(exercises: exercises, setsByExercise: sets)

        XCTAssertEqual(runs.count, exercises.count)
        XCTAssertEqual(runs.map(\.exercises.count), [1, 1, 1, 1])
        XCTAssertTrue(runs.allSatisfy { !$0.isMarked })
        XCTAssertEqual(
            runs.flatMap(\.exercises).map(\.id), exercises.map(\.id),
            "display order must survive the round trip through runs"
        )
    }

    /// An exercise with no rows at all — the window `replaceExercise` opens between clearing the
    /// outgoing sets and adding the replacement's first one.
    func testExerciseWithNoSetsIsUngroupedRatherThanCrashing() {
        let bench = makeExercise("Bench Press")

        XCTAssertNil(SupersetGrouping.groupId(for: bench.id, in: [:]))
        let runs = SupersetGrouping.runs(exercises: [bench], setsByExercise: [:])
        XCTAssertEqual(runs.count, 1)
        XCTAssertFalse(runs[0].isMarked)
    }

    func testRunsSplitGroupedFromUngrouped() {
        let group = UUID()
        let bench = makeExercise("Bench Press")
        let incline = makeExercise("Incline DB Press")
        let fly = makeExercise("Cable Fly")
        let sets = [
            bench.id: [makeSet(exerciseId: bench.id, group: group)],
            incline.id: [makeSet(exerciseId: incline.id, group: group)],
            fly.id: [makeSet(exerciseId: fly.id, group: nil)]
        ]

        let runs = SupersetGrouping.runs(exercises: [bench, incline, fly], setsByExercise: sets)

        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].exercises.map(\.id), [bench.id, incline.id])
        XCTAssertTrue(runs[0].isMarked)
        XCTAssertEqual(runs[1].exercises.map(\.id), [fly.id])
        XCTAssertFalse(runs[1].isMarked)
    }

    /// A template can assign group A to exercises 1 and 3 with something else between them —
    /// `CreateEditTemplateViewModel.setSupersetGroup` has no contiguity check, and that data
    /// propagates into a workout intact. The container must never span the exercise in the middle.
    /// SUPERSETS_IMPLEMENTATION_PLAN.md G4.
    func testNonContiguousGroupProducesSeparateUnmarkedRuns() {
        let group = UUID()
        let bench = makeExercise("Bench Press")
        let fly = makeExercise("Cable Fly")
        let incline = makeExercise("Incline DB Press")
        let sets = [
            bench.id: [makeSet(exerciseId: bench.id, group: group)],
            fly.id: [makeSet(exerciseId: fly.id, group: nil)],
            incline.id: [makeSet(exerciseId: incline.id, group: group)]
        ]

        let runs = SupersetGrouping.runs(exercises: [bench, fly, incline], setsByExercise: sets)

        XCTAssertEqual(runs.count, 3, "three runs, not one container swallowing Cable Fly")
        XCTAssertEqual(runs.map(\.isMarked), [false, false, false], "a run of one never draws a container")
        XCTAssertEqual(runs[1].exercises.map(\.id), [fly.id])
    }

    // MARK: - Workout detail grouping (PR6)

    /// The divergence the extraction found. Calendar ordered by `sets.first?.orderInWorkout` and
    /// Home by `.min()`; a warm-up added mid-workout has `orderInExercise == 1` but the highest
    /// `orderInWorkout` in the session, which is enough to order the same workout differently on
    /// the two screens. `min()` is correct — it matches how the live tab strip orders exercises.
    func testExerciseGroupsOrderByEarliestSetNotByFirstListedSet() {
        let squat = makeExercise("Back Squat")
        let bench = makeExercise("Bench Press")

        // Squat ran first (orderInWorkout 1) but had a warm-up appended at the tail (99).
        // Sorted by orderInExercise that warm-up lands first in the array.
        let squatWarmup = makeChartSet(exerciseId: squat.id, orderInWorkout: 99, orderInExercise: 1)
        let squatWorking = makeChartSet(exerciseId: squat.id, orderInWorkout: 1, orderInExercise: 2)
        let benchWorking = makeChartSet(exerciseId: bench.id, orderInWorkout: 50, orderInExercise: 1)

        let groups = ExerciseGroup.build(
            sets: [squatWarmup, squatWorking, benchWorking],
            exercisesById: [squat.id: squat, bench.id: bench],
            statsById: [:]
        )

        XCTAssertEqual(
            groups.map(\.exercise.id), [squat.id, bench.id],
            "Squat ran first. Ordering on the first *listed* set would have put Bench ahead of it."
        )
    }

    func testExerciseGroupsSkipExercisesThatCannotBeResolved() {
        let bench = makeExercise("Bench Press")
        let ghost = UUID()

        let groups = ExerciseGroup.build(
            sets: [
                makeChartSet(exerciseId: bench.id, orderInWorkout: 1, orderInExercise: 1),
                makeChartSet(exerciseId: ghost, orderInWorkout: 2, orderInExercise: 1)
            ],
            exercisesById: [bench.id: bench],
            statsById: [:]
        )

        XCTAssertEqual(groups.map(\.exercise.id), [bench.id])
    }

    func testWorkoutDetailRunsMarkOnlyContiguousPairs() {
        let group = UUID()
        let bench = makeExercise("Bench Press")
        let incline = makeExercise("Incline DB Press")
        let fly = makeExercise("Cable Fly")

        let groups = ExerciseGroup.build(
            sets: [
                makeChartSet(exerciseId: bench.id, orderInWorkout: 1, orderInExercise: 1, group: group),
                makeChartSet(exerciseId: incline.id, orderInWorkout: 2, orderInExercise: 1, group: group),
                makeChartSet(exerciseId: fly.id, orderInWorkout: 3, orderInExercise: 1)
            ],
            exercisesById: [bench.id: bench, incline.id: incline, fly.id: fly],
            statsById: [:]
        )

        let runs = ExerciseGroupRun.runs(from: groups)

        XCTAssertEqual(runs.count, 2)
        XCTAssertTrue(runs[0].isMarked)
        XCTAssertEqual(runs[0].groups.map(\.exercise.id), [bench.id, incline.id])
        XCTAssertFalse(runs[1].isMarked)
    }

    /// Same G4 rule as the live strip, one level up: a card must never span an exercise that is
    /// not in the group.
    func testWorkoutDetailRunsSplitANonContiguousGroup() {
        let group = UUID()
        let bench = makeExercise("Bench Press")
        let fly = makeExercise("Cable Fly")
        let incline = makeExercise("Incline DB Press")

        let groups = ExerciseGroup.build(
            sets: [
                makeChartSet(exerciseId: bench.id, orderInWorkout: 1, orderInExercise: 1, group: group),
                makeChartSet(exerciseId: fly.id, orderInWorkout: 2, orderInExercise: 1),
                makeChartSet(exerciseId: incline.id, orderInWorkout: 3, orderInExercise: 1, group: group)
            ],
            exercisesById: [bench.id: bench, fly.id: fly, incline.id: incline],
            statsById: [:]
        )

        let runs = ExerciseGroupRun.runs(from: groups)

        XCTAssertEqual(runs.count, 3)
        XCTAssertTrue(runs.allSatisfy { !$0.isMarked })
    }

    // MARK: - Creation carries the group (PR1)

    func testCreatedSetCarriesTheGroupItWasGiven() async throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps)
        try await context.exerciseRepo.save(exercise)
        let group = UUID()

        let created = try await context.setService.create(
            workoutId: UUID(),
            exerciseId: exercise.id,
            date: Date(),
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            weight: nil,
            reps: nil,
            supersetGroupId: group
        )

        XCTAssertEqual(created.supersetGroupId, group)
        let persisted = try await context.setRepo.fetch(byId: created.id)
        XCTAssertEqual(
            persisted?.supersetGroupId, group,
            "the group must survive the round trip, not just the returned instance"
        )
    }

    /// The defect this whole feature was gated on: before the parameter existed, every set added
    /// during a live workout was written ungrouped. Deleting `supersetGroupId:` from
    /// `SetRepository.create`'s `WorkoutSet(...)` call must fail the test above, not this one.
    func testCreatedSetStaysUngroupedWhenNoGroupIsGiven() async throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Cable Fly", equipmentType: .cable, trackingType: .weightReps)
        try await context.exerciseRepo.save(exercise)

        let created = try await context.setService.create(
            workoutId: UUID(),
            exerciseId: exercise.id,
            date: Date(),
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            weight: nil,
            reps: nil
        )

        XCTAssertNil(created.supersetGroupId)
    }

    // MARK: - History partner lookup (PR7)

    func testSupersetPartnerNamesReportsTheOtherHalfOfThePair() async throws {
        let context = try makeContext()
        let bench = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps)
        let incline = Exercise(name: "Incline DB Press", equipmentType: .dumbbell, trackingType: .weightReps)
        try await context.exerciseRepo.save(bench)
        try await context.exerciseRepo.save(incline)

        let workoutId = UUID()
        let group = UUID()
        try await context.setRepo.save(persistedSet(workoutId, bench.id, 1, group))
        try await context.setRepo.save(persistedSet(workoutId, incline.id, 2, group))

        let partners = try await context.setService.supersetPartnerNames(
            workoutIds: [workoutId],
            exerciseId: bench.id
        )

        XCTAssertEqual(partners[workoutId], ["Incline DB Press"])
    }

    func testSupersetPartnerNamesOmitsWorkoutsWithNoGrouping() async throws {
        let context = try makeContext()
        let bench = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps)
        let fly = Exercise(name: "Cable Fly", equipmentType: .cable, trackingType: .weightReps)
        try await context.exerciseRepo.save(bench)
        try await context.exerciseRepo.save(fly)

        let workoutId = UUID()
        try await context.setRepo.save(persistedSet(workoutId, bench.id, 1, nil))
        try await context.setRepo.save(persistedSet(workoutId, fly.id, 2, nil))

        let partners = try await context.setService.supersetPartnerNames(
            workoutIds: [workoutId],
            exerciseId: bench.id
        )

        XCTAssertTrue(partners.isEmpty, "no grouping means no chip, not an empty-named one")
    }

    /// Another exercise in the same workout but a *different* group is not a partner.
    func testSupersetPartnerNamesIgnoresOtherGroupsInTheSameWorkout() async throws {
        let context = try makeContext()
        let bench = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps)
        let incline = Exercise(name: "Incline DB Press", equipmentType: .dumbbell, trackingType: .weightReps)
        let curl = Exercise(name: "Bicep Curl", equipmentType: .dumbbell, trackingType: .weightReps)
        let pushdown = Exercise(name: "Tricep Pushdown", equipmentType: .cable, trackingType: .weightReps)
        for exercise in [bench, incline, curl, pushdown] { try await context.exerciseRepo.save(exercise) }

        let workoutId = UUID()
        let groupA = UUID()
        let groupB = UUID()
        try await context.setRepo.save(persistedSet(workoutId, bench.id, 1, groupA))
        try await context.setRepo.save(persistedSet(workoutId, incline.id, 2, groupA))
        try await context.setRepo.save(persistedSet(workoutId, curl.id, 3, groupB))
        try await context.setRepo.save(persistedSet(workoutId, pushdown.id, 4, groupB))

        let partners = try await context.setService.supersetPartnerNames(
            workoutIds: [workoutId],
            exerciseId: bench.id
        )

        XCTAssertEqual(partners[workoutId], ["Incline DB Press"])
    }

    /// The chip reads the way the session ran, so partners come back in `orderInWorkout` order.
    func testSupersetPartnerNamesFollowWorkoutOrder() async throws {
        let context = try makeContext()
        let bench = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps)
        let dip = Exercise(name: "Dip", equipmentType: .bodyweight, trackingType: .weightReps)
        let fly = Exercise(name: "Cable Fly", equipmentType: .cable, trackingType: .weightReps)
        for exercise in [bench, dip, fly] { try await context.exerciseRepo.save(exercise) }

        let workoutId = UUID()
        let group = UUID()
        try await context.setRepo.save(persistedSet(workoutId, bench.id, 1, group))
        try await context.setRepo.save(persistedSet(workoutId, fly.id, 9, group))
        try await context.setRepo.save(persistedSet(workoutId, dip.id, 5, group))

        let partners = try await context.setService.supersetPartnerNames(
            workoutIds: [workoutId],
            exerciseId: bench.id
        )

        XCTAssertEqual(partners[workoutId], ["Dip", "Cable Fly"])
    }

    // MARK: - Fixtures

    private func persistedSet(
        _ workoutId: UUID,
        _ exerciseId: UUID,
        _ orderInWorkout: Int,
        _ group: UUID?
    ) -> WorkoutSet {
        WorkoutSet(
            workoutId: workoutId,
            exerciseId: exerciseId,
            weight: 80,
            reps: 8,
            orderInWorkout: orderInWorkout,
            orderInExercise: 1,
            supersetGroupId: group,
            completed: true
        )
    }


    private func makeExercise(_ name: String) -> ChartExerciseData {
        ChartExerciseData(
            from: Exercise(name: name, equipmentType: .barbell, trackingType: .weightReps)
        )
    }

    private func makeChartSet(
        exerciseId: UUID,
        orderInWorkout: Int,
        orderInExercise: Int,
        group: UUID? = nil
    ) -> ChartSetData {
        ChartSetData(from: WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseId,
            weight: 80,
            reps: 8,
            orderInWorkout: orderInWorkout,
            orderInExercise: orderInExercise,
            supersetGroupId: group,
            completed: true
        ))
    }

    private func makeSet(exerciseId: UUID, group: UUID?) -> WorkoutSet {
        WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseId,
            orderInWorkout: 1,
            orderInExercise: 1,
            supersetGroupId: group,
            completed: false
        )
    }

    private func makeContext() throws -> (
        setService: SetService,
        setRepo: SetRepository,
        exerciseRepo: ExerciseRepository
    ) {
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

        return (setService, setRepo, exerciseRepo)
    }
}
