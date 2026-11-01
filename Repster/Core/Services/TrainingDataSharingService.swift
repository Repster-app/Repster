import Foundation
import SwiftData

// MARK: - Events

/// The training-data channel: what was lifted, set by set, sent to the same PostHog project as
/// product analytics. Deliberately not part of `AnalyticsEvent`. Everything in that enum goes
/// through `AnalyticsService.sanitize` and carries bucketed values only, and these events carry
/// the training log itself, so they get their own name, their own gate and their own setting.
///
/// Every event repeats `schema_version`, so a later payload change can be told apart in SQL.
/// Design and the PostHog queries that read this live in TRAINING_DATA_SHARING_DESIGN.md.
enum TrainingDataEvent: String, CaseIterable {
    /// One or more full workouts. Sent on finish, after an edit, and in chunks when history is
    /// shared. Workouts are never edited in PostHog, so the latest event per `workout_id` wins.
    case workoutsShared = "training workouts shared"
    /// Tombstone for a workout shared earlier, so queries can drop it.
    case workoutDeleted = "training workout deleted"
    /// Exercises the user made themselves — what the built-in library is missing.
    case exercisesCreated = "training exercises created"
}

enum TrainingWorkoutShareReason: String, Encodable, Sendable {
    case finished
    case edited
    case history
}

enum TrainingExerciseSource: String, Encodable, Sendable {
    case manual
    case csvImport = "csv_import"
    case history
}

// MARK: - Sink

/// The half of `AnalyticsServiceProtocol` the sharing actor needs — same arrangement, and the same
/// reason, as `AnalyticsErrorReporting`.
protocol TrainingDataSink: Sendable {
    /// True only while both Share Anonymous Analytics and Share Training Data are on.
    var isSharingActive: Bool { get }
    /// Workouts dated before this were logged under a policy that said they stay on the device,
    /// and are only shared once the user switches sharing on themselves (which moves this back to
    /// `.distantPast`). Nil means nothing is eligible.
    var sharingSince: Date? { get }
    func capture(_ event: TrainingDataEvent, properties: [String: Any])
}

struct AnalyticsTrainingDataSink: TrainingDataSink, @unchecked Sendable {
    // `AnalyticsServiceProtocol` is not Sendable — see `AnalyticsErrorReporter` for why this is safe.
    private let analytics: any AnalyticsServiceProtocol

    init(analytics: any AnalyticsServiceProtocol) {
        self.analytics = analytics
    }

    var isSharingActive: Bool {
        analytics.isCollectionEnabled && analytics.isTrainingDataSharingEnabled
    }

    var sharingSince: Date? {
        analytics.trainingDataSharingSince
    }

    func capture(_ event: TrainingDataEvent, properties: [String: Any]) {
        analytics.captureTrainingData(event, properties: properties)
    }
}

// MARK: - Service

protocol TrainingDataSharingServiceProtocol: Sendable {
    /// Shares one workout as it is stored now. With a `baseline` from `encodedWorkout(_:)`, sends
    /// nothing when the shareable content has not changed — opening Edit Workout and tapping Done
    /// is not an edit.
    func shareWorkout(
        _ workoutId: UUID,
        reason: TrainingWorkoutShareReason,
        unlessUnchangedFrom baseline: Data?
    ) async

    /// The workout's shareable content, encoded, for comparing before and after an edit. Nil when
    /// sharing is off or the workout is not eligible.
    func encodedWorkout(_ workoutId: UUID) async -> Data?

    func workoutDeleted(_ workoutId: UUID, workoutDate: Date) async

    func exercisesCreated(_ exerciseIds: [UUID], source: TrainingExerciseSource) async

    /// Every completed workout and every custom exercise. Only ever called when the user switches
    /// sharing on themselves — that switch is the consent for history logged before it.
    func shareHistory() async
}

extension TrainingDataSharingServiceProtocol {
    func shareWorkout(_ workoutId: UUID, reason: TrainingWorkoutShareReason) async {
        await shareWorkout(workoutId, reason: reason, unlessUnchangedFrom: nil)
    }
}

struct NoopTrainingDataSharingService: TrainingDataSharingServiceProtocol {
    func shareWorkout(
        _ workoutId: UUID,
        reason: TrainingWorkoutShareReason,
        unlessUnchangedFrom baseline: Data?
    ) async {}
    func encodedWorkout(_ workoutId: UUID) async -> Data? { nil }
    func workoutDeleted(_ workoutId: UUID, workoutDate: Date) async {}
    func exercisesCreated(_ exerciseIds: [UUID], source: TrainingExerciseSource) async {}
    func shareHistory() async {}
}

/// Reads through one `ModelContext` it creates per call, like `WorkoutHistoryBackupService`, so no
/// `@Model` object crosses an actor boundary. Callers pass ids and get nothing back.
///
/// What a payload leaves out is as deliberate as what it carries — the privacy policy promises it:
/// - notes and workout titles (free text)
/// - `effectiveWeight` and stored `e1RM`, which fold in bodyweight on bodyweight exercises, so a
///   reader could subtract their way back to it. e1RM is also computed with whichever formula the
///   user picked; recompute it from `weight_kg` and `reps` with one formula when analysing.
actor TrainingDataSharingService: TrainingDataSharingServiceProtocol {
    static let schemaVersion = 1
    /// Keeps a history share well inside the SDK's 1,000-event queue, which evicts the oldest
    /// events when full, and each event to a few hundred KB.
    static let historyWorkoutsPerEvent = 20
    static let exercisesPerEvent = 50
    static let maxNameLength = 80

    private let modelContainer: ModelContainer
    private let sink: any TrainingDataSink
    private lazy var builtInExerciseNames: Set<String> = Self.loadBuiltInExerciseNames()

    init(modelContainer: ModelContainer, sink: any TrainingDataSink) {
        self.modelContainer = modelContainer
        self.sink = sink
    }

    // MARK: Workouts

    func shareWorkout(
        _ workoutId: UUID,
        reason: TrainingWorkoutShareReason,
        unlessUnchangedFrom baseline: Data?
    ) async {
        guard let payload = eligibleWorkoutPayload(workoutId) else { return }
        if let baseline, baseline == (try? Self.encoder.encode(payload)) { return }
        sendWorkouts([payload], reason: reason)
    }

    func encodedWorkout(_ workoutId: UUID) async -> Data? {
        guard let payload = eligibleWorkoutPayload(workoutId) else { return nil }
        return try? Self.encoder.encode(payload)
    }

    func workoutDeleted(_ workoutId: UUID, workoutDate: Date) async {
        guard sink.isSharingActive, isEligible(workoutDate) else { return }
        sink.capture(.workoutDeleted, properties: [
            "schema_version": Self.schemaVersion,
            "workout_id": workoutId.uuidString
        ])
    }

    func shareHistory() async {
        guard sink.isSharingActive else { return }
        let context = ModelContext(modelContainer)

        do {
            let workouts = try context.fetch(
                FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date)])
            ).filter { $0.status == .completed && isEligible($0.date) }
            let setsByWorkout = Dictionary(
                grouping: try context.fetch(FetchDescriptor<WorkoutSet>()),
                by: \.workoutId
            )
            let exercises = try context.fetch(FetchDescriptor<Exercise>())
            let exercisesById = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            let payloads = workouts.map { workout in
                makeWorkoutPayload(
                    workout,
                    sets: setsByWorkout[workout.id] ?? [],
                    exercisesById: exercisesById
                )
            }
            for chunk in payloads.chunked(into: Self.historyWorkoutsPerEvent) {
                sendWorkouts(chunk, reason: .history)
            }

            let customExercises = exercises
                .filter { !isBuiltIn($0.name) }
                .sorted { $0.createdAt < $1.createdAt }
                .map { makeExerciseCreatedPayload($0) }
            sendExercises(customExercises, source: .history)
        } catch {
            dbg("[TrainingDataSharing] History share failed: \(error)")
        }
    }

    // MARK: Exercises

    func exercisesCreated(_ exerciseIds: [UUID], source: TrainingExerciseSource) async {
        guard sink.isSharingActive, !exerciseIds.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let ids = exerciseIds
        let exercises = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { ids.contains($0.id) })
        )) ?? []
        let order = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let payloads = exercises
            .sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
            .map { makeExerciseCreatedPayload($0) }
        sendExercises(payloads, source: source)
    }

    // MARK: Reading

    private func eligibleWorkoutPayload(_ workoutId: UUID) -> TrainingWorkoutPayload? {
        guard sink.isSharingActive else { return nil }
        let context = ModelContext(modelContainer)
        let id = workoutId

        var workoutDescriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        workoutDescriptor.fetchLimit = 1
        guard let workout = (try? context.fetch(workoutDescriptor))?.first,
              workout.status == .completed,
              isEligible(workout.date) else {
            return nil
        }

        let sets = (try? context.fetch(
            FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.workoutId == id })
        )) ?? []
        let exerciseIds = Array(Set(sets.map(\.exerciseId)))
        let exercises = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { exerciseIds.contains($0.id) })
        )) ?? []
        let exercisesById = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return makeWorkoutPayload(workout, sets: sets, exercisesById: exercisesById)
    }

    private func isEligible(_ workoutDate: Date) -> Bool {
        guard let since = sink.sharingSince else { return false }
        return workoutDate >= since
    }

    // MARK: Building

    private func makeWorkoutPayload(
        _ workout: Workout,
        sets: [WorkoutSet],
        exercisesById: [UUID: Exercise]
    ) -> TrainingWorkoutPayload {
        let orderedSets = sets.sorted {
            if $0.orderInWorkout != $1.orderInWorkout { return $0.orderInWorkout < $1.orderInWorkout }
            return $0.orderInExercise < $1.orderInExercise
        }

        // Superset ids are random per install; a small per-workout number says the same thing.
        var supersetNumbers: [UUID: Int] = [:]
        for set in orderedSets {
            if let group = set.supersetGroupId, supersetNumbers[group] == nil {
                supersetNumbers[group] = supersetNumbers.count + 1
            }
        }

        let excludedExerciseIds = workout.excludedExerciseIdsForProgressionHistory
        var exerciseOrder: [UUID] = []
        var setsByExercise: [UUID: [WorkoutSet]] = [:]
        for set in orderedSets {
            if setsByExercise[set.exerciseId] == nil { exerciseOrder.append(set.exerciseId) }
            setsByExercise[set.exerciseId, default: []].append(set)
        }

        let exercises: [TrainingWorkoutExercisePayload] = exerciseOrder.compactMap { exerciseId in
            // A set whose exercise is gone has nothing to compare it with across users.
            guard let exercise = exercisesById[exerciseId] else { return nil }
            let exerciseSets = (setsByExercise[exerciseId] ?? []).sorted {
                $0.orderInExercise < $1.orderInExercise
            }
            return TrainingWorkoutExercisePayload(
                exerciseId: exercise.id.uuidString,
                name: Self.cappedName(exercise.name),
                builtIn: isBuiltIn(exercise.name),
                equipment: exercise.equipmentType.rawValue,
                trackingType: exercise.trackingType.rawValue,
                primaryMuscle: exercise.primaryMuscle,
                movementPattern: exercise.movementPattern?.rawValue,
                unilateral: exercise.unilateral,
                excludedFromProgression: excludedExerciseIds.contains(exercise.id),
                sets: exerciseSets.map { set in
                    TrainingSetPayload(
                        order: set.orderInExercise,
                        type: set.setType.rawValue,
                        completed: set.completed,
                        weightKg: set.weight.map(Self.roundedKg),
                        reps: set.reps,
                        leftReps: set.leftReps,
                        rightReps: set.rightReps,
                        side: set.side?.rawValue,
                        rir: set.rir,
                        leftRir: set.leftRIR,
                        rightRir: set.rightRIR,
                        rpe: set.rpe,
                        durationSeconds: set.durationSeconds,
                        distanceMeters: set.distanceMeters,
                        restSeconds: set.restDurationSeconds,
                        supersetGroup: set.supersetGroupId.flatMap { supersetNumbers[$0] },
                        excludedFromPrs: set.excludeFromPRs,
                        targetWeightKg: set.targetWeight.map(Self.roundedKg),
                        targetRepMin: set.targetRepMin,
                        targetRepMax: set.targetRepMax,
                        targetRir: set.targetRIR
                    )
                }
            )
        }

        return TrainingWorkoutPayload(
            workoutId: workout.id.uuidString,
            date: workout.date,
            durationSeconds: workout.duration,
            perceivedEffort: workout.perceivedEffort,
            fromProgram: workout.programId != nil,
            excludedFromProgression: workout.excludesEntireWorkoutFromProgressionHistory,
            exercises: exercises
        )
    }

    private func makeExerciseCreatedPayload(_ exercise: Exercise) -> TrainingExerciseCreatedPayload {
        TrainingExerciseCreatedPayload(
            exerciseId: exercise.id.uuidString,
            name: Self.cappedName(exercise.name),
            builtIn: isBuiltIn(exercise.name),
            equipment: exercise.equipmentType.rawValue,
            trackingType: exercise.trackingType.rawValue,
            primaryMuscle: exercise.primaryMuscle,
            secondaryMuscles: exercise.secondaryMuscles,
            movementPattern: exercise.movementPattern?.rawValue,
            unilateral: exercise.unilateral,
            bodyweightFactor: exercise.bodyweightFactor
        )
    }

    private func isBuiltIn(_ name: String) -> Bool {
        builtInExerciseNames.contains(Self.normalizedName(name))
    }

    // MARK: Sending

    private func sendWorkouts(_ workouts: [TrainingWorkoutPayload], reason: TrainingWorkoutShareReason) {
        guard sink.isSharingActive, !workouts.isEmpty else { return }
        let envelope = TrainingWorkoutsEnvelope(
            schemaVersion: Self.schemaVersion,
            reason: reason,
            workoutCount: workouts.count,
            workouts: workouts
        )
        guard let properties = Self.properties(from: envelope) else { return }
        sink.capture(.workoutsShared, properties: properties)
    }

    private func sendExercises(_ exercises: [TrainingExerciseCreatedPayload], source: TrainingExerciseSource) {
        guard sink.isSharingActive else { return }
        for chunk in exercises.chunked(into: Self.exercisesPerEvent) where !chunk.isEmpty {
            let envelope = TrainingExercisesEnvelope(
                schemaVersion: Self.schemaVersion,
                source: source,
                exerciseCount: chunk.count,
                exercises: chunk
            )
            guard let properties = Self.properties(from: envelope) else { continue }
            sink.capture(.exercisesCreated, properties: properties)
        }
    }

    // MARK: Helpers

    /// Sorted keys make two encodings of unchanged content byte-identical, which is what the
    /// edit comparison relies on.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func properties(from value: some Encodable) -> [String: Any]? {
        guard let data = try? encoder.encode(value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Exercise names are free text; a cap keeps a pasted paragraph from riding along.
    static func cappedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    /// Weights converted from pounds are stored as long fractions; three decimals is a gram.
    static func roundedKg(_ kg: Double) -> Double {
        (kg * 1000).rounded() / 1000
    }

    private static func loadBuiltInExerciseNames() -> Set<String> {
        let names = (try? SeedDataLoader.loadExercises().map(\.name)) ?? []
        return Set(names.map(normalizedName))
    }
}

// MARK: - Payloads

struct TrainingWorkoutsEnvelope: Encodable {
    let schemaVersion: Int
    let reason: TrainingWorkoutShareReason
    let workoutCount: Int
    let workouts: [TrainingWorkoutPayload]
}

struct TrainingWorkoutPayload: Encodable, Equatable {
    let workoutId: String
    let date: Date
    let durationSeconds: Int?
    let perceivedEffort: Double?
    let fromProgram: Bool
    let excludedFromProgression: Bool
    let exercises: [TrainingWorkoutExercisePayload]
}

struct TrainingWorkoutExercisePayload: Encodable, Equatable {
    let exerciseId: String
    let name: String
    let builtIn: Bool
    let equipment: String
    let trackingType: String
    let primaryMuscle: String?
    let movementPattern: String?
    let unilateral: Bool
    let excludedFromProgression: Bool
    let sets: [TrainingSetPayload]
}

/// `completed` is sent rather than filtered on: a Copy Previous row that was never ticked still
/// carries real weight and reps (UNPERFORMED_SETS_SCOPING.md), and analysis has to drop it.
struct TrainingSetPayload: Encodable, Equatable {
    let order: Int
    let type: String
    let completed: Bool
    let weightKg: Double?
    let reps: Int?
    let leftReps: Int?
    let rightReps: Int?
    let side: String?
    let rir: Double?
    let leftRir: Double?
    let rightRir: Double?
    let rpe: Double?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let restSeconds: Int?
    let supersetGroup: Int?
    let excludedFromPrs: Bool?
    let targetWeightKg: Double?
    let targetRepMin: Int?
    let targetRepMax: Int?
    let targetRir: Int?
}

struct TrainingExercisesEnvelope: Encodable {
    let schemaVersion: Int
    let source: TrainingExerciseSource
    let exerciseCount: Int
    let exercises: [TrainingExerciseCreatedPayload]
}

struct TrainingExerciseCreatedPayload: Encodable, Equatable {
    let exerciseId: String
    let name: String
    let builtIn: Bool
    let equipment: String
    let trackingType: String
    let primaryMuscle: String?
    let secondaryMuscles: [String]
    let movementPattern: String?
    let unilateral: Bool
    let bodyweightFactor: Double
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
