import XCTest
@testable import Repster

final class AnalyticsServiceTests: XCTestCase {
    func testEventAndScreenNamesMatchTrackingPlan() {
        XCTAssertEqual(AnalyticsEvent.workoutStarted.rawValue, "workout started")
        XCTAssertEqual(AnalyticsEvent.workoutCompleted.rawValue, "workout completed")
        XCTAssertEqual(AnalyticsEvent.paywallShown.rawValue, "paywall shown")
        XCTAssertEqual(AnalyticsScreen.activeWorkout.rawValue, "Active Workout")
        XCTAssertEqual(AnalyticsScreen.workoutSummary.rawValue, "Workout Summary")
    }

    func testBucketFormattingUsesCoarseRanges() {
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 0), "under_30m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 29 * 60), "under_30m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 30 * 60), "30m_or_more")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 60 * 60), "30m_or_more")

        XCTAssertEqual(AnalyticsBuckets.count(0), "0")
        XCTAssertEqual(AnalyticsBuckets.count(1), "1")
        XCTAssertEqual(AnalyticsBuckets.count(3), "2-3")
        XCTAssertEqual(AnalyticsBuckets.count(6), "4-6")
        XCTAssertEqual(AnalyticsBuckets.count(10), "7-10")
        XCTAssertEqual(AnalyticsBuckets.count(11), "11+")
    }

    func testPropertyAllowlistDropsUnknownRawKeys() {
        let service = makeService().service

        let sanitized = service.sanitizeRawProperties([
            AnalyticsPropertyKey.source.rawValue: .string("settings"),
            "exercise_name": .string("Bench Press"),
            "notes": .string("private")
        ])

        XCTAssertEqual(sanitized.count, 1)
        XCTAssertEqual(sanitized[AnalyticsPropertyKey.source.rawValue] as? String, "settings")
        XCTAssertNil(sanitized["exercise_name"])
        XCTAssertNil(sanitized["notes"])
    }

    func testOptOutSuppressesCustomEvents() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        service.track(.workoutStarted, properties: [.source: .string("empty")])
        XCTAssertEqual(client.captures.count, 1)

        service.setCollectionEnabled(false)
        service.track(.workoutCompleted, properties: [.durationBucket: .string("under_30m")])

        XCTAssertEqual(client.optOutCount, 1)
        XCTAssertEqual(client.captures.count, 1)
    }

    func testMissingConfigurationFailsClosed() {
        XCTAssertNil(AnalyticsConfiguration(projectToken: "", host: "https://eu.i.posthog.com"))
        XCTAssertNil(AnalyticsConfiguration(projectToken: "$(POSTHOG_PROJECT_TOKEN)", host: "https://eu.i.posthog.com"))
        XCTAssertFalse(NoopAnalyticsService().isCollectionEnabled)
    }

    private var defaultsSuiteName: String {
        "AnalyticsServiceTests.\(name)"
    }

    private func makeService() -> (
        service: AnalyticsService,
        client: SpyAnalyticsClient,
        defaults: UserDefaults
    ) {
        let client = SpyAnalyticsClient()
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        let configuration = AnalyticsConfiguration(
            projectToken: "phc_test",
            host: "https://eu.i.posthog.com"
        )!
        return (
            AnalyticsService(client: client, configuration: configuration, userDefaults: defaults),
            client,
            defaults
        )
    }
}

private final class SpyAnalyticsClient: AnalyticsClientProtocol {
    private(set) var configured: AnalyticsConfiguration?
    private(set) var captures: [(event: String, properties: [String: Any])] = []
    private(set) var screens: [(screen: String, properties: [String: Any])] = []
    private(set) var optInCount = 0
    private(set) var optOutCount = 0
    private var optedOut = false

    func configure(_ configuration: AnalyticsConfiguration) {
        configured = configuration
    }

    func capture(_ event: String, properties: [String: Any]) {
        captures.append((event, properties))
    }

    func screen(_ screen: String, properties: [String: Any]) {
        screens.append((screen, properties))
    }

    func optIn() {
        optedOut = false
        optInCount += 1
    }

    func optOut() {
        optedOut = true
        optOutCount += 1
    }

    func isOptOut() -> Bool {
        optedOut
    }
}
