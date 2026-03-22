import XCTest
@testable import Reppo

final class WorkoutSetTests: XCTestCase {

    func testSyncDerivedPerformanceFieldsUsesStrongerSideForPRAndTotalRepsForVolumeStats() {
        let exercise = Exercise(
            name: "Split Squat",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            primaryMuscle: "quads",
            unilateral: true
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            weight: 24,
            effectiveWeight: 24,
            leftReps: 12,
            rightReps: 10,
            leftRIR: 2,
            rightRIR: 3,
            orderInWorkout: 1,
            orderInExercise: 1
        )

        set.syncDerivedPerformanceFields(for: exercise)

        XCTAssertEqual(set.prReps, 12)
        XCTAssertEqual(set.totalReps, 22)
        XCTAssertEqual(set.performanceRIR, 2)
        XCTAssertEqual(set.reps, 12)
        XCTAssertEqual(set.rir, 2)
        XCTAssertEqual(set.side, .both)
        XCTAssertEqual(set.volume, 24 * 22)
    }

    func testPerformanceFormatterShowsPerSideLabelsForUnilateralSet() {
        let exercise = Exercise(
            name: "Split Squat",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            primaryMuscle: "legs",
            unilateral: true
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            weight: 20,
            leftReps: 10,
            rightReps: 8,
            leftRIR: 2,
            rightRIR: 3,
            orderInWorkout: 1,
            orderInExercise: 1
        )

        let display = WorkoutSetPerformanceFormatter.display(for: set, exercise: exercise)

        XCTAssertEqual(display.performanceLabel, "20 kg × L: 10  R: 8")
        XCTAssertEqual(display.rirLabel, "L RIR 2 • R RIR 3")
        XCTAssertEqual(display.sideRepsLabels, ["L10", "R8"])
        XCTAssertEqual(display.sideRIRLabels, ["L2", "R3"])
        XCTAssertEqual(display.perSideLabel, "Per side")
    }

    func testChartSetDataUsesTotalRepsForUnilateralVolume() {
        let exercise = Exercise(
            name: "Split Squat",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            primaryMuscle: "legs",
            unilateral: true
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            weight: 24,
            effectiveWeight: 24,
            leftReps: 12,
            rightReps: 10,
            orderInWorkout: 1,
            orderInExercise: 1
        )
        set.syncDerivedPerformanceFields(for: exercise)

        let chartSet = ChartSetData(from: set)

        XCTAssertEqual(chartSet.prReps, 12)
        XCTAssertEqual(chartSet.totalReps, 22)
        XCTAssertEqual(chartSet.volume, 24 * 22)
    }

    func testMuscleGroupCatalogNormalizesLegacyAliases() {
        XCTAssertEqual(ExercisePrimaryGroup.normalizedValue("core"), "abs")
        XCTAssertEqual(ExercisePrimaryGroup.normalizedValue("abdominals"), "abs")
        XCTAssertEqual(ExercisePrimaryGroup.normalizedValue("forearm"), "forearms")
        XCTAssertEqual(ExercisePrimaryGroup.displayName(for: "core"), "Abs")
        XCTAssertEqual(ExercisePrimaryGroup.displayName(for: "forearm"), "Forearms")
    }
}
