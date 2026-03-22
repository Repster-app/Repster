import XCTest
import SwiftData
@testable import Reppo

@MainActor
final class ChartDataServiceTests: XCTestCase {

    func testBreakdownIgnoresWarmupPartialAndNoDataSets() async throws {
        let context = try makeContext()
        let exercise = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        let workout = makeWorkout(on: makeDate(year: 2026, month: 3, day: 19))

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(
            makeSet(
                workoutId: workout.id,
                exerciseId: exercise.id,
                date: workout.date,
                weight: 100,
                effectiveWeight: 100,
                reps: 5,
                setType: .working,
                orderInWorkout: 1,
                orderInExercise: 1
            )
        )
        try await context.setRepo.save(
            makeSet(
                workoutId: workout.id,
                exerciseId: exercise.id,
                date: workout.date,
                weight: 60,
                effectiveWeight: 60,
                reps: 10,
                setType: .warmup,
                orderInWorkout: 2,
                orderInExercise: 2
            )
        )
        try await context.setRepo.save(
            makeSet(
                workoutId: workout.id,
                exerciseId: exercise.id,
                date: workout.date,
                weight: 110,
                effectiveWeight: 110,
                reps: 3,
                setType: .partial,
                orderInWorkout: 3,
                orderInExercise: 3
            )
        )
        try await context.setRepo.save(
            makeSet(
                workoutId: workout.id,
                exerciseId: exercise.id,
                date: workout.date,
                weight: nil,
                effectiveWeight: nil,
                reps: nil,
                setType: .working,
                orderInWorkout: 4,
                orderInExercise: 4
            )
        )

        let data = try await context.chartService.fetchBreakdownData(
            metric: .volumeByCategory,
            timeRange: .all
        )
        let summary = try await context.chartService.fetchBreakdownSummary(timeRange: .all)

        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data.first?.label, "Chest")
        XCTAssertEqual(data.first?.value ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(summary.totalVolume, 500, accuracy: 0.001)
        XCTAssertEqual(summary.totalSets, 1)
        XCTAssertEqual(summary.totalReps, 5)
        XCTAssertEqual(summary.totalWorkouts, 1)
    }

    func testCalendarThenChartsRegressionDoesNotCrashAndReturnsBreakdownData() async throws {
        let context = try makeContext()
        let exercise = makeExercise(name: "Row", primaryMuscle: "back")
        let workout = makeWorkout(on: makeDate(year: 2026, month: 3, day: 18))

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(
            makeSet(
                workoutId: workout.id,
                exerciseId: exercise.id,
                date: workout.date,
                weight: 80,
                effectiveWeight: 80,
                reps: 8,
                setType: .working,
                orderInWorkout: 1,
                orderInExercise: 1
            )
        )

        let exerciseIds = try await context.setService.fetchExerciseIds(for: workout.id)
        let data = try await context.chartService.fetchBreakdownData(
            metric: .setsByExercise,
            timeRange: .all
        )
        let summary = try await context.chartService.fetchBreakdownSummary(timeRange: .all)

        XCTAssertEqual(exerciseIds, Set([exercise.id]))
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data.first?.label, "Row")
        XCTAssertEqual(data.first?.value ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(summary.totalSets, 1)
        XCTAssertEqual(summary.totalReps, 8)
    }

    func testFetchPerformedExercisesUsesStatsSnapshots() async throws {
        let context = try makeContext()
        let performedExercise = makeExercise(name: "Squat", primaryMuscle: "legs")
        let notPerformedExercise = makeExercise(name: "Curl", primaryMuscle: "arms")

        try await context.exerciseRepo.save(performedExercise)
        try await context.exerciseRepo.save(notPerformedExercise)
        try await context.exerciseStatsRepo.save(
            ExerciseStats(
                exerciseId: performedExercise.id,
                lastPerformedDate: makeDate(year: 2026, month: 3, day: 10)
            )
        )
        try await context.exerciseStatsRepo.save(
            ExerciseStats(
                exerciseId: notPerformedExercise.id,
                lastPerformedDate: nil
            )
        )

        let result = try await context.chartService.fetchPerformedExercises()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, performedExercise.id)
        XCTAssertEqual(result.first?.name, "Squat")
    }

    func testFetchExerciseProgressBuildsSeriesFromSnapshots() async throws {
        let context = try makeContext()
        let exercise = makeExercise(name: "Deadlift", primaryMuscle: "back")
        let firstWorkout = makeWorkout(on: makeDate(year: 2026, month: 1, day: 10))
        let secondWorkout = makeWorkout(on: makeDate(year: 2026, month: 1, day: 17))

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(firstWorkout)
        try await context.workoutRepo.save(secondWorkout)
        try await context.setRepo.save(
            makeSet(
                workoutId: firstWorkout.id,
                exerciseId: exercise.id,
                date: firstWorkout.date,
                weight: 100,
                effectiveWeight: 100,
                reps: 5,
                setType: .working,
                orderInWorkout: 1,
                orderInExercise: 1
            )
        )
        try await context.setRepo.save(
            makeSet(
                workoutId: firstWorkout.id,
                exerciseId: exercise.id,
                date: firstWorkout.date,
                weight: 60,
                effectiveWeight: 60,
                reps: 8,
                setType: .warmup,
                orderInWorkout: 2,
                orderInExercise: 2
            )
        )
        try await context.setRepo.save(
            makeSet(
                workoutId: secondWorkout.id,
                exerciseId: exercise.id,
                date: secondWorkout.date,
                weight: 112.5,
                effectiveWeight: 112.5,
                reps: 4,
                setType: .working,
                orderInWorkout: 1,
                orderInExercise: 1
            )
        )

        let result = try await context.chartService.fetchExerciseProgress(
            metric: .maxWeight,
            exerciseIds: [exercise.id],
            timeRange: .all
        )

        let series = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(series.name, "Deadlift")
        XCTAssertEqual(series.points.count, 2)
        XCTAssertEqual(series.points[0].date, firstWorkout.date)
        XCTAssertEqual(series.points[0].value, 100, accuracy: 0.001)
        XCTAssertEqual(series.points[0].topWeight ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(series.points[0].topReps, 5)
        XCTAssertEqual(series.points[1].date, secondWorkout.date)
        XCTAssertEqual(series.points[1].value, 112.5, accuracy: 0.001)
        XCTAssertEqual(series.points[1].topWeight ?? 0, 112.5, accuracy: 0.001)
        XCTAssertEqual(series.points[1].topReps, 4)
    }

    func testFetchEarliestWorkoutDateReturnsEarliestCompletedWorkoutOnly() async throws {
        let context = try makeContext()
        let inProgress = makeWorkout(
            on: makeDate(year: 2026, month: 1, day: 1),
            status: .inProgress
        )
        let firstCompleted = makeWorkout(
            on: makeDate(year: 2026, month: 1, day: 5),
            status: .completed
        )
        let laterCompleted = makeWorkout(
            on: makeDate(year: 2026, month: 1, day: 12),
            status: .completed
        )

        try await context.workoutRepo.save(inProgress)
        try await context.workoutRepo.save(firstCompleted)
        try await context.workoutRepo.save(laterCompleted)

        let earliest = try await context.chartService.fetchEarliestWorkoutDate()

        XCTAssertEqual(earliest, firstCompleted.date)
    }

    private func makeContext() throws -> ChartDataServiceTestContext {
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
        let chartService = ChartDataService(
            setRepository: setRepo,
            workoutRepository: workoutRepo,
            exerciseRepository: exerciseRepo,
            exerciseStatsRepository: exerciseStatsRepo,
            performanceRecordRepository: performanceRecordRepo
        )

        return ChartDataServiceTestContext(
            chartService: chartService,
            setService: setService,
            setRepo: setRepo,
            workoutRepo: workoutRepo,
            exerciseRepo: exerciseRepo,
            exerciseStatsRepo: exerciseStatsRepo
        )
    }

    private func makeExercise(name: String, primaryMuscle: String) -> Exercise {
        Exercise(
            name: name,
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: primaryMuscle
        )
    }

    private func makeWorkout(on date: Date, status: WorkoutStatus = .completed) -> Workout {
        Workout(
            date: date,
            status: status
        )
    }

    private func makeSet(
        workoutId: UUID,
        exerciseId: UUID,
        date: Date,
        weight: Double?,
        effectiveWeight: Double?,
        reps: Int?,
        setType: SetType,
        orderInWorkout: Int,
        orderInExercise: Int
    ) -> WorkoutSet {
        WorkoutSet(
            workoutId: workoutId,
            exerciseId: exerciseId,
            date: date,
            completedAt: date,
            weight: weight,
            effectiveWeight: effectiveWeight,
            reps: reps,
            setType: setType,
            orderInWorkout: orderInWorkout,
            orderInExercise: orderInExercise,
            completed: true
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date!
    }
}

private struct ChartDataServiceTestContext {
    let chartService: ChartDataService
    let setService: SetService
    let setRepo: SetRepository
    let workoutRepo: WorkoutRepository
    let exerciseRepo: ExerciseRepository
    let exerciseStatsRepo: ExerciseStatsRepository
}
