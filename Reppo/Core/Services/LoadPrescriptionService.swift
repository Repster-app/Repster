// LoadPrescriptionService.swift
// Fatigue-aware Smart Suggestions engine.
// Feature: Smart Suggestions (magic wand)
//
// Algorithm summary (v2):
// 1. Estimate capacity e1RM from recent workout history using recent top workout peaks
// 2. Accumulate session fatigue per set: baseFatigueRate * typeMultiplier * effortScale * repScale
// 3. Between sets: fatigue decays via exp(-restSeconds / τ), τ = 180s default (per-exercise override)
// 4. Forward-project fatigue across pending sets (progressive decrease)
// 5. Compute readiness e1RM from fatigue/freshness and clamp to 0.88–1.05 around capacity
// 6. Compute intensity_factor from selected formula: reverseCalculate(1.0, targetReps + targetRIR)
// 7. target_weight = readiness_e1RM × intensity_factor, rounded to increment
//
// Fatigue model calibrated against: Willardson load-reduction studies,
// Nuzzo/SBS rep drop-off meta-analysis, RTS fatigue percents, PCr resynthesis research.
//
// Architecture: Actor — accesses SwiftData only through repository protocols.

import Foundation

actor LoadPrescriptionService: LoadPrescriptionServiceProtocol {

    // MARK: - Dependencies

    private let setRepo: SetRepositoryProtocol
    private let exerciseRepo: ExerciseRepositoryProtocol
    private let workoutRepo: WorkoutRepositoryProtocol
    private let performanceRecordRepo: PerformanceRecordRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol
    private let calibrationProvider: any SuggestionCalibrationProviderProtocol

    // MARK: - Constants (defaults when no per-exercise override)

    /// Default weight increment (kg) when exercise has no override.
    private static let defaultWeightIncrement: Double = 2.5

    /// Number of recent completed workouts used for peak-oriented capacity.
    private static let recentWorkoutPeakWindow: Int = 3

    init(
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol,
        workoutRepository: WorkoutRepositoryProtocol,
        performanceRecordRepository: PerformanceRecordRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol,
        calibrationProvider: any SuggestionCalibrationProviderProtocol = NeutralSuggestionCalibrationProvider()
    ) {
        self.setRepo = setRepository
        self.exerciseRepo = exerciseRepository
        self.workoutRepo = workoutRepository
        self.performanceRecordRepo = performanceRecordRepository
        self.healthProfileRepo = healthProfileRepository
        self.calibrationProvider = calibrationProvider
    }

    // MARK: - LoadPrescriptionServiceProtocol

    func estimateBaseE1RM(
        exerciseId: UUID,
        completedSessionSets _: [SessionSetContext]
    ) async throws -> BaseE1RMEstimate {
        let profile = try await healthProfileRepo.fetchOrCreate()
        let formula = E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley

        let historical = try await estimateCapacityBaseE1RM(
            exerciseId: exerciseId,
            recencyWeeks: profile.prescriptionRecencyWeeks ?? 6,
            formula: formula
        )
        return BaseE1RMEstimate(value: historical.0, source: historical.1)
    }

    func evaluateSuggestions(
        exerciseId: UUID,
        pendingSets: [SuggestionPendingSetInput],
        completedSessionSets: [SessionSetContext]
    ) async throws -> SuggestionEvaluation {
        let profile = try await healthProfileRepo.fetchOrCreate()

        guard profile.prescriptionEnabled ?? true else {
            return .unavailable(.featureDisabled)
        }

        guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else {
            return .unavailable(.missingExercise)
        }

        guard !pendingSets.isEmpty else {
            return .unavailable(.noPendingSets)
        }

        let restTimerSeconds = Double(exercise.defaultRestTime ?? profile.defaultRestTimeSeconds ?? 150)
        let weightIncrement = exercise.weightIncrement ?? profile.prescriptionDefaultIncrement ?? Self.defaultWeightIncrement
        let fatigueEnabled = profile.prescriptionFatigueModelingEnabled ?? true
        let freshnessEnabled = profile.prescriptionFreshnessBonus ?? false
        let freshnessPercent = profile.prescriptionFreshnessBonusPercent ?? 0.03
        let formula = E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley
        let baseFatigueRate = exercise.fatigueRate ?? profile.prescriptionLearnedFatigueRate ?? 0.04
        let recoveryConstant = exercise.recoveryConstant ?? profile.prescriptionDefaultRecoveryConstant ?? 180.0

        let baseEstimate = try await estimateBaseE1RM(
            exerciseId: exerciseId,
            completedSessionSets: completedSessionSets
        )

        guard let baseE1RM = baseEstimate.value, baseEstimate.source != .noData else {
            return .unavailable(.noStrengthData)
        }

        let calibrationAdjustment = await calibrationProvider.calibrationAdjustment(for: exerciseId)

        let input = SuggestionEngineInput(
            baseE1RM: baseE1RM,
            baseSource: baseEstimate.source,
            completedSessionSets: completedSessionSets,
            pendingSets: pendingSets,
            settings: SuggestionSettingsSnapshot(
                formula: formula,
                restTimerSeconds: restTimerSeconds,
                weightIncrement: weightIncrement,
                fatigueEnabled: fatigueEnabled,
                freshnessEnabled: freshnessEnabled,
                freshnessPercent: freshnessPercent,
                baseFatigueRate: baseFatigueRate,
                recoveryConstant: recoveryConstant,
                sessionCapabilityPolicy: .observed
            ),
            calibrationAdjustment: calibrationAdjustment
        )

        return SuggestionEvaluation(
            input: input,
            decisions: SuggestionEngine.evaluate(input),
            unavailableReason: nil
        )
    }

    func prescribe(_ request: PrescriptionRequest) async throws -> PrescriptionResult? {
        let results = try await prescribeBatch(
            exerciseId: request.exerciseId,
            sets: [(targetReps: request.targetReps, targetRIR: request.targetRIR, setIndex: request.setIndex, repRange: nil)],
            completedSessionSets: request.completedSessionSets
        )
        return results.first ?? nil
    }

    func prescribeBatch(
        exerciseId: UUID,
        sets: [(targetReps: Int, targetRIR: Double, setIndex: Int, repRange: ClosedRange<Int>?)],
        completedSessionSets: [SessionSetContext]
    ) async throws -> [PrescriptionResult?] {
        let pendingSets = sets.enumerated().map { index, set in
            SuggestionPendingSetInput(
                setId: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index + 1))") ?? UUID(),
                setIndex: set.setIndex,
                setNumber: index + 1,
                target: SuggestionTarget(
                    reps: set.targetReps,
                    rir: set.targetRIR,
                    repRange: set.repRange,
                    repsSource: .explicitSet,
                    rirSource: .explicitSet
                ),
                setType: .working
            )
        }

        let evaluation = try await evaluateSuggestions(
            exerciseId: exerciseId,
            pendingSets: pendingSets,
            completedSessionSets: completedSessionSets
        )

        guard !evaluation.decisions.isEmpty else {
            return Array(repeating: nil, count: sets.count)
        }

        let resultsBySetId = Dictionary(uniqueKeysWithValues: evaluation.decisions.map { ($0.setId, $0) })
        return pendingSets.map { pendingSet in
            guard let result = resultsBySetId[pendingSet.setId] else { return nil }
            return PrescriptionResult(
                prescribedWeight: result.prescribedWeight,
                rawWeight: result.rawWeight,
                weightIncrement: result.weightIncrement,
                baseE1RM: result.baseE1RM,
                effectiveE1RM: result.effectiveE1RM,
                intensityFactor: result.intensityFactor,
                fatigueDiscount: result.fatigueDiscount,
                freshnessApplied: result.freshnessApplied,
                e1RMSource: result.e1RMSource,
                bestReps: result.bestReps
            )
        }
    }

    // MARK: - Base e1RM Estimation

    /// Estimate capacity baseline e1RM from recent workout history.
    ///
    /// Steps:
    /// 1) Keep eligible working sets in recency window
    /// 2) Compute per-workout peak e1RM from stored snapshots
    /// 3) Take the top value across the last N completed workouts
    /// 4) Fallback to PR table when history is insufficient
    private func estimateCapacityBaseE1RM(
        exerciseId: UUID,
        recencyWeeks: Int,
        formula: E1RMFormula
    ) async throws -> (Double?, E1RMSource) {

        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .weekOfYear, value: -recencyWeeks, to: now)!

        // Fetch recent sets within the recency window
        let recentSets = try await setRepo.fetchSets(
            exerciseId: exerciseId,
            from: windowStart,
            to: now
        )
        let excludedWorkoutIds = try await excludedWorkoutIds(
            for: exerciseId,
            workoutIds: Set(recentSets.map(\.workoutId))
        )

        // Filter to completed non-warmup sets with stored e1RM snapshots.
        let eligibleSets = recentSets.filter { set in
            return set.completed &&
                !excludedWorkoutIds.contains(set.workoutId) &&
                set.setType != .warmup &&
                set.setType != .partial &&
                (set.e1RM ?? 0) > 0
        }

        if !eligibleSets.isEmpty {
            let workouts = Dictionary(grouping: eligibleSets, by: \.workoutId)
                .compactMap { (_, sets) -> (date: Date, value: Double)? in
                    guard let workoutDate = sets.map(\.date).max() else { return nil }
                    let workoutBest = sets.compactMap(\.e1RM).max() ?? 0
                    guard workoutBest > 0 else { return nil }
                    return (date: workoutDate, value: workoutBest)
                }
                .sorted { $0.date > $1.date }

            if !workouts.isEmpty {
                let recentWorkouts = workouts.prefix(Self.recentWorkoutPeakWindow)
                let capacity = recentWorkouts.map(\.value).max() ?? 0
                if capacity > 0 {
                    return (capacity, .recentPerformance)
                }
            }
        }

        // Final fallback: use the PR table
        let prE1RM = try await estimateFromPRTable(exerciseId: exerciseId, formula: formula)
        if let prE1RM, prE1RM > 0 {
            print("[Prescription] Using PR table fallback: e1RM = \(String(format: "%.1f", prE1RM)) kg")
            return (prE1RM, .historicalPR)
        }

        return (nil, .noData)
    }

    /// Estimate e1RM from the PR table (PerformanceRecord) as a fallback.
    ///
    /// Uses the highest-weight PR and applies the user's selected formula to estimate 1RM.
    private func estimateFromPRTable(exerciseId: UUID, formula: E1RMFormula) async throws -> Double? {
        let records = try await performanceRecordRepo.fetchAll(
            for: exerciseId,
            recordType: .repMax
        )

        guard !records.isEmpty else { return nil }

        // Find the PR that gives the highest e1RM estimate
        var bestE1RM: Double = 0

        for record in records {
            let reps = record.reps ?? 1
            let weight = record.value

            guard weight > 0, reps > 0 else { continue }

            let e1RM = formula.calculate(weight: weight, reps: reps)
            bestE1RM = max(bestE1RM, e1RM)
        }

        return bestE1RM > 0 ? bestE1RM : nil
    }

    private func excludedWorkoutIds(
        for exerciseId: UUID,
        workoutIds: Set<UUID>
    ) async throws -> Set<UUID> {
        let workouts = try await workoutRepo.fetch(byIds: workoutIds)
        return Set(
            workouts.compactMap { workout in
                workout.excludesFromProgressionHistory(exerciseId: exerciseId) ? workout.id : nil
            }
        )
    }

}
