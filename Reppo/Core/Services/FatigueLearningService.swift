import Foundation

/// Transient snapshot of a suggestion prediction, captured before a set is completed.
/// Stored in-memory on ActiveWorkoutViewModel for comparison with actual performance.
struct PredictionSnapshot: Sendable {
    let effectiveE1RM: Double
    let baseE1RM: Double
    let prescribedWeight: Double
    let formula: E1RMFormula
}

/// Summary of prediction errors for a single workout session.
struct SessionErrorSummary: Identifiable, Sendable {
    let workoutId: UUID
    let date: Date
    let observationCount: Int
    let medianError: Double
    let errors: [Double]

    var id: UUID { workoutId }
}

/// Direction for a manual fatigue rate nudge from the user.
enum FatigueNudge: Sendable {
    /// User says predictions drop too much — decrease fatigue rate.
    case lessAggressive
    /// User says predictions don't drop enough — increase fatigue rate.
    case moreAggressive
}

/// Adaptive fatigue learning service.
/// Records prediction-vs-actual errors per set and adjusts per-exercise fatigue rates
/// based on accumulated session data.
actor FatigueLearningService {

    // MARK: - Constants

    /// Minimum qualifying sessions before learning adjusts parameters.
    static let minimumSessionsForLearning = 5

    /// Fixed step size for fatigueRate adjustment per session.
    static let fatigueRateStep: Double = 0.002

    /// EMA smoothing factor for cumulative error tracking.
    static let emaAlpha: Double = 0.3

    /// Bounds for learned fatigueRate.
    static let fatigueRateBounds: ClosedRange<Double> = 0.01...0.08

    /// Maximum deviation from prescribed weight before observation is excluded.
    static let maxWeightDeviationFraction: Double = 0.20

    /// Maximum number of sessions to retain per exercise.
    static let maxRetainedSessions = 30

    // MARK: - Dependencies

    private let observationRepo: any FatigueObservationRepositoryProtocol
    private let exerciseRepo: any ExerciseRepositoryProtocol

    init(
        observationRepo: any FatigueObservationRepositoryProtocol,
        exerciseRepo: any ExerciseRepositoryProtocol
    ) {
        self.observationRepo = observationRepo
        self.exerciseRepo = exerciseRepo
    }

    // MARK: - Observation Recording

    /// Record a prediction-vs-actual observation for a completed set.
    /// Returns nil if quality filters exclude this set.
    @discardableResult
    func recordObservation(
        exerciseId: UUID,
        workoutId: UUID,
        setIndex: Int,
        prediction: PredictionSnapshot,
        actualWeight: Double,
        actualReps: Int,
        actualRIR: Double?,
        restDurationSeconds: Int?
    ) async throws -> FatigueObservation? {
        // Quality filter: skip set 0 (first working set has no fatigue signal)
        guard setIndex > 0 else { return nil }

        // Quality filter: must have RIR to compute actual e1RM
        guard let actualRIR else { return nil }

        // Quality filter: must have positive reps and weight
        guard actualReps >= 1, actualWeight > 0 else { return nil }

        // Quality filter: skip if actual weight deviates too much from prescribed
        guard prediction.prescribedWeight > 0 else { return nil }
        let deviation = abs(actualWeight - prediction.prescribedWeight) / prediction.prescribedWeight
        guard deviation <= Self.maxWeightDeviationFraction else { return nil }

        // Compute actual e1RM using the same formula as the engine: reps + RIR
        let totalReps = actualReps + Int(actualRIR)
        let actualE1RM = prediction.formula.calculate(weight: actualWeight, reps: totalReps)

        // Compute normalized error
        let normalizedError = Self.computeNormalizedError(
            predicted: prediction.effectiveE1RM,
            actual: actualE1RM,
            base: prediction.baseE1RM
        )

        let observation = FatigueObservation(
            exerciseId: exerciseId,
            workoutId: workoutId,
            setIndex: setIndex,
            predictedEffectiveE1RM: prediction.effectiveE1RM,
            actualE1RM: actualE1RM,
            normalizedError: normalizedError,
            baseE1RM: prediction.baseE1RM,
            prescribedWeight: prediction.prescribedWeight,
            actualWeight: actualWeight,
            actualReps: actualReps,
            actualRIR: actualRIR,
            restDurationSeconds: restDurationSeconds
        )

        try await observationRepo.save(observation)
        return observation
    }

    // MARK: - Session-End Learning

    /// Process all observations from a completed workout and update per-exercise fatigue rates.
    func processSessionEnd(workoutId: UUID) async {
        do {
            let observations = try await observationRepo.fetchObservations(for: workoutId)
            guard !observations.isEmpty else { return }

            // Group by exercise
            let byExercise = Dictionary(grouping: observations, by: \.exerciseId)

            for (exerciseId, exerciseObs) in byExercise {
                // Need at least 2 qualifying observations per exercise per session
                guard exerciseObs.count >= 2 else { continue }

                let sessionError = Self.medianError(exerciseObs.map(\.normalizedError))

                // Fetch exercise to update learning state
                guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else { continue }

                // Update learning state
                let oldCount = exercise.fatigueLearningSessionCount ?? 0
                let newCount = oldCount + 1
                exercise.fatigueLearningSessionCount = newCount

                let oldCumError = exercise.fatigueLearningCumulativeError ?? 0.0
                let newCumError = Self.emaAlpha * sessionError + (1.0 - Self.emaAlpha) * oldCumError
                exercise.fatigueLearningCumulativeError = newCumError

                // Only adjust fatigueRate after minimum sessions
                if newCount >= Self.minimumSessionsForLearning {
                    let currentRate = exercise.fatigueRate ?? 0.04
                    let adjustment = Self.fatigueRateStep * Self.sign(newCumError)
                    let newRate = Self.clamp(currentRate + adjustment, bounds: Self.fatigueRateBounds)
                    exercise.fatigueRate = newRate

                    print("[FatigueLearning] \(exercise.name): session \(newCount), " +
                          "error=\(String(format: "%.4f", sessionError)), " +
                          "cumError=\(String(format: "%.4f", newCumError)), " +
                          "fatigueRate \(String(format: "%.4f", currentRate)) → \(String(format: "%.4f", newRate))")
                } else {
                    print("[FatigueLearning] \(exercise.name): session \(newCount)/\(Self.minimumSessionsForLearning), " +
                          "error=\(String(format: "%.4f", sessionError)), " +
                          "cumError=\(String(format: "%.4f", newCumError)) (collecting data)")
                }

                exercise.updatedAt = Date()
                try await exerciseRepo.save(exercise)

                // Prune old observations
                try await observationRepo.pruneObservations(
                    exerciseId: exerciseId,
                    keepRecentSessions: Self.maxRetainedSessions
                )
            }
        } catch {
            print("[FatigueLearning] Error processing session end: \(error)")
        }
    }

    // MARK: - Reset & Query

    /// Reset learning state for a single exercise, reverting fatigueRate to default.
    func resetLearning(exerciseId: UUID) async throws {
        guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else { return }
        exercise.fatigueRate = nil
        exercise.fatigueLearningSessionCount = nil
        exercise.fatigueLearningCumulativeError = nil
        exercise.updatedAt = Date()
        try await exerciseRepo.save(exercise)

        // Delete all observations for this exercise
        let observations = try await observationRepo.fetchObservations(exerciseId: exerciseId, limit: nil)
        for obs in observations {
            // Use pruneObservations with 0 to delete all
        }
        try await observationRepo.pruneObservations(exerciseId: exerciseId, keepRecentSessions: 0)
    }

    /// Reset learning state for all exercises.
    func resetAllLearning() async throws {
        let exercises = try await exerciseRepo.fetchAll()
        for exercise in exercises where exercise.fatigueLearningSessionCount != nil {
            exercise.fatigueRate = nil
            exercise.fatigueLearningSessionCount = nil
            exercise.fatigueLearningCumulativeError = nil
            exercise.updatedAt = Date()
            try await exerciseRepo.save(exercise)
            try await observationRepo.pruneObservations(exerciseId: exercise.id, keepRecentSessions: 0)
        }
    }

    /// Fetch exercises that have any learning data, sorted by session count descending.
    func exercisesWithLearningData() async throws -> [Exercise] {
        let allExercises = try await exerciseRepo.fetchAll()
        return allExercises
            .filter { ($0.fatigueLearningSessionCount ?? 0) > 0 }
            .sorted { ($0.fatigueLearningSessionCount ?? 0) > ($1.fatigueLearningSessionCount ?? 0) }
    }

    /// Fetch recent observations for an exercise, grouped by workout (most recent first).
    func recentSessionSummaries(exerciseId: UUID, limit: Int = 10) async throws -> [SessionErrorSummary] {
        let observations = try await observationRepo.fetchObservations(exerciseId: exerciseId, limit: nil)
        let byWorkout = Dictionary(grouping: observations, by: \.workoutId)

        return byWorkout.map { (workoutId, obs) in
            let sortedObs = obs.sorted(by: { $0.setIndex < $1.setIndex })
            let errors = sortedObs.map(\.normalizedError)
            let medianErr = Self.medianError(errors)
            let date = sortedObs.first?.createdAt ?? .distantPast
            return SessionErrorSummary(
                workoutId: workoutId,
                date: date,
                observationCount: obs.count,
                medianError: medianErr,
                errors: errors
            )
        }
        .sorted(by: { $0.date > $1.date })
        .prefix(limit)
        .map { $0 }
    }

    // MARK: - Manual Nudge

    /// Apply a user-initiated nudge to an exercise's fatigue rate.
    /// Adjusts by ±fatigueRateStep without changing learning state (session count / cumulative error).
    func applyManualNudge(exerciseId: UUID, nudge: FatigueNudge) async throws {
        guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else { return }
        let currentRate = exercise.fatigueRate ?? 0.04
        let adjustment: Double = switch nudge {
        case .lessAggressive: -Self.fatigueRateStep
        case .moreAggressive: Self.fatigueRateStep
        }
        exercise.fatigueRate = Self.clamp(currentRate + adjustment, bounds: Self.fatigueRateBounds)
        exercise.updatedAt = Date()
        try await exerciseRepo.save(exercise)
    }

    // MARK: - Observation Queries

    /// Fetch individual observations for a specific workout and exercise.
    func observations(for workoutId: UUID, exerciseId: UUID) async throws -> [FatigueObservation] {
        let all = try await observationRepo.fetchObservations(for: workoutId)
        return all.filter { $0.exerciseId == exerciseId }.sorted { $0.setIndex < $1.setIndex }
    }

    // MARK: - Pure Computation (Static, Testable)

    /// Compute the normalized prediction error.
    /// Negative = model was too aggressive (user stronger than predicted).
    /// Positive = model was too lenient (user weaker than predicted).
    static func computeNormalizedError(predicted: Double, actual: Double, base: Double) -> Double {
        guard base > 0 else { return 0 }
        return (predicted - actual) / base
    }

    /// Compute the median of an array of values.
    static func medianError(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }

    /// Sign function: returns -1, 0, or 1.
    private static func sign(_ value: Double) -> Double {
        if value > 0 { return 1.0 }
        if value < 0 { return -1.0 }
        return 0.0
    }

    /// Clamp a value to a range.
    private static func clamp(_ value: Double, bounds: ClosedRange<Double>) -> Double {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}
