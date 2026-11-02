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
        XCTAssertEqual(SidesCopy.verdictSubtitle(for: try exercise("1 Legged Hip Thrust", in: status)), "About 1 more rep so far, needs more sessions")

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
        XCTAssertEqual(SideStatus.possible(.left).sentence, "Left seems stronger — needs more sessions")
        XCTAssertEqual(SideStatus.even.sentence, "Even")
        XCTAssertEqual(SideStatus.collecting(sessions: 1).sentence, "Needs 2 more sessions")
        XCTAssertEqual(SideStatus.collecting(sessions: 2).sentence, "Needs 1 more session")
        XCTAssertEqual(SideStatus.notTracked(.notUnilateral).sentence, "Not tracked by side")
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

    // MARK: - Best set each session (D30)

    /// Medians are what the verdict runs on, but nobody lifted 8.5. The row under the chart has to
    /// be something the lifter can find in their own history.
    @MainActor
    func testEachSessionKeepsItsOwnBestSetAsLogged() async throws {
        let curl = unilateral("One Legged Leg Curl")
        try seed([curl])
        try history(curl.id, [
            [rir(8, left: 1, right: 2)],
            [Side(left: 9, right: 8, leftRIR: 0, rightRIR: 1), rir(6, left: 2, right: 2)],
        ])

        let summary = try exercise("One Legged Leg Curl", in: try await sides())
        XCTAssertEqual(summary.sessions.first?.bestSet?.left, 8, "oldest first")
        XCTAssertEqual(summary.sessions.first?.bestSet?.rightRIR, 2)
        XCTAssertEqual(summary.sessions.last?.bestSet?.left, 9)
        XCTAssertEqual(summary.sessions.last?.bestSet?.right, 8)
        XCTAssertEqual(summary.sessions.last?.left, 8.5, "the chart still plots the median")
    }

    /// The most reps in a session is usually the lightest set, which nobody calls their best.
    @MainActor
    func testASessionsBestSetIsTheHeaviestNotTheMostReps() async throws {
        let curl = unilateral("One Legged Leg Curl")
        try seed([curl])
        try session(curl.id, daysAgo: 3, [
            Side(left: 14, right: 14, leftRIR: 0, rightRIR: 0, weight: 15),
            Side(left: 6, right: 7, leftRIR: 1, rightRIR: 1, weight: 25),
            Side(left: 20, right: 20, leftRIR: 0, rightRIR: 0, weight: nil),
        ])

        let summary = try exercise("One Legged Leg Curl", in: try await sides())
        let best = try XCTUnwrap(summary.sessions.first?.bestSet)
        XCTAssertEqual(best.weight, 25)
        XCTAssertEqual(best.left, 6)
    }

    @MainActor
    func testAtOneWeightASessionsBestSetFollowsCapacity() async throws {
        let curl = unilateral("One Legged Leg Curl")
        try seed([curl])
        try session(curl.id, daysAgo: 3, [
            rir(6, left: 1, right: 1),
            rir(6, left: 3, right: 3),
            rir(7, left: 1, right: 1),
        ])

        let summary = try exercise("One Legged Leg Curl", in: try await sides())
        let best = try XCTUnwrap(summary.sessions.first?.bestSet)
        XCTAssertEqual(best.left, 6)
        XCTAssertEqual(best.leftRIR, 3)
    }

    /// The marker says what the comparison really did, so it has to follow `capacity` exactly: both
    /// sides or neither, and two "5+" sides compare on reps alone (D31).
    @MainActor
    func testRIRCoverageFollowsWhatTheComparisonCounted() async throws {
        let all = unilateral("All")
        let some = unilateral("Some")
        let none = unilateral("None")
        let oneSided = unilateral("One Sided")
        let censored = unilateral("Censored")
        try seed([all, some, none, oneSided, censored])
        try session(all.id, daysAgo: 3, [rir(8, left: 1, right: 2), rir(8, left: 1, right: 1)])
        try session(some.id, daysAgo: 3, [rir(8, left: 1, right: 2), Side(left: 8, right: 8)])
        try session(none.id, daysAgo: 3, [Side(left: 8, right: 8), Side(left: 9, right: 8)])
        try session(oneSided.id, daysAgo: 3, [Side(left: 8, right: 8, leftRIR: 1, rightRIR: nil)])
        try session(censored.id, daysAgo: 3, [Side(left: 8, right: 8, leftRIR: 5, rightRIR: 5)])

        let result = try await sides()
        XCTAssertEqual(try exercise("All", in: result).rirCoverage, .all)
        XCTAssertEqual(try exercise("Some", in: result).rirCoverage, .partial)
        XCTAssertEqual(try exercise("None", in: result).rirCoverage, .repsOnly)
        XCTAssertEqual(try exercise("One Sided", in: result).rirCoverage, .repsOnly)
        XCTAssertEqual(try exercise("Censored", in: result).rirCoverage, .repsOnly)
    }

    func testRIRWording() {
        XCTAssertEqual(SidesCopy.rirMarker(for: .all), "Reps + RIR")
        XCTAssertEqual(SidesCopy.rirMarker(for: .partial), "Reps + RIR where logged")
        XCTAssertEqual(SidesCopy.rirMarker(for: .repsOnly), "Reps only")
        XCTAssertEqual(SidesCopy.reserveText(0), "0 RIR")
        XCTAssertEqual(SidesCopy.reserveText(2), "2 RIR")
        XCTAssertEqual(SidesCopy.reserveText(1.5), "1.5 RIR")
        XCTAssertEqual(SidesCopy.reserveText(SidesAnalysis.censoredRIR), "5+ RIR")
    }

    // MARK: - Chart scale

    private func chartSessions(_ pairs: [(Double, Double)]) -> [SideSession] {
        pairs.map {
            SideSession(id: UUID(), date: reference, left: $0.0, right: $0.1, bestSet: nil, setCount: 1, rirSetCount: 0)
        }
    }

    func testAHalfRepGapDoesNotFillTheChart() {
        let scale = SideChartScale(sessions: chartSessions([(9, 9.5), (9.5, 10)]))
        XCTAssertEqual(scale.domain.upperBound - scale.domain.lowerBound, SideChartScale.minimumSpan, accuracy: 0.001)
        XCTAssertLessThan(scale.domain.lowerBound, 9)
        XCTAssertGreaterThan(scale.domain.upperBound, 10)
    }

    func testAWideGapWidensTheChartWithRoomAtBothEnds() {
        let scale = SideChartScale(sessions: chartSessions([(5, 15), (6, 14)]))
        XCTAssertLessThan(scale.domain.lowerBound, 5)
        XCTAssertGreaterThan(scale.domain.upperBound, 15)
    }

    func testTheScaleNeverGoesBelowZero() {
        let scale = SideChartScale(sessions: chartSessions([(1, 1), (1, 2)]))
        XCTAssertEqual(scale.domain.lowerBound, 0)
        XCTAssertGreaterThan(scale.domain.upperBound, 2)
    }

    func testGridlinesAreTwoWholeNumbersInsideTheChart() {
        for pairs in [[(8.0, 10.5), (9.0, 9.5)], [(10.0, 10.0)], [(9.2, 9.8)], [(20.0, 31.5)]] {
            let scale = SideChartScale(sessions: chartSessions(pairs))
            XCTAssertEqual(scale.ticks.count, 2)
            for tick in scale.ticks {
                XCTAssertEqual(tick, tick.rounded())
                XCTAssertTrue(scale.domain.contains(tick), "\(tick) outside \(scale.domain)")
            }
            XCTAssertLessThan(scale.ticks[0], scale.ticks[1])
        }
    }

    func testAHigherValueSitsHigherInThePlot() {
        let scale = SideChartScale(sessions: chartSessions([(8, 10)]))
        let plot = CGRect(x: 0, y: 10, width: 300, height: 128)
        XCTAssertLessThan(scale.y(10, in: plot), scale.y(8, in: plot))
        XCTAssertEqual(scale.y(scale.domain.upperBound, in: plot), plot.minY, accuracy: 0.001)
        XCTAssertEqual(scale.y(scale.domain.lowerBound, in: plot), plot.maxY, accuracy: 0.001)
    }

    func testEndLabelsOnlyMoveWhenTheyWouldOverlap() {
        let apart = SideChartScale.labelOffsets(leftY: 40, rightY: 90, leftOnTop: true)
        XCTAssertEqual(apart.left, 0)
        XCTAssertEqual(apart.right, 0)

        let close = SideChartScale.labelOffsets(leftY: 50, rightY: 45, leftOnTop: true)
        XCTAssertEqual(abs((50 + close.left) - (45 + close.right)), SideChartScale.minimumLabelGap, accuracy: 0.001)
        XCTAssertGreaterThan(close.left, 0, "right is higher, so left moves down")

        let tied = SideChartScale.labelOffsets(leftY: 50, rightY: 50, leftOnTop: false)
        XCTAssertGreaterThan(tied.left, 0)
        XCTAssertLessThan(tied.right, 0)
    }

    // MARK: - Best set at each weight (SIDES_DETAIL_REDESIGN_SCOPING.md §4)

    /// The row is a side-by-side comparison, so both halves must come from one set. Maxing the
    /// sides independently pairs the best left with a right it never trained beside — invisible
    /// while only reps showed, wrong the moment a reserve is printed next to each number.
    @MainActor
    func testBestSetComesFromOneSetNotTwoHalves() async throws {
        let curl = unilateral("One Legged Leg Curl")
        try seed([curl])
        try session(curl.id, daysAgo: 3, [
            Side(left: 7, right: 5, leftRIR: 0, rightRIR: 0),
            Side(left: 5, right: 8, leftRIR: 0, rightRIR: 0),
        ])

        let summary = try exercise("One Legged Leg Curl", in: try await sides())
        let row = try XCTUnwrap(summary.bestReps.first)
        XCTAssertEqual(row.left, 5)
        XCTAssertEqual(row.right, 8)
    }

    @MainActor
    func testBestSetTieBreaksOnRepsWhenCapacityMatches() async throws {
        let curl = unilateral("One Legged Leg Curl")
        try seed([curl])
        try session(curl.id, daysAgo: 3, [
            rir(6, left: 2, right: 2),
            rir(7, left: 1, right: 1),
        ])

        let summary = try exercise("One Legged Leg Curl", in: try await sides())
        let row = try XCTUnwrap(summary.bestReps.first)
        XCTAssertEqual(row.left, 7)
        XCTAssertEqual(row.leftRIR, 1)
    }

    @MainActor
    func testBestSetTieBreaksOnRecencyLast() async throws {
        let curl = unilateral("One Legged Leg Curl")
        try seed([curl])
        try session(curl.id, daysAgo: 17, [Side(left: 6, right: 6, leftRIR: 1, rightRIR: 2)])
        try session(curl.id, daysAgo: 3, [Side(left: 6, right: 6, leftRIR: 2, rightRIR: 1)])

        let summary = try exercise("One Legged Leg Curl", in: try await sides())
        let row = try XCTUnwrap(summary.bestReps.first)
        XCTAssertEqual(row.leftRIR, 2, "same capacity and same reps: the newer set wins")
        XCTAssertEqual(row.rightRIR, 1)
    }

    /// The case the old table drew as a tie: matched reps, different reserve.
    @MainActor
    func testBestSetCarriesBothReserves() async throws {
        let curl = unilateral("One Legged Leg Curl")
        try seed([curl])
        try history(curl.id, Array(repeating: [rir(6, left: 1, right: 2)], count: 6))

        let summary = try exercise("One Legged Leg Curl", in: try await sides())
        let row = try XCTUnwrap(summary.bestReps.first)
        XCTAssertEqual(row.left, 6)
        XCTAssertEqual(row.right, 6)
        XCTAssertEqual(row.leftRIR, 1)
        XCTAssertEqual(row.rightRIR, 2)
        XCTAssertEqual(summary.status, .stronger(.right, .clearly), "equal reps, and the verdict still lands")
    }

    @MainActor
    func testBestSetDropsReserveWhenOnlyOneSideHasIt() async throws {
        let curl = unilateral("One Legged Leg Curl")
        try seed([curl])
        try session(curl.id, daysAgo: 3, [Side(left: 6, right: 6, leftRIR: 1, rightRIR: nil)])

        let summary = try exercise("One Legged Leg Curl", in: try await sides())
        let row = try XCTUnwrap(summary.bestReps.first)
        XCTAssertNil(row.leftRIR, "a blank isn\u{2019}t failure, so neither side gets a reserve")
        XCTAssertNil(row.rightRIR)
        XCTAssertEqual(summary.rirOnOneSideSets, 1)
    }

    @MainActor
    func testCensoredReserveShowsItsFloorAndTwoOfThemShowNothing() async throws {
        let curl = unilateral("One Legged Leg Curl")
        let press = unilateral("One Legged Press")
        try seed([curl, press])
        try session(curl.id, daysAgo: 3, [Side(left: 6, right: 6, leftRIR: 5, rightRIR: 2)])
        try session(press.id, daysAgo: 3, [Side(left: 6, right: 6, leftRIR: 5, rightRIR: 5)])

        let result = try await sides()
        let oneCensored = try XCTUnwrap(try exercise("One Legged Leg Curl", in: result).bestReps.first)
        XCTAssertEqual(oneCensored.leftRIR, SidesAnalysis.censoredRIR)
        XCTAssertEqual(oneCensored.rightRIR, 2)

        let bothCensored = try XCTUnwrap(try exercise("One Legged Press", in: result).bestReps.first)
        XCTAssertNil(bothCensored.leftRIR, "two 5+ sides compare on reps alone, so no reserve is comparable")
        XCTAssertNil(bothCensored.rightRIR)
    }

    @MainActor
    func testBestSetRowsRunHeaviestFirstWithBodyweightLast() async throws {
        let pistol = unilateral("Pistol Squat", equipment: .bodyweight)
        try seed([pistol])
        try session(pistol.id, daysAgo: 3, [
            Side(left: 8, right: 8, leftRIR: 0, rightRIR: 0, weight: nil),
            Side(left: 5, right: 5, leftRIR: 0, rightRIR: 0, weight: 50),
            Side(left: 6, right: 6, leftRIR: 0, rightRIR: 0, weight: 30),
        ])

        let summary = try exercise("Pistol Squat", in: try await sides())
        XCTAssertEqual(summary.bestReps.map(\.weight), [50, 30, nil])
    }

    /// The "not tracked by side" list offers marking as an action, so it has to know which
    /// exercises marking would do nothing for.
    @MainActor
    func testCanTrackSidesFollowsTheTrackingType() async throws {
        let split = unilateral("Bulgarian Split Squat")
        let sled = Exercise(
            name: "Sled Push", equipmentType: .sled,
            trackingType: .weightDistance, primaryMuscle: "legs", unilateral: false
        )
        try seed([split, sled])
        try history(split.id, Array(repeating: [rir(8, left: 1, right: 2)], count: 3))
        try session(sled.id, daysAgo: 3, [Side(left: 10, right: 10, leftRIR: 0, rightRIR: 0)])

        let result = try await sides()
        XCTAssertTrue(try exercise("Bulgarian Split Squat", in: result).canTrackSides)
        XCTAssertFalse(
            try exercise("Sled Push", in: result).canTrackSides,
            "weight and distance logs no reps, so marking it Unilateral would change nothing"
        )
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
        XCTAssertEqual(legs.trackedExercises.map(\.name), ["Bulgarian Split Squat"])
    }

    @MainActor
    func testGroupsNothingTracksStayOffTheListAndHideTheTile() async throws {
        let bench = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps, primaryMuscle: "chest")
        try seed([bench])
        try session(bench.id, daysAgo: 2, [Side(left: nil, right: nil, weight: 80, reps: 8)])

        let status = try await sides()
        XCTAssertTrue(status.groups.isEmpty)
        XCTAssertEqual(status.untrackedExercises.map(\.name), ["Bench Press"])
        XCTAssertEqual(status.state, .hidden)
    }

    /// The line at the foot of the list counts across every group, including those nothing tracks.
    /// The analysis used to drop those exercises and keep only the group's name.
    @MainActor
    func testUntrackedExercisesComeFromEveryGroupInNameOrder() async throws {
        let split = unilateral("Bulgarian Split Squat")
        let squat = Exercise(name: "Barbell Back Squat", equipmentType: .barbell, trackingType: .weightReps, primaryMuscle: "legs")
        let bench = Exercise(name: "Bench Press", equipmentType: .barbell, trackingType: .weightReps, primaryMuscle: "chest")
        let pushdown = Exercise(name: "Arm Pushdown", equipmentType: .cable, trackingType: .weightReps, primaryMuscle: "triceps")
        try seed([split, squat, bench, pushdown])
        try history(split.id, Array(repeating: [Side(left: 8, right: 10, leftRIR: 0, rightRIR: 0)], count: 3))
        for exercise in [squat, bench, pushdown] {
            try session(exercise.id, daysAgo: 5, [Side(left: nil, right: nil, weight: 60, reps: 5)])
        }

        let status = try await sides()
        XCTAssertEqual(status.untrackedExercises.map(\.name), ["Arm Pushdown", "Barbell Back Squat", "Bench Press"])
        XCTAssertEqual(status.groups.map(\.id), ["legs"])
        XCTAssertEqual(SidesCopy.untrackedLine(count: 3), "3 other exercises aren\u{2019}t tracked by side")
        XCTAssertEqual(SidesCopy.untrackedLine(count: 1), "1 other exercise isn\u{2019}t tracked by side")
    }

    @MainActor
    func testAnExerciseIsFoundByIdForItsPage() async throws {
        let split = unilateral("Bulgarian Split Squat")
        try seed([split])
        try session(split.id, daysAgo: 3, [rir(8, left: 1, right: 1)])

        let status = try await sides()
        XCTAssertEqual(status.exercise(id: split.id)?.name, "Bulgarian Split Squat")
        XCTAssertNil(status.exercise(id: UUID()))
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
    func testAnEmptyStoreHidesTheTile() async throws {
        let result = try await sides()
        XCTAssertEqual(result.state, .hidden)
    }

    // MARK: - Tile (D25)

    private func group(_ name: String, _ status: SideGroupStatus) -> SideGroupSummary {
        SideGroupSummary(id: name.lowercased(), displayName: name, status: status, exercises: [])
    }

    private func tile(_ groups: SideGroupSummary...) -> (headline: String, subtitle: String) {
        let status = SidesStatus(groups: groups, untrackedExercises: [])
        return (SidesCopy.tileHeadline(for: status), SidesCopy.tileSubtitle(for: status))
    }

    func testTheTileNamesUpToTwoGroupsThenCounts() {
        let legs = group("Legs", .imbalance(exercises: 2))
        let shoulders = group("Shoulders", .imbalance(exercises: 1))
        let back = group("Back", .imbalance(exercises: 1))

        XCTAssertEqual(tile(legs).headline, "Imbalance in Legs")
        XCTAssertEqual(tile(legs, shoulders).headline, "Imbalances in Legs and Shoulders")
        XCTAssertEqual(tile(legs, shoulders, back).headline, "Imbalances in 3 muscle groups")
        XCTAssertEqual(tile(legs).subtitle, "Last \(SidesAnalysis.sessionsConsidered) sessions of each exercise")
    }

    func testTheTileNamesOnlyTheGroupsItIsTalkingAbout() {
        XCTAssertEqual(
            tile(group("Legs", .imbalance(exercises: 1)), group("Back", .possible(exercises: 1)), group("Biceps", .even)).headline,
            "Imbalance in Legs"
        )
    }

    func testTheTileSaysPossibleEvenAndBuildingPlainly() {
        let possible = tile(group("Legs", .possible(exercises: 1)), group("Biceps", .even))
        XCTAssertEqual(possible.headline, "Possible imbalance in Legs")
        XCTAssertEqual(possible.subtitle, "It needs a few more sessions to confirm")
        XCTAssertEqual(
            tile(group("Legs", .possible(exercises: 1)), group("Back", .possible(exercises: 2))).headline,
            "Possible imbalances in 2 muscle groups"
        )

        XCTAssertEqual(tile(group("Biceps", .even)).headline, "Both sides are even")

        let building = tile(group("Back", .collecting(sessions: 1)))
        XCTAssertEqual(building.headline, "Building your baseline")
        XCTAssertEqual(building.subtitle, "Each exercise needs \(SidesAnalysis.minSessions) sessions")
    }

    /// An unconfirmed lean gets no solid mark anywhere in the feature (D24).
    func testOnlyAnUnconfirmedClaimGetsADashedMark() {
        XCTAssertTrue(SidesTileMark(state: .possible).isDashed)
        XCTAssertFalse(SidesTileMark(state: .imbalanced).isDashed)
        XCTAssertTrue(SidesTileMark(status: .possible(.left)).isDashed)
        XCTAssertFalse(SidesTileMark(status: .stronger(.left, .slightly)).isDashed)
        XCTAssertFalse(SidesTileMark(status: .even).isDashed)

        XCTAssertEqual(SidesTileMark(status: .stronger(.right, .clearly)).glyph, .side(.right))
        XCTAssertEqual(SidesTileMark(status: .possible(.left)).glyph, .side(.left))
        XCTAssertEqual(SidesTileMark(status: .even).glyph, .equal)
        XCTAssertEqual(SidesTileMark(status: .collecting(sessions: 1)).glyph, .collecting)
    }

    // MARK: - Exercise verdict

    private func summary(
        _ status: SideStatus,
        gap: Double = 1.2,
        leadCount: Int = 0,
        differingCount: Int = 0
    ) -> SideExerciseSummary {
        SideExerciseSummary(
            id: UUID(), name: "Bulgarian Split Squat", status: status, sessions: [],
            averageGap: gap, leadCount: leadCount, differingCount: differingCount, bestReps: [],
            oneSideOnlySets: 0, rirOnOneSideSets: 0, canTrackSides: true
        )
    }

    func testTheVerdictReadsPlainlyInEveryState() {
        let stronger = summary(.stronger(.right, .clearly), leadCount: 5, differingCount: 5)
        XCTAssertEqual(SidesCopy.verdictTitle(for: stronger), "Right is clearly stronger")
        XCTAssertEqual(SidesCopy.verdictSubtitle(for: stronger), "About 1 more rep at the same weight")
        XCTAssertEqual(SidesCopy.leadLine(for: stronger), "RIGHT AHEAD IN 5")

        let possible = summary(.possible(.left), gap: -2.2, leadCount: 2, differingCount: 2)
        XCTAssertEqual(SidesCopy.verdictTitle(for: possible), "Left seems stronger")
        XCTAssertEqual(SidesCopy.verdictSubtitle(for: possible), "About 2 more reps so far, needs more sessions")
        XCTAssertEqual(SidesCopy.leadLine(for: possible), "LEFT AHEAD IN 2")

        let even = summary(.even, gap: 0.2, differingCount: 2)
        XCTAssertEqual(SidesCopy.verdictTitle(for: even), "Both sides are even")
        XCTAssertEqual(SidesCopy.verdictSubtitle(for: even), "Within a rep of each other, at the same weight")
        XCTAssertEqual(SidesCopy.leadLine(for: even), "NO CONSISTENT GAP")
        XCTAssertEqual(SidesCopy.leadLine(for: summary(.even, gap: 0)), "SIDES MATCHED")

        let collecting = summary(.collecting(sessions: 1), gap: 0)
        XCTAssertEqual(SidesCopy.verdictTitle(for: collecting), "Needs 2 more sessions")
        XCTAssertEqual(SidesCopy.verdictSubtitle(for: collecting), "With both sides logged")
        XCTAssertNil(SidesCopy.leadLine(for: collecting))
    }

    func testAGapUnderOneRepStillSaysAboutOne() {
        XCTAssertEqual(
            SidesCopy.verdictSubtitle(for: summary(.stronger(.left, .slightly), gap: -0.6)),
            "About 1 more rep at the same weight"
        )
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

    // These read the artwork itself, which compiles only under REPSTER_BODY_MAP (D32). Everything
    // around them uses the mapping, which holds none of it.
    #if REPSTER_BODY_MAP
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
    #endif

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
        XCTAssertEqual(AnalyticsEvent.sidesOpened.rawValue, "sides opened")
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
