// ProgramCatalogServiceTests.swift
// Materialisation: catalogue entry in, WorkoutTemplates out.
//
// The happy paths run against the *real* bundled catalogue and the *real* seeded exercise
// library, both read from disk, so these fail if the shipped content drifts. Edge cases use a
// small fixture catalogue written to a temporary directory.

import XCTest
import SwiftData
@testable import Repster

final class ProgramCatalogServiceTests: XCTestCase {

    // MARK: - Happy path, real catalogue

    func testMaterialiseCreatesOneTemplatePerSessionInRotationOrder() async throws {
        let ctx = try await makeContext()

        let result = try await ctx.service.materialise(programId: "full_body_3d")

        XCTAssertEqual(result.programId, "full_body_3d")
        XCTAssertEqual(result.folderName, "Full Body")
        XCTAssertEqual(result.createdCount, 3)
        XCTAssertTrue(result.skippedExercises.isEmpty,
                      "Real catalogue should resolve fully: \(result.skippedExercises)")

        let templates = try await ctx.templateRepo.fetchAllTemplates()
        let mine = templates.filter { $0.folder == "Full Body" }
        XCTAssertEqual(mine.count, 3)
        XCTAssertEqual(
            mine.sorted { ($0.orderInFolder ?? 0) < ($1.orderInFolder ?? 0) }.map(\.name),
            ["Full Body A", "Full Body B", "Full Body C"]
        )
        XCTAssertEqual(mine.compactMap(\.orderInFolder).sorted(), [0, 1, 2])
    }

    func testMaterialisedSetsCarryRepTargetsAndNeverAWeight() async throws {
        let ctx = try await makeContext()
        let result = try await ctx.service.materialise(programId: "five_by_five_3d")

        let detail = try await ctx.service2.fetchTemplateDetail(result.templateIds[0])
        let unwrapped = try XCTUnwrap(detail)

        XCTAssertFalse(unwrapped.exercises.isEmpty)
        for exercise in unwrapped.exercises {
            XCTAssertFalse(exercise.sets.isEmpty)
            for set in exercise.sets {
                XCTAssertEqual(set.targetRepMin, 5)
                XCTAssertEqual(set.targetRepMax, 5)
                XCTAssertEqual(set.targetRIR, 1)
            }
        }
        // 5×5 Workout A is three lifts of five sets.
        XCTAssertEqual(unwrapped.exercises.count, 3)
        XCTAssertEqual(unwrapped.exercises.map(\.sets.count), [5, 5, 5])
    }

    func testEveryCatalogueProgramMaterialisesAgainstTheRealLibrary() async throws {
        let ctx = try await makeContext()

        for program in try ctx.service.availablePrograms() {
            let result = try await ctx.service.materialise(programId: program.id)
            XCTAssertEqual(result.createdCount, program.sessionCount,
                           "\(program.id) produced \(result.createdCount) of \(program.sessionCount)")
            XCTAssertTrue(result.skippedExercises.isEmpty,
                          "\(program.id) skipped \(result.skippedExercises)")
        }
    }

    // MARK: - Idempotency and folder collisions

    func testMaterialiseTwiceDoesNotDuplicate() async throws {
        let ctx = try await makeContext()

        let first = try await ctx.service.materialise(programId: "full_body_3d")
        let second = try await ctx.service.materialise(programId: "full_body_3d")

        XCTAssertEqual(Set(first.templateIds), Set(second.templateIds))
        XCTAssertEqual(second.folderName, "Full Body")

        let all = try await ctx.templateRepo.fetchAllTemplates()
        XCTAssertEqual(all.filter { $0.folder == "Full Body" }.count, 3,
                       "A second call must not write a second copy")
    }

    func testUserFolderOfTheSameNameIsNotMergedInto() async throws {
        let ctx = try await makeContext()

        // The user already keeps their own templates in a folder called "Full Body".
        let library = try await ctx.exerciseRepo.fetchAll()
        let bench = try XCTUnwrap(library.first)
        _ = try await ctx.service2.createTemplate(
            TemplateSaveData(
                name: "My own session",
                notes: nil,
                folder: "Full Body",
                exercises: [
                    TemplateSaveExercise(
                        exerciseId: bench.id, orderInTemplate: 0, supersetGroupId: nil,
                        restTimeSeconds: nil, notes: nil,
                        sets: [TemplateSaveSet(setType: .working, targetRepMin: 8,
                                               targetRepMax: 12, targetRIR: 2, orderInExercise: 0)]
                    )
                ]
            )
        )

        let result = try await ctx.service.materialise(programId: "full_body_3d")

        XCTAssertEqual(result.folderName, "Full Body 2")
        let all = try await ctx.templateRepo.fetchAllTemplates()
        XCTAssertEqual(all.filter { $0.folder == "Full Body" }.count, 1, "User's folder untouched")
        XCTAssertEqual(all.filter { $0.folder == "Full Body 2" }.count, 3)
    }

    // MARK: - Failure modes

    func testUnknownProgramIdThrows() async throws {
        let ctx = try await makeContext()
        do {
            _ = try await ctx.service.materialise(programId: "no_such_program")
            XCTFail("Expected unknownProgram")
        } catch let error as ProgramCatalogError {
            XCTAssertEqual(error, .unknownProgram("no_such_program"))
        }
    }

    func testMissingExerciseIsSkippedRatherThanFatal() async throws {
        let fixture = try makeFixtureBundle(json: """
        { "programs": [ { "id": "fx", "name": "Fixture", "daysPerWeek": 1, "summary": "s",
          "sessions": [ { "name": "Day 1", "exercises": [
            { "exercise": "Barbell Back Squat", "sets": 2, "repMin": 5, "repMax": 8, "rir": 2, "restSeconds": 120 },
            { "exercise": "Nonexistent Lift",  "sets": 3, "repMin": 5, "repMax": 8, "rir": 2, "restSeconds": 120 }
          ] } ] } ] }
        """)
        let ctx = try await makeContext(bundle: fixture)

        let result = try await ctx.service.materialise(programId: "fx")

        XCTAssertEqual(result.createdCount, 1)
        XCTAssertEqual(result.skippedExercises, ["Nonexistent Lift"])

        let detail = try await ctx.service2.fetchTemplateDetail(result.templateIds[0])
        let unwrapped = try XCTUnwrap(detail)
        XCTAssertEqual(unwrapped.exercises.count, 1, "The resolvable lift still made it in")
    }

    func testProgramWhereNothingResolvesThrows() async throws {
        let fixture = try makeFixtureBundle(json: """
        { "programs": [ { "id": "fx", "name": "Fixture", "daysPerWeek": 1, "summary": "s",
          "sessions": [ { "name": "Day 1", "exercises": [
            { "exercise": "Nonexistent Lift", "sets": 3, "repMin": 5, "repMax": 8, "rir": 2, "restSeconds": 120 }
          ] } ] } ] }
        """)
        let ctx = try await makeContext(bundle: fixture)

        do {
            _ = try await ctx.service.materialise(programId: "fx")
            XCTFail("Expected noResolvableExercises")
        } catch let error as ProgramCatalogError {
            XCTAssertEqual(error, .noResolvableExercises("fx"))
        }
    }

    // MARK: - Fixtures

    private struct Context {
        let service: ProgramCatalogService
        let service2: TemplateService
        let templateRepo: TemplateRepository
        let exerciseRepo: ExerciseRepository
    }

    /// Repository root, derived from this file rather than a bundle.
    private static func resourcesDirectory(_ filePath: StaticString = #filePath) -> String {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Repster/Resources")
            .path
    }

    /// A directory Bundle carrying only a fixture catalogue.
    private func makeFixtureBundle(json: String) throws -> Bundle {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("program-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent("seed_programs.json"),
                       atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return try XCTUnwrap(Bundle(path: dir.path))
    }

    /// In-memory store seeded with the real exercise library, matching production seeding.
    private func makeContext(bundle: Bundle? = nil) async throws -> Context {
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
        let templateRepo = TemplateRepository(modelContainer: container)
        let templateService = TemplateService(
            templateRepository: templateRepo,
            workoutRepository: WorkoutRepository(modelContainer: container),
            setRepository: SetRepository(modelContainer: container),
            exerciseRepository: exerciseRepo
        )

        let seedURL = URL(fileURLWithPath: Self.resourcesDirectory())
            .appendingPathComponent("seed_exercises.json")
        let seeds = try JSONDecoder()
            .decode(SeedExerciseFile.self, from: Data(contentsOf: seedURL))
        for dto in seeds.exercises {
            if let exercise = try? dto.toExercise() {
                try await exerciseRepo.save(exercise)
            }
        }

        let catalogueBundle = try bundle ?? XCTUnwrap(Bundle(path: Self.resourcesDirectory()))

        return Context(
            service: ProgramCatalogService(
                templateService: templateService,
                exerciseRepository: exerciseRepo,
                bundle: catalogueBundle
            ),
            service2: templateService,
            templateRepo: templateRepo,
            exerciseRepo: exerciseRepo
        )
    }
}
