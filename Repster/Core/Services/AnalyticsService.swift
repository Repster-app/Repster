import Foundation
import PostHog

struct AnalyticsConfiguration: Equatable {
    let projectToken: String
    let host: String

    init?(projectToken: String?, host: String?) {
        let trimmedToken = Self.resolvedValue(projectToken)
        guard let trimmedToken, !trimmedToken.isEmpty else { return nil }

        self.projectToken = trimmedToken
        self.host = Self.resolvedValue(host) ?? "https://eu.i.posthog.com"
    }

    init?(bundle: Bundle) {
        self.init(
            projectToken: bundle.object(forInfoDictionaryKey: "POSTHOG_PROJECT_TOKEN") as? String,
            host: bundle.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String
        )
    }

    private static func resolvedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

protocol AnalyticsClientProtocol {
    /// - Parameter startOptedOut: Applied at SDK setup time rather than immediately
    ///   after, because PostHog captures `Application Installed` / `Application Opened`
    ///   during `setup(_:)` itself. Opting out afterwards would still leak one
    ///   lifecycle event per launch for users who turned analytics off.
    func configure(_ configuration: AnalyticsConfiguration, startOptedOut: Bool)
    func capture(_ event: String, properties: [String: Any])
    func screen(_ screen: String, properties: [String: Any])
    func optIn()
    func optOut()
    func isOptOut() -> Bool
}

final class PostHogAnalyticsClient: AnalyticsClientProtocol {
    func configure(_ configuration: AnalyticsConfiguration, startOptedOut: Bool) {
        let config = PostHogConfig(
            projectToken: configuration.projectToken,
            host: configuration.host
        )
        config.optOut = startOptedOut
        // Person profiles are keyed off PostHog's random per-install distinct_id
        // (Repster has no accounts, so nothing identity-linked ever reaches it).
        // Required for retention insights and behavioural cohorts — without it
        // PostHog cannot answer "what did the users who never came back do?".
        config.personProfiles = .always
        config.setDefaultPersonProperties = false

        // Supplies `Application Installed` / `Opened` / `Became Active`, which are
        // the denominator for every activation and retention funnel.
        config.captureApplicationLifecycleEvents = true

        // Screen views stay manual so they use the curated `AnalyticsScreen` names.
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.rageClickConfig.enabled = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false

        // In-app surveys (multiple choice only — see the privacy policy) are the
        // qualitative counterpart to the funnel events.
        config.surveys = true

        configureSessionReplay(on: config)

        #if DEBUG
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)
    }

    /// Session replay is deliberately configured so that no workout data can leave
    /// the device. Repster is SwiftUI, so `maskAllTextInputs` masks *every* text
    /// layer (PostHog masks `SwiftUI.CGDrawingView`), not just editable fields —
    /// recordings show layout, navigation and taps with all text redacted.
    ///
    /// Keep this in sync with `marketing/website/privacy.html` and
    /// `marketing/app-store/privacy-review-checklist.md`.
    private func configureSessionReplay(on config: PostHogConfig) {
        config.sessionReplay = true

        // Wireframe mode renders almost nothing for SwiftUI hierarchies; screenshot
        // mode is the supported path, and is only safe because of the masking below.
        config.sessionReplayConfig.screenshotMode = true

        config.sessionReplayConfig.maskAllTextInputs = true
        config.sessionReplayConfig.maskAllImages = true
        config.sessionReplayConfig.maskAllSandboxedViews = true

        // Nothing about network traffic or logs is worth the disclosure surface.
        config.sessionReplayConfig.captureNetworkTelemetry = false
        config.sessionReplayConfig.captureLogs = false

        // One snapshot per second is plenty for navigation-flow analysis and keeps
        // the performance cost off the main thread budget during a workout.
        config.sessionReplayConfig.throttleDelay = 1.0
    }

    func capture(_ event: String, properties: [String: Any]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    func screen(_ screen: String, properties: [String: Any]) {
        PostHogSDK.shared.screen(screen, properties: properties)
    }

    func optIn() {
        PostHogSDK.shared.optIn()
    }

    func optOut() {
        PostHogSDK.shared.optOut()
    }

    func isOptOut() -> Bool {
        PostHogSDK.shared.isOptOut()
    }
}

final class NoopAnalyticsClient: AnalyticsClientProtocol {
    func configure(_ configuration: AnalyticsConfiguration, startOptedOut: Bool) {}
    func capture(_ event: String, properties: [String: Any]) {}
    func screen(_ screen: String, properties: [String: Any]) {}
    func optIn() {}
    func optOut() {}
    func isOptOut() -> Bool { true }
}

final class NoopAnalyticsService: AnalyticsServiceProtocol {
    var isCollectionEnabled: Bool { false }

    func configure() {}
    func setCollectionEnabled(_ enabled: Bool) {}
    func screen(_ screen: AnalyticsScreen, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) {}
    func track(_ event: AnalyticsEvent, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) {}
}

final class AnalyticsService: AnalyticsServiceProtocol {
    static let collectionEnabledDefaultsKey = "shareAnonymousAnalyticsEnabled"
    /// DEBUG-only escape hatch — see `AnalyticsServiceFactory.makeService`.
    static let debugCaptureEnabledDefaultsKey = "analyticsDebugCaptureEnabled"

    private let client: any AnalyticsClientProtocol
    private let configuration: AnalyticsConfiguration
    private let userDefaults: UserDefaults
    private let appVersion: String?
    private let buildNumber: String?

    init(
        client: any AnalyticsClientProtocol,
        configuration: AnalyticsConfiguration,
        userDefaults: UserDefaults = .standard,
        appVersion: String? = nil,
        buildNumber: String? = nil
    ) {
        self.client = client
        self.configuration = configuration
        self.userDefaults = userDefaults
        self.appVersion = appVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        self.buildNumber = buildNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    var isCollectionEnabled: Bool {
        if userDefaults.object(forKey: Self.collectionEnabledDefaultsKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: Self.collectionEnabledDefaultsKey)
    }

    func configure() {
        client.configure(configuration, startOptedOut: !isCollectionEnabled)
        applyCurrentCollectionPreference()
    }

    func setCollectionEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Self.collectionEnabledDefaultsKey)

        if enabled {
            client.optIn()
        } else {
            client.optOut()
        }
    }

    func screen(_ screen: AnalyticsScreen, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [:]) {
        guard isCollectionEnabled else { return }
        client.screen(screen.rawValue, properties: sanitize(properties))
    }

    func track(_ event: AnalyticsEvent, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue] = [:]) {
        guard isCollectionEnabled else { return }
        client.capture(event.rawValue, properties: sanitize(properties))
    }

    func sanitize(_ properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in properties {
            result[key.rawValue] = value.rawValue
        }
        if let appVersion {
            result[AnalyticsPropertyKey.appVersion.rawValue] = appVersion
        }
        if let buildNumber {
            result[AnalyticsPropertyKey.buildNumber.rawValue] = buildNumber
        }
        return result
    }

    func sanitizeRawProperties(_ properties: [String: AnalyticsPropertyValue]) -> [String: Any] {
        let allowedKeys = Set(AnalyticsPropertyKey.allCases.map(\.rawValue))
        return Dictionary(uniqueKeysWithValues: properties.compactMap { key, value in
            guard allowedKeys.contains(key) else { return nil }
            return (key, value.rawValue)
        })
    }

    private func applyCurrentCollectionPreference() {
        if isCollectionEnabled {
            client.optIn()
        } else {
            client.optOut()
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

enum AnalyticsServiceFactory {
    static func makeService(
        bundle: Bundle = .main,
        userDefaults: UserDefaults = .standard,
        client: (any AnalyticsClientProtocol)? = nil
    ) -> any AnalyticsServiceProtocol {
        #if DEBUG
        // There is one PostHog project, so a debug build would otherwise write
        // simulator runs into the same funnels as real users — invisible
        // contamination once a version is live. Verifying instrumentation is
        // still possible: add `-analyticsDebugCaptureEnabled YES` to the scheme's
        // launch arguments for that run.
        if client == nil,
           !userDefaults.bool(forKey: AnalyticsService.debugCaptureEnabledDefaultsKey) {
            return NoopAnalyticsService()
        }
        #endif

        guard let configuration = AnalyticsConfiguration(bundle: bundle) else {
            return NoopAnalyticsService()
        }

        return AnalyticsService(
            client: client ?? PostHogAnalyticsClient(),
            configuration: configuration,
            userDefaults: userDefaults,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
