// CalendarView.swift
// Main calendar screen with single-month paging and workout detail below.
// Upper: month header + horizontally swipeable month grid.
// Lower: scrollable workout detail for selected date.
// Spec: 008-calendar-tab

import SwiftUI

struct CalendarView: View {

    @Environment(ServiceContainer.self) private var services
    @State private var viewModel: CalendarViewModel
    @State private var navigationPath = NavigationPath()
    @State private var workoutToSaveAsTemplate: Workout? = nil
    @State private var saveAsTemplateController = SaveWorkoutAsTemplateController()
    @State private var templateFeedback: TemplateSaveFeedback? = nil

    init(
        workoutService: WorkoutServiceProtocol,
        setService: SetServiceProtocol,
        exerciseService: ExerciseServiceProtocol,
        statsService: StatsServiceProtocol
    ) {
        _viewModel = State(initialValue: CalendarViewModel(
            workoutService: workoutService,
            setService: setService,
            exerciseService: exerciseService,
            statsService: statsService
        ))
    }

    // MARK: - Month Array

    /// Generates months from the earliest workout (or 24 months back) through 6 months into the future.
    private var months: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let startOfCurrentMonth = calendar.startOfMonth(for: today)

        let default24MonthsBack = calendar.date(byAdding: .month, value: -24, to: startOfCurrentMonth) ?? startOfCurrentMonth

        let earliestMonth: Date
        if let earliest = viewModel.earliestWorkoutDate {
            let earliestStart = calendar.startOfMonth(for: earliest)
            earliestMonth = min(earliestStart, default24MonthsBack)
        } else {
            earliestMonth = default24MonthsBack
        }

        let components = calendar.dateComponents([.month], from: earliestMonth, to: startOfCurrentMonth)
        let monthsBack = components.month ?? 24

        var result: [Date] = []
        for offset in (-monthsBack)...6 {
            if let month = calendar.date(byAdding: .month, value: offset, to: startOfCurrentMonth) {
                result.append(month)
            }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Month navigation header
                monthNavigationHeader
                    .padding(.top, 2)

                // Horizontally paged calendar month
                TabView(selection: $viewModel.currentMonth) {
                    ForEach(months, id: \.self) { month in
                        CalendarMonthView(
                            month: month,
                            calendarDotData: viewModel.calendarDotData,
                            selectedDate: viewModel.selectedDate,
                            today: Date(),
                            onDateTapped: { date in
                                Task { await viewModel.selectDate(date) }
                            }
                        )
                        .padding(.horizontal, 16)
                        .tag(month)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: monthGridHeight)

                // Divider
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)

                // Workout detail section
                detailSection
            }
            .background(Color.bg)
            .navigationBarHidden(true)
            .navigationDestination(for: UUID.self) { exerciseId in
                ExerciseDetailView(exerciseId: exerciseId, services: services)
            }
            .task {
                await viewModel.loadAllDots()
            }
            .saveWorkoutAsTemplatePrompt(
                controller: saveAsTemplateController,
                workoutId: workoutToSaveAsTemplate?.id,
                onSaved: { savedName in
                    templateFeedback = TemplateSaveFeedback(
                        title: "Template Saved",
                        message: "\"\(savedName)\" was created from this workout."
                    )
                },
                onError: { error in
                    templateFeedback = TemplateSaveFeedback(
                        title: "Save Failed",
                        message: error.localizedDescription
                    )
                }
            )
            .alert(item: $templateFeedback) { feedback in
                Alert(
                    title: Text(feedback.title),
                    message: Text(feedback.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Month Navigation Header

    private var monthNavigationHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.goToPreviousMonth()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(monthYearString(for: viewModel.currentMonth))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.goToNextMonth()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 44, height: 44)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.scrollToToday()
                }
            } label: {
                Text("Today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentSoft)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Detail Section

    @ViewBuilder
    private var detailSection: some View {
        ScrollView {
            if viewModel.isLoadingDetail {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            } else if let selectedDate = viewModel.selectedDate {
                CalendarWorkoutDetailView(
                    workoutDetails: viewModel.selectedDateWorkoutDetails,
                    selectedDate: selectedDate,
                    onSaveAsTemplate: { workout in
                        workoutToSaveAsTemplate = workout
                        saveAsTemplateController.begin(defaultName: workout.displayTitle)
                    },
                    onExerciseTapped: { exerciseId in
                        navigationPath.append(exerciseId)
                    }
                )
            } else {
                Text("Tap a date to see workout details")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    /// Dynamic height for the month grid: 6 rows of day cells + weekday labels + padding.
    /// This keeps the calendar compact and gives maximum space to the detail section.
    private var monthGridHeight: CGFloat {
        // Weekday labels (~20) + up to 6 rows of 40pt day cells + spacing
        let weekdayHeight: CGFloat = 20
        let rowHeight: CGFloat = 40
        let rowSpacing: CGFloat = 4
        let maxRows: CGFloat = 6
        let verticalPadding: CGFloat = 24
        return weekdayHeight + (maxRows * rowHeight) + ((maxRows - 1) * rowSpacing) + verticalPadding
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private func monthYearString(for date: Date) -> String {
        Self.monthYearFormatter.string(from: date)
    }
}
