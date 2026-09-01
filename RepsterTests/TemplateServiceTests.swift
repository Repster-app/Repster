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
        group: UUID?
    ) -> WorkoutSet {
        WorkoutSet(
            workoutId: workoutId,
            exerciseId: exerciseId,
            date: Date(),
            weight: 60,
            reps: 8,
            setType: .working,
            orderInWorkout: order,
            orderInExercise: order,
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
        viewModel.pairExercise(at: 1, withExerciseAt: 2)

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

        viewModel.pairExercise(at: 0, withExerciseAt: 2)

        XCTAssertEqual(viewModel.exercises.map(\.exerciseName), ["Bench Press", "Rope Pushdown", "Incline DB Press"])
        XCTAssertEqual(viewModel.exercises[0].supersetGroupId, viewModel.exercises[1].supersetGroupId)
        XCTAssertNil(viewModel.exercises[2].supersetGroupId)
    }

    func testRemovingFromASupersetDissolvesTheWholeGroup() throws {
        // Groups are pairs for now, so clearing one side would leave the other in a group of one —
        // the state the whole pairing flow exists to prevent.
        let viewModel = try makeViewModel(exerciseNames: ["Cable Fly", "Lateral Raise"])
        viewModel.pairExercise(at: 0, withExerciseAt: 1)
        XCTAssertNotNil(viewModel.exercises[0].supersetGroupId)

        viewModel.removeFromSuperset(at: 0)

        XCTAssertTrue(viewModel.exercises.allSatisfy { $0.supersetGroupId == nil })
        XCTAssertEqual(viewModel.nextSupersetLetter, "A", "The letter is free again")
    }

    func testRepairingAnAlreadyGroupedExerciseDoesNotStrandItsOldPartner() throws {
        let viewModel = try makeViewModel(exerciseNames: ["A", "B", "C", "D"])
        viewModel.pairExercise(at: 0, withExerciseAt: 1)

        // Pair A with C instead. B must not be left holding a group by itself.
        let indexOfC = try XCTUnwrap(viewModel.exercises.firstIndex { $0.exerciseName == "C" })
        let indexOfA = try XCTUnwrap(viewModel.exercises.firstIndex { $0.exerciseName == "A" })
        viewModel.pairExercise(at: indexOfA, withExerciseAt: indexOfC)

        let byName = Dictionary(uniqueKeysWithValues: viewModel.exercises.map { ($0.exerciseName, $0.supersetGroupId) })
        XCTAssertNotNil(byName["A"] ?? nil)
        XCTAssertEqual(byName["A"], byName["C"])
        XCTAssertNil(byName["B"] ?? nil, "The old partner is released, not left in a group of one")
        XCTAssertNil(byName["D"] ?? nil)
    }

    func testCandidatesExcludeSelfAndMarkAlreadyGroupedOnesUnselectable() throws {
        let viewModel = try makeViewModel(exerciseNames: ["Bench", "Fly", "Raise", "Pushdown"])
        viewModel.pairExercise(at: 1, withExerciseAt: 2)

        let indexOfBench = try XCTUnwrap(viewModel.exercises.firstIndex { $0.exerciseName == "Bench" })
        let candidates = viewModel.supersetCandidates(for: indexOfBench)

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
        let candidates = viewModel.supersetCandidates(for: 0)

        let adjacent = try XCTUnwrap(candidates.first { $0.name == "Incline" })
        XCTAssertFalse(adjacent.wouldMove)

        let distant = try XCTUnwrap(candidates.first { $0.name == "Pushdown" })
        XCTAssertTrue(distant.wouldMove)
        XCTAssertEqual(distant.detailText, "Moves up to sit next to Bench")
    }

    func testLettersAreReusedOnceAGroupIsDissolved() throws {
        let viewModel = try makeViewModel(exerciseNames: ["A", "B", "C", "D"])
        viewModel.pairExercise(at: 0, withExerciseAt: 1)
        viewModel.pairExercise(at: 2, withExerciseAt: 3)
        XCTAssertEqual(viewModel.nextSupersetLetter, "C")

        viewModel.removeFromSuperset(at: 0)
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
        viewModel.pairExercise(at: 0, withExerciseAt: 2)
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
        viewModel.addWorkingSet(to: 0)
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
