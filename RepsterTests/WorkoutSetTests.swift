import XCTest
import SwiftData
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

        let display = WorkoutSetPerformanceFormatter.display(
            for: set,
            exercise: exercise,
            unitPreference: .metric
        )

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

    // MARK: - Snapshot parity with live models
    //
    // The detail cards render from ChartSetData, not WorkoutSet. Every field the card
    // reads has to survive the snapshot, and a missing one fails silently — an RIR
    // column that renders "—" for every set produces no crash and no error.
    // See SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md §8.1, §10, §11.

    func testChartSetDataCarriesFieldsTheDetailCardsRender() {
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: UUID(),
            weight: 100,
            effectiveWeight: 100,
            reps: 8,
            rir: 2,
            leftRIR: 1,
            rightRIR: 3,
            setType: .warmup,
            notes: "felt heavy",
            orderInWorkout: 7,
            orderInExercise: 3,
            completed: true
        )

        let snapshot = ChartSetData(from: set)

        XCTAssertEqual(snapshot.rir, 2)
        XCTAssertEqual(snapshot.leftRIR, 1)
        XCTAssertEqual(snapshot.rightRIR, 3)
        XCTAssertEqual(snapshot.notes, "felt heavy")
        XCTAssertTrue(snapshot.hasNote)
        XCTAssertEqual(snapshot.orderInWorkout, 7)
        XCTAssertEqual(snapshot.orderInExercise, 3)
        XCTAssertEqual(snapshot.setType, .warmup)
        XCTAssertTrue(snapshot.completed)
    }

    /// The regression this guards: the snapshot `display` overload used to hardcode
    /// `rir: nil`, so converting the detail cards would have blanked the RIR column
    /// for `.weightReps` and `.custom` — the two most common tracking types.
    func testRIRFieldDisplayMatchesBetweenLiveModelAndSnapshot() {
        let exercise = Exercise(
            name: "Bench Press",
            equipmentType: .barbell,
            trackingType: .weightReps,
            primaryMuscle: "chest"
        )
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            weight: 100,
            effectiveWeight: 100,
            reps: 8,
            rir: 2,
            orderInWorkout: 1,
            orderInExercise: 1
        )

        let live = WorkoutSetPerformanceFormatter.fieldDisplay(
            for: .rir,
            set: set,
            exercise: exercise,
            unitPreference: .metric
        )
        let snapshot = WorkoutSetPerformanceFormatter.fieldDisplay(
            for: .rir,
            set: ChartSetData(from: set),
            exercise: ChartExerciseData(from: exercise),
            unitPreference: .metric
        )

        XCTAssertEqual(snapshot.text, "2")
        XCTAssertEqual(snapshot, live)
    }

    func testPerSideRIRFieldDisplayMatchesBetweenLiveModelAndSnapshot() {
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
            leftRIR: 1,
            rightRIR: 3,
            orderInWorkout: 1,
            orderInExercise: 1
        )

        for field in WorkoutSetPerformanceFormatter.readOnlyFields(for: exercise.trackingType) {
            let live = WorkoutSetPerformanceFormatter.fieldDisplay(
                for: field,
                set: set,
                exercise: exercise,
                unitPreference: .metric
            )
            let snapshot = WorkoutSetPerformanceFormatter.fieldDisplay(
                for: field,
                set: ChartSetData(from: set),
                exercise: ChartExerciseData(from: exercise),
                unitPreference: .metric
            )
            XCTAssertEqual(snapshot, live, "field \(field.rawValue) differs between live and snapshot")
        }

        let snapshotRIR = WorkoutSetPerformanceFormatter.fieldDisplay(
            for: .rir,
            set: ChartSetData(from: set),
            exercise: ChartExerciseData(from: exercise),
            unitPreference: .metric
        )
        XCTAssertEqual(snapshotRIR.stackedLabels, ["L1", "R3"])
    }

    /// PR badges on the detail cards go through this overload.
    func testEffectiveStatusMatchesBetweenLiveModelAndSnapshot() {
        let exerciseId = UUID()
        let workoutId = UUID()

        func makeSet(weight: Double, reps: Int, status: CachedPRStatus?) -> WorkoutSet {
            let set = WorkoutSet(
                workoutId: workoutId,
                exerciseId: exerciseId,
                weight: weight,
                effectiveWeight: weight,
                reps: reps,
                orderInWorkout: 1,
                orderInExercise: 1
            )
            set.prStatus = status
            return set
        }

        let matched = makeSet(weight: 100, reps: 5, status: .matched)
        let dominator = makeSet(weight: 100, reps: 8, status: .current)
        let siblings = [matched, dominator]
        let snapshots = siblings.map(ChartSetData.init(from:))

        // Dominated by a same-weight, higher-rep sibling → badge suppressed.
        XCTAssertNil(CachedPRStatus.effectiveStatus(for: matched, among: siblings))
        XCTAssertNil(CachedPRStatus.effectiveStatus(for: snapshots[0], among: snapshots))

        // Undominated → badge shown, and the two overloads agree.
        XCTAssertEqual(
            CachedPRStatus.effectiveStatus(for: snapshots[0], among: [snapshots[0]]),
            CachedPRStatus.effectiveStatus(for: matched, among: [matched])
        )
        XCTAssertEqual(CachedPRStatus.effectiveStatus(for: snapshots[0], among: [snapshots[0]]), .matched)
    }

    func testWorkoutSnapshotResolvesDisplayTitleAtSnapshotTime() {
        let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9))!
        let untitled = Workout(date: morning, startTime: morning, status: .completed)
        XCTAssertEqual(WorkoutSnapshot(from: untitled).displayTitle, "Morning Workout")

        let titled = Workout(date: morning, title: "Push Day", startTime: morning, status: .completed)
        let snapshot = WorkoutSnapshot(from: titled)
        XCTAssertEqual(snapshot.displayTitle, "Push Day")
        XCTAssertEqual(snapshot.status, .completed)
        XCTAssertEqual(snapshot.id, titled.id)
    }

    // MARK: - ChartExerciseData is a faithful mirror of Exercise
    //
    // Stage 2 step 1 replaced live `Exercise` handles with `ChartExerciseData` throughout the
    // active-workout surface. Anything the snapshot reports differently from the model is a
    // silent behaviour change — `usesTotalAcrossSidesRepTargets` in particular decides whether
    // rep targets are per-side or total, with no error if it flips.
    // See STAGE2_WRITE_PATH_DESIGN.md §7 step 1.

    /// Builds one exercise per interesting combination and asserts the snapshot agrees with
    /// the model on every stored field and every computed property.
    func testChartExerciseDataMirrorsEveryExerciseField() {
        let exercises = [
            Exercise(
                name: "Bench Press",
                equipmentType: .barbell,
                trackingType: .weightReps,
                primaryMuscle: "chest",
                secondaryMuscles: ["triceps", "shoulders"],
                movementPattern: .press,
                unilateral: false,
                bilateralLoadFactor: 1.5,
                bodyweightFactor: 0,
                weightIncrement: 2.5,
                defaultRestTime: 120,
                fatigueRate: 0.04,
                fatigueRateSourceRawValue: ExerciseFatigueRateSource.manualOverride.rawValue,
                recoveryConstant: 200,
                fatigueLearningSessionCount: 3,
                fatigueLearningCumulativeError: -0.02
            ),
            Exercise(
                name: "Pull Up",
                equipmentType: .bodyweight,
                trackingType: .weightReps,
                unilateral: false,
                bodyweightFactor: 1.0
            ),
            Exercise(
                name: "Split Squat",
                equipmentType: .dumbbell,
                trackingType: .weightReps,
                unilateral: true,
                unilateralRepTargetMode: .totalAcrossSides
            ),
            Exercise(
                name: "Farmer Carry",
                equipmentType: .dumbbell,
                trackingType: .weightDistance,
                unilateral: true
            ),
            Exercise(name: "Plank", equipmentType: .bodyweight, trackingType: .duration),
        ]

        for exercise in exercises {
            let snapshot = ChartExerciseData(from: exercise)
            let label = exercise.name

            XCTAssertEqual(snapshot.id, exercise.id, label)
            XCTAssertEqual(snapshot.name, exercise.name, label)
            XCTAssertEqual(snapshot.equipmentType, exercise.equipmentType, label)
            XCTAssertEqual(snapshot.trackingType, exercise.trackingType, label)
            XCTAssertEqual(snapshot.primaryMuscle, exercise.primaryMuscle, label)
            XCTAssertEqual(snapshot.secondaryMuscles, exercise.secondaryMuscles, label)
            XCTAssertEqual(snapshot.movementPattern, exercise.movementPattern, label)
            XCTAssertEqual(snapshot.unilateral, exercise.unilateral, label)
            XCTAssertEqual(
                snapshot.unilateralRepTargetModeRawValue,
                exercise.unilateralRepTargetModeRawValue,
                label
            )
            XCTAssertEqual(snapshot.bilateralLoadFactor, exercise.bilateralLoadFactor, label)
            XCTAssertEqual(snapshot.bodyweightFactor, exercise.bodyweightFactor, label)
            XCTAssertEqual(snapshot.weightIncrement, exercise.weightIncrement, label)
            XCTAssertEqual(snapshot.defaultRestTime, exercise.defaultRestTime, label)
            XCTAssertEqual(snapshot.fatigueRate, exercise.fatigueRate, label)
            XCTAssertEqual(snapshot.fatigueRateSourceRawValue, exercise.fatigueRateSourceRawValue, label)
            XCTAssertEqual(snapshot.recoveryConstant, exercise.recoveryConstant, label)
            XCTAssertEqual(
                snapshot.fatigueLearningSessionCount,
                exercise.fatigueLearningSessionCount,
                label
            )
            XCTAssertEqual(
                snapshot.fatigueLearningCumulativeError,
                exercise.fatigueLearningCumulativeError,
                label
            )
            XCTAssertEqual(snapshot.createdAt, exercise.createdAt, label)
            XCTAssertEqual(snapshot.updatedAt, exercise.updatedAt, label)

            // Computed parity — the part that fails silently.
            XCTAssertEqual(
                snapshot.supportsUnilateralLogging,
                exercise.supportsUnilateralLogging,
                "supportsUnilateralLogging: \(label)"
            )
            XCTAssertEqual(
                snapshot.unilateralRepTargetMode,
                exercise.unilateralRepTargetMode,
                "unilateralRepTargetMode: \(label)"
            )
            XCTAssertEqual(
                snapshot.usesTotalAcrossSidesRepTargets,
                exercise.usesTotalAcrossSidesRepTargets,
                "usesTotalAcrossSidesRepTargets: \(label)"
            )
            XCTAssertEqual(
                snapshot.resolvedFatigueRateSource,
                exercise.resolvedFatigueRateSource,
                "resolvedFatigueRateSource: \(label)"
            )
            XCTAssertEqual(
                snapshot.isBodyweightStyleExercise,
                exercise.isBodyweightStyleExercise,
                "isBodyweightStyleExercise: \(label)"
            )
        }
    }

    /// `unilateralRepTargetMode` falls back on the exercise *name* when nothing is stored.
    /// A second copy of that rule in the snapshot would change rep targets for exactly these
    /// exercises and nothing else — the least likely thing to be noticed by hand.
    func testUnilateralRepTargetModeNameFallbackMatchesBetweenModelAndSnapshot() {
        let named = Exercise(
            name: "Dumbbell Lunge",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            unilateral: true
        )
        XCTAssertNil(named.unilateralRepTargetModeRawValue)
        XCTAssertEqual(named.unilateralRepTargetMode, .totalAcrossSides)
        XCTAssertEqual(ChartExerciseData(from: named).unilateralRepTargetMode, .totalAcrossSides)
        XCTAssertTrue(ChartExerciseData(from: named).usesTotalAcrossSidesRepTargets)

        // Case and surrounding whitespace are normalised by the same rule on both sides.
        let padded = Exercise(
            name: "  dumbbell LUNGE  ",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            unilateral: true
        )
        XCTAssertEqual(
            ChartExerciseData(from: padded).unilateralRepTargetMode,
            padded.unilateralRepTargetMode
        )
        XCTAssertEqual(ChartExerciseData(from: padded).unilateralRepTargetMode, .totalAcrossSides)

        // Not unilateral → fallback does not apply, on either side.
        let bilateral = Exercise(
            name: "Dumbbell Lunge",
            equipmentType: .dumbbell,
            trackingType: .weightReps,
            unilateral: false
        )
        XCTAssertEqual(bilateral.unilateralRepTargetMode, .perSide)
        XCTAssertEqual(ChartExerciseData(from: bilateral).unilateralRepTargetMode, .perSide)

        // Tracking type without per-side logging → fallback does not apply either.
        let unsupported = Exercise(
            name: "Dumbbell Lunge",
            equipmentType: .dumbbell,
            trackingType: .duration,
            unilateral: true
        )
        XCTAssertEqual(unsupported.unilateralRepTargetMode, .perSide)
        XCTAssertEqual(ChartExerciseData(from: unsupported).unilateralRepTargetMode, .perSide)
    }

    /// Every tracking type, both directions, so a future case added to the enum can't quietly
    /// disagree between model and snapshot.
    func testSupportsUnilateralLoggingMatchesAcrossAllTrackingTypes() {
        for trackingType in TrackingType.allCases {
            let exercise = Exercise(name: "X", equipmentType: .dumbbell, trackingType: trackingType)
            XCTAssertEqual(
                ChartExerciseData(from: exercise).supportsUnilateralLogging,
                exercise.supportsUnilateralLogging,
                "\(trackingType)"
            )
            XCTAssertEqual(
                trackingType.supportsUnilateralLogging,
                exercise.supportsUnilateralLogging,
                "\(trackingType)"
            )
        }
    }

    /// Seeding editable fields from a snapshot must reproduce the exercise exactly, or an edit
    /// to one field would quietly reset the others.
    func testExerciseEditableFieldsRoundTripPreservesEveryEditableField() {
        let exercise = Exercise(
            name: "Incline Dumbbell Press",
            equipmentType: .dumbbell,
            trackingType: .weightRepsDuration,
            primaryMuscle: "chest",
            secondaryMuscles: ["shoulders", "triceps"],
            movementPattern: .press,
            unilateral: true,
            unilateralRepTargetMode: .totalAcrossSides,
            bilateralLoadFactor: 2.0,
            bodyweightFactor: 0.25,
            weightIncrement: 1.25,
            defaultRestTime: 90
        )

        let fields = ExerciseEditableFields(from: ChartExerciseData(from: exercise))

        XCTAssertEqual(fields.name, exercise.name)
        XCTAssertEqual(fields.equipmentType, exercise.equipmentType)
        XCTAssertEqual(fields.trackingType, exercise.trackingType)
        XCTAssertEqual(fields.primaryMuscle, exercise.primaryMuscle)
        XCTAssertEqual(fields.secondaryMuscles, exercise.secondaryMuscles)
        XCTAssertEqual(fields.movementPattern, exercise.movementPattern)
        XCTAssertEqual(fields.unilateral, exercise.unilateral)
        XCTAssertEqual(fields.unilateralRepTargetMode, exercise.unilateralRepTargetMode)
        XCTAssertEqual(fields.bilateralLoadFactor, exercise.bilateralLoadFactor)
        XCTAssertEqual(fields.bodyweightFactor, exercise.bodyweightFactor)
        XCTAssertEqual(fields.weightIncrement, exercise.weightIncrement)
        XCTAssertEqual(fields.defaultRestTime, exercise.defaultRestTime)

        // Going straight from the live model must give the same thing.
        XCTAssertEqual(ExerciseEditableFields(from: exercise), fields)
    }

    /// Fails when a stored property is added to `Exercise` and not to `ChartExerciseData`.
    ///
    /// The field-by-field test above can only check fields that exist on *both* types, so it
    /// is blind to a newly added one. Reflection closes that gap: a new `Exercise` property
    /// makes this fail immediately, with the missing name in the message, instead of the
    /// snapshot quietly dropping data that some screen later needs.
    func testChartExerciseDataCoversEveryStoredExerciseProperty() {
        let exercise = Exercise(name: "X", equipmentType: .barbell, trackingType: .weightReps)

        // SwiftData's macro storage shows up as `_name` plus `_$backingData` /
        // `_$observationRegistrar`; strip the prefix and drop the macro internals.
        let modelProperties = Set(
            Mirror(reflecting: exercise).children
                .compactMap(\.label)
                .filter { !$0.hasPrefix("_$") }
                .map { String($0.dropFirst()) }
        )
        let snapshotProperties = Set(
            Mirror(reflecting: ChartExerciseData(from: exercise)).children.compactMap(\.label)
        )

        XCTAssertFalse(modelProperties.isEmpty, "Reflection returned nothing — the check is vacuous")
        XCTAssertEqual(
            modelProperties.subtracting(snapshotProperties),
            [],
            "Exercise gained stored properties that ChartExerciseData does not mirror"
        )
        XCTAssertEqual(
            snapshotProperties.subtracting(modelProperties),
            [],
            "ChartExerciseData has stored properties Exercise does not — the mirror has drifted"
        )
    }

    /// Fails when a stored property is added to `WorkoutSet` and not to `ChartSetData`.
    ///
    /// The `Exercise` guard above can compare name sets directly. This one cannot, for three
    /// reasons that are all properties of `WorkoutSet` rather than of the technique — so they are
    /// declared here explicitly instead of being silently absorbed by a looser assertion:
    ///
    ///  1. **`@Transient` breaks the prefix strip.** SwiftData's macro rewrites persisted
    ///     properties to `_name`; a `@Transient` one stays `persistedFatigueSnapshot`. The blanket
    ///     `dropFirst()` the `Exercise` guard uses would turn that into `ersistedFatigueSnapshot`
    ///     and compare garbage. `Exercise` has no transients, so it never hit this.
    ///  2. **One property must never be mirrored.** `cachedPRStatus` is a legacy persisted enum
    ///     kept for schema compatibility only, and its declaration says app logic must not read
    ///     it. Requiring it in the snapshot would mandate exactly that.
    ///  3. **Three snapshot fields mirror computed accessors, not storage.** `prStatus` is the
    ///     decoded form of `cachedPRStatusRaw`; `prReps` and `totalReps` are derived. They are
    ///     legitimately on the snapshot and legitimately absent from the model's storage.
    ///
    /// Anything outside those three exemptions has to be mirrored, by name.
    func testChartSetDataCoversEveryStoredWorkoutSetProperty() {
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: UUID(),
            orderInWorkout: 1,
            orderInExercise: 1
        )

        /// Never mirrored. Adding to this set is a decision, not a formality.
        let exemptFromMirroring: Set<String> = [
            // Legacy schema-compatibility field; `WorkoutSet.swift:40` forbids reading it.
            "cachedPRStatus",
            // @Transient — never persisted, and step 5 makes it actor-internal.
            "persistedFatigueSnapshot",
        ]

        /// Snapshot field -> the model storage it stands for.
        let aliases: [String: String] = [
            "prStatus": "cachedPRStatusRaw",
        ]

        /// Snapshot fields derived from storage rather than mirroring one property.
        let derivedOnSnapshot: Set<String> = ["prReps", "totalReps"]

        let modelProperties = Set(
            Mirror(reflecting: set).children
                .compactMap(\.label)
                .filter { !$0.hasPrefix("_$") }
                // Strip the macro prefix only where the macro actually applied it.
                .map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        )
        let snapshotProperties = Set(
            Mirror(reflecting: ChartSetData(from: set)).children.compactMap(\.label)
        )

        XCTAssertFalse(modelProperties.isEmpty, "Reflection returned nothing — the check is vacuous")
        XCTAssertTrue(
            modelProperties.contains("persistedFatigueSnapshot"),
            "The @Transient property is no longer reflected under its own name — the prefix "
                + "handling above needs rechecking, not the exemption list"
        )

        let covered: Set<String> = Set(snapshotProperties.map { aliases[$0] ?? $0 })

        XCTAssertEqual(
            modelProperties.subtracting(covered).subtracting(exemptFromMirroring),
            Set<String>(),
            "WorkoutSet gained stored properties that ChartSetData does not mirror"
        )
        XCTAssertEqual(
            covered.subtracting(modelProperties).subtracting(derivedOnSnapshot),
            Set<String>(),
            "ChartSetData has fields WorkoutSet does not — the mirror has drifted"
        )
    }

    // MARK: - PRBadgeApplier
    //
    // The badge-application rule, extracted from two byte-identical private copies in
    // ActiveWorkoutViewModel and EditWorkoutViewModel (STEP5 §0.5). Unit-tested directly because
    // no higher-level test can currently discriminate it: PRService writes each status onto the
    // same @Model instance the ViewModels hold before returning, so a journey test passes whether
    // this function works or does nothing at all.

    private func makeBadgeSet(prStatus: CachedPRStatus?, completed: Bool) -> WorkoutSet {
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: UUID(),
            weight: 100,
            reps: 5,
            orderInWorkout: 1,
            orderInExercise: 1,
            completed: completed
        )
        set.prStatus = prStatus
        return set
    }

    /// The behaviour chosen on 2026-08-13: badges always match the stored state.
    ///
    /// The removed rule blocked exactly this — a completed set gaining a badge mid-workout. It
    /// never fired in shipped code, and reviving it at step 5 would have left the screen showing
    /// no badge on the set that legitimately inherits a record after a delete or an un-tick.
    func testCompletedSetsReceivePromotions() {
        let set = makeBadgeSet(prStatus: nil, completed: true)
        var state = [set.exerciseId: [set]]

        PRBadgeApplier.apply([set.id: .current], to: &state)

        XCTAssertEqual(set.prStatus, .current, "a completed set must be allowed to gain a badge")
    }

    func testCompletedSetsReceiveDemotions() {
        let set = makeBadgeSet(prStatus: .current, completed: true)
        var state = [set.exerciseId: [set]]

        PRBadgeApplier.apply([set.id: .previous], to: &state)

        XCTAssertEqual(set.prStatus, .previous)
    }

    /// The `[UUID: CachedPRStatus?]` trap: a **present but nil** entry means "clear this badge".
    ///
    /// `affectedSetIds[id]` is `CachedPRStatus??`. Unwrapping only the outer optional is what
    /// makes a clear reach the set; flattening with `??` would turn every demotion-to-nothing
    /// into a no-op and silently strand stale ★s on screen.
    func testPresentButNilEntryClearsTheBadge() {
        let set = makeBadgeSet(prStatus: .current, completed: true)
        var state = [set.exerciseId: [set]]

        PRBadgeApplier.apply([set.id: CachedPRStatus?.none], to: &state)

        XCTAssertNil(set.prStatus, "a present-but-nil entry must clear the badge, not be skipped")
    }

    func testSetsNotMentionedAreLeftAlone() {
        let mentioned = makeBadgeSet(prStatus: nil, completed: true)
        let untouched = makeBadgeSet(prStatus: .matched, completed: true)
        var state = [mentioned.exerciseId: [mentioned, untouched]]

        PRBadgeApplier.apply([mentioned.id: .current], to: &state)

        XCTAssertEqual(mentioned.prStatus, .current)
        XCTAssertEqual(untouched.prStatus, .matched, "an unmentioned set must not be rewritten")
    }

    /// Incomplete sets were never covered by the old rule, and still are not special.
    func testIncompleteSetsAreTreatedIdentically() {
        let set = makeBadgeSet(prStatus: nil, completed: false)
        var state = [set.exerciseId: [set]]

        PRBadgeApplier.apply([set.id: .current], to: &state)

        XCTAssertEqual(set.prStatus, .current)
    }

    // MARK: - SetRepository.applyOrdering (Stage 2 step 4)

    private func makeSetRepo() throws -> SetRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, WorkoutSet.self, ExerciseStats.self,
            PerformanceRecord.self, HealthProfile.self,
            configurations: configuration
        )
        return SetRepository(modelContainer: container)
    }

    func testApplyOrderingWritesBothOrderFieldsAndSkipsUnknownIds() async throws {
        let repo = try makeSetRepo()
        let workoutId = UUID()
        let exerciseId = UUID()

        let a = WorkoutSet(workoutId: workoutId, exerciseId: exerciseId, orderInWorkout: 1, orderInExercise: 1)
        let b = WorkoutSet(workoutId: workoutId, exerciseId: exerciseId, orderInWorkout: 2, orderInExercise: 2)
        try await repo.save(a)
        try await repo.save(b)

        try await repo.applyOrdering([
            SetOrderUpdate(setId: b.id, orderInExercise: 1, orderInWorkout: 1),
            SetOrderUpdate(setId: a.id, orderInExercise: 2, orderInWorkout: 2),
            // An id that no longer exists must be skipped, not throw.
            SetOrderUpdate(setId: UUID(), orderInExercise: 9, orderInWorkout: 9),
        ])

        let persisted = try await repo.fetchChartSets(for: workoutId)
        let byId = Dictionary(uniqueKeysWithValues: persisted.map { ($0.id, $0) })
        XCTAssertEqual(byId[b.id]?.orderInExercise, 1)
        XCTAssertEqual(byId[b.id]?.orderInWorkout, 1)
        XCTAssertEqual(byId[a.id]?.orderInExercise, 2)
        XCTAssertEqual(byId[a.id]?.orderInWorkout, 2)
    }

    /// A `nil` field means "leave alone" — reindexing within an exercise must not disturb
    /// the workout-level ordering, and vice versa.
    func testApplyOrderingLeavesNilFieldsUntouched() async throws {
        let repo = try makeSetRepo()
        let workoutId = UUID()
        let set = WorkoutSet(
            workoutId: workoutId,
            exerciseId: UUID(),
            orderInWorkout: 7,
            orderInExercise: 3
        )
        try await repo.save(set)

        try await repo.applyOrdering([SetOrderUpdate(setId: set.id, orderInExercise: 1)])

        let persisted = try await repo.fetchChartSets(for: workoutId)
        XCTAssertEqual(persisted.first?.orderInExercise, 1)
        XCTAssertEqual(persisted.first?.orderInWorkout, 7, "orderInWorkout must be left alone")
    }

    /// `updatedAt` is a change marker; a set whose order did not move must not be touched.
    func testApplyOrderingOnlyBumpsUpdatedAtForSetsThatActuallyMoved() async throws {
        let repo = try makeSetRepo()
        let workoutId = UUID()
        let moved = WorkoutSet(workoutId: workoutId, exerciseId: UUID(), orderInWorkout: 1, orderInExercise: 1)
        let unmoved = WorkoutSet(workoutId: workoutId, exerciseId: UUID(), orderInWorkout: 2, orderInExercise: 2)
        try await repo.save(moved)
        try await repo.save(unmoved)

        let before = try await repo.fetchChartSets(for: workoutId)
        let unmovedBefore = try await repo.fetch(byId: unmoved.id)
        let unmovedUpdatedAtBefore = try XCTUnwrap(unmovedBefore?.updatedAt)
        XCTAssertEqual(before.count, 2)

        try await repo.applyOrdering([
            SetOrderUpdate(setId: moved.id, orderInExercise: 5),
            // Same value it already has → no write.
            SetOrderUpdate(setId: unmoved.id, orderInExercise: 2),
        ])

        let movedFetched = try await repo.fetch(byId: moved.id)
        let unmovedFetched = try await repo.fetch(byId: unmoved.id)
        let movedAfter = try XCTUnwrap(movedFetched)
        let unmovedAfter = try XCTUnwrap(unmovedFetched)
        XCTAssertEqual(movedAfter.orderInExercise, 5)
        XCTAssertEqual(unmovedAfter.orderInExercise, 2)
        XCTAssertEqual(
            unmovedAfter.updatedAt,
            unmovedUpdatedAtBefore,
            "a set whose order didn't change must not have updatedAt bumped"
        )
    }

    /// Symmetric to the test above. Found by mutation sweep 2026-08-12: the nil-means-leave-alone
    /// contract was only exercised for `orderInWorkout`, so writing a bogus `orderInExercise`
    /// when none was requested went unnoticed.
    func testApplyOrderingLeavesNilOrderInExerciseUntouched() async throws {
        let repo = try makeSetRepo()
        let workoutId = UUID()
        let set = WorkoutSet(
            workoutId: workoutId,
            exerciseId: UUID(),
            orderInWorkout: 7,
            orderInExercise: 3
        )
        try await repo.save(set)

        try await repo.applyOrdering([SetOrderUpdate(setId: set.id, orderInWorkout: 1)])

        let persisted = try await repo.fetchChartSets(for: workoutId)
        XCTAssertEqual(persisted.first?.orderInWorkout, 1)
        XCTAssertEqual(persisted.first?.orderInExercise, 3, "orderInExercise must be left alone")
    }

    /// The reindex reaches the store even though the caller already applied the same values.
    ///
    /// `ActiveWorkoutViewModel` holds this repository's own models and reindexes them on the
    /// main actor *before* batching, so `fetch(byId:)` returns the very instance it mutated
    /// and every value comparison inside `applyOrdering` reads as "unchanged". Found
    /// 2026-08-12: the old `didChangeAny` short-circuit took that as "no save needed" and the
    /// reindex sat uncommitted until an unrelated later write flushed it. Every other test
    /// here drives the repository directly, which is why none of them saw it.
    ///
    /// Asserted through a second `ModelContext` — it sees only what was committed, never
    /// another context's pending changes.
    func testApplyOrderingCommitsWhenTheCallerAlreadyAppliedTheValues() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, WorkoutSet.self, ExerciseStats.self,
            PerformanceRecord.self, HealthProfile.self,
            configurations: configuration
        )
        let repo = SetRepository(modelContainer: container)
        let workoutId = UUID()
        let set = WorkoutSet(
            workoutId: workoutId,
            exerciseId: UUID(),
            orderInWorkout: 1,
            orderInExercise: 1
        )
        try await repo.save(set)
        let setId = set.id

        // reindexOrderInExercise / reindexOrderInWorkout, on the caller's side.
        let live = try await repo.fetchSets(for: workoutId)
        let caller = try XCTUnwrap(live.first)
        caller.orderInExercise = 5
        caller.orderInWorkout = 9
        caller.updatedAt = Date()

        // persistSetOrdering
        try await repo.applyOrdering([
            SetOrderUpdate(setId: setId, orderInExercise: 5, orderInWorkout: 9)
        ])

        let probe = ModelContext(container)
        let committed = try probe.fetch(
            FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.id == setId })
        ).first
        XCTAssertEqual(
            committed?.orderInExercise,
            5,
            "the reindex must be committed, not left pending in the repository's context"
        )
        XCTAssertEqual(committed?.orderInWorkout, 9)
    }

    /// The weight column renders `effectiveWeight ?? weight`. Every other fixture in this suite
    /// has them equal, so a regression to plain `weight` was invisible (mutation sweep,
    /// 2026-08-12). Bodyweight-style exercises are where the two genuinely differ.
    func testWeightColumnUsesEffectiveWeightNotRawWeight() {
        let exercise = Exercise(
            name: "Pull Up",
            equipmentType: .bodyweight,
            trackingType: .weightReps,
            bodyweightFactor: 1.0
        )
        // weight = added load; effectiveWeight = added load + bodyweight contribution.
        let set = WorkoutSet(
            workoutId: UUID(),
            exerciseId: exercise.id,
            weight: 10,
            effectiveWeight: 90,
            reps: 6,
            orderInWorkout: 1,
            orderInExercise: 1
        )

        let snapshot = WorkoutSetPerformanceFormatter.fieldDisplay(
            for: .weight,
            set: ChartSetData(from: set),
            exercise: ChartExerciseData(from: exercise),
            unitPreference: .metric
        )
        let live = WorkoutSetPerformanceFormatter.fieldDisplay(
            for: .weight,
            set: set,
            exercise: exercise,
            unitPreference: .metric
        )

        XCTAssertEqual(snapshot.text, "90 kg", "must render effectiveWeight, not the 10 kg added load")
        XCTAssertEqual(snapshot, live)
    }

    /// Nothing covered the §8.4 hygiene change — the mirrored Apple Health UUID is now written
    /// inside the repository actor, and a no-op implementation passed the whole suite.
    func testSetHealthKitUUIDPersistsTheIdentifier() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, WorkoutSet.self, ExerciseStats.self,
            PerformanceRecord.self, HealthProfile.self,
            configurations: configuration
        )
        let repo = WorkoutRepository(modelContainer: container)
        let workout = Workout(date: Date(), status: .completed)
        try await repo.save(workout)

        let uuid = UUID()
        try await repo.setHealthKitUUID(uuid, forWorkoutId: workout.id)

        let persisted = try await repo.fetch(byId: workout.id)
        XCTAssertEqual(
            persisted?.healthKitWorkoutUUID,
            uuid,
            "the Health sample id must persist — it doubles as the sync flag and the delete handle"
        )

        // Unknown ids must be a quiet no-op, not a crash.
        try await repo.setHealthKitUUID(UUID(), forWorkoutId: UUID())
    }

    func testApplyOrderingWithEmptyBatchIsANoOp() async throws {
        let repo = try makeSetRepo()
        try await repo.applyOrdering([])
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

        let distanceDisplay = WorkoutSetPerformanceFormatter.fieldDisplay(
            for: .distance,
            set: set,
            exercise: exercise,
            unitPreference: .metric
        )
        let timeDisplay = WorkoutSetPerformanceFormatter.fieldDisplay(
            for: .time,
            set: set,
            exercise: exercise,
            unitPreference: .metric
        )

        XCTAssertEqual(distanceDisplay.text, "400 m")
        XCTAssertEqual(timeDisplay.text, "2m 30s")
    }

    func testImperialWeightDisplayRoundTripsCleanWholeAndFractionalPounds() {
        let oneHundredPoundsStored = UnitConversion.lbsToKg(100)
        let fractionalPoundsStored = UnitConversion.lbsToKg(102.5)

        XCTAssertEqual(
            UnitConversion.formatWeightLabel(oneHundredPoundsStored, unitPreference: .imperial),
            "100 lb"
        )
        XCTAssertEqual(
            UnitConversion.formatWeightLabel(fractionalPoundsStored, unitPreference: .imperial),
            "102.5 lb"
        )
    }

    func testLegacyMetricHistoryDisplaysExactImperialConversion() {
        XCTAssertEqual(
            UnitConversion.formatWeightLabel(100, unitPreference: .imperial),
            "220.46 lb"
        )
    }

    func testDefaultWeightIncrementUsesNativeDisplayUnit() {
        XCTAssertEqual(UnitConversion.defaultStoredWeightIncrement(for: .metric), 2.5)
        XCTAssertEqual(
            UnitConversion.formatWeightIncrementLabel(
                storedKg: UnitConversion.defaultStoredWeightIncrement(for: .imperial),
                unitPreference: .imperial,
                options: UnitConversion.displayWeightIncrementOptions(for: .imperial)
            ),
            "5 lb"
        )
    }

    func testMetricDefaultIncrementNormalizesToNativeImperialPreset() {
        let option = UnitConversion.normalizedWeightIncrementOption(
            storedKg: 2.5,
            unitPreference: .imperial,
            options: UnitConversion.displayWeightIncrementOptions(for: .imperial)
        )

        XCTAssertEqual(option.display, 5.0)
        XCTAssertEqual(option.storedKg, UnitConversion.lbsToKg(5), accuracy: 0.0001)
        XCTAssertEqual(
            UnitConversion.formatWeightIncrementLabel(
                storedKg: 2.5,
                unitPreference: .imperial,
                options: UnitConversion.displayWeightIncrementOptions(for: .imperial)
            ),
            "5 lb"
        )
    }

    func testImperialDefaultIncrementNormalizesToNativeMetricPreset() {
        let storedFivePounds = UnitConversion.lbsToKg(5)
        let option = UnitConversion.normalizedWeightIncrementOption(
            storedKg: storedFivePounds,
            unitPreference: .metric,
            options: UnitConversion.displayWeightIncrementOptions(for: .metric)
        )

        XCTAssertEqual(option.display, 2.5)
        XCTAssertEqual(option.storedKg, 2.5)
        XCTAssertEqual(
            UnitConversion.formatWeightIncrementLabel(
                storedKg: storedFivePounds,
                unitPreference: .metric,
                options: UnitConversion.displayWeightIncrementOptions(for: .metric)
            ),
            "2.5 kg"
        )
    }

    func testResolvedDefaultIncrementMatchesNudgeDisplayAfterUnitSwitches() {
        let imperialFromMetric = UnitConversion.resolvedWeightIncrementOption(
            exerciseIncrement: nil,
            defaultIncrement: 2.5,
            unitPreference: .imperial
        )
        let metricFromImperial = UnitConversion.resolvedWeightIncrementOption(
            exerciseIncrement: nil,
            defaultIncrement: UnitConversion.lbsToKg(5),
            unitPreference: .metric
        )

        XCTAssertEqual(imperialFromMetric.display, 5.0)
        XCTAssertEqual(imperialFromMetric.storedKg, UnitConversion.lbsToKg(5), accuracy: 0.0001)
        XCTAssertEqual(metricFromImperial.display, 2.5)
        XCTAssertEqual(metricFromImperial.storedKg, 2.5)
    }

    func testResolvedExerciseIncrementUsesExercisePickerPresetList() {
        let metricFromImperial = UnitConversion.resolvedWeightIncrementOption(
            exerciseIncrement: UnitConversion.lbsToKg(5),
            defaultIncrement: 10,
            unitPreference: .metric
        )

        XCTAssertEqual(metricFromImperial.display, 2.5)
        XCTAssertEqual(metricFromImperial.storedKg, 2.5)
    }

    func testResolvedExerciseIncrementPreservesSmallDumbbellOptions() {
        let oneKg = UnitConversion.resolvedWeightIncrementOption(
            exerciseIncrement: 1.0,
            defaultIncrement: 10,
            unitPreference: .metric
        )
        let twoKg = UnitConversion.resolvedWeightIncrementOption(
            exerciseIncrement: 2.0,
            defaultIncrement: 10,
            unitPreference: .metric
        )
        let twoLb = UnitConversion.resolvedWeightIncrementOption(
            exerciseIncrement: UnitConversion.lbsToKg(2.0),
            defaultIncrement: 10,
            unitPreference: .imperial
        )

        XCTAssertEqual(oneKg.display, 1.0)
        XCTAssertEqual(oneKg.storedKg, 1.0)
        XCTAssertEqual(twoKg.display, 2.0)
        XCTAssertEqual(twoKg.storedKg, 2.0)
        XCTAssertEqual(twoLb.display, 2.0)
        XCTAssertEqual(twoLb.storedKg, UnitConversion.lbsToKg(2.0), accuracy: 0.0001)
    }

    func testExerciseSettingsMetricWeightIncrementOptionsRestoreSheetSpecificList() {
        let options = ExerciseSettingsSheet.weightIncrementOptions(for: .metric)

        XCTAssertEqual(options.map(\.display), [1.0, 1.25, 2.0, 2.5, 5.0, 10.0, 20.0])
        XCTAssertEqual(options.map(\.storedKg), [1.0, 1.25, 2.0, 2.5, 5.0, 10.0, 20.0])
    }

    func testExerciseSettingsImperialWeightIncrementOptionsStayNativePounds() {
        let options = ExerciseSettingsSheet.weightIncrementOptions(for: .imperial)

        XCTAssertEqual(options.map(\.display), [1.0, 2.0, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0])
        XCTAssertEqual(options.map(\.storedKg), options.map { UnitConversion.lbsToKg($0.display) })
    }

    func testDistanceFormattingUsesUnitThresholds() {
        XCTAssertEqual(
            UnitConversion.formatDistanceLabel(999, unitPreference: .metric),
            "999 m"
        )
        XCTAssertEqual(
            UnitConversion.formatDistanceLabel(1_000, unitPreference: .metric),
            "1.00 km"
        )
        XCTAssertEqual(
            UnitConversion.formatDistanceLabel(400, unitPreference: .imperial),
            "1312 ft"
        )
        XCTAssertEqual(
            UnitConversion.formatDistanceLabel(UnitConversion.metersPerMile, unitPreference: .imperial),
            "1.00 mi"
        )
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

/// Pins the semantic predicates on `SetType`.
///
/// These replaced ten inline comparisons that disagreed with each other — a drop set counted
/// toward volume and PRs while vanishing from Copy Previous and the Home card. The predicates
/// only help if their membership is asserted rather than assumed, and every one of them is
/// consulted by the suggestion engine, so a silent membership change moves prescribed weight.
///
/// Exhaustive over `SetType.allCases` on purpose: adding a 14th case should fail here and force
/// a decision about which questions it answers, rather than silently defaulting to "no".
final class SetTypeSemanticPredicateTests: XCTestCase {

    func testCountsAsPerformedWorkExcludesOnlyWarmupAndPartial() {
        let expected: Set<SetType> = [
            .working, .dropset, .restpause, .cluster, .myo, .amrap,
            .backoff, .failure, .tempo, .isometric, .eccentric
        ]
        XCTAssertEqual(Set(SetType.allCases.filter(\.countsAsPerformedWork)), expected)
        XCTAssertFalse(SetType.warmup.countsAsPerformedWork)
        XCTAssertFalse(SetType.partial.countsAsPerformedWork)
    }

    func testIsStraightWorkingSetIsWorkingOnly() {
        XCTAssertEqual(Set(SetType.allCases.filter(\.isStraightWorkingSet)), [.working])
    }

    func testCapacityPointEstimateAcceptsOnlyMaximalSingleEffortSets() {
        XCTAssertEqual(
            Set(SetType.allCases.filter(\.isCapacityPointEstimate)),
            [.working, .amrap, .failure]
        )
    }

    /// AMRAP and failure are the *best* capacity evidence there is; excluding them would throw
    /// away the strongest signal the app receives.
    func testCapacityPointEstimateKeepsAmrapAndFailure() {
        XCTAssertTrue(SetType.amrap.isCapacityPointEstimate)
        XCTAssertTrue(SetType.failure.isCapacityPointEstimate)
    }

    /// Submaximal or fragmented efforts must never *set* the capability estimate — this is the
    /// membership that stops a drop set cratering the rest of the exercise.
    func testCapacityPointEstimateRejectsSubmaximalAndFragmentedTypes() {
        for type in [SetType.dropset, .backoff, .myo, .restpause, .cluster,
                     .tempo, .isometric, .eccentric, .warmup, .partial] {
            XCTAssertFalse(
                type.isCapacityPointEstimate,
                "\(type.rawValue) must not be treated as a capacity point estimate"
            )
        }
    }

    /// Wider than the point estimate on purpose: a back-off set at RIR 5 is a bad estimate of
    /// capacity and a perfectly good floor.
    func testCapacityLowerBoundIncludesBackoffButNotDropSets() {
        XCTAssertEqual(
            Set(SetType.allCases.filter(\.isCapacityLowerBound)),
            [.working, .backoff]
        )
        XCTAssertFalse(SetType.dropset.isCapacityLowerBound)
        XCTAssertFalse(SetType.partial.isCapacityLowerBound)
    }

    func testUserSelectableIsTheThreeTypesWithFeaturesBehindThem() {
        XCTAssertEqual(SetType.userSelectable, [.warmup, .working, .dropset])
    }

    /// The enum must keep every case: raw values are persisted in SwiftData, written to the JSON
    /// archive, and produced by both CSV importers. Narrowing the picker must never narrow this.
    func testEveryPersistedCaseStillExists() {
        XCTAssertEqual(SetType.allCases.count, 13)
        for raw in ["warmup", "working", "partial", "dropset", "restpause", "cluster", "myo",
                    "amrap", "backoff", "failure", "tempo", "isometric", "eccentric"] {
            XCTAssertNotNil(SetType(rawValue: raw), "\(raw) must still decode")
        }
    }

    /// Hidden types must still be representable, or an imported `failure` set would render as
    /// something it is not.
    func testHiddenTypesAreStillDisplayable() {
        for type in SetType.allCases where !SetType.userSelectable.contains(type) {
            XCTAssertFalse(type.displayName.isEmpty)
        }
    }
}
