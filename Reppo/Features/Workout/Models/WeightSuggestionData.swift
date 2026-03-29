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
    let summary: String
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
    let chosenReps: Int
    let targetRIR: Double
    let targetRepRange: ClosedRange<Int>?
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
    /// Target reps used for this prescription.
    let targetReps: Int
    /// Target RIR used for this prescription.
    let targetRIR: Double
    /// Optional minimum target reps when the set is prescribed as a range.
    let targetRepMin: Int?
    /// Optional maximum target reps when the set is prescribed as a range.
    let targetRepMax: Int?
    /// Structured explanation shown in summary and details.
    let explanation: SuggestionExplanation
    /// Structured diagnostics shown in the expanded details panel.
    let diagnostics: SetSuggestionDiagnostics

    var contextLabel: String { explanation.summary }
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

/// Container for all weight suggestions for the current exercise.
struct WeightSuggestionData: Sendable {
    /// Ordered row-level state for each pending non-warmup set.
    let rowStates: [SetSuggestionState]
    /// The base e1RM used for all suggestions (for display in header).
    let baseE1RM: Double?
    /// Source of the e1RM estimate.
    let e1RMSource: E1RMSource
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
    let setResolutions: [SuggestionSetResolution]
    let pendingSets: [SuggestionPendingSetInput]
    let unavailableReason: SuggestionUnavailableReason?
}

/// App-model gathering and cache-key helpers for Smart Suggestions.
enum SuggestionCoordinator {
    static func prepare(
        exercise: Exercise?,
        workout: Workout? = nil,
        sets: [WorkoutSet],
        profile: HealthProfile?
    ) -> SuggestionPreparation {
        let completedSessionSets = completedSessionSets(from: sets)
        let setResolutions = resolvePendingSets(from: sets, profile: profile)
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
            setResolutions: setResolutions,
            pendingSets: pendingSets,
            unavailableReason: unavailableReason
        )
    }

    static func completedSessionSets(from sets: [WorkoutSet]) -> [SessionSetContext] {
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
                    restDurationSeconds: set.restDurationSeconds
                )
            }
    }

    private static func supportsSuggestions(for exercise: Exercise) -> Bool {
        exercise.trackingType == .weightReps || exercise.trackingType == .weightRepsDuration
    }

    private static func resolvePendingSets(
        from sets: [WorkoutSet],
        profile: HealthProfile?
    ) -> [SuggestionSetResolution] {
        var resolutions: [SuggestionSetResolution] = []
        var workingSetNumber = 0

        for (index, set) in sets.enumerated() {
            guard set.setType != .warmup else { continue }
            workingSetNumber += 1
            guard !set.completed else { continue }

            resolutions.append(
                SuggestionSetResolution(
                    setId: set.id,
                    setIndex: index,
                    setNumber: workingSetNumber,
                    eligibility: resolveTarget(for: set, profile: profile),
                    setType: set.setType
                )
            )
        }

        return resolutions
    }

    private static func resolveTarget(
        for set: WorkoutSet,
        profile: HealthProfile?
    ) -> SuggestionEligibility {
        let templateRepRange: ClosedRange<Int>?
        if let min = set.targetRepMin, let max = set.targetRepMax, min < max {
            templateRepRange = min...max
        } else {
            templateRepRange = nil
        }

        let draftRepRange = set.draftTargetRepRange
        let hasDraftRepTarget = set.hasDraftRepTarget
        let draftRepMin = set.draftTargetRepMin
        let draftRepMax = set.draftTargetRepMax
        let defaultTargetReps = normalizedDefaultTargetReps(from: profile)
        let defaultTargetRIR = normalizedDefaultTargetRIR(from: profile)

        let repsResolution: (value: Int, source: SuggestionTargetComponentSource)?
        if let reps = set.reps, reps > 0 {
            repsResolution = (reps, .explicitSet)
        } else if let draftRepRange {
            repsResolution = ((draftRepRange.lowerBound + draftRepRange.upperBound) / 2, .explicitSet)
        } else if let min = draftRepMin, let max = draftRepMax, min > 0, max > 0, min == max {
            repsResolution = (min, .explicitSet)
        } else if let min = draftRepMin, min > 0 {
            repsResolution = (min, .explicitSet)
        } else if let max = draftRepMax, max > 0 {
            repsResolution = (max, .explicitSet)
        } else if let min = set.targetRepMin, let max = set.targetRepMax {
            repsResolution = ((min + max) / 2, .template)
        } else if let min = set.targetRepMin {
            repsResolution = (min, .template)
        } else if let max = set.targetRepMax {
            repsResolution = (max, .template)
        } else if let defaultTargetReps {
            repsResolution = (defaultTargetReps, .smartDefault)
        } else {
            repsResolution = nil
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

        guard let repsResolution, repsResolution.value > 0, let rirResolution else {
            return .ineligible(reason: .missingTarget)
        }

        let repRange: ClosedRange<Int>?
        if set.reps != nil {
            repRange = nil
        } else if let draftRepRange {
            repRange = draftRepRange
        } else if hasDraftRepTarget {
            repRange = nil
        } else if repsResolution.source == .template {
            repRange = templateRepRange
        } else {
            repRange = nil
        }

        return .eligible(
            target: SuggestionTarget(
                reps: repsResolution.value,
                rir: rirResolution.value,
                repRange: repRange,
                repsSource: repsResolution.source,
                rirSource: rirResolution.source
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
        exercise: Exercise?,
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
                        "rir\(signatureNumber(target.rir))"
                    ]
                    if let range = target.repRange {
                        parts.append("rng\(range.lowerBound)-\(range.upperBound)")
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
                "rest\(exercise.defaultRestTime ?? -1)"
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
        exercise: Exercise?
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
}

/// Presentation/explanation layer for Smart Suggestions.
enum SuggestionExplainer {
    static func makeWeightSuggestionData(
        preparation: SuggestionPreparation,
        evaluation: SuggestionEvaluation
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
                configuredRestSeconds: configuredRestSeconds
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
            availability: availability
        )
    }

    private static func makeRowState(
        from resolution: SuggestionSetResolution,
        decision: SuggestionDecision?,
        fallbackReason: SuggestionUnavailableReason?,
        formula: E1RMFormula,
        configuredRestSeconds: Double
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
                    configuredRestSeconds: configuredRestSeconds
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
        configuredRestSeconds: Double
    ) -> SetSuggestion {
        let chosenReps = decision.bestReps ?? decision.targetReps
        return SetSuggestion(
            pendingSetId: decision.setId,
            setNumber: decision.setNumber,
            suggestedWeight: decision.prescribedWeight,
            targetReps: chosenReps,
            targetRIR: decision.targetRIR,
            targetRepMin: decision.repRange?.lowerBound,
            targetRepMax: decision.repRange?.upperBound,
            explanation: explanation(for: decision),
            diagnostics: diagnostics(
                for: decision,
                formula: formula,
                setType: setType,
                configuredRestSeconds: configuredRestSeconds
            )
        )
    }

    private static func explanation(for decision: SuggestionDecision) -> SuggestionExplanation {
        let readinessPercent = ((decision.effectiveE1RM / decision.sessionCapabilityE1RM) - 1.0) * 100.0
        var summaryParts = [
            "\(String(format: "%.1f", decision.historicalBaseE1RM)) kg capacity from \(decision.e1RMSource.label)",
            "readiness \(formatSignedPercent(readinessPercent))",
            "target from \(decision.targetSourceLabel)"
        ]
        if abs(decision.sessionCapabilityE1RM - decision.historicalBaseE1RM) > 0.05 {
            summaryParts.insert(
                "\(String(format: "%.1f", decision.sessionCapabilityE1RM)) kg \(decision.sessionCapabilitySourceLabel)",
                at: 1
            )
        }
        if let defaultUsageLabel = decision.targetDefaultUsageLabel {
            summaryParts.append(defaultUsageLabel)
        }
        let summary = summaryParts.joined(separator: ", ")

        return SuggestionExplanation(
            summary: summary,
            targetSourceLabel: decision.targetSourceLabel,
            repsSourceLabel: decision.targetRepsSourceLabel,
            rirSourceLabel: decision.targetRIRSourceLabel,
            defaultUsageLabel: decision.targetDefaultUsageLabel,
            baselineSourceLabel: decision.e1RMSource.label,
            sessionCapabilitySourceLabel: decision.sessionCapabilitySourceLabel,
            calibrationLabel: decision.calibrationAdjustment.explanation
        )
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
            chosenReps: chosenReps,
            targetRIR: decision.targetRIR,
            targetRepRange: decision.repRange,
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

    private static func formatSignedPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))%"
    }
}
