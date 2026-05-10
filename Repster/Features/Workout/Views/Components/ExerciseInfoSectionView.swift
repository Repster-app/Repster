// ExerciseInfoSectionView.swift
// Container view that arranges Exercise Info cards with section header.
// Feature: 014-exercise-info-active-workout, WP02-T007

import SwiftUI

struct ExerciseInfoSectionView: View {
    let data: ExerciseInfoData?
    let unitPreference: UnitPreference
    let isLoading: Bool

    var body: some View {
        if let data, !isLoading, hasVisibleCards(data) {
            VStack(alignment: .leading, spacing: 10) {
                // Section header
                Text("EXERCISE INFO")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .kerning(0.8)

                // Cards
                VStack(spacing: 12) {
                    // Hero card (e1RM)
                    if let e1RMInfo = data.e1RMInfo {
                        E1RMCardView(info: e1RMInfo, unitPreference: unitPreference)
                    }

                    // Compact cards row
                    compactCardsRow(data: data)
                }
            }
        }
    }

    // MARK: - Compact Cards

    @ViewBuilder
    private func compactCardsRow(data: ExerciseInfoData) -> some View {
        let hasLastWorkout = data.lastWorkoutInfo != nil
        let hasEstReps = data.estimatedRepsInfo != nil

        if hasLastWorkout || hasEstReps {
            HStack(spacing: 12) {
                if let lastWorkoutInfo = data.lastWorkoutInfo {
                    LastWorkoutCardView(
                        info: lastWorkoutInfo,
                        unitPreference: unitPreference,
                        isFullWidth: data.e1RMInfo == nil && !hasEstReps
                    )
                }
                if let estimatedRepsInfo = data.estimatedRepsInfo {
                    EstimatedRepsCardView(
                        info: estimatedRepsInfo,
                        unitPreference: unitPreference
                    )
                }
            }
        }
    }

    // MARK: - Visibility

    private func hasVisibleCards(_ data: ExerciseInfoData) -> Bool {
        data.e1RMInfo != nil || data.lastWorkoutInfo != nil || data.estimatedRepsInfo != nil
    }
}

// MARK: - Previews

#Preview("All Cards") {
    ZStack {
        Color.bg.ignoresSafeArea()
        ExerciseInfoSectionView(
            data: ExerciseInfoData(
                e1RMInfo: E1RMInfo(
                    currentE1RM: 105.5,
                    bestSetWeight: 85,
                    bestSetReps: 8,
                    historicalE1RM: 103.2,
                    historicalWeeksAgo: 4,
                    delta: 2.3,
                    trend: .positive
                ),
                lastWorkoutInfo: LastWorkoutInfo(
                    topSets: [
                        TopSet(weight: 85, reps: 8, durationSeconds: nil, distanceMeters: nil, formattedLabel: "85×8"),
                        TopSet(weight: 80, reps: 8, durationSeconds: nil, distanceMeters: nil, formattedLabel: "80×8")
                    ],
                    daysAgo: 9,
                    relativeTimeLabel: "9 days ago"
                ),
                estimatedRepsInfo: EstimatedRepsInfo(
                    targetReps: 8,
                    estimatedWeight: 85,
                    sourceLabel: "Based on recent data"
                ),
                trackingType: .weightReps
            ),
            unitPreference: .metric,
            isLoading: false
        )
        .padding(.horizontal, 20)
    }
}

#Preview("Duration + Distance Exercise") {
    ZStack {
        Color.bg.ignoresSafeArea()
        ExerciseInfoSectionView(
            data: ExerciseInfoData(
                e1RMInfo: nil,
                lastWorkoutInfo: LastWorkoutInfo(
                    topSets: [
                        TopSet(weight: 0, reps: nil, durationSeconds: 150, distanceMeters: 400, formattedLabel: "2m 30s • \(UnitConversion.formatDistanceLabel(400, unitPreference: .metric))")
                    ],
                    daysAgo: 3,
                    relativeTimeLabel: "3 days ago"
                ),
                estimatedRepsInfo: nil,
                trackingType: .durationDistance
            ),
            unitPreference: .metric,
            isLoading: false
        )
        .padding(.horizontal, 20)
    }
}

#Preview("No Data") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Text("Nothing should render below:")
                .foregroundStyle(Color.textSecondary)
            ExerciseInfoSectionView(
                data: nil,
                unitPreference: .metric,
                isLoading: false
            )
            Text("(End)")
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 20)
    }
}

#Preview("Loading") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Text("Nothing should render below:")
                .foregroundStyle(Color.textSecondary)
            ExerciseInfoSectionView(
                data: ExerciseInfoData(
                    e1RMInfo: E1RMInfo(
                        currentE1RM: 100,
                        bestSetWeight: 80,
                        bestSetReps: 8,
                        historicalE1RM: nil,
                        historicalWeeksAgo: nil,
                        delta: nil,
                        trend: nil
                    ),
                    lastWorkoutInfo: nil,
                    estimatedRepsInfo: nil,
                    trackingType: .weightReps
                ),
                unitPreference: .metric,
                isLoading: true
            )
            Text("(End)")
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 20)
    }
}
