import Foundation
import SwiftData
import XCTest
@testable import Repster

final class SeedExerciseLibraryTests: XCTestCase {

    func testSeedExerciseLibraryCoversAllSupportedPrimaryGroupsAndCanonicalTrackingTypes() throws {
        let file = try loadSeedExerciseFile()
        XCTAssertEqual(file.exercises.count, 69)

        let mappedExercises = try file.exercises.map { try $0.toExercise() }
        XCTAssertEqual(mappedExercises.count, 69)

        let primaryGroups = Set(mappedExercises.compactMap { ExercisePrimaryGroup.normalizedValue($0.primaryMuscle) })
        XCTAssertEqual(
            primaryGroups,
            Set([
                "abs",
                "back",
                "biceps",
                "cardio",
                "chest",
                "forearms",
                "full body",
                "legs",
                "shoulders",
                "triceps"
            ])
        )

        let exercisesByName = Dictionary(uniqueKeysWithValues: mappedExercises.map { ($0.name, $0) })

        XCTAssertEqual(exercisesByName["Running"]?.trackingType, .durationDistance)
        XCTAssertEqual(exercisesByName["Running"]?.primaryMuscle, "cardio")

        XCTAssertEqual(exercisesByName["Barbell Thruster"]?.trackingType, .weightReps)
        XCTAssertEqual(exercisesByName["Barbell Thruster"]?.primaryMuscle, "full body")

        XCTAssertEqual(exercisesByName["Wrist Curl"]?.trackingType, .weightReps)
        XCTAssertEqual(exercisesByName["Wrist Curl"]?.primaryMuscle, "forearms")

        XCTAssertEqual(exercisesByName["Farmer's Walk"]?.trackingType, .weightDistance)
        XCTAssertEqual(exercisesByName["Plank"]?.trackingType, .duration)
    }

    /// Exercise detail shows seeded secondaries through `MuscleAttribution`. A tag that
    /// doesn't count towards a catalog group would have no colour or rollup behind it.
    func testEverySeededSecondaryCountsTowardsACatalogGroup() throws {
        let catalogGroups = Set(ExerciseMuscleGroupCatalog.supportedEntries.map(\.value))

        for exercise in try loadSeedExerciseFile().exercises {
            let attribution = MuscleAttribution(
                primaryMuscle: exercise.primaryMuscle,
                secondaryMuscles: exercise.secondaryMuscles
            )
            for muscle in attribution.secondary {
                let group = try XCTUnwrap(ExerciseMuscleGroupCatalog.coverageGroup(for: muscle))
                XCTAssertTrue(catalogGroups.contains(group), "\(exercise.name): \(muscle)")
            }
        }
    }

    /// New installs get the seed and existing ones get the one-time fix, so the two must agree.
    func testSeedFileCarriesTheCorrectedSecondaryMuscles() throws {
        let seeded = Dictionary(
            uniqueKeysWithValues: try loadSeedExerciseFile().exercises.map { ($0.name, $0.secondaryMuscles) }
        )
        for correction in SecondaryMuscleTagFixMigration.corrections {
            XCTAssertEqual(seeded[correction.name], correction.corrected, correction.name)
        }
    }

    /// Existing installs keep the tags they were seeded with. The fix replaces only untouched
    /// originals, and only once, so anything chosen by hand survives it.
    func testSecondaryMuscleTagFixReplacesOnlyUntouchedOriginalsOnce() throws {
        let container = try ModelContainer(
            for: Schema(ModelContainerSetup.modelTypes),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "muscle-tag-fix-\(UUID().uuidString)"))

        func exercise(_ name: String, _ secondary: [String]) -> Exercise {
            Exercise(name: name, equipmentType: .machinePin, trackingType: .weightReps, primaryMuscle: "legs", secondaryMuscles: secondary)
        }
        let setup = ModelContext(container)
        setup.insert(exercise("Hip Adductor Machine", ["glutes"]))
        setup.insert(exercise("Dead Hang", ["shoulders"]))
        setup.insert(exercise("Hip Abductor Machine", ["glutes"]))
        setup.insert(exercise("Farmer's Walk", ["traps"]))
        setup.insert(exercise("Dead Hang (towel)", ["shoulders"]))
        try setup.save()

        func stored(_ name: String) throws -> [String]? {
            try ModelContext(container).fetch(FetchDescriptor<Exercise>()).first { $0.name == name }?.secondaryMuscles
        }

        SecondaryMuscleTagFixMigration.runIfNeeded(modelContext: ModelContext(container), userDefaults: defaults)

        XCTAssertEqual(try stored("Hip Adductor Machine"), ["adductors"])
        XCTAssertEqual(try stored("Dead Hang"), ["forearms", "shoulders"])
        XCTAssertEqual(try stored("Hip Abductor Machine"), ["glutes"], "not one of the three: kept")
        XCTAssertEqual(try stored("Farmer's Walk"), ["traps"], "edited by hand: kept")
        XCTAssertEqual(try stored("Dead Hang (towel)"), ["shoulders"], "renamed: kept")

        // Set back by hand after the fix, then the app relaunches.
        let edit = ModelContext(container)
        try XCTUnwrap(edit.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Hip Adductor Machine" })
            .secondaryMuscles = ["glutes"]
        try edit.save()

        SecondaryMuscleTagFixMigration.runIfNeeded(modelContext: ModelContext(container), userDefaults: defaults)
        XCTAssertEqual(try stored("Hip Adductor Machine"), ["glutes"], "runs once")
    }

    private func loadSeedExerciseFile() throws -> SeedExerciseFile {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repositoryRootURL = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let seedFileURL = repositoryRootURL
            .appendingPathComponent("Repster")
            .appendingPathComponent("Resources")
            .appendingPathComponent("seed_exercises.json")

        let data = try Data(contentsOf: seedFileURL)
        return try JSONDecoder().decode(SeedExerciseFile.self, from: data)
    }
}
