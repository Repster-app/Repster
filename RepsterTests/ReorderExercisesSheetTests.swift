import XCTest
@testable import Repster

/// The run → exercise translation behind the reorder sheet.
///
/// The sheet's rows are `SupersetGrouping.Run`s, not exercises, so every drag has to be converted
/// into the exercise move it stands for before it reaches `reorderExercises(from:to:)`. That
/// conversion is the only new logic in the feature and the only place a superset could be split,
/// so it is asserted against the array move it produces rather than against its own arithmetic —
/// the offsets are only correct if `move(fromOffsets:toOffset:)` agrees.
final class ReorderExercisesSheetTests: XCTestCase {

    // MARK: - Ungrouped

    func testMovingASingleExerciseBackward() {
        let (runs, names) = fixture()   // [A] [B] [C+D] [E]

        XCTAssertEqual(apply(runMove: 3, to: 0, runs: runs, names: names),
                       ["E", "A", "B", "C", "D"],
                       "the last run lands at the front")
    }

    func testMovingASingleExerciseForward() {
        let (runs, names) = fixture()

        XCTAssertEqual(apply(runMove: 0, to: 2, runs: runs, names: names),
                       ["B", "A", "C", "D", "E"],
                       "dropped before the superset, so it sits second")
    }

    func testMovingPastTheLastRun() {
        let (runs, names) = fixture()

        XCTAssertEqual(apply(runMove: 0, to: 4, runs: runs, names: names),
                       ["B", "C", "D", "E", "A"],
                       "a drop past the end maps to the end of the exercise array, not past it")
    }

    // MARK: - Supersets

    /// The point of drawing a group as one row: it has to travel as one.
    func testMovingASupersetCarriesBothMembers() {
        let (runs, names) = fixture()

        XCTAssertEqual(apply(runMove: 2, to: 0, runs: runs, names: names),
                       ["C", "D", "A", "B", "E"],
                       "both members move, and they stay adjacent and in order")
    }

    func testMovingASupersetToTheEnd() {
        let (runs, names) = fixture()

        XCTAssertEqual(apply(runMove: 2, to: 4, runs: runs, names: names),
                       ["A", "B", "E", "C", "D"],
                       "the pair steps over E together")
    }

    func testASupersetIsMovedAsAContiguousBlock() {
        let (runs, _) = fixture()

        let move = SupersetGrouping.exerciseMove(forRunMove: IndexSet(integer: 2), to: 0, in: runs)

        XCTAssertEqual(move?.source, IndexSet(integersIn: 2..<4),
                       "the source spans every exercise in the run, so nothing is left behind")
        XCTAssertEqual(move?.destination, 0)
    }

    /// A non-contiguous group breaks into single-exercise runs, which are not marked and are not
    /// moved as a unit — the sheet must not invent a block that the strip does not draw.
    func testANonContiguousGroupMovesOneExerciseAtATime() {
        let group = UUID()
        let exercises = ["A", "B", "C"].map(exercise(named:))
        let runs = SupersetGrouping.runs(
            exercises: exercises,
            setsByExercise: [
                exercises[0].id: [set(exercises[0].id, group: group)],
                exercises[1].id: [set(exercises[1].id, group: nil)],
                exercises[2].id: [set(exercises[2].id, group: group)]
            ]
        )

        XCTAssertEqual(runs.count, 3, "the split group is three runs, not two")
        XCTAssertFalse(runs.contains(where: \.isMarked))

        let move = SupersetGrouping.exerciseMove(forRunMove: IndexSet(integer: 2), to: 0, in: runs)
        XCTAssertEqual(move?.source, IndexSet(integer: 2), "one exercise, not a phantom pair")
    }

    // MARK: - Moves that must not reach the store

    func testDroppingARunOnItselfIsRejected() {
        let (runs, _) = fixture()

        XCTAssertNil(SupersetGrouping.exerciseMove(forRunMove: IndexSet(integer: 1), to: 1, in: runs))
    }

    /// `List` reports a drop just below a row as `destination == index + 1`. It changes nothing,
    /// and letting it through would renumber every set in the workout and write for no reason.
    func testDroppingARunImmediatelyAfterItselfIsRejected() {
        let (runs, _) = fixture()

        XCTAssertNil(SupersetGrouping.exerciseMove(forRunMove: IndexSet(integer: 1), to: 2, in: runs))
        XCTAssertNil(SupersetGrouping.exerciseMove(forRunMove: IndexSet(integer: 2), to: 3, in: runs),
                     "including for a superset, where 'immediately after' is two exercises along")
    }

    func testAMultiRowMoveIsRejected() {
        let (runs, _) = fixture()

        XCTAssertNil(
            SupersetGrouping.exerciseMove(forRunMove: IndexSet([0, 1]), to: 3, in: runs),
            "a two-row move is not something the sheet can express — guessing would split a group"
        )
    }

    func testOutOfRangeIndicesAreRejected() {
        let (runs, _) = fixture()

        XCTAssertNil(SupersetGrouping.exerciseMove(forRunMove: IndexSet(integer: 9), to: 0, in: runs))
        XCTAssertNil(SupersetGrouping.exerciseMove(forRunMove: IndexSet(integer: 0), to: 9, in: runs))
        XCTAssertNil(SupersetGrouping.exerciseMove(forRunMove: IndexSet(), to: 0, in: runs))
    }

    func testAnEmptyWorkoutHasNoMoves() {
        XCTAssertNil(SupersetGrouping.exerciseMove(forRunMove: IndexSet(integer: 0), to: 0, in: []))
    }

    // MARK: - Fixtures

    /// Exercises A B C D E where C and D are one superset — so four runs, one of them marked.
    private func fixture() -> (runs: [SupersetGrouping.Run], names: [String]) {
        let group = UUID()
        let names = ["A", "B", "C", "D", "E"]
        let exercises = names.map(exercise(named:))
        let groups: [UUID?] = [nil, nil, group, group, nil]
        let sets = Dictionary(uniqueKeysWithValues: zip(exercises, groups).map { exercise, group in
            (exercise.id, [set(exercise.id, group: group)])
        })

        let runs = SupersetGrouping.runs(exercises: exercises, setsByExercise: sets)
        XCTAssertEqual(runs.count, 4, "fixture is [A] [B] [C+D] [E]")
        XCTAssertTrue(runs[2].isMarked)

        return (runs, names)
    }

    /// Run the translated move through the same array operation `reorderExercises` performs, and
    /// report the resulting order by name.
    private func apply(
        runMove source: Int,
        to destination: Int,
        runs: [SupersetGrouping.Run],
        names: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [String] {
        guard let move = SupersetGrouping.exerciseMove(
            forRunMove: IndexSet(integer: source),
            to: destination,
            in: runs
        ) else {
            XCTFail("expected run \(source) → \(destination) to be a real move", file: file, line: line)
            return []
        }

        var order = names
        order.move(fromOffsets: move.source, toOffset: move.destination)
        return order
    }

    /// `ChartExerciseData.id` is a `let` seeded from the `Exercise`, so identity comes out of the
    /// built value rather than being assigned to it.
    private func exercise(named name: String) -> ChartExerciseData {
        ChartExerciseData(
            from: Exercise(name: name, equipmentType: .barbell, trackingType: .weightReps)
        )
    }

    private func set(_ exerciseId: UUID, group: UUID?) -> WorkoutSet {
        WorkoutSet(
            workoutId: UUID(),
            exerciseId: exerciseId,
            setType: .working,
            orderInWorkout: 1,
            orderInExercise: 1,
            supersetGroupId: group,
            completed: false
        )
    }
}
