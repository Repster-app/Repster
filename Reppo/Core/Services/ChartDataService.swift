// ChartDataService.swift
// Central service actor for chart data aggregation.
// Spec: FR-009
// Feature: 009-charts-tab WP01

import Foundation
import SwiftUI

protocol ChartDataServiceProtocol: Sendable {

    // MARK: - Breakdown Tab (WP06)
    func fetchBreakdownData(metric: BreakdownMetric, timeRange: BreakdownTimeRange) async throws -> [BreakdownDataPoint]
    func fetchBreakdownSummary(timeRange: BreakdownTimeRange) async throws -> BreakdownSummary

    // MARK: - Workouts Tab (WP07)
    func fetchWorkoutsTimeSeries(metric: WorkoutsMetric, aggregation: WorkoutsAggregation, filter: WorkoutsFilter, timeRange: WorkoutsTimeRange) async throws -> [WorkoutsTimeSeriesPoint]
    func fetchAvailableCategories() async throws -> [String]
    func fetchPerformedExercises() async throws -> [(id: UUID, name: String)]

    // MARK: - Exercises Tab (WP08)
    func fetchExerciseProgress(metric: ExerciseMetric, exerciseIds: [UUID], timeRange: WorkoutsTimeRange) async throws -> [ExerciseProgressSeries]

    // MARK: - Helpers
    func fetchEarliestWorkoutDate() async throws -> Date?
}

actor ChartDataService: ChartDataServiceProtocol {

    // MARK: - Dependencies

    private let setRepository: any SetRepositoryProtocol
    private let workoutRepository: any WorkoutRepositoryProtocol
    private let exerciseRepository: any ExerciseRepositoryProtocol
    private let exerciseStatsRepository: any ExerciseStatsRepositoryProtocol
    private let performanceRecordRepository: any PerformanceRecordRepositoryProtocol

    init(
        setRepository: any SetRepositoryProtocol,
        workoutRepository: any WorkoutRepositoryProtocol,
        exerciseRepository: any ExerciseRepositoryProtocol,
        exerciseStatsRepository: any ExerciseStatsRepositoryProtocol,
        performanceRecordRepository: any PerformanceRecordRepositoryProtocol
    ) {
        self.setRepository = setRepository
        self.workoutRepository = workoutRepository
        self.exerciseRepository = exerciseRepository
        self.exerciseStatsRepository = exerciseStatsRepository
        self.performanceRecordRepository = performanceRecordRepository
    }

    // MARK: - Shared Helpers

    /// Canonical filter for sets eligible for chart aggregation.
    /// Applied post-fetch since hasData is a computed property.
    private nonisolated func chartEligibleSets(_ sets: [ChartSetData]) -> [ChartSetData] {
        sets.filter { $0.hasData && $0.setType != .warmup && $0.setType != .partial }
    }

    private func fetchExerciseLookup() async throws -> [UUID: ChartExerciseData] {
        let exercises = try await exerciseRepository.fetchAllChartExercises()
        return Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
    }

    private nonisolated func normalizedMuscleGroup(_ rawValue: String?) -> String? {
        ExercisePrimaryGroup.normalizedValue(rawValue)
    }

    private nonisolated func displayedMuscleGroup(_ rawValue: String?) -> String {
        ExercisePrimaryGroup.displayName(for: normalizedMuscleGroup(rawValue) ?? "other")
    }

    // MARK: - Breakdown Tab (016-charts-tab-v2 WP06, T113)

    func fetchBreakdownData(metric: BreakdownMetric, timeRange: BreakdownTimeRange) async throws -> [BreakdownDataPoint] {
        let startDate = timeRange.startDate ?? Date.distantPast
        let endDate = Date()
        let allSets = try await setRepository.fetchChartSets(from: startDate, to: endDate)
        let eligible = chartEligibleSets(allSets)

        guard !eligible.isEmpty else { return [] }

        let exerciseCache = try await fetchExerciseLookup()

        // Group by category or exercise
        var grouped: [String: [ChartSetData]] = [:]
        for set in eligible {
            guard let exercise = exerciseCache[set.exerciseId] else { continue }
            let key: String
            switch metric.groupBy {
            case .category:
                key = displayedMuscleGroup(exercise.primaryMuscle)
            case .exercise:
                key = exercise.name
            }
            grouped[key, default: []].append(set)
        }

        // Aggregate per group
        var results: [(label: String, value: Double)] = []
        for (label, sets) in grouped {
            let value: Double
            switch metric.aggregateType {
            case .volume:
                value = sets.reduce(0) { $0 + (($1.effectiveWeight ?? 0) * Double($1.totalReps)) }
            case .sets:
                value = Double(sets.count)
            case .reps:
                value = sets.reduce(0) { $0 + Double($1.totalReps) }
            case .workouts:
                value = Double(Swift.Set(sets.map { $0.workoutId }).count)
            }
            if value > 0 {
                results.append((label: label, value: value))
            }
        }

        results.sort { $0.value > $1.value }

        // Cap at max 8 segments (top 7 + "Other" bucket)
        let palette = Color.chartPalette
        if results.count > 8 {
            let top7 = results.prefix(7)
            let otherValue = results.dropFirst(7).reduce(0) { $0 + $1.value }
            var points = top7.enumerated().map { i, r in
                BreakdownDataPoint(label: r.label, value: r.value, color: palette[i % palette.count])
            }
            points.append(BreakdownDataPoint(label: "Other", value: otherValue, color: Color.textTertiary))
            return points
        } else {
            return results.enumerated().map { i, r in
                BreakdownDataPoint(label: r.label, value: r.value, color: palette[i % palette.count])
            }
        }
    }

    func fetchBreakdownSummary(timeRange: BreakdownTimeRange) async throws -> BreakdownSummary {
        let startDate = timeRange.startDate ?? Date.distantPast
        let endDate = Date()
        let allSets = try await setRepository.fetchChartSets(from: startDate, to: endDate)
        let eligible = chartEligibleSets(allSets)

        let totalVolume = eligible.reduce(0.0) { $0 + (($1.effectiveWeight ?? 0) * Double($1.totalReps)) }
        let totalSets = eligible.count
        let totalReps = eligible.reduce(0) { $0 + $1.totalReps }
        let totalWorkouts = Swift.Set(eligible.map { $0.workoutId }).count

        return BreakdownSummary(
            totalVolume: totalVolume,
            totalSets: totalSets,
            totalReps: totalReps,
            totalWorkouts: totalWorkouts
        )
    }

    // MARK: - Workouts Tab (016-charts-tab-v2 WP07, T118)

    func fetchWorkoutsTimeSeries(
        metric: WorkoutsMetric,
        aggregation: WorkoutsAggregation,
        filter: WorkoutsFilter,
        timeRange: WorkoutsTimeRange
    ) async throws -> [WorkoutsTimeSeriesPoint] {
        let startDate = timeRange.startDate ?? Date.distantPast
        let endDate = Date()

        // 1. Fetch and filter sets
        var allSets: [ChartSetData]
        switch filter {
        case .all:
            allSets = try await setRepository.fetchChartSets(from: startDate, to: endDate)
        case .exercise(let id, _):
            allSets = try await setRepository.fetchChartSets(exerciseId: id, from: startDate, to: endDate)
        case .category(let categoryName):
            allSets = try await setRepository.fetchChartSets(from: startDate, to: endDate)
            let cache = try await fetchExerciseLookup()
            allSets = allSets.filter { set in
                guard let ex = cache[set.exerciseId] else { return false }
                return normalizedMuscleGroup(ex.primaryMuscle) == normalizedMuscleGroup(categoryName)
            }
        }

        let eligible = chartEligibleSets(allSets)
        guard !eligible.isEmpty else { return [] }

        let calendar = Calendar.current

        // 2. Bucket by aggregation
        switch aggregation {
        case .perWorkout:
            return computePerWorkout(eligible: eligible, metric: metric)
        case .perWeek:
            return computePeriodic(eligible: eligible, metric: metric, calendar: calendar,
                                   startDate: startDate, endDate: endDate, component: .weekOfYear)
        case .perMonth:
            return computePeriodic(eligible: eligible, metric: metric, calendar: calendar,
                                   startDate: startDate, endDate: endDate, component: .month)
        case .perYear:
            return computePeriodic(eligible: eligible, metric: metric, calendar: calendar,
                                   startDate: startDate, endDate: endDate, component: .year)
        }
    }

    // MARK: - Workouts Tab Helpers

    private func computePerWorkout(eligible: [ChartSetData], metric: WorkoutsMetric) -> [WorkoutsTimeSeriesPoint] {
        let grouped = Dictionary(grouping: eligible) { $0.workoutId }
        var results: [WorkoutsTimeSeriesPoint] = []

        for (workoutId, workoutSets) in grouped {
            guard let date = workoutSets.first?.date else { continue }
            let value = computeWorkoutsMetric(metric, for: workoutSets)
            results.append(WorkoutsTimeSeriesPoint(date: date, value: value, label: nil, workoutId: workoutId))
        }

        return results.sorted { $0.date < $1.date }
    }

    private func computePeriodic(
        eligible: [ChartSetData],
        metric: WorkoutsMetric,
        calendar: Calendar,
        startDate: Date,
        endDate: Date,
        component: Calendar.Component
    ) -> [WorkoutsTimeSeriesPoint] {
        // Group sets by period start date
        let grouped = Dictionary(grouping: eligible) { set -> Date in
            periodStart(for: set.date, component: component, calendar: calendar)
        }

        // Compute metric per period
        var valueByPeriod: [Date: Double] = [:]
        for (periodDate, sets) in grouped {
            valueByPeriod[periodDate] = computeWorkoutsMetric(metric, for: sets)
        }

        // Zero-fill empty periods
        var result: [WorkoutsTimeSeriesPoint] = []
        let effectiveStart = startDate == Date.distantPast
            ? (eligible.map { $0.date }.min() ?? endDate)
            : startDate
        var current = periodStart(for: effectiveStart, component: component, calendar: calendar)
        let endPeriod = periodStart(for: endDate, component: component, calendar: calendar)

        while current <= endPeriod {
            result.append(WorkoutsTimeSeriesPoint(
                date: current,
                value: valueByPeriod[current] ?? 0,
                label: nil,
                workoutId: nil
            ))
            guard let next = calendar.date(byAdding: component, value: 1, to: current) else { break }
            current = next
        }

        return result
    }

    private func periodStart(for date: Date, component: Calendar.Component, calendar: Calendar) -> Date {
        switch component {
        case .weekOfYear:
            return calendar.startOfDay(for: calendar.dateInterval(of: .weekOfYear, for: date)!.start)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: comps) ?? date
        case .year:
            let comps = calendar.dateComponents([.year], from: date)
            return calendar.date(from: comps) ?? date
        default:
            return calendar.startOfDay(for: date)
        }
    }

    private func computeWorkoutsMetric(_ metric: WorkoutsMetric, for sets: [ChartSetData]) -> Double {
        switch metric {
        case .volume:
            return sets.reduce(0) { $0 + (($1.effectiveWeight ?? 0) * Double($1.totalReps)) }
        case .sets:
            return Double(sets.count)
        case .reps:
            return sets.reduce(0) { $0 + Double($1.totalReps) }
        case .workouts:
            return Double(Swift.Set(sets.map { $0.workoutId }).count)
        case .distance:
            return sets.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
        case .time:
            return sets.reduce(0) { $0 + Double($1.durationSeconds ?? 0) } / 60.0 // Convert to minutes
        }
    }

    // MARK: - Filter Dropdown Data (WP07, T122)

    func fetchAvailableCategories() async throws -> [String] {
        let allExercises = try await exerciseRepository.fetchAllChartExercises()
        let orderedValues = ExerciseMuscleGroupCatalog.orderedValues(
            from: allExercises.compactMap(\.primaryMuscle)
        )
        return orderedValues.map { ExercisePrimaryGroup.displayName(for: $0) }
    }

    func fetchPerformedExercises() async throws -> [(id: UUID, name: String)] {
        let exerciseLookup = try await fetchExerciseLookup()
        let allStats = try await exerciseStatsRepository.fetchAllChartExerciseStats()
        let performedIds = Swift.Set(
            allStats.compactMap { $0.lastPerformedDate == nil ? nil : $0.exerciseId }
        )
        let result = exerciseLookup.values
            .filter { performedIds.contains($0.id) }
            .map { (id: $0.id, name: $0.name) }
        return result.sorted { $0.name < $1.name }
    }

    // MARK: - Exercises Tab (016-charts-tab-v2 WP08, T124)

    func fetchExerciseProgress(
        metric: ExerciseMetric,
        exerciseIds: [UUID],
        timeRange: WorkoutsTimeRange
    ) async throws -> [ExerciseProgressSeries] {
        let startDate = timeRange.startDate
        let endDate = Date()
        let exerciseLookup = try await fetchExerciseLookup()

        return try await withThrowingTaskGroup(
            of: (Int, ExerciseProgressSeries?).self
        ) { group in
            for (index, exerciseId) in exerciseIds.enumerated() {
                guard let exercise = exerciseLookup[exerciseId] else { continue }
                group.addTask { [self] in
                    let sets = try await self.setRepository.fetchChartSets(
                        exerciseId: exerciseId, from: startDate, to: endDate
                    )
                    let eligible = self.chartEligibleSets(sets)
                    guard !eligible.isEmpty else { return (index, nil) }

                    let grouped = Dictionary(grouping: eligible) { $0.workoutId }
                    var points: [ExerciseProgressPoint] = []

                    for (workoutId, workoutSets) in grouped {
                        guard let date = workoutSets.first?.date else { continue }
                        let value = self.computeExerciseMetric(metric, for: workoutSets)
                        if let value, value > 0 {
                            // Extract top weight x reps from the best set for display
                            let bestSet = self.bestSetForDisplay(metric: metric, sets: workoutSets)
                            points.append(ExerciseProgressPoint(
                                date: date,
                                value: value,
                                workoutId: workoutId,
                                topWeight: bestSet?.effectiveWeight,
                                topReps: bestSet?.prReps,
                                detailLabel: bestSet.flatMap {
                                    WorkoutSetPerformanceFormatter.performanceLabel(for: $0, exercise: exercise)
                                }
                            ))
                        }
                    }

                    points.sort { $0.date < $1.date }
                    guard !points.isEmpty else { return (index, nil) }

                    let palette = Color.chartPalette
                    let color = palette[index % palette.count]
                    return (index, ExerciseProgressSeries(
                        id: exerciseId, name: exercise.name,
                        color: color, points: points
                    ))
                }
            }

            var results: [(Int, ExerciseProgressSeries)] = []
            for try await (index, series) in group {
                if let series { results.append((index, series)) }
            }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: - Exercise Metric Computation (WP08, T124)

    private nonisolated func computeExerciseMetric(_ metric: ExerciseMetric, for sets: [ChartSetData]) -> Double? {
        switch metric {
        case .estimatedOneRM:
            return sets.compactMap { $0.e1RM }.filter { $0 > 0 }.max()
        case .maxWeight:
            return sets.compactMap { $0.effectiveWeight }.filter { $0 > 0 }.max()
        case .maxReps:
            return sets.map { Double($0.prReps) }.max()
        case .maxVolume:
            return sets.map { ($0.effectiveWeight ?? 0) * Double($0.totalReps) }.max()
        case .maxWeightForReps:
            return sets.compactMap { $0.effectiveWeight }.filter { $0 > 0 }.max()
        case .workoutVolume:
            let vol = sets.reduce(0.0) { $0 + (($1.effectiveWeight ?? 0) * Double($1.totalReps)) }
            return vol > 0 ? vol : nil
        case .workoutReps:
            let total = sets.reduce(0.0) { $0 + Double($1.totalReps) }
            return total > 0 ? total : nil
        case .personalRecords:
            return sets.filter { $0.cachedPRStatus == .current }.compactMap { $0.effectiveWeight }.max()
        case .maxDistance:
            return sets.compactMap { $0.distanceMeters }.filter { $0 > 0 }.max()
        case .maxTime:
            return sets.compactMap { $0.durationSeconds }.map { Double($0) }.max()
        case .minPace:
            let paces = sets.compactMap { set -> Double? in
                guard let dist = set.distanceMeters, dist > 0,
                      let dur = set.durationSeconds, dur > 0 else { return nil }
                return dist / Double(dur)
            }
            return paces.min()
        }
    }

    /// Find the "best" set for a given metric to extract display-friendly weight x reps.
    /// Returns the set that most likely contributed the metric value.
    private nonisolated func bestSetForDisplay(metric: ExerciseMetric, sets: [ChartSetData]) -> ChartSetData? {
        switch metric {
        case .estimatedOneRM:
            return sets.max(by: { ($0.e1RM ?? 0) < ($1.e1RM ?? 0) })
        case .maxWeight, .maxWeightForReps, .personalRecords:
            return sets.max(by: { ($0.effectiveWeight ?? 0) < ($1.effectiveWeight ?? 0) })
        case .maxReps:
            return sets.max(by: { $0.prReps < $1.prReps })
        case .maxVolume:
            return sets.max(by: {
                (($0.effectiveWeight ?? 0) * Double($0.totalReps)) <
                (($1.effectiveWeight ?? 0) * Double($1.totalReps))
            })
        case .workoutVolume, .workoutReps:
            // Aggregate metrics — show the heaviest set as representative
            return sets.max(by: { ($0.effectiveWeight ?? 0) < ($1.effectiveWeight ?? 0) })
        case .maxDistance, .maxTime, .minPace:
            // Non-weight metrics — no weight x reps to show
            return nil
        }
    }

    // MARK: - Helpers

    func fetchEarliestWorkoutDate() async throws -> Date? {
        try await workoutRepository.fetchEarliestCompletedWorkoutDate()
    }
}
