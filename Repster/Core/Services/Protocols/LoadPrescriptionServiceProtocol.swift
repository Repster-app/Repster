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
    /// The RIR this set was *prescribed* at, resolved the same way a pending set's target is
    /// (explicit entry → template → profile default).
    ///
    /// Only consulted when ``rir`` is nil. A lifter who ticks a set complete without tapping the
    /// chip is far better modelled as having landed near the target they were given than as a
    /// global constant — and the constant this replaces (`missingRIRDefault = 1.0`) modelled them
    /// as *harder* than an explicit RIR 2, so leaving the chip blank cost them a plate.
    ///
    /// Deliberately not sourced from `WorkoutSet.targetRIR`: that field is written only by
    /// `TemplateService`, so it is nil for every ad-hoc set and the fallback would silently be a
    /// no-op for anyone not running templates. See SUGGESTION_ENGINE_IMPLEMENTATION_PLAN.md G1.
    let targetRIR: Double?

    init(
        weight: Double,
        reps: Int,
        rir: Double?,
        completedAt: Date?,
        completed: Bool,
        setType: SetType,
        restDurationSeconds: Int?,
        targetRIR: Double? = nil
    ) {
        self.weight = weight
        self.reps = reps
        self.rir = rir
        self.completedAt = completedAt
        self.completed = completed
        self.setType = setType
        self.restDurationSeconds = restDurationSeconds
        self.targetRIR = targetRIR
    }
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
    let displayReps: Int
    let displayRepRange: ClosedRange<Int>?
    let repTargetMode: UnilateralRepTargetMode?
    let repsSource: SuggestionTargetComponentSource
    let rirSource: SuggestionTargetComponentSource

    init(
        reps: Int,
        rir: Double,
        repRange: ClosedRange<Int>?,
        repsSource: SuggestionTargetComponentSource,
        rirSource: SuggestionTargetComponentSource,
        displayReps: Int? = nil,
        displayRepRange: ClosedRange<Int>? = nil,
        repTargetMode: UnilateralRepTargetMode? = nil
    ) {
        self.reps = reps
        self.rir = rir
        self.repRange = repRange
        self.displayReps = displayReps ?? reps
        self.displayRepRange = displayRepRange ?? repRange
        self.repTargetMode = repTargetMode
        self.repsSource = repsSource
        self.rirSource = rirSource
    }

    var repsSourceLabel: String { repsSource.label }
    var rirSourceLabel: String { rirSource.label }

    var displayTargetLabel: String {
        if let displayRepRange {
            switch repTargetMode {
            case .totalAcrossSides:
                return "\(displayRepRange.lowerBound)-\(displayRepRange.upperBound) total reps"
            case .perSide:
                return "\(displayRepRange.lowerBound)-\(displayRepRange.upperBound) reps each side"
            case nil:
                return "\(displayRepRange.lowerBound)-\(displayRepRange.upperBound) reps"
            }
        }

        return displayLabel(forReps: displayReps)
    }

    /// Names a single rep count in the same wording `displayTargetLabel` uses.
    /// When a set carries a rep range the engine prices one count inside it,
    /// and the prescribed weight only means anything against that count — so
    /// the card names it rather than echoing the range back.
    func displayLabel(forReps reps: Int) -> String {
        switch repTargetMode {
        case .totalAcrossSides:
            return "\(reps) total reps"
        case .perSide:
            return "\(reps) reps each side"
        case nil:
            return "\(reps) reps"
        }
    }

    var normalizedTargetLabel: String? {
        guard repTargetMode == .totalAcrossSides else { return nil }
        if let repRange {
            if repRange.lowerBound == repRange.upperBound {
                return "normalized to \(repRange.lowerBound) reps each side"
            }
            return "normalized to \(repRange.lowerBound)-\(repRange.upperBound) reps each side"
        }
        return "normalized to \(reps) reps each side"
    }

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
    case bodyweightHistoryOnly
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
        case .bodyweightHistoryOnly:
            return "Logged at bodyweight"
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
        case .bodyweightHistoryOnly:
            return "Your recent sets for this exercise were logged at bodyweight, so there's no load to estimate from. Older weighted sets are too far back to be a fair guide."
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

/// How completed-set performance should update the session capability baseline.
enum SessionCapabilityPolicy: Sendable, Equatable {
    case blended(observedWeight: Double, priorWeight: Double)
    case observed

    static let defaultBlended: SessionCapabilityPolicy = .blended(observedWeight: 0.7, priorWeight: 0.3)
    static let defaultObserved: SessionCapabilityPolicy = .observed

    var label: String {
        switch self {
        case .blended:
            return "session blend"
        case .observed:
            return "observed"
        }
    }

    var cacheSignature: String {
        switch self {
        case let .blended(observedWeight, priorWeight):
            return "blend-\(String(format: "%.3f", observedWeight))-\(String(format: "%.3f", priorWeight))"
        case .observed:
            return "observed"
        }
    }

    func blend(observedCapability: Double, priorCapability: Double) -> Double {
        switch self {
        case let .blended(observedWeight, priorWeight):
            let totalWeight = observedWeight + priorWeight
            guard totalWeight > 0 else { return observedCapability }
            return ((observedCapability * observedWeight) + (priorCapability * priorWeight)) / totalWeight
        case .observed:
            return observedCapability
        }
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
    var displayTargetReps: Int { target.displayReps }
    var targetRIR: Double { target.rir }
    var repRange: ClosedRange<Int>? { target.repRange }
    var displayRepRange: ClosedRange<Int>? { target.displayRepRange }
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
    /// Per-exercise or global base fatigue rate (default 0.03 fallback).
    let baseFatigueRate: Double
    /// Per-exercise or global recovery time constant in seconds (default 180 for v2).
    let recoveryConstant: Double
    /// Policy for incorporating completed-set capability into the current workout baseline.
    let sessionCapabilityPolicy: SessionCapabilityPolicy
}

/// Normalized engine input after app-model resolution.
struct SuggestionEngineInput: Sendable {
    let baseE1RM: Double
    let baseSource: E1RMSource
    /// Date of the workout the base e1RM is anchored on (nil when not derived
    /// from a specific workout). Threaded through to `SuggestionDecision` so the
    /// UI can surface anchor dates without re-querying.
    let baseSourceWorkoutDate: Date?
    /// The actual top set behind `baseE1RM`. Threaded through to
    /// `SuggestionDecision` so the UI can render the "last top" reference.
    let baseSourceTopSet: HistoricalSetSnapshot?
    let completedSessionSets: [SessionSetContext]
    let pendingSets: [SuggestionPendingSetInput]
    let settings: SuggestionSettingsSnapshot
    let calibrationAdjustment: SuggestionCalibrationAdjustment

    init(
        baseE1RM: Double,
        baseSource: E1RMSource,
        baseSourceWorkoutDate: Date? = nil,
        baseSourceTopSet: HistoricalSetSnapshot? = nil,
        completedSessionSets: [SessionSetContext],
        pendingSets: [SuggestionPendingSetInput],
        settings: SuggestionSettingsSnapshot,
        calibrationAdjustment: SuggestionCalibrationAdjustment
    ) {
        self.baseE1RM = baseE1RM
        self.baseSource = baseSource
        self.baseSourceWorkoutDate = baseSourceWorkoutDate
        self.baseSourceTopSet = baseSourceTopSet
        self.completedSessionSets = completedSessionSets
        self.pendingSets = pendingSets
        self.settings = settings
        self.calibrationAdjustment = calibrationAdjustment
    }
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
    let historicalBaseE1RM: Double
    let sessionCapabilityE1RM: Double
    let effectiveE1RM: Double
    let intensityFactor: Double
    let fatigueDiscount: Double
    let freshnessApplied: Bool
    let e1RMSource: E1RMSource
    /// Date of the workout the base e1RM was sourced from, when available.
    /// Forwarded from `SuggestionEngineInput.baseSourceWorkoutDate`.
    let e1RMSourceWorkoutDate: Date?
    /// The actual top set behind the baseline e1RM, when available.
    /// Forwarded from `SuggestionEngineInput.baseSourceTopSet`.
    let e1RMSourceTopSet: HistoricalSetSnapshot?
    let sessionCapabilitySourceLabel: String
    let bestReps: Int?
    let selectionPolicy: SuggestionSelectionPolicy
    let selectionReferenceE1RM: Double?
    let calibrationAdjustment: SuggestionCalibrationAdjustment
    /// Projected cumulative session fatigue at the point this set would be performed.
    let projectedSessionFatigue: Double
    /// Set when the suggestion floor overrode the model's answer, carrying the completed set that
    /// proved it. Surfaced in the explanation — a suggestion the floor pushed *up* must never still
    /// claim it eased off to manage fatigue.
    let appliedFloor: SuggestionEngine.SuggestionFloor?

    var targetReps: Int { target.reps }
    var displayTargetReps: Int { target.displayReps }
    var targetRIR: Double { target.rir }
    var repRange: ClosedRange<Int>? { target.repRange }
    var displayRepRange: ClosedRange<Int>? { target.displayRepRange }
    var targetSourceLabel: String { target.sourceLabel }
    var targetRepsSourceLabel: String { target.repsSourceLabel }
    var targetRIRSourceLabel: String { target.rirSourceLabel }
    var targetDefaultUsageLabel: String? { target.defaultUsageLabel }
    var targetDisplayLabel: String { target.displayTargetLabel }
    var normalizedTargetLabel: String? { target.normalizedTargetLabel }
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
    /// Date of the workout the base e1RM was sourced from, when available.
    /// Nil for `.noData` or when the source isn't tied to a specific workout.
    let e1RMSourceWorkoutDate: Date?
    /// When rep range optimization was used, the optimal rep count chosen.
    /// Nil when no range was provided (single target reps).
    let bestReps: Int?

    init(
        prescribedWeight: Double,
        rawWeight: Double,
        weightIncrement: Double,
        baseE1RM: Double,
        effectiveE1RM: Double,
        intensityFactor: Double,
        fatigueDiscount: Double,
        freshnessApplied: Bool,
        e1RMSource: E1RMSource,
        e1RMSourceWorkoutDate: Date? = nil,
        bestReps: Int?
    ) {
        self.prescribedWeight = prescribedWeight
        self.rawWeight = rawWeight
        self.weightIncrement = weightIncrement
        self.baseE1RM = baseE1RM
        self.effectiveE1RM = effectiveE1RM
        self.intensityFactor = intensityFactor
        self.fatigueDiscount = fatigueDiscount
        self.freshnessApplied = freshnessApplied
        self.e1RMSource = e1RMSource
        self.e1RMSourceWorkoutDate = e1RMSourceWorkoutDate
        self.bestReps = bestReps
    }
}

/// Snapshot of a logged set from history, used as a UI-facing reference
/// (e.g. "last top set: 52 kg × 8 · RIR 1"). The snapshot is the actual
/// set behind the baseline e1RM — see `LoadPrescriptionService.peakAcrossRecentWorkouts`.
struct HistoricalSetSnapshot: Sendable, Equatable {
    let weight: Double
    let reps: Int
    let rir: Double?
    let date: Date
}

/// Shared base e1RM estimate result for consumers that need a consistent source/value pair.
struct BaseE1RMEstimate: Sendable {
    let value: Double?
    let source: E1RMSource
    /// Date of the workout the estimate is anchored on, when sourced from logged performance.
    /// Nil for `.noData`. Used by the UI to render "based on workout from X weeks ago" copy
    /// and to detect stale data even within the `.recentPerformance` window if desired.
    let sourceWorkoutDate: Date?
    /// The actual top set (highest implied e1RM) behind this baseline.
    /// Nil for `.noData` or when no eligible source set could be identified.
    /// Used by the UI to render "last top: 52 kg × 8 · RIR 1" footer chip.
    let topSet: HistoricalSetSnapshot?
    /// True when a usable older baseline existed but was deliberately withheld because the
    /// exercise has been logged more recently at bodyweight. Lets the caller distinguish
    /// "never logged" from "logged recently, but not at a load we can build an estimate from".
    let suppressedForBodyweightHistory: Bool

    init(
        value: Double?,
        source: E1RMSource,
        sourceWorkoutDate: Date? = nil,
        topSet: HistoricalSetSnapshot? = nil,
        suppressedForBodyweightHistory: Bool = false
    ) {
        self.value = value
        self.source = source
        self.sourceWorkoutDate = sourceWorkoutDate
        self.topSet = topSet
        self.suppressedForBodyweightHistory = suppressedForBodyweightHistory
    }
}

/// How the base e1RM was determined.
enum E1RMSource: Sendable {
    /// From recent workout history inside the configured recency window
    /// (top-performance baseline across the last few workouts).
    case recentPerformance
    /// From the most recent logged workout, but that workout falls outside the
    /// configured recency window. Should be surfaced to the user as a lower-confidence
    /// suggestion (the data is real, just older than they asked for).
    case staleRecentPerformance
    /// No data available — prescription not possible.
    case noData

    var label: String {
        switch self {
        case .recentPerformance:
            return "recent top workouts"
        case .staleRecentPerformance:
            return "older workout (outside recency window)"
        case .noData:
            return "no data"
        }
    }

    /// Whether this source represents data drawn from outside the configured
    /// recency window. Convenience for UI gating on a single boolean.
    var isOutsideRecencyWindow: Bool {
        switch self {
        case .recentPerformance, .noData:
            return false
        case .staleRecentPerformance:
            return true
        }
    }
}

enum SuggestionSelectionPolicy: Sendable, Equatable {
    case closestMatch
    case firstSetProgressionAboveRecentPeak
    /// The model's answer was below a weight already completed this session with reps to spare,
    /// so the floor replaced it. Never silent: a clamped suggestion that still explained itself as
    /// "easing off to manage session fatigue" would be saying the opposite of what it just did.
    case floorHeldAboveCompletedSet

    var label: String {
        switch self {
        case .closestMatch:
            return "closest match to effective e1RM"
        case .firstSetProgressionAboveRecentPeak:
            return "biased above recent top workout"
        case .floorHeldAboveCompletedSet:
            return "held above a completed set with reps to spare"
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

    private static let defaultBaseFatigueRate: Double = 0.03
    private static let defaultRecoveryConstant: Double = 180.0
    private static let maxFatigue: Double = 0.25
    private static let missingRIRDefault: Double = 1.0
    private static let e1RMEpsilon: Double = 0.0001

    /// The most one completed set may pull the session capability estimate *down*, as a fraction
    /// of the running estimate.
    ///
    /// `.observed` replaces the estimate outright rather than blending, so a single light set
    /// becomes the capability figure for every remaining set of the exercise. A 100 kg x 8 @ RIR 2
    /// top set followed by an untagged 60 kg x 10 back-off had the engine concluding capacity fell
    /// ~38% mid-exercise. Type filtering (`isCapacityPointEstimate`) catches the *labelled* cases;
    /// this catches the far commoner unlabelled ones.
    ///
    /// Asymmetric on purpose: upward moves replace freely, because a set that beats the estimate is
    /// direct evidence the estimate was low. Only the downward direction is capped.
    ///
    /// 0.20 mirrors the learning path's existing weight-deviation guard
    /// (`FatigueLearningService.maxWeightDeviationFraction`), which already treats a >20% departure
    /// from the prescription as "not evidence about the model". Failure mode is benign: too tight
    /// and capability tracks a genuine decline more slowly, which costs a lighter suggestion, never
    /// a failed rep.
    private static let maxDownwardCapabilityMove: Double = 0.20

    /// Reps of surplus a completed set must show before it establishes a floor.
    ///
    /// The surplus has to beat the fatigue the model is entitled to claim. At an 8-rep target three
    /// reps of reserve is ~8% of load, while accumulated fatigue between adjacent sets at normal
    /// rest is 2-5%; one rep of reserve is ~2.6% and does not clear that bar.
    ///
    /// Three also lands on a useful symmetry: where target reps match what was performed, the
    /// surplus *is* the completed set's RIR — so the floor activates on precisely the sets
    /// `normalizedObservedCapability` discards at `actualRIR >= 3`. The two are complementary
    /// rather than redundant, which is why the RIR gate stays.
    private static let floorMinimumRepSurplus: Int = 3

    private struct CompletedSessionState: Sendable {
        let sessionCapabilityE1RM: Double
        let runningFatigue: Double
        let usedSessionCapabilityBlend: Bool
    }

    private struct RepRangeCandidate: Sendable {
        let reps: Int
        let intensityFactor: Double
        let rawWeight: Double
        let roundedWeight: Double
        let impliedE1RM: Double
        let errorToEffectiveE1RM: Double
    }

    private struct ReadinessState: Sendable {
        let effectiveE1RM: Double
        let fatigueDiscount: Double
        let freshnessApplied: Bool
        let normalizationMultiplier: Double
    }

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
        let sortedSets = orderedCompletedSets(completedSets)

        for (index, set) in sortedSets.enumerated() {
            if index > 0 {
                // Rest is stored on the previous completed set and applies to the transition into this set.
                let previousSet = sortedSets[index - 1]
                let restSeconds = Double(previousSet.restDurationSeconds ?? Int(configuredRestSeconds))
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
        let completedState = processCompletedSessionState(input)
        let sessionCapabilityE1RM = completedState.sessionCapabilityE1RM
        let sessionCapabilitySourceLabel = completedState.usedSessionCapabilityBlend
            ? input.settings.sessionCapabilityPolicy.label
            : input.baseSource.label

        // Accumulate fatigue from completed sets.
        var runningFatigue: Double = 0.0
        if input.settings.fatigueEnabled {
            runningFatigue = completedState.runningFatigue
        }

        let firstSuggestedSetIndex = input.pendingSets.map(\.setIndex).min()
        let completedWorkSetCount = orderedCompletedSets(input.completedSessionSets)
            .filter { isCapabilityTrackingSetType($0.setType) }
            .count
        var decisions: [SuggestionDecision] = []

        for (pendingIndex, setSpec) in input.pendingSets.enumerated() {
            let isFirstSet = completedWorkSetCount == 0 && setSpec.setIndex == firstSuggestedSetIndex

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
            let readinessState = readinessState(
                capabilityE1RM: sessionCapabilityE1RM,
                projectedFatigue: projectedFatigue,
                isFirstSet: isFirstSet,
                settings: input.settings,
                calibrationAdjustment: input.calibrationAdjustment
            )
            let effectiveE1RM = readinessState.effectiveE1RM

            let bestReps: Int?
            let intensityFactor: Double
            let rawWeight: Double
            var prescribedWeight: Double
            var selectionPolicy: SuggestionSelectionPolicy
            var selectionReferenceE1RM: Double?

            if let range = setSpec.repRange, range.lowerBound < range.upperBound {
                let candidates = repRangeCandidates(
                    range: range,
                    targetRIR: setSpec.targetRIR,
                    effectiveE1RM: effectiveE1RM,
                    settings: input.settings
                )
                let winner = chooseRepRangeCandidate(
                    candidates: candidates,
                    targetReps: setSpec.targetReps,
                    recentCapacityBaselineE1RM: input.baseE1RM,
                    applyFirstSetProgressionBias: isFirstSet && input.baseSource == .recentPerformance
                )

                bestReps = winner.reps
                intensityFactor = winner.intensityFactor
                rawWeight = winner.rawWeight
                prescribedWeight = winner.roundedWeight
                selectionPolicy = winner.selectionPolicy
                selectionReferenceE1RM = winner.selectionReferenceE1RM
            } else {
                bestReps = nil
                let totalReps = max(1, setSpec.targetReps + Int(setSpec.targetRIR))
                intensityFactor = max(0.3, input.settings.formula.reverseCalculate(e1RM: 1.0, reps: totalReps))
                rawWeight = effectiveE1RM * intensityFactor
                prescribedWeight = roundToIncrement(rawWeight, increment: input.settings.weightIncrement)
                selectionPolicy = .closestMatch
                selectionReferenceE1RM = nil
            }

            // D9: applies to every pending set, not only the next one. The argument holds
            // identically further down the projection — reserve was demonstrated, and the lower
            // numbers further out are the model's claim, not an observation. This does flatten the
            // projected decline, which is intended.
            var appliedFloor: SuggestionFloor?
            if let floor = suggestionFloor(
                target: setSpec.target,
                completedSets: input.completedSessionSets,
                increment: input.settings.weightIncrement
            ), floor.weight > prescribedWeight {
                // D8: no cap on how far the floor may raise the answer. A large gap between the
                // floor and the model *is* the signal that the model is wrong, and the floor is the
                // better-evidenced of the two.
                prescribedWeight = floor.weight
                selectionPolicy = .floorHeldAboveCompletedSet
                selectionReferenceE1RM = nil
                appliedFloor = floor
            }

            decisions.append(SuggestionDecision(
                setId: setSpec.setId,
                setIndex: setSpec.setIndex,
                setNumber: setSpec.setNumber,
                target: setSpec.target,
                prescribedWeight: max(0, prescribedWeight),
                rawWeight: rawWeight,
                weightIncrement: input.settings.weightIncrement,
                baseE1RM: sessionCapabilityE1RM,
                historicalBaseE1RM: input.baseE1RM,
                sessionCapabilityE1RM: sessionCapabilityE1RM,
                effectiveE1RM: effectiveE1RM,
                intensityFactor: intensityFactor,
                fatigueDiscount: readinessState.fatigueDiscount,
                freshnessApplied: readinessState.freshnessApplied,
                e1RMSource: input.baseSource,
                e1RMSourceWorkoutDate: input.baseSourceWorkoutDate,
                e1RMSourceTopSet: input.baseSourceTopSet,
                sessionCapabilitySourceLabel: sessionCapabilitySourceLabel,
                bestReps: bestReps,
                selectionPolicy: selectionPolicy,
                selectionReferenceE1RM: selectionReferenceE1RM,
                calibrationAdjustment: input.calibrationAdjustment,
                projectedSessionFatigue: projectedFatigue,
                appliedFloor: appliedFloor
            ))
        }

        return decisions
    }

    private static func repRangeCandidates(
        range: ClosedRange<Int>,
        targetRIR: Double,
        effectiveE1RM: Double,
        settings: SuggestionSettingsSnapshot
    ) -> [RepRangeCandidate] {
        range.map { candidateReps in
            let totalReps = max(1, candidateReps + Int(targetRIR))
            let candidateIntensity = max(
                0.3,
                settings.formula.reverseCalculate(e1RM: 1.0, reps: totalReps)
            )
            let candidateRaw = effectiveE1RM * candidateIntensity
            let candidateRounded = roundToIncrement(candidateRaw, increment: settings.weightIncrement)
            let impliedE1RM = settings.formula.calculate(weight: candidateRounded, reps: totalReps)
            let error = abs(impliedE1RM - effectiveE1RM)

            return RepRangeCandidate(
                reps: candidateReps,
                intensityFactor: candidateIntensity,
                rawWeight: candidateRaw,
                roundedWeight: candidateRounded,
                impliedE1RM: impliedE1RM,
                errorToEffectiveE1RM: error
            )
        }
    }

    private static func chooseRepRangeCandidate(
        candidates: [RepRangeCandidate],
        targetReps: Int,
        recentCapacityBaselineE1RM: Double,
        applyFirstSetProgressionBias: Bool
    ) -> (
        reps: Int,
        intensityFactor: Double,
        rawWeight: Double,
        roundedWeight: Double,
        selectionPolicy: SuggestionSelectionPolicy,
        selectionReferenceE1RM: Double?
    ) {
        guard let normalWinner = bestClosestMatchCandidate(candidates) else {
            return (
                reps: targetReps,
                intensityFactor: 0.0,
                rawWeight: 0.0,
                roundedWeight: 0.0,
                selectionPolicy: .closestMatch,
                selectionReferenceE1RM: nil
            )
        }

        if applyFirstSetProgressionBias,
           normalWinner.impliedE1RM <= recentCapacityBaselineE1RM + Self.e1RMEpsilon,
           let progressedWinner = bestProgressedCandidate(
               candidates,
               targetReps: targetReps,
               recentCapacityBaselineE1RM: recentCapacityBaselineE1RM
           ) {
            return (
                reps: progressedWinner.reps,
                intensityFactor: progressedWinner.intensityFactor,
                rawWeight: progressedWinner.rawWeight,
                roundedWeight: progressedWinner.roundedWeight,
                selectionPolicy: .firstSetProgressionAboveRecentPeak,
                selectionReferenceE1RM: recentCapacityBaselineE1RM
            )
        }

        return (
            reps: normalWinner.reps,
            intensityFactor: normalWinner.intensityFactor,
            rawWeight: normalWinner.rawWeight,
            roundedWeight: normalWinner.roundedWeight,
            selectionPolicy: .closestMatch,
            selectionReferenceE1RM: nil
        )
    }

    private static func bestClosestMatchCandidate(_ candidates: [RepRangeCandidate]) -> RepRangeCandidate? {
        var winner: RepRangeCandidate?
        var bestError = Double.infinity

        for candidate in candidates {
            if candidate.errorToEffectiveE1RM + Self.e1RMEpsilon < bestError {
                bestError = candidate.errorToEffectiveE1RM
                winner = candidate
            }
        }

        return winner
    }

    private static func bestProgressedCandidate(
        _ candidates: [RepRangeCandidate],
        targetReps: Int,
        recentCapacityBaselineE1RM: Double
    ) -> RepRangeCandidate? {
        candidates
            .filter { $0.impliedE1RM > recentCapacityBaselineE1RM + Self.e1RMEpsilon }
            .min { lhs, rhs in
                let lhsDelta = lhs.impliedE1RM - recentCapacityBaselineE1RM
                let rhsDelta = rhs.impliedE1RM - recentCapacityBaselineE1RM

                if abs(lhsDelta - rhsDelta) > Self.e1RMEpsilon {
                    return lhsDelta < rhsDelta
                }

                if abs(lhs.errorToEffectiveE1RM - rhs.errorToEffectiveE1RM) > Self.e1RMEpsilon {
                    return lhs.errorToEffectiveE1RM < rhs.errorToEffectiveE1RM
                }

                let lhsRepDistance = abs(lhs.reps - targetReps)
                let rhsRepDistance = abs(rhs.reps - targetReps)
                if lhsRepDistance != rhsRepDistance {
                    return lhsRepDistance < rhsRepDistance
                }

                return lhs.reps < rhs.reps
            }
    }

    private static func processCompletedSessionState(_ input: SuggestionEngineInput) -> CompletedSessionState {
        let completedSets = orderedCompletedSets(input.completedSessionSets)
        let configuredRestSeconds = input.settings.restTimerSeconds
        let recoveryConstant = input.settings.recoveryConstant
        let baseFatigueRate = input.settings.baseFatigueRate

        var sessionCapabilityE1RM = input.baseE1RM
        var runningFatigue: Double = 0.0
        var usedSessionCapabilityBlend = false
        var hasSeenCompletedWorkSet = false

        for (index, set) in completedSets.enumerated() {
            if input.settings.fatigueEnabled, index > 0 {
                let previousSet = completedSets[index - 1]
                let restSeconds = Double(previousSet.restDurationSeconds ?? Int(configuredRestSeconds))
                runningFatigue *= exp(-restSeconds / recoveryConstant)
            }

            let readiness = readinessState(
                capabilityE1RM: sessionCapabilityE1RM,
                projectedFatigue: runningFatigue,
                isFirstSet: isCapabilityTrackingSetType(set.setType) && !hasSeenCompletedWorkSet,
                settings: input.settings,
                calibrationAdjustment: input.calibrationAdjustment
            )

            if let normalizedObservedCapability = normalizedObservedCapability(
                for: set,
                readiness: readiness,
                formula: input.settings.formula
            ) {
                let blended = input.settings.sessionCapabilityPolicy.blend(
                    observedCapability: normalizedObservedCapability,
                    priorCapability: sessionCapabilityE1RM
                )
                sessionCapabilityE1RM = clampDownwardCapabilityMove(
                    from: sessionCapabilityE1RM,
                    to: blended
                )
                usedSessionCapabilityBlend = true
            }

            if isCapabilityTrackingSetType(set.setType) {
                hasSeenCompletedWorkSet = true
            }

            if input.settings.fatigueEnabled {
                let setFatigue = computeSetFatigue(
                    reps: set.reps,
                    rir: set.rir,
                    setType: set.setType,
                    baseFatigueRate: baseFatigueRate
                )
                runningFatigue = min(runningFatigue + setFatigue, Self.maxFatigue)
            }
        }

        return CompletedSessionState(
            sessionCapabilityE1RM: sessionCapabilityE1RM,
            runningFatigue: runningFatigue,
            usedSessionCapabilityBlend: usedSessionCapabilityBlend
        )
    }

    private static func normalizedObservedCapability(
        for set: SessionSetContext,
        readiness: ReadinessState,
        formula: E1RMFormula
    ) -> Double? {
        guard set.setType.isCapacityPointEstimate,
              set.weight > 0,
              set.reps > 0,
              let actualRIR = set.rir,
              actualRIR >= 0,
              actualRIR < 3 else { return nil }
        // RIR ≥ 3 sets are weak evidence of true capacity (RIR self-report is unreliable
        // far from failure and e1RM formulas degrade past ~10 reps to failure), so they
        // don't move sessionCapabilityE1RM. They still contribute to session fatigue.

        let totalReps = max(1, set.reps + Int(actualRIR))
        let observedEffectiveE1RM = formula.calculate(weight: set.weight, reps: totalReps)

        guard readiness.normalizationMultiplier > 0 else {
            return observedEffectiveE1RM
        }
        return observedEffectiveE1RM / readiness.normalizationMultiplier
    }

    /// Cap a downward move in the session capability estimate. Upward moves pass through.
    ///
    /// See ``maxDownwardCapabilityMove``.
    private static func clampDownwardCapabilityMove(from prior: Double, to proposed: Double) -> Double {
        guard prior > 0, proposed < prior else { return proposed }
        return max(proposed, prior * (1.0 - Self.maxDownwardCapabilityMove))
    }

    // MARK: - Suggestion floor

    /// A weight already completed in this session with reps to spare, and the set that proved it.
    struct SuggestionFloor: Sendable, Equatable {
        let weight: Double
        let completedWeight: Double
        let completedReps: Int
        let completedRIR: Double
    }

    /// The highest weight this session has already demonstrated the lifter can exceed.
    ///
    /// Makes a class of answer unreachable no matter what the model computes: if you lifted a
    /// weight several minutes ago *with reps left over*, you can lift that weight. That is a report
    /// of something that physically happened, and it is more trustworthy than anything the model
    /// infers from it — so where the two disagree, this wins.
    ///
    /// This is how RIR >= 3 sets are credited. `normalizedObservedCapability` still refuses them as
    /// a *point estimate*, for the reason stated there: RIR self-report is unreliable far from
    /// failure. But refusing them entirely meant a lifter reporting "five left in the tank" got a
    /// *lower* suggestion than the set they had just finished — the fatigue cost of the set was
    /// charged while its evidence of capacity was thrown away. Reading them as a lower bound takes
    /// the half of the signal that is trustworthy and needs no tuning constant to do it: the answer
    /// can never exceed one increment above a weight the lifter actually completed.
    ///
    /// Design: SUGGESTION_FLOOR_GUARDRAIL_DESIGN.md (D1-D9).
    static func suggestionFloor(
        target: SuggestionTarget,
        completedSets: [SessionSetContext],
        increment: Double
    ) -> SuggestionFloor? {
        // D1: compare on total reps — a set of 35 x 8 @ RIR 5 demonstrates capacity for 13 reps,
        // so a target of "12 @ RIR 0" is inside what was shown even though 12 > 8. Normalized
        // reps, never display reps: a `.totalAcrossSides` target is halved by the time it gets here.
        let targetTotal = target.reps + Int(target.rir)

        return completedSets
            .filter(\.completed)
            .compactMap { set -> SuggestionFloor? in
                // D5: only clean single-effort types. A drop set's trailing RIR does not describe
                // its opening weight; a partial's reps are not comparable to a full-ROM target.
                guard set.setType.isCapacityLowerBound else { return nil }
                // D6: no RIR, no floor. `missingRIRDefault` must not be reused here — assuming a
                // reserve nobody reported would invent a floor out of nothing.
                guard let rir = set.rir, rir >= 0 else { return nil }
                guard set.weight > 0, set.reps > 0 else { return nil }

                // D2: the surplus must beat the fatigue the model is entitled to claim.
                let surplus = (set.reps + Int(rir)) - targetTotal
                guard surplus >= Self.floorMinimumRepSurplus else { return nil }

                // D3: the next grid value strictly above — not the weight itself, which the
                // surplus proves was too light, and not an extrapolation of how much more, which
                // is the model's job and the model is what is under suspicion here. Expressed as
                // "next grid value" so an off-grid entry floors correctly: 33 kg on a 2.5 kg grid
                // gives 35, not 37.5.
                guard increment > 0 else { return nil }
                let steps = (set.weight + Self.e1RMEpsilon) / increment
                let floorWeight = (steps.rounded(.down) + 1) * increment

                return SuggestionFloor(
                    weight: floorWeight,
                    completedWeight: set.weight,
                    completedReps: set.reps,
                    completedRIR: rir
                )
            }
            // D4: every qualifying set contributes; take the maximum. An earlier heavier set still
            // bounds the answer when the most recent one was lighter.
            .max { $0.weight < $1.weight }
    }

    private static func readinessState(
        capabilityE1RM: Double,
        projectedFatigue: Double,
        isFirstSet: Bool,
        settings: SuggestionSettingsSnapshot,
        calibrationAdjustment: SuggestionCalibrationAdjustment
    ) -> ReadinessState {
        let fatigueDiscount = min(
            1.0,
            max(0.0, (1.0 - projectedFatigue) + calibrationAdjustment.fatigueDiscountOffset)
        )
        let readinessMultiplier = calibrationAdjustment.readinessMultiplier * fatigueDiscount

        var freshnessApplied = false
        let freshnessMultiplier: Double
        if isFirstSet && settings.freshnessEnabled {
            freshnessMultiplier = 1.0 + settings.freshnessPercent
            freshnessApplied = true
        } else {
            freshnessMultiplier = 1.0
        }
        let normalizationMultiplier = readinessMultiplier * freshnessMultiplier
        let readinessRawE1RM = capabilityE1RM * normalizationMultiplier

        let effectiveE1RM = readinessRawE1RM

        return ReadinessState(
            effectiveE1RM: effectiveE1RM,
            fatigueDiscount: fatigueDiscount,
            freshnessApplied: freshnessApplied,
            normalizationMultiplier: normalizationMultiplier
        )
    }

    /// Whether a completed set counts as "the lifter has started working" — it arms
    /// `hasSeenCompletedWorkSet` and therefore disarms the first-set freshness bonus.
    ///
    /// Deliberately the *wide* predicate. A drop set is not capacity evidence
    /// (`isCapacityPointEstimate`), but it absolutely means the lifter is no longer fresh, so
    /// narrowing this would let a set *after* a drop set wrongly claim the freshness bonus.
    private static func isCapabilityTrackingSetType(_ type: SetType) -> Bool {
        type.countsAsPerformedWork
    }

    private static func orderedCompletedSets(_ completedSets: [SessionSetContext]) -> [SessionSetContext] {
        completedSets.enumerated()
            .filter { $0.element.completed }
            .sorted { lhs, rhs in
                switch (lhs.element.completedAt, rhs.element.completedAt) {
                case let (leftDate?, rightDate?) where leftDate != rightDate:
                    return leftDate < rightDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
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
    /// Uses recent workout history in the recency window, then falls back to the most
    /// recent logged workout of any age (flagged as `.staleRecentPerformance`). Returns
    /// `.noData` if the exercise has never been logged.
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
