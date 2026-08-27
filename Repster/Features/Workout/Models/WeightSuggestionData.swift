// WeightSuggestionData.swift
// Transient display models and orchestration helpers for Smart Suggestions.
// The pure engine lives in LoadPrescriptionServiceProtocol.swift via SuggestionEngine.

import Foundation

/// Signed closeness information relative to an e1RM reference.
struct E1RMCloseness: Sendable {
    /// Signed absolute delta in kg (implied - reference).
    let delta: Double
    /// Signed percent delta (implied - reference) / reference * 100.
    let percent: Double
}

/// One weight candidate for a fixed reps target.
struct SuggestionWeightCandidate: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case downOneIncrement
        case suggested
        case upOneIncrement
    }

    var id: String { kind.rawValue }
    let kind: Kind
    /// Candidate weight in kg.
    let weight: Double
    /// Implied e1RM if this weight is used for the corresponding reps target.
    let impliedE1RM: Double
    let closenessToEffectiveE1RM: E1RMCloseness
    let closenessToBaseE1RM: E1RMCloseness
    let isRecommended: Bool
}

/// Alternative computations for a given reps target.
struct SuggestionRepAlternative: Identifiable, Sendable {
    var id: String { "reps-\(reps)" }
    let reps: Int
    let totalReps: Int
    let targetRIR: Double
    let intensityFactor: Double
    let rawWeight: Double
    let candidates: [SuggestionWeightCandidate]
}

/// User-facing explanation for why a suggestion exists.
struct SuggestionExplanation: Sendable {
    let userSummary: String
    let adminSummary: String
    let targetDisplayLabel: String
    let normalizedTargetLabel: String?
    let targetSourceLabel: String
    let repsSourceLabel: String
    let rirSourceLabel: String
    let defaultUsageLabel: String?
    let baselineSourceLabel: String
    let sessionCapabilitySourceLabel: String
    let calibrationLabel: String
}

/// Expanded diagnostics payload for a single suggestion row.
struct SetSuggestionDiagnostics: Sendable {
    let baseE1RM: Double
    let historicalBaseE1RM: Double
    let sessionCapabilityE1RM: Double
    let effectiveE1RM: Double
    let readinessPercent: Double
    let fatigueDiscount: Double
    let freshnessApplied: Bool
    let weightIncrement: Double
    let intensityFactor: Double
    let rawWeight: Double
    let roundedWeight: Double
    let displayTargetReps: Int
    let displayTargetRepRange: ClosedRange<Int>?
    let chosenReps: Int
    let normalizedTargetReps: Int
    let normalizedTargetRepRange: ClosedRange<Int>?
    let targetRIR: Double
    let targetRepRange: ClosedRange<Int>?
    let targetDisplayLabel: String
    let normalizedTargetLabel: String?
    let targetSourceLabel: String
    let repsSourceLabel: String
    let rirSourceLabel: String
    let defaultUsageLabel: String?
    let baselineSourceLabel: String
    let sessionCapabilitySourceLabel: String
    let calibrationLabel: String
    let selectionPolicy: SuggestionSelectionPolicy
    let selectionReferenceE1RM: Double?
    let alternatives: [SuggestionRepAlternative]
    // v2 fatigue diagnostics
    let projectedSessionFatigue: Double
    let setTypeFatigueMultiplier: Double
    let restSecondsUsed: Double
    let restSource: String
}

/// A single per-set weight suggestion for display.
struct SetSuggestion: Identifiable, Sendable {
    /// The underlying pending WorkoutSet identifier.
    let pendingSetId: UUID
    var id: UUID { pendingSetId }
    /// 1-indexed set number in the exercise.
    let setNumber: Int
    /// Prescribed weight in kg (views handle unit conversion).
    let suggestedWeight: Double
    /// User-facing target reps shown in the card.
    let targetReps: Int
    /// Target RIR used for this prescription.
    let targetRIR: Double
    /// Optional user-facing minimum target reps when the set is prescribed as a range.
    let targetRepMin: Int?
    /// Optional user-facing maximum target reps when the set is prescribed as a range.
    let targetRepMax: Int?
    let targetDisplayLabel: String
    /// The rep count the prescribed weight was actually priced for. When the set
    /// carries a rep range the engine picks one count inside it, and the weight
    /// is only a progression against that count — echoing the whole range back
    /// reads as a regression at the bottom of it.
    let prescribedDisplayLabel: String
    let normalizedTargetLabel: String?
    /// Structured explanation shown in summary and details.
    let explanation: SuggestionExplanation
    /// Structured diagnostics shown in the expanded details panel.
    let diagnostics: SetSuggestionDiagnostics

    var contextLabel: String { explanation.userSummary }
}

/// Row-level Smart Suggestion state for a pending set.
struct SetSuggestionState: Identifiable, Sendable {
    enum Availability: Sendable {
        case available(SetSuggestion)
        case unavailable(SuggestionUnavailableReason)
    }

    let setId: UUID
    let setIndex: Int
    let setNumber: Int
    let target: SuggestionTarget?
    let availability: Availability

    var id: UUID { setId }

    var suggestion: SetSuggestion? {
        guard case let .available(suggestion) = availability else { return nil }
        return suggestion
    }

    var unavailableReason: SuggestionUnavailableReason? {
        guard case let .unavailable(reason) = availability else { return nil }
        return reason
    }
}

/// Availability state for the current exercise's suggestion module.
enum SuggestionAvailability: Sendable {
    case available
    case unavailable(SuggestionUnavailableReason)
}

/// Snapshot of what was suggested for a set at the moment it was logged.
/// Captured in `ActiveWorkoutViewModel.completeSet` before the set transitions
/// from pending → completed. Used by the done strip to render
/// "= suggested" / "+1 kg vs sug" comparisons after the fact.
///
/// Nil-tolerant: a set logged before the snapshot path existed (or completed
/// while no suggestion was available) won't have one.
struct SuggestionSnapshot: Sendable, Equatable {
    let suggestedWeight: Double
    let targetReps: Int
    let targetRepMin: Int?
    let targetRepMax: Int?
    let targetDisplayLabel: String
    let targetRIR: Double
}

/// A completed working set that should appear in the "Logged this session"
/// section of the suggestion module, alongside any suggestion snapshot
/// captured when the user logged it.
struct CompletedSetSnapshot: Identifiable, Sendable, Equatable {
    let setId: UUID
    let setNumber: Int
    let weight: Double
    let reps: Int
    let rir: Double?
    let suggestion: SuggestionSnapshot?

    var id: UUID { setId }
}

/// Container for all weight suggestions for the current exercise.
struct WeightSuggestionData: Sendable {
    /// Ordered row-level state for each pending non-warmup set.
    let rowStates: [SetSuggestionState]
    /// The base e1RM used for all suggestions (for display in header).
    let baseE1RM: Double?
    /// Source of the e1RM estimate.
    let e1RMSource: E1RMSource
    /// Date of the workout the base e1RM is anchored on (nil when not derived
    /// from a specific workout). Used by the stale banner copy.
    let e1RMSourceWorkoutDate: Date?
    /// The actual top set behind the baseline e1RM, when available. Surfaced
    /// in the "last top" footer chip ("52 kg × 8 · RIR 1 · 8d ago").
    let baselineTopSet: HistoricalSetSnapshot?
    /// Working sets completed in the current session for this exercise, in
    /// workout order. Surfaced as compact done strips above the pending strips
    /// in the redesigned module. Each entry optionally carries the suggestion
    /// snapshot captured when the user logged the set, used to render
    /// "= suggested" / "+1 kg vs sug" inline comparisons.
    let completedInSessionSets: [CompletedSetSnapshot]
    /// Whether the module is available or unavailable for a typed reason.
    let availability: SuggestionAvailability

    var unavailableReason: SuggestionUnavailableReason? {
        guard case let .unavailable(reason) = availability else { return nil }
        return reason
    }

    var suggestions: [SetSuggestion] {
        rowStates.compactMap(\.suggestion)
    }

    func rowState(for setId: UUID) -> SetSuggestionState? {
        rowStates.first { $0.setId == setId }
    }

    func suggestion(for setId: UUID) -> SetSuggestion? {
        rowState(for: setId)?.suggestion
    }

    func suggestedWeight(for setId: UUID) -> Double? {
        suggestion(for: setId)?.suggestedWeight
    }
}

/// Prepared current-state snapshot used before engine evaluation.
struct SuggestionPreparation: Sendable {
    let cacheKey: String
    let completedSessionSets: [SessionSetContext]
    /// Completed working sets for the current exercise in workout order,
    /// surfaced to the UI as compact done strips in the suggestions module.
    /// Suggestion snapshots (what was suggested at log time) are joined in
    /// `SuggestionExplainer.makeWeightSuggestionData` from a VM-owned cache.
    let completedWorkingSetSnapshots: [CompletedSetSnapshot]
    let setResolutions: [SuggestionSetResolution]
    let pendingSets: [SuggestionPendingSetInput]
    let unavailableReason: SuggestionUnavailableReason?

    init(
        cacheKey: String,
        completedSessionSets: [SessionSetContext],
        completedWorkingSetSnapshots: [CompletedSetSnapshot] = [],
        setResolutions: [SuggestionSetResolution],
        pendingSets: [SuggestionPendingSetInput],
        unavailableReason: SuggestionUnavailableReason?
    ) {
        self.cacheKey = cacheKey
        self.completedSessionSets = completedSessionSets
        self.completedWorkingSetSnapshots = completedWorkingSetSnapshots
        self.setResolutions = setResolutions
        self.pendingSets = pendingSets
        self.unavailableReason = unavailableReason
    }
}

/// App-model gathering and cache-key helpers for Smart Suggestions.
enum SuggestionCoordinator {
    static func prepare(
        exercise: ChartExerciseData?,
        workout: Workout? = nil,
        sets: [WorkoutSet],
        profile: HealthProfile?
    ) -> SuggestionPreparation {
        let completedSessionSets = completedSessionSets(from: sets, exercise: exercise, profile: profile)
        let resolved = resolveWorkingSets(from: sets, exercise: exercise, profile: profile)
        let setResolutions = resolved.pending
        let completedWorkingSetSnapshots = resolved.completed
        let pendingSets = setResolutions.compactMap(pendingSetInput(from:))

        let unavailableReason: SuggestionUnavailableReason?
        if exercise == nil {
            unavailableReason = .missingExercise
        } else if !(profile?.prescriptionEnabled ?? true) {
            unavailableReason = .featureDisabled
        } else if let exercise, !supportsSuggestions(for: exercise) {
            unavailableReason = .unsupportedExercise
        } else if setResolutions.isEmpty {
            unavailableReason = .noPendingSets
        } else if pendingSets.isEmpty {
            unavailableReason = .missingTarget
        } else {
            unavailableReason = nil
        }

        return SuggestionPreparation(
            cacheKey: cacheKey(
                exercise: exercise,
                workout: workout,
                completedWorking: sets.filter { $0.completed && $0.setType != .warmup },
                setResolutions: setResolutions,
                profile: profile,
                unavailableReason: unavailableReason
            ),
            completedSessionSets: completedSessionSets,
            completedWorkingSetSnapshots: completedWorkingSetSnapshots,
            setResolutions: setResolutions,
            pendingSets: pendingSets,
            unavailableReason: unavailableReason
        )
    }

    /// Completed sets in engine space.
    ///
    /// `exercise` and `profile` are needed only to resolve `targetRIR` — the RIR the set was
    /// prescribed at, used when the lifter completed it without filling the chip. `resolveTarget`
    /// is the same resolver pending sets use, so the fallback chain (explicit → template →
    /// profile default) is identical and no set is left without a target just because it was
    /// logged ad hoc rather than from a template.
    static func completedSessionSets(
        from sets: [WorkoutSet],
        exercise: ChartExerciseData? = nil,
        profile: HealthProfile? = nil
    ) -> [SessionSetContext] {
        sets
            .filter { $0.completed && $0.setType != .warmup }
            .map { set in
                SessionSetContext(
                    weight: set.effectiveWeight ?? set.weight ?? 0,
                    reps: set.prReps,
                    rir: set.performanceRIR,
                    completedAt: set.completedAt,
                    completed: true,
                    setType: set.setType,
                    restDurationSeconds: set.restDurationSeconds,
                    targetRIR: resolvedTargetRIR(for: set, exercise: exercise, profile: profile)
                )
            }
    }

    /// The prescribed RIR for an already-completed set.
    ///
    /// Returns nil when the set carries its own RIR — the engine uses the real value in that
    /// case and never consults this — and when no target can be resolved at all.
    private static func resolvedTargetRIR(
        for set: WorkoutSet,
        exercise: ChartExerciseData?,
        profile: HealthProfile?
    ) -> Double? {
        guard set.performanceRIR == nil else { return nil }
        guard case let .eligible(target) = resolveTarget(for: set, exercise: exercise, profile: profile) else {
            return nil
        }
        return target.rir
    }

    private static func supportsSuggestions(for exercise: ChartExerciseData) -> Bool {
        exercise.trackingType == .weightReps || exercise.trackingType == .weightRepsDuration
    }

    /// Single-pass walk over working sets producing both:
    /// - `pending`: resolutions for incomplete working sets (engine input)
    /// - `completed`: snapshots for completed working sets (UI done strips),
    ///   with `suggestion = nil`; the explainer joins the suggestion snapshot
    ///   later from the VM-owned cache.
    /// Set numbering increments across both buckets so display numbers stay
    /// stable when a set transitions completed → pending or vice versa.
    private static func resolveWorkingSets(
        from sets: [WorkoutSet],
        exercise: ChartExerciseData?,
        profile: HealthProfile?
    ) -> (pending: [SuggestionSetResolution], completed: [CompletedSetSnapshot]) {
        var pending: [SuggestionSetResolution] = []
        var completed: [CompletedSetSnapshot] = []
        var workingSetNumber = 0

        for (index, set) in sets.enumerated() {
            guard set.setType != .warmup else { continue }
            workingSetNumber += 1

            if set.completed {
                completed.append(
                    CompletedSetSnapshot(
                        setId: set.id,
                        setNumber: workingSetNumber,
                        weight: set.effectiveWeight ?? set.weight ?? 0,
                        reps: set.prReps,
                        rir: set.performanceRIR,
                        suggestion: nil
                    )
                )
                continue
            }

            pending.append(
                SuggestionSetResolution(
                    setId: set.id,
                    setIndex: index,
                    setNumber: workingSetNumber,
                    eligibility: resolveTarget(for: set, exercise: exercise, profile: profile),
                    setType: set.setType
                )
            )
        }

        return (pending, completed)
    }

    private static func resolveTarget(
        for set: WorkoutSet,
        exercise: ChartExerciseData?,
        profile: HealthProfile?
    ) -> SuggestionEligibility {
        let repTargetMode = repTargetMode(for: exercise)
        let templateRepRange = makeRepRange(min: set.targetRepMin, max: set.targetRepMax)

        let overrideRepRange = set.overrideTargetRepRange
        let hasOverrideRepTarget = set.hasOverrideRepTarget
        let overrideRepMin = set.overrideTargetRepMin
        let overrideRepMax = set.overrideTargetRepMax
        let defaultTargetReps = normalizedDefaultTargetReps(from: profile)
        let defaultTargetRIR = normalizedDefaultTargetRIR(from: profile)

        let displayRepsResolution: (value: Int, source: SuggestionTargetComponentSource)?
        if let overrideRepRange {
            displayRepsResolution = ((overrideRepRange.lowerBound + overrideRepRange.upperBound) / 2, .explicitSet)
        } else if let min = overrideRepMin, let max = overrideRepMax, min > 0, max > 0, min == max {
            displayRepsResolution = (min, .explicitSet)
        } else if let min = overrideRepMin, min > 0 {
            displayRepsResolution = (min, .explicitSet)
        } else if let max = overrideRepMax, max > 0 {
            displayRepsResolution = (max, .explicitSet)
        } else if let reps = set.reps, reps > 0 {
            displayRepsResolution = (reps, .explicitSet)
        } else if let min = set.targetRepMin, let max = set.targetRepMax {
            displayRepsResolution = ((min + max) / 2, .template)
        } else if let min = set.targetRepMin {
            displayRepsResolution = (min, .template)
        } else if let max = set.targetRepMax {
            displayRepsResolution = (max, .template)
        } else if let defaultTargetReps {
            displayRepsResolution = (defaultTargetReps, .smartDefault)
        } else {
            displayRepsResolution = nil
        }

        let rirResolution: (value: Double, source: SuggestionTargetComponentSource)?
        if let rir = set.rir {
            rirResolution = (rir, .explicitSet)
        } else if let templateRIR = set.targetRIR {
            rirResolution = (Double(templateRIR), .template)
        } else if let defaultTargetRIR {
            rirResolution = (Double(defaultTargetRIR), .smartDefault)
        } else {
            rirResolution = nil
        }

        guard let displayRepsResolution, displayRepsResolution.value > 0, let rirResolution else {
            return .ineligible(reason: .missingTarget)
        }

        let displayRepRange: ClosedRange<Int>?
        if let overrideRepRange {
            displayRepRange = overrideRepRange
        } else if hasOverrideRepTarget || set.reps != nil {
            displayRepRange = nil
        } else if displayRepsResolution.source == .template {
            displayRepRange = templateRepRange
        } else {
            displayRepRange = nil
        }

        let normalizedReps = normalizedTargetReps(
            from: displayRepsResolution.value,
            mode: repTargetMode
        )
        let normalizedRepRange = normalizedTargetRepRange(
            from: displayRepRange,
            mode: repTargetMode
        )

        return .eligible(
            target: SuggestionTarget(
                reps: normalizedReps,
                rir: rirResolution.value,
                repRange: normalizedRepRange,
                repsSource: displayRepsResolution.source,
                rirSource: rirResolution.source,
                displayReps: displayRepsResolution.value,
                displayRepRange: displayRepRange,
                repTargetMode: repTargetMode
            )
        )
    }

    private static func pendingSetInput(from resolution: SuggestionSetResolution) -> SuggestionPendingSetInput? {
        guard case let .eligible(target) = resolution.eligibility else { return nil }
        return SuggestionPendingSetInput(
            setId: resolution.setId,
            setIndex: resolution.setIndex,
            setNumber: resolution.setNumber,
            target: target,
            setType: resolution.setType
        )
    }

    private static func cacheKey(
        exercise: ChartExerciseData?,
        workout: Workout?,
        completedWorking: [WorkoutSet],
        setResolutions: [SuggestionSetResolution],
        profile: HealthProfile?,
        unavailableReason: SuggestionUnavailableReason?
    ) -> String {
        let completedSignature = completedWorking
            .sorted { $0.orderInExercise < $1.orderInExercise }
            .map { set in
                let weight = set.effectiveWeight ?? set.weight ?? 0
                let reps = set.prReps
                let rir = set.performanceRIR ?? -1
                let completedAt = Int(set.completedAt?.timeIntervalSince1970 ?? 0)
                return [
                    set.id.uuidString,
                    "w\(signatureNumber(weight))",
                    "r\(reps)",
                    "rir\(signatureNumber(rir))",
                    "t\(completedAt)"
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        let resolutionSignature = setResolutions
            .map { resolution in
                let base = [
                    resolution.setId.uuidString,
                    "i\(resolution.setIndex)",
                    "n\(resolution.setNumber)"
                ]

                switch resolution.eligibility {
                case let .eligible(target):
                    var parts = base + [
                        "eligible",
                        "r\(target.reps)",
                        "displayR\(target.displayReps)",
                        "rir\(signatureNumber(target.rir))"
                    ]
                    if let range = target.repRange {
                        parts.append("rng\(range.lowerBound)-\(range.upperBound)")
                    }
                    if let displayRange = target.displayRepRange {
                        parts.append("displayRng\(displayRange.lowerBound)-\(displayRange.upperBound)")
                    }
                    if let repTargetMode = target.repTargetMode {
                        parts.append("mode\(repTargetMode.rawValue)")
                    }
                    return parts.joined(separator: ":")
                case let .ineligible(reason):
                    return (base + ["ineligible", reason.rawValue]).joined(separator: ":")
                }
            }
            .joined(separator: "|")

        let profileSignature: String
        if let profile {
            profileSignature = [
                "enabled\(profile.prescriptionEnabled ?? true)",
                "unit\(profile.unitPreference.rawValue)",
                "weeks\(profile.prescriptionRecencyWeeks ?? 6)",
                "inc\(signatureOptionalNumber(profile.prescriptionDefaultIncrement))",
                "defaultReps\(profile.prescriptionDefaultTargetReps ?? 8)",
                "defaultRIR\(profile.prescriptionDefaultTargetRIR ?? 2)",
                "fresh\(profile.prescriptionFreshnessBonus ?? false)",
                "freshPct\(signatureOptionalNumber(profile.prescriptionFreshnessBonusPercent))",
                "fatigue\(profile.prescriptionFatigueModelingEnabled ?? true)",
                "formula\(profile.e1RMFormula)",
                "learnedRate\(signatureOptionalNumber(profile.prescriptionLearnedFatigueRate))",
                "globalLearnSessions\(profile.prescriptionFatigueLearningSessionCount ?? 0)"
            ].joined(separator: ":")
        } else {
            profileSignature = "profile:unknown"
        }

        let exerciseSignature: String
        if let exercise {
            exerciseSignature = [
                exercise.id.uuidString,
                "tracking\(exercise.trackingType.rawValue)",
                "inc\(signatureOptionalNumber(exercise.weightIncrement))",
                "fatigueRate\(signatureOptionalNumber(exercise.fatigueRate))",
                "fatigueRateSource\(exercise.fatigueRateSourceRawValue ?? "nil")",
                "localLearnSessions\(exercise.fatigueLearningSessionCount ?? 0)",
                "recovery\(signatureOptionalNumber(exercise.recoveryConstant))",
                "rest\(exercise.defaultRestTime ?? -1)",
                "repMode\(exercise.unilateralRepTargetMode.rawValue)"
            ].joined(separator: ":")
        } else {
            exerciseSignature = "exercise:missing"
        }

        return [
            exerciseSignature,
            workoutProgressionHistorySignature(workout: workout, exercise: exercise),
            profileSignature,
            "reason:\(unavailableReason?.rawValue ?? "none")",
            completedSignature,
            resolutionSignature
        ].joined(separator: "||")
    }

    private static func signatureNumber(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func signatureOptionalNumber(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return signatureNumber(value)
    }

    private static func workoutProgressionHistorySignature(
        workout: Workout?,
        exercise: ChartExerciseData?
    ) -> String {
        guard let workout else { return "workout:none" }
        let excludedIds = (workout.excludedExerciseIdsFromProgressionHistory ?? [])
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",")
        let currentExerciseExcludedFromHistory: Bool
        if let exercise {
            currentExerciseExcludedFromHistory = workout.excludesFromProgressionHistory(exerciseId: exercise.id)
        } else {
            currentExerciseExcludedFromHistory = false
        }
        return [
            workout.id.uuidString,
            "all\(workout.excludesEntireWorkoutFromProgressionHistory)",
            "current\(currentExerciseExcludedFromHistory)",
            "ids\(excludedIds)"
        ].joined(separator: ":")
    }

    private static func normalizedDefaultTargetReps(from profile: HealthProfile?) -> Int? {
        guard let reps = profile?.prescriptionDefaultTargetReps, (1...30).contains(reps) else { return nil }
        return reps
    }

    private static func normalizedDefaultTargetRIR(from profile: HealthProfile?) -> Int? {
        guard let rir = profile?.prescriptionDefaultTargetRIR, (0...5).contains(rir) else { return nil }
        return rir
    }

    private static func repTargetMode(for exercise: ChartExerciseData?) -> UnilateralRepTargetMode? {
        guard let exercise,
              exercise.supportsUnilateralLogging,
              exercise.unilateral else {
            return nil
        }
        return exercise.unilateralRepTargetMode
    }

    private static func makeRepRange(min: Int?, max: Int?) -> ClosedRange<Int>? {
        guard let min, let max, min < max else { return nil }
        return min...max
    }

    private static func normalizedTargetReps(
        from displayReps: Int,
        mode: UnilateralRepTargetMode?
    ) -> Int {
        guard mode == .totalAcrossSides else { return displayReps }
        return max(1, Int(ceil(Double(displayReps) / 2.0)))
    }

    private static func normalizedTargetRepRange(
        from displayRepRange: ClosedRange<Int>?,
        mode: UnilateralRepTargetMode?
    ) -> ClosedRange<Int>? {
        guard let displayRepRange else { return nil }
        guard mode == .totalAcrossSides else { return displayRepRange }

        let normalizedLower = normalizedTargetReps(from: displayRepRange.lowerBound, mode: mode)
        let normalizedUpper = normalizedTargetReps(from: displayRepRange.upperBound, mode: mode)
        guard normalizedLower < normalizedUpper else { return nil }
        return normalizedLower...normalizedUpper
    }
}

/// Presentation/explanation layer for Smart Suggestions.
enum SuggestionExplainer {
    static func makeWeightSuggestionData(
        preparation: SuggestionPreparation,
        evaluation: SuggestionEvaluation,
        unitPreference: UnitPreference,
        suggestionSnapshots: [UUID: SuggestionSnapshot] = [:]
    ) -> WeightSuggestionData {
        let formula = evaluation.input?.settings.formula ?? .epley
        let configuredRestSeconds = evaluation.input?.settings.restTimerSeconds ?? 150.0
        let decisionsBySetId = Dictionary(uniqueKeysWithValues: evaluation.decisions.map { ($0.setId, $0) })
        let rowStates = preparation.setResolutions.map { resolution in
            makeRowState(
                from: resolution,
                decision: decisionsBySetId[resolution.setId],
                fallbackReason: evaluation.unavailableReason ?? preparation.unavailableReason,
                formula: formula,
                configuredRestSeconds: configuredRestSeconds,
                unitPreference: unitPreference
            )
        }

        // Join the per-set suggestion snapshot (captured by the VM at log time)
        // onto each completed snapshot from the preparation pass.
        let completedInSessionSets = preparation.completedWorkingSetSnapshots.map { snapshot in
            CompletedSetSnapshot(
                setId: snapshot.setId,
                setNumber: snapshot.setNumber,
                weight: snapshot.weight,
                reps: snapshot.reps,
                rir: snapshot.rir,
                suggestion: suggestionSnapshots[snapshot.setId]
            )
        }

        let availability: SuggestionAvailability
        if rowStates.contains(where: { $0.suggestion != nil }) {
            availability = .available
        } else {
            availability = .unavailable(
                evaluation.unavailableReason ??
                preparation.unavailableReason ??
                rowStates.first?.unavailableReason ??
                .calculationFailed
            )
        }

        return WeightSuggestionData(
            rowStates: rowStates,
            baseE1RM: evaluation.decisions.first?.baseE1RM ?? evaluation.input?.baseE1RM,
            e1RMSource: evaluation.decisions.first?.e1RMSource ?? evaluation.input?.baseSource ?? .noData,
            e1RMSourceWorkoutDate: evaluation.decisions.first?.e1RMSourceWorkoutDate
                ?? evaluation.input?.baseSourceWorkoutDate,
            baselineTopSet: evaluation.decisions.first?.e1RMSourceTopSet
                ?? evaluation.input?.baseSourceTopSet,
            completedInSessionSets: completedInSessionSets,
            availability: availability
        )
    }

    private static func makeRowState(
        from resolution: SuggestionSetResolution,
        decision: SuggestionDecision?,
        fallbackReason: SuggestionUnavailableReason?,
        formula: E1RMFormula,
        configuredRestSeconds: Double,
        unitPreference: UnitPreference
    ) -> SetSuggestionState {
        let target: SuggestionTarget?
        if case let .eligible(resolvedTarget) = resolution.eligibility {
            target = resolvedTarget
        } else {
            target = nil
        }

        if let decision {
            return SetSuggestionState(
                setId: resolution.setId,
                setIndex: resolution.setIndex,
                setNumber: resolution.setNumber,
                target: target,
                availability: .available(makeSuggestion(
                    for: decision,
                    formula: formula,
                    setType: resolution.setType,
                    configuredRestSeconds: configuredRestSeconds,
                    unitPreference: unitPreference
                ))
            )
        }

        let reason: SuggestionUnavailableReason
        switch resolution.eligibility {
        case let .ineligible(unavailableReason):
            reason = unavailableReason
        case .eligible:
            reason = fallbackReason ?? .calculationFailed
        }

        return SetSuggestionState(
            setId: resolution.setId,
            setIndex: resolution.setIndex,
            setNumber: resolution.setNumber,
            target: target,
            availability: .unavailable(reason)
        )
    }

    private static func makeSuggestion(
        for decision: SuggestionDecision,
        formula: E1RMFormula,
        setType: SetType,
        configuredRestSeconds: Double,
        unitPreference: UnitPreference
    ) -> SetSuggestion {
        let chosenDisplayReps = resolvedDisplayTargetReps(for: decision)
        return SetSuggestion(
            pendingSetId: decision.setId,
            setNumber: decision.setNumber,
            suggestedWeight: decision.prescribedWeight,
            targetReps: chosenDisplayReps,
            targetRIR: decision.targetRIR,
            targetRepMin: decision.displayRepRange?.lowerBound,
            targetRepMax: decision.displayRepRange?.upperBound,
            targetDisplayLabel: decision.targetDisplayLabel,
            prescribedDisplayLabel: decision.target.displayLabel(forReps: chosenDisplayReps),
            normalizedTargetLabel: decision.normalizedTargetLabel,
            explanation: explanation(for: decision, unitPreference: unitPreference),
            diagnostics: diagnostics(
                for: decision,
                formula: formula,
                setType: setType,
                configuredRestSeconds: configuredRestSeconds
            )
        )
    }

    private static func explanation(
        for decision: SuggestionDecision,
        unitPreference: UnitPreference
    ) -> SuggestionExplanation {
        let readinessPercent = ((decision.effectiveE1RM / decision.sessionCapabilityE1RM) - 1.0) * 100.0
        var summaryParts = [
            "\(UnitConversion.formatWeightLabel(decision.historicalBaseE1RM, unitPreference: unitPreference)) capacity from \(decision.e1RMSource.label)",
            "readiness \(formatSignedPercent(readinessPercent))",
            "\(decision.targetDisplayLabel) target from \(decision.targetSourceLabel)"
        ]
        if abs(decision.sessionCapabilityE1RM - decision.historicalBaseE1RM) > 0.05 {
            summaryParts.insert(
                "\(UnitConversion.formatWeightLabel(decision.sessionCapabilityE1RM, unitPreference: unitPreference)) \(decision.sessionCapabilitySourceLabel)",
                at: 1
            )
        }
        if let normalizedTargetLabel = decision.normalizedTargetLabel {
            summaryParts.append(normalizedTargetLabel)
        }
        if let defaultUsageLabel = decision.targetDefaultUsageLabel {
            summaryParts.append(defaultUsageLabel)
        }
        let adminSummary = summaryParts.joined(separator: ", ")

        let userSummary = contextualUserSummary(for: decision)

        return SuggestionExplanation(
            userSummary: userSummary,
            adminSummary: adminSummary,
            targetDisplayLabel: decision.targetDisplayLabel,
            normalizedTargetLabel: decision.normalizedTargetLabel,
            targetSourceLabel: decision.targetSourceLabel,
            repsSourceLabel: decision.targetRepsSourceLabel,
            rirSourceLabel: decision.targetRIRSourceLabel,
            defaultUsageLabel: decision.targetDefaultUsageLabel,
            baselineSourceLabel: decision.e1RMSource.label,
            sessionCapabilitySourceLabel: decision.sessionCapabilitySourceLabel,
            calibrationLabel: decision.calibrationAdjustment.explanation
        )
    }

    /// Picks one of four contextual one-liners based on which engine signal
    /// most explains the prescribed weight. Priority: progression bump >
    /// session fatigue > in-session readjustment > generic baseline.
    private static func contextualUserSummary(for decision: SuggestionDecision) -> String {
        let hasProgressionBump = decision.freshnessApplied
            || decision.selectionPolicy == .firstSetProgressionAboveRecentPeak
        let meaningfulFatigue = decision.fatigueDiscount < 0.99
            || decision.projectedSessionFatigue > 0.01
        let sessionAdjusted = abs(decision.sessionCapabilityE1RM - decision.historicalBaseE1RM) > 0.05

        let base: String
        if hasProgressionBump {
            base = "Nudging up from your last workout's peak."
        } else if meaningfulFatigue {
            base = "Easing off slightly to manage session fatigue."
        } else if sessionAdjusted {
            base = "Adjusted from how this session is going."
        } else {
            base = "Based on your recent performance for this rep target."
        }

        if decision.targetDefaultUsageLabel != nil {
            return "\(base) Missing targets used your Smart Suggestions defaults."
        }
        return base
    }

    private static func diagnostics(
        for decision: SuggestionDecision,
        formula: E1RMFormula,
        setType: SetType,
        configuredRestSeconds: Double
    ) -> SetSuggestionDiagnostics {
        let chosenReps = decision.bestReps ?? decision.targetReps
        let readinessPercent = ((decision.effectiveE1RM / decision.sessionCapabilityE1RM) - 1.0) * 100.0

        return SetSuggestionDiagnostics(
            baseE1RM: decision.baseE1RM,
            historicalBaseE1RM: decision.historicalBaseE1RM,
            sessionCapabilityE1RM: decision.sessionCapabilityE1RM,
            effectiveE1RM: decision.effectiveE1RM,
            readinessPercent: readinessPercent,
            fatigueDiscount: decision.fatigueDiscount,
            freshnessApplied: decision.freshnessApplied,
            weightIncrement: decision.weightIncrement,
            intensityFactor: decision.intensityFactor,
            rawWeight: decision.rawWeight,
            roundedWeight: decision.prescribedWeight,
            displayTargetReps: resolvedDisplayTargetReps(for: decision),
            displayTargetRepRange: decision.displayRepRange,
            chosenReps: chosenReps,
            normalizedTargetReps: decision.targetReps,
            normalizedTargetRepRange: decision.repRange,
            targetRIR: decision.targetRIR,
            targetRepRange: decision.repRange,
            targetDisplayLabel: decision.targetDisplayLabel,
            normalizedTargetLabel: decision.normalizedTargetLabel,
            targetSourceLabel: decision.targetSourceLabel,
            repsSourceLabel: decision.targetRepsSourceLabel,
            rirSourceLabel: decision.targetRIRSourceLabel,
            defaultUsageLabel: decision.targetDefaultUsageLabel,
            baselineSourceLabel: decision.e1RMSource.label,
            sessionCapabilitySourceLabel: decision.sessionCapabilitySourceLabel,
            calibrationLabel: decision.calibrationAdjustment.explanation,
            selectionPolicy: decision.selectionPolicy,
            selectionReferenceE1RM: decision.selectionReferenceE1RM,
            alternatives: alternatives(for: decision, formula: formula),
            projectedSessionFatigue: decision.projectedSessionFatigue,
            setTypeFatigueMultiplier: SuggestionEngine.setTypeMultiplier(setType),
            restSecondsUsed: configuredRestSeconds,
            restSource: "configured"
        )
    }

    private static func alternatives(
        for decision: SuggestionDecision,
        formula: E1RMFormula
    ) -> [SuggestionRepAlternative] {
        let chosenReps = decision.bestReps ?? decision.targetReps
        let resolvedChosenReps: Int
        if let repRange = decision.repRange {
            resolvedChosenReps = min(max(chosenReps, repRange.lowerBound), repRange.upperBound)
        } else {
            resolvedChosenReps = chosenReps
        }

        let repCandidates: [Int]
        if let repRange = decision.repRange {
            repCandidates = Array(repRange)
        } else {
            repCandidates = (0..<4).map { resolvedChosenReps + $0 }
        }

        return repCandidates.map { candidateReps in
            let reps = max(1, candidateReps)
            let totalReps = max(1, reps + Int(decision.targetRIR))
            let intensityFactor = max(0.3, formula.reverseCalculate(e1RM: 1.0, reps: totalReps))
            let rawWeight = decision.effectiveE1RM * intensityFactor
            let roundedWeight = roundToIncrement(rawWeight, increment: decision.weightIncrement)
            let downWeight = max(0, roundedWeight - decision.weightIncrement)
            let upWeight = roundedWeight + decision.weightIncrement

            let candidateKinds: [SuggestionWeightCandidate.Kind] = [
                .downOneIncrement,
                .suggested,
                .upOneIncrement
            ]

            let candidates = candidateKinds.map { kind in
                let weight: Double
                switch kind {
                case .downOneIncrement:
                    weight = downWeight
                case .suggested:
                    weight = roundedWeight
                case .upOneIncrement:
                    weight = upWeight
                }

                let impliedE1RM = formula.calculate(weight: weight, reps: totalReps)
                return SuggestionWeightCandidate(
                    kind: kind,
                    weight: weight,
                    impliedE1RM: impliedE1RM,
                    closenessToEffectiveE1RM: closeness(impliedE1RM: impliedE1RM, referenceE1RM: decision.effectiveE1RM),
                    closenessToBaseE1RM: closeness(impliedE1RM: impliedE1RM, referenceE1RM: decision.baseE1RM),
                    isRecommended: reps == resolvedChosenReps && kind == .suggested
                )
            }

            return SuggestionRepAlternative(
                reps: reps,
                totalReps: totalReps,
                targetRIR: decision.targetRIR,
                intensityFactor: intensityFactor,
                rawWeight: rawWeight,
                candidates: candidates
            )
        }
    }

    private static func closeness(impliedE1RM: Double, referenceE1RM: Double) -> E1RMCloseness {
        let delta = impliedE1RM - referenceE1RM
        let percent = referenceE1RM > 0 ? (delta / referenceE1RM) * 100.0 : 0
        return E1RMCloseness(delta: delta, percent: percent)
    }

    private static func roundToIncrement(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }

    private static func resolvedDisplayTargetReps(for decision: SuggestionDecision) -> Int {
        guard let normalizedBestReps = decision.bestReps else {
            return decision.displayTargetReps
        }
        guard decision.target.repTargetMode == .totalAcrossSides,
              let displayRange = decision.displayRepRange else {
            return normalizedBestReps
        }

        let matchingDisplayReps = displayRange.filter {
            normalizedTotalAcrossSidesDisplayReps($0) == normalizedBestReps
        }

        guard !matchingDisplayReps.isEmpty else {
            return decision.displayTargetReps
        }

        return matchingDisplayReps.min { lhs, rhs in
            let lhsDistance = abs(lhs - decision.displayTargetReps)
            let rhsDistance = abs(rhs - decision.displayTargetReps)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs < rhs
        } ?? decision.displayTargetReps
    }

    private static func normalizedTotalAcrossSidesDisplayReps(_ displayReps: Int) -> Int {
        max(1, Int(ceil(Double(displayReps) / 2.0)))
    }

    private static func formatSignedPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))%"
    }
}
