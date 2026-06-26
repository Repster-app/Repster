// InsightsService.swift
// Analysis engine for the Insights feed.
//
// Pipeline: generate (every rule runs) → gate (data sufficiency + minimum
// effect, enforced inside each rule) → score → curate (one card per rule,
// capped) → persist as InsightRecords. Zero insights is a valid outcome —
// rules stay silent below their statistical gates rather than emitting
// low-confidence findings.

import Foundation
import SwiftData

// MARK: - Rule plumbing

/// A candidate finding emitted by a rule. Scoring happens in the engine.
struct InsightFinding {
    let ruleId: String
    let subjectId: UUID?
    let subjectName: String?
    let headline: String
    let detailText: String
    let methodologyText: String
    let chartLabels: [String]
    let chartValues: [Double]
    /// Normalized 0...1 magnitude of the finding. Rules return nothing below
    /// their minimum-effect floor, so this is always "worth saying".
    let effectSize: Double
}

/// Read-only snapshot of training data that rules evaluate against.
struct InsightAnalysisContext {
    /// Completed workouts, newest first.
    let workouts: [Workout]
    /// Completed sets with data, grouped by workout, ordered by orderInWorkout.
    let setsByWorkout: [UUID: [WorkoutSet]]
    let exercisesById: [UUID: Exercise]
    /// Fatigue observations, newest first.
    let observations: [FatigueObservation]
    let referenceDate: Date
    let unitPreference: UnitPreference

    func workout(_ id: UUID) -> Workout? {
        workoutsById[id]
    }

    private var workoutsById: [UUID: Workout] {
        Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
    }

    /// Working sets eligible for progression analysis (respects per-workout
    /// and per-exercise exclusion flags), newest workout first.
    var eligibleWorkingSets: [WorkoutSet] {
        workouts.flatMap { workout -> [WorkoutSet] in
            guard !workout.excludesEntireWorkoutFromProgressionHistory else { return [] }
            let excluded = workout.excludedExerciseIdsForProgressionHistory
            return (setsByWorkout[workout.id] ?? []).filter {
                $0.setType == .working && !excluded.contains($0.exerciseId)
            }
        }
    }
}

protocol InsightRule {
    var ruleId: String { get }
    /// Relative weight for findings the user can directly act on (0...1).
    var actionability: Double { get }
    func evaluate(_ context: InsightAnalysisContext) -> [InsightFinding]
}

// MARK: - Engine

@ModelActor
actor InsightsService: InsightsServiceProtocol {

    /// Bump when rule logic changes so existing users get a fresh analysis.
    static let analysisVersion = 1
    static let maxVisibleInsights = 3
    static let snoozeDays = 21

    private static let lastAnalysisSignatureKey = "insightsLastAnalysisSignature"

    static let rules: [any InsightRule] = [
        RestSweetSpotInsightRule(),
        TargetAdherenceInsightRule(),
        MuscleBalanceInsightRule(),
        PRRhythmInsightRule(),
        RIRCalibrationInsightRule()
    ]

    // MARK: - InsightsServiceProtocol

    func refreshIfNeeded() async throws {
        let signature = try currentDataSignature()
        let stored = UserDefaults.standard.string(forKey: Self.lastAnalysisSignatureKey)
        guard signature != stored else { return }

        try runAnalysis(referenceDate: Date())
        UserDefaults.standard.set(signature, forKey: Self.lastAnalysisSignatureKey)
    }

    func fetchActiveInsights() async throws -> [InsightItem] {
        try activeRecords().map(Self.item(from:))
    }

    func newInsightCount() async throws -> Int {
        try activeRecords().filter { $0.state == .new }.count
    }

    func markAllSeen() async throws {
        let now = Date()
        var changed = false
        for record in try activeRecords() where record.state == .new {
            record.state = .seen
            record.seenAt = now
            record.updatedAt = now
            changed = true
        }
        if changed {
            try modelContext.save()
        }
    }

    func snooze(insightId: UUID) async throws {
        let descriptor = FetchDescriptor<InsightRecord>(
            predicate: #Predicate { $0.id == insightId }
        )
        guard let record = try modelContext.fetch(descriptor).first else { return }
        let now = Date()
        record.snoozedUntil = Calendar.current.date(byAdding: .day, value: Self.snoozeDays, to: now)
        record.state = .seen
        record.seenAt = record.seenAt ?? now
        record.updatedAt = now
        try modelContext.save()
    }

    // MARK: - Analysis

    /// Runs the full pipeline against the current store. Internal so tests can
    /// drive it with a fixed reference date.
    func runAnalysis(referenceDate: Date) throws {
        let context = try buildContext(referenceDate: referenceDate)

        let findings = Self.rules.flatMap { rule in
            rule.evaluate(context).map { finding in
                (finding: finding, score: finding.effectSize * rule.actionability)
            }
        }

        // One card per rule, best finding wins, capped feed.
        var bestPerRule: [String: (finding: InsightFinding, score: Double)] = [:]
        for entry in findings {
            if let existing = bestPerRule[entry.finding.ruleId], existing.score >= entry.score {
                continue
            }
            bestPerRule[entry.finding.ruleId] = entry
        }
        let curated = bestPerRule.values
            .sorted { $0.score > $1.score }
            .prefix(Self.maxVisibleInsights)

        try persist(Array(curated), referenceDate: referenceDate)
    }

    private func persist(
        _ curated: [(finding: InsightFinding, score: Double)],
        referenceDate: Date
    ) throws {
        let existing = try modelContext.fetch(FetchDescriptor<InsightRecord>())
        var liveIds = Set<UUID>()

        for entry in curated {
            let finding = entry.finding
            let match = existing.first {
                $0.ruleId == finding.ruleId && $0.subjectId == finding.subjectId
            }

            if let match {
                // Snoozed insights stay hidden even when re-detected.
                match.score = entry.score
                match.headline = finding.headline
                match.detailText = finding.detailText
                match.methodologyText = finding.methodologyText
                match.chartLabels = finding.chartLabels
                match.chartValues = finding.chartValues
                match.generatedAt = referenceDate
                match.updatedAt = referenceDate
                liveIds.insert(match.id)
            } else {
                let record = InsightRecord(
                    ruleId: finding.ruleId,
                    subjectId: finding.subjectId,
                    subjectName: finding.subjectName,
                    score: entry.score,
                    headline: finding.headline,
                    detailText: finding.detailText,
                    methodologyText: finding.methodologyText,
                    chartLabels: finding.chartLabels,
                    chartValues: finding.chartValues,
                    generatedAt: referenceDate
                )
                modelContext.insert(record)
                liveIds.insert(record.id)
            }
        }

        // Findings that no longer hold are removed; snoozed records survive
        // until their cooldown lapses so re-detection inside the window stays
        // suppressed.
        for record in existing where !liveIds.contains(record.id) {
            if let snoozedUntil = record.snoozedUntil, snoozedUntil > referenceDate {
                continue
            }
            modelContext.delete(record)
        }

        try modelContext.save()
    }

    private func buildContext(referenceDate: Date) throws -> InsightAnalysisContext {
        let workoutDescriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let workouts = try modelContext.fetch(workoutDescriptor)
            .filter { $0.status == .completed }
        let workoutIds = Set(workouts.map(\.id))

        let setDescriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.completed == true },
            sortBy: [SortDescriptor(\.orderInWorkout)]
        )
        let sets = try modelContext.fetch(setDescriptor)
            .filter { $0.hasData && workoutIds.contains($0.workoutId) }

        let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())

        let observationDescriptor = FetchDescriptor<FatigueObservation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let observations = try modelContext.fetch(observationDescriptor)

        let profile = try modelContext.fetch(FetchDescriptor<HealthProfile>()).first

        return InsightAnalysisContext(
            workouts: workouts,
            setsByWorkout: Dictionary(grouping: sets, by: \.workoutId),
            exercisesById: Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) }),
            observations: observations,
            referenceDate: referenceDate,
            unitPreference: profile?.unitPreference ?? .metric
        )
    }

    // MARK: - Helpers

    private func activeRecords() throws -> [InsightRecord] {
        let now = Date()
        let records = try modelContext.fetch(FetchDescriptor<InsightRecord>())
        return records
            .filter { $0.snoozedUntil == nil || $0.snoozedUntil! <= now }
            .sorted {
                if ($0.state == .new) != ($1.state == .new) {
                    return $0.state == .new
                }
                return $0.score > $1.score
            }
    }

    /// Cheap change detector: completed workout count + latest completion date
    /// + analysis version. Avoids re-running the pipeline on every Home load.
    private func currentDataSignature() throws -> String {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let completed = try modelContext.fetch(descriptor)
            .filter { $0.status == .completed }
        let latest = completed.first?.date.timeIntervalSince1970 ?? 0
        return "v\(Self.analysisVersion)-\(completed.count)-\(latest)"
    }

    private static func item(from record: InsightRecord) -> InsightItem {
        InsightItem(
            id: record.id,
            ruleId: record.ruleId,
            subjectName: record.subjectName,
            headline: record.headline,
            detailText: record.detailText,
            methodologyText: record.methodologyText,
            chartLabels: record.chartLabels,
            chartValues: record.chartValues,
            isNew: record.state == .new,
            generatedAt: record.generatedAt
        )
    }
}
