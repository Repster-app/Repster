// LoadPrescriptionServiceProtocol.swift
// Contract for the fatigue-aware weight prescription engine.
// Based on: RIR_Fatigue_Aware_1RM_Model.pdf
// Feature: Weight Prescription (magic wand)

import Foundation

/// Input describing a single set in the current session for fatigue modeling.
/// Used by the prescription engine to accumulate session fatigue.
struct SessionSetContext: Sendable {
    /// Weight used for this set (kg).
    let weight: Double
    /// Reps performed (or target reps for upcoming sets).
    let reps: Int
    /// RIR at completion (nil if not recorded).
    let rir: Double?
    /// When this set was completed (nil if not yet completed).
    let completedAt: Date?
    /// Whether this set has been completed.
    let completed: Bool
}

/// A pending set that needs a smart suggestion.
struct SuggestionPendingSetInput: Sendable {
    /// The underlying WorkoutSet identifier for row-level mapping.
    let setId: UUID
    /// The set's position in the exercise (0-indexed, including warmups in the source array).
    let setIndex: Int
    /// The display set number among non-warmup sets (1-indexed).
    let setNumber: Int
    /// The single reps target used when no range optimization applies.
    let targetReps: Int
    /// The target RIR used for load selection.
    let targetRIR: Double
    /// Optional rep range for range-aware optimization.
    let repRange: ClosedRange<Int>?
}

/// Snapshot of resolved settings and exercise overrides used by the engine.
struct SuggestionSettingsSnapshot: Sendable {
    let formula: E1RMFormula
    let restTimerSeconds: Double
    let weightIncrement: Double
    let fatigueEnabled: Bool
    let freshnessEnabled: Bool
    let freshnessPercent: Double
}

/// Normalized engine input after app-model resolution.
struct SuggestionEngineInput: Sendable {
    let baseE1RM: Double
    let baseSource: E1RMSource
    let completedSessionSets: [SessionSetContext]
    let pendingSets: [SuggestionPendingSetInput]
    let settings: SuggestionSettingsSnapshot
}

/// Pure engine output for one pending set.
struct SuggestionEngineResult: Sendable {
    let setId: UUID
    let setIndex: Int
    let setNumber: Int
    let targetReps: Int
    let targetRIR: Double
    let repRange: ClosedRange<Int>?
    let prescribedWeight: Double
    let rawWeight: Double
    let weightIncrement: Double
    let baseE1RM: Double
    let effectiveE1RM: Double
    let intensityFactor: Double
    let fatigueDiscount: Double
    let freshnessApplied: Bool
    let e1RMSource: E1RMSource
    let bestReps: Int?
}

/// Bundles normalized input with the engine's outputs for explanation/UI layers.
struct SuggestionEvaluation: Sendable {
    let input: SuggestionEngineInput
    let results: [SuggestionEngineResult]
}

/// Request to prescribe weight for a single set.
struct PrescriptionRequest: Sendable {
    /// The exercise to prescribe for.
    let exerciseId: UUID
    /// Target reps for this set. For rep ranges, use the midpoint.
    let targetReps: Int
    /// Target RIR for this set.
    let targetRIR: Double
    /// The set's position in the exercise (0-indexed).
    let setIndex: Int
    /// All completed sets for this exercise in the current session (for fatigue calculation).
    let completedSessionSets: [SessionSetContext]
}

/// Result of a weight prescription calculation.
struct PrescriptionResult: Sendable {
    /// The prescribed weight in kg, rounded to the nearest increment.
    let prescribedWeight: Double
    /// The raw weight before rounding (for debug display).
    let rawWeight: Double
    /// The weight increment used for rounding (for debug display).
    let weightIncrement: Double
    /// The base e1RM used for the calculation (before fatigue).
    let baseE1RM: Double
    /// The effective e1RM after fatigue discount.
    let effectiveE1RM: Double
    /// The intensity factor applied (reps + RIR → %1RM).
    let intensityFactor: Double
    /// The fatigue discount applied (1.0 = no fatigue).
    let fatigueDiscount: Double
    /// Whether a freshness bonus was applied.
    let freshnessApplied: Bool
    /// Source of the e1RM estimate.
    let e1RMSource: E1RMSource
    /// When rep range optimization was used, the optimal rep count chosen.
    /// Nil when no range was provided (single target reps).
    let bestReps: Int?
}

/// Shared base e1RM estimate result for consumers that need a consistent source/value pair.
struct BaseE1RMEstimate: Sendable {
    let value: Double?
    let source: E1RMSource
}

/// How the base e1RM was determined.
enum E1RMSource: Sendable {
    /// From recent workout history in the recency window (top-performance baseline).
    case recentPerformance
    /// From the PR table (PerformanceRecord) — less reliable for current strength.
    case historicalPR
    /// No data available — prescription not possible.
    case noData
}

/// Pure smart-suggestion calculation engine.
///
/// The engine has no repository or view-model dependencies. It operates only on
/// normalized inputs so the current behavior can be audited and evolved separately
/// from app-model gathering and UI explanation.
enum SuggestionEngine {
    private static let recoveryConstant: Double = 300.0
    private static let maxFatigue: Double = 0.20
    private static let readinessMinFactor: Double = 0.95
    private static let readinessMaxFactor: Double = 1.05

    static func evaluate(_ input: SuggestionEngineInput) -> [SuggestionEngineResult] {
        let sessionFatigue: Double
        if input.settings.fatigueEnabled {
            sessionFatigue = computeSessionFatigue(
                completedSets: input.completedSessionSets,
                restTimerSeconds: input.settings.restTimerSeconds
            )
        } else {
            sessionFatigue = 0.0
        }

        let firstSuggestedSetIndex = input.pendingSets.map(\.setIndex).min()

        return input.pendingSets.map { setSpec in
            let isFirstSet = input.completedSessionSets.isEmpty && setSpec.setIndex == firstSuggestedSetIndex

            let fatigueDiscount = 1.0 - sessionFatigue
            var readinessRawE1RM = input.baseE1RM * fatigueDiscount

            var freshnessApplied = false
            if isFirstSet && input.settings.freshnessEnabled {
                readinessRawE1RM *= (1.0 + input.settings.freshnessPercent)
                freshnessApplied = true
            }

            let minReadiness = input.baseE1RM * Self.readinessMinFactor
            let maxReadiness = input.baseE1RM * Self.readinessMaxFactor
            let effectiveE1RM = min(max(readinessRawE1RM, minReadiness), maxReadiness)

            let bestReps: Int?
            let intensityFactor: Double
            let rawWeight: Double
            let prescribedWeight: Double

            if let range = setSpec.repRange, range.lowerBound < range.upperBound {
                var bestError = Double.infinity
                var winnerReps = setSpec.targetReps
                var winnerIntensity = 0.0
                var winnerRaw = 0.0
                var winnerRounded = 0.0

                for candidateReps in range {
                    let totalReps = max(1, candidateReps + Int(setSpec.targetRIR))
                    let candidateIntensity = max(0.3, input.settings.formula.reverseCalculate(e1RM: 1.0, reps: totalReps))
                    let candidateRaw = effectiveE1RM * candidateIntensity
                    let candidateRounded = roundToIncrement(candidateRaw, increment: input.settings.weightIncrement)
                    let impliedE1RM = input.settings.formula.calculate(weight: candidateRounded, reps: totalReps)
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
                bestReps = nil
                let totalReps = max(1, setSpec.targetReps + Int(setSpec.targetRIR))
                intensityFactor = max(0.3, input.settings.formula.reverseCalculate(e1RM: 1.0, reps: totalReps))
                rawWeight = effectiveE1RM * intensityFactor
                prescribedWeight = roundToIncrement(rawWeight, increment: input.settings.weightIncrement)
            }

            return SuggestionEngineResult(
                setId: setSpec.setId,
                setIndex: setSpec.setIndex,
                setNumber: setSpec.setNumber,
                targetReps: setSpec.targetReps,
                targetRIR: setSpec.targetRIR,
                repRange: setSpec.repRange,
                prescribedWeight: max(0, prescribedWeight),
                rawWeight: rawWeight,
                weightIncrement: input.settings.weightIncrement,
                baseE1RM: input.baseE1RM,
                effectiveE1RM: effectiveE1RM,
                intensityFactor: intensityFactor,
                fatigueDiscount: fatigueDiscount,
                freshnessApplied: freshnessApplied,
                e1RMSource: input.baseSource,
                bestReps: bestReps
            )
        }
    }

    private static func computeSessionFatigue(
        completedSets: [SessionSetContext],
        restTimerSeconds: Double
    ) -> Double {
        var sessionFatigue: Double = 0.0
        let sortedSets = completedSets.filter(\.completed)

        for (index, set) in sortedSets.enumerated() {
            if index > 0 {
                sessionFatigue *= exp(-restTimerSeconds / Self.recoveryConstant)
            }

            let rir = set.rir ?? 2.0
            let baseFatigue: Double = 0.03
            let rirBonus = max(0.0, 2.0 - rir) * 0.02
            let repScale = min(Double(set.reps) / 8.0, 1.5)
            let setFatigue = (baseFatigue + rirBonus) * repScale

            sessionFatigue += setFatigue
        }

        return min(sessionFatigue, Self.maxFatigue)
    }

    private static func roundToIncrement(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }
}

/// Service for prescribing weights based on estimated 1RM, fatigue modeling, and user settings.
///
/// The engine follows a layered model:
/// 1. Base e1RM capacity from recent workout history (top recent workout peaks)
/// 2. Session fatigue accumulation from completed sets
/// 3. Rest-time fatigue decay
/// 4. Readiness bounded to a narrow band around capacity
/// 5. Intensity factor from target reps + RIR
/// 6. Rounding to nearest weight increment
///
/// See: RIR_Fatigue_Aware_1RM_Model.pdf for full algorithm documentation.
protocol LoadPrescriptionServiceProtocol: Sendable {

    /// Estimate base e1RM capacity baseline for an exercise using the same logic as prescription generation.
    ///
    /// Uses recent workout history in the recency window, then PR fallback when needed.
    /// - Parameters:
    ///   - exerciseId: The exercise to estimate for.
    ///   - completedSessionSets: Completed sets from the current session context.
    /// - Returns: The estimated base e1RM and source metadata.
    func estimateBaseE1RM(
        exerciseId: UUID,
        completedSessionSets: [SessionSetContext]
    ) async throws -> BaseE1RMEstimate

    /// Normalize inputs and evaluate smart suggestions for all pending sets.
    ///
    /// This is the preferred integration point for the active workout flow because
    /// it exposes a pure-engine contract (`SuggestionEngineInput`/`SuggestionEvaluation`)
    /// while preserving current app behavior.
    func evaluateSuggestions(
        exerciseId: UUID,
        pendingSets: [SuggestionPendingSetInput],
        completedSessionSets: [SessionSetContext]
    ) async throws -> SuggestionEvaluation?

    /// Prescribe a weight for a single set.
    ///
    /// - Parameter request: The prescription request containing exercise, targets, and session context.
    /// - Returns: The prescription result, or nil if no data is available for this exercise.
    func prescribe(_ request: PrescriptionRequest) async throws -> PrescriptionResult?

    /// Prescribe weights for multiple sets at once (batch operation).
    ///
    /// More efficient than calling prescribe() repeatedly because it fetches
    /// exercise data and e1RM only once.
    ///
    /// - Parameters:
    ///   - exerciseId: The exercise to prescribe for.
    ///   - sets: Array of (targetReps, targetRIR, setIndex, repRange) tuples.
    ///     When `repRange` is provided, the engine evaluates all reps in the range
    ///     and picks the (weight, reps) pair closest to the target e1RM after rounding.
    ///   - completedSessionSets: All completed sets for this exercise in the current session.
    /// - Returns: Array of prescription results (nil entries where prescription not possible).
    func prescribeBatch(
        exerciseId: UUID,
        sets: [(targetReps: Int, targetRIR: Double, setIndex: Int, repRange: ClosedRange<Int>?)],
        completedSessionSets: [SessionSetContext]
    ) async throws -> [PrescriptionResult?]
}
