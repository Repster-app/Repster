// BaselineMeterGeometryTests.swift
// The week-vs-usual comparison and the muscle rows have to stay proportional
// across the whole ratio range.
//
// Two generations of bug live behind these tests. The first anchored the
// baseline tick at a fixed 74% and clamped the fill, so every week past ~1.35x
// drew identically. The second scaled the muscle rows to one shared maximum, so
// a leg-focused week drew legs at the full track and every other group as a
// stub — the panel went blank exactly when it had something to say.

import XCTest
@testable import Repster

final class WeekComparisonGeometryTests: XCTestCase {

    // MARK: - Both bars stay honest

    func testTheLargerBarFillsTheTrack() {
        // Whichever side is bigger sets the scale, in both directions.
        let heavy = WeekComparisonGeometry(current: 39, usual: 16)
        XCTAssertEqual(heavy.currentFraction, 1.0, accuracy: 0.0001)
        XCTAssertLessThan(heavy.usualFraction, 1.0)

        let light = WeekComparisonGeometry(current: 5, usual: 12)
        XCTAssertEqual(light.usualFraction, 1.0, accuracy: 0.0001)
        XCTAssertLessThan(light.currentFraction, 1.0)
    }

    func testBarsAreProportionalToEachOther() {
        // 24 against a usual of 12 draws exactly twice the usual bar.
        let geometry = WeekComparisonGeometry(current: 24, usual: 12)
        XCTAssertEqual(geometry.currentFraction, geometry.usualFraction * 2, accuracy: 0.0001)
    }

    func testMatchingWeekAndUsualDrawTheSame() {
        let geometry = WeekComparisonGeometry(current: 12, usual: 12)
        XCTAssertEqual(geometry.currentFraction, geometry.usualFraction, accuracy: 0.0001)
    }

    /// The original regression, restated: two different heavy weeks must not
    /// render identically. Both fill the track now, so the difference has to
    /// show up in how far short of it the usual bar stops.
    func testWeeksAboveUsualStayDistinguishable() {
        let seventeen = WeekComparisonGeometry(current: 17, usual: 12)
        let twentyFour = WeekComparisonGeometry(current: 24, usual: 12)
        XCTAssertLessThan(twentyFour.usualFraction, seventeen.usualFraction)
    }

    // MARK: - Degenerate input

    func testNothingLoggedStillDrawsTheUsualBar() {
        let geometry = WeekComparisonGeometry(current: 0, usual: 12)
        XCTAssertEqual(geometry.currentFraction, 0)
        XCTAssertEqual(geometry.usualFraction, 1.0, accuracy: 0.0001)
    }

    func testZeroUsualDoesNotDivideByZero() {
        let geometry = WeekComparisonGeometry(current: 0, usual: 0)
        XCTAssertEqual(geometry.currentFraction, 0)
        XCTAssertEqual(geometry.usualFraction, 0)
    }

    // MARK: - The relation in words

    func testLargeGapsReadAsMultiples() {
        XCTAssertEqual(
            WeekComparisonGeometry.relationText(current: 39, usual: 16),
            "2.4\u{00D7} your usual"
        )
    }

    func testWholeMultiplesDropTheDecimal() {
        XCTAssertEqual(
            WeekComparisonGeometry.relationText(current: 24, usual: 12),
            "2\u{00D7} your usual"
        )
    }

    func testModerateGapsReadAsPercentages() {
        XCTAssertEqual(
            WeekComparisonGeometry.relationText(current: 15, usual: 12),
            "25% above your usual"
        )
        XCTAssertEqual(
            WeekComparisonGeometry.relationText(current: 9, usual: 12),
            "25% below your usual"
        )
    }

    func testSmallGapsReadAsUnremarkable() {
        XCTAssertEqual(
            WeekComparisonGeometry.relationText(current: 12, usual: 12.3),
            "about your usual"
        )
    }

    func testAnEmptyWeekSaysSoRatherThanReadingAsMinusOneHundredPercent() {
        XCTAssertEqual(
            WeekComparisonGeometry.relationText(current: 0, usual: 12),
            "nothing logged this week"
        )
    }

    func testNoUsualMeansNoRelation() {
        XCTAssertNil(WeekComparisonGeometry.relationText(current: 12, usual: 0))
    }
}

final class MuscleRowGeometryTests: XCTestCase {

    // MARK: - Rows are read against their own usual

    func testMatchingTheUsualLandsOnTheReferenceLine() {
        let geometry = MuscleRowGeometry(current: 20, usual: 20)
        XCTAssertEqual(
            geometry.fillFraction, MuscleRowGeometry.usualFraction, accuracy: 0.0001
        )
        XCTAssertFalse(geometry.isOverCap)
    }

    /// The whole point of the change: two groups an order of magnitude apart in
    /// absolute terms draw the same when both matched their own usual.
    func testGroupsOfDifferentSizesDrawAlikeWhenBothAreOnTarget() {
        let legs = MuscleRowGeometry(current: 284, usual: 284)
        let triceps = MuscleRowGeometry(current: 12, usual: 12)
        XCTAssertEqual(legs.fillFraction, triceps.fillFraction, accuracy: 0.0001)
    }

    /// The reported screen. Under the old shared scale legs filled the track and
    /// shoulders drew 8% of it; the ratio scale has to leave shoulders visible
    /// and place it below the line.
    func testALegFocusedWeekLeavesTheOtherGroupsReadable() {
        let legs = MuscleRowGeometry(current: 284, usual: 43)
        let shoulders = MuscleRowGeometry(current: 24, usual: 34)

        XCTAssertTrue(legs.isOverCap)
        XCTAssertEqual(legs.fillFraction, 1.0, accuracy: 0.0001)

        XCTAssertGreaterThan(shoulders.fillFraction, 0.3)
        XCTAssertLessThan(shoulders.fillFraction, MuscleRowGeometry.usualFraction)
    }

    func testHalfTheUsualDrawsHalfwayToTheLine() {
        let geometry = MuscleRowGeometry(current: 10, usual: 20)
        XCTAssertEqual(
            geometry.fillFraction, MuscleRowGeometry.usualFraction / 2, accuracy: 0.0001
        )
    }

    func testTheCapIsMarkedRatherThanSilent() {
        let atCap = MuscleRowGeometry(current: 40, usual: 20)
        XCTAssertEqual(atCap.fillFraction, 1.0, accuracy: 0.0001)
        XCTAssertFalse(atCap.isOverCap, "exactly twice is the cap, not past it")

        let pastCap = MuscleRowGeometry(current: 41, usual: 20)
        XCTAssertTrue(pastCap.isOverCap)
    }

    func testFillNeverExceedsTheTrack() {
        for current in [0.0, 1, 19, 20, 21, 200, 5_000] {
            let geometry = MuscleRowGeometry(current: current, usual: 20)
            XCTAssertLessThanOrEqual(geometry.fillFraction, 1.0, "overflowed at \(current)")
            XCTAssertGreaterThanOrEqual(geometry.fillFraction, 0.0, "underflowed at \(current)")
        }
    }

    // MARK: - Degenerate input

    func testASkippedGroupDrawsNothing() {
        let geometry = MuscleRowGeometry(current: 0, usual: 34)
        XCTAssertEqual(geometry.fillFraction, 0)
        XCTAssertFalse(geometry.isOverCap)
        XCTAssertFalse(geometry.isUncompared)
    }

    /// A group first trained this week has no ratio behind it, so the row says
    /// "new" rather than dividing by zero.
    func testAGroupWithNoHistoryIsMarkedUncompared() {
        let geometry = MuscleRowGeometry(current: 18, usual: 0)
        XCTAssertTrue(geometry.isUncompared)
        XCTAssertEqual(geometry.fillFraction, 1.0, accuracy: 0.0001)
    }

    func testNoBaselineAndNoWorkDrawsAnEmptyRow() {
        let geometry = MuscleRowGeometry(current: 0, usual: nil)
        XCTAssertEqual(geometry.fillFraction, 0)
        XCTAssertFalse(geometry.isUncompared)
    }
}
