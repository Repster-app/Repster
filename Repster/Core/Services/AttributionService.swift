// AttributionService.swift
// Resolves Apple Search Ads install attribution and reports it once per install.
// Feature: paid-vs-organic acquisition measurement (1.4)

import AdServices
import Foundation
import OSLog

/// Apple Search Ads attribution, via Apple's own `AdServices` framework.
///
/// Why this can exist in an app that declares `NSPrivacyTracking = false`: the
/// token resolves to a *campaign*, not to a person. No IDFA is read, nothing is
/// linked with third-party data, and Apple therefore requires no ATT prompt.
/// The one thing it does add is an `NSPrivacyCollectedDataTypeAdvertisingData`
/// declaration — see `Repster/PrivacyInfo.xcprivacy` and section 1.2 of
/// `PRE_1.4_CHECKLIST.md`.
///
/// **Attribution is forward-only.** Nothing here can be backfilled, so an
/// install that resolves wrongly is lost permanently. That is why the retry
/// spans launches rather than giving up when the first attempt 404s.
actor AttributionService: AttributionServiceProtocol {
    struct RetryPolicy: Sendable {
        /// Attempts within a single launch. Apple's window is usually seconds,
        /// so a short burst catches most installs before the user has finished
        /// onboarding.
        var attemptsPerLaunch: Int = 3

        /// Apple's documentation asks for 5s between retries.
        var delayBetweenAttempts: Duration = .seconds(5)

        /// Cold launches we will keep trying across. Beyond this the record is
        /// almost certainly never coming, and a permanently pending install
        /// would otherwise make a network request on every launch forever.
        var maxLaunches: Int = 8

        /// Apple expires the attribution record itself, so there is no point
        /// asking after this even if we have attempts left.
        var maxAge: TimeInterval = 7 * 24 * 60 * 60
    }

    private let tokenProvider: any AttributionTokenProviding
    private let endpoint: any AttributionEndpointRequesting
    private let store: AttributionStateStore
    private let reporter: any AttributionReporting
    private let policy: RetryPolicy
    private let clock: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.repster.app", category: "attribution")

    init(
        tokenProvider: any AttributionTokenProviding = AdServicesTokenProvider(),
        endpoint: any AttributionEndpointRequesting = AppleAttributionEndpoint(),
        store: AttributionStateStore = AttributionStateStore(),
        reporter: any AttributionReporting,
        policy: RetryPolicy = RetryPolicy(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.tokenProvider = tokenProvider
        self.endpoint = endpoint
        self.store = store
        self.reporter = reporter
        self.policy = policy
        self.clock = clock
    }

    func resolveIfNeeded() async {
        guard store.status == .pending else { return }

        let now = clock()
        let firstAttemptAt = store.firstAttemptAt ?? now
        if store.firstAttemptAt == nil {
            store.firstAttemptAt = now
        }

        guard now.timeIntervalSince(firstAttemptAt) < policy.maxAge else {
            logger.notice("Attribution abandoned: record window expired")
            store.status = .abandoned
            return
        }

        let launchAttempt = store.launchAttempts + 1
        store.launchAttempts = launchAttempt

        for attempt in 1...policy.attemptsPerLaunch {
            switch await resolveOnce() {
            case .resolved(let record):
                store.status = .resolved
                reporter.reportAttribution(record)
                logger.notice("Attribution resolved: \(record.channel.rawValue, privacy: .public)")
                return

            case .unavailable:
                // Simulator or an unsupported platform — nothing will change on
                // a later launch, so stop rather than burning the launch budget.
                store.status = .abandoned
                logger.notice("Attribution unavailable on this device")
                return

            case .notReady:
                if attempt < policy.attemptsPerLaunch {
                    try? await Task.sleep(for: policy.delayBetweenAttempts)
                }
            }
        }

        if launchAttempt >= policy.maxLaunches {
            logger.notice("Attribution abandoned after \(launchAttempt) launches")
            store.status = .abandoned
        }
    }

    private func resolveOnce() async -> AttributionOutcome {
        let token: String
        do {
            token = try tokenProvider.attributionToken()
        } catch {
            // `AAAttribution` throws on the simulator and on platforms without
            // AdServices. It also throws a transient network error, but there is
            // no reliable way to tell the two apart across OS versions, so this
            // is treated as terminal only after the launch budget runs out.
            logger.debug("Attribution token unavailable: \(error.localizedDescription, privacy: .public)")
            return .unavailable
        }

        do {
            return .resolved(try await endpoint.resolve(token: token))
        } catch AttributionEndpointError.notReady {
            return .notReady
        } catch {
            logger.debug("Attribution lookup failed: \(error.localizedDescription, privacy: .public)")
            return .notReady
        }
    }
}

// MARK: - Token

protocol AttributionTokenProviding: Sendable {
    func attributionToken() throws -> String
}

struct AdServicesTokenProvider: AttributionTokenProviding {
    func attributionToken() throws -> String {
        try AAAttribution.attributionToken()
    }
}

// MARK: - Endpoint

enum AttributionEndpointError: Error, Equatable {
    /// Apple answers 404 until the record exists, and 5xx transiently.
    case notReady
    case badResponse
}

protocol AttributionEndpointRequesting: Sendable {
    func resolve(token: String) async throws -> AttributionRecord
}

/// Apple's attribution lookup. The token goes in the body as `text/plain`; the
/// response is a small JSON object.
struct AppleAttributionEndpoint: AttributionEndpointRequesting {
    static let url = URL(string: "https://api-adservices.apple.com/api/v1/")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(token: String) async throws -> AttributionRecord {
        var request = URLRequest(url: Self.url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(token.utf8)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AttributionEndpointError.badResponse
        }

        switch http.statusCode {
        case 200:
            let payload = try JSONDecoder().decode(ApplePayload.self, from: data)
            return payload.record
        case 404, 500...599:
            throw AttributionEndpointError.notReady
        default:
            throw AttributionEndpointError.badResponse
        }
    }

    /// Only the fields worth keeping. `orgId` and `adId` are deliberately
    /// dropped — `orgId` is our own account and constant, `adId` identifies a
    /// creative we do not vary.
    struct ApplePayload: Decodable {
        let attribution: Bool
        let campaignId: Int?
        let conversionType: String?
        let adGroupId: Int?
        let countryOrRegion: String?
        let keywordId: Int?

        var record: AttributionRecord {
            guard attribution else { return .organic }
            return AttributionRecord(
                channel: .appleSearchAds,
                conversionType: conversionType.flatMap {
                    AttributionConversionType(rawValue: $0.lowercased())
                },
                campaignId: campaignId,
                adGroupId: adGroupId,
                keywordId: keywordId,
                countryOrRegion: countryOrRegion
            )
        }
    }
}

// MARK: - State

/// Survives launches so a pending resolution can be picked up again. Small
/// enough that `UserDefaults` is the right home; it must *not* be persisted
/// anywhere that restores to a new device, or a restored backup would inherit
/// the old phone's campaign.
struct AttributionStateStore: Sendable {
    enum Status: String {
        case pending
        case resolved
        case abandoned
    }

    private enum Key {
        static let status = "attribution.status"
        static let launchAttempts = "attribution.launchAttempts"
        static let firstAttemptAt = "attribution.firstAttemptAt"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var status: Status {
        get {
            userDefaults.string(forKey: Key.status)
                .flatMap(Status.init(rawValue:)) ?? .pending
        }
        nonmutating set {
            userDefaults.set(newValue.rawValue, forKey: Key.status)
        }
    }

    var launchAttempts: Int {
        get { userDefaults.integer(forKey: Key.launchAttempts) }
        nonmutating set { userDefaults.set(newValue, forKey: Key.launchAttempts) }
    }

    var firstAttemptAt: Date? {
        get { userDefaults.object(forKey: Key.firstAttemptAt) as? Date }
        nonmutating set { userDefaults.set(newValue, forKey: Key.firstAttemptAt) }
    }
}

// MARK: - Reporting

protocol AttributionReporting: Sendable {
    func reportAttribution(_ record: AttributionRecord)
}

/// Writes the resolved record to PostHog as **person properties**, not event
/// properties.
///
/// This matters more than it looks. Resolution can land after `onboarding step
/// viewed` has already fired, so an event property would be missing from
/// precisely the first-session events the activation funnel is built on. PostHog
/// applies person-property filters across a person's whole history, so setting
/// them late still segments every earlier event correctly.
///
/// `setOnce` because an install has exactly one origin — a later re-resolution
/// must never overwrite it.
struct AnalyticsAttributionReporter: AttributionReporting, @unchecked Sendable {
    // `AnalyticsServiceProtocol` predates strict concurrency and is not Sendable,
    // but `AnalyticsService` holds only immutable state and forwards to the
    // PostHog SDK, which is thread-safe by contract.
    private let analytics: any AnalyticsServiceProtocol

    init(analytics: any AnalyticsServiceProtocol) {
        self.analytics = analytics
    }

    func reportAttribution(_ record: AttributionRecord) {
        var personProperties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [
            .acquisitionChannel: .string(record.channel.rawValue)
        ]
        if let conversionType = record.conversionType {
            personProperties[.asaConversionType] = .string(conversionType.rawValue)
        }
        if let campaignId = record.campaignId {
            personProperties[.asaCampaignId] = .int(campaignId)
        }
        if let adGroupId = record.adGroupId {
            personProperties[.asaAdGroupId] = .int(adGroupId)
        }
        if let keywordId = record.keywordId {
            personProperties[.asaKeywordId] = .int(keywordId)
        }
        if let countryOrRegion = record.countryOrRegion {
            personProperties[.asaCountry] = .string(countryOrRegion)
        }

        // The event itself is the verification signal: if this never arrives in
        // PostHog after release, resolution is broken and every funnel below is
        // running unsegmented.
        analytics.track(
            .attributionResolved,
            properties: [
                .acquisitionChannel: .string(record.channel.rawValue),
                .asaConversionType: .string(record.conversionType?.rawValue ?? "unknown")
            ],
            personPropertiesSetOnce: personProperties
        )
    }
}

// MARK: - Factory

enum AttributionServiceFactory {
    /// Returns `nil` when attribution must not run: analytics collection is off,
    /// or this is a DEBUG build without the explicit capture override. Callers
    /// treat `nil` as "do nothing", which also keeps RevenueCat's own AdServices
    /// collector switched off — the privacy policy promises one toggle covers
    /// everything, so no collection path may ignore it.
    static func makeService(
        analytics: any AnalyticsServiceProtocol,
        userDefaults: UserDefaults = .standard
    ) -> (any AttributionServiceProtocol)? {
        guard analytics.isCollectionEnabled else { return nil }

        #if DEBUG
        guard userDefaults.bool(forKey: AnalyticsService.debugCaptureEnabledDefaultsKey) else {
            return nil
        }
        #endif

        return AttributionService(
            store: AttributionStateStore(userDefaults: userDefaults),
            reporter: AnalyticsAttributionReporter(analytics: analytics)
        )
    }
}
