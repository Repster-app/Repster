// ExerciseInfoProvider.swift
// Computation engine for Exercise Info section — derives all card models from a single data fetch
// Feature: 014-exercise-info-active-workout, WP01-T003

import Foundation

enum ExerciseInfoProvider {

    static func compute(
        currentSets: [WorkoutSet],
        exerciseId: UUID,
        currentWorkoutId: UUID,
        trackingType: TrackingType,
        weightIncrement: Double?,
        setService: any SetServiceProtocol,
        statsService: any StatsServiceProtocol,
        healthProfileRepo: any HealthProfileRepositoryProtocol
    ) async throws -> ExerciseInfoData {

        // Step 1: Fetch and prepare data — single DB query for all computation
        let allSets = try await setService.fetchSets(for: exerciseId, limit: nil)
        let historicalSets = allSets.filter { $0.workoutId != currentWorkoutId }
        let profile = try await healthProfileRepo.fetchOrCreate()
        let formula = E1RMFormula(rawValue: profile.e1RMFormula) ?? .epley

        // Step 2: Determine tracking type visibility
        let supportsE1RM = trackingType == .weightReps || trackingType == .weightRepsDuration

        // Step 3: Compute E1RM info
        let (e1RMInfo, bestAvailableE1RM) = supportsE1RM
            ? try await computeE1RM(
                currentSets: currentSets,
                historicalSets: historicalSets,
                exerciseId: exerciseId,
                statsService: statsService
            )
            : (nil, nil)

        // Step 4: Compute Last Workout info
        let lastWorkoutInfo = computeLastWorkout(historicalSets: historicalSets)

        // Step 5: Compute Estimated Reps info
        let estimatedRepsInfo: EstimatedRepsInfo?
        if supportsE1RM, let bestE1RM = bestAvailableE1RM, bestE1RM > 0 {
            let targetReps = currentSets
                .last(where: { $0.setType == .working && $0.hasData })?.reps ?? 8

            let rawEstimated = formula.reverseCalculate(e1RM: bestE1RM, reps: targetReps)
            let snapped = snap(rawEstimated, to: weightIncrement ?? 2.5)

            estimatedRepsInfo = EstimatedRepsInfo(
                targetReps: targetReps,
                estimatedWeight: snapped,
                sourceLabel: "Based on recent data"
            )
        } else {
            estimatedRepsInfo = nil
        }

        // Step 6: Assemble and return
        return ExerciseInfoData(
            e1RMInfo: e1RMInfo,
            lastWorkoutInfo: lastWorkoutInfo,
            estimatedRepsInfo: estimatedRepsInfo,
            trackingType: trackingType
        )
    }

    // MARK: - E1RM Computation

    private static func computeE1RM(
        currentSets: [WorkoutSet],
        historicalSets: [WorkoutSet],
        exerciseId: UUID,
        statsService: any StatsServiceProtocol
    ) async throws -> (E1RMInfo?, Double?) {
        // Find best e1RM from current session working sets
        let currentWorkingSets = currentSets.filter {
            $0.setType == .working && $0.hasData && $0.e1RM != nil
        }
        let bestToday = currentWorkingSets.max(by: { ($0.e1RM ?? 0) < ($1.e1RM ?? 0) })

        var currentE1RM = bestToday?.e1RM
        var bestSetWeight = bestToday?.effectiveWeight ?? 0
        var bestSetReps = bestToday?.reps ?? 0

        // Fallback to ExerciseStats
        if currentE1RM == nil {
            let stats = try await statsService.fetchStats(for: exerciseId)
            if let statsE1RM = stats?.bestE1RM, statsE1RM > 0 {
                currentE1RM = statsE1RM
                bestSetWeight = stats?.maxWeight ?? 0
                bestSetReps = 0
            }
        }

        guard let currentE1RM else { return (nil, nil) }

        // Historical comparison — target ~4 weeks ago with ±7 day window
        let now = Date()
        let calendar = Calendar.current
        let targetDate = calendar.date(byAdding: .day, value: -28, to: now)!
        let windowStart = calendar.date(byAdding: .day, value: -7, to: targetDate)!
        let windowEnd = calendar.date(byAdding: .day, value: 7, to: targetDate)!

        let windowSets = historicalSets.filter { set in
            set.setType == .working && set.hasData && set.e1RM != nil
                && set.date >= windowStart && set.date <= windowEnd
        }

        var historicalE1RM: Double?
        var historicalDate: Date?

        if let bestWindowSet = windowSets.max(by: { ($0.e1RM ?? 0) < ($1.e1RM ?? 0) }) {
            historicalE1RM = bestWindowSet.e1RM
            historicalDate = bestWindowSet.date
        } else {
            // Fallback: nearest available historical e1RM
            let nearest = historicalSets
                .filter { $0.setType == .working && $0.hasData && $0.e1RM != nil }
                .sorted { $0.date > $1.date }
                .first

            historicalE1RM = nearest?.e1RM
            historicalDate = nearest?.date
        }

        var delta: Double?
        var trend: Trend?
        var historicalWeeksAgo: Int?

        if let historicalE1RM, let historicalDate {
            let deltaGrams = UnitConversion.toGrams(currentE1RM) - UnitConversion.toGrams(historicalE1RM)
            delta = Double(deltaGrams) / 1000.0
            trend = deltaGrams > 0 ? .positive : deltaGrams < 0 ? .negative : .neutral
            historicalWeeksAgo = calendar.dateComponents([.weekOfYear], from: historicalDate, to: now).weekOfYear ?? 4
        }

        let info = E1RMInfo(
            currentE1RM: currentE1RM,
            bestSetWeight: bestSetWeight,
            bestSetReps: bestSetReps,
            historicalE1RM: historicalE1RM,
            historicalWeeksAgo: historicalWeeksAgo,
            delta: delta,
            trend: trend
        )

        return (info, currentE1RM)
    }

    // MARK: - Last Workout Computation

    private static func computeLastWorkout(historicalSets: [WorkoutSet]) -> LastWorkoutInfo? {
        let grouped = Dictionary(grouping: historicalSets) { $0.workoutId }
        let sortedGroups = grouped.values.sorted { group1, group2 in
            let date1 = group1.first?.date ?? .distantPast
            let date2 = group2.first?.date ?? .distantPast
            return date1 > date2
        }

        guard let lastGroup = sortedGroups.first else { return nil }

        let workingSets = lastGroup
            .filter { $0.setType == .working && $0.hasData }
            .sorted { ($0.effectiveWeight ?? 0) > ($1.effectiveWeight ?? 0) }

        let topSets = workingSets.prefix(2).map { set -> TopSet in
            let label: String
            if let ew = set.effectiveWeight, let reps = set.reps, reps > 0 {
                label = "\(formatWeight(ew))×\(reps)"
            } else if let duration = set.durationSeconds, duration > 0 {
                label = UnitConversion.formatDuration(duration)
            } else {
                label = "--"
            }
            return TopSet(
                weight: set.effectiveWeight ?? 0,
                reps: set.reps,
                durationSeconds: set.durationSeconds,
                formattedLabel: label
            )
        }

        let lastDate = lastGroup.compactMap(\.completedAt).max()
            ?? lastGroup.first?.date
            ?? Date()
        let calendar = Calendar.current
        let daysAgo = calendar.dateComponents([.day], from: lastDate, to: Date()).day ?? 0

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeTimeLabel = formatter.localizedString(for: lastDate, relativeTo: Date())

        return LastWorkoutInfo(
            topSets: Array(topSets),
            daysAgo: daysAgo,
            relativeTimeLabel: relativeTimeLabel
        )
    }

    // MARK: - Helpers

    private static func snap(_ value: Double, to increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }

    private static func formatWeight(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", kg)
            : String(format: "%.1f", kg)
    }
}
