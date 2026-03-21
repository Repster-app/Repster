// TrendingExercisesView.swift
// Shows exercises with the highest positive e1RM trend.

import SwiftUI

struct TrendingExercise: Identifiable {
    let id: UUID
    let exerciseName: String
    let trendPercent: Double
}

struct TrendingExercisesView: View {
    let exercises: [TrendingExercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRENDING UP")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            ForEach(exercises) { exercise in
                trendCard(exercise)
            }
        }
    }

    private func trendCard(_ exercise: TrendingExercise) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.success.opacity(0.08))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.success)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exerciseName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("e1RM up \(String(format: "%.1f", exercise.trendPercent))% this month")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.success)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}
