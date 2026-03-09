// WeightSuggestionCardView.swift
// Card displaying per-set weight suggestions with brief context.
// Follows the card styling pattern from E1RMCardView (bgCard, cornerRadius 14, padding 14).

import SwiftUI

struct WeightSuggestionCardView: View {
    let data: WeightSuggestionData
    let unitPreference: UnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach(data.suggestions) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Header

    private var header: some View {
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
    }

    // MARK: - Suggestion Row

    private func suggestionRow(_ suggestion: SetSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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

            Text(suggestion.contextLabel)
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Formatting

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
