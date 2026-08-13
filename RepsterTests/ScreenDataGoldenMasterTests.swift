import XCTest
import SwiftData
@testable import Repster

/// Golden masters for what the read-only screens hand to their views.
///
/// **Why these exist.** The Stage 1 / Stage 2 snapshot conversion changed the *type* of
/// almost everything the UI renders, and the app has no UI test target — no SwiftUI view is
/// constructed anywhere in this suite. So the layer where a silent rendering change would
/// land had zero coverage. The RIR column that nearly shipped blank
/// (SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md §10) is exactly that failure mode: no crash, no
/// error, no failing test.
///
/// These close the gap without a UI target, by asserting one level down: seed a known
/// workout through the **real** service stack against a real SwiftData store, then pin the
/// complete data each screen produces. A view can still be mis-wired, but it can no longer
/// be handed different data than before without something here going red.
///
/// Deliberately end-to-end: real repositories, real `WorkoutService` / `SetService` /
/// `ExerciseService` / `StatsService` / `PRService`, real persistence. The only stubs are
/// for things with no bearing on screen data (HealthKit, analytics).
@MainActor
final class ScreenDataGoldenMasterTests: XCTestCase {

    // MARK: - Fixture

    /// A fixed, hand-checked workout: one bilateral exercise with a warmup and two working
    /// sets (one carrying a note and an RIR), and one unilateral exercise.
    ///
    /// Values are chosen so that every field the detail cards render is non-default —
    /// a snapshot that drops a field shows up as a concrete diff rather than a plausible zero.
    private struct Fixture {
        let container: ModelContainer
        let workoutService: WorkoutService
        let setService: SetService
        let exerciseService: ExerciseService
        let statsService: StatsService
        let chartDataService: ChartDataService
        let workoutId: UUID
        let benchId: UUID
        let lungeId: UUID
        let date: Date
    }

    private func makeFixture() async throws -> Fixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, WorkoutSet.self, ExerciseStats.self,
            PerformanceRecord.self, BodyweightEntry.self, HealthProfile.self,
            FatigueObservation.self, FatigueLearningSetAudit.self,
            configurations: configuration
        )

        let workoutRepo = WorkoutRepository(modelContainer: container)
        let setRepo = SetRepository(modelContainer: container)
        let exerciseRepo = ExerciseRepository(modelContainer: container)
        let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
        let performanceRecordRepo = PerformanceRecordRepository(modelContainer: container)
        let bodyweightRepo = BodyweightEntryRepository(modelContainer: container)
        let healthProfileRepo = HealthProfileRepository(modelContainer: container)
        let fatigueObservationRepo = FatigueObservationRepository(modelContainer: container)
        let fatigueAuditRepo = FatigueLearningSetAuditRepository(modelContainer: container)

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
            auditRepo: fatigueAuditRepo
        )
        let bodyweightService = BodyweightService(
            bodyweightEntryRepository: bodyweightRepo,
            healthProfileRepository: healthProfileRepo
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
        let exerciseService = ExerciseService(
            exerciseRepository: exerciseRepo,
            setRepository: setRepo,
            exerciseStatsRepository: exerciseStatsRepo,
            performanceRecordRepository: performanceRecordRepo,
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
            bodyweightService: bodyweightService,
            healthKitService: NoopHealthKitService()
        )
        let chartDataService = ChartDataService(
            setRepository: setRepo,
            workoutRepository: workoutRepo,
            exerciseRepository: exerciseRepo,
            exerciseStatsRepository: exerciseStatsRepo,
            performanceRecordRepository: performanceRecordRepo
        )

        // Anchor to a fixed point in the current week so week-strip assertions are stable.
        let date = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: Date()
        ) ?? Date()

        let bench = try await exerciseService.createExercise(
            fields: ExerciseEditableFields(
                name: "Bench Press",
                equipmentType: .barbell,
                trackingType: .weightReps,
                primaryMuscle: "chest",
                defaultRestTime: 120
            )
        )
        let lunge = try await exerciseService.createExercise(
            fields: ExerciseEditableFields(
                name: "Dumbbell Lunge",
                equipmentType: .dumbbell,
                trackingType: .weightReps,
                primaryMuscle: "legs",
                unilateral: true
            )
        )

        let workout = Workout(
            date: date,
            title: "Push Day",
            startTime: date,
            status: .inProgress
        )
        try await workoutRepo.save(workout)

        // Bench: warmup + two working sets. Set 2 carries a note and an RIR.
        let warmup = WorkoutSet(
            workoutId: workout.id, exerciseId: bench, date: date,
            weight: 40, reps: 10, setType: .warmup,
            orderInWorkout: 1, orderInExercise: 1, completed: true
        )
        let work1 = WorkoutSet(
            workoutId: workout.id, exerciseId: bench, date: date,
            weight: 100, reps: 5, rir: 2,
            orderInWorkout: 2, orderInExercise: 2, completed: true
        )
        let work2 = WorkoutSet(
            workoutId: workout.id, exerciseId: bench, date: date,
            weight: 100, reps: 8, rir: 1,
            notes: "felt strong", orderInWorkout: 3, orderInExercise: 3, completed: true
        )
        // Lunge: one per-side set.
        let lungeSet = WorkoutSet(
            workoutId: workout.id, exerciseId: lunge, date: date,
            weight: 24, leftReps: 12, rightReps: 10, leftRIR: 1, rightRIR: 2,
            orderInWorkout: 4, orderInExercise: 1, completed: true
        )

        for set in [warmup, work1, work2, lungeSet] {
            _ = try await setService.save(set)
        }

        try await workoutService.finishWorkout(
            workout.id, title: "Push Day", notes: nil,
            perceivedEffort: 8, durationSecondsOverride: 3_600
        )

        return Fixture(
            container: container,
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService,
            statsService: statsService,
            chartDataService: chartDataService,
            workoutId: workout.id,
            benchId: bench,
            lungeId: lunge,
            date: date
        )
    }

    private func makeHomeViewModel(_ fixture: Fixture) -> HomeViewModel {
        HomeViewModel(
            workoutService: fixture.workoutService,
            setService: fixture.setService,
            exerciseService: fixture.exerciseService,
            chartDataService: fixture.chartDataService,
            statsService: fixture.statsService
        )
    }

    private func makeCalendarViewModel(_ fixture: Fixture) -> CalendarViewModel {
        CalendarViewModel(
            workoutService: fixture.workoutService,
            setService: fixture.setService,
            exerciseService: fixture.exerciseService,
            statsService: fixture.statsService
        )
    }

    // MARK: - Home

    func testHomeRecentWorkoutsGoldenMaster() async throws {
        let fixture = try await makeFixture()
        let viewModel = makeHomeViewModel(fixture)

        await viewModel.loadRecentWorkouts()

        XCTAssertEqual(viewModel.recentWorkouts.count, 1)
        let summary = try XCTUnwrap(viewModel.recentWorkouts.first)

        XCTAssertEqual(summary.id, fixture.workoutId)
        XCTAssertEqual(summary.displayTitle, "Push Day")
        XCTAssertEqual(summary.exerciseCount, 2)
        // Working sets with data only — the warmup is excluded.
        XCTAssertEqual(summary.setCount, 3)
        XCTAssertEqual(summary.durationMinutes, 60)
        XCTAssertEqual(Set(summary.muscleGroups), ["chest", "legs"])

        // Volume: bench 100×5 + 100×8, lunge 24×(12+10) — per-side reps count in full.
        let expectedVolume = 100.0 * 5 + 100.0 * 8 + 24.0 * 22
        guard case let .volume(volume)? = summary.primaryMetric else {
            return XCTFail("expected a volume primary metric, got \(String(describing: summary.primaryMetric))")
        }
        XCTAssertEqual(volume, expectedVolume, accuracy: 0.001)
    }

    /// Home shows completed workouts only. The fixture seeds nothing else, so dropping the
    /// status filter entirely went unnoticed (mutation sweep, 2026-08-12) — an in-progress
    /// session would have appeared in Recent Workouts and the week strip while still running.
    func testHomeExcludesInProgressWorkouts() async throws {
        let fixture = try await makeFixture()
        let viewModel = makeHomeViewModel(fixture)

        let inProgress = try await fixture.workoutService.startWorkout()
        let set = WorkoutSet(
            workoutId: inProgress.id, exerciseId: fixture.benchId, date: fixture.date,
            weight: 60, reps: 5, orderInWorkout: 1, orderInExercise: 1, completed: true
        )
        _ = try await fixture.setService.save(set)

        await viewModel.loadData()

        XCTAssertEqual(viewModel.recentWorkouts.count, 1, "only the completed workout")
        XCTAssertEqual(viewModel.recentWorkouts.first?.id, fixture.workoutId)
        XCTAssertFalse(
            viewModel.recentWorkouts.contains { $0.id == inProgress.id },
            "an in-progress workout must not appear in Recent Workouts"
        )
        XCTAssertEqual(
            viewModel.thisWeekWorkoutCount, 1,
            "an in-progress workout must not count toward the weekly total"
        )
    }

    func testHomeWeekStripAndActivityGoldenMaster() async throws {
        let fixture = try await makeFixture()
        let viewModel = makeHomeViewModel(fixture)

        await viewModel.loadData()

        XCTAssertEqual(viewModel.weekDays.count, 7)
        XCTAssertEqual(viewModel.weekDays.map(\.abbreviation), ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"])

        let today = try XCTUnwrap(viewModel.weekDays.first(where: \.isToday))
        XCTAssertTrue(today.hasWorkout, "the seeded workout is today")
        XCTAssertEqual(Set(today.muscleGroups), ["chest", "legs"])
        XCTAssertEqual(viewModel.weekDays.filter(\.hasWorkout).count, 1)
        XCTAssertEqual(viewModel.thisWeekWorkoutCount, 1)

        // Finished workout → no active workout banner.
        XCTAssertFalse(viewModel.hasActiveWorkout)
        XCTAssertNil(viewModel.activeWorkoutStartTime)
    }

    func testHomeActiveWorkoutDetectionGoldenMaster() async throws {
        let fixture = try await makeFixture()
        let viewModel = makeHomeViewModel(fixture)

        // A second, still-running workout with one completed set.
        let workout = try await fixture.workoutService.startWorkout()
        let set = WorkoutSet(
            workoutId: workout.id, exerciseId: fixture.benchId, date: Date(),
            weight: 60, reps: 5, orderInWorkout: 1, orderInExercise: 1, completed: true
        )
        _ = try await fixture.setService.save(set)

        await viewModel.checkActiveWorkout()

        XCTAssertTrue(viewModel.hasActiveWorkout)
        XCTAssertNotNil(viewModel.activeWorkoutStartTime)
        XCTAssertEqual(viewModel.activeWorkoutExerciseCount, 1)
        XCTAssertEqual(viewModel.activeWorkoutSetCount, 1)
    }

    func testHomeRecentPRsGoldenMaster() async throws {
        let fixture = try await makeFixture()
        let viewModel = makeHomeViewModel(fixture)

        await viewModel.loadData()

        // The seeded sets are the first of their kind, so they own PRs.
        XCTAssertFalse(viewModel.recentPRs.isEmpty, "seeded sets should have produced PRs")

        let names = Set(viewModel.recentPRs.map(\.exerciseName))
        XCTAssertTrue(names.isSubset(of: ["Bench Press", "Dumbbell Lunge"]))

        if let bench = viewModel.recentPRs.first(where: { $0.exerciseName == "Bench Press" }) {
            XCTAssertEqual(bench.weight, 100)
            XCTAssertFalse(bench.isPerSide, "bench is bilateral")
        }
        if let lunge = viewModel.recentPRs.first(where: { $0.exerciseName == "Dumbbell Lunge" }) {
            XCTAssertTrue(lunge.isPerSide, "lunge is unilateral with per-side logging")
        }
    }

    // MARK: - Calendar

    func testCalendarDotsGoldenMaster() async throws {
        let fixture = try await makeFixture()
        let viewModel = makeCalendarViewModel(fixture)

        await viewModel.loadAllDots()

        let key = CalendarViewModel.normalizeDate(fixture.date)
        XCTAssertEqual(viewModel.workoutsByDate[key]?.count, 1)
        XCTAssertEqual(viewModel.workoutsByDate[key]?.first?.displayTitle, "Push Day")
        XCTAssertEqual(Set(viewModel.calendarDotData[key] ?? []), ["chest", "legs"])
        XCTAssertNotNil(viewModel.earliestWorkoutDate)
    }

    /// The big one: `selectDate` builds the `WorkoutDetail` tree that both detail screens
    /// render. Every field asserted here is one a card puts on screen.
    func testCalendarWorkoutDetailGoldenMaster() async throws {
        let fixture = try await makeFixture()
        let viewModel = makeCalendarViewModel(fixture)

        await viewModel.loadAllDots()
        await viewModel.selectDate(fixture.date)

        let details = viewModel.selectedDateWorkoutDetails
        XCTAssertEqual(details.count, 1)
        let detail = try XCTUnwrap(details.first)

        // Header / summary strip
        XCTAssertEqual(detail.workout.id, fixture.workoutId)
        XCTAssertEqual(detail.workout.displayTitle, "Push Day")
        XCTAssertEqual(detail.workout.duration, 3_600)
        XCTAssertEqual(detail.workout.status, .completed)
        XCTAssertEqual(detail.exerciseCount, 2)
        XCTAssertEqual(detail.setCount, 4, "all four sets have data, warmups included")

        // Exercise ordering follows orderInWorkout — bench before lunge.
        XCTAssertEqual(detail.exerciseGroups.map(\.exercise.name), ["Bench Press", "Dumbbell Lunge"])

        // Bench group: set ordering is warmup-first via orderInExercise.
        let bench = try XCTUnwrap(detail.exerciseGroups.first)
        XCTAssertEqual(bench.sets.map(\.orderInExercise), [1, 2, 3])
        XCTAssertEqual(bench.sets.map(\.setType), [.warmup, .working, .working])
        XCTAssertEqual(bench.sets.map(\.reps), [10, 5, 8])

        // RIR must survive the snapshot — this is the field that nearly shipped blank.
        XCTAssertEqual(bench.sets.map(\.rir), [nil, 2, 1])

        // Note dots.
        XCTAssertEqual(bench.sets.map(\.hasNote), [false, false, true])
        XCTAssertEqual(bench.sets.last?.notes, "felt strong")

        // Per-side data on the unilateral exercise.
        let lunge = try XCTUnwrap(detail.exerciseGroups.last)
        let lungeSet = try XCTUnwrap(lunge.sets.first)
        XCTAssertEqual(lungeSet.leftReps, 12)
        XCTAssertEqual(lungeSet.rightReps, 10)
        XCTAssertEqual(lungeSet.leftRIR, 1)
        XCTAssertEqual(lungeSet.rightRIR, 2)
        XCTAssertTrue(lunge.exercise.unilateral)
        XCTAssertTrue(lunge.exercise.supportsUnilateralLogging)
    }

    /// What the detail card actually renders per column, end to end from seeded data.
    /// Catches a formatter/snapshot mismatch that field-level assertions would miss.
    func testWorkoutDetailCardRenderedColumnsGoldenMaster() async throws {
        let fixture = try await makeFixture()
        let viewModel = makeCalendarViewModel(fixture)

        await viewModel.loadAllDots()
        await viewModel.selectDate(fixture.date)

        let detail = try XCTUnwrap(viewModel.selectedDateWorkoutDetails.first)
        let bench = try XCTUnwrap(detail.exerciseGroups.first)
        let fields = WorkoutSetPerformanceFormatter.readOnlyFields(for: bench.exercise.trackingType)
        XCTAssertEqual(fields, [.weight, .reps, .rir])

        let rendered = bench.sets.map { set in
            fields.map { field in
                WorkoutSetPerformanceFormatter.fieldDisplay(
                    for: field,
                    set: set,
                    exercise: bench.exercise,
                    unitPreference: .metric
                ).text
            }
        }

        XCTAssertEqual(rendered, [
            ["40 kg", "10", "—"],   // warmup, no RIR logged
            ["100 kg", "5", "2"],
            ["100 kg", "8", "1"],
        ])
    }

    /// Editing a workout must be reflected on the detail screen after the explicit reload.
    /// Snapshots are frozen, so this is the staleness risk §10 of the crash analysis names.
    func testDetailReflectsEditedTitleAfterReload() async throws {
        let fixture = try await makeFixture()
        let viewModel = makeCalendarViewModel(fixture)

        await viewModel.loadAllDots()
        await viewModel.selectDate(fixture.date)
        XCTAssertEqual(viewModel.selectedDateWorkoutDetails.first?.workout.displayTitle, "Push Day")

        try await fixture.workoutService.updateWorkoutMetadata(
            fixture.workoutId, notes: "edited", perceivedEffort: 9
        )
        // Calendar reloads dots + detail on return from the edit sheet.
        await viewModel.reloadAllDots()
        await viewModel.selectDate(fixture.date)

        let detail = try XCTUnwrap(viewModel.selectedDateWorkoutDetails.first)
        XCTAssertEqual(detail.workout.id, fixture.workoutId)
        XCTAssertEqual(detail.exerciseGroups.count, 2, "reload must rebuild the full detail tree")
    }
}
