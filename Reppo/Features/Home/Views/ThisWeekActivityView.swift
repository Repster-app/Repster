// ThisWeekActivityView.swift
// Weekly activity bar chart with session counter.
// Spec: 013-home-screen, WP03 T015

import SwiftUI

struct ThisWeekActivityView: View {
    let workoutCount: Int
    let workoutDays: Set<Int>  // 0=Mon..6=Sun
    let weeklyGoal: Int

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header (outside card)
            Text("THIS WEEK")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            VStack(spacing: 12) {
                // Bar chart
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(workoutDays.contains(index) ? Color.accent : Color.bgSubtle)
                                .frame(height: 32)

                            Text(dayLabels[index])
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isToday(index) ? Color.accent : Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                // Session counter
                HStack(spacing: 4) {
                    Text("\(workoutCount)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accent)
                    Text("/ \(weeklyGoal) sessions")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(14)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
    }

    private func isToday(_ index: Int) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let todayIndex = (weekday + 5) % 7  // Mon=0..Sun=6
        return index == todayIndex
    }
}
