// CalendarMonthView.swift
// Renders a single month: header, weekday labels, 7-column day grid.
// Spec: 008-calendar-tab, WP02 T006

import SwiftUI

struct CalendarMonthView: View {
    let month: Date
    let calendarDotData: [Date: [String]]
    let selectedDate: Date?
    let today: Date
    let onDateTapped: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            weekdayLabels
            dayGrid
        }
        .padding(.vertical, 8)
    }

    // MARK: - Weekday Labels

    private var weekdayLabels: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day Grid

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            // Leading empty cells for weekday offset
            ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                Color.clear.frame(height: 40)
            }

            // Day cells
            ForEach(daysInMonth, id: \.self) { date in
                CalendarDayCell(
                    date: date,
                    muscleGroups: calendarDotData[CalendarViewModel.normalizeDate(date)] ?? [],
                    isToday: calendar.isDate(date, inSameDayAs: today),
                    isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false,
                    onTapped: { onDateTapped(date) }
                )
            }
        }
    }

    // MARK: - Date Helpers

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private var monthYearString: String {
        Self.monthYearFormatter.string(from: month)
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday - 1
        return Array(symbols[firstWeekday...]) + Array(symbols[..<firstWeekday])
    }

    private var firstWeekdayOffset: Int {
        let weekday = calendar.component(.weekday, from: month)
        let offset = weekday - calendar.firstWeekday
        return offset >= 0 ? offset : offset + 7
    }

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { day in
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = day
            return calendar.date(from: components)
        }
    }
}
