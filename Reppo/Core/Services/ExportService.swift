import Foundation
import SwiftData

actor WorkoutHistoryBackupService: WorkoutHistoryBackupServiceProtocol {

    private struct ArchiveCoreReferences {
        let workoutIds: Set<UUID>
        let exerciseIds: Set<UUID>
        let setsById: [UUID: WorkoutHistoryArchiveSet]
    }

    private struct SanitizedLearningArchiveData {
        let observations: [WorkoutHistoryArchiveFatigueObservation]
        let audits: [WorkoutHistoryArchiveFatigueLearningSetAudit]
        let skippedObservationCount: Int
        let skippedAuditCount: Int
    }

    // MARK: - Dependencies

    private let workoutRepo: any WorkoutRepositoryProtocol
    private let exerciseRepo: any ExerciseRepositoryProtocol
    private let setRepo: any SetRepositoryProtocol
    private let fatigueObservationRepo: any FatigueObservationRepositoryProtocol
    private let fatigueLearningAuditRepo: any FatigueLearningSetAuditRepositoryProtocol
    private let statsService: any StatsServiceProtocol
    private let prService: any PRServiceProtocol
    private let modelContainer: ModelContainer

    // MARK: - Init

    init(
        workoutRepo: any WorkoutRepositoryProtocol,
        exerciseRepo: any ExerciseRepositoryProtocol,
        setRepo: any SetRepositoryProtocol,
        fatigueObservationRepo: any FatigueObservationRepositoryProtocol,
        fatigueLearningAuditRepo: any FatigueLearningSetAuditRepositoryProtocol,
        statsService: any StatsServiceProtocol,
        prService: any PRServiceProtocol,
        modelContainer: ModelContainer
    ) {
        self.workoutRepo = workoutRepo
        self.exerciseRepo = exerciseRepo
        self.setRepo = setRepo
        self.fatigueObservationRepo = fatigueObservationRepo
        self.fatigueLearningAuditRepo = fatigueLearningAuditRepo
        self.statsService = statsService
        self.prService = prService
        self.modelContainer = modelContainer
    }

    // MARK: - WorkoutHistoryBackupServiceProtocol

    func exportBackup() async throws -> Data {
        let workouts = try await sortedWorkouts()
        let allSets = try await setRepo.fetchSets(from: .distantPast, to: .distantFuture)
        let exerciseIds = Set(allSets.map(\.exerciseId))
        let exercises = try await exerciseRepo.fetchAll()
            .filter { exerciseIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let workoutIndex = Dictionary(uniqueKeysWithValues: workouts.enumerated().map { ($0.element.id, $0.offset) })
        let sortedSets = allSets.sorted { lhs, rhs in
            let lhsWorkoutOrder = workoutIndex[lhs.workoutId] ?? .max
            let rhsWorkoutOrder = workoutIndex[rhs.workoutId] ?? .max
            if lhsWorkoutOrder != rhsWorkoutOrder { return lhsWorkoutOrder < rhsWorkoutOrder }
            if lhs.orderInWorkout != rhs.orderInWorkout { return lhs.orderInWorkout < rhs.orderInWorkout }
            return lhs.createdAt < rhs.createdAt
        }

        // Fetch fatigue observations
        let observationContext = ModelContext(modelContainer)
        let allObservations = try observationContext.fetch(FetchDescriptor<FatigueObservation>())
            .sorted { $0.createdAt < $1.createdAt }
        let allAudits = try observationContext.fetch(FetchDescriptor<FatigueLearningSetAudit>())
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.visibleSetNumber < rhs.visibleSetNumber
            }
        let healthProfile = try observationContext.fetch(FetchDescriptor<HealthProfile>()).first

        let archiveWorkouts = workouts.map(WorkoutHistoryArchiveWorkout.init)
        let archiveExercises = exercises.map(WorkoutHistoryArchiveExercise.init)
        let archiveSets = sortedSets.map(WorkoutHistoryArchiveSet.init)
        let coreReferences = try validateCoreArchive(
            workouts: archiveWorkouts,
            exercises: archiveExercises,
            sets: archiveSets
        )
        let sanitizedLearningData = sanitizeLearningData(
            observations: allObservations.map(WorkoutHistoryArchiveFatigueObservation.init),
            audits: allAudits.map(WorkoutHistoryArchiveFatigueLearningSetAudit.init),
            coreReferences: coreReferences
        )

        let archive = WorkoutHistoryArchive(
            version: WorkoutHistoryArchive.currentVersion,
            exportedAt: Date(),
            workouts: archiveWorkouts,
            exercises: archiveExercises,
            sets: archiveSets,
            fatigueObservations: sanitizedLearningData.observations,
            fatigueLearningAudits: sanitizedLearningData.audits,
            healthProfileLearning: healthProfile.map(WorkoutHistoryArchiveHealthProfileLearning.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    nonisolated func previewBackup(data: Data) throws -> WorkoutHistoryBackupPreview {
        let archive = try decodeArchive(data)
        let dates = archive.workouts.map(\.date).sorted()

        return WorkoutHistoryBackupPreview(
            archiveVersion: archive.version,
            exportedAt: archive.exportedAt,
            workoutCount: archive.workouts.count,
            exerciseCount: archive.exercises.count,
            setCount: archive.sets.count,
            earliestWorkoutDate: dates.first,
            latestWorkoutDate: dates.last
        )
    }

    func restoreBackup(data: Data) async throws -> WorkoutHistoryRestoreResult {
        let archive = try decodeArchive(data)
        let coreReferences = try validateCoreArchive(archive)
        let sanitizedLearningData = sanitizeLearningData(
            observations: archive.fatigueObservations ?? [],
            audits: archive.fatigueLearningAudits ?? [],
            coreReferences: coreReferences
        )

        let start = Date()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        // Apply the replace-history mutation in a single save so restore is all-or-nothing.
        let existingSets = try context.fetch(FetchDescriptor<WorkoutSet>())
        for set in existingSets {
            context.delete(set)
        }

        let existingWorkouts = try context.fetch(FetchDescriptor<Workout>())
        for workout in existingWorkouts {
            context.delete(workout)
        }

        let existingStats = try context.fetch(FetchDescriptor<ExerciseStats>())
        for stats in existingStats {
            context.delete(stats)
        }

        let existingRecords = try context.fetch(FetchDescriptor<PerformanceRecord>())
        for record in existingRecords {
            context.delete(record)
        }

        let fetchedExercises = try context.fetch(FetchDescriptor<Exercise>())
        var exercisesById = Dictionary(uniqueKeysWithValues: fetchedExercises.map { ($0.id, $0) })

        for archivedExercise in archive.exercises {
            if let existing = exercisesById[archivedExercise.id] {
                existing.applyArchive(archivedExercise)
            } else {
                let exercise = archivedExercise.makeModel()
                context.insert(exercise)
                exercisesById[exercise.id] = exercise
            }
        }

        let sortedWorkouts = archive.workouts.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.createdAt < $1.createdAt
        }
        for archivedWorkout in sortedWorkouts {
            context.insert(archivedWorkout.makeModel())
        }

        let sortedSets = archive.sets.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.orderInWorkout != $1.orderInWorkout { return $0.orderInWorkout < $1.orderInWorkout }
            return $0.createdAt < $1.createdAt
        }
        for archivedSet in sortedSets {
            context.insert(archivedSet.makeModel())
        }

        // Restore fatigue observations (delete existing, insert from archive)
        let existingObservations = try context.fetch(FetchDescriptor<FatigueObservation>())
        for obs in existingObservations {
            context.delete(obs)
        }
        for archivedObs in sanitizedLearningData.observations {
            context.insert(archivedObs.makeModel())
        }

        let existingAudits = try context.fetch(FetchDescriptor<FatigueLearningSetAudit>())
        for audit in existingAudits {
            context.delete(audit)
        }
        for archivedAudit in sanitizedLearningData.audits {
            context.insert(archivedAudit.makeModel())
        }

        try context.save()

        if let healthProfileLearning = archive.healthProfileLearning {
            let profileContext = ModelContext(modelContainer)
            let profile = try fetchOrCreateHealthProfile(in: profileContext)
            healthProfileLearning.apply(to: profile)
            profile.updatedAt = Date()
            try profileContext.save()
        }

        try await statsService.rebuildAll()
        try await prService.rebuildAll()

        return WorkoutHistoryRestoreResult(
            workoutsRestored: archive.workouts.count,
            exercisesUpserted: archive.exercises.count,
            setsRestored: archive.sets.count,
            skippedFatigueObservations: sanitizedLearningData.skippedObservationCount,
            skippedFatigueLearningAudits: sanitizedLearningData.skippedAuditCount,
            duration: Date().timeIntervalSince(start)
        )
    }

    // MARK: - Helpers

    private func sortedWorkouts() async throws -> [Workout] {
        let workouts = try await workoutRepo.fetchAllWorkouts(limit: nil, offset: nil)
        return workouts.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.createdAt < $1.createdAt
        }
    }

    private nonisolated func decodeArchive(_ data: Data) throws -> WorkoutHistoryArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let archive: WorkoutHistoryArchive
        do {
            archive = try decoder.decode(WorkoutHistoryArchive.self, from: data)
        } catch {
            throw WorkoutHistoryBackupError.decodingFailed(error.localizedDescription)
        }

        guard archive.version == WorkoutHistoryArchive.currentVersion else {
            throw WorkoutHistoryBackupError.invalidArchiveVersion(archive.version)
        }

        return archive
    }

    private nonisolated func validateCoreArchive(_ archive: WorkoutHistoryArchive) throws -> ArchiveCoreReferences {
        try validateCoreArchive(
            workouts: archive.workouts,
            exercises: archive.exercises,
            sets: archive.sets
        )
    }

    private nonisolated func validateCoreArchive(
        workouts: [WorkoutHistoryArchiveWorkout],
        exercises: [WorkoutHistoryArchiveExercise],
        sets: [WorkoutHistoryArchiveSet]
    ) throws -> ArchiveCoreReferences {
        let workoutIds = Set(workouts.map(\.id))
        guard workoutIds.count == workouts.count else {
            throw WorkoutHistoryBackupError.invalidArchive("Duplicate workout IDs found.")
        }

        let exerciseIds = Set(exercises.map(\.id))
        guard exerciseIds.count == exercises.count else {
            throw WorkoutHistoryBackupError.invalidArchive("Duplicate exercise IDs found.")
        }

        let setIds = Set(sets.map(\.id))
        guard setIds.count == sets.count else {
            throw WorkoutHistoryBackupError.invalidArchive("Duplicate set IDs found.")
        }

        for set in sets {
            guard workoutIds.contains(set.workoutId) else {
                throw WorkoutHistoryBackupError.invalidArchive("Set \(set.id) references a missing workout.")
            }
            guard exerciseIds.contains(set.exerciseId) else {
                throw WorkoutHistoryBackupError.invalidArchive("Set \(set.id) references a missing exercise.")
            }
        }

        return ArchiveCoreReferences(
            workoutIds: workoutIds,
            exerciseIds: exerciseIds,
            setsById: Dictionary(uniqueKeysWithValues: sets.map { ($0.id, $0) })
        )
    }

    private nonisolated func sanitizeLearningData(
        observations: [WorkoutHistoryArchiveFatigueObservation],
        audits: [WorkoutHistoryArchiveFatigueLearningSetAudit],
        coreReferences: ArchiveCoreReferences
    ) -> SanitizedLearningArchiveData {
        let validObservations = observations.filter { observation in
            guard coreReferences.workoutIds.contains(observation.workoutId),
                  coreReferences.exerciseIds.contains(observation.exerciseId),
                  let archivedSet = coreReferences.setsById[observation.setId] else {
                return false
            }

            return archivedSet.workoutId == observation.workoutId
                && archivedSet.exerciseId == observation.exerciseId
        }

        let validAudits = audits.filter { audit in
            guard coreReferences.workoutIds.contains(audit.workoutId),
                  coreReferences.exerciseIds.contains(audit.exerciseId),
                  let archivedSet = coreReferences.setsById[audit.setId] else {
                return false
            }

            return archivedSet.workoutId == audit.workoutId
                && archivedSet.exerciseId == audit.exerciseId
        }

        return SanitizedLearningArchiveData(
            observations: validObservations,
            audits: validAudits,
            skippedObservationCount: observations.count - validObservations.count,
            skippedAuditCount: audits.count - validAudits.count
        )
    }

    private func fetchOrCreateHealthProfile(in context: ModelContext) throws -> HealthProfile {
        if let existing = try context.fetch(FetchDescriptor<HealthProfile>()).first {
            return existing
        }
        let profile = HealthProfile()
        context.insert(profile)
        try context.save()
        return profile
    }
}

private extension WorkoutHistoryArchiveWorkout {
    init(_ workout: Workout) {
        self.init(
            id: workout.id,
            date: workout.date,
            title: workout.title,
            startTime: workout.startTime,
            endTime: workout.endTime,
            duration: workout.duration,
            perceivedEffort: workout.perceivedEffort,
            notes: workout.notes,
            programId: workout.programId,
            status: workout.status,
            excludeFromProgressionHistory: workout.excludeFromProgressionHistory,
            excludedExerciseIdsFromProgressionHistory: workout.excludedExerciseIdsFromProgressionHistory,
            createdAt: workout.createdAt,
            updatedAt: workout.updatedAt
        )
    }

    func makeModel() -> Workout {
        Workout(
            id: id,
            date: date,
            title: title,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            perceivedEffort: perceivedEffort,
            notes: notes,
            programId: programId,
            status: status,
            excludeFromProgressionHistory: excludeFromProgressionHistory,
            excludedExerciseIdsFromProgressionHistory: excludedExerciseIdsFromProgressionHistory,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private extension WorkoutHistoryArchiveExercise {
    init(_ exercise: Exercise) {
        self.init(
            id: exercise.id,
            name: exercise.name,
            equipmentType: exercise.equipmentType,
            trackingType: exercise.trackingType,
            primaryMuscle: exercise.primaryMuscle,
            secondaryMuscles: exercise.secondaryMuscles,
            movementPattern: exercise.movementPattern,
            unilateral: exercise.unilateral,
            bilateralLoadFactor: exercise.bilateralLoadFactor,
            bodyweightFactor: exercise.bodyweightFactor,
            weightIncrement: exercise.weightIncrement,
            defaultRestTime: exercise.defaultRestTime,
            fatigueRate: exercise.fatigueRate,
            fatigueRateSourceRawValue: exercise.resolvedFatigueRateSource?.rawValue,
            recoveryConstant: exercise.recoveryConstant,
            fatigueLearningSessionCount: exercise.fatigueLearningSessionCount,
            fatigueLearningCumulativeError: exercise.fatigueLearningCumulativeError,
            createdAt: exercise.createdAt,
            updatedAt: exercise.updatedAt
        )
    }

    func makeModel() -> Exercise {
        let exercise = Exercise(
            id: id,
            name: name,
            equipmentType: equipmentType,
            trackingType: trackingType,
            primaryMuscle: primaryMuscle,
            secondaryMuscles: secondaryMuscles,
            movementPattern: movementPattern,
            unilateral: unilateral,
            bilateralLoadFactor: bilateralLoadFactor,
            bodyweightFactor: bodyweightFactor,
            weightIncrement: weightIncrement,
            defaultRestTime: defaultRestTime,
            fatigueRate: fatigueRate,
            fatigueRateSourceRawValue: fatigueRateSourceRawValue,
            recoveryConstant: recoveryConstant,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        exercise.fatigueLearningSessionCount = fatigueLearningSessionCount
        exercise.fatigueLearningCumulativeError = fatigueLearningCumulativeError
        return exercise
    }
}

private extension Exercise {
    func applyArchive(_ archive: WorkoutHistoryArchiveExercise) {
        name = archive.name
        equipmentType = archive.equipmentType
        trackingType = archive.trackingType
        primaryMuscle = archive.primaryMuscle
        secondaryMuscles = archive.secondaryMuscles
        movementPattern = archive.movementPattern
        unilateral = archive.unilateral
        bilateralLoadFactor = archive.bilateralLoadFactor
        bodyweightFactor = archive.bodyweightFactor
        weightIncrement = archive.weightIncrement
        defaultRestTime = archive.defaultRestTime
        fatigueRate = archive.fatigueRate
        fatigueRateSourceRawValue = archive.fatigueRateSourceRawValue
        recoveryConstant = archive.recoveryConstant
        fatigueLearningSessionCount = archive.fatigueLearningSessionCount
        fatigueLearningCumulativeError = archive.fatigueLearningCumulativeError
        createdAt = archive.createdAt
        updatedAt = archive.updatedAt
    }
}

private extension WorkoutHistoryArchiveSet {
    init(_ set: WorkoutSet) {
        self.init(
            id: set.id,
            workoutId: set.workoutId,
            exerciseId: set.exerciseId,
            date: set.date,
            startedAt: set.startedAt,
            completedAt: set.completedAt,
            weight: set.weight,
            effectiveWeight: set.effectiveWeight,
            reps: set.reps,
            leftReps: set.leftReps,
            rightReps: set.rightReps,
            durationSeconds: set.durationSeconds,
            distanceMeters: set.distanceMeters,
            e1RM: set.e1RM,
            e1RMFormulaVersion: set.e1RMFormulaVersion,
            rpe: set.rpe,
            rir: set.rir,
            leftRIR: set.leftRIR,
            rightRIR: set.rightRIR,
            setType: set.setType,
            pauseDuration: set.pauseDuration,
            side: set.side,
            notes: set.notes,
            orderInWorkout: set.orderInWorkout,
            orderInExercise: set.orderInExercise,
            supersetGroupId: set.supersetGroupId,
            completed: set.completed,
            excludeFromPRs: set.excludeFromPRs,
            cachedPRStatus: set.cachedPRStatus,
            targetWeight: set.targetWeight,
            targetRepMin: set.targetRepMin,
            targetRepMax: set.targetRepMax,
            targetRPE: set.targetRPE,
            targetRIR: set.targetRIR,
            createdAt: set.createdAt,
            updatedAt: set.updatedAt,
            restDurationSeconds: set.restDurationSeconds
        )
    }

    func makeModel() -> WorkoutSet {
        WorkoutSet(
            id: id,
            workoutId: workoutId,
            exerciseId: exerciseId,
            date: date,
            startedAt: startedAt,
            completedAt: completedAt,
            weight: weight,
            effectiveWeight: effectiveWeight,
            reps: reps,
            leftReps: leftReps,
            rightReps: rightReps,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            e1RM: e1RM,
            e1RMFormulaVersion: e1RMFormulaVersion,
            rpe: rpe,
            rir: rir,
            leftRIR: leftRIR,
            rightRIR: rightRIR,
            setType: setType,
            pauseDuration: pauseDuration,
            side: side,
            notes: notes,
            orderInWorkout: orderInWorkout,
            orderInExercise: orderInExercise,
            supersetGroupId: supersetGroupId,
            completed: completed,
            excludeFromPRs: excludeFromPRs,
            cachedPRStatus: cachedPRStatus,
            targetWeight: targetWeight,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            targetRPE: targetRPE,
            targetRIR: targetRIR,
            createdAt: createdAt,
            updatedAt: updatedAt,
            restDurationSeconds: restDurationSeconds
        )
    }
}

private extension WorkoutHistoryArchiveFatigueObservation {
    init(_ obs: FatigueObservation) {
        self.init(
            id: obs.id,
            exerciseId: obs.exerciseId,
            workoutId: obs.workoutId,
            setId: obs.setId,
            setIndex: obs.setIndex,
            predictedEffectiveE1RM: obs.predictedEffectiveE1RM,
            actualE1RM: obs.actualE1RM,
            normalizedError: obs.normalizedError,
            baseE1RM: obs.baseE1RM,
            prescribedWeight: obs.prescribedWeight,
            actualWeight: obs.actualWeight,
            actualReps: obs.actualReps,
            actualRIR: obs.actualRIR,
            restDurationSeconds: obs.restDurationSeconds,
            createdAt: obs.createdAt
        )
    }

    func makeModel() -> FatigueObservation {
        FatigueObservation(
            id: id,
            exerciseId: exerciseId,
            workoutId: workoutId,
            setId: setId,
            setIndex: setIndex,
            predictedEffectiveE1RM: predictedEffectiveE1RM,
            actualE1RM: actualE1RM,
            normalizedError: normalizedError,
            baseE1RM: baseE1RM,
            prescribedWeight: prescribedWeight,
            actualWeight: actualWeight,
            actualReps: actualReps,
            actualRIR: actualRIR,
            restDurationSeconds: restDurationSeconds,
            createdAt: createdAt
        )
    }
}

private extension WorkoutHistoryArchiveFatigueLearningSetAudit {
    init(_ audit: FatigueLearningSetAudit) {
        self.init(
            id: audit.id,
            workoutId: audit.workoutId,
            exerciseId: audit.exerciseId,
            setId: audit.setId,
            visibleSetNumber: audit.visibleSetNumber,
            setType: audit.setType,
            status: audit.status,
            suggestionUnavailableReasonRawValue: audit.suggestionUnavailableReasonRawValue,
            predictedEffectiveE1RM: audit.predictedEffectiveE1RM,
            baseE1RM: audit.baseE1RM,
            prescribedWeight: audit.prescribedWeight,
            actualWeight: audit.actualWeight,
            actualReps: audit.actualReps,
            actualRIR: audit.actualRIR,
            deviationFraction: audit.deviationFraction,
            normalizedError: audit.normalizedError,
            createdAt: audit.createdAt
        )
    }

    func makeModel() -> FatigueLearningSetAudit {
        FatigueLearningSetAudit(
            id: id,
            workoutId: workoutId,
            exerciseId: exerciseId,
            setId: setId,
            visibleSetNumber: visibleSetNumber,
            setType: setType,
            status: status,
            suggestionUnavailableReason: suggestionUnavailableReasonRawValue.flatMap(SuggestionUnavailableReason.init(rawValue:)),
            predictedEffectiveE1RM: predictedEffectiveE1RM,
            baseE1RM: baseE1RM,
            prescribedWeight: prescribedWeight,
            actualWeight: actualWeight,
            actualReps: actualReps,
            actualRIR: actualRIR,
            deviationFraction: deviationFraction,
            normalizedError: normalizedError,
            createdAt: createdAt
        )
    }
}

private extension WorkoutHistoryArchiveHealthProfileLearning {
    init(_ profile: HealthProfile) {
        self.init(
            prescriptionLearnedFatigueRate: profile.prescriptionLearnedFatigueRate,
            prescriptionFatigueLearningSessionCount: profile.prescriptionFatigueLearningSessionCount,
            prescriptionFatigueLearningCumulativeError: profile.prescriptionFatigueLearningCumulativeError
        )
    }

    func apply(to profile: HealthProfile) {
        profile.prescriptionLearnedFatigueRate = prescriptionLearnedFatigueRate
        profile.prescriptionFatigueLearningSessionCount = prescriptionFatigueLearningSessionCount
        profile.prescriptionFatigueLearningCumulativeError = prescriptionFatigueLearningCumulativeError
    }
}
