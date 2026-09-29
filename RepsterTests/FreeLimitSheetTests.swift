import XCTest
@testable import Repster

/// The free-limit sheet's recap row (PAYWALL_BRIDGE_SCOPING.md §5). The gate routing in
/// `ContentView` has no harness, so these cover the part that decides what the user reads.
final class FreeLimitSheetTests: XCTestCase {
    func testNoHistoryHidesTheRecap() {
        XCTAssertNil(FreeLimitRecap(workouts: 0, sets: 0))
        XCTAssertNil(FreeLimitRecap(workouts: 0, sets: 12))
    }

    func testHistoryProducesARecap() {
        let recap = FreeLimitRecap(workouts: 12, sets: 184)
        XCTAssertEqual(recap?.workouts, 12)
        XCTAssertEqual(recap?.sets, 184)
    }

    /// Workouts with no chart-eligible sets still count; the sets tile is what drops out.
    func testZeroSetsKeepsTheRecapButClampsNegatives() {
        XCTAssertEqual(FreeLimitRecap(workouts: 3, sets: 0)?.sets, 0)
        XCTAssertEqual(FreeLimitRecap(workouts: 3, sets: -1)?.sets, 0)
    }

    func testLabelsAreSingularAtOne() {
        let one = FreeLimitRecap(workouts: 1, sets: 1)
        XCTAssertEqual(one?.workoutsLabel, "workout")
        XCTAssertEqual(one?.setsLabel, "set")

        let many = FreeLimitRecap(workouts: 10, sets: 40)
        XCTAssertEqual(many?.workoutsLabel, "workouts")
        XCTAssertEqual(many?.setsLabel, "sets")
    }

    /// An imported history can run to thousands of sets.
    func testValuesAreGroupedForTheLocale() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(FreeLimitRecap.value(184, locale: locale), "184")
        XCTAssertEqual(FreeLimitRecap.value(4210, locale: locale), "4,210")
    }
}
