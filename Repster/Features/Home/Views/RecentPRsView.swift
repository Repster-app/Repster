// RecentPRsView.swift
// Shows the latest personal records across all exercises.

import SwiftUI

struct RecentPR: Identifiable {
    let id: UUID
    let exerciseName: String
    let weight: Double
    let reps: Int
    let date: Date
    let isPerSide: Bool
}

struct RecentPRsView: View {
    let prs: [RecentPR]
    let unitPreference: UnitPreference
    var displayMode: PRDisplayMode = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT PRS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            switch displayMode {
            case .standard:
                ForEach(prs) { pr in
                    prCard(pr)
                }
            case .compact:
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(prs) { pr in
                        compactPRCard(pr)
                    }
                }
            }
        }
    }

    // MARK: - Standard Card (full-width)

    private func prCard(_ pr: RecentPR) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gold.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.gold)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(pr.exerciseName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(formattedWeight(pr.weight)) x \(pr.reps) reps")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)

                if pr.isPerSide {
                    Text("Per side")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            Text(relativeDate(pr.date))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(12)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Compact Card (half-width, 2-column grid)

    private func compactPRCard(_ pr: RecentPR) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.gold)
                Text(pr.exerciseName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }

            Text("\(formattedWeight(pr.weight)) x \(pr.reps) reps")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 4) {
                Text(relativeDate(pr.date))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                if pr.isPerSide {
                    Text("· Per side")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }

    // MARK: - Helpers

    private func formattedWeight(_ weight: Double) -> String {
        UnitConversion.formatWeightLabel(weight, unitPreference: unitPreference)
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let startOfDate = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days) days ago"
    }
}
