import XCTest
@testable import Repster

final class MuscleAttributionTests: XCTestCase {

    // MARK: - Rollup

    func testCoverageGroupFoldsLegSubMusclesIntoLegs() {
        for tag in ["glutes", "quads", "quadriceps", "hamstrings", "calves", " Glutes "] {
            XCTAssertEqual(ExerciseMuscleGroupCatalog.coverageGroup(for: tag), "legs", tag)
        }
        XCTAssertEqual(ExerciseMuscleGroupCatalog.coverageGroup(for: "core"), "abs")
        XCTAssertEqual(ExerciseMuscleGroupCatalog.coverageGroup(for: "triceps"), "triceps")
        XCTAssertNil(ExerciseMuscleGroupCatalog.coverageGroup(for: "  "))
        XCTAssertNil(ExerciseMuscleGroupCatalog.coverageGroup(for: nil))
    }

    /// Every primary-muscle surface keys off `normalizedValue`. A legacy "quads" primary
    /// rolling up there would regroup Insights and chart numbers users have already seen.
    func testNormalizedValueLeavesLegSubMusclesAlone() {
        for tag in ["glutes", "quads", "hamstrings", "calves"] {
            XCTAssertEqual(ExerciseMuscleGroupCatalog.normalizedValue(tag), tag)
        }
    }

    // MARK: - Attribution

    func testLegTagsUnderALegsPrimaryCollapseAway() {
        // Barbell Back Squat as seeded.
        let squat = MuscleAttribution(
            primaryMuscle: "legs",
            secondaryMuscles: ["quads", "glutes", "hamstrings", "core"]
        )

        XCTAssertEqual(squat.primary, "legs")
        XCTAssertEqual(squat.secondary, ["abs"])
    }

    func testSecondaryIsDedupedInStoredOrder() {
        // Conventional Deadlift as seeded: two leg tags become one group, before abs.
        let deadlift = MuscleAttribution(
            primaryMuscle: "back",
            secondaryMuscles: ["hamstrings", "glutes", "core"]
        )

        XCTAssertEqual(deadlift.secondary, ["legs", "abs"])
    }

    func testSecondaryNeverIncludesCardioOrFullBody() {
        let attribution = MuscleAttribution(
            primaryMuscle: "chest",
            secondaryMuscles: ["cardio", "Full Body", "triceps"]
        )

        XCTAssertEqual(attribution.secondary, ["triceps"])
    }

    func testLegacyLegPrimaryCountsAsLegs() {
        let attribution = MuscleAttribution(primaryMuscle: "quads", secondaryMuscles: ["glutes", "core"])

        XCTAssertEqual(attribution.primary, "legs")
        XCTAssertEqual(attribution.secondary, ["abs"])
    }

    func testOffCatalogSecondaryPassesThroughNormalized() {
        let attribution = MuscleAttribution(primaryMuscle: "back", secondaryMuscles: ["Lats", "biceps"])

        XCTAssertEqual(attribution.secondary, ["lats", "biceps"])
    }

    func testNoPrimaryKeepsEverySecondary() {
        let attribution = MuscleAttribution(primaryMuscle: nil, secondaryMuscles: ["legs", "glutes", "abs"])

        XCTAssertNil(attribution.primary)
        XCTAssertEqual(attribution.secondary, ["legs", "abs"])
    }

    // MARK: - Editor options

    func testEditorOptionsLeaveOutThePrimaryGroupCardioAndFullBody() {
        let options = MuscleAttribution.secondaryOptions(primaryMuscle: "chest", secondaryMuscles: [])

        XCTAssertEqual(options, ["abs", "back", "biceps", "forearms", "legs", "shoulders", "triceps"])
    }

    func testEditorOptionsKeepAnOffCatalogGroupTheExerciseCarries() {
        let options = MuscleAttribution.secondaryOptions(primaryMuscle: "back", secondaryMuscles: ["lats"])

        XCTAssertEqual(options, ["abs", "biceps", "chest", "forearms", "legs", "shoulders", "triceps", "lats"])
    }

    // MARK: - Toggling

    func testTogglingOffRemovesEveryTagThatRollsUpToTheGroup() {
        XCTAssertEqual(MuscleAttribution.toggling("legs", in: ["hamstrings", "glutes", "core"]), ["core"])
    }

    func testTogglingOnAppendsTheGroupAndKeepsStoredSpellings() {
        XCTAssertEqual(
            MuscleAttribution.toggling("biceps", in: ["hamstrings", "glutes", "core"]),
            ["hamstrings", "glutes", "core", "biceps"]
        )
    }

    func testTogglingTwiceRestoresTheList() {
        let original = ["shoulders", "triceps"]
        let added = MuscleAttribution.toggling("abs", in: original)

        XCTAssertEqual(MuscleAttribution.toggling("abs", in: added), original)
    }
}
