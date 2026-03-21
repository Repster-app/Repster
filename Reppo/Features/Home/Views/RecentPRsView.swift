// RecentPRsView.swift
// Shows the latest personal records across all exercises.

import SwiftUI

struct RecentPR: Identifiable {
    let id: UUID
    let exerciseName: String
    let weight: Double
    let reps: Int
    let date: Date
}

struct RecentPRsView: View {
    let prs: [RecentPR]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT PRS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            ForEach(prs) { pr in
                prCard(pr)
            }
        }
    }

    private func prCard(_ pr: RecentPR) -> some View {
        HStack(spacing: 12) {
            // Trophy icon
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

    private func formattedWeight(_ weight: Double) -> String {
        if weight == weight.rounded() {
            return "\(Int(weight))kg"
        }
        return String(format: "%.1fkg", weight)
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
