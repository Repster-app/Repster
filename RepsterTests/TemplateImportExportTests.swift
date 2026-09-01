// TemplateImportExportTests.swift
// Import and export of `.repstertemplate` archives and AI-authored drafts.
//
// These nine tests lived in `ActiveWorkoutViewModelSuggestionRefreshTests.swift` — a 7,700-line file
// named for something else — where they were the only template coverage in the project while
// `startWorkoutFromTemplate` had none. Moved here unchanged (TEMPLATES_IMPLEMENTATION_PLAN.md P5.3).
// Behavioural coverage of the service lives in `TemplateServiceTests.swift`.

import XCTest
import SwiftData
@testable import Repster

@MainActor
final class TemplateImportExportTests: XCTestCase {

    func testExportImportRoundtripPreservesTemplateStructure() async throws {
        let context = try makeTemplateServiceContext()
        let squat = makeExercise(name: "Back Squat", primaryMuscle: "legs", defaultRestTime: 180)
        let bench = makeExercise(
            name: "Bench Press",
            primaryMuscle: "chest",
            defaultRestTime: 120,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides
        )
        try await context.exerciseRepo.save(squat)
        try await context.exerciseRepo.save(bench)

        let supersetGroupId = UUID()
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Strength Day",
                notes: "Heavy compounds",
                exercises: [
                    TemplateSaveExercise(
                        exerciseId: squat.id,
                        orderInTemplate: 1,
                        supersetGroupId: supersetGroupId,
                        restTimeSeconds: 180,
                        notes: "Brace hard",
                        sets: [
                            TemplateSaveSet(
                                setType: .warmup,
                                targetRepMin: 5,
                                targetRepMax: 5,
                                targetRIR: 4,
                                orderInExercise: 1
                            ),
                            TemplateSaveSet(
                                setType: .working,
                                targetRepMin: 3,
                                targetRepMax: 5,
                                targetRIR: 2,
                                orderInExercise: 2
                            )
                        ]
                    ),
                    TemplateSaveExercise(
                        exerciseId: bench.id,
                        orderInTemplate: 2,
                        supersetGroupId: supersetGroupId,
                        restTimeSeconds: 120,
                        notes: "Pause first rep",
                        sets: [
                            TemplateSaveSet(
                                setType: .working,
                                targetRepMin: 6,
                                targetRepMax: 8,
                                targetRIR: 1,
                                orderInExercise: 1
                            )
                        ]
                    )
                ]
            )
        )

        let exportedData = try await context.service.exportTemplate(templateId)
        let exportedArchive = try JSONDecoder().decode(TemplateArchive.self, from: exportedData)
        let importedTemplateId = try await context.service.importTemplate(data: exportedData)
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)
        let exercises = try await context.exerciseRepo.fetchAll()
        let exportedBench = try XCTUnwrap(exportedArchive.exercises.last)

        XCTAssertEqual(importedDetail.template.name, "Strength Day (Imported)")
        XCTAssertEqual(importedDetail.template.notes, "Heavy compounds")
        XCTAssertEqual(importedDetail.exercises.count, 2)
        XCTAssertEqual(exercises.count, 2, "Import should reuse existing exercises via UUID match.")
        XCTAssertEqual(exportedBench.exercise.id, bench.id)
        XCTAssertEqual(exportedBench.exercise.unilateralRepTargetMode, .totalAcrossSides)

        let importedSquat = try XCTUnwrap(importedDetail.exercises.first)
        XCTAssertEqual(importedSquat.exerciseId, squat.id)
        XCTAssertEqual(importedSquat.orderInTemplate, 1)
        XCTAssertEqual(importedSquat.restTimeSeconds, 180)
        XCTAssertEqual(importedSquat.notes, "Brace hard")
        XCTAssertEqual(importedSquat.sets.map(\.orderInExercise), [1, 2])
        XCTAssertEqual(importedSquat.sets.map(\.setType), [.warmup, .working])
        XCTAssertEqual(importedSquat.sets.map(\.targetRepMin), [5 as Int?, 3])
        XCTAssertEqual(importedSquat.sets.map(\.targetRepMax), [5 as Int?, 5])
        XCTAssertEqual(importedSquat.sets.map(\.targetRIR), [4 as Int?, 2])

        let importedBench = try XCTUnwrap(importedDetail.exercises.last)
        XCTAssertEqual(importedBench.exerciseId, bench.id)
        XCTAssertEqual(importedBench.orderInTemplate, 2)
        XCTAssertEqual(importedBench.restTimeSeconds, 120)
        XCTAssertEqual(importedBench.notes, "Pause first rep")
        XCTAssertEqual(importedBench.sets.count, 1)
        XCTAssertEqual(importedBench.sets.first?.targetRepMin, 6)
        XCTAssertEqual(importedBench.sets.first?.targetRepMax, 8)
        XCTAssertEqual(importedBench.sets.first?.targetRIR, 1)
        XCTAssertEqual(importedSquat.supersetGroupId, importedBench.supersetGroupId)
    }

    func testImportMatchesExistingExerciseByNormalizedName() async throws {
        let context = try makeTemplateServiceContext()
        let existingExercise = makeExercise(name: "Incline Bench Press", primaryMuscle: "chest", defaultRestTime: 90)
        try await context.exerciseRepo.save(existingExercise)

        let archiveData = try makeArchiveData(
            templateName: "Upper Builder",
            exercises: [
                makeArchiveExercise(
                    exerciseId: UUID(),
                    exerciseName: "  incline   bench press  ",
                    primaryMuscle: "chest",
                    defaultRestTime: 90,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 8,
                            targetRepMax: 10,
                            targetRIR: 2,
                            orderInExercise: 1
                        )
                    ]
                )
            ]
        )

        let importedTemplateId = try await context.service.importTemplate(data: archiveData)
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)
        let exercises = try await context.exerciseRepo.fetchAll()

        XCTAssertEqual(importedDetail.exercises.first?.exerciseId, existingExercise.id)
        XCTAssertEqual(exercises.count, 1, "Import should reuse an existing exercise matched by name.")
    }

    func testPreviewAndFinalizeCanCreateMissingExerciseFromArchiveMetadata() async throws {
        let context = try makeTemplateServiceContext()
        let archivedExerciseId = UUID()

        let archiveData = try makeArchiveData(
            templateName: "Travel Workout",
            exercises: [
                makeArchiveExercise(
                    exerciseId: archivedExerciseId,
                    exerciseName: "Single Arm Cable Row",
                    primaryMuscle: "back",
                    defaultRestTime: 75,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 10,
                            targetRepMax: 12,
                            targetRIR: 1,
                            orderInExercise: 1
                        )
                    ],
                    unilateral: true,
                    unilateralRepTargetMode: .totalAcrossSides,
                    trackingType: .weightReps,
                    equipmentType: .cable
                )
            ]
        )

        let preview = try await context.service.previewTemplateImport(data: archiveData)
        XCTAssertEqual(preview.unresolvedExercises.count, 1)
        XCTAssertEqual(preview.unresolvedExercises.first?.exercise.name, "Single Arm Cable Row")
        XCTAssertEqual(preview.unresolvedExercises.first?.exercise.unilateralRepTargetMode, .totalAcrossSides)

        do {
            _ = try await context.service.importTemplate(data: archiveData)
            XCTFail("Expected direct import to require exercise resolution")
        } catch let error as TemplateServiceError {
            guard case .importRequiresResolution(let unresolvedCount) = error else {
                return XCTFail("Unexpected template service error: \(error)")
            }
            XCTAssertEqual(unresolvedCount, 1)
        }

        let importedTemplateId = try await context.service.finalizeTemplateImport(
            preview,
            resolutions: [
                TemplateImportExerciseResolution(
                    previewExerciseId: try XCTUnwrap(preview.unresolvedExercises.first?.id),
                    action: .createNew
                )
            ]
        )
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)
        let createdExercise = try await context.exerciseRepo.fetch(byId: archivedExerciseId)

        XCTAssertEqual(importedDetail.exercises.first?.exerciseId, archivedExerciseId)
        XCTAssertEqual(createdExercise?.name, "Single Arm Cable Row")
        XCTAssertEqual(createdExercise?.primaryMuscle, "back")
        XCTAssertEqual(createdExercise?.defaultRestTime, 75)
        XCTAssertEqual(createdExercise?.unilateral, true)
        XCTAssertEqual(createdExercise?.unilateralRepTargetMode, .totalAcrossSides)
        XCTAssertEqual(createdExercise?.equipmentType, .cable)
    }

    func testFinalizeImportCanMapMissingExerciseToExistingExercise() async throws {
        let context = try makeTemplateServiceContext()
        let existingExercise = Exercise(
            name: "Cable Row",
            equipmentType: .cable,
            trackingType: .weightReps,
            primaryMuscle: "back",
            unilateral: false,
            defaultRestTime: 75
        )
        try await context.exerciseRepo.save(existingExercise)

        let archiveData = try makeArchiveData(
            templateName: "Travel Workout",
            exercises: [
                makeArchiveExercise(
                    exerciseId: UUID(),
                    exerciseName: "Single Arm Cable Row",
                    primaryMuscle: "back",
                    defaultRestTime: 75,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 10,
                            targetRepMax: 12,
                            targetRIR: 1,
                            orderInExercise: 1
                        )
                    ],
                    unilateral: true,
                    trackingType: .weightReps,
                    equipmentType: .cable
                )
            ]
        )

        let preview = try await context.service.previewTemplateImport(data: archiveData)
        let importedTemplateId = try await context.service.finalizeTemplateImport(
            preview,
            resolutions: [
                TemplateImportExerciseResolution(
                    previewExerciseId: try XCTUnwrap(preview.unresolvedExercises.first?.id),
                    action: .mapToExisting,
                    existingExerciseId: existingExercise.id
                )
            ]
        )
        let importedDetailValue = try await context.service.fetchTemplateDetail(importedTemplateId)
        let importedDetail = try XCTUnwrap(importedDetailValue)
        let exercises = try await context.exerciseRepo.fetchAll()

        XCTAssertEqual(importedDetail.exercises.first?.exerciseId, existingExercise.id)
        XCTAssertEqual(exercises.count, 1, "Manual mapping should reuse the chosen exercise instead of creating a new one.")
    }


    func testImportAddsImportedSuffixForTemplateNameCollisions() async throws {
        let context = try makeTemplateServiceContext()
        let exercise = makeExercise(name: "Pull-Up", primaryMuscle: "back", defaultRestTime: 90)
        try await context.exerciseRepo.save(exercise)

        _ = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Pull Day",
                notes: nil,
                exercises: [
                    TemplateSaveExercise(
                        exerciseId: exercise.id,
                        orderInTemplate: 1,
                        supersetGroupId: nil,
                        restTimeSeconds: 90,
                        notes: nil,
                        sets: [
                            TemplateSaveSet(
                                setType: .working,
                                targetRepMin: 6,
                                targetRepMax: 8,
                                targetRIR: 2,
                                orderInExercise: 1
                            )
                        ]
                    )
                ]
            )
        )

        let archiveData = try makeArchiveData(
            templateName: "Pull Day",
            exercises: [
                makeArchiveExercise(
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    primaryMuscle: "back",
                    defaultRestTime: 90,
                    orderInTemplate: 1,
                    sets: [
                        TemplateArchiveSet(
                            setType: .working,
                            targetRepMin: 6,
                            targetRepMax: 8,
                            targetRIR: 2,
                            orderInExercise: 1
                        )
                    ]
                )
            ]
        )

        let firstImportedId = try await context.service.importTemplate(data: archiveData)
        let secondImportedId = try await context.service.importTemplate(data: archiveData)

        let firstImportedValue = try await context.service.fetchTemplateDetail(firstImportedId)
        let secondImportedValue = try await context.service.fetchTemplateDetail(secondImportedId)
        let firstImported = try XCTUnwrap(firstImportedValue)
        let secondImported = try XCTUnwrap(secondImportedValue)

        XCTAssertEqual(firstImported.template.name, "Pull Day (Imported)")
        XCTAssertEqual(secondImported.template.name, "Pull Day (Imported 2)")
    }

    func testCreateTemplateFromWorkoutPrefersPersistedTargetOverrideBounds() async throws {
        let context = try makeTemplateServiceContext()
        let exercise = makeExercise(name: "Bench Press", primaryMuscle: "chest", defaultRestTime: 120)
        let workoutDate = makeDate(2026, 3, 22, 7, 0)
        let workout = Workout(
            date: workoutDate,
            startTime: workoutDate,
            status: .inProgress
        )
        let set = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exercise.id,
            date: workoutDate,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: false
        )
        set.targetRepMin = 8
        set.targetRepMax = 12
        set.overrideTargetRepMin = 6
        set.overrideTargetRepMax = 8
        set.targetRIR = 2

        try await context.exerciseRepo.save(exercise)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(set)

        let templateId = try await context.service.createTemplateFromWorkout(workout.id, name: "Bench Override")
        let detail = try await context.service.fetchTemplateDetail(templateId)
        let unwrappedDetail = try XCTUnwrap(detail)
        let savedSet = try XCTUnwrap(unwrappedDetail.exercises.first?.sets.first)

        XCTAssertEqual(savedSet.targetRepMin, 6)
        XCTAssertEqual(savedSet.targetRepMax, 8)
        XCTAssertEqual(savedSet.targetRIR, 2)
    }

    private func makeTemplateServiceContext() throws -> TemplateServiceTestContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self,
            ExerciseStats.self,
            Workout.self,
            WorkoutSet.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateSet.self,
            configurations: configuration
        )

        let exerciseRepo = ExerciseRepository(modelContainer: container)
        let workoutRepo = WorkoutRepository(modelContainer: container)
        let setRepo = SetRepository(modelContainer: container)
        let exerciseStatsRepo = ExerciseStatsRepository(modelContainer: container)
        let templateRepo = TemplateRepository(modelContainer: container)
        let service = TemplateService(
            templateRepository: templateRepo,
            workoutRepository: workoutRepo,
            setRepository: setRepo,
            exerciseRepository: exerciseRepo
        )

        return TemplateServiceTestContext(
            service: service,
            exerciseRepo: exerciseRepo,
            exerciseStatsRepo: exerciseStatsRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo
        )
    }

    private func makeExercise(
        name: String,
        primaryMuscle: String,
        defaultRestTime: Int,
        unilateral: Bool = false,
        unilateralRepTargetMode: UnilateralRepTargetMode? = nil
    ) -> Exercise {
        Exercise(
            name: name,
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: primaryMuscle,
            unilateral: unilateral,
            unilateralRepTargetMode: unilateralRepTargetMode,
            defaultRestTime: defaultRestTime
        )
    }

    private func makeArchiveData(
        templateName: String,
        exercises: [TemplateArchiveExercise]
    ) throws -> Data {
        try JSONEncoder().encode(
            TemplateArchive(
                version: TemplateArchive.currentVersion,
                template: TemplateArchiveTemplate(
                    id: UUID(),
                    name: templateName,
                    notes: nil
                ),
                exercises: exercises
            )
        )
    }

    private func makeArchiveExercise(
        exerciseId: UUID,
        exerciseName: String,
        primaryMuscle: String,
        defaultRestTime: Int,
        orderInTemplate: Int,
        sets: [TemplateArchiveSet],
        unilateral: Bool = false,
        unilateralRepTargetMode: UnilateralRepTargetMode? = nil,
        trackingType: TrackingType = .weightReps,
        equipmentType: EquipmentType = .barbell
    ) -> TemplateArchiveExercise {
        TemplateArchiveExercise(
            exercise: TemplateArchiveExerciseMetadata(
                id: exerciseId,
                name: exerciseName,
                equipmentType: equipmentType,
                trackingType: trackingType,
                primaryMuscle: primaryMuscle,
                secondaryMuscles: [],
                movementPattern: nil,
                unilateral: unilateral,
                unilateralRepTargetMode: unilateralRepTargetMode,
                bilateralLoadFactor: nil,
                bodyweightFactor: 0,
                weightIncrement: 2.5,
                defaultRestTime: defaultRestTime,
                fatigueRate: nil,
                recoveryConstant: nil
            ),
            orderInTemplate: orderInTemplate,
            supersetGroupId: nil,
            restTimeSeconds: defaultRestTime,
            notes: nil,
            sets: sets
        )
    }


    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}

private struct TemplateServiceTestContext {
    let service: TemplateService
    let exerciseRepo: ExerciseRepository
    let exerciseStatsRepo: ExerciseStatsRepository
    let workoutRepo: WorkoutRepository
    let setRepo: SetRepository
}
