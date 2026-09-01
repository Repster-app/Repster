// TemplateServiceTests.swift
// Coverage for the template paths that had none: starting a workout from a template, the atomic
// content replace, superset group derivation, and folders.
//
// The nine pre-existing template tests all cover import/export and live in
// `ActiveWorkoutViewModelSuggestionRefreshTests.swift` under `TemplateImportExportTests`. Moving them
// here is still owed (TEMPLATES_IMPLEMENTATION_PLAN.md P5.3); this file covers what was untested.

import XCTest
import SwiftData
@testable import Repster

final class TemplateServiceTests: XCTestCase {

    // MARK: - startWorkoutFromTemplate — the most-used path, previously untested

    func testStartWorkoutFromTemplateCreatesOneSetPerTemplateSetWithTargets() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)

        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push",
                notes: nil,
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [
                        saveSet(order: 1, min: 6, max: 8, rir: 2),
                        saveSet(order: 2, min: 6, max: 8, rir: 2),
                        saveSet(order: 3, min: 6, max: 8, rir: 1)
                    ])
                ]
            )
        )

        let workout = try await context.service.startWorkoutFromTemplate(templateId)
        let sets = try await context.setRepo.fetchSets(for: workout.id)

        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.exerciseId == bench.id })
        XCTAssertTrue(sets.allSatisfy { $0.completed == false })
        XCTAssertEqual(sets.map(\.orderInExercise).sorted(), [1, 2, 3])
        XCTAssertEqual(Set(sets.map(\.targetRepMin)), [6])
        XCTAssertEqual(Set(sets.map(\.targetRepMax)), [8])
        XCTAssertEqual(sets.compactMap(\.targetRIR).sorted(), [1, 2, 2])
        // No weights: a template prescribes targets, never loads.
        XCTAssertTrue(sets.allSatisfy { $0.weight == nil })
    }

    func testStartWorkoutFromTemplateCarriesSupersetGroupOntoEverySet() async throws {
        let context = try makeContext()
        let fly = makeExercise(name: "Cable Fly")
        let raise = makeExercise(name: "Lateral Raise")
        try await context.exerciseRepo.save(fly)
        try await context.exerciseRepo.save(raise)

        let groupId = UUID()
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Superset",
                notes: nil,
                exercises: [
                    saveExercise(fly.id, order: 1, group: groupId, sets: [saveSet(order: 1)]),
                    saveExercise(raise.id, order: 2, group: groupId, sets: [saveSet(order: 1)])
                ]
            )
        )

        let workout = try await context.service.startWorkoutFromTemplate(templateId)
        let sets = try await context.setRepo.fetchSets(for: workout.id)

        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(Set(sets.compactMap(\.supersetGroupId)), [groupId])
    }

    func testStartWorkoutFromTemplateStampsLastUsedAt() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let templateId = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Push")

        let before = try await context.service.fetchAllTemplates().first
        XCTAssertNil(before?.lastUsedAt)

        _ = try await context.service.startWorkoutFromTemplate(templateId)

        let after = try await context.service.fetchAllTemplates().first
        XCTAssertNotNil(after?.lastUsedAt)
    }

    // MARK: - D2 — the content replace is atomic and lossless

    func testUpdateTemplateReplacesContentsWithoutLosingThem() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        let incline = makeExercise(name: "Incline DB Press")
        try await context.exerciseRepo.save(bench)
        try await context.exerciseRepo.save(incline)

        let templateId = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Push")

        try await context.service.updateTemplate(
            templateId,
            data: TemplateSaveData(
                name: "Push A",
                notes: "reworked",
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [saveSet(order: 1, min: 5, max: 5)]),
                    saveExercise(incline.id, order: 2, sets: [saveSet(order: 1), saveSet(order: 2)])
                ]
            )
        )

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)
        XCTAssertEqual(detail.template.name, "Push A")
        XCTAssertEqual(detail.template.notes, "reworked")
        XCTAssertEqual(detail.exercises.count, 2)
        XCTAssertEqual(detail.exercises.map(\.exerciseName), ["Bench Press", "Incline DB Press"])
        XCTAssertEqual(detail.exercises[0].sets.count, 1)
        XCTAssertEqual(detail.exercises[1].sets.count, 2)
        XCTAssertEqual(detail.template.totalSetCount, 3)
    }

    func testUpdateTemplateToEmptyLeavesNoOrphanedSets() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let templateId = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Push")

        try await context.service.updateTemplate(
            templateId,
            data: TemplateSaveData(name: "Push", notes: nil, exercises: [])
        )

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)
        let summaries = try await context.service.fetchAllTemplates()
        XCTAssertTrue(detail.exercises.isEmpty)
        // D4: a zero-exercise template still exists and still lists.
        XCTAssertEqual(summaries.count, 1)
    }

    func testDeleteTemplateRemovesItsExercisesAndSets() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let templateId = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Push")

        try await context.service.deleteTemplate(templateId)

        let summaries = try await context.service.fetchAllTemplates()
        let detail = try await context.service.fetchTemplateDetail(templateId)
        let orphanExercises = try await context.templateRepo.fetchTemplateExercises(for: templateId)
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertNil(detail)
        XCTAssertTrue(orphanExercises.isEmpty)
    }

    // MARK: - P0.3 — group derivation uses any non-nil set, not the first

    func testCreateTemplateFromWorkoutKeepsGroupWhenFirstSetPredatesIt() async throws {
        let context = try makeContext()
        let fly = makeExercise(name: "Cable Fly")
        try await context.exerciseRepo.save(fly)

        let workout = Workout(date: Date(), startTime: Date(), status: .completed)
        try await context.workoutRepo.save(workout)

        let groupId = UUID()
        // The shape this regressed on: set 1 was logged before the superset was created at the rack,
        // so it carries no group. `sortedSets.first` read nil and dropped the grouping entirely.
        try await context.setRepo.save(workoutSet(workout.id, fly.id, order: 1, group: nil))
        try await context.setRepo.save(workoutSet(workout.id, fly.id, order: 2, group: groupId))
        try await context.setRepo.save(workoutSet(workout.id, fly.id, order: 3, group: groupId))

        let templateId = try await context.service.createTemplateFromWorkout(workout.id, name: "From Workout")
        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)

        XCTAssertEqual(detail.exercises.first?.supersetGroupId, groupId)
    }

    func testCreateTemplateFromWorkoutLeavesUngroupedExerciseUngrouped() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)

        let workout = Workout(date: Date(), startTime: Date(), status: .completed)
        try await context.workoutRepo.save(workout)
        try await context.setRepo.save(workoutSet(workout.id, bench.id, order: 1, group: nil))
        try await context.setRepo.save(workoutSet(workout.id, bench.id, order: 2, group: nil))

        let templateId = try await context.service.createTemplateFromWorkout(workout.id, name: "From Workout")
        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)

        XCTAssertNil(detail.exercises.first?.supersetGroupId)
    }

    // MARK: - P1.1 / D3 — folders, and preserving superset data the new editor would not produce

    func testFolderRoundTripsThroughCreateUpdateAndFetch() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)

        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push",
                notes: nil,
                folder: "Mesocycle 3",
                exercises: [saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)])]
            )
        )

        let afterCreate = try await context.service.fetchAllTemplates().first
        XCTAssertEqual(afterCreate?.folder, "Mesocycle 3")

        try await context.service.updateTemplate(
            templateId,
            data: TemplateSaveData(
                name: "Push",
                notes: nil,
                folder: "Deload",
                exercises: [saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)])]
            )
        )

        let afterUpdate = try await context.service.fetchAllTemplates().first
        XCTAssertEqual(afterUpdate?.folder, "Deload")
    }

    func testFolderCanBeClearedBackToNone() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push", notes: nil, folder: "Mesocycle 3",
                exercises: [saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)])]
            )
        )

        try await context.service.updateTemplate(
            templateId,
            data: TemplateSaveData(
                name: "Push", notes: nil, folder: nil,
                exercises: [saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)])]
            )
        )

        let cleared = try await context.service.fetchAllTemplates().first
        XCTAssertNil(cleared?.folder)
    }

    func testFolderNormalisationTrimsAndTreatsBlankAsNone() {
        XCTAssertEqual(TemplateFolder.normalized("  Mesocycle 3  "), "Mesocycle 3")
        XCTAssertNil(TemplateFolder.normalized("   "))
        XCTAssertNil(TemplateFolder.normalized(""))
        XCTAssertNil(TemplateFolder.normalized(nil))
        // A whitespace-only field must not create a folder nobody can see or name.
        XCTAssertNil(TemplateSaveData(name: "x", notes: nil, folder: "  ", exercises: []).folder)
    }

    func testFolderGroupingKeyFoldsCase() {
        XCTAssertEqual(TemplateFolder.groupingKey("Deload"), TemplateFolder.groupingKey("deload"))
        XCTAssertEqual(TemplateFolder.groupingKey("  DELOAD "), TemplateFolder.groupingKey("Deload"))
        XCTAssertNil(TemplateFolder.groupingKey("  "))
    }

    func testFolderSurvivesTemplateExportImportRoundTrip() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push", notes: nil, folder: "Mesocycle 3",
                exercises: [saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)])]
            )
        )

        let data = try await context.service.exportTemplate(templateId)
        let importedId = try await context.service.importTemplate(data: data)
        let allTemplates = try await context.service.fetchAllTemplates()
        let imported = allTemplates.first { $0.id == importedId }

        XCTAssertEqual(imported?.folder, "Mesocycle 3")
    }

    func testArchiveWithoutFolderKeyStillDecodesAsNoFolder() throws {
        // Archives written before folders existed have no `folder` key at all. They must decode, not
        // throw, and land as "Not in a folder".
        let json = """
        {"version":1,"template":{"id":"\(UUID().uuidString)","name":"Legacy","notes":null},"exercises":[]}
        """
        let archive = try JSONDecoder().decode(TemplateArchive.self, from: Data(json.utf8))
        XCTAssertEqual(archive.template.name, "Legacy")
        XCTAssertNil(archive.template.folder)
    }

    func testGroupOfOneKeepsItsSupersetIdThroughAnUpdate() async throws {
        // D3: today's editor makes a group of one trivially, so this data exists in the wild. An
        // open-and-save cycle must not silently clear it.
        let context = try makeContext()
        let fly = makeExercise(name: "Cable Fly")
        try await context.exerciseRepo.save(fly)

        let groupId = UUID()
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Odd", notes: nil,
                exercises: [saveExercise(fly.id, order: 1, group: groupId, sets: [saveSet(order: 1)])]
            )
        )

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)
        XCTAssertEqual(detail.exercises.first?.supersetGroupId, groupId)

        // Re-save exactly what was read back, as an unmodified edit would.
        try await context.service.updateTemplate(
            templateId,
            data: TemplateSaveData(
                name: detail.template.name,
                notes: detail.template.notes,
                folder: detail.template.folder,
                exercises: detail.exercises.map { exercise in
                    TemplateSaveExercise(
                        exerciseId: exercise.exerciseId,
                        orderInTemplate: exercise.orderInTemplate,
                        supersetGroupId: exercise.supersetGroupId,
                        restTimeSeconds: exercise.restTimeSeconds,
                        notes: exercise.notes,
                        sets: exercise.sets.map {
                            TemplateSaveSet(
                                setType: $0.setType,
                                targetRepMin: $0.targetRepMin,
                                targetRepMax: $0.targetRepMax,
                                targetRIR: $0.targetRIR,
                                orderInExercise: $0.orderInExercise
                            )
                        }
                    )
                }
            )
        )

        let rereadFetched = try await context.service.fetchTemplateDetail(templateId)
        let reread = try XCTUnwrap(rereadFetched)
        XCTAssertEqual(reread.exercises.first?.supersetGroupId, groupId)
    }

    // MARK: - Regression: sets must stay with their own exercise

    func testEditorRoundTripKeepsEachSetWithItsOwnExercise() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        let incline = makeExercise(name: "Incline DB Press")
        let fly = makeExercise(name: "Cable Fly")
        for exercise in [bench, incline, fly] { try await context.exerciseRepo.save(exercise) }

        // Distinct set counts so a collapse onto one exercise is unmistakable: 3 / 1 / 2.
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push", notes: nil,
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [saveSet(order: 1), saveSet(order: 2), saveSet(order: 3)]),
                    saveExercise(incline.id, order: 2, sets: [saveSet(order: 1)]),
                    saveExercise(fly.id, order: 3, sets: [saveSet(order: 1), saveSet(order: 2)])
                ]
            )
        )

        let expected = ["Bench Press": 3, "Incline DB Press": 1, "Cable Fly": 2]

        let created = try await context.service.fetchTemplateDetail(templateId)
        let createdDetail = try XCTUnwrap(created)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: createdDetail.exercises.map { ($0.exerciseName, $0.sets.count) }),
            expected,
            "after create"
        )

        // Re-save exactly what was read back, three times — what opening and saving does.
        for pass in 1...3 {
            let fetched = try await context.service.fetchTemplateDetail(templateId)
            let detail = try XCTUnwrap(fetched)
            try await context.service.updateTemplate(
                templateId,
                data: TemplateSaveData(
                    name: detail.template.name,
                    notes: detail.template.notes,
                    folder: detail.template.folder,
                    exercises: detail.exercises.map { exercise in
                        TemplateSaveExercise(
                            exerciseId: exercise.exerciseId,
                            orderInTemplate: exercise.orderInTemplate,
                            supersetGroupId: exercise.supersetGroupId,
                            restTimeSeconds: exercise.restTimeSeconds,
                            notes: exercise.notes,
                            sets: exercise.sets.map {
                                TemplateSaveSet(
                                    setType: $0.setType,
                                    targetRepMin: $0.targetRepMin,
                                    targetRepMax: $0.targetRepMax,
                                    targetRIR: $0.targetRIR,
                                    orderInExercise: $0.orderInExercise
                                )
                            }
                        )
                    }
                )
            )

            let reread = try await context.service.fetchTemplateDetail(templateId)
            let rereadDetail = try XCTUnwrap(reread)
            XCTAssertEqual(
                Dictionary(uniqueKeysWithValues: rereadDetail.exercises.map { ($0.exerciseName, $0.sets.count) }),
                expected,
                "after save pass \(pass)"
            )
        }
    }

    func testSetsFromARemovedExerciseAreNotAdoptedByAnother() async throws {
        // "All sets moved to the first exercise" is what an orphaned-set bug looks like from outside.
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        let incline = makeExercise(name: "Incline DB Press")
        try await context.exerciseRepo.save(bench)
        try await context.exerciseRepo.save(incline)

        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push", notes: nil,
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)]),
                    saveExercise(incline.id, order: 2, sets: [saveSet(order: 1), saveSet(order: 2)])
                ]
            )
        )

        try await context.service.updateTemplate(
            templateId,
            data: TemplateSaveData(
                name: "Push", notes: nil,
                exercises: [saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)])]
            )
        )

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)
        let summaries = try await context.service.fetchAllTemplates()
        XCTAssertEqual(detail.exercises.count, 1)
        XCTAssertEqual(detail.exercises.first?.sets.count, 1, "Sets from the removed exercise must not reappear")
        XCTAssertEqual(detail.template.totalSetCount, 1)
        XCTAssertEqual(summaries.first?.totalSetCount, 1, "List count must agree with detail")
    }

    // MARK: - Save-as-template from a workout: set distribution

    func testSaveAsTemplateKeepsEachExercisesOwnSets() async throws {
        let context = try makeContext()
        let names = ["Back extension holds", "Assisted Pull Up", "Cable Row", "Cable Curl"]
        var exercises: [Exercise] = []
        for name in names {
            let exercise = makeExercise(name: name)
            try await context.exerciseRepo.save(exercise)
            exercises.append(exercise)
        }

        let workout = Workout(date: Date(), startTime: Date(), status: .completed)
        try await context.workoutRepo.save(workout)

        // 3 / 2 / 4 / 1 — deliberately uneven, and logged exercise-by-exercise.
        let counts = [3, 2, 4, 1]
        var order = 1
        for (exercise, count) in zip(exercises, counts) {
            for setIndex in 1...count {
                try await context.setRepo.save(
                    workoutSet(workout.id, exercise.id, order: order, group: nil, orderInExercise: setIndex)
                )
                order += 1
            }
        }

        let templateId = try await context.service.createTemplateFromWorkout(workout.id, name: "From Workout")
        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)

        XCTAssertEqual(detail.exercises.map(\.exerciseName), names)
        XCTAssertEqual(detail.exercises.map { $0.sets.count }, counts)
        XCTAssertEqual(detail.template.totalSetCount, 10)
    }

    func testSaveAsTemplateHandlesInterleavedSupersetLogging() async throws {
        // A superset is logged A, B, A, B, A, B — the sets are not contiguous per exercise, which is
        // the ordering most likely to break a grouping that assumed they were.
        let context = try makeContext()
        let fly = makeExercise(name: "Cable Fly")
        let raise = makeExercise(name: "Lateral Raise")
        try await context.exerciseRepo.save(fly)
        try await context.exerciseRepo.save(raise)

        let workout = Workout(date: Date(), startTime: Date(), status: .completed)
        try await context.workoutRepo.save(workout)

        var order = 1
        for round in 1...3 {
            for exercise in [fly, raise] {
                try await context.setRepo.save(
                    workoutSet(workout.id, exercise.id, order: order, group: nil, orderInExercise: round)
                )
                order += 1
            }
        }

        let templateId = try await context.service.createTemplateFromWorkout(workout.id, name: "Superset day")
        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)

        XCTAssertEqual(detail.exercises.map(\.exerciseName), ["Cable Fly", "Lateral Raise"])
        XCTAssertEqual(detail.exercises.map { $0.sets.count }, [3, 3], "Sets must not pile onto the first exercise")
    }

    func testSaveAsTemplateWithNineExercisesDoesNotCollapseOntoTheFirst() async throws {
        // The reported shape: 9 exercises, first showing 12 sets and the rest 1 each.
        let context = try makeContext()
        var exercises: [Exercise] = []
        for index in 1...9 {
            let exercise = makeExercise(name: "Exercise \(index)")
            try await context.exerciseRepo.save(exercise)
            exercises.append(exercise)
        }

        let workout = Workout(date: Date(), startTime: Date(), status: .completed)
        try await context.workoutRepo.save(workout)

        var order = 1
        for exercise in exercises {
            for setIndex in 1...2 {
                try await context.setRepo.save(
                    workoutSet(workout.id, exercise.id, order: order, group: nil, orderInExercise: setIndex)
                )
                order += 1
            }
        }

        let templateId = try await context.service.createTemplateFromWorkout(workout.id, name: "Upper Body 2")
        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)

        XCTAssertEqual(detail.exercises.count, 9)
        XCTAssertEqual(detail.exercises.map { $0.sets.count }, Array(repeating: 2, count: 9))
    }

    func testExportSkipsAnUnresolvableExerciseInsteadOfFailing() async throws {
        // A template holding a dangling reference is the one you most want a copy of. Throwing meant
        // the only way to get that data out was blocked precisely when it mattered.
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)

        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Half broken", notes: nil,
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [saveSet(order: 1), saveSet(order: 2)]),
                    saveExercise(UUID(), order: 2, sets: [saveSet(order: 1)])
                ]
            )
        )

        let data = try await context.service.exportTemplate(templateId)
        let archive = try JSONDecoder().decode(TemplateArchive.self, from: data)

        XCTAssertEqual(archive.template.name, "Half broken")
        XCTAssertEqual(archive.exercises.count, 1, "The resolvable exercise still exports")
        XCTAssertEqual(archive.exercises.first?.exercise.name, "Bench Press")
        XCTAssertEqual(archive.exercises.first?.sets.count, 2)
    }

    // MARK: - Filing from the list

    func testSettingAFolderRewritesOnlyTheFolder() async throws {
        // Moving a template from the list round-trips its whole structure through updateTemplate, so
        // the thing to prove is that nothing except the folder changes.
        let context = try makeContext()
        let fly = makeExercise(name: "Cable Fly")
        let raise = makeExercise(name: "Lateral Raise")
        try await context.exerciseRepo.save(fly)
        try await context.exerciseRepo.save(raise)

        let group = UUID()
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push", notes: "keep me",
                exercises: [
                    saveExercise(fly.id, order: 1, group: group, sets: [saveSet(order: 1, min: 12, max: 15, rir: 1)]),
                    saveExercise(raise.id, order: 2, group: group, sets: [saveSet(order: 1), saveSet(order: 2)])
                ]
            )
        )

        let beforeFetched = try await context.service.fetchTemplateDetail(templateId)
        let before = try XCTUnwrap(beforeFetched)

        try await context.service.updateTemplate(
            templateId,
            data: TemplateSaveData(
                name: before.template.name,
                notes: before.template.notes,
                folder: "Mesocycle 3",
                exercises: before.exercises.map { exercise in
                    TemplateSaveExercise(
                        exerciseId: exercise.exerciseId,
                        orderInTemplate: exercise.orderInTemplate,
                        supersetGroupId: exercise.supersetGroupId,
                        restTimeSeconds: exercise.restTimeSeconds,
                        notes: exercise.notes,
                        sets: exercise.sets.map {
                            TemplateSaveSet(
                                setType: $0.setType,
                                targetRepMin: $0.targetRepMin,
                                targetRepMax: $0.targetRepMax,
                                targetRIR: $0.targetRIR,
                                orderInExercise: $0.orderInExercise
                            )
                        }
                    )
                }
            )
        )

        let afterFetched = try await context.service.fetchTemplateDetail(templateId)
        let after = try XCTUnwrap(afterFetched)
        XCTAssertEqual(after.template.folder, "Mesocycle 3")
        XCTAssertEqual(after.template.name, "Push")
        XCTAssertEqual(after.template.notes, "keep me")
        XCTAssertEqual(after.exercises.map(\.exerciseName), ["Cable Fly", "Lateral Raise"])
        XCTAssertEqual(after.exercises.map { $0.sets.count }, [1, 2], "Set counts stay with their exercises")
        XCTAssertEqual(Set(after.exercises.compactMap(\.supersetGroupId)), [group])
        XCTAssertEqual(after.exercises[0].sets.first?.targetRepMin, 12)
    }

    // MARK: - D4 — a template whose exercise no longer resolves still renders

    func testTemplateWithMissingExerciseStillFetches() async throws {
        let context = try makeContext()
        let ghostId = UUID()
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Ghost", notes: nil,
                exercises: [saveExercise(ghostId, order: 1, sets: [saveSet(order: 1)])]
            )
        )

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)
        let summaries = try await context.service.fetchAllTemplates()
        XCTAssertEqual(detail.exercises.count, 1)
        XCTAssertEqual(detail.exercises.first?.exerciseName, "Unknown Exercise")
        XCTAssertEqual(summaries.count, 1)
    }

    // MARK: - P1.2 — the list read, now two actor round trips

    func testFetchAllTemplatesReportsCountsAndMuscleGroupsInTemplateOrder() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press", muscle: "chest")
        let raise = makeExercise(name: "Lateral Raise", muscle: "shoulders")
        let dip = makeExercise(name: "Dip", muscle: "chest")
        for exercise in [bench, raise, dip] { try await context.exerciseRepo.save(exercise) }

        _ = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push",
                notes: nil,
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [saveSet(order: 1), saveSet(order: 2)]),
                    saveExercise(raise.id, order: 2, sets: [saveSet(order: 1)]),
                    saveExercise(dip.id, order: 3, sets: [saveSet(order: 1)])
                ]
            )
        )

        let allSummaries = try await context.service.fetchAllTemplates()
        let summary = try XCTUnwrap(allSummaries.first)
        XCTAssertEqual(summary.exerciseCount, 3)
        XCTAssertEqual(summary.totalSetCount, 4)
        // First-seen order, de-duplicated: chest from Bench, shoulders from Raise, Dip repeats chest.
        XCTAssertEqual(summary.muscleGroups, ["chest", "shoulders"])
    }

    func testFetchAllTemplatesSortsByLastUsedThenCreated() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)

        let first = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "First")
        _ = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Second")
        let third = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Third")

        // Used templates lead, most recent first; unused fall back to newest-created.
        _ = try await context.service.startWorkoutFromTemplate(first)
        try await Task.sleep(for: .milliseconds(10))
        _ = try await context.service.startWorkoutFromTemplate(third)

        let names = try await context.service.fetchAllTemplates().map(\.name)
        XCTAssertEqual(names, ["Third", "First", "Second"])
    }

    func testFetchAllTemplatesIncludesTemplatesWithNoExercises() async throws {
        // D4: an inner join would drop this row and the template would look deleted.
        let context = try makeContext()
        _ = try await context.service.createTemplate(
            TemplateSaveData(name: "Empty", notes: nil, exercises: [])
        )

        let allSummaries = try await context.service.fetchAllTemplates()
        let summary = try XCTUnwrap(allSummaries.first)
        XCTAssertEqual(summary.name, "Empty")
        XCTAssertEqual(summary.exerciseCount, 0)
        XCTAssertEqual(summary.totalSetCount, 0)
        XCTAssertTrue(summary.muscleGroups.isEmpty)
    }

    func testFetchAllTemplatesCountsSetsPerTemplateNotAcrossThem() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)

        _ = try await context.service.createTemplate(
            TemplateSaveData(name: "Two sets", notes: nil,
                             exercises: [saveExercise(bench.id, order: 1, sets: [saveSet(order: 1), saveSet(order: 2)])])
        )
        _ = try await context.service.createTemplate(
            TemplateSaveData(name: "One set", notes: nil,
                             exercises: [saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)])])
        )

        let byName = Dictionary(uniqueKeysWithValues: try await context.service.fetchAllTemplates().map { ($0.name, $0) })
        XCTAssertEqual(byName["Two sets"]?.totalSetCount, 2)
        XCTAssertEqual(byName["One set"]?.totalSetCount, 1)
    }

    // MARK: - P1.3 — duplicate

    func testDuplicateCopiesStructureFolderAndSupersetGroupsUnderACopyName() async throws {
        let context = try makeContext()
        let fly = makeExercise(name: "Cable Fly")
        let raise = makeExercise(name: "Lateral Raise")
        try await context.exerciseRepo.save(fly)
        try await context.exerciseRepo.save(raise)

        let groupId = UUID()
        let originalId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push Day A",
                notes: "top set then back off",
                folder: "Mesocycle 3",
                exercises: [
                    saveExercise(fly.id, order: 1, group: groupId, sets: [saveSet(order: 1, min: 12, max: 15, rir: 1)]),
                    saveExercise(raise.id, order: 2, group: groupId, sets: [saveSet(order: 1), saveSet(order: 2)])
                ]
            )
        )

        let copyId = try await context.service.duplicateTemplate(originalId)
        XCTAssertNotEqual(copyId, originalId)

        let fetchedCopy = try await context.service.fetchTemplateDetail(copyId)
        let copyDetail = try XCTUnwrap(fetchedCopy)
        XCTAssertEqual(copyDetail.template.name, "Push Day A (Copy)")
        XCTAssertEqual(copyDetail.template.notes, "top set then back off")
        XCTAssertEqual(copyDetail.template.folder, "Mesocycle 3")
        XCTAssertEqual(copyDetail.exercises.map(\.exerciseName), ["Cable Fly", "Lateral Raise"])
        XCTAssertEqual(Set(copyDetail.exercises.compactMap(\.supersetGroupId)), [groupId])
        XCTAssertEqual(copyDetail.exercises[0].sets.count, 1)
        XCTAssertEqual(copyDetail.exercises[1].sets.count, 2)
        XCTAssertEqual(copyDetail.exercises[0].sets.first?.targetRepMin, 12)

        // The original is untouched.
        let fetchedOriginal = try await context.service.fetchTemplateDetail(originalId)
        let originalDetail = try XCTUnwrap(fetchedOriginal)
        XCTAssertEqual(originalDetail.template.name, "Push Day A")
        XCTAssertEqual(originalDetail.exercises.count, 2)
    }

    func testDuplicatingTwiceNumbersTheSecondCopy() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let originalId = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Push")

        _ = try await context.service.duplicateTemplate(originalId)
        _ = try await context.service.duplicateTemplate(originalId)

        let names = Set(try await context.service.fetchAllTemplates().map(\.name))
        XCTAssertEqual(names, ["Push", "Push (Copy)", "Push (Copy 2)"])
    }

    func testDuplicateThrowsForAMissingTemplate() async throws {
        let context = try makeContext()
        do {
            _ = try await context.service.duplicateTemplate(UUID())
            XCTFail("Expected duplicateTemplate to throw for an unknown id")
        } catch {
            // Expected.
        }
    }

    // MARK: - The detail read

    func testAnExerciseDeletedFromTheLibraryStillResolvesThroughTheRowsPath() async throws {
        // The lenient resolve has to survive the switch from a per-exercise fetch to one snapshot
        // lookup — a dangling row must read as "Unknown Exercise", not disappear and not throw.
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let ghostId = UUID()

        let templateId = try await context.service.createTemplate(
            TemplateSaveData(name: "Push", notes: nil, exercises: [
                saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)]),
                saveExercise(ghostId, order: 2, sets: [saveSet(order: 1), saveSet(order: 2)])
            ])
        )

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)

        XCTAssertEqual(detail.exercises.map(\.exerciseName), ["Bench Press", "Unknown Exercise"])
        XCTAssertEqual(detail.exercises.map(\.sets.count), [1, 2])
        XCTAssertNil(detail.exercises[1].primaryMuscle)
        XCTAssertEqual(detail.template.totalSetCount, 3)
        XCTAssertEqual(detail.template.muscleGroups, ["chest"])
    }

    func testDetailRowsCarrySetsOnlyForTheirOwnExercise() async throws {
        // The rows path fetches every TemplateSet once and groups them, rather than querying per
        // exercise. A grouping mistake here is exactly the reparenting this feature was investigated
        // for, so it is asserted directly rather than through a count.
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        let fly = makeExercise(name: "Cable Fly")
        try await context.exerciseRepo.save(bench)
        try await context.exerciseRepo.save(fly)

        let mine = try await context.service.createTemplate(
            TemplateSaveData(name: "Push", notes: nil, exercises: [
                saveExercise(bench.id, order: 1, sets: [saveSet(order: 1, min: 3, max: 5)]),
                saveExercise(fly.id, order: 2, sets: [
                    saveSet(order: 1, min: 12, max: 15), saveSet(order: 2, min: 12, max: 15)
                ])
            ])
        )
        // A second template's sets live in the same table and must not leak in.
        _ = try await context.service.createTemplate(
            TemplateSaveData(name: "Pull", notes: nil, exercises: [
                saveExercise(bench.id, order: 1, sets: [saveSet(order: 1), saveSet(order: 2), saveSet(order: 3)])
            ])
        )

        let fetchedRows = try await context.templateRepo.fetchTemplateDetailRows(templateId: mine)
        let rows = try XCTUnwrap(fetchedRows)

        XCTAssertEqual(rows.exercises.map(\.sets.count), [1, 2])
        XCTAssertEqual(rows.exercises[0].sets.map(\.targetRepMin), [3])
        XCTAssertEqual(rows.exercises[1].sets.map(\.targetRepMin), [12, 12])
        XCTAssertEqual(rows.exercises[1].sets.map(\.orderInExercise), [1, 2])
    }

    func testDetailRowsAreNilForAMissingTemplate() async throws {
        let context = try makeContext()
        let rows = try await context.templateRepo.fetchTemplateDetailRows(templateId: UUID())
        XCTAssertNil(rows)
    }

    // MARK: - Filing a template into a folder

    func testMovingATemplateToAFolderLeavesItsContentsUntouched() async throws {
        // Filing used to read the whole detail and push it back through replaceTemplateContents,
        // which deletes and recreates every row to change one nullable string.
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        let fly = makeExercise(name: "Cable Fly")
        try await context.exerciseRepo.save(bench)
        try await context.exerciseRepo.save(fly)

        let templateId = try await context.service.createTemplate(
            TemplateSaveData(name: "Push", notes: "leave me", exercises: [
                saveExercise(bench.id, order: 1, sets: [saveSet(order: 1), saveSet(order: 2)]),
                saveExercise(fly.id, order: 2, sets: [saveSet(order: 1)])
            ])
        )

        let before = try await context.templateRepo.fetchTemplateExercises(for: templateId)
        let beforeExerciseIds = before.map(\.id)
        let beforeCreatedAt = before.map(\.createdAt)
        var beforeSetIds: [UUID] = []
        for row in before {
            beforeSetIds += try await context.templateRepo.fetchTemplateSets(for: row.id).map(\.id)
        }

        try await context.service.updateTemplateFolder(templateId, folder: "Push Days")

        let after = try await context.templateRepo.fetchTemplateExercises(for: templateId)
        var afterSetIds: [UUID] = []
        for row in after {
            afterSetIds += try await context.templateRepo.fetchTemplateSets(for: row.id).map(\.id)
        }

        // The same rows, not equivalent replacements.
        XCTAssertEqual(after.map(\.id), beforeExerciseIds)
        XCTAssertEqual(afterSetIds, beforeSetIds)
        XCTAssertEqual(after.map(\.createdAt), beforeCreatedAt)

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)
        XCTAssertEqual(detail.template.folder, "Push Days")
        XCTAssertEqual(detail.template.notes, "leave me")
        XCTAssertEqual(detail.exercises.map(\.sets.count), [2, 1])
    }

    func testMovingATemplateOutOfAFolderClearsIt() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(name: "Push", notes: nil, folder: "Push Days", exercises: [
                saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)])
            ])
        )

        try await context.service.updateTemplateFolder(templateId, folder: nil)

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        XCTAssertNil(try XCTUnwrap(fetched).template.folder)
    }

    func testMovingToAWhitespaceFolderNameFilesItNowhere() async throws {
        // The editor's path normalises through TemplateSaveData; this one has to match or a folder
        // named "   " appears in the list.
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let templateId = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Push")

        try await context.service.updateTemplateFolder(templateId, folder: "   ")

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        XCTAssertNil(try XCTUnwrap(fetched).template.folder)
    }

    func testMovingTrimsTheFolderName() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let templateId = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Push")

        try await context.service.updateTemplateFolder(templateId, folder: "  Push Days  ")

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        XCTAssertEqual(try XCTUnwrap(fetched).template.folder, "Push Days")
    }

    func testMovingAMissingTemplateThrows() async throws {
        let context = try makeContext()
        do {
            try await context.service.updateTemplateFolder(UUID(), folder: "Push Days")
            XCTFail("Expected updateTemplateFolder to throw for an unknown id")
        } catch {
            // Expected.
        }
    }

    // MARK: - Deleting an exercise that templates point at
    //
    // `ExerciseService.deleteExercise` calls itself a full cascade and skipped templates entirely,
    // so a deleted exercise left a `TemplateExercise` row behind that resolved to nothing. The
    // template rendered it as "Unknown Exercise" forever and kept counting its sets in the total.
    // Two real templates on a user device were found holding one each.

    func testDeletingAnExerciseRemovesItsTemplateRowAndItsSets() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        let fly = makeExercise(name: "Cable Fly")
        let press = makeExercise(name: "Overhead Press")
        for exercise in [bench, fly, press] { try await context.exerciseRepo.save(exercise) }

        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push",
                notes: nil,
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [saveSet(order: 1), saveSet(order: 2)]),
                    saveExercise(fly.id, order: 2, sets: [saveSet(order: 1), saveSet(order: 2), saveSet(order: 3)]),
                    saveExercise(press.id, order: 3, sets: [saveSet(order: 1)])
                ]
            )
        )

        let removed = try await context.templateRepo.deleteTemplateReferences(toExerciseId: fly.id)
        XCTAssertEqual(removed, 1)

        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)
        XCTAssertEqual(detail.exercises.map(\.exerciseId), [bench.id, press.id])
        XCTAssertFalse(detail.exercises.contains { $0.exerciseName == "Unknown Exercise" })

        // The 3 sets went with it, and nobody else's moved or vanished.
        XCTAssertEqual(detail.template.totalSetCount, 3)
        XCTAssertEqual(detail.exercises.map(\.sets.count), [2, 1])
    }

    func testDeletingAnExerciseClosesTheOrderGapItLeaves() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        let fly = makeExercise(name: "Cable Fly")
        let press = makeExercise(name: "Overhead Press")
        for exercise in [bench, fly, press] { try await context.exerciseRepo.save(exercise) }

        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push",
                notes: nil,
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)]),
                    saveExercise(fly.id, order: 2, sets: [saveSet(order: 1)]),
                    saveExercise(press.id, order: 3, sets: [saveSet(order: 1)])
                ]
            )
        )

        try await context.templateRepo.deleteTemplateReferences(toExerciseId: fly.id)

        // Not [1, 3]: a gap survives every read and export, and reads as a missing exercise.
        let rows = try await context.templateRepo.fetchTemplateExercises(for: templateId)
        XCTAssertEqual(rows.map(\.orderInTemplate), [1, 2])
        XCTAssertEqual(rows.map(\.exerciseId), [bench.id, press.id])
    }

    func testDeletingOneHalfOfASupersetDissolvesTheGroup() async throws {
        let context = try makeContext()
        let fly = makeExercise(name: "Cable Fly")
        let raise = makeExercise(name: "Lateral Raise")
        let bench = makeExercise(name: "Bench Press")
        for exercise in [fly, raise, bench] { try await context.exerciseRepo.save(exercise) }

        let groupId = UUID()
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push",
                notes: nil,
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)]),
                    saveExercise(fly.id, order: 2, group: groupId, sets: [saveSet(order: 1)]),
                    saveExercise(raise.id, order: 3, group: groupId, sets: [saveSet(order: 1)])
                ]
            )
        )

        try await context.templateRepo.deleteTemplateReferences(toExerciseId: fly.id)

        // A group of one is the state the pairing flow exists to prevent (SUPERSETS_SCOPING.md §6).
        let rows = try await context.templateRepo.fetchTemplateExercises(for: templateId)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.supersetGroupId == nil })
    }

    func testDeletingAnExerciseLeavesASupersetOfTwoSurvivorsIntact() async throws {
        let context = try makeContext()
        let fly = makeExercise(name: "Cable Fly")
        let raise = makeExercise(name: "Lateral Raise")
        let bench = makeExercise(name: "Bench Press")
        for exercise in [fly, raise, bench] { try await context.exerciseRepo.save(exercise) }

        let groupId = UUID()
        let templateId = try await context.service.createTemplate(
            TemplateSaveData(
                name: "Push",
                notes: nil,
                exercises: [
                    saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)]),
                    saveExercise(fly.id, order: 2, group: groupId, sets: [saveSet(order: 1)]),
                    saveExercise(raise.id, order: 3, group: groupId, sets: [saveSet(order: 1)])
                ]
            )
        )

        try await context.templateRepo.deleteTemplateReferences(toExerciseId: bench.id)

        let rows = try await context.templateRepo.fetchTemplateExercises(for: templateId)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap(\.supersetGroupId)), [groupId])
    }

    func testDeletingAnExerciseReachesEveryTemplateUsingItAndNoOthers() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        let fly = makeExercise(name: "Cable Fly")
        try await context.exerciseRepo.save(bench)
        try await context.exerciseRepo.save(fly)

        let usesFly = try await context.service.createTemplate(
            TemplateSaveData(name: "Push", notes: nil, exercises: [
                saveExercise(bench.id, order: 1, sets: [saveSet(order: 1)]),
                saveExercise(fly.id, order: 2, sets: [saveSet(order: 1)])
            ])
        )
        let alsoUsesFly = try await context.service.createTemplate(
            TemplateSaveData(name: "Chest", notes: nil, exercises: [
                saveExercise(fly.id, order: 1, sets: [saveSet(order: 1), saveSet(order: 2)])
            ])
        )
        let untouched = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Legs")

        let removed = try await context.templateRepo.deleteTemplateReferences(toExerciseId: fly.id)
        XCTAssertEqual(removed, 2)

        let pushRows = try await context.templateRepo.fetchTemplateExercises(for: usesFly)
        XCTAssertEqual(pushRows.map(\.exerciseId), [bench.id])
        // A template can be emptied by this. It is left alive and empty rather than deleted: losing a
        // named template as a side effect of an unrelated library edit would be the bigger surprise.
        let chestRows = try await context.templateRepo.fetchTemplateExercises(for: alsoUsesFly)
        XCTAssertTrue(chestRows.isEmpty)
        let legsRows = try await context.templateRepo.fetchTemplateExercises(for: untouched)
        XCTAssertEqual(legsRows.map(\.exerciseId), [bench.id])
        let legsSets = try await context.templateRepo.fetchTemplateSets(for: legsRows[0].id)
        XCTAssertEqual(legsSets.count, 2)
    }

    func testDeletingAnExerciseNoTemplateUsesChangesNothing() async throws {
        let context = try makeContext()
        let bench = makeExercise(name: "Bench Press")
        try await context.exerciseRepo.save(bench)
        let templateId = try await makeSimpleTemplate(context, exerciseId: bench.id, name: "Push")

        let removed = try await context.templateRepo.deleteTemplateReferences(toExerciseId: UUID())

        XCTAssertEqual(removed, 0)
        let fetched = try await context.service.fetchTemplateDetail(templateId)
        let detail = try XCTUnwrap(fetched)
        XCTAssertEqual(detail.exercises.count, 1)
        XCTAssertEqual(detail.template.totalSetCount, 2)
    }

    // MARK: - Harness

    private func makeContext() throws -> Context {
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

        return Context(
            service: TemplateService(
                templateRepository: templateRepo,
                workoutRepository: workoutRepo,
                setRepository: setRepo,
                exerciseRepository: exerciseRepo
            ),
            templateRepo: templateRepo,
            exerciseRepo: exerciseRepo,
            workoutRepo: workoutRepo,
            setRepo: setRepo
        )
    }

    private struct Context {
        let service: TemplateService
        let templateRepo: TemplateRepository
        let exerciseRepo: ExerciseRepository
        let workoutRepo: WorkoutRepository
        let setRepo: SetRepository
    }

    private func makeExercise(name: String, muscle: String = "chest") -> Exercise {
        Exercise(
            name: name,
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: muscle
        )
    }

    private func makeSimpleTemplate(
        _ context: Context,
        exerciseId: UUID,
        name: String
    ) async throws -> UUID {
        try await context.service.createTemplate(
            TemplateSaveData(
                name: name,
                notes: nil,
                exercises: [saveExercise(exerciseId, order: 1, sets: [saveSet(order: 1), saveSet(order: 2)])]
            )
        )
    }

    private func saveExercise(
        _ exerciseId: UUID,
        order: Int,
        group: UUID? = nil,
        sets: [TemplateSaveSet]
    ) -> TemplateSaveExercise {
        TemplateSaveExercise(
            exerciseId: exerciseId,
            orderInTemplate: order,
            supersetGroupId: group,
            restTimeSeconds: nil,
            notes: nil,
            sets: sets
        )
    }

    private func saveSet(order: Int, min: Int? = 8, max: Int? = 10, rir: Int? = 2) -> TemplateSaveSet {
        TemplateSaveSet(
            setType: .working,
            targetRepMin: min,
            targetRepMax: max,
            targetRIR: rir,
            orderInExercise: order
        )
    }

    private func workoutSet(
        _ workoutId: UUID,
        _ exerciseId: UUID,
        order: Int,
        group: UUID?,
        orderInExercise: Int? = nil
    ) -> WorkoutSet {
        WorkoutSet(
            workoutId: workoutId,
            exerciseId: exerciseId,
            date: Date(),
            weight: 60,
            reps: 8,
            setType: .working,
            orderInWorkout: order,
            orderInExercise: orderInExercise ?? order,
            supersetGroupId: group,
            completed: true
        )
    }
}

// MARK: - List shaping

/// Pure grouping rules: no service, no main actor. Each of these is a decision the design argued
/// about, so each gets a line.
final class TemplateListGroupingTests: XCTestCase {

    func testChipsPutAllFirstAndGiveUngroupedNoChipOfItsOwn() {
        let templates = [
            summary(name: "Push", folder: "Mesocycle 3"),
            summary(name: "Pull", folder: "Mesocycle 3"),
            summary(name: "Arms", folder: "Accessory"),
            summary(name: "Hotel Gym", folder: nil)
        ]

        let chips = TemplateListGrouping.chips(for: templates)

        XCTAssertEqual(chips.first?.id, TemplateFolderChip.allID)
        XCTAssertEqual(chips.first?.count, 4, "All counts every template, folder or not")
        // None of these has been used, so folders tie on recency and fall back to name order.
        XCTAssertEqual(chips.map(\.name), ["All", "Accessory", "Mesocycle 3"])
        XCTAssertEqual(chips.map(\.count), [4, 1, 2])
    }

    func testChipsAreEmptyWithNoTemplates() {
        XCTAssertTrue(TemplateListGrouping.chips(for: []).isEmpty)
    }

    func testFoldersOrderByMostRecentlyUsedTemplate() {
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 9_000)
        let templates = [
            summary(name: "Arms", folder: "Accessory", lastUsedAt: recent),
            summary(name: "Push", folder: "Mesocycle 3", lastUsedAt: old)
        ]

        let sections = TemplateListGrouping.sections(for: templates, selectedFolderID: nil, searchText: "")
        XCTAssertEqual(sections.map(\.title), ["Accessory", "Mesocycle 3"])
    }

    func testUnusedFoldersFallBackToNameOrder() {
        let templates = [
            summary(name: "Zebra", folder: "Zone 2"),
            summary(name: "Alpha", folder: "Accessory")
        ]
        let sections = TemplateListGrouping.sections(for: templates, selectedFolderID: nil, searchText: "")
        XCTAssertEqual(sections.map(\.title), ["Accessory", "Zone 2"])
    }

    func testUngroupedSectionIsAlwaysLastAndAlwaysShown() {
        let templates = [
            summary(name: "Hotel Gym", folder: nil, lastUsedAt: Date()),
            summary(name: "Push", folder: "Mesocycle 3", lastUsedAt: Date(timeIntervalSince1970: 1))
        ]

        let sections = TemplateListGrouping.sections(for: templates, selectedFolderID: nil, searchText: "")
        XCTAssertEqual(sections.map(\.title), ["Mesocycle 3", TemplateListGrouping.ungroupedTitle])
        XCTAssertEqual(sections.last?.templates.map(\.name), ["Hotel Gym"])
    }

    func testSelectingAFolderGivesOneUntitledSection() {
        let templates = [
            summary(name: "Push", folder: "Mesocycle 3"),
            summary(name: "Arms", folder: "Accessory")
        ]
        let key = try! XCTUnwrap(TemplateFolder.groupingKey("Mesocycle 3"))

        let sections = TemplateListGrouping.sections(for: templates, selectedFolderID: key, searchText: "")

        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections.first?.title, "Headers repeat the chip the user just tapped")
        XCTAssertEqual(sections.first?.templates.map(\.name), ["Push"])
    }

    func testFolderNamesDifferingOnlyByCaseAreOneFolder() {
        let templates = [
            summary(name: "Push", folder: "Deload"),
            summary(name: "Pull", folder: "deload"),
            summary(name: "Legs", folder: "  DELOAD ")
        ]

        let chips = TemplateListGrouping.chips(for: templates)
        XCTAssertEqual(chips.count, 2, "All plus one folder")
        XCTAssertEqual(chips.last?.count, 3)
        XCTAssertEqual(chips.last?.name, "Deload", "First spelling seen supplies the display name")

        let sections = TemplateListGrouping.sections(for: templates, selectedFolderID: nil, searchText: "")
        XCTAssertEqual(sections.count, 1)
    }

    func testSearchMatchesNameOrFolder() {
        let templates = [
            summary(name: "Push Day A", folder: "Mesocycle 3"),
            summary(name: "Hotel Gym", folder: nil),
            summary(name: "Arms", folder: "Deload")
        ]

        let byName = TemplateListGrouping.sections(for: templates, selectedFolderID: nil, searchText: "hotel")
        XCTAssertEqual(byName.flatMap { $0.templates }.map(\.name), ["Hotel Gym"])

        let byFolder = TemplateListGrouping.sections(for: templates, selectedFolderID: nil, searchText: "deload")
        XCTAssertEqual(byFolder.flatMap { $0.templates }.map(\.name), ["Arms"])

        let blank = TemplateListGrouping.sections(for: templates, selectedFolderID: nil, searchText: "   ")
        XCTAssertEqual(blank.flatMap { $0.templates }.count, 3, "Whitespace is not a query")
    }

    func testSearchNarrowsWithinASelectedFolder() {
        let templates = [
            summary(name: "Push Day A", folder: "Mesocycle 3"),
            summary(name: "Pull Day A", folder: "Mesocycle 3")
        ]
        let key = try! XCTUnwrap(TemplateFolder.groupingKey("Mesocycle 3"))

        let sections = TemplateListGrouping.sections(for: templates, selectedFolderID: key, searchText: "pull")
        XCTAssertEqual(sections.flatMap { $0.templates }.map(\.name), ["Pull Day A"])
    }

    func testNoMatchesYieldsNoSections() {
        let templates = [summary(name: "Push", folder: nil)]
        XCTAssertTrue(TemplateListGrouping.sections(for: templates, selectedFolderID: nil, searchText: "zzz").isEmpty)
    }

    private func summary(
        name: String,
        folder: String?,
        lastUsedAt: Date? = nil
    ) -> TemplateSummary {
        TemplateSummary(
            id: UUID(),
            name: name,
            notes: nil,
            folder: folder,
            exerciseCount: 3,
            totalSetCount: 9,
            muscleGroups: [],
            lastUsedAt: lastUsedAt,
            createdAt: Date()
        )
    }
}

// MARK: - Detail layout

/// Numbering and superset grouping for the detail screen.
final class TemplateDetailLayoutTests: XCTestCase {

    func testPlainExercisesNumberSequentially() {
        let rows = TemplateDetailLayout.rows(for: [
            exercise(name: "Bench Press", order: 1),
            exercise(name: "Incline DB Press", order: 2),
            exercise(name: "Cable Fly", order: 3)
        ])

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(numberLabel), ["1", "2", "3"])
    }

    func testAdjacentPairCollapsesIntoOneBlockSharingAPosition() {
        let group = UUID()
        let rows = TemplateDetailLayout.rows(for: [
            exercise(name: "Bench Press", order: 1),
            exercise(name: "Incline DB Press", order: 2),
            exercise(name: "Cable Fly", order: 3, group: group),
            exercise(name: "Lateral Raise", order: 4, group: group),
            exercise(name: "Rope Pushdown", order: 5)
        ])

        XCTAssertEqual(rows.count, 4, "The pair occupies one row, not two")

        guard case let .superset(_, letter, members) = rows[2] else {
            return XCTFail("Expected a superset block at position 3")
        }
        XCTAssertEqual(letter, "A")
        XCTAssertEqual(members.map(\.label), ["3a", "3b"])
        XCTAssertEqual(members.map(\.exercise.exerciseName), ["Cable Fly", "Lateral Raise"])

        // The exercise after the pair continues from the shared position, not from 5.
        XCTAssertEqual(numberLabel(rows[3]), "4")
    }

    func testGroupOfOneRendersAsAnOrdinaryExercise() {
        // Today's editor makes these trivially, so they exist in real libraries. A block holding one
        // exercise would look broken; the stored id is untouched either way.
        let rows = TemplateDetailLayout.rows(for: [
            exercise(name: "Cable Fly", order: 1, group: UUID())
        ])

        XCTAssertEqual(rows.count, 1)
        guard case .single = rows[0] else {
            return XCTFail("A group of one should render as a single exercise")
        }
    }

    func testNonAdjacentGroupMembersAreNotCollapsed() {
        // SUPERSETS_SCOPING.md §6 constraint 1 requires groups to be contiguous. Data that predates
        // it — or arrives via import, where a free-text key maps to a UUID — can break that. Showing
        // them apart is honest about what is stored; silently reordering would not be.
        let group = UUID()
        let rows = TemplateDetailLayout.rows(for: [
            exercise(name: "Cable Fly", order: 1, group: group),
            exercise(name: "Bench Press", order: 2),
            exercise(name: "Lateral Raise", order: 3, group: group)
        ])

        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { if case .single = $0 { return true } else { return false } })
        XCTAssertEqual(rows.map(numberLabel), ["1", "2", "3"])
    }

    func testLettersFollowEncounterOrderNotUUIDOrder() {
        let first = UUID()
        let second = UUID()
        let rows = TemplateDetailLayout.rows(for: [
            exercise(name: "A1", order: 1, group: first),
            exercise(name: "A2", order: 2, group: first),
            exercise(name: "B1", order: 3, group: second),
            exercise(name: "B2", order: 4, group: second)
        ])

        let letters = rows.compactMap { row -> String? in
            guard case let .superset(_, letter, _) = row else { return nil }
            return letter
        }
        XCTAssertEqual(letters, ["A", "B"])
    }

    func testRowsSortByOrderInTemplateRegardlessOfInputOrder() {
        let rows = TemplateDetailLayout.rows(for: [
            exercise(name: "Third", order: 3),
            exercise(name: "First", order: 1),
            exercise(name: "Second", order: 2)
        ])

        let names = rows.compactMap { row -> String? in
            guard case let .single(_, exercise) = row else { return nil }
            return exercise.exerciseName
        }
        XCTAssertEqual(names, ["First", "Second", "Third"])
    }

    func testPrescriptionFormatsRangeFixedAndOpenTargets() {
        XCTAssertEqual(TemplateDetailLayout.prescription(for: [set(min: 6, max: 8), set(min: 6, max: 8)]), "2 × 6–8")
        // A fixed target reads as a single number — the shape the two-field editor makes deliberate.
        XCTAssertEqual(TemplateDetailLayout.prescription(for: [set(min: 8, max: 8)]), "1 × 8")
        XCTAssertEqual(TemplateDetailLayout.prescription(for: [set(min: 5, max: nil)]), "1 × 5+")
        XCTAssertEqual(TemplateDetailLayout.prescription(for: [set(min: nil, max: 12)]), "1 × ≤12")
        XCTAssertEqual(TemplateDetailLayout.prescription(for: [set(min: nil, max: nil)]), "1 set")
        XCTAssertNil(TemplateDetailLayout.prescription(for: []))
    }

    func testWarmupsAreCountedSeparatelyAndExcludedFromThePrescription() {
        let sets = [set(min: nil, max: nil, type: .warmup), set(min: nil, max: nil, type: .warmup), set(min: 6, max: 8)]
        XCTAssertEqual(TemplateDetailLayout.warmupCount(for: sets), 2)
        XCTAssertEqual(TemplateDetailLayout.prescription(for: sets), "1 × 6–8")
    }

    // MARK: - Helpers

    private func numberLabel(_ row: TemplateDetailRow) -> String {
        switch row {
        case let .single(number, _): return "\(number)"
        case let .superset(_, _, members): return members.first?.label ?? "?"
        }
    }

    private func exercise(
        name: String,
        order: Int,
        group: UUID? = nil,
        sets: [TemplateSetDetail] = []
    ) -> TemplateExerciseDetail {
        TemplateExerciseDetail(
            id: UUID(),
            exerciseId: UUID(),
            exerciseName: name,
            primaryMuscle: "chest",
            orderInTemplate: order,
            supersetGroupId: group,
            restTimeSeconds: nil,
            notes: nil,
            sets: sets
        )
    }

    private func set(min: Int?, max: Int?, type: SetType = .working) -> TemplateSetDetail {
        TemplateSetDetail(
            id: UUID(),
            setType: type,
            targetRepMin: min,
            targetRepMax: max,
            targetRIR: nil,
            orderInExercise: 1
        )
    }
}

// MARK: - Superset pairing in the editor

/// The pairing model that replaced the letter picker. Every case here is one the old flow either
/// allowed by accident or made hard to reach.
@MainActor
final class TemplateEditorSupersetTests: XCTestCase {

    func testPairingTwoExercisesGivesThemOneGroupAndAssignsTheLetter() throws {
        let viewModel = try makeViewModel(exerciseNames: ["Bench Press", "Cable Fly", "Lateral Raise"])

        XCTAssertEqual(viewModel.nextSupersetLetter, "A")
        viewModel.pairExercise(exerciseId: viewModel.exercises[1].id, withPartnerId: viewModel.exercises[2].id)

        let groups = viewModel.exercises.map(\.supersetGroupId)
        XCTAssertNil(groups[0])
        XCTAssertNotNil(groups[1])
        XCTAssertEqual(groups[1], groups[2], "Both sides of the pair share one group")
        XCTAssertEqual(viewModel.supersetLabel(for: groups[1]), "A", "The app assigns the letter, not the user")
        XCTAssertEqual(viewModel.nextSupersetLetter, "B")
    }

    func testPairingANonAdjacentPartnerMovesItNextToTheSubject() throws {
        // SUPERSETS_SCOPING.md §6 constraint 1: a group must be contiguous. The picker warns that
        // this will happen; this is the move itself.
        let viewModel = try makeViewModel(exerciseNames: ["Bench Press", "Incline DB Press", "Rope Pushdown"])

        viewModel.pairExercise(exerciseId: viewModel.exercises[0].id, withPartnerId: viewModel.exercises[2].id)

        XCTAssertEqual(viewModel.exercises.map(\.exerciseName), ["Bench Press", "Rope Pushdown", "Incline DB Press"])
        XCTAssertEqual(viewModel.exercises[0].supersetGroupId, viewModel.exercises[1].supersetGroupId)
        XCTAssertNil(viewModel.exercises[2].supersetGroupId)
    }

    func testRemovingFromASupersetDissolvesTheWholeGroup() throws {
        // Groups are pairs for now, so clearing one side would leave the other in a group of one —
        // the state the whole pairing flow exists to prevent.
        let viewModel = try makeViewModel(exerciseNames: ["Cable Fly", "Lateral Raise"])
        viewModel.pairExercise(exerciseId: viewModel.exercises[0].id, withPartnerId: viewModel.exercises[1].id)
        XCTAssertNotNil(viewModel.exercises[0].supersetGroupId)

        viewModel.removeFromSuperset(exerciseId: viewModel.exercises[0].id)

        XCTAssertTrue(viewModel.exercises.allSatisfy { $0.supersetGroupId == nil })
        XCTAssertEqual(viewModel.nextSupersetLetter, "A", "The letter is free again")
    }

    func testRepairingAnAlreadyGroupedExerciseDoesNotStrandItsOldPartner() throws {
        let viewModel = try makeViewModel(exerciseNames: ["A", "B", "C", "D"])
        viewModel.pairExercise(exerciseId: viewModel.exercises[0].id, withPartnerId: viewModel.exercises[1].id)

        // Pair A with C instead. B must not be left holding a group by itself.
        let idOfC = try XCTUnwrap(viewModel.exercises.first { $0.exerciseName == "C" }?.id)
        let idOfA = try XCTUnwrap(viewModel.exercises.first { $0.exerciseName == "A" }?.id)
        viewModel.pairExercise(exerciseId: idOfA, withPartnerId: idOfC)

        let byName = Dictionary(uniqueKeysWithValues: viewModel.exercises.map { ($0.exerciseName, $0.supersetGroupId) })
        XCTAssertNotNil(byName["A"] ?? nil)
        XCTAssertEqual(byName["A"], byName["C"])
        XCTAssertNil(byName["B"] ?? nil, "The old partner is released, not left in a group of one")
        XCTAssertNil(byName["D"] ?? nil)
    }

    func testCandidatesExcludeSelfAndMarkAlreadyGroupedOnesUnselectable() throws {
        let viewModel = try makeViewModel(exerciseNames: ["Bench", "Fly", "Raise", "Pushdown"])
        viewModel.pairExercise(exerciseId: viewModel.exercises[1].id, withPartnerId: viewModel.exercises[2].id)

        let idOfBench = try XCTUnwrap(viewModel.exercises.first { $0.exerciseName == "Bench" }?.id)
        let candidates = viewModel.supersetCandidates(forExerciseId: idOfBench)

        XCTAssertEqual(candidates.count, 3, "Everything except the subject")
        XCTAssertFalse(candidates.contains { $0.name == "Bench" })

        let fly = try XCTUnwrap(candidates.first { $0.name == "Fly" })
        XCTAssertFalse(fly.isSelectable)
        XCTAssertEqual(fly.existingGroupLabel, "A")
        XCTAssertEqual(fly.detailText, "Already in Superset A", "Shown and disabled, not hidden")

        let pushdown = try XCTUnwrap(candidates.first { $0.name == "Pushdown" })
        XCTAssertTrue(pushdown.isSelectable)
    }

    func testCandidateSaysWhenPairingWouldReorder() throws {
        let viewModel = try makeViewModel(exerciseNames: ["Bench", "Incline", "Pushdown"])
        let candidates = viewModel.supersetCandidates(forExerciseId: viewModel.exercises[0].id)

        let adjacent = try XCTUnwrap(candidates.first { $0.name == "Incline" })
        XCTAssertFalse(adjacent.wouldMove)

        let distant = try XCTUnwrap(candidates.first { $0.name == "Pushdown" })
        XCTAssertTrue(distant.wouldMove)
        XCTAssertEqual(distant.detailText, "Moves up to sit next to Bench")
    }

    func testLettersAreReusedOnceAGroupIsDissolved() throws {
        let viewModel = try makeViewModel(exerciseNames: ["A", "B", "C", "D"])
        viewModel.pairExercise(exerciseId: viewModel.exercises[0].id, withPartnerId: viewModel.exercises[1].id)
        viewModel.pairExercise(exerciseId: viewModel.exercises[2].id, withPartnerId: viewModel.exercises[3].id)
        XCTAssertEqual(viewModel.nextSupersetLetter, "C")

        viewModel.removeFromSuperset(exerciseId: viewModel.exercises[0].id)
        XCTAssertEqual(viewModel.nextSupersetLetter, "A", "A is free again and gets reused")
    }

    func testEditingASetAfterPairingReordersWritesToTheRightExercise() throws {
        // pairExercise moves a non-adjacent partner, so any row still addressing by its old index
        // would write into whatever now sits there. This is the shape of "my sets ended up on the
        // wrong exercise".
        let viewModel = try makeViewModel(exerciseNames: ["Bench", "Incline", "Pushdown"])
        let benchId = viewModel.exercises[0].id
        let pushdownId = viewModel.exercises[2].id
        let pushdownSetId = viewModel.exercises[2].sets[0].id

        // Bench + Pushdown: Pushdown moves from index 2 to index 1.
        viewModel.pairExercise(exerciseId: viewModel.exercises[0].id, withPartnerId: viewModel.exercises[2].id)
        XCTAssertEqual(viewModel.exercises.map(\.exerciseName), ["Bench", "Pushdown", "Incline"])

        viewModel.updateSet(exerciseId: pushdownId, setId: pushdownSetId) { $0.targetRepMin = 5 }

        let pushdown = try XCTUnwrap(viewModel.exercises.first { $0.id == pushdownId })
        let bench = try XCTUnwrap(viewModel.exercises.first { $0.id == benchId })
        let incline = try XCTUnwrap(viewModel.exercises.first { $0.exerciseName == "Incline" })
        XCTAssertEqual(pushdown.sets[0].targetRepMin, 5, "The edit lands on the set it was made on")
        XCTAssertEqual(bench.sets[0].targetRepMin, 8, "Bench is untouched")
        XCTAssertEqual(incline.sets[0].targetRepMin, 8, "Incline is untouched")
    }

    func testRemovingASetByIdRemovesOnlyThatSet() throws {
        let viewModel = try makeViewModel(exerciseNames: ["Bench", "Incline"])
        let benchId = viewModel.exercises[0].id
        viewModel.addWorkingSet(toExerciseId: benchId)
        XCTAssertEqual(viewModel.exercises[0].sets.count, 2)

        let firstSetId = viewModel.exercises[0].sets[0].id
        viewModel.removeSet(exerciseId: benchId, setId: firstSetId)

        XCTAssertEqual(viewModel.exercises[0].sets.count, 1)
        XCTAssertFalse(viewModel.exercises[0].sets.contains { $0.id == firstSetId })
        XCTAssertEqual(viewModel.exercises[1].sets.count, 1, "The other exercise keeps its set")
    }

    func testEditsAgainstAStaleIdAreDroppedRatherThanMisapplied() throws {
        let viewModel = try makeViewModel(exerciseNames: ["Bench", "Incline"])
        let before = viewModel.exercises.map { $0.sets.map(\.targetRepMin) }

        viewModel.updateSet(exerciseId: UUID(), setId: UUID()) { $0.targetRepMin = 99 }
        viewModel.removeSet(exerciseId: UUID(), setId: UUID())
        viewModel.duplicateSet(exerciseId: UUID(), setId: UUID())

        XCTAssertEqual(viewModel.exercises.map { $0.sets.map(\.targetRepMin) }, before)
    }

    // MARK: - Harness

    private func makeViewModel(exerciseNames: [String]) throws -> CreateEditTemplateViewModel {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self, ExerciseStats.self, Workout.self, WorkoutSet.self,
            WorkoutTemplate.self, TemplateExercise.self, TemplateSet.self,
            configurations: configuration
        )
        let viewModel = CreateEditTemplateViewModel(
            templateService: TemplateService(
                templateRepository: TemplateRepository(modelContainer: container),
                workoutRepository: WorkoutRepository(modelContainer: container),
                setRepository: SetRepository(modelContainer: container),
                exerciseRepository: ExerciseRepository(modelContainer: container)
            ),
            exerciseService: InertExerciseService()
        )

        viewModel.exercises = exerciseNames.map { name in
            EditorExercise(
                id: UUID(),
                exerciseId: UUID(),
                exerciseName: name,
                primaryMuscle: "chest",
                sets: [EditorSet(id: UUID(), setType: .working, targetRepMin: 8, targetRepMax: 10, targetRIR: 2)]
            )
        }
        return viewModel
    }
}

// MARK: - Editor load failures

/// A read that does not produce the template used to leave an empty editor titled "Edit Template",
/// indistinguishable from a template with nothing in it. Adding an exercise and saving then replaced
/// the real contents. The editor now refuses to render a saveable form it cannot stand behind.
@MainActor
final class TemplateEditorLoadFailureTests: XCTestCase {

    func testATemplateThatDoesNotLoadBlocksTheEditorInsteadOfShowingAnEmptyForm() async throws {
        let harness = try makeHarness()

        await harness.viewModel.prepareForPresentation(
            editingTemplateId: UUID(),
            expectedExerciseCount: 3
        )

        XCTAssertTrue(harness.viewModel.loadFailed)
        XCTAssertFalse(harness.viewModel.canSave)
        XCTAssertFalse(harness.viewModel.isLoading)
    }

    func testSaveStaysBlockedAfterAFailedLoadEvenWithAFilledInForm() async throws {
        // The real loss path: the form is filled in, Save looks available, and `updateTemplate`
        // replaces the template's contents with whatever is on screen.
        let harness = try makeHarness()
        await harness.viewModel.prepareForPresentation(
            editingTemplateId: UUID(),
            expectedExerciseCount: 3
        )

        harness.viewModel.templateName = "Upper Body 2"
        harness.viewModel.exercises = [
            EditorExercise(
                id: UUID(),
                exerciseId: UUID(),
                exerciseName: "Bench Press",
                primaryMuscle: "chest",
                sets: [EditorSet(id: UUID(), setType: .working, targetRepMin: 8, targetRepMax: 10, targetRIR: 2)]
            )
        ]

        XCTAssertFalse(harness.viewModel.canSave)
    }

    func testAnEmptyReadOfATemplateTheListSaysHasExercisesIsTreatedAsAFailure() async throws {
        let harness = try makeHarness()
        let templateId = try await harness.makeTemplate(exerciseCount: 3)
        // Stand in for the transient empty read `fetchTemplateDetailWithRetry` exists to paper over.
        try await harness.templateRepo.replaceTemplateContents(templateId: templateId, exercises: [])

        await harness.viewModel.prepareForPresentation(
            editingTemplateId: templateId,
            expectedExerciseCount: 3
        )

        XCTAssertTrue(harness.viewModel.loadFailed)
        XCTAssertFalse(harness.viewModel.canSave)
    }

    func testRetryingAcceptsATemplateThatIsGenuinelyEmpty() async throws {
        // Templates can legitimately end up empty — every exercise they used was deleted from the
        // library — and that one has to stay editable rather than being locked out forever.
        let harness = try makeHarness()
        let templateId = try await harness.makeTemplate(exerciseCount: 2)
        try await harness.templateRepo.replaceTemplateContents(templateId: templateId, exercises: [])

        await harness.viewModel.prepareForPresentation(
            editingTemplateId: templateId,
            expectedExerciseCount: 2
        )
        XCTAssertTrue(harness.viewModel.loadFailed)

        await harness.viewModel.retryLoad()

        XCTAssertFalse(harness.viewModel.loadFailed)
        XCTAssertTrue(harness.viewModel.exercises.isEmpty)
        XCTAssertEqual(harness.viewModel.templateName, "Push")
    }

    func testANormalLoadIsNotFlagged() async throws {
        let harness = try makeHarness()
        let templateId = try await harness.makeTemplate(exerciseCount: 2)

        await harness.viewModel.prepareForPresentation(
            editingTemplateId: templateId,
            expectedExerciseCount: 2
        )

        XCTAssertFalse(harness.viewModel.loadFailed)
        XCTAssertEqual(harness.viewModel.exercises.count, 2)
        XCTAssertTrue(harness.viewModel.canSave)
    }

    func testCreatingANewTemplateIsNeverFlagged() async throws {
        let harness = try makeHarness()

        await harness.viewModel.prepareForPresentation(editingTemplateId: nil)

        XCTAssertFalse(harness.viewModel.loadFailed)
    }

    // MARK: - Harness

    private struct Harness {
        let viewModel: CreateEditTemplateViewModel
        let service: TemplateService
        let templateRepo: TemplateRepository
        let exerciseRepo: ExerciseRepository

        func makeTemplate(exerciseCount: Int) async throws -> UUID {
            var saveExercises: [TemplateSaveExercise] = []
            for index in 0..<exerciseCount {
                let exercise = Exercise(
                    name: "Exercise \(index)",
                    equipmentType: .barbell,
                    trackingType: .weightReps,
                    primaryMuscle: "chest"
                )
                try await exerciseRepo.save(exercise)
                saveExercises.append(
                    TemplateSaveExercise(
                        exerciseId: exercise.id,
                        orderInTemplate: index + 1,
                        supersetGroupId: nil,
                        restTimeSeconds: nil,
                        notes: nil,
                        sets: [
                            TemplateSaveSet(
                                setType: .working,
                                targetRepMin: 8,
                                targetRepMax: 10,
                                targetRIR: 2,
                                orderInExercise: 1
                            )
                        ]
                    )
                )
            }
            return try await service.createTemplate(
                TemplateSaveData(name: "Push", notes: nil, exercises: saveExercises)
            )
        }
    }

    private func makeHarness() throws -> Harness {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self, ExerciseStats.self, Workout.self, WorkoutSet.self,
            WorkoutTemplate.self, TemplateExercise.self, TemplateSet.self,
            configurations: configuration
        )
        let templateRepo = TemplateRepository(modelContainer: container)
        let exerciseRepo = ExerciseRepository(modelContainer: container)
        let service = TemplateService(
            templateRepository: templateRepo,
            workoutRepository: WorkoutRepository(modelContainer: container),
            setRepository: SetRepository(modelContainer: container),
            exerciseRepository: exerciseRepo
        )
        return Harness(
            viewModel: CreateEditTemplateViewModel(
                templateService: service,
                exerciseService: InertExerciseService()
            ),
            service: service,
            templateRepo: templateRepo,
            exerciseRepo: exerciseRepo
        )
    }
}

/// The pairing logic touches no service; this exists only to satisfy the initialiser.
private final class InertExerciseService: @unchecked Sendable, ExerciseServiceProtocol {
    func createExercise(fields: ExerciseEditableFields) async throws -> UUID { UUID() }
    func updateExercise(id: UUID, fields: ExerciseEditableFields) async throws {}
    func fetchExercise(_ exerciseId: UUID) async throws -> Exercise? { nil }
    func fetchExerciseSnapshot(_ exerciseId: UUID) async throws -> ChartExerciseData? { nil }
    func fetchAllExercises() async throws -> [Exercise] { [] }
    func searchExercises(name query: String) async throws -> [Exercise] { [] }
    func deleteExercise(_ exerciseId: UUID) async throws {}
    func exerciseHasSets(_ exerciseId: UUID) async throws -> Bool { false }
    func exerciseHasLoggedSetData(_ exerciseId: UUID) async throws -> Bool { false }
}
