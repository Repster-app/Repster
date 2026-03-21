import XCTest
@testable import Reppo

final class FatigueLearningServiceTests: XCTestCase {

    // MARK: - computeNormalizedError

    func testNormalizedError_modelTooAggressive_returnsNegative() {
        // Model predicted less capacity than user actually had
        let error = FatigueLearningService.computeNormalizedError(
            predicted: 130.0,  // model thought effective e1RM was 130
            actual: 140.0,     // user demonstrated 140
            base: 150.0        // baseline was 150
        )

        // (130 - 140) / 150 = -0.0667
        XCTAssertEqual(error, -10.0 / 150.0, accuracy: 0.0001)
        XCTAssertLessThan(error, 0, "Negative error means model was too aggressive")
    }

    func testNormalizedError_modelTooLenient_returnsPositive() {
        // Model predicted more capacity than user actually had
        let error = FatigueLearningService.computeNormalizedError(
            predicted: 145.0,
            actual: 135.0,
            base: 150.0
        )

        // (145 - 135) / 150 = 0.0667
        XCTAssertEqual(error, 10.0 / 150.0, accuracy: 0.0001)
        XCTAssertGreaterThan(error, 0, "Positive error means model was too lenient")
    }

    func testNormalizedError_perfectPrediction_returnsZero() {
        let error = FatigueLearningService.computeNormalizedError(
            predicted: 140.0,
            actual: 140.0,
            base: 150.0
        )

        XCTAssertEqual(error, 0.0, accuracy: 0.0001)
    }

    func testNormalizedError_zeroBase_returnsZero() {
        let error = FatigueLearningService.computeNormalizedError(
            predicted: 140.0,
            actual: 130.0,
            base: 0.0
        )

        XCTAssertEqual(error, 0.0, "Should return 0 when base is 0 to avoid division by zero")
    }

    // MARK: - medianError

    func testMedianError_oddCount() {
        let median = FatigueLearningService.medianError([-0.05, -0.02, -0.08])
        XCTAssertEqual(median, -0.05, accuracy: 0.0001)
    }

    func testMedianError_evenCount() {
        let median = FatigueLearningService.medianError([-0.05, -0.02, -0.08, -0.01])
        // sorted: -0.08, -0.05, -0.02, -0.01 → median = (-0.05 + -0.02) / 2 = -0.035
        XCTAssertEqual(median, -0.035, accuracy: 0.0001)
    }

    func testMedianError_singleValue() {
        let median = FatigueLearningService.medianError([-0.03])
        XCTAssertEqual(median, -0.03, accuracy: 0.0001)
    }

    func testMedianError_emptyArray() {
        let median = FatigueLearningService.medianError([])
        XCTAssertEqual(median, 0.0)
    }

    func testMedianError_robustToOutliers() {
        // One large outlier should not dominate
        let median = FatigueLearningService.medianError([-0.03, -0.04, -0.50, -0.02, -0.05])
        // sorted: -0.50, -0.05, -0.04, -0.03, -0.02 → median = -0.04
        XCTAssertEqual(median, -0.04, accuracy: 0.0001)
    }

    // MARK: - Quality Filters (via recordObservation)

    func testRecordObservation_skipsSetIndexZero() async throws {
        let service = makeService()
        let snapshot = makePrediction()

        let result = try await service.recordObservation(
            exerciseId: UUID(),
            workoutId: UUID(),
            setIndex: 0,  // first set — no fatigue signal
            prediction: snapshot,
            actualWeight: 100,
            actualReps: 10,
            actualRIR: 0,
            restDurationSeconds: 180
        )

        XCTAssertNil(result, "Set 0 should be skipped (no fatigue signal)")
    }

    func testRecordObservation_skipsNilRIR() async throws {
        let service = makeService()
        let snapshot = makePrediction()

        let result = try await service.recordObservation(
            exerciseId: UUID(),
            workoutId: UUID(),
            setIndex: 1,
            prediction: snapshot,
            actualWeight: 100,
            actualReps: 10,
            actualRIR: nil,  // no RIR reported
            restDurationSeconds: 180
        )

        XCTAssertNil(result, "Should skip when RIR is nil")
    }

    func testRecordObservation_skipsLargeWeightDeviation() async throws {
        let service = makeService()
        let snapshot = makePrediction(prescribedWeight: 100)

        let result = try await service.recordObservation(
            exerciseId: UUID(),
            workoutId: UUID(),
            setIndex: 1,
            prediction: snapshot,
            actualWeight: 130,  // 30% deviation > 20% threshold
            actualReps: 10,
            actualRIR: 0,
            restDurationSeconds: 180
        )

        XCTAssertNil(result, "Should skip when weight deviates >20% from prescribed")
    }

    func testRecordObservation_recordsValidObservation() async throws {
        let repo = InMemoryFatigueObservationRepo()
        let service = makeService(observationRepo: repo)
        let snapshot = makePrediction(effectiveE1RM: 140, baseE1RM: 150, prescribedWeight: 110)

        let result = try await service.recordObservation(
            exerciseId: UUID(),
            workoutId: UUID(),
            setIndex: 2,
            prediction: snapshot,
            actualWeight: 115,
            actualReps: 10,
            actualRIR: 0,
            restDurationSeconds: 180
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(repo.observations.count, 1)

        // Actual e1RM: Epley formula, weight=115, reps=10+0=10
        // e1RM = 115 * (1 + 10/30) = 115 * 1.333 = 153.33
        let expectedActualE1RM = 115.0 * (1.0 + 10.0 / 30.0)
        XCTAssertEqual(result?.actualE1RM ?? 0, expectedActualE1RM, accuracy: 0.01)

        // Normalized error = (140 - 153.33) / 150
        let expectedError = (140.0 - expectedActualE1RM) / 150.0
        XCTAssertEqual(result?.normalizedError ?? 0, expectedError, accuracy: 0.001)
        XCTAssertLessThan(result?.normalizedError ?? 0, 0, "User over-performed, error should be negative")
    }

    // MARK: - Learning Algorithm (processSessionEnd)

    func testProcessSessionEnd_updatesLearningState() async throws {
        let exerciseId = UUID()
        let workoutId = UUID()
        let exercise = Exercise(
            id: exerciseId,
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps
        )

        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let observationRepo = InMemoryFatigueObservationRepo()

        // Add observations simulating user over-performing (negative errors)
        observationRepo.observations = [
            FatigueObservation(
                exerciseId: exerciseId, workoutId: workoutId, setIndex: 1,
                predictedEffectiveE1RM: 140, actualE1RM: 148,
                normalizedError: -0.053, baseE1RM: 150,
                prescribedWeight: 105, actualWeight: 110, actualReps: 10, actualRIR: 0
            ),
            FatigueObservation(
                exerciseId: exerciseId, workoutId: workoutId, setIndex: 2,
                predictedEffectiveE1RM: 135, actualE1RM: 145,
                normalizedError: -0.067, baseE1RM: 150,
                prescribedWeight: 100, actualWeight: 110, actualReps: 10, actualRIR: 0
            ),
        ]

        let service = FatigueLearningService(
            observationRepo: observationRepo,
            exerciseRepo: exerciseRepo
        )

        await service.processSessionEnd(workoutId: workoutId)

        // Session count should be 1
        XCTAssertEqual(exercise.fatigueLearningSessionCount, 1)

        // Cumulative error should be negative (EMA of session error)
        XCTAssertNotNil(exercise.fatigueLearningCumulativeError)
        XCTAssertLessThan(exercise.fatigueLearningCumulativeError ?? 0, 0)

        // FatigueRate should NOT change yet (need 5 sessions minimum)
        XCTAssertNil(exercise.fatigueRate, "Should not adjust fatigueRate before 5 sessions")
    }

    func testProcessSessionEnd_adjustsFatigueRateAfterMinimumSessions() async throws {
        let exerciseId = UUID()
        let exercise = Exercise(
            id: exerciseId,
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps
        )
        // Simulate 4 prior sessions with consistently negative error
        exercise.fatigueLearningSessionCount = 4
        exercise.fatigueLearningCumulativeError = -0.05

        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let observationRepo = InMemoryFatigueObservationRepo()

        let workoutId = UUID()
        observationRepo.observations = [
            FatigueObservation(
                exerciseId: exerciseId, workoutId: workoutId, setIndex: 1,
                predictedEffectiveE1RM: 140, actualE1RM: 148,
                normalizedError: -0.053, baseE1RM: 150,
                prescribedWeight: 105, actualWeight: 110, actualReps: 10, actualRIR: 0
            ),
            FatigueObservation(
                exerciseId: exerciseId, workoutId: workoutId, setIndex: 2,
                predictedEffectiveE1RM: 135, actualE1RM: 145,
                normalizedError: -0.067, baseE1RM: 150,
                prescribedWeight: 100, actualWeight: 110, actualReps: 10, actualRIR: 0
            ),
        ]

        let service = FatigueLearningService(
            observationRepo: observationRepo,
            exerciseRepo: exerciseRepo
        )

        await service.processSessionEnd(workoutId: workoutId)

        // Session count should be 5 now
        XCTAssertEqual(exercise.fatigueLearningSessionCount, 5)

        // Cumulative error is still negative
        XCTAssertLessThan(exercise.fatigueLearningCumulativeError ?? 0, 0)

        // FatigueRate should now be adjusted: default 0.04 - 0.002 = 0.038
        XCTAssertNotNil(exercise.fatigueRate)
        XCTAssertEqual(exercise.fatigueRate ?? 0, 0.038, accuracy: 0.0001,
                       "Negative cumulative error should decrease fatigueRate")
    }

    func testProcessSessionEnd_respectsLowerBound() async throws {
        let exerciseId = UUID()
        let exercise = Exercise(
            id: exerciseId,
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            fatigueRate: 0.011  // very close to lower bound of 0.01
        )
        exercise.fatigueLearningSessionCount = 10
        exercise.fatigueLearningCumulativeError = -0.05

        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let observationRepo = InMemoryFatigueObservationRepo()

        let workoutId = UUID()
        observationRepo.observations = [
            FatigueObservation(
                exerciseId: exerciseId, workoutId: workoutId, setIndex: 1,
                predictedEffectiveE1RM: 140, actualE1RM: 148,
                normalizedError: -0.053, baseE1RM: 150,
                prescribedWeight: 105, actualWeight: 110, actualReps: 10, actualRIR: 0
            ),
            FatigueObservation(
                exerciseId: exerciseId, workoutId: workoutId, setIndex: 2,
                predictedEffectiveE1RM: 135, actualE1RM: 145,
                normalizedError: -0.067, baseE1RM: 150,
                prescribedWeight: 100, actualWeight: 110, actualReps: 10, actualRIR: 0
            ),
        ]

        let service = FatigueLearningService(
            observationRepo: observationRepo,
            exerciseRepo: exerciseRepo
        )

        await service.processSessionEnd(workoutId: workoutId)

        // Should clamp to lower bound
        XCTAssertEqual(exercise.fatigueRate ?? 0, 0.01, accuracy: 0.0001,
                       "FatigueRate should not go below 0.01")
    }

    func testProcessSessionEnd_skipsExerciseWithTooFewObservations() async throws {
        let exerciseId = UUID()
        let exercise = Exercise(
            id: exerciseId,
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps
        )

        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let observationRepo = InMemoryFatigueObservationRepo()

        let workoutId = UUID()
        // Only 1 observation — need at least 2
        observationRepo.observations = [
            FatigueObservation(
                exerciseId: exerciseId, workoutId: workoutId, setIndex: 1,
                predictedEffectiveE1RM: 140, actualE1RM: 148,
                normalizedError: -0.053, baseE1RM: 150,
                prescribedWeight: 105, actualWeight: 110, actualReps: 10, actualRIR: 0
            ),
        ]

        let service = FatigueLearningService(
            observationRepo: observationRepo,
            exerciseRepo: exerciseRepo
        )

        await service.processSessionEnd(workoutId: workoutId)

        XCTAssertNil(exercise.fatigueLearningSessionCount,
                     "Should not update learning state with < 2 observations")
    }

    // MARK: - Manual Nudge

    func testApplyManualNudge_lessAggressive_decreasesRate() async throws {
        let exerciseId = UUID()
        let exercise = Exercise(
            id: exerciseId,
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps
        )
        // Start at default rate
        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let service = makeService(exerciseRepo: exerciseRepo)

        try await service.applyManualNudge(exerciseId: exerciseId, nudge: .lessAggressive)

        XCTAssertEqual(exercise.fatigueRate ?? 0, 0.038, accuracy: 0.0001,
                       "Less aggressive nudge should decrease rate by 0.002")
    }

    func testApplyManualNudge_moreAggressive_increasesRate() async throws {
        let exerciseId = UUID()
        let exercise = Exercise(
            id: exerciseId,
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps
        )
        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let service = makeService(exerciseRepo: exerciseRepo)

        try await service.applyManualNudge(exerciseId: exerciseId, nudge: .moreAggressive)

        XCTAssertEqual(exercise.fatigueRate ?? 0, 0.042, accuracy: 0.0001,
                       "More aggressive nudge should increase rate by 0.002")
    }

    func testApplyManualNudge_respectsBounds() async throws {
        let exerciseId = UUID()
        let exercise = Exercise(
            id: exerciseId,
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            fatigueRate: 0.079 // near upper bound of 0.08
        )
        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let service = makeService(exerciseRepo: exerciseRepo)

        try await service.applyManualNudge(exerciseId: exerciseId, nudge: .moreAggressive)

        XCTAssertEqual(exercise.fatigueRate ?? 0, 0.08, accuracy: 0.0001,
                       "Should clamp to upper bound")
    }

    func testApplyManualNudge_doesNotChangeLearningState() async throws {
        let exerciseId = UUID()
        let exercise = Exercise(
            id: exerciseId,
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps
        )
        exercise.fatigueLearningSessionCount = 3
        exercise.fatigueLearningCumulativeError = -0.02

        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let service = makeService(exerciseRepo: exerciseRepo)

        try await service.applyManualNudge(exerciseId: exerciseId, nudge: .lessAggressive)

        XCTAssertEqual(exercise.fatigueLearningSessionCount, 3,
                       "Manual nudge should not change session count")
        XCTAssertEqual(exercise.fatigueLearningCumulativeError ?? 0, -0.02, accuracy: 0.0001,
                       "Manual nudge should not change cumulative error")
    }

    // MARK: - Helpers

    private func makeService(
        observationRepo: FatigueObservationRepositoryProtocol? = nil,
        exerciseRepo: ExerciseRepositoryProtocol? = nil
    ) -> FatigueLearningService {
        FatigueLearningService(
            observationRepo: observationRepo ?? InMemoryFatigueObservationRepo(),
            exerciseRepo: exerciseRepo ?? InMemoryExerciseRepo()
        )
    }

    private func makePrediction(
        effectiveE1RM: Double = 140,
        baseE1RM: Double = 150,
        prescribedWeight: Double = 110
    ) -> PredictionSnapshot {
        PredictionSnapshot(
            effectiveE1RM: effectiveE1RM,
            baseE1RM: baseE1RM,
            prescribedWeight: prescribedWeight,
            formula: .epley
        )
    }
}

// MARK: - In-Memory Test Doubles

private final class InMemoryFatigueObservationRepo: @unchecked Sendable, FatigueObservationRepositoryProtocol {
    var observations: [FatigueObservation] = []

    func save(_ observation: FatigueObservation) async throws {
        observations.append(observation)
    }

    func fetchObservations(for workoutId: UUID) async throws -> [FatigueObservation] {
        observations.filter { $0.workoutId == workoutId }
    }

    func fetchObservations(exerciseId: UUID, limit: Int?) async throws -> [FatigueObservation] {
        let filtered = observations.filter { $0.exerciseId == exerciseId }
        if let limit { return Array(filtered.prefix(limit)) }
        return filtered
    }

    func distinctWorkoutCount(exerciseId: UUID) async throws -> Int {
        Set(observations.filter { $0.exerciseId == exerciseId }.map(\.workoutId)).count
    }

    @discardableResult
    func pruneObservations(exerciseId: UUID, keepRecentSessions: Int) async throws -> Int {
        0
    }
}

private final class InMemoryExerciseRepo: @unchecked Sendable, ExerciseRepositoryProtocol {
    var exercises: [Exercise]

    init(exercises: [Exercise] = []) {
        self.exercises = exercises
    }

    func save(_ exercise: Exercise) async throws {
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            exercises[index] = exercise
        } else {
            exercises.append(exercise)
        }
    }

    func delete(_ exercise: Exercise) async throws {
        exercises.removeAll { $0.id == exercise.id }
    }

    func fetch(byId id: UUID) async throws -> Exercise? {
        exercises.first { $0.id == id }
    }

    func fetchAll() async throws -> [Exercise] { exercises }
    func fetchAllChartExercises() async throws -> [ChartExerciseData] { [] }
    func search(name: String) async throws -> [Exercise] { [] }
    func hasAssociatedSets(_ exerciseId: UUID) async throws -> Bool { false }
}
