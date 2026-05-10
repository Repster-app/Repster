// MonthlyStatsCardView.swift
// Compact card showing this month's workout totals.

import SwiftUI

struct MonthlyStatsCardView: View {
    let totalWorkouts: Int
    let primaryMetric: WorkoutPrimaryMetric?
    let totalSets: Int
    let unitPreference: UnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THIS MONTH")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            HStack(spacing: 8) {
                statCell(value: "\(totalWorkouts)", label: "Workouts")
                if let primaryMetric {
                    statCell(
                        value: primaryMetric.formattedValue(unitPreference: unitPreference),
                        label: primaryMetric.label
                    )
                }
                statCell(value: "\(totalSets)", label: "Sets")
            }
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.5)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.bgSubtle)
        .cornerRadius(10)
    }
}
