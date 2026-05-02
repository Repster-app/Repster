import XCTest
@testable import Repster

final class WorkoutSetTests: XCTestCase {

    func testPreferredTargetRepBoundsPreferOverrideWithoutMixingTemplateBounds() {
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: UUID(),
            orderInWorkout: 1,
            orderInExercise: 1,
            targetRepMin: 8,
            targetRepMax: 12
        )
        set.overrideTargetRepMin = 10
        set.overrideTargetRepMax = nil

        let bounds = set.preferredTargetRepBounds

        XCTAssertEqual(bounds.min, 10)
        XCTAssertNil(bounds.max)
    }

    func testCustomRepRangeCommitStoresOverrideGuidanceWithoutSettingActualReps() {
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: UUID(),
            reps: 6,
            orderInWorkout: 1,
            orderInExercise: 1
        )

        let didCommit = CustomRepRangeCommitter.commit(min: 8, max: 12, to: set)

        XCTAssertTrue(didCommit)
        XCTAssertEqual(set.reps, 6)
        XCTAssertEqual(set.overrideTargetRepMin, 8)
        XCTAssertEqual(set.overrideTargetRepMax, 12)
    }

    func testCustomRepRangeCommitStoresSingleValueAsNormalizedOverrideGuidance() {
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: UUID(),
            orderInWorkout: 1,
            orderInExercise: 1
        )

        let didCommit = CustomRepRangeCommitter.commit(min: 8, max: nil, to: set)

        XCTAssertTrue(didCommit)
        XCTAssertNil(set.reps)
        XCTAssertEqual(set.overrideTargetRepMin, 8)
        XCTAssertEqual(set.overrideTargetRepMax, 8)
    }

    func testTemplateSaveTargetRepBoundsNormalizeSingleValueOverride() {
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: UUID(),
            orderInWorkout: 1,
            orderInExercise: 1,
            targetRepMin: 8,
            targetRepMax: 12
        )
        set.overrideTargetRepMin = 6

        let bounds = set.templateSaveTargetRepBounds

        XCTAssertEqual(bounds.min, 6)
        XCTAssertEqual(bounds.max, 6)
    }

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

    func testReadOnlyFieldsMatchTrackingTypeVariants() {
        XCTAssertEqual(
            WorkoutSetPerformanceFormatter.readOnlyFields(for: .durationDistance),
            [.distance, .time]
        )
        XCTAssertEqual(
            WorkoutSetPerformanceFormatter.readOnlyFields(for: .weightDistance),
            [.weight, .distance]
        )
        XCTAssertEqual(
            WorkoutSetPerformanceFormatter.readOnlyFields(for: .weightRepsDuration),
            [.weight, .reps, .time, .rir]
        )
    }

    func testReadOnlyFieldDisplayUsesDurationDistanceValues() {
        let exercise = Exercise(
            name: "Running",
            equipmentType: .bodyweight,
            trackingType: .durationDistance,
            primaryMuscle: "legs"
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            durationSeconds: 150,
            distanceMeters: 400,
            orderInWorkout: 1,
            orderInExercise: 1
        )

        let distanceDisplay = WorkoutSetPerformanceFormatter.fieldDisplay(for: .distance, set: set, exercise: exercise)
        let timeDisplay = WorkoutSetPerformanceFormatter.fieldDisplay(for: .time, set: set, exercise: exercise)

        XCTAssertEqual(distanceDisplay.text, "400 m")
        XCTAssertEqual(timeDisplay.text, "2m 30s")
    }

    func testWorkoutAggregateSummarySelectsDistanceForRunningWorkout() {
        let exercise = Exercise(
            name: "Run",
            equipmentType: .bodyweight,
            trackingType: .durationDistance,
            primaryMuscle: "legs"
        )
        let firstSet = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            durationSeconds: 180,
            distanceMeters: 600,
            orderInWorkout: 1,
            orderInExercise: 1
        )
        let secondSet = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            durationSeconds: 150,
            distanceMeters: 400,
            orderInWorkout: 2,
            orderInExercise: 2
        )

        let aggregate = WorkoutAggregateSummary.summarize(
            sets: [firstSet, secondSet],
            exercisesById: [exercise.id: exercise]
        )

        if case let .distance(value)? = aggregate.primaryMetric {
            XCTAssertEqual(value, 1000, accuracy: 0.001)
        } else {
            XCTFail("Expected distance as the primary metric")
        }
    }

    func testWorkoutAggregateSummarySelectsDurationForDurationOnlyWorkout() {
        let exercise = Exercise(
            name: "Plank",
            equipmentType: .bodyweight,
            trackingType: .duration,
            primaryMuscle: "abs"
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            durationSeconds: 95,
            orderInWorkout: 1,
            orderInExercise: 1
        )

        let aggregate = WorkoutAggregateSummary.summarize(
            sets: [set],
            exercisesById: [exercise.id: exercise]
        )

        if case let .duration(value)? = aggregate.primaryMetric {
            XCTAssertEqual(value, 95)
        } else {
            XCTFail("Expected duration as the primary metric")
        }
    }

    func testWorkoutAggregateSummaryUsesMostSetsAndDistanceTieBreaker() {
        let strengthExercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        let durationExercise = Exercise(
            name: "Plank",
            equipmentType: .bodyweight,
            trackingType: .duration,
            primaryMuscle: "abs"
        )
        let distanceExercise = Exercise(
            name: "Run",
            equipmentType: .bodyweight,
            trackingType: .durationDistance,
            primaryMuscle: "legs"
        )

        let strengthSet = WorkoutSet(
            workoutId: UUID(),
            exerciseId: strengthExercise.id,
            weight: 100,
            effectiveWeight: 100,
            reps: 5,
            orderInWorkout: 1,
            orderInExercise: 1
        )
        let durationSet = WorkoutSet(
            workoutId: UUID(),
            exerciseId: durationExercise.id,
            durationSeconds: 90,
            orderInWorkout: 2,
            orderInExercise: 1
        )
        let distanceSet = WorkoutSet(
            workoutId: UUID(),
            exerciseId: distanceExercise.id,
            durationSeconds: 180,
            distanceMeters: 800,
            orderInWorkout: 3,
            orderInExercise: 1
        )

        let tieAggregate = WorkoutAggregateSummary.summarize(
            sets: [strengthSet, durationSet, distanceSet],
            exercisesById: [
                strengthExercise.id: strengthExercise,
                durationExercise.id: durationExercise,
                distanceExercise.id: distanceExercise
            ]
        )

        if case let .distance(value)? = tieAggregate.primaryMetric {
            XCTAssertEqual(value, 800, accuracy: 0.001)
        } else {
            XCTFail("Expected distance to win the family tie-breaker")
        }

        let mostSetsAggregate = WorkoutAggregateSummary.summarize(
            sets: [strengthSet, distanceSet, distanceSet],
            exercisesById: [
                strengthExercise.id: strengthExercise,
                distanceExercise.id: distanceExercise
            ]
        )

        if case let .distance(value)? = mostSetsAggregate.primaryMetric {
            XCTAssertEqual(value, 1600, accuracy: 0.001)
        } else {
            XCTFail("Expected most-sets selection to prefer distance")
        }
    }

    func testKeyboardContextMovesFromDistanceToDurationUsingTrackedOrder() {
        var focusedField: SetRowInputField? = .distance
        let context = SetEntryKeyboardContext(
            ownerSetID: UUID(),
            trackingType: .durationDistance,
            equipmentType: .bodyweight,
            inputOrder: [.distance, .duration],
            activeField: .distance,
            getFocusedField: { focusedField },
            setFocusedField: { focusedField = $0 },
            getFieldValue: { _ in "" },
            setFieldValue: { _, _ in },
            getBilateralRIRValue: { nil },
            setBilateralRIRValue: { _ in },
            getSuggestedWeight: { nil },
            canMovePrevious: { false },
            canMoveNext: { true },
            movePrevious: {},
            moveNext: {},
            dismiss: {}
        )

        XCTAssertTrue(context.canMoveNextInTrackedOrder)
        XCTAssertFalse(context.canMovePreviousInTrackedOrder)

        context.moveNextInTrackedOrder()

        XCTAssertEqual(context.trackedField, .duration)
        XCTAssertEqual(focusedField, .duration)
        XCTAssertFalse(context.canMoveNextInTrackedOrder)
        XCTAssertTrue(context.canMovePreviousInTrackedOrder)
    }

    func testKeyboardContextMovesBackFromDurationToDistanceUsingTrackedOrder() {
        var focusedField: SetRowInputField? = .duration
        let context = SetEntryKeyboardContext(
            ownerSetID: UUID(),
            trackingType: .durationDistance,
            equipmentType: .bodyweight,
            inputOrder: [.distance, .duration],
            activeField: .duration,
            getFocusedField: { focusedField },
            setFocusedField: { focusedField = $0 },
            getFieldValue: { _ in "" },
            setFieldValue: { _, _ in },
            getBilateralRIRValue: { nil },
            setBilateralRIRValue: { _ in },
            getSuggestedWeight: { nil },
            canMovePrevious: { true },
            canMoveNext: { false },
            movePrevious: {},
            moveNext: {},
            dismiss: {}
        )

        XCTAssertTrue(context.canMovePreviousInTrackedOrder)
        XCTAssertFalse(context.canMoveNextInTrackedOrder)

        context.movePreviousInTrackedOrder()

        XCTAssertEqual(context.trackedField, .distance)
        XCTAssertEqual(focusedField, .distance)
        XCTAssertTrue(context.canMoveNextInTrackedOrder)
        XCTAssertFalse(context.canMovePreviousInTrackedOrder)
    }

    func testKeyboardContextResolvesSharedRIRForBilateralReps() {
        var focusedField: SetRowInputField? = .reps
        var bilateralRIR: Double? = 2
        var leftRIR: Double? = 1
        var rightRIR: Double? = 4
        let context = SetEntryKeyboardContext(
            ownerSetID: UUID(),
            trackingType: .weightReps,
            equipmentType: .dumbbell,
            inputOrder: [.weight, .reps],
            activeField: .reps,
            getFocusedField: { focusedField },
            setFocusedField: { focusedField = $0 },
            getFieldValue: { _ in "" },
            setFieldValue: { _, _ in },
            getBilateralRIRValue: { bilateralRIR },
            setBilateralRIRValue: { bilateralRIR = $0 },
            getLeftRIRValue: { leftRIR },
            setLeftRIRValue: { leftRIR = $0 },
            getRightRIRValue: { rightRIR },
            setRightRIRValue: { rightRIR = $0 },
            getSuggestedWeight: { nil },
            canMovePrevious: { true },
            canMoveNext: { false },
            movePrevious: {},
            moveNext: {},
            dismiss: {}
        )

        XCTAssertTrue(context.canEditActiveRIR)
        XCTAssertEqual(context.resolvedRIRField, .reps)
        XCTAssertEqual(context.resolvedRIRValue(), 2)

        context.setResolvedRIRValue(3)

        XCTAssertEqual(bilateralRIR, 3)
        XCTAssertEqual(leftRIR, 1)
        XCTAssertEqual(rightRIR, 4)
    }

    func testKeyboardContextResolvesLeftRIRForLeftReps() {
        var focusedField: SetRowInputField? = .leftReps
        var bilateralRIR: Double? = 2
        var leftRIR: Double? = 1
        var rightRIR: Double? = 4
        let context = SetEntryKeyboardContext(
            ownerSetID: UUID(),
            trackingType: .weightReps,
            equipmentType: .dumbbell,
            inputOrder: [.weight, .leftReps, .rightReps],
            activeField: .leftReps,
            getFocusedField: { focusedField },
            setFocusedField: { focusedField = $0 },
            getFieldValue: { _ in "" },
            setFieldValue: { _, _ in },
            getBilateralRIRValue: { bilateralRIR },
            setBilateralRIRValue: { bilateralRIR = $0 },
            getLeftRIRValue: { leftRIR },
            setLeftRIRValue: { leftRIR = $0 },
            getRightRIRValue: { rightRIR },
            setRightRIRValue: { rightRIR = $0 },
            getSuggestedWeight: { nil },
            canMovePrevious: { true },
            canMoveNext: { true },
            movePrevious: {},
            moveNext: {},
            dismiss: {}
        )

        XCTAssertTrue(context.canEditActiveRIR)
        XCTAssertEqual(context.resolvedRIRField, .leftReps)
        XCTAssertEqual(context.resolvedRIRValue(), 1)

        context.setResolvedRIRValue(0)

        XCTAssertEqual(bilateralRIR, 2)
        XCTAssertEqual(leftRIR, 0)
        XCTAssertEqual(rightRIR, 4)
    }

    func testKeyboardContextResolvesRightRIRForRightReps() {
        var focusedField: SetRowInputField? = .rightReps
        var bilateralRIR: Double? = 2
        var leftRIR: Double? = 1
        var rightRIR: Double? = 4
        let context = SetEntryKeyboardContext(
            ownerSetID: UUID(),
            trackingType: .weightReps,
            equipmentType: .dumbbell,
            inputOrder: [.weight, .leftReps, .rightReps],
            activeField: .rightReps,
            getFocusedField: { focusedField },
            setFocusedField: { focusedField = $0 },
            getFieldValue: { _ in "" },
            setFieldValue: { _, _ in },
            getBilateralRIRValue: { bilateralRIR },
            setBilateralRIRValue: { bilateralRIR = $0 },
            getLeftRIRValue: { leftRIR },
            setLeftRIRValue: { leftRIR = $0 },
            getRightRIRValue: { rightRIR },
            setRightRIRValue: { rightRIR = $0 },
            getSuggestedWeight: { nil },
            canMovePrevious: { true },
            canMoveNext: { false },
            movePrevious: {},
            moveNext: {},
            dismiss: {}
        )

        XCTAssertTrue(context.canEditActiveRIR)
        XCTAssertEqual(context.resolvedRIRField, .rightReps)
        XCTAssertEqual(context.resolvedRIRValue(), 4)

        context.setResolvedRIRValue(5)

        XCTAssertEqual(bilateralRIR, 2)
        XCTAssertEqual(leftRIR, 1)
        XCTAssertEqual(rightRIR, 5)
    }

    func testKeyboardContextDoesNotExposeRIRForNonRepFields() {
        var focusedField: SetRowInputField? = .weight
        var bilateralRIR: Double? = 2
        var leftRIR: Double? = 1
        var rightRIR: Double? = 4
        let context = SetEntryKeyboardContext(
            ownerSetID: UUID(),
            trackingType: .weightReps,
            equipmentType: .barbell,
            inputOrder: [.weight, .reps],
            activeField: .weight,
            getFocusedField: { focusedField },
            setFocusedField: { focusedField = $0 },
            getFieldValue: { _ in "" },
            setFieldValue: { _, _ in },
            getBilateralRIRValue: { bilateralRIR },
            setBilateralRIRValue: { bilateralRIR = $0 },
            getLeftRIRValue: { leftRIR },
            setLeftRIRValue: { leftRIR = $0 },
            getRightRIRValue: { rightRIR },
            setRightRIRValue: { rightRIR = $0 },
            getSuggestedWeight: { nil },
            canMovePrevious: { false },
            canMoveNext: { true },
            movePrevious: {},
            moveNext: {},
            dismiss: {}
        )

        XCTAssertFalse(context.canEditActiveRIR)
        XCTAssertNil(context.resolvedRIRField)
        XCTAssertNil(context.resolvedRIRValue())

        context.setResolvedRIRValue(0)

        XCTAssertEqual(bilateralRIR, 2)
        XCTAssertEqual(leftRIR, 1)
        XCTAssertEqual(rightRIR, 4)
    }

    func testMuscleGroupCatalogNormalizesLegacyAliases() {
        XCTAssertEqual(ExercisePrimaryGroup.normalizedValue("core"), "abs")
        XCTAssertEqual(ExercisePrimaryGroup.normalizedValue("abdominals"), "abs")
        XCTAssertEqual(ExercisePrimaryGroup.normalizedValue("forearm"), "forearms")
        XCTAssertEqual(ExercisePrimaryGroup.displayName(for: "core"), "Abs")
        XCTAssertEqual(ExercisePrimaryGroup.displayName(for: "forearm"), "Forearms")
    }
}
