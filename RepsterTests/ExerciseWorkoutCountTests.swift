import XCTest
import SwiftData
@testable import Repster

/// Coverage for ExerciseStats.totalWorkouts — the "N workouts" counter on the exercise
/// list and detail screens. A workout counts once, from the first set in it that
/// contributes to stats; rows that contribute nothing (the empty placeholder set added
/// with the exercise, warmups while they're excluded, partials) neither establish that
/// membership nor block it.
final class ExerciseWorkoutCountTests: XCTestCase {

    // MARK: - Save

    func testEmptyPlaceholderSetDoesNotCountAsWorkout() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        // Adding an exercise persists an empty working set immediately.
        _ = try await context.setService.save(
            makeSet(fixture, order: 1, weight: nil, reps: nil, completed: false)
        )

        let stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts ?? 0, 0)
    }

    func testWarmupLoggedFirstDoesNotBlockTheWorkoutCount() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        let warmup = makeSet(fixture, order: 1, weight: 40, reps: 10, setType: .warmup)
        _ = try await context.setService.save(warmup)

        var stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts ?? 0, 0, "Warmups are excluded from stats by default")

        let working = makeSet(fixture, order: 2, weight: 100, reps: 5)
        _ = try await context.setService.save(working)

        stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts, 1)
        XCTAssertEqual(stats?.totalSets, 1)
    }

    func testPlaceholderRowsAddedUpFrontDoNotBlockTheWorkoutCount() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        // Three empty rows queued up before anything is logged.
        let rows = (1...3).map { order in
            makeSet(fixture, order: order, weight: nil, reps: nil, completed: false)
        }
        for row in rows {
            _ = try await context.setService.save(row)
        }

        // The user fills in the first one.
        rows[0].weight = 100
        rows[0].reps = 5
        rows[0].completed = true
        _ = try await context.setService.save(rows[0])

        let stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts, 1)
    }

    func testSecondWorkingSetInSameWorkoutDoesNotDoubleCount() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        _ = try await context.setService.save(makeSet(fixture, order: 1, weight: 100, reps: 5))
        _ = try await context.setService.save(makeSet(fixture, order: 2, weight: 100, reps: 5))

        let stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts, 1)
        XCTAssertEqual(stats?.totalSets, 2)
    }

    func testSeparateWorkoutsEachCountOnce() async throws {
        let context = try makeContext()
        let first = try await insertExerciseAndWorkout(in: context)
        let secondWorkout = Workout(
            date: makeDate(2026, 3, 24, 10, 0),
            title: "Session 2",
            startTime: makeDate(2026, 3, 24, 10, 0),
            status: .completed
        )
        try await context.workoutRepo.save(secondWorkout)

        _ = try await context.setService.save(makeSet(first, order: 1, weight: 100, reps: 5))
        _ = try await context.setService.save(
            WorkoutSet(
                workoutId: secondWorkout.id,
                exerciseId: first.exercise.id,
                date: secondWorkout.date,
                weight: 102.5,
                reps: 5,
                setType: .working,
                orderInWorkout: 1,
                orderInExercise: 1,
                completed: true
            )
        )

        let stats = try await context.statsService.fetchStats(for: first.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts, 2)
    }

    // MARK: - Delete

    func testDeletingTheOnlyWorkingSetDecrementsEvenWithWarmupsLeft() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        _ = try await context.setService.save(
            makeSet(fixture, order: 1, weight: 40, reps: 10, setType: .warmup)
        )
        let working = makeSet(fixture, order: 2, weight: 100, reps: 5)
        _ = try await context.setService.save(working)

        try await context.setService.delete(working)

        let stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts ?? -1, 0, "Only a warmup is left — the exercise wasn't performed")
    }

    func testDeletingOneOfTwoWorkingSetsKeepsTheWorkoutCounted() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        let first = makeSet(fixture, order: 1, weight: 100, reps: 5)
        _ = try await context.setService.save(first)
        _ = try await context.setService.save(makeSet(fixture, order: 2, weight: 100, reps: 5))

        try await context.setService.delete(first)

        let stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts, 1)
    }

    // MARK: - Uncomplete / re-complete

    func testUncompleteThenRecompleteCountsTheWorkoutOnce() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        let set = makeSet(fixture, order: 1, weight: 100, reps: 5)
        _ = try await context.setService.save(set)
        _ = try await context.setService.uncomplete(set)

        var stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts ?? -1, 0)

        set.completed = true
        set.completedAt = fixture.workout.date
        _ = try await context.setService.save(set)

        stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts, 1)
        XCTAssertEqual(stats?.totalSets, 1)
    }

    // MARK: - Edit

    func testEditingTheOnlySetToAWarmupDropsTheWorkoutCount() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        let set = makeSet(fixture, order: 1, weight: 100, reps: 5)
        _ = try await context.setService.save(set)

        let previous = SetContributionSnapshot(set: set)
        set.setType = .warmup
        _ = try await context.setService.edit(set, previousContribution: previous)

        let stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts ?? -1, 0)
    }

    func testEditingAWarmupIntoAWorkingSetCountsTheWorkout() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        let set = makeSet(fixture, order: 1, weight: 40, reps: 10, setType: .warmup)
        _ = try await context.setService.save(set)

        let previous = SetContributionSnapshot(set: set)
        set.setType = .working
        _ = try await context.setService.edit(set, previousContribution: previous)

        let stats = try await context.statsService.fetchStats(for: fixture.exercise.id)
        XCTAssertEqual(stats?.totalWorkouts, 1)
    }

    // MARK: - Rebuild parity

    func testRebuildMatchesTheIncrementalCount() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        _ = try await context.setService.save(
            makeSet(fixture, order: 1, weight: nil, reps: nil, completed: false)
        )
        _ = try await context.setService.save(
            makeSet(fixture, order: 2, weight: 40, reps: 10, setType: .warmup)
        )
        _ = try await context.setService.save(makeSet(fixture, order: 3, weight: 100, reps: 5))

        let incremental = try await context.statsService.fetchStats(for: fixture.exercise.id)?.totalWorkouts
        try await context.statsService.rebuild(for: fixture.exercise.id)
        let rebuilt = try await context.statsService.fetchStats(for: fixture.exercise.id)?.totalWorkouts

        XCTAssertEqual(incremental, 1)
        XCTAssertEqual(rebuilt, incremental)
    }

    // MARK: - Backfill migration

    func testBackfillMigrationRepairsStoredCounts() async throws {
        let context = try makeContext()
        let fixture = try await insertExerciseAndWorkout(in: context)

        _ = try await context.setService.save(
            makeSet(fixture, order: 1, weight: 40, reps: 10, setType: .warmup)
        )
        _ = try await context.setService.save(makeSet(fixture, order: 2, weight: 100, reps: 5))

        // Simulate the count left behind by the old row-counting rule.
        let migrationContext = ModelContext(context.modelContainer)
        let stored = try XCTUnwrap(
            try migrationContext.fetch(FetchDescriptor<ExerciseStats>()).first
        )
        stored.totalWorkouts = 0
        try migrationContext.save()

        UserDefaults.standard.removeObject(forKey: "didRunExerciseWorkoutCountBackfill_v1")
        defer { UserDefaults.standard.removeObject(forKey: "didRunExerciseWorkoutCountBackfill_v1") }
        ExerciseWorkoutCountBackfillMigration.runIfNeeded(modelContext: migrationContext)

        let repaired = try XCTUnwrap(
            try ModelContext(context.modelContainer).fetch(FetchDescriptor<ExerciseStats>()).first
        )
        XCTAssertEqual(repaired.totalWorkouts, 1)
    }

    // MARK: - Helpers

    private func makeSet(
        _ fixture: WorkoutCountFixture,
        order: Int,
        weight: Double?,
        reps: Int?,
        setType: SetType = .working,
        completed: Bool = true
    ) -> WorkoutSet {
        WorkoutSet(
            workoutId: fixture.workout.id,
            exerciseId: fixture.exercise.id,
            date: fixture.workout.date,
            completedAt: completed ? fixture.workout.date : nil,
            weight: weight,
            reps: reps,
            setType: setType,
            orderInWorkout: order,
            orderInExercise: order,
            completed: completed
        )
    }

    private func insertExerciseAndWorkout(
        in context: WorkoutCountTestContext
    ) async throws -> WorkoutCountFixture {
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        let date = makeDate(2026, 3, 22, 10, 0)
        let workout = Workout(
            date: date,
            title: "Push",
            startTime: date,
            endTime: date.addingTimeInterval(3_600),
            duration: 3_600,
            status: .completed
        )

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)

        return WorkoutCountFixture(exercise: exercise, workout: workout)
    }

    private func makeContext() throws -> WorkoutCountTestContext {
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

        return WorkoutCountTestContext(
            modelContainer: container,
            setService: setService,
            statsService: statsService,
            exerciseRepo: exerciseRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo
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

private struct WorkoutCountTestContext {
    let modelContainer: ModelContainer
    let setService: SetService
    let statsService: StatsService
    let exerciseRepo: ExerciseRepository
    let workoutRepo: WorkoutRepository
    let setRepo: SetRepository
}

private struct WorkoutCountFixture {
    let exercise: Exercise
    let workout: Workout
}
