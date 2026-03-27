import Foundation
import XCTest
@testable import Reppo

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

    private func loadSeedExerciseFile() throws -> SeedExerciseFile {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repositoryRootURL = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let seedFileURL = repositoryRootURL
            .appendingPathComponent("Reppo")
            .appendingPathComponent("Resources")
            .appendingPathComponent("seed_exercises.json")

        let data = try Data(contentsOf: seedFileURL)
        return try JSONDecoder().decode(SeedExerciseFile.self, from: data)
    }
}
