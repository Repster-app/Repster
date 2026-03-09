// LoadPrescriptionService.swift
// Fatigue-aware weight prescription engine.
// Feature: Weight Prescription (magic wand)
//
// Algorithm summary:
// 1. Estimate base e1RM from recent sets, using user's selected formula (Epley/Brzycki/Lombardi)
// 2. Accumulate session fatigue: each set adds 3% base + up to 4% RIR bonus, scaled by reps
// 3. Between sets: fatigue decays via exp(-restTimerSeconds / τ), where τ = 300s
// 4. Compute effective e1RM = base × (1 − sessionFatigue), capped at 20%
// 5. Compute intensity_factor from selected formula: reverseCalculate(1.0, targetReps + targetRIR)
// 6. target_weight = effective_e1RM × intensity_factor, rounded to increment
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

    /// Maximum RIR to consider a set "hard" for e1RM estimation.
    private static let hardSetMaxRIR: Double = 1.0

    /// Exponential decay half-life in days for recency weighting.
    /// Sets from `halfLifeDays` ago get 50% weight.
    private static let recencyHalfLifeDays: Double = 21.0

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

    func prescribe(_ request: PrescriptionRequest) async throws -> PrescriptionResult? {
        let results = try await prescribeBatch(
            exerciseId: request.exerciseId,
            sets: [(targetReps: request.targetReps, targetRIR: request.targetRIR, setIndex: request.setIndex)],
            completedSessionSets: request.completedSessionSets
        )
        return results.first ?? nil
    }

    func prescribeBatch(
        exerciseId: UUID,
        sets: [(targetReps: Int, targetRIR: Double, setIndex: Int)],
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

        // 3. Estimate base e1RM — in-session performance overrides history
        var baseE1RM: Double?
        var source: E1RMSource = .noData

        // 3a. In-session override: if completed sets exist, compute e1RM from the best one
        let completedWithData = completedSessionSets.filter { $0.completed && $0.reps > 0 && $0.weight > 0 }
        if !completedWithData.isEmpty {
            var bestSessionE1RM: Double = 0
            for s in completedWithData {
                let e1RM = computeE1RMFromSet(weight: s.weight, reps: s.reps, rir: s.rir, formula: formula)
                if e1RM > bestSessionE1RM {
                    bestSessionE1RM = e1RM
                    print("[Prescription] In-session e1RM from: \(String(format: "%.1f", s.weight)) kg × \(s.reps) reps" +
                          " @ RIR \(s.rir.map { String(format: "%.0f", $0) } ?? "unknown→0")" +
                          " → e1RM = \(String(format: "%.1f", e1RM)) kg")
                }
            }
            if bestSessionE1RM > 0 {
                baseE1RM = bestSessionE1RM
                source = .recentPerformance
                print("[Prescription] Using IN-SESSION e1RM: \(String(format: "%.1f", bestSessionE1RM)) kg (overrides history)")
            }
        }

        // 3b. Fallback: historical e1RM from most recent workout (only if no session data)
        if baseE1RM == nil {
            let (histE1RM, histSource) = try await estimateBaseE1RM(
                exerciseId: exerciseId,
                recencyWeeks: profile.prescriptionRecencyWeeks ?? 6,
                formula: formula
            )
            baseE1RM = histE1RM
            source = histSource
        }

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

            // Effective e1RM
            var effectiveE1RM = baseE1RM * fatigueDiscount

            // Freshness bonus on first set (PDF section 8)
            var freshnessApplied = false
            if isFirstSet && freshnessEnabled {
                effectiveE1RM *= (1.0 + freshnessPercent)
                freshnessApplied = true
            }

            // Intensity factor: use same formula as e1RM estimation for consistency.
            // reverseCalculate(1.0, totalReps) gives %1RM for that rep count.
            let totalReps = max(1, setSpec.targetReps + Int(setSpec.targetRIR))
            let intensityFactor = max(0.3, formula.reverseCalculate(e1RM: 1.0, reps: totalReps))

            // Target weight
            let rawWeight = effectiveE1RM * intensityFactor

            // Round to nearest weight increment
            let prescribedWeight = roundToIncrement(rawWeight, increment: weightIncrement)

            return PrescriptionResult(
                prescribedWeight: max(0, prescribedWeight),
                baseE1RM: baseE1RM,
                effectiveE1RM: effectiveE1RM,
                intensityFactor: intensityFactor,
                fatigueDiscount: fatigueDiscount,
                freshnessApplied: freshnessApplied,
                e1RMSource: source
            )
        }
    }

    // MARK: - Base e1RM Estimation

    /// Estimate the user's current base e1RM for an exercise.
    ///
    /// Strategy (simplified):
    /// 1. Find the single heaviest non-warmup set from the most recent workout
    /// 2. Compute e1RM using Brzycki with RIR adjustment (assume RIR 0 if unknown)
    /// 3. Fallback: use PerformanceRecord (PR table) if no recent sets
    private func estimateBaseE1RM(
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

        // Filter to completed non-warmup sets with actual weight + reps data
        let eligibleSets = recentSets.filter { set in
            set.completed &&
            set.hasData &&
            set.setType != .warmup &&
            set.setType != .partial &&
            (set.effectiveWeight ?? 0) > 0 &&
            (set.reps ?? 0) > 0
        }

        if !eligibleSets.isEmpty {
            // Group by workoutId, find the most recent workout
            let grouped = Dictionary(grouping: eligibleSets, by: \.workoutId)
            let mostRecentWorkoutId = grouped.keys
                .compactMap { wid -> (UUID, Date)? in
                    guard let maxDate = grouped[wid]?.map(\.date).max() else { return nil }
                    return (wid, maxDate)
                }
                .sorted { $0.1 > $1.1 }
                .first?.0

            if let workoutId = mostRecentWorkoutId, let workoutSets = grouped[workoutId] {
                // Find the set that yields the highest computed e1RM (not just heaviest weight)
                var bestE1RM: Double = 0
                var bestSetForLog: (weight: Double, reps: Int, rir: Double?, e1RM: Double)?

                for set in workoutSets {
                    guard let ew = set.effectiveWeight, let reps = set.reps, ew > 0, reps > 0 else { continue }
                    let e1RM = computeE1RMFromSet(weight: ew, reps: reps, rir: set.rir, formula: formula)
                    if e1RM > bestE1RM {
                        bestE1RM = e1RM
                        bestSetForLog = (weight: ew, reps: reps, rir: set.rir, e1RM: e1RM)
                    }
                }

                if let best = bestSetForLog {
                    print("[Prescription] Historical e1RM from best set: \(String(format: "%.1f", best.weight)) kg × \(best.reps) reps" +
                          " @ RIR \(best.rir.map { String(format: "%.0f", $0) } ?? "unknown→0")" +
                          " → e1RM = \(String(format: "%.1f", best.e1RM)) kg" +
                          (best.rir != nil ? "" : " ⚠️ No RIR (assumed 0, conservative)"))

                    return (bestE1RM, .recentPerformance)
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

    /// Compute e1RM from a single set using the user's selected formula with RIR adjustment.
    /// When RIR is nil, assumes RIR 0 (conservative — treats reps as max).
    private func computeE1RMFromSet(weight: Double, reps: Int, rir: Double?, formula: E1RMFormula) -> Double {
        // Total reps = actual reps + RIR (assumed 0 if unknown)
        let totalReps = Int(Double(reps) + (rir ?? 0))
        guard totalReps > 0 else { return weight }
        return formula.calculate(weight: weight, reps: totalReps)
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
