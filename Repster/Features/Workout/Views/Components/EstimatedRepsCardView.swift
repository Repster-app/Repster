// EstimatedRepsCardView.swift
// Compact card showing estimated weight for the user's current rep target.
// Feature: 014-exercise-info-active-workout, WP02-T006

import SwiftUI

struct EstimatedRepsCardView: View {
    let info: EstimatedRepsInfo
    let unitPreference: UnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            header

            // Estimated weight value
            Text(formattedWeight)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // Source label
            Text(info.sourceLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 14))
                .foregroundStyle(Color.accent)
                .frame(width: 22, height: 22)
                .background(Color.accent.opacity(0.08))
                .cornerRadius(6)

            Text("Est. for \(info.targetReps) reps")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Formatting

    private var formattedWeight: String {
        UnitConversion.formatWeightLabel(info.estimatedWeight, unitPreference: unitPreference)
    }
}

// MARK: - Previews

#Preview("Normal") {
    ZStack {
        Color.bg.ignoresSafeArea()
        EstimatedRepsCardView(
            info: EstimatedRepsInfo(
                targetReps: 8,
                estimatedWeight: 85,
                sourceLabel: "Based on recent data"
            ),
            unitPreference: .metric
        )
        .frame(width: 180)
        .padding()
    }
}

#Preview("Decimal Weight") {
    ZStack {
        Color.bg.ignoresSafeArea()
        EstimatedRepsCardView(
            info: EstimatedRepsInfo(
                targetReps: 5,
                estimatedWeight: 92.5,
                sourceLabel: "Based on recent data"
            ),
            unitPreference: .metric
        )
        .frame(width: 180)
        .padding()
    }
}

#Preview("Imperial") {
    ZStack {
        Color.bg.ignoresSafeArea()
        EstimatedRepsCardView(
            info: EstimatedRepsInfo(
                targetReps: 10,
                estimatedWeight: 60,
                sourceLabel: "Based on recent data"
            ),
            unitPreference: .imperial
        )
        .frame(width: 180)
        .padding()
    }
}
