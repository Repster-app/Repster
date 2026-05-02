// WeekStripView.swift
// Compact 7-day calendar strip with individual day cards matching reference design.
// Each day is a rounded rectangle card. Today gets accent-fill.
// Up to 3 colored muscle group dots below each day with a workout.
// Tapping a day calls onDayTap for calendar navigation.
// Spec: 013-home-screen, WP03 T012

import SwiftUI

struct WeekStripView: View {
    let weekDays: [WeekDay]
    var onDayTap: ((Date) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(weekDays) { day in
                dayCard(day)
                    .onTapGesture {
                        onDayTap?(day.date)
                    }
            }
        }
    }

    private func dayCard(_ day: WeekDay) -> some View {
        VStack(spacing: 6) {
            // Card with abbreviation + number
            VStack(spacing: 4) {
                Text(day.abbreviation)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(day.isToday ? .white.opacity(0.85) : Color.textTertiary)
                    .kerning(0.3)

                Text("\(day.dateNumber)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(day.isToday ? .white : Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(day.isToday ? Color.accent : Color.bgCard)
            )

            // Muscle group dots (up to 3 colored dots) or single clear dot for spacing
            HStack(spacing: 3) {
                if day.muscleGroups.isEmpty {
                    Circle()
                        .fill(day.hasWorkout ? Color.success : Color.clear)
                        .frame(width: 5, height: 5)
                } else {
                    ForEach(day.muscleGroups.prefix(3), id: \.self) { muscle in
                        Circle()
                            .fill(MuscleGroupColors.color(for: muscle))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .frame(height: 5)
        }
    }
}
