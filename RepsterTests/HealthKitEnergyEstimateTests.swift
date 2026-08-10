import XCTest
@testable import Repster

/// Pins the MET-based energy estimate written to Apple Health.
///
/// The behaviour these cover is a product decision, not an implementation detail:
/// a fabricated calorie figure reaches the user's Move ring and any nutrition app
/// reading "calories out", so "no bodyweight" must yield no estimate rather than a
/// substituted average. See HEALTHKIT_INTEGRATION_EXPLORATION.md.
final class HealthKitEnergyEstimateTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func end(afterMinutes minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    // MARK: - The estimate itself

    func testEstimateUsesMET3Point5TimesBodyweightTimesHours() {
        let kcal = HealthKitService.estimatedKilocalories(
            bodyweightKg: 80,
            start: start,
            end: end(afterMinutes: 60)
        )

        // 3.5 MET x 80 kg x 1.0 h
        XCTAssertEqual(try XCTUnwrap(kcal), 280, accuracy: 0.001)
    }

    func testEstimateScalesWithDuration() {
        let half = HealthKitService.estimatedKilocalories(
            bodyweightKg: 80,
            start: start,
            end: end(afterMinutes: 30)
        )

        XCTAssertEqual(try XCTUnwrap(half), 140, accuracy: 0.001)
    }

    func testEstimateScalesWithBodyweight() {
        let lighter = try? XCTUnwrap(
            HealthKitService.estimatedKilocalories(bodyweightKg: 60, start: start, end: end(afterMinutes: 60))
        )
        let heavier = try? XCTUnwrap(
            HealthKitService.estimatedKilocalories(bodyweightKg: 120, start: start, end: end(afterMinutes: 60))
        )

        XCTAssertEqual(try XCTUnwrap(lighter), 210, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(heavier), 420, accuracy: 0.001)
    }

    // MARK: - No bodyweight means no estimate, never a substituted average

    func testNoBodyweightYieldsNoEstimate() {
        XCTAssertNil(HealthKitService.estimatedKilocalories(
            bodyweightKg: nil,
            start: start,
            end: end(afterMinutes: 60)
        ))
    }

    func testNonPositiveBodyweightYieldsNoEstimate() {
        XCTAssertNil(HealthKitService.estimatedKilocalories(
            bodyweightKg: 0,
            start: start,
            end: end(afterMinutes: 60)
        ))
        XCTAssertNil(HealthKitService.estimatedKilocalories(
            bodyweightKg: -70,
            start: start,
            end: end(afterMinutes: 60)
        ))
    }

    // MARK: - Degenerate durations

    func testZeroLengthWorkoutYieldsNoEstimate() {
        XCTAssertNil(HealthKitService.estimatedKilocalories(
            bodyweightKg: 80,
            start: start,
            end: start
        ))
    }

    func testEndBeforeStartYieldsNoEstimate() {
        XCTAssertNil(HealthKitService.estimatedKilocalories(
            bodyweightKg: 80,
            start: start,
            end: start.addingTimeInterval(-3600)
        ))
    }
}
