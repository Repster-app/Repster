import XCTest
@testable import Repster

/// The What's New gate is invisible until a release actually ships, so the failure modes
/// — greeting a brand-new user with news, or nagging every launch — can't be caught by
/// looking at the app. They're covered here instead.
final class WhatsNewPreferencesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WhatsNewTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// The upgrade case: no stamp means a build from before the sheet existed.
    func testPresentsWhenNothingHasBeenSeen() {
        guard WhatsNewRelease.current != nil else {
            // This build's version has no release notes, which is a supported state —
            // `testSilentWhenReleaseHasNothingToSay` covers it.
            return
        }
        XCTAssertTrue(WhatsNewPreferences.shouldPresent(userDefaults: defaults))
    }

    /// The trap this design exists to avoid: a fresh install is stamped when onboarding
    /// completes, so it never sees news about the only version it has ever run.
    func testDoesNotPresentAfterOnboardingStampsCurrentVersion() {
        WhatsNewPreferences.markSeen(userDefaults: defaults)
        XCTAssertFalse(WhatsNewPreferences.shouldPresent(userDefaults: defaults))
    }

    func testDoesNotPresentTwiceForTheSameVersion() {
        WhatsNewPreferences.markSeen(userDefaults: defaults)
        XCTAssertFalse(WhatsNewPreferences.shouldPresent(userDefaults: defaults))
        XCTAssertFalse(WhatsNewPreferences.shouldPresent(userDefaults: defaults))
    }

    /// Equality rather than ordering, so a version rolled back in TestFlight still shows
    /// its sheet once rather than staying silent forever.
    func testPresentsAgainWhenTheStampedVersionDiffers() {
        guard WhatsNewRelease.current != nil else { return }
        defaults.set("0.0-stale", forKey: WhatsNewPreferences.lastSeenVersionKey)
        XCTAssertTrue(WhatsNewPreferences.shouldPresent(userDefaults: defaults))
    }

    func testSilentWhenReleaseHasNothingToSay() {
        // `current` is nil whenever the running version isn't in the catalogue, and that
        // must mean no sheet at all rather than an empty one.
        guard WhatsNewRelease.current == nil else { return }
        XCTAssertFalse(WhatsNewPreferences.shouldPresent(userDefaults: defaults))
    }

    func testCatalogueVersionsAreUniqueAndItemsAreCapped() {
        let versions = WhatsNewRelease.all.map(\.version)
        XCTAssertEqual(Set(versions).count, versions.count, "Two entries for one version means `current` silently picks the first")

        for release in WhatsNewRelease.all {
            XCTAssertFalse(release.items.isEmpty, "An empty release should be absent from the catalogue, not present and blank")
            XCTAssertLessThanOrEqual(release.items.count, 3, "Cap is three — see PRE_1.4_CHECKLIST.md §3.3")

            let ids = release.items.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "Duplicate item ids break ForEach identity")
        }
    }

    /// Exactly one row may carry the Health ask; two would race for the same one-shot
    /// iOS permission sheet.
    func testAtMostOneAppleHealthActionPerRelease() {
        for release in WhatsNewRelease.all {
            let asks = release.items.filter { $0.action == .connectAppleHealth }
            XCTAssertLessThanOrEqual(asks.count, 1)
        }
    }
}

/// Insights is the headline of 1.4 and has never shipped, so it must not land at the
/// bottom of a Home screen the user arranged before it existed.
final class InsightsSectionPromotionMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "InsightsPromotion.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        // HomeSectionConfig reads and writes `.standard`, so tests share that domain and
        // restore it rather than pretending otherwise.
        UserDefaults.standard.removeObject(forKey: "homeSectionConfig")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeObject(forKey: "homeSectionConfig")
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLiftsInsightsToTheTopOfACustomisedHome() {
        HomeSectionConfig(
            sections: [
                HomeSectionEntry(sectionId: .monthlyStats, visible: true),
                HomeSectionEntry(sectionId: .recentPRs, visible: true),
                HomeSectionEntry(sectionId: .insights, visible: true),
            ],
            recentWorkoutsCount: 5,
            prDisplayMode: .standard,
            recentPRScope: .anyPR
        ).save()

        InsightsSectionPromotionMigration.runIfNeeded(userDefaults: defaults)

        XCTAssertEqual(HomeSectionConfig.load().sections.first?.sectionId, .insights)
    }

    /// Hiding it is a real preference. Promotion moves the row, it doesn't reinstate it.
    func testPreservesHiddenState() {
        HomeSectionConfig(
            sections: [
                HomeSectionEntry(sectionId: .monthlyStats, visible: true),
                HomeSectionEntry(sectionId: .insights, visible: false),
            ],
            recentWorkoutsCount: 5,
            prDisplayMode: .standard,
            recentPRScope: .anyPR
        ).save()

        InsightsSectionPromotionMigration.runIfNeeded(userDefaults: defaults)

        let sections = HomeSectionConfig.load().sections
        XCTAssertEqual(sections.first?.sectionId, .insights)
        XCTAssertEqual(sections.first?.visible, false)
    }

    /// The rest of the arrangement is the user's and must survive untouched.
    func testLeavesTheRelativeOrderOfEverythingElseAlone() {
        HomeSectionConfig(
            sections: [
                HomeSectionEntry(sectionId: .recentWorkouts, visible: true),
                HomeSectionEntry(sectionId: .recentPRs, visible: true),
                HomeSectionEntry(sectionId: .monthlyStats, visible: true),
                HomeSectionEntry(sectionId: .insights, visible: true),
            ],
            recentWorkoutsCount: 5,
            prDisplayMode: .standard,
            recentPRScope: .anyPR
        ).save()

        InsightsSectionPromotionMigration.runIfNeeded(userDefaults: defaults)

        XCTAssertEqual(
            HomeSectionConfig.load().sections.map(\.sectionId),
            [.insights, .recentWorkouts, .recentPRs, .monthlyStats]
        )
    }

    /// Running once is help; running on every launch is an argument with the user.
    func testDoesNotReapplyAfterTheUserMovesItBack() {
        HomeSectionConfig(
            sections: [
                HomeSectionEntry(sectionId: .monthlyStats, visible: true),
                HomeSectionEntry(sectionId: .insights, visible: true),
            ],
            recentWorkoutsCount: 5,
            prDisplayMode: .standard,
            recentPRScope: .anyPR
        ).save()

        InsightsSectionPromotionMigration.runIfNeeded(userDefaults: defaults)
        XCTAssertEqual(HomeSectionConfig.load().sections.first?.sectionId, .insights)

        // The user deliberately demotes it.
        var config = HomeSectionConfig.load()
        let entry = config.sections.removeFirst()
        config.sections.append(entry)
        config.save()

        InsightsSectionPromotionMigration.runIfNeeded(userDefaults: defaults)

        XCTAssertEqual(HomeSectionConfig.load().sections.last?.sectionId, .insights)
    }
}
