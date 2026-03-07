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
        if let data, !data.suggestions.isEmpty, !isLoading {
            VStack(alignment: .leading, spacing: 10) {
                Text("WEIGHT SUGGESTIONS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .kerning(0.8)

                WeightSuggestionCardView(
                    data: data,
                    unitPreference: unitPreference
                )
            }
        }
    }
}
