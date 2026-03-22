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

struct FatigueLearningCaptureResult {
    let audit: FatigueLearningSetAudit
    let observation: FatigueObservation?
}

struct FatigueLearningSetSnapshot: Sendable {
    let completed: Bool
    let setType: SetType
    let actualWeight: Double?
    let actualReps: Int?
    let actualRIR: Double?
    let restDurationSeconds: Int?
}

enum AppliedFatigueRateSource: String, Sendable {
    case exerciseOverride
    case globalLearned
    case defaultRate

    var displayTitle: String {
        switch self {
        case .exerciseOverride:
            return "Exercise override"
        case .globalLearned:
            return "Global learned"
        case .defaultRate:
            return "Default"
        }
    }
}

struct AppliedFatigueRateInfo: Sendable {
    let rate: Double
    let source: AppliedFatigueRateSource
}

struct GlobalFatigueLearningSummary: Sendable {
    let appliedRate: AppliedFatigueRateInfo
    let sessionCount: Int
    let cumulativeError: Double
}

struct FatigueLearningExerciseDiagnostics: Identifiable, Sendable {
    let exercise: Exercise
    let appliedRate: AppliedFatigueRateInfo
    let hasAuditHistory: Bool
    let lastAuditDate: Date?

    var id: UUID { exercise.id }
}

struct FatigueLearningWorkoutAuditSummary: Identifiable, Sendable {
    let workoutId: UUID
    let date: Date
    let totalAudits: Int
    let usedSetCount: Int
    let medianError: Double?

    var id: UUID { workoutId }
    var qualifiesForExerciseLearning: Bool { usedSetCount >= 2 }
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
    private let healthProfileRepo: any HealthProfileRepositoryProtocol
    private let auditRepo: any FatigueLearningSetAuditRepositoryProtocol

    init(
        observationRepo: any FatigueObservationRepositoryProtocol,
        exerciseRepo: any ExerciseRepositoryProtocol,
        healthProfileRepo: any HealthProfileRepositoryProtocol,
        auditRepo: any FatigueLearningSetAuditRepositoryProtocol
    ) {
        self.observationRepo = observationRepo
        self.exerciseRepo = exerciseRepo
        self.healthProfileRepo = healthProfileRepo
        self.auditRepo = auditRepo
    }

    // MARK: - Deterministic Set Capture

    @discardableResult
    func captureCompletedSet(
        setId: UUID,
        exerciseId: UUID,
        workoutId: UUID,
        visibleSetNumber: Int,
        setType: SetType,
        priorCompletedWorkingSetCount: Int,
        suggestionUnavailableReason: SuggestionUnavailableReason?,
        prediction: PredictionSnapshot?,
        actualWeight: Double?,
        actualReps: Int?,
        actualRIR: Double?,
        restDurationSeconds: Int?
    ) async throws -> FatigueLearningCaptureResult {
        let status: FatigueLearningAuditStatus
        let deviationFraction: Double?
        let normalizedError: Double?
        let observation: FatigueObservation?

        if setType == .warmup {
            status = .warmupNotTracked
            deviationFraction = nil
            normalizedError = nil
            observation = nil
        } else if prediction == nil {
            status = .suggestionUnavailable
            deviationFraction = nil
            normalizedError = nil
            observation = nil
        } else if priorCompletedWorkingSetCount == 0 {
            status = .baselineFirstWorkingSet
            deviationFraction = nil
            normalizedError = nil
            observation = nil
        } else if (actualReps ?? 0) < 1 || (actualWeight ?? 0) <= 0 {
            status = .invalidPerformance
            deviationFraction = nil
            normalizedError = nil
            observation = nil
        } else if actualRIR == nil {
            status = .missingRIR
            deviationFraction = nil
            normalizedError = nil
            observation = nil
        } else if let prediction, prediction.prescribedWeight <= 0 {
            status = .invalidPerformance
            deviationFraction = nil
            normalizedError = nil
            observation = nil
        } else if let prediction, let actualWeight {
            let deviation = abs(actualWeight - prediction.prescribedWeight) / prediction.prescribedWeight
            deviationFraction = deviation

            if deviation > Self.maxWeightDeviationFraction {
                status = .weightDeviationOver20Percent
                normalizedError = nil
                observation = nil
            } else if let actualReps, let actualRIR {
                status = .used
                let totalReps = actualReps + Int(actualRIR)
                let actualE1RM = prediction.formula.calculate(weight: actualWeight, reps: totalReps)
                let computedError = Self.computeNormalizedError(
                    predicted: prediction.effectiveE1RM,
                    actual: actualE1RM,
                    base: prediction.baseE1RM
                )
                normalizedError = computedError
                observation = FatigueObservation(
                    exerciseId: exerciseId,
                    workoutId: workoutId,
                    setId: setId,
                    setIndex: priorCompletedWorkingSetCount,
                    predictedEffectiveE1RM: prediction.effectiveE1RM,
                    actualE1RM: actualE1RM,
                    normalizedError: computedError,
                    baseE1RM: prediction.baseE1RM,
                    prescribedWeight: prediction.prescribedWeight,
                    actualWeight: actualWeight,
                    actualReps: actualReps,
                    actualRIR: actualRIR,
                    restDurationSeconds: restDurationSeconds
                )
            } else {
                status = .invalidPerformance
                normalizedError = nil
                observation = nil
            }
        } else {
            status = .invalidPerformance
            deviationFraction = nil
            normalizedError = nil
            observation = nil
        }

        let audit = FatigueLearningSetAudit(
            workoutId: workoutId,
            exerciseId: exerciseId,
            setId: setId,
            visibleSetNumber: visibleSetNumber,
            setType: setType,
            status: status,
            suggestionUnavailableReason: suggestionUnavailableReason,
            predictedEffectiveE1RM: prediction?.effectiveE1RM,
            baseE1RM: prediction?.baseE1RM,
            prescribedWeight: prediction?.prescribedWeight,
            actualWeight: actualWeight,
            actualReps: actualReps,
            actualRIR: actualRIR,
            deviationFraction: deviationFraction,
            normalizedError: normalizedError
        )

        try await observationRepo.deleteObservation(for: setId)
        if let observation {
            try await observationRepo.upsert(observation)
        }
        try await auditRepo.upsert(audit)
        return FatigueLearningCaptureResult(audit: audit, observation: observation)
    }

    func removeCapturedSetData(setId: UUID) async throws {
        try await observationRepo.deleteObservation(for: setId)
        try await auditRepo.deleteAudit(for: setId)
    }

    func capturedSetDataNeedsInvalidation(
        setId: UUID,
        workoutId: UUID,
        exerciseId: UUID,
        previous: FatigueLearningSetSnapshot,
        current: FatigueLearningSetSnapshot
    ) async throws -> Bool {
        let hasObservation = try await observationRepo
            .fetchObservations(for: workoutId)
            .contains { $0.setId == setId }
        let hasAudit = try await auditRepo
            .fetchAudits(workoutId: workoutId, exerciseId: exerciseId)
            .contains { $0.setId == setId }

        guard hasObservation || hasAudit else {
            return false
        }

        guard current.completed else {
            return true
        }

        return previous.completed != current.completed
            || previous.setType != current.setType
            || previous.actualWeight != current.actualWeight
            || previous.actualReps != current.actualReps
            || previous.actualRIR != current.actualRIR
            || previous.restDurationSeconds != current.restDurationSeconds
    }

    func removeCapturedWorkoutData(workoutId: UUID) async throws {
        let observations = try await observationRepo.fetchObservations(for: workoutId)
        for observation in observations {
            try await observationRepo.deleteObservation(for: observation.setId)
        }
        try await auditRepo.deleteAudits(workoutId: workoutId)
    }

    func removeCapturedExerciseData(exerciseId: UUID) async throws {
        try await observationRepo.pruneObservations(exerciseId: exerciseId, keepRecentSessions: 0)
        try await auditRepo.deleteAudits(exerciseId: exerciseId)
    }

    // MARK: - Session-End Learning

    func processSessionEnd(workoutId: UUID) async {
        do {
            let audits = try await auditRepo.fetchAudits(for: workoutId)
            let usedAudits = audits.filter { $0.status == .used }
            guard !usedAudits.isEmpty else { return }

            let profile = try await healthProfileRepo.fetchOrCreate()
            let byExercise = Dictionary(grouping: usedAudits, by: \.exerciseId)

            if usedAudits.count >= 2 {
                let exerciseMedians = byExercise.values.compactMap { audits -> Double? in
                    let errors = audits.compactMap(\.normalizedError)
                    guard !errors.isEmpty else { return nil }
                    return Self.medianError(errors)
                }

                if !exerciseMedians.isEmpty {
                    updateGlobalLearning(profile: profile, sessionError: Self.medianError(exerciseMedians))
                    try await healthProfileRepo.save(profile)
                }
            }

            for (exerciseId, exerciseAudits) in byExercise where exerciseAudits.count >= 2 {
                let errors = exerciseAudits.compactMap(\.normalizedError)
                guard !errors.isEmpty else { continue }
                guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else { continue }
                try await updateExerciseLearning(
                    exercise: exercise,
                    profile: profile,
                    sessionError: Self.medianError(errors)
                )
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

        try await observationRepo.pruneObservations(exerciseId: exerciseId, keepRecentSessions: 0)
        try await auditRepo.deleteAudits(exerciseId: exerciseId)
    }

    /// Reset learning state for all exercises.
    func resetAllLearning() async throws {
        let exercises = try await exerciseRepo.fetchAll()
        for exercise in exercises {
            if exercise.fatigueRate != nil ||
                exercise.fatigueLearningSessionCount != nil ||
                exercise.fatigueLearningCumulativeError != nil {
                exercise.fatigueRate = nil
                exercise.fatigueLearningSessionCount = nil
                exercise.fatigueLearningCumulativeError = nil
                exercise.updatedAt = Date()
                try await exerciseRepo.save(exercise)
            }
            try await observationRepo.pruneObservations(exerciseId: exercise.id, keepRecentSessions: 0)
        }
        try await auditRepo.deleteAll()

        let profile = try await healthProfileRepo.fetchOrCreate()
        profile.prescriptionLearnedFatigueRate = nil
        profile.prescriptionFatigueLearningSessionCount = nil
        profile.prescriptionFatigueLearningCumulativeError = nil
        profile.updatedAt = Date()
        try await healthProfileRepo.save(profile)
    }

    /// Fetch exercises that have any learning data, sorted by session count descending.
    func exercisesWithLearningData() async throws -> [Exercise] {
        let allExercises = try await exerciseRepo.fetchAll()
        return allExercises
            .filter { ($0.fatigueLearningSessionCount ?? 0) > 0 }
            .sorted { ($0.fatigueLearningSessionCount ?? 0) > ($1.fatigueLearningSessionCount ?? 0) }
    }

    func globalSummary() async throws -> GlobalFatigueLearningSummary {
        let profile = try await healthProfileRepo.fetchOrCreate()
        return GlobalFatigueLearningSummary(
            appliedRate: AppliedFatigueRateInfo(
                rate: profile.prescriptionLearnedFatigueRate ?? 0.04,
                source: profile.prescriptionLearnedFatigueRate == nil ? .defaultRate : .globalLearned
            ),
            sessionCount: profile.prescriptionFatigueLearningSessionCount ?? 0,
            cumulativeError: profile.prescriptionFatigueLearningCumulativeError ?? 0.0
        )
    }

    func diagnosticsExercises() async throws -> [FatigueLearningExerciseDiagnostics] {
        let allExercises = try await exerciseRepo.fetchAll()
        let profile = try await healthProfileRepo.fetchOrCreate()
        let auditedExerciseIds = Set(try await auditRepo.exerciseIdsWithAudits())

        var diagnostics: [FatigueLearningExerciseDiagnostics] = []
        for exercise in allExercises {
            let hasLocalData = (exercise.fatigueLearningSessionCount ?? 0) > 0 || exercise.fatigueRate != nil
            let hasAuditHistory = auditedExerciseIds.contains(exercise.id)
            guard hasLocalData || hasAuditHistory else { continue }

            let latestAudit = try await auditRepo.fetchAudits(exerciseId: exercise.id, limit: 1).first
            diagnostics.append(
                FatigueLearningExerciseDiagnostics(
                    exercise: exercise,
                    appliedRate: Self.appliedFatigueRate(for: exercise, profile: profile),
                    hasAuditHistory: hasAuditHistory,
                    lastAuditDate: latestAudit?.createdAt
                )
            )
        }

        return diagnostics.sorted { lhs, rhs in
            if lhs.lastAuditDate != rhs.lastAuditDate {
                return (lhs.lastAuditDate ?? .distantPast) > (rhs.lastAuditDate ?? .distantPast)
            }
            if (lhs.exercise.fatigueLearningSessionCount ?? 0) != (rhs.exercise.fatigueLearningSessionCount ?? 0) {
                return (lhs.exercise.fatigueLearningSessionCount ?? 0) > (rhs.exercise.fatigueLearningSessionCount ?? 0)
            }
            return lhs.exercise.name.localizedCaseInsensitiveCompare(rhs.exercise.name) == .orderedAscending
        }
    }

    func recentWorkoutAuditSummaries(exerciseId: UUID, limit: Int = 10) async throws -> [FatigueLearningWorkoutAuditSummary] {
        let audits = try await auditRepo.fetchAudits(exerciseId: exerciseId, limit: nil)
        let byWorkout = Dictionary(grouping: audits, by: \.workoutId)

        return byWorkout.map { (workoutId, workoutAudits) in
            let date = workoutAudits.map(\.createdAt).max() ?? .distantPast
            let usedAudits = workoutAudits.filter { $0.status == .used }
            let errors = usedAudits.compactMap(\.normalizedError)
            return FatigueLearningWorkoutAuditSummary(
                workoutId: workoutId,
                date: date,
                totalAudits: workoutAudits.count,
                usedSetCount: usedAudits.count,
                medianError: errors.isEmpty ? nil : Self.medianError(errors)
            )
        }
        .sorted { $0.date > $1.date }
        .prefix(limit)
        .map { $0 }
    }

    func audits(for workoutId: UUID, exerciseId: UUID) async throws -> [FatigueLearningSetAudit] {
        try await auditRepo.fetchAudits(workoutId: workoutId, exerciseId: exerciseId)
    }

    func appliedFatigueRate(for exerciseId: UUID) async throws -> AppliedFatigueRateInfo {
        guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else {
            return AppliedFatigueRateInfo(rate: 0.04, source: .defaultRate)
        }
        let profile = try await healthProfileRepo.fetchOrCreate()
        return Self.appliedFatigueRate(for: exercise, profile: profile)
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
        let profile = try await healthProfileRepo.fetchOrCreate()
        let currentRate = Self.appliedFatigueRate(for: exercise, profile: profile).rate
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

    private static func appliedFatigueRate(for exercise: Exercise, profile: HealthProfile) -> AppliedFatigueRateInfo {
        if let rate = exercise.fatigueRate {
            return AppliedFatigueRateInfo(rate: rate, source: .exerciseOverride)
        }
        if let rate = profile.prescriptionLearnedFatigueRate {
            return AppliedFatigueRateInfo(rate: rate, source: .globalLearned)
        }
        return AppliedFatigueRateInfo(rate: 0.04, source: .defaultRate)
    }

    private func updateGlobalLearning(profile: HealthProfile, sessionError: Double) {
        let oldCount = profile.prescriptionFatigueLearningSessionCount ?? 0
        let newCount = oldCount + 1
        profile.prescriptionFatigueLearningSessionCount = newCount

        let oldCumError = profile.prescriptionFatigueLearningCumulativeError ?? 0.0
        let newCumError = Self.emaAlpha * sessionError + (1.0 - Self.emaAlpha) * oldCumError
        profile.prescriptionFatigueLearningCumulativeError = newCumError

        let currentRate = profile.prescriptionLearnedFatigueRate ?? 0.04
        let adjustment = Self.fatigueRateStep * Self.sign(newCumError)
        profile.prescriptionLearnedFatigueRate = Self.clamp(currentRate + adjustment, bounds: Self.fatigueRateBounds)
        profile.updatedAt = Date()
    }

    private func updateExerciseLearning(exercise: Exercise, profile: HealthProfile, sessionError: Double) async throws {
        let oldCount = exercise.fatigueLearningSessionCount ?? 0
        let newCount = oldCount + 1
        exercise.fatigueLearningSessionCount = newCount

        let oldCumError = exercise.fatigueLearningCumulativeError ?? 0.0
        let newCumError = Self.emaAlpha * sessionError + (1.0 - Self.emaAlpha) * oldCumError
        exercise.fatigueLearningCumulativeError = newCumError

        if newCount >= Self.minimumSessionsForLearning {
            let seededRate = exercise.fatigueRate ?? profile.prescriptionLearnedFatigueRate ?? 0.04
            let adjustment = Self.fatigueRateStep * Self.sign(newCumError)
            exercise.fatigueRate = Self.clamp(seededRate + adjustment, bounds: Self.fatigueRateBounds)
        }

        exercise.updatedAt = Date()
        try await exerciseRepo.save(exercise)
    }
}
