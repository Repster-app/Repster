// WeightSuggestionCardView.swift
// Card displaying per-set weight suggestions with expandable diagnostics.
// Follows the card styling pattern from E1RMCardView (bgCard, cornerRadius 14, padding 14).

import SwiftUI

struct WeightSuggestionCardView: View {
    let data: WeightSuggestionData
    let unitPreference: UnitPreference
    @State private var showDetails: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach(Array(data.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                suggestionRow(suggestion)

                if index < data.suggestions.count - 1 {
                    Divider()
                        .overlay(Color.border.opacity(0.45))
                        .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accent)
                    .frame(width: 22, height: 22)
                    .background(Color.accent.opacity(0.08))
                    .cornerRadius(6)

                Text("Smart Suggestions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                if let baseE1RM = data.baseE1RM {
                    Text("e1RM: \(formatWeight(baseE1RM))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDetails.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(showDetails ? "Hide details" : "Details")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.bg.opacity(0.55))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Suggestion Row

    private func suggestionRow(_ suggestion: SetSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text("Set \(suggestion.setNumber): ")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                Text(formatWeight(suggestion.suggestedWeight))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text(" \u{00D7} \(suggestion.targetReps)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }

            Text(suggestion.explanation.summary)
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)

            if showDetails {
                suggestionDetails(suggestion.diagnostics)
            }
        }
    }

    // MARK: - Details

    private func suggestionDetails(_ diagnostics: SetSuggestionDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    "base \(formatWeight(diagnostics.baseE1RM)) | effective \(formatWeight(diagnostics.effectiveE1RM)) (\(formatSignedPercent(diagnostics.readinessPercent)))"
                )
                Text(
                    "fatigue \(String(format: "%.3f", diagnostics.fatigueDiscount)) | freshness \(diagnostics.freshnessApplied ? "on" : "off")"
                )
                Text(
                    "intensity \(String(format: "%.3f", diagnostics.intensityFactor)) | RIR \(formatSimpleNumber(diagnostics.targetRIR))"
                )
                Text(
                    "target source \(diagnostics.targetSourceLabel) | baseline \(diagnostics.baselineSourceLabel)"
                )
                Text(
                    diagnostics.calibrationLabel
                )
                Text(
                    "raw \(formatWeight(diagnostics.rawWeight)) -> rounded \(formatWeight(diagnostics.roundedWeight)) (inc \(formatWeight(diagnostics.weightIncrement)))"
                )
                if let range = diagnostics.targetRepRange {
                    Text("rep range \(range.lowerBound)-\(range.upperBound), chosen \(diagnostics.chosenReps)")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.textTertiary)

            Text(alternativesHeaderText(diagnostics))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)

            ForEach(diagnostics.alternatives) { alternative in
                alternativeRow(alternative, chosenReps: diagnostics.chosenReps)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bg.opacity(0.45))
        .cornerRadius(10)
    }

    private func alternativeRow(_ alternative: SuggestionRepAlternative, chosenReps: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("Reps \(alternative.reps)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                if alternative.reps == chosenReps {
                    Text("selected")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accent.opacity(0.12))
                        .cornerRadius(6)
                }

                Spacer()
                Text("raw \(formatWeight(alternative.rawWeight))")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }

            ForEach(alternative.candidates) { candidate in
                candidateRow(candidate)
            }
        }
        .padding(8)
        .background(Color.bg.opacity(0.35))
        .cornerRadius(8)
    }

    private func candidateRow(_ candidate: SuggestionWeightCandidate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(candidateKindLabel(candidate.kind))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                Text(formatWeight(candidate.weight))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                if candidate.isRecommended {
                    Text("recommended")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.success)
                }

                Spacer()
                Text("implied \(formatWeight(candidate.impliedE1RM))")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }

            Text(
                "vs effective: \(formatCloseness(candidate.closenessToEffectiveE1RM)) | vs base: \(formatCloseness(candidate.closenessToBaseE1RM))"
            )
            .font(.system(size: 9))
            .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Formatting

    private func candidateKindLabel(_ kind: SuggestionWeightCandidate.Kind) -> String {
        switch kind {
        case .downOneIncrement: return "-1 inc"
        case .suggested: return "suggested"
        case .upOneIncrement: return "+1 inc"
        }
    }

    private func alternativesHeaderText(_ diagnostics: SetSuggestionDiagnostics) -> String {
        guard let range = diagnostics.targetRepRange else {
            return "Alternatives (x...x+3)"
        }
        return "Alternatives (\(range.lowerBound)-\(range.upperBound) rep range)"
    }

    private func formatCloseness(_ closeness: E1RMCloseness) -> String {
        "Delta \(formatSignedWeight(closeness.delta)) (\(formatSignedPercent(closeness.percent)))"
    }

    private func formatSignedWeight(_ kg: Double) -> String {
        let value = unitPreference == .imperial ? UnitConversion.kgToLbs(kg) : kg
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        let absValue = abs(value)
        let unit = unitPreference == .imperial ? "lbs" : "kg"

        if absValue == absValue.rounded() {
            return "\(sign)\(Int(absValue)) \(unit)"
        }
        return "\(sign)\(String(format: "%.1f", absValue)) \(unit)"
    }

    private func formatSignedPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        return "\(sign)\(String(format: "%.1f", abs(value)))%"
    }

    private func formatSimpleNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private func formatWeight(_ kg: Double) -> String {
        let value = unitPreference == .imperial ? UnitConversion.kgToLbs(kg) : kg
        let unit = unitPreference == .imperial ? "lbs" : "kg"
        if value == value.rounded() && value == Double(Int(value)) {
            return "\(Int(value)) \(unit)"
        }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(formatted) \(unit)"
    }
}
