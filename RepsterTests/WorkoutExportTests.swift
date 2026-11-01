// WorkoutExportTests.swift
// The single-workout JSON export (WORKOUT_EXPORT_SCOPING.md): what goes in the file, in which
// unit, and that the file can never be mistaken for a backup.

import XCTest
@testable import Repster

@MainActor
final class WorkoutExportTests: XCTestCase {

    private let workoutId = UUID()
    /// Pinned so offsets and filenames are deterministic: CEST is +02:00 in September.
    private let timeZone = TimeZone(identifier: "Europe/Budapest")!
    private lazy var workoutDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 18))!
    }()

    // MARK: - Fixtures

    private func exercise(
        _ name: String,
        equipment: EquipmentType = .barbell,
        tracking: TrackingType = .weightReps,
        muscle: String? = "chest",
        unilateral: Bool = false,
        bodyweightFactor: Double = 0
    ) -> ChartExerciseData {
        ChartExerciseData(from: Exercise(
            name: name,
            equipmentType: equipment,
            trackingType: tracking,
            primaryMuscle: muscle,
            unilateral: unilateral,
            bodyweightFactor: bodyweightFactor
        ))
    }

    private func set(
        _ exercise: ChartExerciseData,
        order: Int,
        orderInExercise: Int? = nil,
        weight: Double? = nil,
        effectiveWeight: Double? = nil,
        reps: Int? = nil,
        completed: Bool = true,
        type: SetType = .working,
        pr: CachedPRStatus? = nil,
        e1RM: Double? = nil,
        distance: Double? = nil,
        rir: Double? = nil,
        superset: UUID? = nil,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        overrideTargetRepMin: Int? = nil,
        overrideTargetRepMax: Int? = nil,
        targetRIR: Int? = nil,
        notes: String? = nil
    ) -> ChartSetData {
        let set = WorkoutSet(
            workoutId: workoutId,
            exerciseId: exercise.id,
            weight: weight,
            effectiveWeight: effectiveWeight ?? weight,
            reps: reps,
            distanceMeters: distance,
            e1RM: e1RM,
            rir: rir,
            setType: type,
            notes: notes,
            orderInWorkout: order,
            orderInExercise: orderInExercise ?? order,
            supersetGroupId: superset,
            completed: completed,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            overrideTargetRepMin: overrideTargetRepMin,
            overrideTargetRepMax: overrideTargetRepMax,
            targetRIR: targetRIR
        )
        set.prStatus = pr
        return ChartSetData(from: set)
    }

    /// A saved workout as the history screens load it: every set in one pile, grouped and
    /// ordered by `ExerciseGroup.build`.
    private func detail(
        _ sets: [ChartSetData],
        exercises: [ChartExerciseData],
        title: String? = "Push Day A",
        status: WorkoutStatus = .completed,
        excludeWorkout: Bool? = nil,
        excludedExerciseIds: [UUID]? = nil,
        notes: String? = nil
    ) -> WorkoutDetail {
        let workout = Workout(
            id: workoutId,
            date: workoutDate,
            title: title,
            startTime: workoutDate,
            endTime: workoutDate.addingTimeInterval(3840),
            duration: 3840,
            perceivedEffort: 7,
            notes: notes,
            status: status,
            excludeFromProgressionHistory: excludeWorkout,
            excludedExerciseIdsFromProgressionHistory: excludedExerciseIds
        )
        let byId = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        return WorkoutDetail(
            workout: WorkoutSnapshot(from: workout),
            exerciseGroups: ExerciseGroup.build(sets: sets, exercisesById: byId, statsById: [:]),
            primaryMetric: nil,
            exerciseCount: 0,
            setCount: 0
        )
    }

    private func make(_ detail: WorkoutDetail, unit: UnitPreference = .metric) -> WorkoutExport {
        WorkoutExportBuilder.make(
            detail: detail,
            unitPreference: unit,
            exportedAt: workoutDate.addingTimeInterval(86_400),
            appVersion: "1.6"
        )
    }

    private func json(_ export: WorkoutExport) throws -> [String: Any] {
        let data = try WorkoutExportBuilder.encode(export, timeZone: timeZone)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Never-ticked rows

    /// The decision with the user: a row nobody ticked stays in the file, marked not done,
    /// rather than being dropped the way the share card drops it.
    func testNeverTickedRowsAreExportedAsNotCompleted() {
        let bench = exercise("Barbell Bench Press")
        let raise = exercise("Lateral Raise", equipment: .dumbbell, muscle: "shoulders")
        let export = make(detail([
            set(bench, order: 1, weight: 100, reps: 5),
            set(bench, order: 2, weight: 100, reps: 5),
            set(bench, order: 3, weight: 100, reps: 5, completed: false),
            set(raise, order: 4, weight: 10, reps: 15, completed: false)
        ], exercises: [bench, raise]))

        let exercises = export.workout.exercises
        XCTAssertEqual(exercises.map(\.name), ["Barbell Bench Press", "Lateral Raise"],
                       "An exercise added and never done is still part of the session.")
        XCTAssertEqual(exercises[0].sets.map(\.completed), [true, true, false])
        XCTAssertEqual(exercises[0].sets[2].weight, 100, "A ghost row keeps its values; only the flag says it wasn't done.")
        XCTAssertEqual(exercises[1].sets.map(\.completed), [false])

        XCTAssertEqual(export.workout.summary, WorkoutExport.Summary(exerciseCount: 2, setCount: 4, completedSetCount: 2))
    }

    func testEveryEncodedSetCarriesCompletedAndTheFileHasNoNulls() throws {
        let bench = exercise("Barbell Bench Press")
        let data = try WorkoutExportBuilder.encode(make(detail([
            set(bench, order: 1, weight: 100, reps: 5),
            set(bench, order: 2, completed: false)
        ], exercises: [bench])), timeZone: timeZone)

        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("null"), "Absent values are omitted, never written as null.")

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let workout = try XCTUnwrap(root["workout"] as? [String: Any])
        let exercises = try XCTUnwrap(workout["exercises"] as? [[String: Any]])
        let sets = try XCTUnwrap(exercises.first?["sets"] as? [[String: Any]])
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.map { $0["completed"] as? Bool }, [true, false],
                       "completed must be present on every set, false included.")
        XCTAssertNil(sets[1]["weight"], "A blank row has no weight key at all.")
    }

    // MARK: - Units

    func testImperialConvertsWeightAndE1RMButDistanceStaysInMetres() throws {
        let bench = exercise("Barbell Bench Press")
        let sled = exercise("Sled Push", equipment: .sled, tracking: .weightDistance, muscle: "quads")
        let export = make(detail([
            set(bench, order: 1, weight: 100, reps: 5, e1RM: 116.67),
            set(sled, order: 2, weight: 40, distance: 20)
        ], exercises: [bench, sled]), unit: .imperial)

        XCTAssertEqual(export.units, WorkoutExport.Units(weight: "lb", distance: "m", duration: "s"))
        let benchSet = export.workout.exercises[0].sets[0]
        XCTAssertEqual(benchSet.weight, 220.46, "Rounded to 2 dp, not 220.46200000000002.")
        XCTAssertEqual(benchSet.estimatedOneRepMax, 257.21)
        XCTAssertEqual(export.workout.exercises[1].sets[0].distance, 20,
                       "Distance is stored and typed in metres for every user; only display converts.")
        XCTAssertTrue(export.conventions.first?.contains("lb") == true)

        let text = try XCTUnwrap(String(data: WorkoutExportBuilder.encode(export, timeZone: timeZone), encoding: .utf8))
        XCTAssertTrue(text.contains("220.46"))
        XCTAssertFalse(text.contains("220.462"))
    }

    func testMetricKeepsStoredKilograms() {
        let bench = exercise("Barbell Bench Press")
        let export = make(detail([set(bench, order: 1, weight: 92.5, reps: 5)], exercises: [bench]))

        XCTAssertEqual(export.units.weight, "kg")
        XCTAssertEqual(export.workout.exercises[0].sets[0].weight, 92.5)
    }

    /// `effectiveWeight` only appears when it says something `weight` doesn't.
    func testEffectiveWeightOnlyWhenBodyweightChangesIt() {
        let dip = exercise("Dip", equipment: .bodyweight, muscle: "triceps", bodyweightFactor: 1)
        let bench = exercise("Barbell Bench Press")
        let export = make(detail([
            set(dip, order: 1, weight: 10, effectiveWeight: 90, reps: 8),
            set(bench, order: 2, weight: 100, reps: 5)
        ], exercises: [dip, bench]))

        XCTAssertEqual(export.workout.exercises[0].sets[0].weight, 10)
        XCTAssertEqual(export.workout.exercises[0].sets[0].effectiveWeight, 90)
        XCTAssertEqual(export.workout.exercises[0].bodyweightFactor, 1)
        XCTAssertNil(export.workout.exercises[1].sets[0].effectiveWeight)
    }

    // MARK: - Order and numbering

    func testExercisesFollowWorkoutOrderAndSetsAreNumberedByPosition() {
        let bench = exercise("Barbell Bench Press")
        let press = exercise("Overhead Press", muscle: "shoulders")
        let export = make(detail([
            set(press, order: 3, orderInExercise: 2, weight: 50, reps: 8),
            set(bench, order: 1, orderInExercise: 4, weight: 100, reps: 5),
            set(bench, order: 2, orderInExercise: 9, weight: 100, reps: 5),
            set(press, order: 4, orderInExercise: 7, weight: 50, reps: 8)
        ], exercises: [bench, press]))

        XCTAssertEqual(export.workout.exercises.map(\.name), ["Barbell Bench Press", "Overhead Press"])
        XCTAssertEqual(export.workout.exercises[0].sets.map(\.number), [1, 2],
                       "orderInExercise has gaps once sets are deleted; the number is the position.")
        XCTAssertEqual(export.workout.exercises[1].sets.map(\.number), [1, 2])
    }

    func testSetTypeIsTheRawValue() {
        let bench = exercise("Barbell Bench Press")
        let export = make(detail([
            set(bench, order: 1, weight: 60, reps: 5, type: .warmup),
            set(bench, order: 2, weight: 100, reps: 5),
            set(bench, order: 3, weight: 70, reps: 10, type: .dropset)
        ], exercises: [bench]))

        XCTAssertEqual(export.workout.exercises[0].sets.map(\.type), ["warmup", "working", "dropset"])
    }

    // MARK: - Records

    func testPersonalRecordMapping() {
        XCTAssertEqual(WorkoutExportBuilder.personalRecord(.current), "current")
        XCTAssertEqual(WorkoutExportBuilder.personalRecord(.matched), "matched")
        XCTAssertEqual(WorkoutExportBuilder.personalRecord(.previous), "beaten",
                       "A record set on the day is still a record set on the day.")
        XCTAssertNil(WorkoutExportBuilder.personalRecord(.dominated), "No badge in the app, so no claim in the file.")
        XCTAssertNil(WorkoutExportBuilder.personalRecord(nil))
    }

    func testPersonalRecordReadsPRStatusOffTheSet() {
        let bench = exercise("Barbell Bench Press")
        let export = make(detail([
            set(bench, order: 1, weight: 100, reps: 5, pr: .current),
            set(bench, order: 2, weight: 95, reps: 5, pr: .previous),
            set(bench, order: 3, weight: 90, reps: 5)
        ], exercises: [bench]))

        XCTAssertEqual(export.workout.exercises[0].sets.map(\.personalRecord), ["current", "beaten", nil])
    }

    // MARK: - Targets

    func testTargetPrefersTheOverrideOverTheTemplate() {
        let bench = exercise("Barbell Bench Press")
        let export = make(detail([
            set(bench, order: 1, weight: 100, reps: 5, targetRepMin: 8, targetRepMax: 12,
                overrideTargetRepMin: 5, overrideTargetRepMax: 6, targetRIR: 2),
            set(bench, order: 2, weight: 100, reps: 10, targetRepMin: 8, targetRepMax: 12),
            set(bench, order: 3, weight: 100, reps: 10)
        ], exercises: [bench]))

        let sets = export.workout.exercises[0].sets
        XCTAssertEqual(sets[0].target, WorkoutExport.Target(repMin: 5, repMax: 6, rir: 2))
        XCTAssertEqual(sets[1].target, WorkoutExport.Target(repMin: 8, repMax: 12, rir: nil))
        XCTAssertNil(sets[2].target, "No target at all is omitted, not an empty object.")
    }

    // MARK: - Supersets

    func testSupersetsAreNumberedInOrderAndUngroupedExercisesHaveNoNumber() {
        let first = UUID()
        let second = UUID()
        let bench = exercise("Barbell Bench Press")
        let row = exercise("Barbell Row", muscle: "back")
        let curl = exercise("Curl", muscle: "biceps")
        let pushdown = exercise("Triceps Pushdown", muscle: "triceps")
        let raise = exercise("Lateral Raise", muscle: "shoulders")
        let export = make(detail([
            set(bench, order: 1, weight: 100, reps: 5, superset: first),
            set(row, order: 2, weight: 80, reps: 8, superset: first),
            set(raise, order: 3, weight: 10, reps: 15),
            set(curl, order: 4, weight: 15, reps: 10, superset: second),
            set(pushdown, order: 5, weight: 30, reps: 12, superset: second)
        ], exercises: [bench, row, curl, pushdown, raise]))

        XCTAssertEqual(export.workout.exercises.map(\.supersetGroup), [1, 1, nil, 2, 2])
    }

    /// A group id left on one exercise — its partner removed — is drawn as an ordinary card,
    /// so the file must not call it a superset either.
    func testALoneGroupIdIsNotASuperset() {
        let bench = exercise("Barbell Bench Press")
        let export = make(detail([
            set(bench, order: 1, weight: 100, reps: 5, superset: UUID())
        ], exercises: [bench]))

        XCTAssertNil(export.workout.exercises[0].supersetGroup)
    }

    // MARK: - Progression exclusions

    func testProgressionExclusionAtWorkoutAndExerciseLevel() {
        let bench = exercise("Barbell Bench Press")
        let press = exercise("Overhead Press", muscle: "shoulders")
        let sets = [
            set(bench, order: 1, weight: 100, reps: 5),
            set(press, order: 2, weight: 50, reps: 8)
        ]

        let counted = make(detail(sets, exercises: [bench, press], excludedExerciseIds: [press.id]))
        XCTAssertTrue(counted.workout.countsTowardProgression)
        XCTAssertEqual(counted.workout.exercises.map(\.countsTowardProgression), [true, false])

        let excluded = make(detail(sets, exercises: [bench, press], excludeWorkout: true))
        XCTAssertFalse(excluded.workout.countsTowardProgression)
        XCTAssertEqual(excluded.workout.exercises.map(\.countsTowardProgression), [false, false])
    }

    // MARK: - Workout fields

    func testWorkoutFieldsAndDatesCarryTheLocalOffset() throws {
        let bench = exercise("Barbell Bench Press")
        let root = try json(make(detail(
            [set(bench, order: 1, weight: 100, reps: 5, notes: "  felt fast \n")],
            exercises: [bench],
            notes: "Good session"
        )))

        XCTAssertEqual(root["format"] as? String, "repster.workout")
        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        XCTAssertEqual((root["app"] as? [String: Any])?["version"] as? String, "1.6")
        XCTAssertEqual(root["exportedAt"] as? String, "2026-09-11T18:00:00+02:00")

        let workout = try XCTUnwrap(root["workout"] as? [String: Any])
        XCTAssertEqual(workout["title"] as? String, "Push Day A")
        XCTAssertEqual(workout["date"] as? String, "2026-09-10T18:00:00+02:00")
        XCTAssertEqual(workout["endTime"] as? String, "2026-09-10T19:04:00+02:00")
        XCTAssertEqual(workout["durationSeconds"] as? Int, 3840)
        XCTAssertEqual(workout["perceivedEffort"] as? Double, 7)
        XCTAssertEqual(workout["notes"] as? String, "Good session")

        let sets = try XCTUnwrap(((workout["exercises"] as? [[String: Any]])?.first)?["sets"] as? [[String: Any]])
        XCTAssertEqual(sets.first?["notes"] as? String, "felt fast")
    }

    func testAnUntitledWorkoutUsesTheTitleTheScreenShows() {
        let bench = exercise("Barbell Bench Press")
        let detail = detail([set(bench, order: 1, weight: 100, reps: 5)], exercises: [bench], title: nil)

        XCTAssertEqual(make(detail).workout.title, detail.workout.displayTitle)
        XCTAssertFalse(make(detail).workout.title.isEmpty)
    }

    func testAnEmptyFinishedWorkoutStillExports() throws {
        let export = make(detail([], exercises: []))

        XCTAssertEqual(export.workout.exercises, [])
        XCTAssertEqual(export.workout.summary, WorkoutExport.Summary(exerciseCount: 0, setCount: 0, completedSetCount: 0))
        XCTAssertNoThrow(try WorkoutExportBuilder.encode(export, timeZone: timeZone))
    }

    // MARK: - Gate

    func testOnlyFinishedWorkoutsCanBeExported() {
        let bench = exercise("Barbell Bench Press")
        let sets = [set(bench, order: 1, weight: 100, reps: 5)]

        XCTAssertTrue(WorkoutExportBuilder.canExport(detail(sets, exercises: [bench])))
        XCTAssertFalse(WorkoutExportBuilder.canExport(detail(sets, exercises: [bench], status: .inProgress)))
    }

    // MARK: - Never a backup

    /// Restore is a replace. If a one-workout file decoded as an archive, restoring it would
    /// delete every other workout. This mirrors `WorkoutHistoryBackupService.decodeArchive`,
    /// the first step of both preview and restore.
    func testRestoreRejectsAnExportedWorkout() throws {
        let bench = exercise("Barbell Bench Press")
        let data = try WorkoutExportBuilder.encode(
            make(detail([set(bench, order: 1, weight: 100, reps: 5)], exercises: [bench])),
            timeZone: timeZone
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(WorkoutHistoryArchive.self, from: data))
    }

    // MARK: - Filename

    func testFilenameIsDateAndSanitisedTitle() {
        let bench = exercise("Barbell Bench Press")
        let sets = [set(bench, order: 1, weight: 100, reps: 5)]

        XCTAssertEqual(
            WorkoutExportBuilder.filename(for: detail(sets, exercises: [bench]), timeZone: timeZone),
            "repster-workout-2026-09-10-push-day-a.json"
        )
        XCTAssertEqual(
            WorkoutExportBuilder.filename(for: detail(sets, exercises: [bench], title: "Legs / Back: 2x?"), timeZone: timeZone),
            "repster-workout-2026-09-10-legs-back-2x.json",
            "Path and reserved characters never reach the filename."
        )
        XCTAssertEqual(
            WorkoutExportBuilder.filename(for: detail(sets, exercises: [bench], title: "///"), timeZone: timeZone),
            "repster-workout-2026-09-10.json"
        )
    }
}
