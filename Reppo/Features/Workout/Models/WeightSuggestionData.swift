// WeightSuggestionData.swift
// Transient display models and presentation helpers for Smart Suggestions.
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

/// Expanded diagnostics payload for a single suggestion row.
struct SetSuggestionDiagnostics: Sendable {
    let baseE1RM: Double
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
    let alternatives: [SuggestionRepAlternative]
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
    /// Brief context string, e.g. "104 kg capacity from recent top workouts, readiness -5.0%".
    let contextLabel: String
    /// Structured diagnostics shown in the expanded details panel.
    let diagnostics: SetSuggestionDiagnostics
}

/// Container for all weight suggestions for the current exercise.
struct WeightSuggestionData: Sendable {
    /// Per-set suggestions for unfilled working sets.
    let suggestions: [SetSuggestion]
    /// The base e1RM used for all suggestions (for display in header).
    let baseE1RM: Double?
    /// Source of the e1RM estimate.
    let e1RMSource: E1RMSource

    func suggestion(for setId: UUID) -> SetSuggestion? {
        suggestions.first { $0.pendingSetId == setId }
    }
}

/// App-model gathering and cache-key helpers for Smart Suggestions.
enum SuggestionCoordinator {
    static func completedSessionSets(from sets: [WorkoutSet]) -> [SessionSetContext] {
        sets
            .filter { $0.completed && $0.setType != .warmup }
            .map { set in
                SessionSetContext(
                    weight: set.effectiveWeight ?? set.weight ?? 0,
                    reps: set.reps ?? 0,
                    rir: set.rir,
                    completedAt: set.completedAt,
                    completed: true
                )
            }
    }

    static func pendingSetInputs(from sets: [WorkoutSet]) -> [SuggestionPendingSetInput] {
        var pendingSets: [SuggestionPendingSetInput] = []
        var workingSetNumber = 0

        for (index, set) in sets.enumerated() {
            guard set.setType != .warmup else { continue }
            workingSetNumber += 1
            guard !set.completed else { continue }

            let targetReps: Int?
            if let reps = set.reps, reps > 0 {
                targetReps = reps
            } else if let min = set.targetRepMin, let max = set.targetRepMax {
                targetReps = (min + max) / 2
            } else if let min = set.targetRepMin {
                targetReps = min
            } else if let max = set.targetRepMax {
                targetReps = max
            } else {
                targetReps = 8
            }

            let targetRIR: Double
            if let rir = set.rir {
                targetRIR = rir
            } else if let templateRIR = set.targetRIR {
                targetRIR = Double(templateRIR)
            } else {
                targetRIR = 2.0
            }

            guard let targetReps, targetReps > 0 else { continue }

            let repRange: ClosedRange<Int>?
            if let min = set.targetRepMin, let max = set.targetRepMax, min < max {
                repRange = min...max
            } else {
                repRange = nil
            }

            pendingSets.append(
                SuggestionPendingSetInput(
                    setId: set.id,
                    setIndex: index,
                    setNumber: workingSetNumber,
                    targetReps: targetReps,
                    targetRIR: targetRIR,
                    repRange: repRange
                )
            )
        }

        return pendingSets
    }

    static func cacheKey(
        exercise: Exercise,
        completedWorking: [WorkoutSet],
        pendingSets: [SuggestionPendingSetInput],
        profile: HealthProfile?
    ) -> String {
        let completedSignature = completedWorking
            .sorted { $0.orderInExercise < $1.orderInExercise }
            .map { set in
                let weight = set.effectiveWeight ?? set.weight ?? 0
                let reps = set.reps ?? 0
                let rir = set.rir ?? -1
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

        let pendingSignature = pendingSets
            .map { pendingSet in
                var parts = [
                    pendingSet.setId.uuidString,
                    "i\(pendingSet.setIndex)",
                    "n\(pendingSet.setNumber)",
                    "r\(pendingSet.targetReps)",
                    "rir\(signatureNumber(pendingSet.targetRIR))"
                ]
                if let range = pendingSet.repRange {
                    parts.append("rng\(range.lowerBound)-\(range.upperBound)")
                }
                return parts.joined(separator: ":")
            }
            .joined(separator: "|")

        let profileSignature: String
        if let profile {
            profileSignature = [
                "enabled\(profile.prescriptionEnabled ?? true)",
                "weeks\(profile.prescriptionRecencyWeeks ?? 6)",
                "inc\(signatureOptionalNumber(profile.prescriptionDefaultIncrement))",
                "fresh\(profile.prescriptionFreshnessBonus ?? false)",
                "freshPct\(signatureOptionalNumber(profile.prescriptionFreshnessBonusPercent))",
                "fatigue\(profile.prescriptionFatigueModelingEnabled ?? true)",
                "recovery\(signatureOptionalNumber(profile.prescriptionDefaultRecoveryConstant))",
                "formula\(profile.e1RMFormula)",
                "updated\(Int(profile.updatedAt.timeIntervalSince1970))"
            ].joined(separator: ":")
        } else {
            profileSignature = "profile:unknown"
        }

        let exerciseSignature = [
            "inc\(signatureOptionalNumber(exercise.weightIncrement))",
            "fatigueRate\(signatureOptionalNumber(exercise.fatigueRate))",
            "recovery\(signatureOptionalNumber(exercise.recoveryConstant))"
        ].joined(separator: ":")

        return [
            exercise.id.uuidString,
            exerciseSignature,
            profileSignature,
            completedSignature,
            pendingSignature
        ].joined(separator: "||")
    }

    private static func signatureNumber(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func signatureOptionalNumber(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return signatureNumber(value)
    }
}

/// Presentation/explanation layer for Smart Suggestions.
enum SuggestionExplainer {
    static func makeWeightSuggestionData(_ evaluation: SuggestionEvaluation) -> WeightSuggestionData? {
        let suggestions = evaluation.results.map { result in
            let chosenReps = result.bestReps ?? result.targetReps
            return SetSuggestion(
                pendingSetId: result.setId,
                setNumber: result.setNumber,
                suggestedWeight: result.prescribedWeight,
                targetReps: chosenReps,
                targetRIR: result.targetRIR,
                targetRepMin: result.repRange?.lowerBound,
                targetRepMax: result.repRange?.upperBound,
                contextLabel: contextLabel(for: result),
                diagnostics: diagnostics(for: result, formula: evaluation.input.settings.formula)
            )
        }

        guard !suggestions.isEmpty else { return nil }

        return WeightSuggestionData(
            suggestions: suggestions,
            baseE1RM: evaluation.results.first?.baseE1RM,
            e1RMSource: evaluation.results.first?.e1RMSource ?? evaluation.input.baseSource
        )
    }

    private static func contextLabel(for result: SuggestionEngineResult) -> String {
        let capacityStr = String(format: "%.1f", result.baseE1RM)
        let readinessPercent = ((result.effectiveE1RM / result.baseE1RM) - 1.0) * 100.0

        let sourceStr: String
        switch result.e1RMSource {
        case .recentPerformance:
            sourceStr = "recent top workouts"
        case .historicalPR:
            sourceStr = "PR history"
        case .noData:
            sourceStr = "no data"
        }

        return [
            "\(capacityStr) kg capacity from \(sourceStr)",
            "readiness \(formatSignedPercent(readinessPercent))"
        ].joined(separator: ", ")
    }

    private static func diagnostics(
        for result: SuggestionEngineResult,
        formula: E1RMFormula
    ) -> SetSuggestionDiagnostics {
        let chosenReps = result.bestReps ?? result.targetReps
        let readinessPercent = ((result.effectiveE1RM / result.baseE1RM) - 1.0) * 100.0

        return SetSuggestionDiagnostics(
            baseE1RM: result.baseE1RM,
            effectiveE1RM: result.effectiveE1RM,
            readinessPercent: readinessPercent,
            fatigueDiscount: result.fatigueDiscount,
            freshnessApplied: result.freshnessApplied,
            weightIncrement: result.weightIncrement,
            intensityFactor: result.intensityFactor,
            rawWeight: result.rawWeight,
            roundedWeight: result.prescribedWeight,
            chosenReps: chosenReps,
            targetRIR: result.targetRIR,
            targetRepRange: result.repRange,
            alternatives: alternatives(for: result, formula: formula)
        )
    }

    private static func alternatives(
        for result: SuggestionEngineResult,
        formula: E1RMFormula
    ) -> [SuggestionRepAlternative] {
        let chosenReps = result.bestReps ?? result.targetReps
        let resolvedChosenReps: Int
        if let repRange = result.repRange {
            resolvedChosenReps = min(max(chosenReps, repRange.lowerBound), repRange.upperBound)
        } else {
            resolvedChosenReps = chosenReps
        }

        let repCandidates: [Int]
        if let repRange = result.repRange {
            repCandidates = Array(repRange)
        } else {
            repCandidates = (0..<4).map { resolvedChosenReps + $0 }
        }

        return repCandidates.map { candidateReps in
            let reps = max(1, candidateReps)
            let totalReps = max(1, reps + Int(result.targetRIR))
            let intensityFactor = max(0.3, formula.reverseCalculate(e1RM: 1.0, reps: totalReps))
            let rawWeight = result.effectiveE1RM * intensityFactor
            let roundedWeight = roundToIncrement(rawWeight, increment: result.weightIncrement)
            let downWeight = max(0, roundedWeight - result.weightIncrement)
            let upWeight = roundedWeight + result.weightIncrement

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
                    closenessToEffectiveE1RM: closeness(impliedE1RM: impliedE1RM, referenceE1RM: result.effectiveE1RM),
                    closenessToBaseE1RM: closeness(impliedE1RM: impliedE1RM, referenceE1RM: result.baseE1RM),
                    isRecommended: reps == resolvedChosenReps && kind == .suggested
                )
            }

            return SuggestionRepAlternative(
                reps: reps,
                totalReps: totalReps,
                targetRIR: result.targetRIR,
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
