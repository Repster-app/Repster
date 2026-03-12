// LoadPrescriptionService.swift
// Fatigue-aware weight prescription engine.
// Feature: Weight Prescription (magic wand)
//
// Algorithm summary:
// 1. Estimate capacity e1RM from recent workout history using recent top workout peaks
// 2. Accumulate session fatigue: each set adds 3% base + up to 4% RIR bonus, scaled by reps
// 3. Between sets: fatigue decays via exp(-restTimerSeconds / τ), where τ = 300s
// 4. Compute readiness e1RM from fatigue/freshness and clamp it to ±5% around capacity
// 5. Compute intensity_factor from selected formula: reverseCalculate(1.0, targetReps + targetRIR)
// 6. target_weight = readiness_e1RM × intensity_factor, rounded to increment
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
    private let performanceRecordRepo: PerformanceRecordRepositoryProtocol
    private let healthProfileRepo: HealthProfileRepositoryProtocol

    // MARK: - Constants (defaults when no per-exercise override)

    /// Recovery time constant (τ) in seconds for exponential fatigue decay.
    /// After τ seconds of rest, 63% of accumulated fatigue is recovered.
    /// Calibrated against PCr resynthesis research (slow component τ > 170s)
    /// and load-reduction studies (~5% per set at 2 min rest).
    private static let recoveryConstant: Double = 300.0

    /// Maximum session fatigue (cap). Research shows even extreme protocols
    /// (to failure, short rest) rarely cause >25% performance decline.
    private static let maxFatigue: Double = 0.20

    /// Default weight increment (kg) when exercise has no override.
    private static let defaultWeightIncrement: Double = 2.5

    /// Number of recent completed workouts used for peak-oriented capacity.
    private static let recentWorkoutPeakWindow: Int = 3

    /// Readiness is bounded to a small band around baseline capacity.
    private static let readinessMinFactor: Double = 0.95
    private static let readinessMaxFactor: Double = 1.05

    init(
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol,
        performanceRecordRepository: PerformanceRecordRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol
    ) {
        self.setRepo = setRepository
        self.exerciseRepo = exerciseRepository
        self.performanceRecordRepo = performanceRecordRepository
        self.healthProfileRepo = healthProfileRepository
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

        // 1. Fetch settings + exercise data
        let profile = try await healthProfileRepo.fetchOrCreate()

        guard profile.prescriptionEnabled ?? true else {
            return Array(repeating: nil, count: sets.count)
        }

        guard let exercise = try await exerciseRepo.fetch(byId: exerciseId) else {
            return Array(repeating: nil, count: sets.count)
        }

        // 2. Resolve per-exercise vs global parameters
        let restTimerSeconds = Double(exercise.defaultRestTime ?? profile.defaultRestTimeSeconds ?? 150)
        let weightIncrement = exercise.weightIncrement ?? profile.prescriptionDefaultIncrement ?? Self.defaultWeightIncrement
        let fatigueEnabled = profile.prescriptionFatigueModelingEnabled ?? true
        let freshnessEnabled = profile.prescriptionFreshnessBonus ?? false
        let freshnessPercent = profile.prescriptionFreshnessBonusPercent ?? 0.03
        let formula = E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley

        // 3. Estimate base e1RM — shared with other consumers (Exercise Info, etc.)
        let baseEstimate = try await estimateBaseE1RM(
            exerciseId: exerciseId,
            completedSessionSets: completedSessionSets
        )
        let baseE1RM = baseEstimate.value
        let source = baseEstimate.source

        guard let baseE1RM, source != .noData else {
            return Array(repeating: nil, count: sets.count)
        }

        // 4. Compute session fatigue from completed sets
        let sessionFatigue: Double
        if fatigueEnabled {
            sessionFatigue = computeSessionFatigue(
                completedSets: completedSessionSets,
                restTimerSeconds: restTimerSeconds
            )
        } else {
            sessionFatigue = 0.0
        }

        // 5. Prescribe each set
        // Freshness bonus should apply to the first suggested working set,
        // not strictly the absolute set index 0 (warmups may come first).
        let firstSuggestedSetIndex = sets.map(\.setIndex).min()
        return sets.map { setSpec in
            let isFirstSet = completedSessionSets.isEmpty && setSpec.setIndex == firstSuggestedSetIndex

            // Fatigue discount: linear (interpretable — "8% fatigue" = exactly 8% load reduction)
            let fatigueDiscount = 1.0 - sessionFatigue

            // Readiness around stable capacity.
            var readinessRawE1RM = baseE1RM * fatigueDiscount

            // Freshness bonus on first set (PDF section 8)
            var freshnessApplied = false
            if isFirstSet && freshnessEnabled {
                readinessRawE1RM *= (1.0 + freshnessPercent)
                freshnessApplied = true
            }
            let minReadiness = baseE1RM * Self.readinessMinFactor
            let maxReadiness = baseE1RM * Self.readinessMaxFactor
            let effectiveE1RM = min(max(readinessRawE1RM, minReadiness), maxReadiness)

            // Rep range optimization: when a range is provided, evaluate each rep count
            // and pick the (weight, reps) pair whose implied e1RM is closest to effectiveE1RM.
            // This minimizes the distortion introduced by coarse weight increments.
            let bestReps: Int?
            let intensityFactor: Double
            let rawWeight: Double
            let prescribedWeight: Double

            if let range = setSpec.repRange, range.count > 1 {
                var bestError = Double.infinity
                var winnerReps = setSpec.targetReps
                var winnerIntensity = 0.0
                var winnerRaw = 0.0
                var winnerRounded = 0.0

                for candidateReps in range {
                    let totalReps = max(1, candidateReps + Int(setSpec.targetRIR))
                    let candidateIntensity = max(0.3, formula.reverseCalculate(e1RM: 1.0, reps: totalReps))
                    let candidateRaw = effectiveE1RM * candidateIntensity
                    let candidateRounded = roundToIncrement(candidateRaw, increment: weightIncrement)

                    // Implied e1RM if the user lifts this rounded weight for totalReps
                    let impliedE1RM = formula.calculate(weight: candidateRounded, reps: totalReps)
                    let error = abs(impliedE1RM - effectiveE1RM)

                    if error < bestError {
                        bestError = error
                        winnerReps = candidateReps
                        winnerIntensity = candidateIntensity
                        winnerRaw = candidateRaw
                        winnerRounded = candidateRounded
                    }
                }

                bestReps = winnerReps
                intensityFactor = winnerIntensity
                rawWeight = winnerRaw
                prescribedWeight = winnerRounded
            } else {
                // Single target reps (no range)
                bestReps = nil
                let totalReps = max(1, setSpec.targetReps + Int(setSpec.targetRIR))
                intensityFactor = max(0.3, formula.reverseCalculate(e1RM: 1.0, reps: totalReps))
                rawWeight = effectiveE1RM * intensityFactor
                prescribedWeight = roundToIncrement(rawWeight, increment: weightIncrement)
            }

            return PrescriptionResult(
                prescribedWeight: max(0, prescribedWeight),
                rawWeight: rawWeight,
                weightIncrement: weightIncrement,
                baseE1RM: baseE1RM,
                effectiveE1RM: effectiveE1RM,
                intensityFactor: intensityFactor,
                fatigueDiscount: fatigueDiscount,
                freshnessApplied: freshnessApplied,
                e1RMSource: source,
                bestReps: bestReps
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

        // Filter to completed non-warmup sets with stored e1RM snapshots.
        let eligibleSets = recentSets.filter { set in
            return set.completed &&
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

    // MARK: - Session Fatigue Modeling

    /// Compute accumulated session fatigue from completed sets.
    ///
    /// Every completed set adds fatigue (3% base + up to 4% RIR bonus, scaled by reps).
    /// Between sets, fatigue decays exponentially using the rest timer duration
    /// and a fixed recovery constant (τ = 300s).
    ///
    /// Calibrated against research:
    /// - Willardson load-reduction studies: ~5% per set at 2 min rest
    /// - Nuzzo/SBS rep drop-off meta-analysis: set-to-set performance decline
    /// - RTS fatigue percents: 5-10% typical session fatigue
    /// - PCr resynthesis: biphasic recovery, slow component τ > 170s
    private func computeSessionFatigue(
        completedSets: [SessionSetContext],
        restTimerSeconds: Double
    ) -> Double {
        var sessionFatigue: Double = 0.0

        let sortedSets = completedSets.filter { $0.completed }

        for (index, set) in sortedSets.enumerated() {
            // Rest decay: use rest timer setting as assumed rest duration
            if index > 0 {
                sessionFatigue *= exp(-restTimerSeconds / Self.recoveryConstant)
            }

            // Per-set fatigue contribution:
            // - Base: 3% per set (every set causes some fatigue)
            // - RIR bonus: up to 4% extra for hard sets (RIR 0 = +4%, RIR 1 = +2%, RIR 2+ = +0%)
            // - Rep scale: normalized to 8 reps, capped at 1.5× to prevent extreme values
            let rir = set.rir ?? 2.0
            let baseFatigue: Double = 0.03
            let rirBonus = max(0.0, 2.0 - rir) * 0.02
            let repScale = min(Double(set.reps) / 8.0, 1.5)
            let setFatigue = (baseFatigue + rirBonus) * repScale

            sessionFatigue += setFatigue
        }

        return min(sessionFatigue, Self.maxFatigue)
    }

    // MARK: - Helpers

    /// Round a weight value to the nearest increment.
    ///
    /// Examples with 2.5kg increment:
    /// - 81.3 → 82.5
    /// - 80.0 → 80.0
    /// - 79.1 → 80.0
    private func roundToIncrement(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }
}
