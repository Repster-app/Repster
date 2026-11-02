import UIKit
import XCTest
@testable import Repster

final class MuscleAttributionTests: XCTestCase {

    // MARK: - Rollup

    func testCoverageGroupSaysWhereEachFinerMuscleCounts() {
        let expectedGroups = [
            "front delts": "shoulders",
            "side delts": "shoulders",
            "rear delts": "shoulders",
            "lats": "back",
            "traps": "back",
            "lower back": "back",
            "obliques": "abs",
            "quads": "legs",
            "quadriceps": "legs",
            "glutes": "legs",
            "hamstrings": "legs",
            "calves": "legs",
            "adductors": "legs"
        ]

        for (muscle, group) in expectedGroups {
            XCTAssertEqual(ExerciseMuscleGroupCatalog.coverageGroup(for: muscle), group, muscle)
        }
        XCTAssertEqual(ExerciseMuscleGroupCatalog.coverageGroup(for: " Glutes "), "legs")
        XCTAssertEqual(ExerciseMuscleGroupCatalog.coverageGroup(for: "core"), "abs")
        XCTAssertEqual(ExerciseMuscleGroupCatalog.coverageGroup(for: "triceps"), "triceps")
        XCTAssertNil(ExerciseMuscleGroupCatalog.coverageGroup(for: "  "))
        XCTAssertNil(ExerciseMuscleGroupCatalog.coverageGroup(for: nil))
    }

    /// Every primary-muscle surface keys off `normalizedValue`. A legacy "quads" primary
    /// rolling up there would regroup Insights and chart numbers users have already seen.
    func testNormalizedValueLeavesFinerMusclesAlone() {
        for muscle in ExerciseMuscleGroupCatalog.secondaryMuscleAreas.flatMap(\.muscles) {
            XCTAssertEqual(ExerciseMuscleGroupCatalog.normalizedValue(muscle), muscle)
        }
    }

    // MARK: - The list

    func testTheListOffersNineteenDifferentMuscles() {
        let muscles = ExerciseMuscleGroupCatalog.secondaryMuscleAreas.flatMap(\.muscles)

        XCTAssertEqual(muscles.count, 19)
        XCTAssertEqual(Set(muscles).count, 19)
    }

    /// Anything added to the list without a rollup would have nowhere to count later.
    func testEveryListedMuscleCountsTowardsACatalogGroup() throws {
        let catalogGroups = Set(ExerciseMuscleGroupCatalog.supportedEntries.map(\.value))

        for muscle in ExerciseMuscleGroupCatalog.secondaryMuscleAreas.flatMap(\.muscles) {
            let group = try XCTUnwrap(ExerciseMuscleGroupCatalog.coverageGroup(for: muscle))
            XCTAssertTrue(catalogGroups.contains(group), muscle)
        }
    }

    // MARK: - Attribution

    func testLegMusclesShowUnderALegsPrimary() {
        // Barbell Back Squat as seeded.
        let squat = MuscleAttribution(
            primaryMuscle: "legs",
            secondaryMuscles: ["quads", "glutes", "hamstrings", "core"]
        )

        XCTAssertEqual(squat.primary, "legs")
        XCTAssertEqual(squat.secondary, ["quads", "glutes", "hamstrings", "abs"])
    }

    func testSecondaryDropsThePrimaryAndRepeatsInStoredOrder() {
        let attribution = MuscleAttribution(
            primaryMuscle: "chest",
            secondaryMuscles: ["Triceps", "chest", "triceps", "shoulders"]
        )

        XCTAssertEqual(attribution.secondary, ["triceps", "shoulders"])
    }

    func testSecondaryNeverIncludesCardioOrFullBody() {
        let attribution = MuscleAttribution(
            primaryMuscle: "chest",
            secondaryMuscles: ["cardio", "Full Body", "triceps"]
        )

        XCTAssertEqual(attribution.secondary, ["triceps"])
    }

    func testLegacyPrimaryCoversItselfAndItsGroup() {
        let attribution = MuscleAttribution(primaryMuscle: "quads", secondaryMuscles: ["quads", "legs", "glutes"])

        XCTAssertEqual(attribution.primary, "legs")
        XCTAssertEqual(attribution.secondary, ["glutes"])
    }

    func testUnlistedSecondaryPassesThroughNormalized() {
        let attribution = MuscleAttribution(primaryMuscle: "back", secondaryMuscles: ["Upper Back", "biceps"])

        XCTAssertEqual(attribution.secondary, ["upper back", "biceps"])
    }

    func testNoPrimaryKeepsEverySecondary() {
        let attribution = MuscleAttribution(primaryMuscle: nil, secondaryMuscles: ["legs", "glutes", "abs"])

        XCTAssertNil(attribution.primary)
        XCTAssertEqual(attribution.secondary, ["legs", "glutes", "abs"])
    }

    // MARK: - Editor areas

    func testAreasDropThePrimaryAndAnAreaLeftEmpty() {
        let areas = MuscleAttribution.secondaryAreas(primaryMuscle: "chest", secondaryMuscles: [])

        XCTAssertEqual(areas.map(\.title), ["Shoulders", "Arms", "Back", "Core", "Legs"])
    }

    func testAreasKeepTheFinerMusclesOfThePrimaryGroup() throws {
        let areas = MuscleAttribution.secondaryAreas(primaryMuscle: "shoulders", secondaryMuscles: [])
        let shoulders = try XCTUnwrap(areas.first { $0.title == "Shoulders" })

        XCTAssertEqual(shoulders.muscles, ["front delts", "side delts", "rear delts"])
    }

    func testAreasListACarriedMuscleUnderOtherSoItCanBeRemoved() throws {
        // Running as seeded: plain "legs" isn't on the list any more.
        let areas = MuscleAttribution.secondaryAreas(primaryMuscle: "cardio", secondaryMuscles: ["legs"])
        let other = try XCTUnwrap(areas.last)

        XCTAssertEqual(other.title, "Other")
        XCTAssertEqual(other.muscles, ["legs"])
    }

    func testAreasHaveNoOtherWhenEveryTagIsListed() {
        let areas = MuscleAttribution.secondaryAreas(primaryMuscle: "back", secondaryMuscles: ["hamstrings", "core"])

        XCTAssertFalse(areas.contains { $0.title == "Other" })
    }

    // MARK: - Toggling

    func testTogglingOffRemovesEverySpellingOfTheMuscle() {
        XCTAssertEqual(MuscleAttribution.toggling("abs", in: ["hamstrings", "core", "abs"]), ["hamstrings"])
    }

    func testTogglingOneMuscleLeavesItsNeighboursAlone() {
        XCTAssertEqual(MuscleAttribution.toggling("glutes", in: ["hamstrings", "glutes", "core"]), ["hamstrings", "core"])
    }

    func testTogglingOnAppendsTheMuscleAndKeepsStoredSpellings() {
        XCTAssertEqual(
            MuscleAttribution.toggling("biceps", in: ["hamstrings", "core"]),
            ["hamstrings", "core", "biceps"]
        )
    }

    func testTogglingTwiceRestoresTheList() {
        let original = ["shoulders", "triceps"]
        let added = MuscleAttribution.toggling("rear delts", in: original)

        XCTAssertEqual(MuscleAttribution.toggling("rear delts", in: added), original)
    }

    // MARK: - Colours

    func testFinerMusclesShareTheirGroupsColour() {
        XCTAssertEqual(MuscleGroupColors.groupColor(for: "rear delts"), MuscleGroupColors.color(for: "shoulders"))
        XCTAssertEqual(MuscleGroupColors.groupColor(for: "traps"), MuscleGroupColors.color(for: "back"))
        XCTAssertEqual(MuscleGroupColors.groupColor(for: "obliques"), MuscleGroupColors.color(for: "abs"))
        XCTAssertEqual(MuscleGroupColors.groupColor(for: "glutes"), MuscleGroupColors.color(for: "legs"))
        XCTAssertEqual(MuscleGroupColors.groupColor(for: "biceps"), MuscleGroupColors.color(for: "biceps"))
    }

    /// A menu only keeps an icon's colour when the image is marked as original.
    func testDotImageKeepsItsOwnColourInAMenu() {
        let dot = MuscleGroupColors.dotImage(for: "chest")

        XCTAssertEqual(dot.renderingMode, .alwaysOriginal)
        XCTAssertEqual(dot.size, CGSize(width: 10, height: 10))
    }
}
