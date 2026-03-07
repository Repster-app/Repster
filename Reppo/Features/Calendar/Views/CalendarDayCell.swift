// CalendarDayCell.swift
// Individual calendar day cell with number, today/selection state, muscle group dots.
// Spec: 008-calendar-tab, WP02 T007

import SwiftUI

struct CalendarDayCell: View {
    let date: Date
    let muscleGroups: [String]
    let isToday: Bool
    let isSelected: Bool
    let onTapped: () -> Void

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    var body: some View {
        VStack(spacing: 2) {
            dayNumberView
            dotsView
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTapped() }
    }

    // MARK: - Day Number

    @ViewBuilder
    private var dayNumberView: some View {
        if isToday {
            Text("\(dayNumber)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accent))
        } else if isSelected {
            Text("\(dayNumber)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().stroke(Color.accent, lineWidth: 1.5))
        } else {
            Text("\(dayNumber)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 30, height: 30)
        }
    }

    // MARK: - Dots

    @ViewBuilder
    private var dotsView: some View {
        if muscleGroups.isEmpty {
            Color.clear.frame(height: 8)
        } else {
            HStack(spacing: 2) {
                ForEach(muscleGroups.prefix(3), id: \.self) { group in
                    MuscleGroupDot(muscleGroup: group)
                }
                if muscleGroups.count > 3 {
                    Text("+\(muscleGroups.count - 3)")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }
}
