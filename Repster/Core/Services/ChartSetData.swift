import Foundation

struct ChartSetData: Sendable, Equatable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let date: Date
    let weight: Double?
    let effectiveWeight: Double?
    let reps: Int?
    let prReps: Int
    let totalReps: Int
    let leftReps: Int?
    let rightReps: Int?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let e1RM: Double?
    let setType: SetType
    let cachedPRStatus: CachedPRStatus?

    var hasData: Bool {
        ((weight ?? 0) > 0 && prReps > 0) ||
        totalReps > 0 ||
        (durationSeconds ?? 0) > 0 ||
        (distanceMeters ?? 0) > 0
    }

    var volume: Double? {
        guard let ew = effectiveWeight, totalReps > 0 else { return nil }
        return ew * Double(totalReps)
    }

    init(from set: WorkoutSet) {
        self.id = set.id
        self.workoutId = set.workoutId
        self.exerciseId = set.exerciseId
        self.date = set.date
        self.weight = set.weight
        self.effectiveWeight = set.effectiveWeight
        self.reps = set.reps
        self.prReps = set.prReps
        self.totalReps = set.totalReps
        self.leftReps = set.leftReps
        self.rightReps = set.rightReps
        self.durationSeconds = set.durationSeconds
        self.distanceMeters = set.distanceMeters
        self.e1RM = set.e1RM
        self.setType = set.setType
        self.cachedPRStatus = set.cachedPRStatus
    }
}

struct ChartExerciseData: Sendable, Equatable {
    let id: UUID
    let name: String
    let primaryMuscle: String?
    let equipmentType: EquipmentType
    let bodyweightFactor: Double
    let unilateral: Bool
    let trackingType: TrackingType

    init(from exercise: Exercise) {
        self.id = exercise.id
        self.name = exercise.name
        self.primaryMuscle = exercise.primaryMuscle
        self.equipmentType = exercise.equipmentType
        self.bodyweightFactor = exercise.bodyweightFactor
        self.unilateral = exercise.unilateral
        self.trackingType = exercise.trackingType
    }

    var isBodyweightStyleExercise: Bool {
        equipmentType == .bodyweight || bodyweightFactor > 0
    }
}

struct ChartExerciseStatsData: Sendable, Equatable {
    let exerciseId: UUID
    let lastPerformedDate: Date?

    init(from stats: ExerciseStats) {
        self.exerciseId = stats.exerciseId
        self.lastPerformedDate = stats.lastPerformedDate
    }
}
