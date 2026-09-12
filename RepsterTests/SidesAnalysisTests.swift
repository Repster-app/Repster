import XCTest
import SwiftData
import SwiftUI
@testable import Repster

/// The Sides feature: left against right on unilateral exercises.
/// Spec: UNILATERAL_IMBALANCE_EXPLORATION.md §5 (rules, D22), D21 (group vs exercise), D23 (acceptance).
final class SidesAnalysisTests: XCTestCase {

    private var container: ModelContainer!
    private let reference = Date(timeIntervalSince1970: 1_788_000_000)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Workout.self,
            WorkoutSet.self,
            Exercise.self,
            HealthProfile.self,
            FatigueObservation.self,
            InsightRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() {
        container = nil
    }

    // MARK: - Helpers

    /// One set. `reps` is only for bilateral exercises, which log a single count.
    private struct Side {
        var left: Int?
        var right: Int?
        var leftRIR: Double? = nil
        var rightRIR: Double? = nil
        var type: SetType = .working
        var weight: Double? = 20
        var reps: Int? = nil
    }

    /// Same reps both sides, RIR carries the difference.
    private func rir(_ reps: Int, left: Double, right: Double) -> Side {
        Side(left: reps, right: reps, leftRIR: left, rightRIR: right)
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: reference)!
    }

    private func unilateral(_ name: String, group: String = "legs", equipment: EquipmentType = .dumbbell) -> Exercise {
        Exercise(name: name, equipmentType: equipment, trackingType: .weightReps, primaryMuscle: group, unilateral: true)
    }

    @MainActor
    private func seed(_ models: [any PersistentModel]) throws {
        let context = ModelContext(container)
        for model in models {
            context.insert(model)
        }
        try context.save()
    }

    @MainActor
    private func session(_ exerciseId: UUID, daysAgo days: Int, _ sides: [Side], excludeWorkout: Bool = false) throws {
        let date = daysAgo(days)
        let workout = Workout(date: date, startTime: date, status: .completed)
        if excludeWorkout {
            workout.excludeFromProgressionHistory = true
        }
        let sets = sides.enumerated().map { index, side in
            WorkoutSet(
                workoutId: workout.id,
                exerciseId: exerciseId,
                date: date,
                weight: side.weight,
                effectiveWeight: side.weight,
                reps: side.reps ?? max(side.left ?? 0, side.right ?? 0),
                leftReps: side.left,
                rightReps: side.right,
                leftRIR: side.leftRIR,
                rightRIR: side.rightRIR,
                setType: side.type,
                orderInWorkout: index,
                orderInExercise: index,
                completed: true
            )
        }
        try seed([workout] + sets)
    }

    /// Sessions oldest first, one a week, the newest `newestDaysAgo` days before the reference.
    @MainActor
    private func history(_ exerciseId: UUID, newestDaysAgo: Int = 3, _ sessions: [[Side]]) throws {
        for (index, sets) in sessions.enumerated() {
            try session(exerciseId, daysAgo: newestDaysAgo + (sessions.count - 1 - index) * 7, sets)
        }
    }

    private func sides() async throws -> SidesStatus {
        try await InsightsService(modelContainer: container).sidesStatus(referenceDate: reference)
    }

    private func exercise(_ name: String, in status: SidesStatus) throws -> SideExerciseSummary {
        try XCTUnwrap(status.groups.flatMap(\.exercises).first { $0.name == name }, name)
    }

    // MARK: - Acceptance (D23)

    /// The maintainer's own pattern: same weight and reps, RIR carries the difference. The right
    /// quad is weaker on leg extension, the left hamstring weaker on leg curl — and both sit in
    /// "legs", leaning opposite ways. Both must show, each on its own exercise.
    @MainActor
    func testSameRepsDifferentRIRShowsTheWeakerSideOfEachExercise() async throws {
        let legExtension = unilateral("Leg Extension - 1 leg", equipment: .machinePin)
        let legCurl = unilateral("One Legged Leg Curl")
        try seed([legExtension, legCurl])
        // Right one rep closer to failure in four sessions, equal in two — equal ones mustn't count against it.
        try history(legExtension.id, [
            [rir(10, left: 1, right: 0)], [rir(10, left: 0, right: 0)], [rir(8, left: 1, right: 0)],
            [rir(12, left: 1, right: 1)], [rir(8, left: 2, right: 0)], [rir(9, left: 1, right: 0)],
        ])
        // Left closer to failure in all three sessions.
        try history(legCurl.id, newestDaysAgo: 4, [
            [rir(8, left: 1, right: 2)], [rir(10, left: 0, right: 1)], [rir(6, left: 0, right: 2)],
        ])

        let status = try await sides()

        XCTAssertEqual(try exercise("Leg Extension - 1 leg", in: status).status, .stronger(.left, .slightly))
        XCTAssertEqual(try exercise("One Legged Leg Curl", in: status).status, .stronger(.right, .clearly))
        XCTAssertEqual(try exercise("Leg Extension - 1 leg", in: status).status.sentence, "Left is slightly stronger")

        let legs = try XCTUnwrap(status.groups.first)
        XCTAssertEqual(legs.status, .imbalance(exercises: 2))
        XCTAssertEqual(legs.status.sentence, "Imbalance in 2 exercises")
        XCTAssertEqual(status.state, .imbalanced)
        XCTAssertEqual(SidesBodyFill.color(region: "quadriceps", statuses: [legs.id: legs.status]), .sidesImbalance)
    }

    /// The same imbalance logged the other way — different reps, both sides to failure — reads the same.
    @MainActor
    func testDifferentRepsShowTheSameImbalance() async throws {
        let legExtension = unilateral("Leg Extension - 1 leg", equipment: .machinePin)
        try seed([legExtension])
        try history(legExtension.id, Array(repeating: [Side(left: 10, right: 8, leftRIR: 0, rightRIR: 0)], count: 6))

        let status = try await sides()
        XCTAssertEqual(try exercise("Leg Extension - 1 leg", in: status).status, .stronger(.left, .clearly))
    }

    /// Evening out with matched reps: the gap shows up less often. Equal sessions pull the
    /// average down until it reads Even — within four sessions of it closing.
    @MainActor
    func testEvenOutWithMatchedRepsReachesEvenWithinFourSessions() async throws {
        let legExtension = unilateral("Leg Extension - 1 leg", equipment: .machinePin)
        try seed([legExtension])
        let behind = [rir(10, left: 1, right: 0)]
        let level = [rir(10, left: 1, right: 1)]
        try history(legExtension.id, newestDaysAgo: 10, [behind, behind, behind, behind, behind, behind, level, level, level])

        var status = try await sides()
        XCTAssertEqual(try exercise("Leg Extension - 1 leg", in: status).status, .stronger(.left, .slightly))

        try session(legExtension.id, daysAgo: 3, level)
        status = try await sides()
        XCTAssertEqual(try exercise("Leg Extension - 1 leg", in: status).status, .even)
        XCTAssertEqual(status.groups.first?.status, .even)
        XCTAssertEqual(status.state, .even)
    }

    /// Evening out with different reps: the gap gets smaller.
    @MainActor
    func testEvenOutWithDifferentRepsReachesEven() async throws {
        let split = unilateral("Bulgarian Split Squat")
        try seed([split])
        let gaps = [2, 2, 2, 1, 1, 0, 0]
        try history(split.id, newestDaysAgo: 17, gaps.map { [Side(left: 8, right: 8 + $0, leftRIR: 0, rightRIR: 0)] })

        var status = try await sides()
        XCTAssertEqual(try exercise("Bulgarian Split Squat", in: status).status.isStronger, true)

        try session(split.id, daysAgo: 10, [Side(left: 8, right: 8, leftRIR: 0, rightRIR: 0)])
        try session(split.id, daysAgo: 3, [Side(left: 8, right: 8, leftRIR: 0, rightRIR: 0)])
        status = try await sides()
        XCTAssertEqual(try exercise("Bulgarian Split Squat", in: status).status, .even)
    }

    /// A weak side that overtakes passes through Even rather than flipping in one step.
    @MainActor
    func testAFlipPassesThroughEven() async throws {
        let split = unilateral("Bulgarian Split Squat")
        try seed([split])
        let leftAhead = [Side(left: 10, right: 9, leftRIR: 0, rightRIR: 0)]
        let rightAhead = [Side(left: 9, right: 10, leftRIR: 0, rightRIR: 0)]
        try history(split.id, [leftAhead, leftAhead, leftAhead, leftAhead, rightAhead, rightAhead, rightAhead])

        let result = try await sides()
        XCTAssertEqual(try exercise("Bulgarian Split Squat", in: result).status, .even)
    }

    /// A lean on too few sessions to confirm says so rather than "Even" (D24): left ahead in two
    /// of three sessions, level in the third. A third session the same way confirms it.
    @MainActor
    func testAnUnconfirmedLeanSeemsStrongerUntilAThirdSessionConfirmsIt() async throws {
        let hipThrust = unilateral("1 Legged Hip Thrust")
        try seed([hipThrust])
        try history(hipThrust.id, newestDaysAgo: 10, [
            [Side(left: 11, right: 9, leftRIR: 0, rightRIR: 0)], [rir(9, left: 1, right: 0)], [rir(9, left: 1, right: 1)],
        ])

        var status = try await sides()
        XCTAssertEqual(try exercise("1 Legged Hip Thrust", in: status).status, .possible(.left))
        let legs = try XCTUnwrap(status.groups.first)
        XCTAssertEqual(legs.status, .possible(exercises: 1))
        XCTAssertEqual(status.state, .possible)
        XCTAssertEqual(SidesBodyFill.color(region: "gluteal", statuses: [legs.id: legs.status]), .sidesCollecting)
        XCTAssertEqual(SidesCopy.gapLine(for: try exercise("1 Legged Hip Thrust", in: status)), "About 1 more rep on your left so far, at the same weight")

        try session(hipThrust.id, daysAgo: 3, [rir(9, left: 1, right: 0)])
        status = try await sides()
        XCTAssertEqual(try exercise("1 Legged Hip Thrust", in: status).status, .stronger(.left, .slightly))
        XCTAssertEqual(status.groups.first?.status, .imbalance(exercises: 1))
    }

    /// A confirmed imbalance anywhere outranks a possible one on the card.
    @MainActor
    func testAConfirmedImbalanceOutranksAPossibleOne() async throws {
        let split = unilateral("Bulgarian Split Squat")
        let raise = unilateral("Cable Lateral Raise", group: "shoulders", equipment: .cable)
        try seed([split, raise])
        try history(split.id, Array(repeating: [Side(left: 8, right: 10, leftRIR: 0, rightRIR: 0)], count: 6))
        try history(raise.id, [[Side(left: 12, right: 10, leftRIR: 0, rightRIR: 0)], [rir(12, left: 1, right: 1)], [rir(12, left: 1, right: 1)]])

        let status = try await sides()
        XCTAssertEqual(status.state, .imbalanced)
        XCTAssertEqual(status.groups.map(\.status), [.imbalance(exercises: 1), .possible(exercises: 1)])
    }

    // MARK: - Rules

    func testCapacityAddsRIROnlyWhenBothSidesHaveIt() {
        let both = SidesAnalysis.capacity(leftReps: 8, rightReps: 8, leftRIR: 1, rightRIR: 3)
        XCTAssertEqual(both.left, 9)
        XCTAssertEqual(both.right, 11)

        // A blank isn't failure: RIR on one side only compares on reps.
        let oneSided = SidesAnalysis.capacity(leftReps: 8, rightReps: 10, leftRIR: nil, rightRIR: 2)
        XCTAssertEqual(oneSided.left, 8)
        XCTAssertEqual(oneSided.right, 10)
    }

    func testFivePlusIsAFloorAgainstAMeasuredSide() {
        // "5+" against 1: the direction is certain and 5 is the smallest the gap can be.
        let floor = SidesAnalysis.capacity(leftReps: 8, rightReps: 8, leftRIR: 5, rightRIR: 1)
        XCTAssertEqual(floor.left, 13)
        XCTAssertEqual(floor.right, 9)

        // Two "5+" sides: nothing to compare but reps.
        let both = SidesAnalysis.capacity(leftReps: 8, rightReps: 9, leftRIR: 5, rightRIR: 5)
        XCTAssertEqual(both.left, 8)
        XCTAssertEqual(both.right, 9)
    }

    func testDegreeIsRelativeToTheRepsInvolved() {
        XCTAssertEqual(SidesAnalysis.degree(gap: 1, meanCapacity: 10), .slightly)
        XCTAssertEqual(SidesAnalysis.degree(gap: 1.3, meanCapacity: 10), .clearly)
        XCTAssertEqual(SidesAnalysis.degree(gap: -2, meanCapacity: 9), .clearly)
        XCTAssertEqual(SidesAnalysis.degree(gap: 2.6, meanCapacity: 10), .much)
        XCTAssertEqual(SidesAnalysis.degree(gap: 1, meanCapacity: 6), .clearly)
        XCTAssertEqual(SidesAnalysis.degree(gap: 1, meanCapacity: 15), .slightly)
    }

    func testSentencesArePlainWords() {
        XCTAssertEqual(SideStatus.stronger(.right, .clearly).sentence, "Right is clearly stronger")
        XCTAssertEqual(SideStatus.possible(.left).sentence, "Left seems stronger — needs more sessions to confirm")
        XCTAssertEqual(SideStatus.even.sentence, "Even")
        XCTAssertEqual(SideGroupStatus.possible(exercises: 1).sentence, "Possible imbalance in 1 exercise")
        XCTAssertEqual(SideStatus.collecting(sessions: 1).sentence, "Needs 2 more sessions")
        XCTAssertEqual(SideStatus.collecting(sessions: 2).sentence, "Needs 1 more session")
        XCTAssertEqual(SideStatus.notTracked(.notUnilateral).sentence, "Not tracked by side")
        XCTAssertEqual(SideGroupStatus.imbalance(exercises: 1).sentence, "Imbalance in 1 exercise")
        XCTAssertEqual(SideGroupStatus.imbalance(exercises: 3).sentence, "Imbalance in 3 exercises")
    }

    @MainActor
    func testCollectingUntilThreeSessionsThenEvenNotCollecting() async throws {
        let split = unilateral("Bulgarian Split Squat")
        try seed([split])
        try history(split.id, newestDaysAgo: 10, [[rir(8, left: 1, right: 1)], [rir(8, left: 1, right: 1)]])

        var status = try await sides()
        XCTAssertEqual(try exercise("Bulgarian Split Squat", in: status).status, .collecting(sessions: 2))
        XCTAssertEqual(status.groups.first?.status, .collecting(sessions: 2))
        XCTAssertEqual(status.state, .building)

        try session(split.id, daysAgo: 3, [rir(8, left: 1, right: 1)])
        status = try await sides()
        XCTAssertEqual(try exercise("Bulgarian Split Squat", in: status).status, .even)
        XCTAssertEqual(status.state, .even)
    }

    @MainActor
    func testOnlyTheLastSixSessionsCount() async throws {
        let split = unilateral("Bulgarian Split Squat")
        try seed([split])
        let lopsided = [Side(left: 5, right: 12, leftRIR: 0, rightRIR: 0)]
        let level = [rir(10, left: 1, right: 1)]
        try history(split.id, [lopsided, lopsided, lopsided, lopsided, level, level, level, level, level, level])

        let summary = try exercise("Bulgarian Split Squat", in: try await sides())
        XCTAssertEqual(summary.status, .even)
        XCTAssertEqual(summary.sessions.count, 6)
    }

    @MainActor
    func testSessionsOlderThanTwelveWeeksAreIgnored() async throws {
        let split = unilateral("Bulgarian Split Squat")
        try seed([split])
        try history(split.id, newestDaysAgo: 90, Array(repeating: [Side(left: 5, right: 12, leftRIR: 0, rightRIR: 0)], count: 6))

        let result = try await sides()
        XCTAssertEqual(result.state, .hidden)
    }

    @MainActor
    func testOneSidedRowsAndOneSidedRIRAreCountedNotCompared() async throws {
        let split = unilateral("Bulgarian Split Squat")
        try seed([split])
        try history(split.id, newestDaysAgo: 10, Array(repeating: [rir(10, left: 1, right: 1)], count: 3))
        try session(split.id, daysAgo: 3, [
            Side(left: 12, right: nil),
            Side(left: 10, right: 10, leftRIR: 1, rightRIR: nil),
        ])

        let summary = try exercise("Bulgarian Split Squat", in: try await sides())
        XCTAssertEqual(summary.status, .even)
        XCTAssertEqual(summary.oneSideOnlySets, 1)
        XCTAssertEqual(summary.rirOnOneSideSets, 1)
    }

    @MainActor
    func testOnlyStraightWorkingEvidenceCounts() async throws {
        let split = unilateral("Bulgarian Split Squat")
        try seed([split])
        try history(split.id, Array(repeating: [
            Side(left: 10, right: 10, leftRIR: 1, rightRIR: 1),
            Side(left: 15, right: 5, type: .dropset),
            Side(left: 14, right: 6, type: .backoff),
            Side(left: 20, right: 2, type: .warmup),
        ], count: 6))

        let result = try await sides()
        XCTAssertEqual(try exercise("Bulgarian Split Squat", in: result).status, .even)
    }

    @MainActor
    func testExcludedWorkoutsAreIgnored() async throws {
        let split = unilateral("Bulgarian Split Squat")
        try seed([split])
        try history(split.id, Array(repeating: [rir(10, left: 1, right: 1)], count: 6))
        for week in 0..<6 {
            try session(split.id, daysAgo: 4 + week * 7, [Side(left: 5, right: 15, leftRIR: 0, rightRIR: 0)], excludeWorkout: true)
        }

        let result = try await sides()
        XCTAssertEqual(try exercise("Bulgarian Split Squat", in: result).status, .even)
    }

    @MainActor
    func testBodyweightUnilateralWorkStillCompares() async throws {
        let pistol = unilateral("Pistol Squat", equipment: .bodyweight)
        try seed([pistol])
        try history(pistol.id, Array(repeating: [Side(left: 6, right: 8, leftRIR: 0, rightRIR: 0, weight: nil)], count: 6))

        let summary = try exercise("Pistol Squat", in: try await sides())
        XCTAssertEqual(summary.status, .stronger(.right, .much))
        XCTAssertEqual(summary.bestReps.count, 1)
        XCTAssertNil(summary.bestReps[0].weight)
    }

    // MARK: - Groups (D21)

    /// Opposite directions in one group are just two imbalances — no "mixed" state.
    @MainActor
    func testExercisesLeaningOppositeWaysAreBothImbalances() async throws {
        let curl = unilateral("Dumbbell Curl", group: "biceps")
        let hammer = unilateral("Hammer Curl", group: "biceps")
        try seed([curl, hammer])
        try history(curl.id, Array(repeating: [Side(left: 12, right: 9, leftRIR: 0, rightRIR: 0)], count: 6))
        try history(hammer.id, newestDaysAgo: 4, Array(repeating: [Side(left: 9, right: 12, leftRIR: 0, rightRIR: 0)], count: 6))

        let result = try await sides()
        let biceps = try XCTUnwrap(result.groups.first)
        XCTAssertEqual(biceps.status, .imbalance(exercises: 2))
        XCTAssertEqual(Set(biceps.exercises.map(\.status)), [.stronger(.left, .much), .stronger(.right, .much)])
    }

    @MainActor
    func testExercisesNotMarkedUnilateralAreListedLastAsNotTracked() async throws {
        let split = unilateral("Bulgarian Split Squat")
        let squat = Exercise(name: "Barbell Back Squat", equipmentType: .barbell, trackingType: .weightReps, primaryMuscle: "legs")
        try seed([split, squat])
        try history(split.id, Array(repeating: [Side(left: 8, right: 10, leftRIR: 0, rightRIR: 0)], count: 6))
        try session(squat.id, daysAgo: 5, [Side(left: nil, right: nil, weight: 100, reps: 5)])

        let result = try await sides()
        let legs = try XCTUnwrap(result.groups.first)
        XCTAssertEqual(legs.exercises.map(\.name), ["Bulgarian Split Squat", "Barbell Back Squat"])
        XCTAssertEqual(legs.exercises.last?.status, .notTracked(.notUnilateral))
        XCTAssertEqual(legs.trackedExerciseCount, 1)
    }

    @MainActor
    func testGroupsNothingTracksFeedTheCoverageNoteAndHideTheCard() async throws {
        let bench = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps, primaryMuscle: "chest")
        try seed([bench])
        try session(bench.id, daysAgo: 2, [Side(left: nil, right: nil, weight: 80, reps: 8)])

        let status = try await sides()
        XCTAssertTrue(status.groups.isEmpty)
        XCTAssertEqual(status.untrackedGroupNames, ["Chest"])
        XCTAssertEqual(status.state, .hidden)
    }

    @MainActor
    func testImbalancedGroupsSortAheadOfEvenAndCollecting() async throws {
        let split = unilateral("Bulgarian Split Squat")
        let raise = unilateral("Cable Lateral Raise", group: "shoulders", equipment: .cable)
        let row = unilateral("Dumbbell Row", group: "back")
        try seed([split, raise, row])
        try history(row.id, Array(repeating: [rir(9, left: 1, right: 1)], count: 2))
        try history(raise.id, Array(repeating: [rir(12, left: 1, right: 1)], count: 6))
        try history(split.id, Array(repeating: [Side(left: 8, right: 10, leftRIR: 0, rightRIR: 0)], count: 6))

        let result = try await sides()
        XCTAssertEqual(result.groups.map(\.id), ["legs", "shoulders", "back"])
    }

    @MainActor
    func testAnEmptyStoreHidesTheCard() async throws {
        let result = try await sides()
        XCTAssertEqual(result.state, .hidden)
    }

    // MARK: - Body map

    func testTheFrontViewMirrorsAndTheBackViewDoesNot() {
        XCTAssertEqual(BodyMapGeometry.librarySide(for: .left, in: .front), "right")
        XCTAssertEqual(BodyMapGeometry.librarySide(for: .right, in: .front), "left")
        XCTAssertEqual(BodyMapGeometry.librarySide(for: .left, in: .back), "left")
        XCTAssertEqual(BodyMapGeometry.librarySide(for: .right, in: .back), "right")

        for view in [BodyView.front, .back] {
            for side in [SideLean.left, .right] {
                let library = BodyMapGeometry.librarySide(for: side, in: view)
                XCTAssertEqual(BodyMapGeometry.anatomicalSide(forLibrarySide: library, in: view), side)
            }
        }
        XCTAssertNil(BodyMapGeometry.anatomicalSide(forLibrarySide: "common", in: .front))
    }

    /// The mirror trap, checked against the artwork itself rather than the mapping table.
    func testTheFiguresLeftArmIsOnTheViewersRightInTheFrontViewOnly() throws {
        func midX(_ geometry: BodyMapGeometry, _ region: String, _ side: SideLean) throws -> CGFloat {
            try XCTUnwrap(geometry.regions.first { $0.region == region && $0.side == side }).path.boundingRect.midX
        }
        XCTAssertGreaterThan(try midX(.front, "biceps", .left), try midX(.front, "biceps", .right))
        XCTAssertLessThan(try midX(.back, "triceps", .left), try midX(.back, "triceps", .right))
    }

    func testEveryGeneratedPathParsesInsideItsViewBox() {
        for geometry in [BodyMapGeometry.front, BodyMapGeometry.back] {
            XCTAssertFalse(geometry.regions.isEmpty)
            let box = geometry.viewBox.insetBy(dx: -1, dy: -1)
            for region in geometry.regions {
                let rect = region.path.boundingRect
                XCTAssertFalse(rect.isEmpty, region.region)
                XCTAssertTrue(box.contains(rect), "\(region.region) spills outside the view box")
            }
            XCTAssertTrue(box.contains(geometry.outline.boundingRect))
        }
    }

    func testEveryMuscleRegionCanShowAGroup() {
        for geometry in [BodyMapGeometry.front, BodyMapGeometry.back] {
            for region in Set(geometry.regions.map(\.region)) where !BodyMapGeometry.nonMuscleRegions.contains(region) {
                XCTAssertNotNil(BodyMapGeometry.regionGroups[region], region)
            }
        }
    }

    /// The map says where, never which side (D21).
    func testFillsShowWhereNotWhichSide() {
        let statuses: [String: SideGroupStatus] = [
            "legs": .imbalance(exercises: 2), "back": .even, "biceps": .collecting(sessions: 2),
        ]
        XCTAssertEqual(SidesBodyFill.color(region: "quadriceps", statuses: statuses), .sidesImbalance)
        XCTAssertEqual(SidesBodyFill.color(region: "hamstring", statuses: statuses), .sidesImbalance)
        XCTAssertEqual(SidesBodyFill.color(region: "upper-back", statuses: statuses), .sidesEven)
        XCTAssertEqual(SidesBodyFill.color(region: "biceps", statuses: statuses), .sidesCollecting)
        XCTAssertEqual(SidesBodyFill.color(region: "chest", statuses: statuses), .bodyBase)
        XCTAssertEqual(SidesBodyFill.color(region: "quadriceps", statuses: statuses, only: "biceps"), .bodyBase)
    }

    // MARK: - Analytics

    func testSidesEventsHaveStableNames() {
        XCTAssertEqual(AnalyticsEvent.sidesGroupOpened.rawValue, "sides group opened")
        XCTAssertEqual(AnalyticsEvent.sidesExerciseOpened.rawValue, "sides exercise opened")
        XCTAssertEqual(AnalyticsPropertyKey.sidesState.rawValue, "sides_state")
        XCTAssertEqual(SidesCardState.imbalanced.rawValue, "imbalanced")
        XCTAssertEqual(SidesCardState.possible.rawValue, "possible")
        XCTAssertEqual(SideStatus.possible(.right).analyticsValue, "possible")
        XCTAssertEqual(SideGroupStatus.possible(exercises: 1).analyticsValue, "possible")
        XCTAssertEqual(SideGroupStatus.imbalance(exercises: 2).analyticsValue, "imbalance")
        XCTAssertEqual(SideStatus.stronger(.left, .slightly).analyticsValue, "stronger")
    }
}
