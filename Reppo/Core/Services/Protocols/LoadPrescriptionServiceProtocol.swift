// LoadPrescriptionServiceProtocol.swift
// Contract for the fatigue-aware Smart Suggestions engine.
// Based on: RIR_Fatigue_Aware_1RM_Model.pdf
// Feature: Smart Suggestions (magic wand)

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
    /// The type of set (working, amrap, dropset, etc.) for fatigue multiplier lookup.
    let setType: SetType
    /// Actual rest duration captured from the rest timer (nil = use configured rest).
    let restDurationSeconds: Int?
}

/// Where an individual target component came from.
enum SuggestionTargetComponentSource: String, Sendable, Equatable {
    case explicitSet
    case template
    case smartDefault

    var label: String {
        switch self {
        case .explicitSet:
            return "set entry"
        case .template:
            return "template target"
        case .smartDefault:
            return "Smart Suggestions default"
        }
    }
}

/// Resolved reps/RIR target for a pending suggestion.
struct SuggestionTarget: Sendable {
    let reps: Int
    let rir: Double
    let repRange: ClosedRange<Int>?
    let repsSource: SuggestionTargetComponentSource
    let rirSource: SuggestionTargetComponentSource

    var repsSourceLabel: String { repsSource.label }
    var rirSourceLabel: String { rirSource.label }

    var sourceLabel: String {
        var orderedSources: [SuggestionTargetComponentSource] = []
        for source in [repsSource, rirSource] where !orderedSources.contains(source) {
            orderedSources.append(source)
        }
        return orderedSources.map(\.label).joined(separator: " + ")
    }

    var defaultUsageLabel: String? {
        switch (repsSource == .smartDefault, rirSource == .smartDefault) {
        case (true, true):
            return "using default target"
        case (true, false):
            return "using default reps"
        case (false, true):
            return "using default RIR"
        case (false, false):
            return nil
        }
    }
}

/// Typed reason for why a smart suggestion is unavailable.
enum SuggestionUnavailableReason: String, Sendable, Equatable {
    case missingExercise
    case unsupportedExercise
    case featureDisabled
    case noPendingSets
    case missingTarget
    case noStrengthData
    case calculationFailed

    var title: String {
        switch self {
        case .missingExercise:
            return "No exercise selected"
        case .unsupportedExercise:
            return "Suggestions unavailable"
        case .featureDisabled:
            return "Smart Suggestions disabled"
        case .noPendingSets:
            return "No pending sets"
        case .missingTarget:
            return "Missing target"
        case .noStrengthData:
            return "Not enough history"
        case .calculationFailed:
            return "Suggestion unavailable"
        }
    }

    var message: String {
        switch self {
        case .missingExercise:
            return "Select an exercise to load Smart Suggestions."
        case .unsupportedExercise:
            return "Smart Suggestions currently support weight-based exercises only."
        case .featureDisabled:
            return "Enable Smart Suggestions in Settings to show recommendations here."
        case .noPendingSets:
            return "All working sets are complete or there are no remaining sets to suggest."
        case .missingTarget:
            return "This set needs reps or RIR guidance from the set entry, template, or Smart Suggestions defaults."
        case .noStrengthData:
            return "Complete more sets for this exercise before Smart Suggestions can estimate a baseline."
        case .calculationFailed:
            return "The app could not build a suggestion from the current input state."
        }
    }
}

/// Result of resolving whether a pending set can receive a suggestion.
enum SuggestionEligibility: Sendable {
    case eligible(target: SuggestionTarget)
    case ineligible(reason: SuggestionUnavailableReason)
}

/// Intermediate pending-set resolution used before engine evaluation.
struct SuggestionSetResolution: Sendable {
    let setId: UUID
    let setIndex: Int
    let setNumber: Int
    let eligibility: SuggestionEligibility
    let setType: SetType
}

/// Neutral calibration seam for future per-user/per-exercise personalization.
struct SuggestionCalibrationAdjustment: Sendable {
    let readinessMultiplier: Double
    let fatigueDiscountOffset: Double
    let explanation: String

    static let neutral = SuggestionCalibrationAdjustment(
        readinessMultiplier: 1.0,
        fatigueDiscountOffset: 0.0,
        explanation: "No calibration adjustment applied"
    )
}

/// Provider for future exercise-specific suggestion calibration.
protocol SuggestionCalibrationProviderProtocol: Sendable {
    func calibrationAdjustment(for exerciseId: UUID) async -> SuggestionCalibrationAdjustment
}

/// Default no-op calibration provider.
struct NeutralSuggestionCalibrationProvider: SuggestionCalibrationProviderProtocol {
    func calibrationAdjustment(for exerciseId: UUID) async -> SuggestionCalibrationAdjustment {
        let _ = exerciseId
        return .neutral
    }
}

/// A pending set that needs a smart suggestion.
struct SuggestionPendingSetInput: Sendable {
    /// The underlying WorkoutSet identifier for row-level mapping.
    let setId: UUID
    /// The set's position in the exercise (0-indexed, including warmups in the source array).
    let setIndex: Int
    /// The display set number among non-warmup sets (1-indexed).
    let setNumber: Int
    /// The resolved target used for this suggestion.
    let target: SuggestionTarget
    /// The set type for fatigue multiplier lookup during forward projection.
    let setType: SetType

    var targetReps: Int { target.reps }
    var targetRIR: Double { target.rir }
    var repRange: ClosedRange<Int>? { target.repRange }
    var targetSourceLabel: String { target.sourceLabel }
}

/// Snapshot of resolved settings and exercise overrides used by the engine.
struct SuggestionSettingsSnapshot: Sendable {
    let formula: E1RMFormula
    let restTimerSeconds: Double
    let weightIncrement: Double
    let fatigueEnabled: Bool
    let freshnessEnabled: Bool
    let freshnessPercent: Double
    /// Per-exercise or global base fatigue rate (default 0.04 for v2).
    let baseFatigueRate: Double
    /// Per-exercise or global recovery time constant in seconds (default 180 for v2).
    let recoveryConstant: Double
}

/// Normalized engine input after app-model resolution.
struct SuggestionEngineInput: Sendable {
    let baseE1RM: Double
    let baseSource: E1RMSource
    let completedSessionSets: [SessionSetContext]
    let pendingSets: [SuggestionPendingSetInput]
    let settings: SuggestionSettingsSnapshot
    let calibrationAdjustment: SuggestionCalibrationAdjustment
}

/// Pure decision output for one pending set.
struct SuggestionDecision: Sendable {
    let setId: UUID
    let setIndex: Int
    let setNumber: Int
    let target: SuggestionTarget
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
    let calibrationAdjustment: SuggestionCalibrationAdjustment
    /// Projected cumulative session fatigue at the point this set would be performed.
    let projectedSessionFatigue: Double

    var targetReps: Int { target.reps }
    var targetRIR: Double { target.rir }
    var repRange: ClosedRange<Int>? { target.repRange }
    var targetSourceLabel: String { target.sourceLabel }
    var targetRepsSourceLabel: String { target.repsSourceLabel }
    var targetRIRSourceLabel: String { target.rirSourceLabel }
    var targetDefaultUsageLabel: String? { target.defaultUsageLabel }
}

/// Expected-vs-actual set outcome payload for future calibration work.
struct SuggestionOutcome: Sendable {
    let setId: UUID
    let expectedWeight: Double
    let expectedReps: Int
    let expectedRIR: Double
    let actualWeight: Double?
    let actualReps: Int?
    let actualRIR: Double?
}

/// Bundles normalized input with the engine's outputs for explanation/UI layers.
struct SuggestionEvaluation: Sendable {
    let input: SuggestionEngineInput?
    let decisions: [SuggestionDecision]
    let unavailableReason: SuggestionUnavailableReason?

    static func unavailable(_ reason: SuggestionUnavailableReason) -> SuggestionEvaluation {
        SuggestionEvaluation(
            input: nil,
            decisions: [],
            unavailableReason: reason
        )
    }
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

    var label: String {
        switch self {
        case .recentPerformance:
            return "recent top workouts"
        case .historicalPR:
            return "PR history"
        case .noData:
            return "no data"
        }
    }
}

/// Pure smart-suggestion calculation engine.
///
/// The engine has no repository or view-model dependencies. It operates only on
/// normalized inputs so the current behavior can be audited and evolved separately
/// from app-model gathering and UI explanation.
enum SuggestionEngine {
    // MARK: - v2 constants

    private static let defaultBaseFatigueRate: Double = 0.04
    private static let defaultRecoveryConstant: Double = 180.0
    private static let maxFatigue: Double = 0.25
    private static let readinessMinFactor: Double = 0.88
    private static let readinessMaxFactor: Double = 1.05
    private static let missingRIRDefault: Double = 1.0

    // MARK: - Set-type fatigue multipliers

    static func setTypeMultiplier(_ type: SetType) -> Double {
        switch type {
        case .warmup:    return 0.0
        case .working:   return 1.0
        case .tempo:     return 1.1
        case .backoff:   return 0.7
        case .cluster:   return 0.8
        case .restpause: return 1.3
        case .myo:       return 1.3
        case .dropset:   return 1.4
        case .amrap:     return 1.5
        case .failure:   return 1.5
        case .partial:   return 0.5
        case .isometric: return 0.9
        case .eccentric: return 1.2
        }
    }

    // MARK: - Per-set fatigue calculation

    /// Compute fatigue contribution for a single set.
    /// Formula: baseFatigueRate * typeMultiplier * effortScale * repScale
    static func computeSetFatigue(
        reps: Int,
        rir: Double?,
        setType: SetType,
        baseFatigueRate: Double
    ) -> Double {
        let effectiveRIR = rir ?? Self.missingRIRDefault
        let effortScale = 1.0 + max(0.0, 3.0 - effectiveRIR) * 0.15
        let repScale = max(0.6, min(Double(reps) / 8.0, 1.5))
        let typeMultiplier = setTypeMultiplier(setType)
        return baseFatigueRate * typeMultiplier * effortScale * repScale
    }

    // MARK: - Session fatigue from completed sets

    static func computeSessionFatigue(
        completedSets: [SessionSetContext],
        configuredRestSeconds: Double,
        recoveryConstant: Double,
        baseFatigueRate: Double
    ) -> Double {
        var sessionFatigue: Double = 0.0
        let sortedSets = completedSets.filter(\.completed)

        for (index, set) in sortedSets.enumerated() {
            if index > 0 {
                // Use actual captured rest duration if available, otherwise configured rest.
                let restSeconds = Double(set.restDurationSeconds ?? Int(configuredRestSeconds))
                sessionFatigue *= exp(-restSeconds / recoveryConstant)
            }

            let setFatigue = computeSetFatigue(
                reps: set.reps,
                rir: set.rir,
                setType: set.setType,
                baseFatigueRate: baseFatigueRate
            )
            sessionFatigue += setFatigue
        }

        return min(sessionFatigue, Self.maxFatigue)
    }

    // MARK: - Evaluate with forward projection

    static func evaluate(_ input: SuggestionEngineInput) -> [SuggestionDecision] {
        let baseFatigueRate = input.settings.baseFatigueRate
        let recoveryConstant = input.settings.recoveryConstant
        let configuredRestSeconds = input.settings.restTimerSeconds

        // Accumulate fatigue from completed sets.
        var runningFatigue: Double = 0.0
        if input.settings.fatigueEnabled {
            runningFatigue = computeSessionFatigue(
                completedSets: input.completedSessionSets,
                configuredRestSeconds: configuredRestSeconds,
                recoveryConstant: recoveryConstant,
                baseFatigueRate: baseFatigueRate
            )
        }

        let firstSuggestedSetIndex = input.pendingSets.map(\.setIndex).min()
        var decisions: [SuggestionDecision] = []

        for (pendingIndex, setSpec) in input.pendingSets.enumerated() {
            let isFirstSet = input.completedSessionSets.isEmpty && setSpec.setIndex == firstSuggestedSetIndex

            // Forward projection: decay fatigue between pending sets using configured rest.
            if input.settings.fatigueEnabled && pendingIndex > 0 {
                runningFatigue *= exp(-configuredRestSeconds / recoveryConstant)

                // Project the previous pending set's fatigue contribution.
                let prev = input.pendingSets[pendingIndex - 1]
                let prevFatigue = computeSetFatigue(
                    reps: prev.targetReps,
                    rir: prev.targetRIR,
                    setType: prev.setType,
                    baseFatigueRate: baseFatigueRate
                )
                runningFatigue = min(runningFatigue + prevFatigue, Self.maxFatigue)
            }

            let projectedFatigue = runningFatigue

            let fatigueDiscount = min(
                1.0,
                max(0.0, (1.0 - projectedFatigue) + input.calibrationAdjustment.fatigueDiscountOffset)
            )
            var readinessRawE1RM = input.baseE1RM * input.calibrationAdjustment.readinessMultiplier * fatigueDiscount

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

            decisions.append(SuggestionDecision(
                setId: setSpec.setId,
                setIndex: setSpec.setIndex,
                setNumber: setSpec.setNumber,
                target: setSpec.target,
                prescribedWeight: max(0, prescribedWeight),
                rawWeight: rawWeight,
                weightIncrement: input.settings.weightIncrement,
                baseE1RM: input.baseE1RM,
                effectiveE1RM: effectiveE1RM,
                intensityFactor: intensityFactor,
                fatigueDiscount: fatigueDiscount,
                freshnessApplied: freshnessApplied,
                e1RMSource: input.baseSource,
                bestReps: bestReps,
                calibrationAdjustment: input.calibrationAdjustment,
                projectedSessionFatigue: projectedFatigue
            ))
        }

        return decisions
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
    ) async throws -> SuggestionEvaluation

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
