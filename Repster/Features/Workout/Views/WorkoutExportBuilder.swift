// WorkoutExportBuilder.swift
// One saved workout as a self-describing JSON file, for a coach, an AI or a script to evaluate.
// Built from the `WorkoutDetail` the history screens already hold, so it needs no fetch and
// touches no live model.
// Scoping: WORKOUT_EXPORT_SCOPING.md

import Foundation

/// The exported file, schema version 1.
///
/// **Not a backup and must never decode as one.** Restore is a replace: a one-workout file it
/// could read would become "delete my history except this workout". The top-level shape shares
/// no required key with `WorkoutHistoryArchive`, and the file is `.json`, which the Restore
/// picker does not accept — see `testRestoreRejectsAnExportedWorkout`.
///
/// Optionals are omitted rather than written as `null` (synthesized `encodeIfPresent`).
/// `completed` is the one field every set always carries.
struct WorkoutExport: Encodable, Equatable {
    static let format = "repster.workout"
    static let schemaVersion = 1

    struct App: Encodable, Equatable {
        let name: String
        let version: String
    }

    struct Units: Encodable, Equatable {
        let weight: String
        let distance: String
        let duration: String
    }

    struct Summary: Encodable, Equatable {
        let exerciseCount: Int
        let setCount: Int
        let completedSetCount: Int
    }

    struct Workout: Encodable, Equatable {
        let id: UUID
        let title: String
        let date: Date
        let startTime: Date?
        let endTime: Date?
        let durationSeconds: Int?
        let perceivedEffort: Double?
        let notes: String?
        let countsTowardProgression: Bool
        let summary: Summary
        let exercises: [Exercise]
    }

    struct Exercise: Encodable, Equatable {
        let name: String
        let exerciseId: UUID
        let equipment: String
        let trackingType: String
        let primaryMuscle: String?
        let secondaryMuscles: [String]
        let movementPattern: String?
        let unilateral: Bool
        let unilateralRepCounting: String?
        let bodyweightFactor: Double
        let supersetGroup: Int?
        let countsTowardProgression: Bool
        let sets: [LoggedSet]
    }

    struct LoggedSet: Encodable, Equatable {
        let number: Int
        let type: String
        let completed: Bool
        let weight: Double?
        let effectiveWeight: Double?
        let reps: Int?
        let leftReps: Int?
        let rightReps: Int?
        let side: String?
        let rir: Double?
        let leftRIR: Double?
        let rightRIR: Double?
        let rpe: Double?
        let durationSeconds: Int?
        let distance: Double?
        let estimatedOneRepMax: Double?
        let personalRecord: String?
        let target: Target?
        let restSeconds: Int?
        let startedAt: Date?
        let completedAt: Date?
        let notes: String?
    }

    struct Target: Encodable, Equatable {
        let repMin: Int?
        let repMax: Int?
        let rir: Int?
    }

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let app: App
    let units: Units
    let conventions: [String]
    let workout: Workout
}

enum WorkoutExportBuilder {

    /// Finished workouts only. The Calendar lists in-progress ones too, and a file exported
    /// mid-session is wrong a minute later.
    static func canExport(_ detail: WorkoutDetail) -> Bool {
        detail.workout.status == .completed
    }

    // MARK: - Build

    /// Every set row is exported, ticked or not. A row nobody ticked — a Copy Previous ghost, or
    /// an exercise added and never done — carries `completed: false` rather than being dropped,
    /// so the reader sees the plan as well as what was done (UNPERFORMED_SETS_SCOPING.md).
    static func make(
        detail: WorkoutDetail,
        unitPreference: UnitPreference,
        exportedAt: Date = Date(),
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    ) -> WorkoutExport {
        let workout = detail.workout
        let supersetNumbers = supersetNumbers(for: detail.exerciseGroups)

        let exercises = detail.exerciseGroups.map { group in
            exportExercise(
                group,
                supersetGroup: supersetNumbers[group.exercise.id],
                countsTowardProgression: !workout.excludesFromProgressionHistory(exerciseId: group.exercise.id),
                unitPreference: unitPreference
            )
        }
        let allSets = exercises.flatMap(\.sets)

        return WorkoutExport(
            format: WorkoutExport.format,
            schemaVersion: WorkoutExport.schemaVersion,
            exportedAt: exportedAt,
            app: WorkoutExport.App(name: "Repster", version: appVersion),
            units: WorkoutExport.Units(
                weight: UnitConversion.weightUnitLabel(for: unitPreference),
                distance: "m",
                duration: "s"
            ),
            conventions: conventions(unitPreference: unitPreference),
            workout: WorkoutExport.Workout(
                id: workout.id,
                title: workout.displayTitle,
                date: workout.date,
                startTime: workout.startTime,
                endTime: workout.endTime,
                durationSeconds: workout.duration,
                perceivedEffort: workout.perceivedEffort,
                notes: trimmedNotes(workout.notes),
                countsTowardProgression: !workout.excludesEntireWorkoutFromProgressionHistory,
                summary: WorkoutExport.Summary(
                    exerciseCount: exercises.count,
                    setCount: allSets.count,
                    completedSetCount: allSets.filter(\.completed).count
                ),
                exercises: exercises
            )
        )
    }

    private static func exportExercise(
        _ group: ExerciseGroup,
        supersetGroup: Int?,
        countsTowardProgression: Bool,
        unitPreference: UnitPreference
    ) -> WorkoutExport.Exercise {
        let exercise = group.exercise
        return WorkoutExport.Exercise(
            name: exercise.name,
            exerciseId: exercise.id,
            equipment: exercise.equipmentType.rawValue,
            trackingType: exercise.trackingType.rawValue,
            primaryMuscle: exercise.primaryMuscle,
            secondaryMuscles: exercise.secondaryMuscles,
            movementPattern: exercise.movementPattern?.rawValue,
            unilateral: exercise.unilateral,
            unilateralRepCounting: exercise.unilateral ? repCounting(exercise.unilateralRepTargetMode) : nil,
            bodyweightFactor: exercise.bodyweightFactor,
            supersetGroup: supersetGroup,
            countsTowardProgression: countsTowardProgression,
            // `group.sets` is already in `orderInExercise` order (`ExerciseGroup.build`), but that
            // column has gaps once a set is deleted, so the visible number is the position.
            sets: group.sets.enumerated().map { index, set in
                exportSet(set, number: index + 1, unitPreference: unitPreference)
            }
        )
    }

    private static func exportSet(
        _ set: ChartSetData,
        number: Int,
        unitPreference: UnitPreference
    ) -> WorkoutExport.LoggedSet {
        let weight = set.weight.map { displayed($0, unitPreference) }
        let effectiveWeight = set.effectiveWeight.map { displayed($0, unitPreference) }
        let bounds = set.preferredTargetRepBounds
        let target: WorkoutExport.Target? = bounds.min == nil && bounds.max == nil && set.targetRIR == nil
            ? nil
            : WorkoutExport.Target(repMin: bounds.min, repMax: bounds.max, rir: set.targetRIR)

        return WorkoutExport.LoggedSet(
            number: number,
            type: set.setType.rawValue,
            completed: set.completed,
            weight: weight,
            // Only when it says something `weight` doesn't: the logged bodyweight share.
            effectiveWeight: effectiveWeight == weight ? nil : effectiveWeight,
            reps: set.reps,
            leftReps: set.leftReps,
            rightReps: set.rightReps,
            side: set.side?.rawValue,
            rir: set.rir,
            leftRIR: set.leftRIR,
            rightRIR: set.rightRIR,
            rpe: set.rpe,
            durationSeconds: set.durationSeconds,
            // Metres for everyone: it is what the field stores and what the user typed —
            // `handleDistanceChange` parses with no unit conversion. Only display converts.
            distance: set.distanceMeters,
            estimatedOneRepMax: set.e1RM.map { displayed($0, unitPreference) },
            personalRecord: personalRecord(set.prStatus),
            target: target,
            restSeconds: set.restDurationSeconds,
            startedAt: set.startedAt,
            completedAt: set.completedAt,
            notes: trimmedNotes(set.notes)
        )
    }

    // MARK: - Field rules

    /// Mirrors the badges the app draws, plus `beaten` so a record set on the day still reads as
    /// one. `dominated` owns a rep-count record but has no badge, and calling it a PR would
    /// overclaim. Reads `prStatus` — the legacy `cachedPRStatus` is never written.
    static func personalRecord(_ status: CachedPRStatus?) -> String? {
        switch status {
        case .current: return "current"
        case .matched: return "matched"
        case .previous: return "beaten"
        case .dominated, nil: return nil
        }
    }

    private static func repCounting(_ mode: UnilateralRepTargetMode) -> String {
        switch mode {
        case .perSide: return "perSide"
        case .totalAcrossSides: return "totalAcrossSides"
        }
    }

    /// 1, 2, … for each superset in workout order, keyed by exercise. Uses the same runs the
    /// detail screen draws as superset cards, so the file groups exactly what the user sees —
    /// trios included, and a lone or non-adjacent group id left as an ordinary exercise.
    private static func supersetNumbers(for groups: [ExerciseGroup]) -> [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        var next = 1
        for run in ExerciseGroupRun.runs(from: groups) where run.isMarked {
            for group in run.groups {
                numbers[group.exercise.id] = next
            }
            next += 1
        }
        return numbers
    }

    /// Stored kg into the user's unit, at the 2 dp `UnitConversion.formatWeight` shows.
    /// Unrounded, 100 kg in lb is 220.46200000000002.
    private static func displayed(_ kg: Double, _ unitPreference: UnitPreference) -> Double {
        (UnitConversion.displayedWeight(kg, unitPreference: unitPreference) * 100).rounded() / 100
    }

    private static func trimmedNotes(_ notes: String?) -> String? {
        guard let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Written into the file because its reader is usually an AI or a person without this
    /// codebase, and these are the fields that get misread.
    private static func conventions(unitPreference: UnitPreference) -> [String] {
        let unit = UnitConversion.weightUnitLabel(for: unitPreference)
        return [
            "Weights are in \(unit). Distance is in metres. Durations are in seconds.",
            "completed: false means the set was planned or pre-filled but never ticked as done. Do not count it as performed.",
            "weight is the load entered for the set. effectiveWeight, when present, adds the logged bodyweight share for bodyweight-style exercises.",
            "rir is reps in reserve. A value of 5 means 5 or more.",
            "restSeconds is only recorded when the rest timer ran to zero. Absent means not measured, not no rest.",
            "personalRecord: current = still the record, matched = tied the record, beaten = was a record when set and has since been beaten.",
            "perceivedEffort is the session RPE on a 1-10 scale.",
            "Sets are numbered within their exercise. Exercises sharing a supersetGroup number were done as a superset."
        ]
    }

    // MARK: - Encoding

    /// Pretty-printed with sorted keys, so two exports of the same workout differ only in
    /// `exportedAt`. Dates carry the UTC offset of `timeZone`: "07:10+02:00" tells a reader it
    /// was a morning session, where "05:10Z" does not.
    static func encode(_ export: WorkoutExport, timeZone: TimeZone = .current) throws -> Data {
        let style = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: timeZone)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(style))
        }
        return try encoder.encode(export)
    }

    /// `repster-workout-2026-09-10-push-day-a.json`: sortable by date, recognisable by title.
    static func filename(for detail: WorkoutDetail, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: detail.workout.date)
        let date = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)

        let slug = detail.workout.displayTitle
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let title = String(slug.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return "repster-workout-\(date)\(title.isEmpty ? "" : "-\(title)").json"
    }
}
