// BaselineMeterGeometryTests.swift
// The meter has to stay proportional across the whole ratio range.
//
// The version this replaces anchored the baseline tick at a fixed 74% and
// clamped the fill to the track, so every week past ~1.35x baseline drew
// identically — the failure only appeared at ratios nobody had looked at.

import XCTest
@testable import Repster

final class BaselineMeterGeometryTests: XCTestCase {

    // MARK: - The fill stays honest

    func testFillNeverReachesTheEdge() {
        // Ratios spanning far below to far above the user's norm.
        let cases: [(current: Int, baseline: Double)] = [
            (0, 12), (2, 12), (5, 12), (12, 12), (17, 12), (24, 12), (24, 6), (60, 5),
        ]

        for (current, baseline) in cases {
            let geometry = BaselineMeterGeometry(current: current, baseline: baseline)
            XCTAssertLessThan(
                geometry.fillFraction, 1.0,
                "fill pinned at \(current) vs \(baseline)"
            )
            XCTAssertLessThan(
                geometry.tickFraction, 1.0,
                "tick pinned at \(current) vs \(baseline)"
            )
        }
    }

    /// The specific regression: two different weeks well above baseline used to
    /// render the same because both clamped.
    func testWeeksAboveBaselineStayDistinguishable() {
        let seventeen = BaselineMeterGeometry(current: 17, baseline: 12)
        let twentyFour = BaselineMeterGeometry(current: 24, baseline: 12)

        XCTAssertGreaterThan(twentyFour.fillFraction, seventeen.fillFraction)
    }

    func testFillIsProportionalToTheTick() {
        // 24 sets against a baseline of 12 should draw exactly twice the tick.
        let geometry = BaselineMeterGeometry(current: 24, baseline: 12)
        XCTAssertEqual(geometry.fillFraction, geometry.tickFraction * 2, accuracy: 0.0001)
    }

    func testMatchingWeekAndBaselineLandTogether() {
        let geometry = BaselineMeterGeometry(current: 12, baseline: 12)
        XCTAssertEqual(geometry.fillFraction, geometry.tickFraction, accuracy: 0.0001)
    }

    // MARK: - The tick moves with the data

    func testTickSitsHighWhenTheWeekIsLight() {
        // A light week leaves the baseline out near the end of the track.
        let geometry = BaselineMeterGeometry(current: 5, baseline: 12)
        XCTAssertEqual(geometry.tickFraction, 1 / BaselineMeterGeometry.headroom, accuracy: 0.0001)
        XCTAssertLessThan(geometry.fillFraction, geometry.tickFraction)
    }

    func testTickSitsLowWhenTheWeekIsHeavy() {
        // 24 vs 12: the week sets the scale, so the tick lands near the middle.
        let geometry = BaselineMeterGeometry(current: 24, baseline: 12)
        XCTAssertEqual(geometry.tickFraction, 0.446, accuracy: 0.005)
    }

    // MARK: - Degenerate input

    func testNothingLoggedStillPlacesTheTick() {
        let geometry = BaselineMeterGeometry(current: 0, baseline: 12)
        XCTAssertEqual(geometry.fillFraction, 0)
        XCTAssertGreaterThan(geometry.tickFraction, 0)
    }

    func testZeroBaselineDoesNotDivideByZero() {
        let geometry = BaselineMeterGeometry(current: 0, baseline: 0)
        XCTAssertEqual(geometry.fillFraction, 0)
        XCTAssertEqual(geometry.tickFraction, 0)
    }

    // MARK: - Caption stays inside the track

    func testCaptionIsClampedAtBothEnds() {
        let width: CGFloat = 300
        let captionWidth = BaselineMeterGeometry.captionWidth

        // Tick near the right edge (very light week) and near the left edge
        // (very heavy week) are the two cases that could push it out of bounds.
        for (current, baseline) in [(1, 40.0), (60, 5.0), (0, 12.0), (12, 12.0)] {
            let offset = BaselineMeterGeometry(current: current, baseline: baseline)
                .captionOffset(width: width)
            XCTAssertGreaterThanOrEqual(offset, 0, "caption clipped left at \(current)/\(baseline)")
            XCTAssertLessThanOrEqual(
                offset, width - captionWidth,
                "caption clipped right at \(current)/\(baseline)"
            )
        }
    }

    func testCaptionCentresOnTheTickWhenThereIsRoom() {
        let width: CGFloat = 300
        let geometry = BaselineMeterGeometry(current: 24, baseline: 12)
        let expected = width * geometry.tickFraction - BaselineMeterGeometry.captionWidth / 2

        XCTAssertEqual(geometry.captionOffset(width: width), expected, accuracy: 0.01)
    }
}
