import XCTest
import SwiftData
@testable import Repster

// MARK: - Settings and gating

final class TrainingDataSharingSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrainingDataSharingSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSharingIsOnUntilTheUserSwitchesItOff() {
        let service = makeService(client: RecordingAnalyticsClient())
        XCTAssertTrue(service.isTrainingDataSharingEnabled)

        service.setTrainingDataSharingEnabled(false)
        XCTAssertFalse(service.isTrainingDataSharingEnabled)
    }

    func testFirstLaunchStartsTheWindowAndLaterLaunchesNeverMoveIt() throws {
        let before = Date()
        makeService(client: RecordingAnalyticsClient()).configure()
        let start = try XCTUnwrap(defaults.object(forKey: AnalyticsService.trainingDataSharingSinceDefaultsKey) as? Date)
        XCTAssertGreaterThanOrEqual(start, before)

        makeService(client: RecordingAnalyticsClient()).configure()
        XCTAssertEqual(defaults.object(forKey: AnalyticsService.trainingDataSharingSinceDefaultsKey) as? Date, start)
    }

    /// Switching on by hand is the consent for history logged before the default started.
    func testSwitchingOnByHandOpensTheWindowToAllHistory() {
        let service = makeService(client: RecordingAnalyticsClient())
        service.configure()
        service.setTrainingDataSharingEnabled(false)
        XCTAssertNotEqual(service.trainingDataSharingSince, .distantPast)

        service.setTrainingDataSharingEnabled(true)
        XCTAssertEqual(service.trainingDataSharingSince, .distantPast)
    }

    func testTrainingDataNeedsBothSwitches() {
        let client = RecordingAnalyticsClient()
        let service = makeService(client: client)
        let sink = AnalyticsTrainingDataSink(analytics: service)

        service.captureTrainingData(.workoutsShared, properties: ["workout_count": 1])
        XCTAssertTrue(sink.isSharingActive)
        XCTAssertEqual(client.events, ["training workouts shared"])

        service.setTrainingDataSharingEnabled(false)
        service.captureTrainingData(.workoutsShared, properties: ["workout_count": 1])
        XCTAssertFalse(sink.isSharingActive)

        service.setTrainingDataSharingEnabled(true)
        service.setCollectionEnabled(false)
        service.captureTrainingData(.workoutsShared, properties: ["workout_count": 1])
        XCTAssertFalse(sink.isSharingActive)

        XCTAssertEqual(client.events, ["training workouts shared"])
    }

    /// The bucketed-only promise still holds for every other event: nothing is added to them.
    func testTrainingDataEventsAreKeptOutOfTheProductEventList() {
        let productEvents = Set(AnalyticsEvent.allCases.map(\.rawValue))
        for event in TrainingDataEvent.allCases {
            XCTAssertFalse(productEvents.contains(event.rawValue), event.rawValue)
        }
        XCTAssertEqual(AnalyticsEvent.trainingDataSharingToggled.rawValue, "training data sharing toggled")
    }

    private func makeService(client: RecordingAnalyticsClient) -> AnalyticsService {
        AnalyticsService(
            client: client,
            configuration: AnalyticsConfiguration(projectToken: "test-token", host: nil)!,
            userDefaults: defaults
        )
    }
}

// MARK: - Payloads

final class TrainingDataSharingServiceTests: XCTestCase {
    private let windowStart = Date(timeIntervalSince1970: 1_790_000_000)

    func testFinishedWorkoutCarriesTheSetsAndNothingPrivate() async throws {
        let store = try TestStore()
        let squat = store.insertExercise("Barbell Back Squat")
        let landmine = store.insertExercise("Landmine Rotation")
        let workout = store.insertWorkout(date: windowStart.addingTimeInterval(3600), title: "Leg day", notes: "Knee felt off")
        let superset = UUID()
        store.insertSet(workout, squat, order: 0, weight: 100, reps: 5, rir: 2, notes: "grindy", superset: superset)
        store.insertSet(workout, squat, order: 1, weight: 61.23456789, reps: 8, completed: false, superset: superset)
        store.insertSet(workout, landmine, order: 2, weight: 20, reps: 12)
        try store.save()

        let sink = RecordingSink(since: windowStart)
        let service = TrainingDataSharingService(modelContainer: store.container, sink: sink)
        await service.shareWorkout(workout.id, reason: .finished)

        let capture = try XCTUnwrap(sink.captures.first)
        XCTAssertEqual(sink.captures.count, 1)
        XCTAssertEqual(capture.event, .workoutsShared)
        XCTAssertEqual(capture.properties["reason"] as? String, "finished")
        XCTAssertEqual(capture.properties["schema_version"] as? Int, TrainingDataSharingService.schemaVersion)

        let workouts = try XCTUnwrap(capture.properties["workouts"] as? [[String: Any]])
        XCTAssertEqual(workouts.first?["workout_id"] as? String, workout.id.uuidString)
        let exercises = try XCTUnwrap(workouts.first?["exercises"] as? [[String: Any]])
        XCTAssertEqual(exercises.map { $0["name"] as? String }, ["Barbell Back Squat", "Landmine Rotation"])
        XCTAssertEqual(exercises.map { $0["built_in"] as? Bool }, [true, false])

        let squatSets = try XCTUnwrap(exercises.first?["sets"] as? [[String: Any]])
        XCTAssertEqual(squatSets.count, 2, "unticked rows are sent and flagged, not dropped")
        XCTAssertEqual(squatSets[0]["weight_kg"] as? Double, 100)
        XCTAssertEqual(squatSets[0]["reps"] as? Int, 5)
        XCTAssertEqual(squatSets[0]["rir"] as? Double, 2)
        XCTAssertEqual(squatSets[0]["completed"] as? Bool, true)
        XCTAssertEqual(squatSets[0]["superset_group"] as? Int, 1)
        XCTAssertEqual(squatSets[1]["completed"] as? Bool, false)
        XCTAssertEqual(squatSets[1]["weight_kg"] as? Double, 61.235)

        let json = try String(decoding: JSONSerialization.data(withJSONObject: capture.properties), as: UTF8.self)
        for fragment in ["Leg day", "Knee felt off", "grindy", "effective_weight", "e1_rm", "e1rm", "notes", "title"] {
            XCTAssertFalse(json.contains(fragment), "payload must not contain \(fragment)")
        }
    }

    func testWorkoutsLoggedBeforeTheWindowStayOnTheDevice() async throws {
        let store = try TestStore()
        let squat = store.insertExercise("Barbell Back Squat")
        let workout = store.insertWorkout(date: windowStart.addingTimeInterval(-60))
        store.insertSet(workout, squat, order: 0, weight: 100, reps: 5)
        try store.save()

        let sink = RecordingSink(since: windowStart)
        let service = TrainingDataSharingService(modelContainer: store.container, sink: sink)
        await service.shareWorkout(workout.id, reason: .edited)
        await service.workoutDeleted(workout.id, workoutDate: workout.date)
        let encoded = await service.encodedWorkout(workout.id)

        XCTAssertTrue(sink.captures.isEmpty)
        XCTAssertNil(encoded)
    }

    func testNothingIsReadOrSentWhileSharingIsInactive() async throws {
        let store = try TestStore()
        let squat = store.insertExercise("Barbell Back Squat")
        let workout = store.insertWorkout(date: windowStart.addingTimeInterval(60))
        store.insertSet(workout, squat, order: 0, weight: 100, reps: 5)
        try store.save()

        let sink = RecordingSink(since: .distantPast, active: false)
        let service = TrainingDataSharingService(modelContainer: store.container, sink: sink)
        await service.shareWorkout(workout.id, reason: .finished)
        await service.exercisesCreated([squat.id], source: .manual)
        await service.shareHistory()

        XCTAssertTrue(sink.captures.isEmpty)
    }

    func testAnEditResendsOnlyWhenSharedContentChanged() async throws {
        let store = try TestStore()
        let squat = store.insertExercise("Barbell Back Squat")
        let workout = store.insertWorkout(date: windowStart.addingTimeInterval(60), notes: "before")
        let set = store.insertSet(workout, squat, order: 0, weight: 100, reps: 5)
        try store.save()

        let sink = RecordingSink(since: windowStart)
        let service = TrainingDataSharingService(modelContainer: store.container, sink: sink)
        let baseline = await service.encodedWorkout(workout.id)
        XCTAssertNotNil(baseline)

        // Notes are not shared, so changing them is not a change worth sending.
        workout.notes = "after"
        try store.save()
        await service.shareWorkout(workout.id, reason: .edited, unlessUnchangedFrom: baseline)
        XCTAssertTrue(sink.captures.isEmpty)

        set.reps = 6
        try store.save()
        await service.shareWorkout(workout.id, reason: .edited, unlessUnchangedFrom: baseline)
        XCTAssertEqual(sink.captures.count, 1)
        XCTAssertEqual(sink.captures.first?.properties["reason"] as? String, "edited")
    }

    func testDeletingASharedWorkoutSendsATombstone() async throws {
        let store = try TestStore()
        let sink = RecordingSink(since: windowStart)
        let service = TrainingDataSharingService(modelContainer: store.container, sink: sink)
        let workoutId = UUID()

        await service.workoutDeleted(workoutId, workoutDate: windowStart.addingTimeInterval(60))

        XCTAssertEqual(sink.captures.map(\.event), [.workoutDeleted])
        XCTAssertEqual(sink.captures.first?.properties["workout_id"] as? String, workoutId.uuidString)
    }

    func testHistoryShareSendsEveryCompletedWorkoutInChunksAndTheCustomExercises() async throws {
        let store = try TestStore()
        let squat = store.insertExercise("Barbell Back Squat")
        let custom = store.insertExercise("Belt Squat (Hip)")
        for day in 0..<45 {
            let workout = store.insertWorkout(date: windowStart.addingTimeInterval(Double(day - 30) * 86_400))
            store.insertSet(workout, day.isMultiple(of: 2) ? squat : custom, order: 0, weight: 80, reps: 8)
        }
        let unfinished = store.insertWorkout(date: windowStart, status: .inProgress)
        store.insertSet(unfinished, squat, order: 0, weight: 80, reps: 8)
        try store.save()

        // Switching on by hand moves the window back to the beginning.
        let sink = RecordingSink(since: .distantPast)
        let service = TrainingDataSharingService(modelContainer: store.container, sink: sink)
        await service.shareHistory()

        let workoutEvents = sink.captures.filter { $0.event == .workoutsShared }
        XCTAssertEqual(workoutEvents.map { $0.properties["workout_count"] as? Int }, [20, 20, 5])
        XCTAssertTrue(workoutEvents.allSatisfy { $0.properties["reason"] as? String == "history" })

        let exerciseEvents = sink.captures.filter { $0.event == .exercisesCreated }
        XCTAssertEqual(exerciseEvents.count, 1)
        let exercises = try XCTUnwrap(exerciseEvents.first?.properties["exercises"] as? [[String: Any]])
        XCTAssertEqual(exercises.map { $0["name"] as? String }, ["Belt Squat (Hip)"])
        XCTAssertEqual(exerciseEvents.first?.properties["source"] as? String, "history")
    }

    func testCreatedExercisesAreFlaggedAndTheirNamesCapped() async throws {
        let store = try TestStore()
        let builtIn = store.insertExercise("  barbell back squat ")
        let long = store.insertExercise(String(repeating: "x", count: 120))
        try store.save()

        let sink = RecordingSink(since: windowStart)
        let service = TrainingDataSharingService(modelContainer: store.container, sink: sink)
        await service.exercisesCreated([long.id, builtIn.id], source: .csvImport)

        let capture = try XCTUnwrap(sink.captures.first)
        XCTAssertEqual(capture.properties["source"] as? String, "csv_import")
        let exercises = try XCTUnwrap(capture.properties["exercises"] as? [[String: Any]])
        XCTAssertEqual((exercises[0]["name"] as? String)?.count, TrainingDataSharingService.maxNameLength)
        XCTAssertEqual(exercises.map { $0["built_in"] as? Bool }, [false, true])
    }
}

// MARK: - Helpers

private final class TestStore {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try ModelContainer(
            for: Schema(ModelContainerSetup.modelTypes),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    func insertExercise(_ name: String) -> Exercise {
        let exercise = Exercise(name: name, equipmentType: .barbell, trackingType: .weightReps, primaryMuscle: "legs")
        context.insert(exercise)
        return exercise
    }

    func insertWorkout(
        date: Date,
        title: String? = nil,
        notes: String? = nil,
        status: WorkoutStatus = .completed
    ) -> Workout {
        let workout = Workout(date: date, title: title, startTime: date, duration: 3600, notes: notes, status: status)
        context.insert(workout)
        return workout
    }

    @discardableResult
    func insertSet(
        _ workout: Workout,
        _ exercise: Exercise,
        order: Int,
        weight: Double,
        reps: Int,
        rir: Double? = nil,
        completed: Bool = true,
        notes: String? = nil,
        superset: UUID? = nil
    ) -> WorkoutSet {
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workout.date,
            weight: weight,
            effectiveWeight: weight + 40,
            reps: reps,
            e1RM: weight * 1.2,
            rir: rir,
            notes: notes,
            orderInWorkout: order,
            orderInExercise: order,
            supersetGroupId: superset,
            completed: completed
        )
        context.insert(set)
        return set
    }

    func save() throws {
        try context.save()
    }
}

private final class RecordingSink: TrainingDataSink, @unchecked Sendable {
    struct Capture {
        let event: TrainingDataEvent
        let properties: [String: Any]
    }

    private let lock = NSLock()
    private let active: Bool
    private let since: Date?
    private var recorded: [Capture] = []

    init(since: Date?, active: Bool = true) {
        self.since = since
        self.active = active
    }

    var isSharingActive: Bool { active }
    var sharingSince: Date? { since }

    var captures: [Capture] {
        lock.withLock { recorded }
    }

    func capture(_ event: TrainingDataEvent, properties: [String: Any]) {
        lock.withLock { recorded.append(Capture(event: event, properties: properties)) }
    }
}

private final class RecordingAnalyticsClient: AnalyticsClientProtocol {
    private(set) var events: [String] = []
    private var optedOut = false

    func configure(_ configuration: AnalyticsConfiguration, startOptedOut: Bool) {
        optedOut = startOptedOut
    }

    func capture(_ event: String, properties: [String: Any]) {
        events.append(event)
    }

    func capture(_ event: String, properties: [String: Any], personPropertiesSetOnce: [String: Any]) {
        events.append(event)
    }

    func screen(_ screen: String, properties: [String: Any]) {}
    func captureException(_ error: Error, properties: [String: Any]) {}
    func optIn() { optedOut = false }
    func optOut() { optedOut = true }
    func isOptOut() -> Bool { optedOut }
}
