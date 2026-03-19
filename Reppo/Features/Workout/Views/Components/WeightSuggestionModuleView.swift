// WeightSuggestionModuleView.swift
// Section container for weight suggestion cards.
// Sits between SetTableView and ExerciseInfoSectionView in the Sets sub-tab.
// Follows the section pattern from ExerciseInfoSectionView.

import SwiftUI

struct WeightSuggestionModuleView: View {
    let data: WeightSuggestionData?
    let unitPreference: UnitPreference
    let isLoading: Bool

    var body: some View {
        if let data, !isLoading {
            if !data.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel

                    WeightSuggestionCardView(
                        data: data,
                        unitPreference: unitPreference
                    )
                }
            } else if let reason = data.unavailableReason, reason != .featureDisabled {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel
                    unavailableCard(for: reason)
                }
            }
        }
    }

    private var sectionLabel: some View {
        Text("WEIGHT SUGGESTIONS")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textTertiary)
            .kerning(0.8)
    }

    private func unavailableCard(for reason: SuggestionUnavailableReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Color.bg.opacity(0.55))
                    .cornerRadius(6)

                Text(reason.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Text(reason.message)
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}
