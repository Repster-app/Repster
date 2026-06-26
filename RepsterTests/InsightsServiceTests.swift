import XCTest
import SwiftData
@testable import Repster

final class InsightsServiceTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
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
}
