import XCTest
@testable import Repster

final class FatigueLearningServiceTests: XCTestCase {

    // MARK: - Pure Helpers

    func testNormalizedError_modelTooAggressive_returnsNegative() {
        let error = FatigueLearningService.computeNormalizedError(
            predicted: 130.0,
            actual: 140.0,
            base: 150.0
        )

        XCTAssertEqual(error, -10.0 / 150.0, accuracy: 0.0001)
        XCTAssertLessThan(error, 0)
    }

    func testNormalizedError_modelTooLenient_returnsPositive() {
        let error = FatigueLearningService.computeNormalizedError(
            predicted: 145.0,
            actual: 135.0,
            base: 150.0
        )

        XCTAssertEqual(error, 10.0 / 150.0, accuracy: 0.0001)
        XCTAssertGreaterThan(error, 0)
    }

    func testNormalizedError_perfectPrediction_returnsZero() {
        let error = FatigueLearningService.computeNormalizedError(
            predicted: 140.0,
            actual: 140.0,
            base: 150.0
        )

        XCTAssertEqual(error, 0.0, accuracy: 0.0001)
    }

    func testNormalizedError_zeroBase_returnsZero() {
        let error = FatigueLearningService.computeNormalizedError(
            predicted: 140.0,
            actual: 130.0,
            base: 0.0
        )

        XCTAssertEqual(error, 0.0)
    }

    func testMedianError_oddCount() {
        XCTAssertEqual(FatigueLearningService.medianError([-0.05, -0.02, -0.08]), -0.05, accuracy: 0.0001)
    }

    func testMedianError_evenCount() {
        XCTAssertEqual(FatigueLearningService.medianError([-0.05, -0.02, -0.08, -0.01]), -0.035, accuracy: 0.0001)
    }

    func testMedianError_singleValue() {
        XCTAssertEqual(FatigueLearningService.medianError([-0.03]), -0.03, accuracy: 0.0001)
    }

    func testMedianError_emptyArray() {
        XCTAssertEqual(FatigueLearningService.medianError([]), 0.0)
    }

    func testMedianError_robustToOutliers() {
        XCTAssertEqual(FatigueLearningService.medianError([-0.03, -0.04, -0.50, -0.02, -0.05]), -0.04, accuracy: 0.0001)
    }

    // MARK: - Deterministic Capture

    func testCaptureCompletedSet_recordsUsedAuditAndObservation() async throws {
        let observationRepo = InMemoryFatigueObservationRepo()
        let auditRepo = InMemoryFatigueLearningSetAuditRepo()
        let service = makeService(observationRepo: observationRepo, auditRepo: auditRepo)

        let result = try await capture(
            with: service,
            actualWeight: 115,
            actualReps: 10,
            actualRIR: 0
        )

        XCTAssertEqual(result.audit.status, .used)
        XCTAssertNotNil(result.observation)
        XCTAssertEqual(observationRepo.observations.count, 1)
        XCTAssertEqual(auditRepo.audits.count, 1)

        let expectedActualE1RM = 115.0 * (1.0 + 10.0 / 30.0)
        XCTAssertEqual(result.observation?.actualE1RM ?? 0, expectedActualE1RM, accuracy: 0.01)
        XCTAssertLessThan(result.observation?.normalizedError ?? 0, 0)
    }

    func testCaptureCompletedSet_recordsAllSkippedStatuses() async throws {
        let observationRepo = InMemoryFatigueObservationRepo()
        let auditRepo = InMemoryFatigueLearningSetAuditRepo()
        let service = makeService(observationRepo: observationRepo, auditRepo: auditRepo)

        let scenarios: [(String, FatigueLearningAuditStatus, () async throws -> FatigueLearningCaptureResult)] = [
            (
                "warmup",
                .warmupNotTracked,
                { try await self.capture(with: service, setType: .warmup) }
            ),
            (
                "baseline",
                .baselineFirstWorkingSet,
                { try await self.capture(with: service, priorCompletedWorkingSetCount: 0) }
            ),
            (
                "suggestion unavailable",
                .suggestionUnavailable,
                {
                    try await self.capture(
                        with: service,
                        suggestionUnavailableReason: .noStrengthData,
                        prediction: nil
                    )
                }
            ),
            (
                "missing RIR",
                .missingRIR,
                { try await self.capture(with: service, actualRIR: nil) }
            ),
            (
                "invalid performance",
                .invalidPerformance,
                { try await self.capture(with: service, actualWeight: nil) }
            ),
            (
                "deviation over 20 percent",
                .weightDeviationOver20Percent,
                { try await self.capture(with: service, actualWeight: 135) }
            ),
        ]

        for (name, expectedStatus, runScenario) in scenarios {
            let result = try await runScenario()
            XCTAssertEqual(result.audit.status, expectedStatus, name)
            XCTAssertNil(result.observation, name)
        }

        XCTAssertEqual(observationRepo.observations.count, 0)
        XCTAssertEqual(auditRepo.audits.count, scenarios.count)
    }

    func testCaptureCompletedSet_replacesExistingObservationForSameSet() async throws {
        let setId = UUID()
        let observationRepo = InMemoryFatigueObservationRepo()
        let auditRepo = InMemoryFatigueLearningSetAuditRepo()
        let service = makeService(observationRepo: observationRepo, auditRepo: auditRepo)

        _ = try await capture(with: service, setId: setId, actualWeight: 110, actualReps: 10, actualRIR: 0)
        _ = try await capture(with: service, setId: setId, actualWeight: 112.5, actualReps: 10, actualRIR: 0)

        XCTAssertEqual(observationRepo.observations.count, 1)
        XCTAssertEqual(auditRepo.audits.count, 1)
        XCTAssertEqual(observationRepo.observations.first?.actualWeight, 112.5)
    }

    // MARK: - Session-End Learning

    func testProcessSessionEnd_updatesGlobalBaselineFromTwoUsedSetsAcrossWorkout() async throws {
        let workoutId = UUID()
        let chest = Exercise(name: "Chest Press", equipmentType: .machinePin, trackingType: .weightReps)
        let row = Exercise(name: "Row", equipmentType: .machinePin, trackingType: .weightReps)
        let exerciseRepo = InMemoryExerciseRepo(exercises: [chest, row])
        let profileRepo = InMemoryHealthProfileRepo(profile: HealthProfile())
        let auditRepo = InMemoryFatigueLearningSetAuditRepo(
            audits: [
                makeUsedAudit(exerciseId: chest.id, workoutId: workoutId, visibleSetNumber: 2, normalizedError: -0.06),
                makeUsedAudit(exerciseId: row.id, workoutId: workoutId, visibleSetNumber: 2, normalizedError: -0.02)
            ]
        )
        let service = makeService(
            exerciseRepo: exerciseRepo,
            healthProfileRepo: profileRepo,
            auditRepo: auditRepo
        )

        await service.processSessionEnd(workoutId: workoutId)

        let profile = try await profileRepo.fetchOrCreate()
        XCTAssertEqual(profile.prescriptionFatigueLearningSessionCount, 1)
        XCTAssertEqual(profile.prescriptionLearnedFatigueRate ?? 0, 0.028, accuracy: 0.0001)
        XCTAssertLessThan(profile.prescriptionFatigueLearningCumulativeError ?? 0, 0)
        XCTAssertEqual(chest.fatigueLearningSessionCount, 1)
        XCTAssertEqual(row.fatigueLearningSessionCount, 1)
        XCTAssertEqual(chest.fatigueRate ?? 0, 0.026, accuracy: 0.0001)
        XCTAssertEqual(row.fatigueRate ?? 0, 0.026, accuracy: 0.0001)
    }

    func testProcessSessionEnd_qualifiesLocalLearningWithOneUsedSetWithoutUpdatingGlobalBaseline() async throws {
        let workoutId = UUID()
        let exercise = Exercise(name: "Leg Extension", equipmentType: .machinePin, trackingType: .weightReps)
        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let auditRepo = InMemoryFatigueLearningSetAuditRepo(
            audits: [makeUsedAudit(exerciseId: exercise.id, workoutId: workoutId, visibleSetNumber: 2, normalizedError: -0.05)]
        )
        let service = makeService(exerciseRepo: exerciseRepo, auditRepo: auditRepo)

        await service.processSessionEnd(workoutId: workoutId)

        XCTAssertEqual(exercise.fatigueLearningSessionCount, 1)
        XCTAssertEqual(exercise.fatigueRate ?? 0, 0.028, accuracy: 0.0001)
        XCTAssertEqual(exercise.fatigueRateSourceRawValue, ExerciseFatigueRateSource.learned.rawValue)
        let profile = try await service.globalSummary()
        XCTAssertEqual(profile.sessionCount, 0)
    }

    func testProcessSessionEnd_startsBlendedLocalRateAfterSecondQualifyingWorkout() async throws {
        let workoutId = UUID()
        let exercise = Exercise(name: "Leg Extension", equipmentType: .machinePin, trackingType: .weightReps)
        exercise.fatigueLearningSessionCount = 1
        exercise.fatigueLearningCumulativeError = -0.04
        exercise.fatigueRate = 0.048
        exercise.fatigueRateSourceRawValue = ExerciseFatigueRateSource.learned.rawValue

        let profile = HealthProfile(
            prescriptionLearnedFatigueRate: 0.05,
            prescriptionFatigueLearningSessionCount: 3,
            prescriptionFatigueLearningCumulativeError: -0.03
        )
        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let profileRepo = InMemoryHealthProfileRepo(profile: profile)
        let auditRepo = InMemoryFatigueLearningSetAuditRepo(
            audits: [
                makeUsedAudit(exerciseId: exercise.id, workoutId: workoutId, visibleSetNumber: 2, normalizedError: -0.06),
                makeUsedAudit(exerciseId: exercise.id, workoutId: workoutId, visibleSetNumber: 3, normalizedError: -0.04)
            ]
        )
        let service = makeService(
            exerciseRepo: exerciseRepo,
            healthProfileRepo: profileRepo,
            auditRepo: auditRepo
        )

        await service.processSessionEnd(workoutId: workoutId)

        XCTAssertEqual(exercise.fatigueLearningSessionCount, 2)
        XCTAssertEqual(exercise.fatigueRate ?? 0, 0.046, accuracy: 0.0001)
        XCTAssertLessThan(exercise.fatigueLearningCumulativeError ?? 0, 0)

        let appliedRate = try await service.appliedFatigueRate(for: exercise.id)
        XCTAssertEqual(appliedRate.source, .blendedLocal)
        XCTAssertEqual(appliedRate.localInfluence, 0.5, accuracy: 0.0001)
        XCTAssertEqual(appliedRate.rate, 0.048, accuracy: 0.0001)
    }

    func testProcessSessionEnd_reachesFullLocalOverrideAfterFourthQualifyingWorkout() async throws {
        let workoutId = UUID()
        let exercise = Exercise(name: "Leg Extension", equipmentType: .machinePin, trackingType: .weightReps)
        exercise.fatigueLearningSessionCount = 3
        exercise.fatigueLearningCumulativeError = -0.04
        exercise.fatigueRate = 0.048
        exercise.fatigueRateSourceRawValue = ExerciseFatigueRateSource.learned.rawValue

        let profile = HealthProfile(prescriptionLearnedFatigueRate: 0.05)
        let service = makeService(
            exerciseRepo: InMemoryExerciseRepo(exercises: [exercise]),
            healthProfileRepo: InMemoryHealthProfileRepo(profile: profile),
            auditRepo: InMemoryFatigueLearningSetAuditRepo(
                audits: [makeUsedAudit(exerciseId: exercise.id, workoutId: workoutId, visibleSetNumber: 2, normalizedError: -0.06)]
            )
        )

        await service.processSessionEnd(workoutId: workoutId)

        let appliedRate = try await service.appliedFatigueRate(for: exercise.id)
        XCTAssertEqual(exercise.fatigueLearningSessionCount, 4)
        XCTAssertEqual(exercise.fatigueRate ?? 0, 0.046, accuracy: 0.0001)
        XCTAssertEqual(appliedRate.source, .localLearned)
        XCTAssertEqual(appliedRate.localInfluence, 1.0, accuracy: 0.0001)
        XCTAssertEqual(appliedRate.rate, 0.046, accuracy: 0.0001)
    }

    // MARK: - Applied Rate + Diagnostics

    func testAppliedFatigueRate_prefersManualThenGlobalThenDefault() async throws {
        let defaultExercise = Exercise(name: "Pulldown", equipmentType: .machinePin, trackingType: .weightReps)
        let globalExercise = Exercise(name: "Press", equipmentType: .machinePin, trackingType: .weightReps)
        let overrideExercise = Exercise(name: "Curl", equipmentType: .cable, trackingType: .weightReps, fatigueRate: 0.06)
        overrideExercise.fatigueRateSourceRawValue = ExerciseFatigueRateSource.manualOverride.rawValue
        let exerciseRepo = InMemoryExerciseRepo(exercises: [defaultExercise, globalExercise, overrideExercise])

        let defaultService = makeService(exerciseRepo: exerciseRepo)
        let defaultRate = try await defaultService.appliedFatigueRate(for: defaultExercise.id)
        XCTAssertEqual(defaultRate.rate, 0.03, accuracy: 0.0001)
        XCTAssertEqual(defaultRate.source.displayTitle, "Default")
        XCTAssertEqual(defaultRate.localInfluence, 0.0, accuracy: 0.0001)

        let globalService = makeService(
            exerciseRepo: exerciseRepo,
            healthProfileRepo: InMemoryHealthProfileRepo(
                profile: HealthProfile(prescriptionLearnedFatigueRate: 0.05)
            )
        )
        let globalRate = try await globalService.appliedFatigueRate(for: globalExercise.id)
        XCTAssertEqual(globalRate.rate, 0.05, accuracy: 0.0001)
        XCTAssertEqual(globalRate.source.displayTitle, "Global baseline")

        let overrideRate = try await globalService.appliedFatigueRate(for: overrideExercise.id)
        XCTAssertEqual(overrideRate.rate, 0.06, accuracy: 0.0001)
        XCTAssertEqual(overrideRate.source.displayTitle, "Manual override")
        XCTAssertEqual(overrideRate.localInfluence, 1.0, accuracy: 0.0001)
    }

    func testAppliedFatigueRate_infersLearnedSourceAndBlendsAtThreeSessions() async throws {
        let exercise = Exercise(
            name: "Lat Pulldown",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            fatigueRate: 0.04
        )
        exercise.fatigueLearningSessionCount = 3
        exercise.fatigueLearningCumulativeError = -0.02
        let service = makeService(
            exerciseRepo: InMemoryExerciseRepo(exercises: [exercise]),
            healthProfileRepo: InMemoryHealthProfileRepo(
                profile: HealthProfile(prescriptionLearnedFatigueRate: 0.05)
            )
        )

        let appliedRate = try await service.appliedFatigueRate(for: exercise.id)

        XCTAssertEqual(appliedRate.source, .blendedLocal)
        XCTAssertEqual(appliedRate.localInfluence, 0.75, accuracy: 0.0001)
        XCTAssertEqual(appliedRate.rate, 0.0425, accuracy: 0.0001)
    }

    func testAppliedFatigueRate_infersManualOverrideSourceWithoutSessions() async throws {
        let exercise = Exercise(
            name: "Lat Pulldown",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            fatigueRate: 0.041
        )
        let service = makeService(exerciseRepo: InMemoryExerciseRepo(exercises: [exercise]))

        let appliedRate = try await service.appliedFatigueRate(for: exercise.id)

        XCTAssertEqual(appliedRate.source, .manualOverride)
        XCTAssertEqual(appliedRate.rate, 0.041, accuracy: 0.0001)
    }

    func testDiagnosticsExercises_includeAuditHistoryWithoutLocalLearning() async throws {
        let workoutId = UUID()
        let exercise = Exercise(name: "Lat Pulldown", equipmentType: .machinePin, trackingType: .weightReps)
        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let auditRepo = InMemoryFatigueLearningSetAuditRepo(
            audits: [
                FatigueLearningSetAudit(
                    workoutId: workoutId,
                    exerciseId: exercise.id,
                    setId: UUID(),
                    visibleSetNumber: 2,
                    setType: .working,
                    status: .suggestionUnavailable,
                    suggestionUnavailableReason: .noStrengthData
                )
            ]
        )
        let service = makeService(exerciseRepo: exerciseRepo, auditRepo: auditRepo)

        let diagnostics = try await service.diagnosticsExercises()

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.exercise.id, exercise.id)
        XCTAssertEqual(diagnostics.first?.hasAuditHistory, true)
    }

    // MARK: - Manual Nudge + Reset

    func testApplyManualNudge_usesGlobalRateWhenExerciseHasNoOverride() async throws {
        let exercise = Exercise(name: "Leg Extension", equipmentType: .machinePin, trackingType: .weightReps)
        let exerciseRepo = InMemoryExerciseRepo(exercises: [exercise])
        let service = makeService(
            exerciseRepo: exerciseRepo,
            healthProfileRepo: InMemoryHealthProfileRepo(
                profile: HealthProfile(prescriptionLearnedFatigueRate: 0.05)
            )
        )

        try await service.applyManualNudge(exerciseId: exercise.id, nudge: .lessAggressive)

        XCTAssertEqual(exercise.fatigueRate ?? 0, 0.048, accuracy: 0.0001)
        XCTAssertEqual(exercise.fatigueRateSourceRawValue, ExerciseFatigueRateSource.manualOverride.rawValue)
        XCTAssertNil(exercise.fatigueLearningSessionCount)
        XCTAssertNil(exercise.fatigueLearningCumulativeError)
    }

    func testApplyManualNudge_bypassesLocalBlendWhenExerciseHadLearnedRate() async throws {
        let exercise = Exercise(
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            fatigueRate: 0.045
        )
        exercise.fatigueLearningSessionCount = 3
        exercise.fatigueLearningCumulativeError = -0.02
        exercise.fatigueRateSourceRawValue = ExerciseFatigueRateSource.learned.rawValue

        let service = makeService(
            exerciseRepo: InMemoryExerciseRepo(exercises: [exercise]),
            healthProfileRepo: InMemoryHealthProfileRepo(
                profile: HealthProfile(prescriptionLearnedFatigueRate: 0.05)
            )
        )

        try await service.applyManualNudge(exerciseId: exercise.id, nudge: .lessAggressive)

        let appliedRate = try await service.appliedFatigueRate(for: exercise.id)
        XCTAssertEqual(exercise.fatigueRateSourceRawValue, ExerciseFatigueRateSource.manualOverride.rawValue)
        XCTAssertEqual(appliedRate.source, .manualOverride)
        XCTAssertEqual(appliedRate.localInfluence, 1.0, accuracy: 0.0001)
    }

    func testResetLearning_clearsExerciseDataAndPreservesGlobalBaseline() async throws {
        let workoutId = UUID()
        let exercise = Exercise(
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            fatigueRate: 0.05
        )
        exercise.fatigueLearningSessionCount = 3
        exercise.fatigueLearningCumulativeError = -0.02

        let profile = HealthProfile(
            prescriptionLearnedFatigueRate: 0.047,
            prescriptionFatigueLearningSessionCount: 2,
            prescriptionFatigueLearningCumulativeError: -0.01
        )
        let observation = makeObservation(exerciseId: exercise.id, workoutId: workoutId)
        let observationRepo = InMemoryFatigueObservationRepo(observations: [observation])
        let auditRepo = InMemoryFatigueLearningSetAuditRepo(
            audits: [makeUsedAudit(exerciseId: exercise.id, workoutId: workoutId, setId: observation.setId, visibleSetNumber: 2, normalizedError: -0.05)]
        )
        let profileRepo = InMemoryHealthProfileRepo(profile: profile)
        let service = makeService(
            observationRepo: observationRepo,
            exerciseRepo: InMemoryExerciseRepo(exercises: [exercise]),
            healthProfileRepo: profileRepo,
            auditRepo: auditRepo
        )

        try await service.resetLearning(exerciseId: exercise.id)

        XCTAssertNil(exercise.fatigueRate)
        XCTAssertNil(exercise.fatigueRateSourceRawValue)
        XCTAssertNil(exercise.fatigueLearningSessionCount)
        XCTAssertNil(exercise.fatigueLearningCumulativeError)
        XCTAssertTrue(observationRepo.observations.isEmpty)
        XCTAssertTrue(auditRepo.audits.isEmpty)

        let persistedProfile = try await profileRepo.fetchOrCreate()
        XCTAssertEqual(persistedProfile.prescriptionLearnedFatigueRate ?? 0, 0.047, accuracy: 0.0001)
        XCTAssertEqual(persistedProfile.prescriptionFatigueLearningSessionCount, 2)
    }

    func testResetAllLearning_clearsGlobalAndExerciseData() async throws {
        let workoutId = UUID()
        let learningExercise = Exercise(
            name: "Leg Extension",
            equipmentType: .machinePin,
            trackingType: .weightReps,
            fatigueRate: 0.05
        )
        learningExercise.fatigueRateSourceRawValue = ExerciseFatigueRateSource.learned.rawValue
        learningExercise.fatigueLearningSessionCount = 3
        learningExercise.fatigueLearningCumulativeError = -0.02

        let auditOnlyExercise = Exercise(name: "Lat Pulldown", equipmentType: .machinePin, trackingType: .weightReps)
        let profile = HealthProfile(
            prescriptionLearnedFatigueRate: 0.047,
            prescriptionFatigueLearningSessionCount: 2,
            prescriptionFatigueLearningCumulativeError: -0.01
        )
        let observationRepo = InMemoryFatigueObservationRepo(
            observations: [
                makeObservation(exerciseId: learningExercise.id, workoutId: workoutId),
                makeObservation(exerciseId: auditOnlyExercise.id, workoutId: workoutId)
            ]
        )
        let auditRepo = InMemoryFatigueLearningSetAuditRepo(
            audits: [
                makeUsedAudit(exerciseId: learningExercise.id, workoutId: workoutId, visibleSetNumber: 2, normalizedError: -0.05),
                makeUsedAudit(exerciseId: auditOnlyExercise.id, workoutId: workoutId, visibleSetNumber: 2, normalizedError: -0.03)
            ]
        )
        let profileRepo = InMemoryHealthProfileRepo(profile: profile)
        let service = makeService(
            observationRepo: observationRepo,
            exerciseRepo: InMemoryExerciseRepo(exercises: [learningExercise, auditOnlyExercise]),
            healthProfileRepo: profileRepo,
            auditRepo: auditRepo
        )

        try await service.resetAllLearning()

        XCTAssertNil(learningExercise.fatigueRate)
        XCTAssertNil(learningExercise.fatigueRateSourceRawValue)
        XCTAssertNil(learningExercise.fatigueLearningSessionCount)
        XCTAssertNil(learningExercise.fatigueLearningCumulativeError)
        XCTAssertTrue(observationRepo.observations.isEmpty)
        XCTAssertTrue(auditRepo.audits.isEmpty)

        let persistedProfile = try await profileRepo.fetchOrCreate()
        XCTAssertNil(persistedProfile.prescriptionLearnedFatigueRate)
        XCTAssertNil(persistedProfile.prescriptionFatigueLearningSessionCount)
        XCTAssertNil(persistedProfile.prescriptionFatigueLearningCumulativeError)
    }

    // MARK: - Helpers

    private func makeService(
        observationRepo: (any FatigueObservationRepositoryProtocol)? = nil,
        exerciseRepo: (any ExerciseRepositoryProtocol)? = nil,
        healthProfileRepo: (any HealthProfileRepositoryProtocol)? = nil,
        auditRepo: (any FatigueLearningSetAuditRepositoryProtocol)? = nil
    ) -> FatigueLearningService {
        FatigueLearningService(
            observationRepo: observationRepo ?? InMemoryFatigueObservationRepo(),
            exerciseRepo: exerciseRepo ?? InMemoryExerciseRepo(),
            healthProfileRepo: healthProfileRepo ?? InMemoryHealthProfileRepo(profile: HealthProfile()),
            auditRepo: auditRepo ?? InMemoryFatigueLearningSetAuditRepo()
        )
    }

    private func makePrediction(
        effectiveE1RM: Double = 140,
        baseE1RM: Double = 150,
        prescribedWeight: Double = 110
    ) -> PredictionSnapshot {
        PredictionSnapshot(
            effectiveE1RM: effectiveE1RM,
            baseE1RM: baseE1RM,
            prescribedWeight: prescribedWeight,
            formula: .epley
        )
    }

    private func capture(
        with service: FatigueLearningService,
        setId: UUID = UUID(),
        exerciseId: UUID = UUID(),
        workoutId: UUID = UUID(),
        visibleSetNumber: Int = 2,
        setType: SetType = .working,
        priorCompletedWorkingSetCount: Int = 1,
        suggestionUnavailableReason: SuggestionUnavailableReason? = nil,
        prediction: PredictionSnapshot? = PredictionSnapshot(
            effectiveE1RM: 140,
            baseE1RM: 150,
            prescribedWeight: 110,
            formula: .epley
        ),
        actualWeight: Double? = 110,
        actualReps: Int? = 10,
        actualRIR: Double? = 0,
        restDurationSeconds: Int? = 180
    ) async throws -> FatigueLearningCaptureResult {
        try await service.captureCompletedSet(
            setId: setId,
            exerciseId: exerciseId,
            workoutId: workoutId,
            visibleSetNumber: visibleSetNumber,
            setType: setType,
            priorCompletedWorkingSetCount: priorCompletedWorkingSetCount,
            suggestionUnavailableReason: suggestionUnavailableReason,
            prediction: prediction,
            actualWeight: actualWeight,
            actualReps: actualReps,
            actualRIR: actualRIR,
            restDurationSeconds: restDurationSeconds
        )
    }

    private func makeUsedAudit(
        exerciseId: UUID,
        workoutId: UUID,
        setId: UUID = UUID(),
        visibleSetNumber: Int,
        normalizedError: Double,
        createdAt: Date = Date()
    ) -> FatigueLearningSetAudit {
        FatigueLearningSetAudit(
            workoutId: workoutId,
            exerciseId: exerciseId,
            setId: setId,
            visibleSetNumber: visibleSetNumber,
            setType: .working,
            status: .used,
            predictedEffectiveE1RM: 140,
            baseE1RM: 150,
            prescribedWeight: 110,
            actualWeight: 110,
            actualReps: 10,
            actualRIR: 0,
            deviationFraction: 0,
            normalizedError: normalizedError,
            createdAt: createdAt
        )
    }

    private func makeObservation(
        exerciseId: UUID,
        workoutId: UUID,
        setId: UUID = UUID()
    ) -> FatigueObservation {
        FatigueObservation(
            exerciseId: exerciseId,
            workoutId: workoutId,
            setId: setId,
            setIndex: 1,
            predictedEffectiveE1RM: 140,
            actualE1RM: 148,
            normalizedError: -0.053,
            baseE1RM: 150,
            prescribedWeight: 105,
            actualWeight: 110,
            actualReps: 10,
            actualRIR: 0
        )
    }
}

private final class InMemoryFatigueObservationRepo: @unchecked Sendable, FatigueObservationRepositoryProtocol {
    var observations: [FatigueObservation]

    init(observations: [FatigueObservation] = []) {
        self.observations = observations
    }

    func upsert(_ observation: FatigueObservation) async throws {
        observations.removeAll { $0.setId == observation.setId }
        observations.append(observation)
    }

    func fetchObservations(for workoutId: UUID) async throws -> [FatigueObservation] {
        observations
            .filter { $0.workoutId == workoutId }
            .sorted { $0.setIndex < $1.setIndex }
    }

    func fetchObservations(exerciseId: UUID, limit: Int?) async throws -> [FatigueObservation] {
        let filtered = observations
            .filter { $0.exerciseId == exerciseId }
            .sorted { $0.createdAt > $1.createdAt }
        if let limit {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    func distinctWorkoutCount(exerciseId: UUID) async throws -> Int {
        Set(observations.filter { $0.exerciseId == exerciseId }.map(\.workoutId)).count
    }

    func deleteObservation(for setId: UUID) async throws {
        observations.removeAll { $0.setId == setId }
    }

    @discardableResult
    func pruneObservations(exerciseId: UUID, keepRecentSessions: Int) async throws -> Int {
        let originalCount = observations.count
        guard keepRecentSessions > 0 else {
            observations.removeAll { $0.exerciseId == exerciseId }
            return originalCount - observations.count
        }

        let grouped = Dictionary(grouping: observations.filter { $0.exerciseId == exerciseId }, by: \.workoutId)
        let sortedWorkoutIds = grouped.keys.sorted { lhs, rhs in
            let lhsDate = grouped[lhs]?.first?.createdAt ?? .distantPast
            let rhsDate = grouped[rhs]?.first?.createdAt ?? .distantPast
            return lhsDate > rhsDate
        }
        let workoutsToKeep = Set(sortedWorkoutIds.prefix(keepRecentSessions))
        observations.removeAll {
            $0.exerciseId == exerciseId && !workoutsToKeep.contains($0.workoutId)
        }
        return originalCount - observations.count
    }
}

private final class InMemoryFatigueLearningSetAuditRepo: @unchecked Sendable, FatigueLearningSetAuditRepositoryProtocol {
    var audits: [FatigueLearningSetAudit]

    init(audits: [FatigueLearningSetAudit] = []) {
        self.audits = audits
    }

    func upsert(_ audit: FatigueLearningSetAudit) async throws {
        audits.removeAll { $0.setId == audit.setId }
        audits.append(audit)
    }

    func fetchAudits(for workoutId: UUID) async throws -> [FatigueLearningSetAudit] {
        audits
            .filter { $0.workoutId == workoutId }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.visibleSetNumber < $1.visibleSetNumber
            }
    }

    func fetchAudits(workoutId: UUID, exerciseId: UUID) async throws -> [FatigueLearningSetAudit] {
        audits
            .filter { $0.workoutId == workoutId && $0.exerciseId == exerciseId }
            .sorted {
                if $0.visibleSetNumber != $1.visibleSetNumber { return $0.visibleSetNumber < $1.visibleSetNumber }
                return $0.createdAt < $1.createdAt
            }
    }

    func fetchAudits(exerciseId: UUID, limit: Int?) async throws -> [FatigueLearningSetAudit] {
        let filtered = audits
            .filter { $0.exerciseId == exerciseId }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.visibleSetNumber < $1.visibleSetNumber
            }
        if let limit {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    func exerciseIdsWithAudits() async throws -> [UUID] {
        Array(Set(audits.map(\.exerciseId))).sorted { $0.uuidString < $1.uuidString }
    }

    func deleteAudit(for setId: UUID) async throws {
        audits.removeAll { $0.setId == setId }
    }

    func deleteAudits(workoutId: UUID) async throws {
        audits.removeAll { $0.workoutId == workoutId }
    }

    func deleteAudits(exerciseId: UUID) async throws {
        audits.removeAll { $0.exerciseId == exerciseId }
    }

    func deleteAll() async throws {
        audits.removeAll()
    }
}

private final class InMemoryHealthProfileRepo: @unchecked Sendable, HealthProfileRepositoryProtocol {
    private var profile: HealthProfile

    init(profile: HealthProfile) {
        self.profile = profile
    }

    func save(_ profile: HealthProfile) async throws {
        self.profile = profile
    }

    func fetch() async throws -> HealthProfile? {
        profile
    }

    func fetchOrCreate() async throws -> HealthProfile {
        profile
    }
}

private final class InMemoryExerciseRepo: @unchecked Sendable, ExerciseRepositoryProtocol {
    var exercises: [Exercise]

    init(exercises: [Exercise] = []) {
        self.exercises = exercises
    }

    func save(_ exercise: Exercise) async throws {
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            exercises[index] = exercise
        } else {
            exercises.append(exercise)
        }
    }

    func delete(_ exercise: Exercise) async throws {
        exercises.removeAll { $0.id == exercise.id }
    }

    func fetch(byId id: UUID) async throws -> Exercise? {
        exercises.first { $0.id == id }
    }

    func fetchAll() async throws -> [Exercise] {
        exercises
    }

    func fetchAllChartExercises() async throws -> [ChartExerciseData] { [] }
    func search(name: String) async throws -> [Exercise] { [] }
    func hasAssociatedSets(_ exerciseId: UUID) async throws -> Bool { false }
    func hasLoggedSetData(_ exerciseId: UUID) async throws -> Bool { false }
}
