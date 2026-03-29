import Foundation

struct WorkoutHistoryBackupPreview: Sendable {
    let archiveVersion: Int
    let exportedAt: Date
    let workoutCount: Int
    let exerciseCount: Int
    let setCount: Int
    let earliestWorkoutDate: Date?
    let latestWorkoutDate: Date?
}

struct WorkoutHistoryRestoreResult: Sendable {
    let workoutsRestored: Int
    let exercisesUpserted: Int
    let setsRestored: Int
    let skippedFatigueObservations: Int
    let skippedFatigueLearningAudits: Int
    let duration: TimeInterval

    var hasSkippedLearningData: Bool {
        skippedFatigueObservations > 0 || skippedFatigueLearningAudits > 0
    }

    var learningDataWarningMessage: String? {
        guard hasSkippedLearningData else { return nil }
        return "Some fatigue learning data could not be restored. Skipped \(skippedFatigueObservations) observation(s) and \(skippedFatigueLearningAudits) audit record(s) because they referenced missing workout history."
    }
}

enum WorkoutHistoryBackupError: Error, LocalizedError, Sendable {
    case invalidArchiveVersion(Int)
    case decodingFailed(String)
    case invalidArchive(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchiveVersion(let version):
            return "Unsupported backup version: \(version)."
        case .decodingFailed(let message):
            return "Failed to read backup file: \(message)"
        case .invalidArchive(let message):
            return "Invalid backup archive: \(message)"
        }
    }
}

struct WorkoutHistoryArchive: Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let workouts: [WorkoutHistoryArchiveWorkout]
    let exercises: [WorkoutHistoryArchiveExercise]
    let sets: [WorkoutHistoryArchiveSet]
    let fatigueObservations: [WorkoutHistoryArchiveFatigueObservation]?
    let fatigueLearningAudits: [WorkoutHistoryArchiveFatigueLearningSetAudit]?
    let healthProfileLearning: WorkoutHistoryArchiveHealthProfileLearning?
}

struct WorkoutHistoryArchiveWorkout: Codable, Sendable {
    let id: UUID
    let date: Date
    let title: String?
    let startTime: Date?
    let endTime: Date?
    let duration: Int?
    let perceivedEffort: Double?
    let notes: String?
    let programId: UUID?
    let status: WorkoutStatus
    let excludeFromProgressionHistory: Bool?
    let excludedExerciseIdsFromProgressionHistory: [UUID]?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        date: Date,
        title: String?,
        startTime: Date?,
        endTime: Date?,
        duration: Int?,
        perceivedEffort: Double?,
        notes: String?,
        programId: UUID?,
        status: WorkoutStatus,
        excludeFromProgressionHistory: Bool?,
        excludedExerciseIdsFromProgressionHistory: [UUID]?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.perceivedEffort = perceivedEffort
        self.notes = notes
        self.programId = programId
        self.status = status
        self.excludeFromProgressionHistory = excludeFromProgressionHistory
        self.excludedExerciseIdsFromProgressionHistory = excludedExerciseIdsFromProgressionHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case title
        case startTime
        case endTime
        case duration
        case perceivedEffort
        case notes
        case programId
        case status
        case excludeFromProgressionHistory
        case excludedExerciseIdsFromProgressionHistory
        case excludeFromPRsAndSuggestions
        case excludedExerciseIdsFromPRsAndSuggestions
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        perceivedEffort = try container.decodeIfPresent(Double.self, forKey: .perceivedEffort)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        programId = try container.decodeIfPresent(UUID.self, forKey: .programId)
        status = try container.decode(WorkoutStatus.self, forKey: .status)
        excludeFromProgressionHistory =
            try container.decodeIfPresent(Bool.self, forKey: .excludeFromProgressionHistory)
            ?? (try container.decodeIfPresent(Bool.self, forKey: .excludeFromPRsAndSuggestions))
        excludedExerciseIdsFromProgressionHistory =
            try container.decodeIfPresent([UUID].self, forKey: .excludedExerciseIdsFromProgressionHistory)
            ?? (try container.decodeIfPresent([UUID].self, forKey: .excludedExerciseIdsFromPRsAndSuggestions))
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(perceivedEffort, forKey: .perceivedEffort)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(programId, forKey: .programId)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(excludeFromProgressionHistory, forKey: .excludeFromProgressionHistory)
        try container.encodeIfPresent(
            excludedExerciseIdsFromProgressionHistory,
            forKey: .excludedExerciseIdsFromProgressionHistory
        )
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct WorkoutHistoryArchiveExercise: Codable, Sendable {
    let id: UUID
    let name: String
    let equipmentType: EquipmentType
    let trackingType: TrackingType
    let primaryMuscle: String?
    let secondaryMuscles: [String]
    let movementPattern: MovementPattern?
    let unilateral: Bool
    let bilateralLoadFactor: Double?
    let bodyweightFactor: Double
    let weightIncrement: Double?
    let defaultRestTime: Int?
    let fatigueRate: Double?
    let fatigueRateSourceRawValue: String?
    let recoveryConstant: Double?
    let fatigueLearningSessionCount: Int?
    let fatigueLearningCumulativeError: Double?
    let createdAt: Date
    let updatedAt: Date
}

struct WorkoutHistoryArchiveFatigueObservation: Codable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let workoutId: UUID
    let setId: UUID
    let setIndex: Int
    let predictedEffectiveE1RM: Double
    let actualE1RM: Double
    let normalizedError: Double
    let baseE1RM: Double
    let prescribedWeight: Double
    let actualWeight: Double
    let actualReps: Int
    let actualRIR: Double
    let restDurationSeconds: Int?
    let createdAt: Date
}

struct WorkoutHistoryArchiveFatigueLearningSetAudit: Codable, Sendable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let setId: UUID
    let visibleSetNumber: Int
    let setType: SetType
    let status: FatigueLearningAuditStatus
    let suggestionUnavailableReasonRawValue: String?
    let predictedEffectiveE1RM: Double?
    let baseE1RM: Double?
    let prescribedWeight: Double?
    let actualWeight: Double?
    let actualReps: Int?
    let actualRIR: Double?
    let deviationFraction: Double?
    let normalizedError: Double?
    let createdAt: Date
}

struct WorkoutHistoryArchiveHealthProfileLearning: Codable, Sendable {
    let prescriptionLearnedFatigueRate: Double?
    let prescriptionFatigueLearningSessionCount: Int?
    let prescriptionFatigueLearningCumulativeError: Double?
}

struct WorkoutHistoryArchiveSet: Codable, Sendable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let date: Date
    let startedAt: Date?
    let completedAt: Date?
    let weight: Double?
    let effectiveWeight: Double?
    let reps: Int?
    let leftReps: Int?
    let rightReps: Int?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let e1RM: Double?
    let e1RMFormulaVersion: String?
    let rpe: Double?
    let rir: Double?
    let leftRIR: Double?
    let rightRIR: Double?
    let setType: SetType
    let pauseDuration: Int?
    let side: Side?
    let notes: String?
    let orderInWorkout: Int
    let orderInExercise: Int
    let supersetGroupId: UUID?
    let completed: Bool
    let excludeFromPRs: Bool?
    let cachedPRStatus: CachedPRStatus?
    let targetWeight: Double?
    let targetRepMin: Int?
    let targetRepMax: Int?
    let targetRPE: Double?
    let targetRIR: Int?
    let createdAt: Date
    let updatedAt: Date
    let restDurationSeconds: Int?
}

protocol WorkoutHistoryBackupServiceProtocol: Sendable {
    func exportBackup() async throws -> Data
    func previewBackup(data: Data) throws -> WorkoutHistoryBackupPreview
    func restoreBackup(data: Data) async throws -> WorkoutHistoryRestoreResult
}
