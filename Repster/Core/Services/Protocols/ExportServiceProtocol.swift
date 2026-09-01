import Foundation

struct WorkoutHistoryBackupPreview: Sendable {
    let archiveVersion: Int
    let exportedAt: Date
    let workoutCount: Int
    let exerciseCount: Int
    let setCount: Int
    let earliestWorkoutDate: Date?
    let latestWorkoutDate: Date?
    /// `nil` for a v1 archive: it does not describe templates at all, so restoring it leaves them alone.
    /// The restore screen should say so rather than implying the user is about to lose them.
    var templateCount: Int? = nil
}

struct WorkoutHistoryRestoreResult: Sendable {
    let workoutsRestored: Int
    let exercisesUpserted: Int
    let setsRestored: Int
    let skippedFatigueObservations: Int
    let skippedFatigueLearningAudits: Int
    let duration: TimeInterval
    /// `nil` when the archive predates template backup, which is not the same as "restored zero".
    let templatesRestored: Int?

    init(
        workoutsRestored: Int,
        exercisesUpserted: Int,
        setsRestored: Int,
        skippedFatigueObservations: Int,
        skippedFatigueLearningAudits: Int,
        duration: TimeInterval,
        templatesRestored: Int? = nil
    ) {
        self.workoutsRestored = workoutsRestored
        self.exercisesUpserted = exercisesUpserted
        self.setsRestored = setsRestored
        self.skippedFatigueObservations = skippedFatigueObservations
        self.skippedFatigueLearningAudits = skippedFatigueLearningAudits
        self.duration = duration
        self.templatesRestored = templatesRestored
    }

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
    case archiveVersionTooNew(Int)
    case decodingFailed(String)
    case invalidArchive(String)

    var errorDescription: String? {
        switch self {
        case .archiveVersionTooNew(let version):
            return "This backup was made by a newer version of Repster (backup format \(version)). "
                + "Update Repster, then restore it again."
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
    /// The version this build writes.
    ///
    /// v2 added `templates`. v1 archives stay readable and are the reason `templates` is optional —
    /// see the property.
    static let currentVersion = 2

    /// The oldest version this build can still read.
    ///
    /// Every `.repsterbackup` a user has saved since launch is v1, and those files are the whole
    /// point of the feature — they sit in Files and iCloud Drive indefinitely. So restore accepts
    /// anything in `minimumSupportedVersion ... currentVersion` and this constant only moves when a
    /// format genuinely stops being decodable, which is a deliberate act of dropping user backups.
    static let minimumSupportedVersion = 1

    let version: Int
    let exportedAt: Date
    let workouts: [WorkoutHistoryArchiveWorkout]
    let exercises: [WorkoutHistoryArchiveExercise]
    let sets: [WorkoutHistoryArchiveSet]
    let fatigueObservations: [WorkoutHistoryArchiveFatigueObservation]?
    let fatigueLearningAudits: [WorkoutHistoryArchiveFatigueLearningSetAudit]?
    let healthProfileLearning: WorkoutHistoryArchiveHealthProfileLearning?

    /// Workout templates, added in v2.
    ///
    /// **`nil` and `[]` mean different things and restore must branch on it.** `nil` is a v1 archive,
    /// written before templates were backed up at all — the user's templates are simply not described
    /// by this file, so restore leaves them alone. `[]` is a v2 archive from someone who genuinely had
    /// none, so restore clears them.
    ///
    /// Restore is a replace, not a merge, and every backup a user owns today is v1. Defaulting this to
    /// `[]` anywhere between decode and the delete pass would turn restoring an old backup into
    /// "delete every template". That single `?? []` is the whole bug — see
    /// TEMPLATES_IMPLEMENTATION_PLAN.md D1.
    let templates: [WorkoutHistoryArchiveTemplate]?

    /// `templates` defaults to nil so an archive constructed without it is v1-shaped — which is what
    /// it means. Only `exportBackup` passes it, and it always does.
    init(
        version: Int,
        exportedAt: Date,
        workouts: [WorkoutHistoryArchiveWorkout],
        exercises: [WorkoutHistoryArchiveExercise],
        sets: [WorkoutHistoryArchiveSet],
        fatigueObservations: [WorkoutHistoryArchiveFatigueObservation]?,
        fatigueLearningAudits: [WorkoutHistoryArchiveFatigueLearningSetAudit]?,
        healthProfileLearning: WorkoutHistoryArchiveHealthProfileLearning?,
        templates: [WorkoutHistoryArchiveTemplate]? = nil
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.workouts = workouts
        self.exercises = exercises
        self.sets = sets
        self.fatigueObservations = fatigueObservations
        self.fatigueLearningAudits = fatigueLearningAudits
        self.healthProfileLearning = healthProfileLearning
        self.templates = templates
    }
}

// MARK: - Templates (archive v2)

struct WorkoutHistoryArchiveTemplate: Codable, Sendable {
    let id: UUID
    let name: String
    let notes: String?
    let folder: String?
    let lastUsedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let exercises: [WorkoutHistoryArchiveTemplateExercise]
}

struct WorkoutHistoryArchiveTemplateExercise: Codable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let orderInTemplate: Int
    let supersetGroupId: UUID?
    let restTimeSeconds: Int?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let sets: [WorkoutHistoryArchiveTemplateSet]
}

struct WorkoutHistoryArchiveTemplateSet: Codable, Sendable {
    let id: UUID
    let setType: SetType
    let targetRepMin: Int?
    let targetRepMax: Int?
    let targetRIR: Int?
    let orderInExercise: Int
    let createdAt: Date
    let updatedAt: Date
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
    let unilateralRepTargetMode: UnilateralRepTargetMode?
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
    /// See ``FatigueLearningSetAudit/modelEpoch``.
    let modelEpoch: Int?
    /// Raw string rather than `SetType?` on purpose. `decodeIfPresent(SetType.self,…)` *throws*
    /// on an unrecognised raw value, so a backup written by a newer build carrying a set type this
    /// build doesn't know would fail the entire restore — costing the user their whole history over
    /// one optional column. Decoding the string and resolving it at the model boundary degrades to
    /// nil instead. Absent means "not captured", not `.working`.
    let setTypeRawValue: String?
    let createdAt: Date
}

struct WorkoutHistoryArchiveFatigueLearningSetAudit: Codable, Sendable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let setId: UUID
    let visibleSetNumber: Int
    /// Raw strings, not typed enums. A `Codable` enum throws on an unrecognised raw value, and
    /// because the whole archive decodes in one call, a single unknown value fails the *entire*
    /// restore — the user loses their history over one diagnostic column. Resolved leniently at
    /// the model boundary instead.
    let setType: String
    let status: String
    let suggestionUnavailableReasonRawValue: String?
    let predictedEffectiveE1RM: Double?
    let baseE1RM: Double?
    let prescribedWeight: Double?
    let actualWeight: Double?
    let actualReps: Int?
    let actualRIR: Double?
    let deviationFraction: Double?
    let normalizedError: Double?
    /// Optional Int, so it is safe in both directions: older archives simply lack it and resolve
    /// to the legacy epoch. Without it a restored epoch-2 prediction would be mislabelled as
    /// having come from the 1.x model.
    let modelEpoch: Int?
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
    /// Raw string for the same reason as the audit's: an unrecognised type must cost one column,
    /// never the whole restore. This is the core data path, so it matters most here.
    let setType: String
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
    let overrideTargetRepMin: Int?
    let overrideTargetRepMax: Int?
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
