// LoadPrescriptionService.swift
// Fatigue-aware Smart Suggestions engine.
// Feature: Smart Suggestions (magic wand)
//
// Algorithm summary (v2):
// 1. Estimate capacity e1RM from recent workout history using recent top workout peaks
// 2. Accumulate session fatigue per set: baseFatigueRate * typeMultiplier * effortScale * repScale
// 3. Between sets: fatigue decays via exp(-restSeconds / τ), τ = 180s default (per-exercise override)
// 4. Forward-project fatigue across pending sets (progressive decrease)
// 5. Compute readiness e1RM from fatigue/freshness with no clamp floor
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
    private let healthProfileRepo: HealthProfileRepositoryProtocol
    private let calibrationProvider: any SuggestionCalibrationProviderProtocol

    // MARK: - Constants (defaults when no per-exercise override)

    /// Number of recent completed workouts used for peak-oriented capacity.
    private static let recentWorkoutPeakWindow: Int = 3

    init(
        setRepository: SetRepositoryProtocol,
        exerciseRepository: ExerciseRepositoryProtocol,
        workoutRepository: WorkoutRepositoryProtocol,
        healthProfileRepository: HealthProfileRepositoryProtocol,
        calibrationProvider: any SuggestionCalibrationProviderProtocol = NeutralSuggestionCalibrationProvider()
    ) {
        self.setRepo = setRepository
        self.exerciseRepo = exerciseRepository
        self.workoutRepo = workoutRepository
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

        return try await estimateCapacityBaseE1RM(
            exerciseId: exerciseId,
            recencyWeeks: profile.prescriptionRecencyWeeks ?? 6,
            formula: formula
        )
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
        let weightIncrement = UnitConversion.resolvedStoredWeightIncrement(
            exerciseIncrement: exercise.weightIncrement,
            defaultIncrement: profile.prescriptionDefaultIncrement,
            unitPreference: profile.unitPreference
        )
        let fatigueEnabled = profile.prescriptionFatigueModelingEnabled ?? true
        let freshnessEnabled = profile.prescriptionFreshnessBonus ?? false
        let freshnessPercent = profile.prescriptionFreshnessBonusPercent ?? 0.03
        let formula = E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley
        let baseFatigueRate = FatigueLearningService.appliedFatigueRateInfo(for: exercise, profile: profile).rate
        let recoveryConstant = exercise.recoveryConstant ?? profile.prescriptionDefaultRecoveryConstant ?? 180.0

        let baseEstimate = try await estimateBaseE1RM(
            exerciseId: exerciseId,
            completedSessionSets: completedSessionSets
        )

        guard let baseE1RM = baseEstimate.value, baseEstimate.source != .noData else {
            return .unavailable(
                baseEstimate.suppressedForBodyweightHistory ? .bodyweightHistoryOnly : .noStrengthData
            )
        }

        let calibrationAdjustment = await calibrationProvider.calibrationAdjustment(for: exerciseId)

        let input = SuggestionEngineInput(
            baseE1RM: baseE1RM,
            baseSource: baseEstimate.source,
            baseSourceWorkoutDate: baseEstimate.sourceWorkoutDate,
            baseSourceTopSet: baseEstimate.topSet,
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
                sessionCapabilityPolicy: .observed,
                capacityGuardsEnabled: profile.prescriptionCapacityGuardsEnabled ?? true
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
                e1RMSourceWorkoutDate: result.e1RMSourceWorkoutDate,
                bestReps: result.bestReps
            )
        }
    }

    // MARK: - Base e1RM Estimation

    /// Estimate capacity baseline e1RM from logged workout history.
    ///
    /// Two-tier fallback:
    /// 1. **In-window peak** — eligible sets inside the configured recency window;
    ///    peak across the last N completed workouts. Returns `.recentPerformance`.
    /// 2. **Most recent workout (any age)** — if the window is empty, walk back
    ///    through all logged sets and use the peak from the *most recent* eligible
    ///    workout, regardless of age. Returns `.staleRecentPerformance` with the
    ///    anchor workout's date so the UI can flag the suggestion as low-confidence.
    /// 3. **No data** — returns `.noData` if the exercise has never been logged.
    ///
    /// Note: there is no PR-table fallback. `PerformanceRecord` entries in this app
    /// are only created from logged sets (see `PRService`), so a present PR implies
    /// a present logged set — tier 2 will always reach it first.
    private func estimateCapacityBaseE1RM(
        exerciseId: UUID,
        recencyWeeks: Int,
        formula: E1RMFormula
    ) async throws -> BaseE1RMEstimate {

        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .weekOfYear, value: -recencyWeeks, to: now)!

        // --- Tier 1: in-window recent sets ---
        let recentSets = try await setRepo.fetchSets(
            exerciseId: exerciseId,
            from: windowStart,
            to: now
        )
        let inWindowExcluded = try await excludedWorkoutIds(
            for: exerciseId,
            workoutIds: Set(recentSets.map(\.workoutId))
        )
        let inWindowEligible = recentSets.filter { isEligibleForCapacity(set: $0, excludedWorkoutIds: inWindowExcluded) }

        if let inWindow = peakAcrossRecentWorkouts(
            inWindowEligible,
            limit: Self.recentWorkoutPeakWindow,
            formula: formula
        ) {
            return BaseE1RMEstimate(
                value: inWindow.value,
                source: .recentPerformance,
                sourceWorkoutDate: inWindow.workoutDate,
                topSet: inWindow.topSet
            )
        }

        // --- Tier 2: most recent eligible workout of any age ---
        let allSets = try await setRepo.fetchSets(
            exerciseId: exerciseId,
            from: nil,
            to: now
        )
        let allExcluded = try await excludedWorkoutIds(
            for: exerciseId,
            workoutIds: Set(allSets.map(\.workoutId))
        )
        let allEligible = allSets.filter { isEligibleForCapacity(set: $0, excludedWorkoutIds: allExcluded) }

        if let mostRecent = peakAcrossRecentWorkouts(allEligible, limit: 1, formula: formula) {
            // A set logged at bodyweight can never be eligible: every e1RM formula is
            // `weight * repFactor`, so 0 kg yields 0 and fails the `> 0` test above. Without
            // this check the fallback reaches straight past a bodyweight era to the last
            // weighted session — a year back, in the reported case — and presents it as a
            // current load prescription. Withhold rather than mislead.
            let loggedAtBodyweightSince = allSets.contains { set in
                set.completed &&
                    set.hasData &&
                    set.setType != .warmup &&
                    set.setType != .partial &&
                    !allExcluded.contains(set.workoutId) &&
                    (set.e1RM ?? 0) <= 0 &&
                    set.date > mostRecent.workoutDate
            }
            if loggedAtBodyweightSince {
                dbg("""
                    [Prescription] Withholding stale baseline from \(mostRecent.workoutDate): \
                    exercise has been logged at bodyweight since
                    """)
                return BaseE1RMEstimate(
                    value: nil,
                    source: .noData,
                    sourceWorkoutDate: nil,
                    topSet: nil,
                    suppressedForBodyweightHistory: true
                )
            }

            dbg("""
                [Prescription] No in-window data; falling back to most recent workout \
                from \(mostRecent.workoutDate) (e1RM = \(String(format: "%.1f", mostRecent.value)) kg)
                """)
            return BaseE1RMEstimate(
                value: mostRecent.value,
                source: .staleRecentPerformance,
                sourceWorkoutDate: mostRecent.workoutDate,
                topSet: mostRecent.topSet
            )
        }

        // --- Tier 3: no logged sets ever ---
        return BaseE1RMEstimate(value: nil, source: .noData, sourceWorkoutDate: nil, topSet: nil)
    }

    /// Whether a set is eligible to contribute to the capacity baseline:
    /// completed, non-warmup, non-partial, has a stored e1RM, and not part of an
    /// excluded workout.
    private func isEligibleForCapacity(set: WorkoutSet, excludedWorkoutIds: Set<UUID>) -> Bool {
        return set.completed &&
            !excludedWorkoutIds.contains(set.workoutId) &&
            set.setType.countsAsPerformedWork &&
            (set.e1RM ?? 0) > 0
    }

    /// Group eligible sets by workout, take each workout's peak capacity, sort
    /// most-recent-first, and return the highest peak across the first `limit`
    /// workouts along with the date of the workout that produced that peak.
    private func peakAcrossRecentWorkouts(
        _ eligibleSets: [WorkoutSet],
        limit: Int,
        formula: E1RMFormula
    ) -> (value: Double, workoutDate: Date, topSet: HistoricalSetSnapshot)? {
        guard !eligibleSets.isEmpty, limit > 0 else { return nil }

        let workouts = Dictionary(grouping: eligibleSets, by: \.workoutId)
            .compactMap { (_, sets) -> (date: Date, value: Double, topSet: HistoricalSetSnapshot)? in
                guard let workoutDate = sets.map(\.date).max() else { return nil }
                // Rank on capacity, not on the stored e1RM — see `capacityE1RM`. Ranking on one
                // and reporting the other would let a set win the comparison and then contribute
                // a different number.
                guard let topSet = sets.max(by: {
                          capacityE1RM(for: $0, formula: formula) < capacityE1RM(for: $1, formula: formula)
                      }),
                      case let topCapacity = capacityE1RM(for: topSet, formula: formula),
                      topCapacity > 0 else { return nil }
                let snapshot = HistoricalSetSnapshot(
                    weight: topSet.effectiveWeight ?? topSet.weight ?? 0,
                    reps: topSet.prReps,
                    rir: topSet.performanceRIR,
                    date: workoutDate
                )
                return (date: workoutDate, value: topCapacity, topSet: snapshot)
            }
            .sorted { $0.date > $1.date }

        let candidates = Array(workouts.prefix(limit))
        guard let winner = candidates.max(by: { $0.value < $1.value }) else { return nil }
        return (value: winner.value, workoutDate: winner.date, topSet: winner.topSet)
    }

    /// What this set says the lifter can lift — reps **plus reps in reserve**.
    ///
    /// The stored `WorkoutSet.e1RM` is computed from reps alone (`SetService`), so it is a display
    /// figure, not a capacity figure: 60 kg x 8 @ RIR 2 stores 76.0 while the engine's own
    /// in-session estimator reads the same set as 80.0. Seeding the cross-session baseline from the
    /// stored value therefore understated capacity for anyone who trains with reps in reserve, and
    /// because a fixed rep target prices at `e1RM x intensityFactor(reps + targetRIR)`, the result
    /// was not a plateau but a ratchet *down* — roughly 4% per session at RIR 2.
    ///
    /// Recomputed here rather than by rewriting stored rows: no migration, and charts, PRs and
    /// history keep the display convention they have always used.
    ///
    /// Falls back to the stored value when no RIR was recorded, which is the same number as before
    /// — so histories with no RIR are unaffected.
    private func capacityE1RM(for set: WorkoutSet, formula: E1RMFormula) -> Double {
        guard let rir = set.performanceRIR, rir >= 0 else { return set.e1RM ?? 0 }
        let weight = set.effectiveWeight ?? set.weight ?? 0
        let reps = set.prReps
        guard weight > 0, reps > 0 else { return set.e1RM ?? 0 }
        return formula.calculate(weight: weight, reps: reps + Int(rir))
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
