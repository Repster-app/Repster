import XCTest
import SwiftData
@testable import Repster

final class InsightsServiceTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        // Refire cooldowns and the analysis cache live in UserDefaults, so
        // without this a rule that fired in an earlier test stays suppressed here.
        InsightsService.resetPersistedAnalysisState()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Workout.self,
            WorkoutSet.self,
            Exercise.self,
            HealthProfile.self,
            FatigueObservation.self,
            InsightRecord.self,
            configurations: config
        )
    }

    override func tearDown() {
        InsightsService.resetPersistedAnalysisState()
        container = nil
    }

    // MARK: - Helpers

    private func makeService() -> InsightsService {
        InsightsService(modelContainer: container)
    }

    @MainActor
    private func seed(_ models: [any PersistentModel]) throws {
        let context = ModelContext(container)
        for model in models {
            context.insert(model)
        }
        try context.save()
    }

    private func makeExercise(name: String, primaryMuscle: String) -> Exercise {
        Exercise(
            name: name,
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: primaryMuscle
        )
    }

    @MainActor
    private func seedWorkout(
        date: Date,
        sets: [(exercise: Exercise, weight: Double, reps: Int, rest: Int?, prStatus: CachedPRStatus?)]
    ) throws {
        let workout = Workout(date: date, startTime: date, status: .completed)
        let workoutSets = sets.enumerated().map { index, spec in
            WorkoutSet(
                workoutId: workout.id,
                exerciseId: spec.exercise.id,
                date: date,
                completedAt: date.addingTimeInterval(Double(index) * 180),
                weight: spec.weight,
                effectiveWeight: spec.weight,
                reps: spec.reps,
                setType: .working,
                orderInWorkout: index,
                orderInExercise: index,
                completed: true,
                cachedPRStatus: spec.prStatus,
                restDurationSeconds: spec.rest
            )
        }
        try seed([workout] + workoutSets)
    }

    private func daysAgo(_ days: Int, from reference: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: reference)!
    }

    /// Sets with no weight at all — `effectiveWeight` nil, which is what makes
    /// `WorkoutSet.volume` nil rather than zero.
    @MainActor
    private func seedBodyweightWorkout(
        date: Date,
        exercise: Exercise,
        setCount: Int,
        reps: Int
    ) throws {
        let workout = Workout(date: date, startTime: date, status: .completed)
        let sets = (0..<setCount).map { index in
            WorkoutSet(
                workoutId: workout.id,
                exerciseId: exercise.id,
                date: date,
                completedAt: date,
                reps: reps,
                setType: .working,
                orderInWorkout: index,
                orderInExercise: index,
                completed: true
            )
        }
        try seed([workout] + sets)
    }

    private func makeBiasedObservations(
        exerciseId: UUID,
        bias: Double,
        count: Int = 12,
        reference: Date
    ) -> [FatigueObservation] {
        (0..<count).map { index in
            FatigueObservation(
                exerciseId: exerciseId,
                workoutId: UUID(),
                setId: UUID(),
                setIndex: index % 3,
                predictedEffectiveE1RM: 100 * (1 + bias),
                actualE1RM: 100,
                normalizedError: bias,
                baseE1RM: 100,
                prescribedWeight: 80,
                actualWeight: 80,
                actualReps: 8,
                actualRIR: 2,
                createdAt: daysAgo(index, from: reference)
            )
        }
    }

    /// Seeds `weeks` weeks of history, `setsPerWeek` sets each week, one workout
    /// per week ending `endingDaysAgo` days before the reference date.
    @MainActor
    private func seedWeekly(
        exercise: Exercise,
        weeks: Int,
        setsPerWeek: Int,
        from reference: Date,
        startingWeeksAgo: Int
    ) throws {
        for week in 0..<weeks {
            let date = daysAgo((startingWeeksAgo - week) * 7, from: reference)
            try seedWorkout(
                date: date,
                sets: (0..<setsPerWeek).map { _ in (exercise, 80.0, 8, 120, nil) }
            )
        }
    }

    /// Workout whose sets carry an explicit e1RM and session RPE — the inputs
    /// the strength-trend and readiness rules actually read.
    @MainActor
    private func seedSession(
        date: Date,
        exercises: [Exercise],
        e1RM: Double,
        setsPerExercise: Int = 3,
        effort: Double? = nil
    ) throws {
        let workout = Workout(date: date, startTime: date, status: .completed)
        workout.perceivedEffort = effort
        var sets: [WorkoutSet] = []
        var order = 0
        for exercise in exercises {
            for index in 0..<setsPerExercise {
                sets.append(WorkoutSet(
                    workoutId: workout.id,
                    exerciseId: exercise.id,
                    date: date,
                    completedAt: date,
                    weight: 80,
                    effectiveWeight: 80,
                    reps: 8,
                    e1RM: e1RM,
                    setType: .working,
                    orderInWorkout: order,
                    orderInExercise: index,
                    completed: true
                ))
                order += 1
            }
        }
        try seed([workout] + sets)
    }

    // MARK: - Strength trend

    @MainActor
    func testStrengthTrendReportsARisingLift() async throws {
        let service = makeService()
        let now = Date()
        let squat = makeExercise(name: "Back Squat", primaryMuscle: "legs")
        try seed([squat])

        for (days, e1RM) in [(50, 100.0), (35, 101.0), (20, 110.0), (5, 112.0)] {
            try seedSession(date: daysAgo(days, from: now), exercises: [squat], e1RM: e1RM)
        }

        try await service.runAnalysis(referenceDate: now)
        let insights = try await service.fetchActiveInsights()
        let trend = insights.first { $0.ruleId == "strengthTrend" }

        XCTAssertNotNil(trend, "A 10% climb over 45 days should surface")
        XCTAssertTrue(trend?.headline.contains("up") ?? false, "Got: \(trend?.headline ?? "nil")")
        XCTAssertEqual(trend?.chartKind, .series)
    }

    // MARK: - Deload readiness

    /// Builds a fatigued-looking history: three lifts regressing ~6% over the
    /// last two weeks with effort ratings climbing.
    @MainActor
    private func seedFatiguePattern(
        now: Date,
        exercises: [Exercise],
        recentSetsPerExercise: Int
    ) throws {
        // Prior window: 12 sessions across days 15–56, strong and easy.
        for index in 0..<12 {
            try seedSession(
                date: daysAgo(56 - index * 3, from: now),
                exercises: exercises,
                e1RM: 100,
                setsPerExercise: 3,
                effort: 5
            )
        }
        // Recent window: 4 sessions in the last 14 days, weaker and harder.
        for index in 0..<4 {
            try seedSession(
                date: daysAgo(13 - index * 3, from: now),
                exercises: exercises,
                e1RM: 94,
                setsPerExercise: recentSetsPerExercise,
                effort: 8
            )
        }
    }

    @MainActor
    func testDeloadReadinessFiresOnCorroboratedRegression() async throws {
        let service = makeService()
        let now = Date()
        let exercises = [
            makeExercise(name: "Back Squat", primaryMuscle: "legs"),
            makeExercise(name: "Bench Press", primaryMuscle: "chest"),
            makeExercise(name: "Deadlift", primaryMuscle: "back")
        ]
        try seed(exercises)
        try seedFatiguePattern(now: now, exercises: exercises, recentSetsPerExercise: 3)

        try await service.runAnalysis(referenceDate: now)
        let insights = try await service.fetchActiveInsights()

        XCTAssertNotNil(
            insights.first { $0.ruleId == "deloadReadiness" },
            "Three lifts down 6% with effort up and volume held should fire. Got: \(insights.map(\.ruleId))"
        )
    }

    @MainActor
    func testDeloadReadinessStaysQuietWhenVolumeDropped() async throws {
        let service = makeService()
        let now = Date()
        let exercises = [
            makeExercise(name: "Back Squat", primaryMuscle: "legs"),
            makeExercise(name: "Bench Press", primaryMuscle: "chest"),
            makeExercise(name: "Deadlift", primaryMuscle: "back")
        ]
        try seed(exercises)
        // Same regression, but a third of the sets — this is a lighter fortnight,
        // not accumulated fatigue, and calling it fatigue is the single most
        // embarrassing way the rule could be wrong.
        try seedFatiguePattern(now: now, exercises: exercises, recentSetsPerExercise: 1)

        try await service.runAnalysis(referenceDate: now)
        let insights = try await service.fetchActiveInsights()

        XCTAssertNil(
            insights.first { $0.ruleId == "deloadReadiness" },
            "Detraining must not be reported as fatigue"
        )
    }

    @MainActor
    func testDeloadReadinessRespectsItsRefireInterval() async throws {
        let service = makeService()
        let now = Date()
        let exercises = [
            makeExercise(name: "Back Squat", primaryMuscle: "legs"),
            makeExercise(name: "Bench Press", primaryMuscle: "chest"),
            makeExercise(name: "Deadlift", primaryMuscle: "back")
        ]
        try seed(exercises)
        try seedFatiguePattern(now: now, exercises: exercises, recentSetsPerExercise: 3)

        try await service.runAnalysis(referenceDate: now)
        let first = try await service.fetchActiveInsights()
        XCTAssertNotNil(first.first { $0.ruleId == "deloadReadiness" })

        // Two days later the pattern still holds, but the rule must stay quiet.
        try await service.runAnalysis(referenceDate: now.addingTimeInterval(2 * 86_400))
        let second = try await service.fetchActiveInsights()

        XCTAssertNil(
            second.first { $0.ruleId == "deloadReadiness" },
            "A serious finding that reappears every day is nagging, not advice"
        )
    }

    // MARK: - Curation

    private func scored(_ ruleId: String, _ tone: InsightTone, _ score: Double) -> InsightsService.Scored {
        InsightsService.Scored(
            finding: InsightFinding(
                ruleId: ruleId, subjectId: nil, subjectName: nil,
                headline: ruleId, detailText: "", methodologyText: "",
                chartKind: .ranking, chartLabels: [], chartValues: [],
                effectSize: score, tone: tone
            ),
            score: score
        )
    }

    func testCurationCapsDiagnosticCards() {
        let curated = InsightsService.curate([
            scored("a", .diagnostic, 0.9),
            scored("b", .diagnostic, 0.8),
            scored("c", .diagnostic, 0.7),
            scored("d", .progress, 0.2)
        ])

        XCTAssertEqual(curated.count, 3)
        XCTAssertEqual(curated.filter { $0.finding.tone == .diagnostic }.count, 2)
        XCTAssertTrue(
            curated.contains { $0.finding.ruleId == "d" },
            "A lower-scoring progress card should claim the last slot once the diagnostic budget is spent"
        )
    }

    func testCurationKeepsOneCardPerRule() {
        let curated = InsightsService.curate([
            scored("a", .neutral, 0.4),
            scored("a", .neutral, 0.9),
            scored("b", .neutral, 0.5)
        ])

        XCTAssertEqual(curated.count, 2)
        XCTAssertEqual(curated.first { $0.finding.ruleId == "a" }?.score, 0.9)
    }

    // MARK: - Positive floor

    @MainActor
    func testFeedFallsBackToADescriptiveFindingRatherThanNothing() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])

        // Six weeks of steady, unremarkable training: nothing regresses, nothing
        // ramps, no group is neglected. v1 would show an empty feed here.
        for week in 0..<6 {
            for session in 0..<2 {
                try seedSession(
                    date: daysAgo(42 - week * 7 - session * 3, from: now),
                    exercises: [bench],
                    e1RM: 100
                )
            }
        }

        try await service.runAnalysis(referenceDate: now)
        let insights = try await service.fetchActiveInsights()

        XCTAssertFalse(
            insights.isEmpty,
            "Once there's history the feed should always have something to say"
        )
        XCTAssertLessThanOrEqual(insights.count, InsightsService.maxVisibleInsights)
    }

    // MARK: - Training status

    @MainActor
    func testStatusComparesTrailingWeekAgainstBaseline() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])

        // 8 baseline weeks at 10 sets, then 4 sets in the trailing week.
        try seedWeekly(exercise: bench, weeks: 8, setsPerWeek: 10, from: now, startingWeeksAgo: 9)
        try seedWorkout(date: daysAgo(2, from: now), sets: (0..<4).map { _ in (bench, 80.0, 8, 120, nil) })

        let status = try await service.trainingStatus(referenceDate: now)

        XCTAssertEqual(status.currentSets, 4)
        XCTAssertNotNil(status.baselineSets)
        XCTAssertEqual(status.baselineSets ?? 0, 10, accuracy: 1.5)
        XCTAssertEqual(status.band, .wellBelow)
    }

    @MainActor
    func testStatusRanksByBaselineSoASkippedGroupStaysVisible() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        let curl = makeExercise(name: "Curl", primaryMuscle: "biceps")
        try seed([bench, curl])

        // Chest is the user's biggest group historically but got skipped this
        // week; biceps is small but was trained.
        try seedWeekly(exercise: bench, weeks: 8, setsPerWeek: 12, from: now, startingWeeksAgo: 9)
        try seedWeekly(exercise: curl, weeks: 8, setsPerWeek: 3, from: now, startingWeeksAgo: 9)
        try seedWorkout(date: daysAgo(2, from: now), sets: (0..<3).map { _ in (curl, 20.0, 10, 90, nil) })

        let status = try await service.trainingStatus(referenceDate: now)

        XCTAssertEqual(
            status.muscles.first?.group, "chest",
            "Ranking by current volume would bury the skipped group — which is the one worth seeing"
        )
        let chest = status.muscles.first { $0.group == "chest" }
        XCTAssertEqual(chest?.currentSets, 0)
        XCTAssertTrue(chest?.isAbsent ?? false)
        XCTAssertLessThan(chest?.delta ?? 0, 0)
    }

    @MainActor
    func testStatusHasNoBaselineDuringColdStart() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])

        // Ten days of history — not enough to average against.
        try seedWorkout(date: daysAgo(9, from: now), sets: (0..<5).map { _ in (bench, 80.0, 8, 120, nil) })
        try seedWorkout(date: daysAgo(2, from: now), sets: (0..<5).map { _ in (bench, 80.0, 8, 120, nil) })

        let status = try await service.trainingStatus(referenceDate: now)

        XCTAssertTrue(status.hasData)
        XCTAssertEqual(status.currentSets, 5)
        XCTAssertNil(status.baselineSets, "A baseline from one thin week is worse than no baseline")
        XCTAssertNil(status.band)
        XCTAssertNil(status.muscles.first?.delta)
        XCTAssertFalse(status.muscles.first?.isAbsent ?? true)
    }

    // MARK: - Muscle panel metrics

    @MainActor
    func testMuscleRowsCountRepsAndVolumeAlongsideSets() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])

        // 4 sets this week at 80kg x 8 = 32 reps, 2560kg.
        try seedWorkout(date: daysAgo(2, from: now), sets: (0..<4).map { _ in (bench, 80.0, 8, 120, nil) })

        let status = try await service.trainingStatus(referenceDate: now)
        let chest = try XCTUnwrap(status.muscles.first { $0.group == "chest" })

        XCTAssertEqual(chest.currentSets, 4)
        XCTAssertEqual(chest.currentReps, 32)
        XCTAssertEqual(chest.currentVolume, 2_560, accuracy: 0.001)
    }

    @MainActor
    func testMuscleRowBaselinesAreAveragedPerMetric() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])

        // 8 baseline weeks of 10 sets at 80kg x 8: 80 reps and 6400kg a week.
        try seedWeekly(exercise: bench, weeks: 8, setsPerWeek: 10, from: now, startingWeeksAgo: 9)
        try seedWorkout(date: daysAgo(2, from: now), sets: (0..<4).map { _ in (bench, 80.0, 8, 120, nil) })

        let status = try await service.trainingStatus(referenceDate: now)
        let chest = try XCTUnwrap(status.muscles.first { $0.group == "chest" })

        XCTAssertEqual(try XCTUnwrap(chest.baselineReps), 80, accuracy: 12)
        XCTAssertEqual(try XCTUnwrap(chest.baselineVolume), 6_400, accuracy: 960)
        // All three metrics must agree on direction — this week ran light.
        for metric in MuscleMetric.allCases {
            let delta = try XCTUnwrap(chest.delta(for: metric), "\(metric) delta")
            XCTAssertLessThan(delta, 0, "\(metric) should read below baseline")
        }
    }

    /// Bodyweight work carries no weight, so it has sets and reps but no volume.
    /// The volume view must not mistake that for a skipped group.
    @MainActor
    func testBodyweightSetsCountForRepsButContributeNoVolume() async throws {
        let service = makeService()
        let now = Date()
        let pullup = makeExercise(name: "Pull Up", primaryMuscle: "back")
        try seed([pullup])
        try seedBodyweightWorkout(date: daysAgo(2, from: now), exercise: pullup, setCount: 5, reps: 10)

        let status = try await service.trainingStatus(referenceDate: now)
        let back = try XCTUnwrap(status.muscles.first { $0.group == "back" })

        XCTAssertEqual(back.currentSets, 5)
        XCTAssertEqual(back.currentReps, 50)
        XCTAssertEqual(back.currentVolume, 0)
        XCTAssertTrue(back.hasVolumeGap, "Trained with no weight is not the same as untrained")
        XCTAssertFalse(back.isAbsent, "The group was trained — absent must stay defined on sets")
    }

    /// Unilateral sets record each side separately; reps must count both.
    @MainActor
    func testUnilateralSetsCountBothSidesInReps() async throws {
        let service = makeService()
        let now = Date()
        let split = makeExercise(name: "Split Squat", primaryMuscle: "quads")
        let date = daysAgo(2, from: now)
        let workout = Workout(date: date, startTime: date, status: .completed)
        let sets = (0..<3).map { index in
            WorkoutSet(
                workoutId: workout.id,
                exerciseId: split.id,
                date: date,
                completedAt: date,
                weight: 40,
                effectiveWeight: 40,
                leftReps: 8,
                rightReps: 8,
                setType: .working,
                orderInWorkout: index,
                orderInExercise: index,
                completed: true
            )
        }
        try seed([split, workout] + sets)

        let status = try await service.trainingStatus(referenceDate: now)
        let quads = try XCTUnwrap(status.muscles.first { $0.group == "quads" })

        XCTAssertEqual(quads.currentSets, 3)
        XCTAssertEqual(quads.currentReps, 48, "8 + 8 per set across 3 sets")
        XCTAssertEqual(quads.currentVolume, 40 * 48, accuracy: 0.001)
    }

    @MainActor
    func testColdStartLeavesEveryMetricWithoutABaseline() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])
        try seedWorkout(date: daysAgo(2, from: now), sets: (0..<5).map { _ in (bench, 80.0, 8, 120, nil) })

        let status = try await service.trainingStatus(referenceDate: now)
        let chest = try XCTUnwrap(status.muscles.first)

        for metric in MuscleMetric.allCases {
            XCTAssertNil(chest.baseline(for: metric), "\(metric) baseline")
            XCTAssertNil(chest.delta(for: metric), "\(metric) delta")
        }
    }

    /// The status fetch only reaches back as far as the baseline window, but how
    /// much history exists before that is what decides whether there's a
    /// baseline at all. A user coming back after a long break must not be
    /// mistaken for one who has never trained.
    @MainActor
    func testStatusAccountsForHistoryOlderThanTheWindow() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])

        // Twelve weeks of training that ended long before the nine-week window,
        // then one session this week.
        try seedWeekly(exercise: bench, weeks: 12, setsPerWeek: 10, from: now, startingWeeksAgo: 34)
        try seedWorkout(date: daysAgo(2, from: now), sets: (0..<5).map { _ in (bench, 80.0, 8, 120, nil) })

        let status = try await service.trainingStatus(referenceDate: now)

        XCTAssertTrue(status.hasData)
        XCTAssertEqual(status.currentSets, 5)
        XCTAssertEqual(
            status.baselineSets ?? -1, 0, accuracy: 0.001,
            "Eight baseline weeks are available and empty — that isn't the same as having none"
        )
    }

    @MainActor
    func testStatusReportsNoDataForAnUntouchedStore() async throws {
        let service = makeService()
        let status = try await service.trainingStatus(referenceDate: Date())

        XCTAssertFalse(status.hasData)
        XCTAssertEqual(status.currentSets, 0)
        XCTAssertNil(status.baselineSets)
        XCTAssertTrue(status.muscles.isEmpty)
    }

    @MainActor
    func testStatusExcludesCardioAndFullBody() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        let row = makeExercise(name: "Rower", primaryMuscle: "cardio")
        let burpee = makeExercise(name: "Burpee", primaryMuscle: "full body")
        try seed([bench, row, burpee])

        try seedWeekly(exercise: bench, weeks: 8, setsPerWeek: 6, from: now, startingWeeksAgo: 9)
        try seedWorkout(date: daysAgo(1, from: now), sets: [
            (bench, 80.0, 8, 120, nil), (row, 0.0, 30, nil, nil), (burpee, 0.0, 20, nil, nil)
        ])

        let status = try await service.trainingStatus(referenceDate: now)
        let groups = status.muscles.map(\.group)

        XCTAssertTrue(groups.contains("chest"))
        XCTAssertFalse(groups.contains("cardio"), "Cardio isn't a muscle group and distorts the ranking")
        XCTAssertFalse(groups.contains("full body"))
        XCTAssertEqual(status.currentSets, 1, "Only the chest set counts toward the trailing total")
    }

    @MainActor
    func testStatusIncludesCustomMuscleGroups() async throws {
        let service = makeService()
        let now = Date()
        // Not one of the ten catalog entries. ExerciseMuscleGroupCatalog
        // .orderedValues would silently drop this; the panel must not use it.
        let raise = makeExercise(name: "Calf Raise", primaryMuscle: "calves")
        try seed([raise])

        try seedWeekly(exercise: raise, weeks: 8, setsPerWeek: 4, from: now, startingWeeksAgo: 9)
        try seedWorkout(date: daysAgo(1, from: now), sets: (0..<4).map { _ in (raise, 60.0, 15, 60, nil) })

        let status = try await service.trainingStatus(referenceDate: now)
        let calves = status.muscles.first { $0.group == "calves" }

        XCTAssertNotNil(calves, "Groups come from the user's own exercises, not a fixed enum")
        XCTAssertEqual(calves?.displayName, "Calves")
        XCTAssertEqual(calves?.currentSets, 4)
    }

    @MainActor
    func testStatusRespectsProgressionExclusionFlags() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])
        try seedWeekly(exercise: bench, weeks: 8, setsPerWeek: 6, from: now, startingWeeksAgo: 9)

        let context = ModelContext(container)
        let excluded = Workout(date: daysAgo(1, from: now), status: .completed)
        excluded.excludeFromProgressionHistory = true
        let sets = (0..<5).map { index in
            WorkoutSet(
                workoutId: excluded.id, exerciseId: bench.id, date: daysAgo(1, from: now),
                completedAt: daysAgo(1, from: now), weight: 80, effectiveWeight: 80, reps: 8,
                setType: .working, orderInWorkout: index, orderInExercise: index, completed: true
            )
        }
        context.insert(excluded)
        sets.forEach { context.insert($0) }
        try context.save()

        let status = try await service.trainingStatus(referenceDate: now)

        XCTAssertEqual(status.currentSets, 0, "A workout excluded from progression history must not count")
    }

    // MARK: - Analysis signature

    @MainActor
    func testSignatureChangesWithTheDaySoRollingWindowsStayFresh() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])
        try seedWorkout(date: daysAgo(2, from: now), sets: [(bench, 80, 8, 120, nil)])

        let today = try await service.currentDataSignature(referenceDate: now)
        let laterToday = try await service.currentDataSignature(
            referenceDate: now.addingTimeInterval(60)
        )
        let tomorrow = try await service.currentDataSignature(
            referenceDate: Calendar.current.date(byAdding: .day, value: 1, to: now)!
        )

        XCTAssertEqual(today, laterToday, "Same day with unchanged data must not re-run the pipeline")
        XCTAssertNotEqual(
            today, tomorrow,
            "Every rule evaluates over a window relative to the reference date. Without a day component the analysis freezes as soon as the user stops training."
        )
    }

    @MainActor
    func testSignatureChangesWhenAWorkoutIsLogged() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])
        try seedWorkout(date: daysAgo(2, from: now), sets: [(bench, 80, 8, 120, nil)])

        let before = try await service.currentDataSignature(referenceDate: now)
        try seedWorkout(date: daysAgo(1, from: now), sets: [(bench, 82.5, 8, 120, nil)])
        let after = try await service.currentDataSignature(referenceDate: now)

        XCTAssertNotEqual(before, after, "A newly completed workout must invalidate the cached analysis")
    }

    // MARK: - Gating

    @MainActor
    func testNoInsightsWithInsufficientData() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])

        // One small workout — far below every rule's gate.
        try seedWorkout(
            date: daysAgo(2, from: now),
            sets: [(bench, 80, 8, 120, nil)]
        )

        try await service.runAnalysis(referenceDate: now)
        let insights = try await service.fetchActiveInsights()

        XCTAssertTrue(insights.isEmpty, "Sparse data must produce zero insights, got: \(insights.map(\.ruleId))")
    }

    // MARK: - RIR calibration rule

    @MainActor
    func testRIRCalibrationDetectsConsistentSandbagging() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])

        // 12 observations where the user consistently beat the prediction by 6%.
        try seed(makeBiasedObservations(exerciseId: bench.id, bias: -0.06, reference: now))

        try await service.runAnalysis(referenceDate: now)
        let insights = try await service.fetchActiveInsights()

        let calibration = insights.first { $0.ruleId == "rirCalibration" }
        XCTAssertNotNil(calibration, "Consistent -6% bias across 12 observations should fire the calibration rule")
        XCTAssertTrue(calibration?.headline.contains("Bench Press") ?? false)
        XCTAssertTrue(calibration?.isNew ?? false)
    }

    @MainActor
    func testRIRCalibrationStaysQuietWhenUnbiased() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])

        // Alternating small errors — no systematic bias.
        let observations = (0..<12).map { index in
            FatigueObservation(
                exerciseId: bench.id,
                workoutId: UUID(),
                setId: UUID(),
                setIndex: index % 3,
                predictedEffectiveE1RM: 100,
                actualE1RM: 100,
                normalizedError: index.isMultiple(of: 2) ? 0.01 : -0.01,
                baseE1RM: 100,
                prescribedWeight: 80,
                actualWeight: 80,
                actualReps: 8,
                actualRIR: 2,
                createdAt: daysAgo(index, from: now)
            )
        }
        try seed(observations)

        try await service.runAnalysis(referenceDate: now)
        let insights = try await service.fetchActiveInsights()

        XCTAssertFalse(insights.contains { $0.ruleId == "rirCalibration" })
    }

    // MARK: - Muscle balance rule

    @MainActor
    func testMuscleBalanceFlagsNeglectedGroup() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        let squat = makeExercise(name: "Squat", primaryMuscle: "quads")
        let row = makeExercise(name: "Row", primaryMuscle: "back")
        try seed([bench, squat, row])

        // 8 sessions over 6 weeks: back trained early on, then dropped for the
        // last two weeks while chest and quads keep getting ~8 sets each.
        for sessionIndex in 0..<8 {
            let date = daysAgo(42 - sessionIndex * 5, from: now)
            var sets: [(Exercise, Double, Int, Int?, CachedPRStatus?)] = []
            for _ in 0..<4 {
                sets.append((bench, 80, 8, nil, nil))
                sets.append((squat, 100, 8, nil, nil))
            }
            if date < daysAgo(14, from: now) {
                for _ in 0..<4 {
                    sets.append((row, 60, 10, nil, nil))
                }
            }
            try seedWorkout(date: date, sets: sets)
        }

        try await service.runAnalysis(referenceDate: now)
        let insights = try await service.fetchActiveInsights()

        let balance = insights.first { $0.ruleId == "muscleBalance" }
        XCTAssertNotNil(balance, "Back dropped to zero recent sets should fire muscle balance")
        XCTAssertEqual(balance?.subjectName, "back")
    }

    /// The copy used to say the other groups got "\(median)+ each", which claims
    /// a floor a median doesn't provide — a card reading "7+ each" beside a
    /// shoulders row showing 5.
    @MainActor
    func testMuscleBalanceDoesNotOverstateTheComparisonGroups() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        let row = makeExercise(name: "Row", primaryMuscle: "back")
        let press = makeExercise(name: "Overhead Press", primaryMuscle: "shoulders")
        let squat = makeExercise(name: "Squat", primaryMuscle: "quads")
        try seed([bench, row, press, squat])

        // Build history for all four, then a trailing fortnight where the other
        // groups land on clearly different counts and quads gets nothing.
        try seedWeekly(exercise: bench, weeks: 6, setsPerWeek: 8, from: now, startingWeeksAgo: 8)
        try seedWeekly(exercise: row, weeks: 6, setsPerWeek: 8, from: now, startingWeeksAgo: 8)
        try seedWeekly(exercise: press, weeks: 6, setsPerWeek: 6, from: now, startingWeeksAgo: 8)
        try seedWeekly(exercise: squat, weeks: 6, setsPerWeek: 8, from: now, startingWeeksAgo: 8)

        try seedWorkout(date: daysAgo(3, from: now), sets: (0..<8).map { _ in (row, 60.0, 10, nil, nil) })
        try seedWorkout(date: daysAgo(4, from: now), sets: (0..<7).map { _ in (bench, 80.0, 8, nil, nil) })
        try seedWorkout(date: daysAgo(5, from: now), sets: (0..<5).map { _ in (press, 40.0, 8, nil, nil) })

        try await service.runAnalysis(referenceDate: now)
        let active = try await service.fetchActiveInsights()
        let balance = try XCTUnwrap(active.first { $0.ruleId == "muscleBalance" })

        XCTAssertFalse(
            balance.detailText.contains("+ each"),
            "Median is not a floor: \(balance.detailText)"
        )

        // Every comparison group's count should be inside whatever the copy claims.
        let others = balance.chartValues.filter { $0 > 0 }
        let low = Int(others.min() ?? 0)
        let high = Int(others.max() ?? 0)
        XCTAssertTrue(
            balance.detailText.contains("\(low)–\(high)") || balance.detailText.contains("\(low)"),
            "Copy should span the real range \(low)–\(high): \(balance.detailText)"
        )
    }

    /// Rules with a nil subjectId reuse one record across subjects, so a rerun
    /// that names a different group has to carry the new name with it. Stale, it
    /// put the old group's name in the card header beside the new group's
    /// headline.
    @MainActor
    func testMuscleBalanceSubjectNameFollowsTheNewWorstGroup() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        let squat = makeExercise(name: "Squat", primaryMuscle: "quads")
        let row = makeExercise(name: "Row", primaryMuscle: "back")
        let curl = makeExercise(name: "Curl", primaryMuscle: "biceps")
        try seed([bench, squat, row, curl])

        // Back is the neglected group as of `now`: everything else keeps getting
        // sets through the trailing two weeks, back stops before them.
        for sessionIndex in 0..<12 {
            let date = daysAgo(56 - sessionIndex * 5, from: now)
            var sets: [(Exercise, Double, Int, Int?, CachedPRStatus?)] = []
            for _ in 0..<4 {
                sets.append((bench, 80, 8, nil, nil))
                sets.append((squat, 100, 8, nil, nil))
                sets.append((curl, 20, 10, nil, nil))
            }
            if date < daysAgo(14, from: now) {
                for _ in 0..<4 { sets.append((row, 60, 10, nil, nil)) }
            }
            try seedWorkout(date: date, sets: sets)
        }

        try await service.runAnalysis(referenceDate: now)
        let first = try await service.fetchActiveInsights().first { $0.ruleId == "muscleBalance" }
        XCTAssertEqual(first?.subjectName, "back")

        // Two weeks on, back has been trained throughout and biceps is the one
        // that stopped — the same record, a different subject.
        let later = Calendar.current.date(byAdding: .day, value: 14, to: now)!
        for sessionIndex in 0..<3 {
            let date = daysAgo(12 - sessionIndex * 5, from: later)
            var sets: [(Exercise, Double, Int, Int?, CachedPRStatus?)] = []
            for _ in 0..<4 {
                sets.append((bench, 80, 8, nil, nil))
                sets.append((squat, 100, 8, nil, nil))
                sets.append((row, 60, 10, nil, nil))
            }
            try seedWorkout(date: date, sets: sets)
        }

        InsightsService.resetPersistedAnalysisState()
        try await service.runAnalysis(referenceDate: later)
        let updated = try await service.fetchActiveInsights().first { $0.ruleId == "muscleBalance" }

        let subject = try XCTUnwrap(updated?.subjectName)
        let headline = try XCTUnwrap(updated?.headline)
        XCTAssertTrue(
            headline.lowercased().hasPrefix(subject.lowercased()),
            "Header subject '\(subject)' must match the headline '\(headline)'"
        )
    }

    // MARK: - Lifecycle

    @MainActor
    func testSnoozeHidesInsightAndSurvivesReanalysis() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])
        try seed(makeBiasedObservations(exerciseId: bench.id, bias: -0.06, reference: now))

        try await service.runAnalysis(referenceDate: now)
        guard let insight = try await service.fetchActiveInsights().first else {
            return XCTFail("Expected an insight to snooze")
        }

        try await service.snooze(insightId: insight.id)
        let afterSnooze = try await service.fetchActiveInsights()
        XCTAssertTrue(afterSnooze.isEmpty)

        // Re-running the analysis must not resurface the snoozed insight.
        try await service.runAnalysis(referenceDate: now.addingTimeInterval(3600))
        let afterReanalysis = try await service.fetchActiveInsights()
        XCTAssertTrue(afterReanalysis.isEmpty)
    }

    @MainActor
    func testMarkAllSeenClearsBadgeButKeepsInsights() async throws {
        let service = makeService()
        let now = Date()
        let bench = makeExercise(name: "Bench Press", primaryMuscle: "chest")
        try seed([bench])
        try seed(makeBiasedObservations(exerciseId: bench.id, bias: -0.06, reference: now))
        try await service.runAnalysis(referenceDate: now)

        let newCountBefore = try await service.newInsightCount()
        XCTAssertGreaterThan(newCountBefore, 0)

        try await service.markAllSeen()

        let newCountAfter = try await service.newInsightCount()
        XCTAssertEqual(newCountAfter, 0)
        let stillThere = try await service.fetchActiveInsights()
        XCTAssertFalse(stillThere.isEmpty)
        XCTAssertFalse(stillThere[0].isNew)
    }

    // MARK: - Rest sweet spot rule

    @MainActor
    func testRestSweetSpotDetectsRepGainFromLongerRest() async throws {
        let service = makeService()
        let now = Date()
        let squat = makeExercise(name: "Squat", primaryMuscle: "quads")
        try seed([squat])

        // 10 sessions, 3 sets each at 100kg: rests alternate short (60s, next
        // set 6 reps) and long (180s, next set 9 reps).
        for sessionIndex in 0..<10 {
            let date = daysAgo(30 - sessionIndex * 3, from: now)
            let shortSession = sessionIndex.isMultiple(of: 2)
            let rest = shortSession ? 60 : 180
            let reps = shortSession ? 6 : 9
            try seedWorkout(date: date, sets: [
                (squat, 100, 9, rest, nil),
                (squat, 100, reps, rest, nil),
                (squat, 100, reps, nil, nil)
            ])
        }

        try await service.runAnalysis(referenceDate: now)
        let insights = try await service.fetchActiveInsights()

        let rest = insights.first { $0.ruleId == "restSweetSpot" }
        XCTAssertNotNil(rest, "3-rep gap between short and long rests should fire the rest rule")
        XCTAssertEqual(rest?.subjectName, "Squat")
    }

    // MARK: - PR pace rule

    /// The drought variant fed the timeline chart `[medianGap, daysSinceLastPR]`
    /// — two durations in days — where it expects event timestamps. The chart
    /// reads the last value as the most recent event, so a 235-day plateau was
    /// drawn as one dot on 1 Jan 1970 under a headline gap of ~20,000 days.
    ///
    /// Every preview and gallery sample fed the chart real timestamps, which is
    /// why the mismatch only showed on device.
    @MainActor
    func testPRPaceDroughtChartsPRDatesRatherThanDurations() throws {
        let now = Date()
        let fly = makeExercise(name: "Seated Machine Fly", primaryMuscle: "chest")

        // Five PRs about 12 days apart and then nothing, but the lift is still
        // being trained — which is what separates a plateau from a dropped lift.
        let prDaysAgo = [283, 271, 259, 247, 235]  // oldest first
        var workouts: [Workout] = []
        var setsByWorkout: [UUID: [WorkoutSet]] = [:]

        for days in prDaysAgo + [3] {
            let date = daysAgo(days, from: now)
            let workout = Workout(date: date, startTime: date, status: .completed)
            workouts.append(workout)
            setsByWorkout[workout.id] = [WorkoutSet(
                workoutId: workout.id,
                exerciseId: fly.id,
                date: date,
                completedAt: date,
                weight: 60,
                effectiveWeight: 60,
                reps: 10,
                setType: .working,
                orderInWorkout: 0,
                orderInExercise: 0,
                completed: true,
                cachedPRStatus: prDaysAgo.contains(days) ? .current : nil
            )]
        }

        let context = InsightAnalysisContext(
            workouts: workouts,
            setsByWorkout: setsByWorkout,
            exercisesById: [fly.id: fly],
            observations: [],
            referenceDate: now,
            unitPreference: .metric
        )

        let findings = PRPaceInsightRule().evaluate(context)
        let drought = try XCTUnwrap(
            findings.first { $0.headline.contains("overdue") },
            "A 235-day gap against a 12-day PR cadence should fire the drought variant"
        )

        XCTAssertEqual(drought.chartKind, .timeline)
        XCTAssertEqual(drought.chartValues.count, prDaysAgo.count)
        for (plotted, days) in zip(drought.chartValues, prDaysAgo) {
            XCTAssertEqual(
                plotted,
                daysAgo(days, from: now).timeIntervalSince1970,
                accuracy: 1,
                "Timeline charts plot event timestamps, not gap durations"
            )
        }
        XCTAssertEqual(
            try XCTUnwrap(drought.typicalGapDays), 12, accuracy: 0.01,
            "The cadence the chart prints has to be the one the text quotes"
        )
    }

    // MARK: - Dropped exercise rule

    /// The rule takes its median over every session but hands the chart only the
    /// last 8, so the chart's own estimate described a different stretch of
    /// training than the sentence beneath it — "usually every 15" under prose
    /// reading "about every 5 days". The rule's figure now travels with the
    /// finding.
    @MainActor
    func testDroppedExerciseCarriesItsFullHistoryCadence() throws {
        let now = Date()
        let thrust = makeExercise(name: "Hip Thrust", primaryMuscle: "glutes")

        // Twelve sessions 5 days apart, then 8 more at 15, then a 60-day gap:
        // the median over everything is 5, over the charted tail it's 15.
        let recent = [60, 75, 90, 105, 120, 135, 150, 165]
        let earlier = Array(stride(from: 170, through: 225, by: 5))
        let sessionDaysAgo = (recent + earlier).sorted(by: >)  // oldest first

        var workouts: [Workout] = []
        var setsByWorkout: [UUID: [WorkoutSet]] = [:]
        for days in sessionDaysAgo {
            let date = daysAgo(days, from: now)
            let workout = Workout(date: date, startTime: date, status: .completed)
            workouts.append(workout)
            setsByWorkout[workout.id] = [WorkoutSet(
                workoutId: workout.id,
                exerciseId: thrust.id,
                date: date,
                completedAt: date,
                weight: 100,
                effectiveWeight: 100,
                reps: 10,
                setType: .working,
                orderInWorkout: 0,
                orderInExercise: 0,
                completed: true
            )]
        }

        let context = InsightAnalysisContext(
            workouts: workouts,
            setsByWorkout: setsByWorkout,
            exercisesById: [thrust.id: thrust],
            observations: [],
            referenceDate: now,
            unitPreference: .metric
        )

        let finding = try XCTUnwrap(
            DroppedExerciseInsightRule().evaluate(context).first,
            "A 60-day gap on a lift trained 20 times should read as dropped"
        )

        XCTAssertEqual(
            try XCTUnwrap(finding.typicalGapDays), 5, accuracy: 0.01,
            "The carried cadence is the median over every session"
        )
        XCTAssertTrue(
            finding.detailText.contains("about every 5 days"),
            "…which is the same number the card's text quotes"
        )

        // The charted tail on its own would have said something else entirely,
        // which is the whole reason the figure is carried rather than derived.
        let charted = finding.chartValues.sorted()
        XCTAssertEqual(charted.count, 8)
        let chartedGaps = zip(charted.dropFirst(), charted)
            .map { ($0 - $1) / 86_400 }
            .sorted()
        XCTAssertEqual(chartedGaps[chartedGaps.count / 2], 15, accuracy: 0.01)
    }
}
