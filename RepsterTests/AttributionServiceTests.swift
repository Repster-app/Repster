import XCTest
@testable import Repster

final class AttributionServiceTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AttributionServiceTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Payload decoding

    func testAttributedPayloadDecodesCampaignFields() throws {
        let json = """
        {
          "attribution": true,
          "orgId": 40669820,
          "campaignId": 542370539,
          "conversionType": "Download",
          "adGroupId": 542317095,
          "countryOrRegion": "US",
          "keywordId": 87675432,
          "adId": 542317136
        }
        """
        let payload = try JSONDecoder().decode(
            AppleAttributionEndpoint.ApplePayload.self,
            from: Data(json.utf8)
        )

        let record = payload.record
        XCTAssertEqual(record.channel, .appleSearchAds)
        XCTAssertEqual(record.conversionType, .download)
        XCTAssertEqual(record.campaignId, 542370539)
        XCTAssertEqual(record.adGroupId, 542317095)
        XCTAssertEqual(record.keywordId, 87675432)
        XCTAssertEqual(record.countryOrRegion, "US")
    }

    /// Apple sends the bare `attribution: false` for an organic install — every
    /// other field is absent, so decoding must not require them.
    func testOrganicPayloadDecodesWithNoOtherFields() throws {
        let payload = try JSONDecoder().decode(
            AppleAttributionEndpoint.ApplePayload.self,
            from: Data(#"{"attribution": false}"#.utf8)
        )

        XCTAssertEqual(payload.record, .organic)
        XCTAssertEqual(payload.record.channel, .organic)
    }

    /// A reinstall by the same Apple ID. Kept separate because it skips
    /// onboarding and would otherwise be counted as a new user.
    func testRedownloadConversionTypeIsRecognised() throws {
        let json = #"{"attribution": true, "conversionType": "Redownload"}"#
        let payload = try JSONDecoder().decode(
            AppleAttributionEndpoint.ApplePayload.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(payload.record.conversionType, .redownload)
    }

    /// Campaign-level fields are withheld for low-volume campaigns and absent
    /// for non-search campaign types, so an attributed install with nothing but
    /// the flag still has to resolve rather than fall back to organic.
    func testAttributedPayloadWithNoCampaignFieldsStaysPaid() throws {
        let payload = try JSONDecoder().decode(
            AppleAttributionEndpoint.ApplePayload.self,
            from: Data(#"{"attribution": true}"#.utf8)
        )

        XCTAssertEqual(payload.record.channel, .appleSearchAds)
        XCTAssertNil(payload.record.campaignId)
        XCTAssertNil(payload.record.conversionType)
    }

    // MARK: - Resolution

    func testResolvedRecordIsReportedAndPersisted() async {
        let reporter = SpyReporter()
        let store = AttributionStateStore(userDefaults: userDefaults)
        let service = makeService(
            endpoint: StubEndpoint(results: [.success(.paidExample)]),
            store: store,
            reporter: reporter
        )

        await service.resolveIfNeeded()

        XCTAssertEqual(reporter.records, [.paidExample])
        XCTAssertEqual(store.status, .resolved)
    }

    /// An install has exactly one origin. Once resolved, later launches must not
    /// hit the network again or re-report.
    func testResolutionDoesNotRepeatOnLaterLaunches() async {
        let reporter = SpyReporter()
        let endpoint = StubEndpoint(results: [.success(.paidExample)])
        let store = AttributionStateStore(userDefaults: userDefaults)

        await makeService(endpoint: endpoint, store: store, reporter: reporter)
            .resolveIfNeeded()
        await makeService(endpoint: endpoint, store: store, reporter: reporter)
            .resolveIfNeeded()

        XCTAssertEqual(reporter.records.count, 1)
        XCTAssertEqual(endpoint.callCount, 1)
    }

    /// Apple 404s until the record exists. The first answer is expected to be
    /// `notReady`, and the retry inside the launch has to pick it up.
    func testRetriesWithinALaunchUntilAppleAnswers() async {
        let reporter = SpyReporter()
        let endpoint = StubEndpoint(results: [
            .failure(AttributionEndpointError.notReady),
            .failure(AttributionEndpointError.notReady),
            .success(.paidExample)
        ])

        await makeService(endpoint: endpoint, reporter: reporter).resolveIfNeeded()

        XCTAssertEqual(endpoint.callCount, 3)
        XCTAssertEqual(reporter.records, [.paidExample])
    }

    /// The whole reason the retry spans launches: attribution cannot be
    /// backfilled, so a launch that ends before Apple answers must leave the
    /// state pending rather than giving up.
    func testStaysPendingWhenAppleNeverAnswersWithinALaunch() async {
        let store = AttributionStateStore(userDefaults: userDefaults)
        let endpoint = StubEndpoint(
            results: Array(repeating: .failure(AttributionEndpointError.notReady), count: 3)
        )

        await makeService(endpoint: endpoint, store: store, reporter: SpyReporter())
            .resolveIfNeeded()

        XCTAssertEqual(store.status, .pending)
        XCTAssertEqual(store.launchAttempts, 1)
    }

    func testLaterLaunchResolvesWhatAnEarlierOneCouldNot() async {
        let reporter = SpyReporter()
        let store = AttributionStateStore(userDefaults: userDefaults)
        let endpoint = StubEndpoint(results: [
            .failure(AttributionEndpointError.notReady),
            .failure(AttributionEndpointError.notReady),
            .failure(AttributionEndpointError.notReady),
            .success(.paidExample)
        ])

        await makeService(endpoint: endpoint, store: store, reporter: reporter)
            .resolveIfNeeded()
        XCTAssertTrue(reporter.records.isEmpty)

        await makeService(endpoint: endpoint, store: store, reporter: reporter)
            .resolveIfNeeded()

        XCTAssertEqual(reporter.records, [.paidExample])
        XCTAssertEqual(store.status, .resolved)
    }

    /// A permanently pending install would otherwise make a network request on
    /// every launch forever.
    func testGivesUpAfterTheLaunchBudget() async {
        let store = AttributionStateStore(userDefaults: userDefaults)
        let policy = AttributionService.RetryPolicy(
            attemptsPerLaunch: 1,
            delayBetweenAttempts: .zero,
            maxLaunches: 3
        )
        let endpoint = StubEndpoint(
            results: Array(repeating: .failure(AttributionEndpointError.notReady), count: 10)
        )

        for _ in 0..<3 {
            await makeService(
                endpoint: endpoint,
                store: store,
                reporter: SpyReporter(),
                policy: policy
            ).resolveIfNeeded()
        }

        XCTAssertEqual(store.status, .abandoned)
        XCTAssertEqual(endpoint.callCount, 3)

        // A fourth launch must not touch the network at all.
        await makeService(
            endpoint: endpoint,
            store: store,
            reporter: SpyReporter(),
            policy: policy
        ).resolveIfNeeded()
        XCTAssertEqual(endpoint.callCount, 3)
    }

    /// Apple expires the record, so there is nothing left to ask for.
    func testGivesUpOnceTheRecordWindowHasExpired() async {
        let store = AttributionStateStore(userDefaults: userDefaults)
        let installedAt = Date(timeIntervalSince1970: 1_000_000)
        store.firstAttemptAt = installedAt

        let endpoint = StubEndpoint(results: [.success(.paidExample)])
        let service = AttributionService(
            tokenProvider: StubTokenProvider(token: "token"),
            endpoint: endpoint,
            store: store,
            reporter: SpyReporter(),
            policy: AttributionService.RetryPolicy(delayBetweenAttempts: .zero),
            clock: { installedAt.addingTimeInterval(8 * 24 * 60 * 60) }
        )

        await service.resolveIfNeeded()

        XCTAssertEqual(store.status, .abandoned)
        XCTAssertEqual(endpoint.callCount, 0)
    }

    /// The simulator throws, and no later launch will change that.
    func testUnavailableTokenIsTerminalImmediately() async {
        let store = AttributionStateStore(userDefaults: userDefaults)
        let endpoint = StubEndpoint(results: [.success(.paidExample)])
        let service = AttributionService(
            tokenProvider: FailingTokenProvider(),
            endpoint: endpoint,
            store: store,
            reporter: SpyReporter(),
            policy: AttributionService.RetryPolicy(delayBetweenAttempts: .zero)
        )

        await service.resolveIfNeeded()

        XCTAssertEqual(store.status, .abandoned)
        XCTAssertEqual(endpoint.callCount, 0)
    }

    // MARK: - Reporting

    /// Person properties, not event properties — resolution can land after the
    /// first-session events have already fired, and only person properties
    /// segment those retroactively.
    func testReporterSendsCampaignFieldsAsPersonProperties() {
        let analytics = CapturingAnalytics()
        AnalyticsAttributionReporter(analytics: analytics)
            .reportAttribution(.paidExample)

        XCTAssertEqual(analytics.event, .attributionResolved)
        XCTAssertEqual(analytics.personProperties[.acquisitionChannel], .string("apple_search_ads"))
        XCTAssertEqual(analytics.personProperties[.asaCampaignId], .int(542370539))
        XCTAssertEqual(analytics.personProperties[.asaKeywordId], .int(87675432))
        XCTAssertEqual(analytics.personProperties[.asaConversionType], .string("download"))
        XCTAssertEqual(analytics.personProperties[.asaCountry], .string("US"))
    }

    func testOrganicInstallReportsChannelAndNothingElse() {
        let analytics = CapturingAnalytics()
        AnalyticsAttributionReporter(analytics: analytics)
            .reportAttribution(.organic)

        XCTAssertEqual(analytics.personProperties[.acquisitionChannel], .string("organic"))
        XCTAssertNil(analytics.personProperties[.asaCampaignId])
        XCTAssertNil(analytics.personProperties[.asaConversionType])
    }

    // MARK: - Opt-out

    /// The privacy policy promises the Share Anonymous Analytics toggle disables
    /// everything. A collection path that ignored it would make that wrong.
    func testFactoryReturnsNilWhenCollectionIsDisabled() {
        let analytics = CapturingAnalytics()
        analytics.isCollectionEnabled = false

        XCTAssertNil(
            AttributionServiceFactory.makeService(
                analytics: analytics,
                userDefaults: userDefaults
            )
        )
    }

    // MARK: - Helpers

    private func makeService(
        endpoint: any AttributionEndpointRequesting,
        store: AttributionStateStore? = nil,
        reporter: any AttributionReporting,
        policy: AttributionService.RetryPolicy = AttributionService.RetryPolicy(
            delayBetweenAttempts: .zero
        )
    ) -> AttributionService {
        AttributionService(
            tokenProvider: StubTokenProvider(token: "token"),
            endpoint: endpoint,
            store: store ?? AttributionStateStore(userDefaults: userDefaults),
            reporter: reporter,
            policy: policy
        )
    }
}

// MARK: - Doubles

private extension AttributionRecord {
    static let paidExample = AttributionRecord(
        channel: .appleSearchAds,
        conversionType: .download,
        campaignId: 542370539,
        adGroupId: 542317095,
        keywordId: 87675432,
        countryOrRegion: "US"
    )
}

private struct StubTokenProvider: AttributionTokenProviding {
    let token: String
    func attributionToken() throws -> String { token }
}

private struct FailingTokenProvider: AttributionTokenProviding {
    struct Unavailable: Error {}
    func attributionToken() throws -> String { throw Unavailable() }
}

private final class StubEndpoint: AttributionEndpointRequesting, @unchecked Sendable {
    private let results: [Result<AttributionRecord, Error>]
    private let lock = NSLock()
    private var index = 0

    init(results: [Result<AttributionRecord, Error>]) {
        self.results = results
    }

    var callCount: Int {
        lock.withLock { index }
    }

    func resolve(token: String) async throws -> AttributionRecord {
        let result: Result<AttributionRecord, Error> = lock.withLock {
            guard index < results.count else {
                return .failure(AttributionEndpointError.notReady)
            }
            defer { index += 1 }
            return results[index]
        }
        return try result.get()
    }
}

private final class SpyReporter: AttributionReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AttributionRecord] = []

    var records: [AttributionRecord] {
        lock.withLock { storage }
    }

    func reportAttribution(_ record: AttributionRecord) {
        lock.withLock { storage.append(record) }
    }
}

private final class CapturingAnalytics: AnalyticsServiceProtocol {
    var isCollectionEnabled = true
    private(set) var event: AnalyticsEvent?
    private(set) var properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [:]
    private(set) var personProperties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [:]

    func configure() {}
    func setCollectionEnabled(_ enabled: Bool) { isCollectionEnabled = enabled }
    func screen(_ screen: AnalyticsScreen, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) {}

    func track(_ event: AnalyticsEvent, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) {
        self.event = event
        self.properties = properties
    }

    func track(
        _ event: AnalyticsEvent,
        properties: [AnalyticsPropertyKey: AnalyticsPropertyValue],
        personPropertiesSetOnce: [AnalyticsPropertyKey: AnalyticsPropertyValue]
    ) {
        self.event = event
        self.properties = properties
        self.personProperties = personPropertiesSetOnce
    }
}
