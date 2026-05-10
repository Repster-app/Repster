// LastWorkoutCardView.swift
// Compact card showing top working sets from the most recent previous session.
// Feature: 014-exercise-info-active-workout, WP02-T005

import SwiftUI

struct LastWorkoutCardView: View {
    let info: LastWorkoutInfo
    let unitPreference: UnitPreference
    let isFullWidth: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            header

            if info.topSets.isEmpty {
                Text("No previous data")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            } else {
                // Top sets value
                Text(formattedTopSets)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                // Relative time
                Text(info.relativeTimeLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
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
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14))
                .foregroundStyle(Color.accent)
                .frame(width: 22, height: 22)
                .background(Color.accent.opacity(0.08))
                .cornerRadius(6)

            Text("Last Workout")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Formatting

    private var formattedTopSets: String {
        info.topSets
            .map(\.formattedLabel)
            .joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview("Normal") {
    ZStack {
        Color.bg.ignoresSafeArea()
        LastWorkoutCardView(
            info: LastWorkoutInfo(
                topSets: [
                    TopSet(weight: 85, reps: 8, durationSeconds: nil, distanceMeters: nil, formattedLabel: "85×8"),
                    TopSet(weight: 80, reps: 8, durationSeconds: nil, distanceMeters: nil, formattedLabel: "80×8")
                ],
                daysAgo: 9,
                relativeTimeLabel: "9 days ago"
            ),
            unitPreference: .metric,
            isFullWidth: false
        )
        .frame(width: 180)
        .padding()
    }
}

#Preview("Full Width") {
    ZStack {
        Color.bg.ignoresSafeArea()
        LastWorkoutCardView(
            info: LastWorkoutInfo(
                topSets: [
                    TopSet(weight: 0, reps: nil, durationSeconds: 150, distanceMeters: 400, formattedLabel: "2m 30s • \(UnitConversion.formatDistanceLabel(400, unitPreference: .metric))"),
                    TopSet(weight: 0, reps: nil, durationSeconds: 120, distanceMeters: 300, formattedLabel: "2m • \(UnitConversion.formatDistanceLabel(300, unitPreference: .metric))")
                ],
                daysAgo: 3,
                relativeTimeLabel: "3 days ago"
            ),
            unitPreference: .metric,
            isFullWidth: true
        )
        .padding()
    }
}

#Preview("Empty") {
    ZStack {
        Color.bg.ignoresSafeArea()
        LastWorkoutCardView(
            info: LastWorkoutInfo(
                topSets: [],
                daysAgo: 0,
                relativeTimeLabel: ""
            ),
            unitPreference: .metric,
            isFullWidth: false
        )
        .frame(width: 180)
        .padding()
    }
}
