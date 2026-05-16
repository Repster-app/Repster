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
    func configure(_ configuration: AnalyticsConfiguration)
    func capture(_ event: String, properties: [String: Any])
    func screen(_ screen: String, properties: [String: Any])
    func optIn()
    func optOut()
    func isOptOut() -> Bool
}

final class PostHogAnalyticsClient: AnalyticsClientProtocol {
    func configure(_ configuration: AnalyticsConfiguration) {
        let config = PostHogConfig(
            projectToken: configuration.projectToken,
            host: configuration.host
        )
        config.personProfiles = .never
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.sessionReplay = false
        config.surveys = false
        config.rageClickConfig.enabled = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.setDefaultPersonProperties = false

        #if DEBUG
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)
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
    func configure(_ configuration: AnalyticsConfiguration) {}
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

    private let client: any AnalyticsClientProtocol
    private let configuration: AnalyticsConfiguration
    private let userDefaults: UserDefaults

    init(
        client: any AnalyticsClientProtocol,
        configuration: AnalyticsConfiguration,
        userDefaults: UserDefaults = .standard
    ) {
        self.client = client
        self.configuration = configuration
        self.userDefaults = userDefaults
    }

    var isCollectionEnabled: Bool {
        if userDefaults.object(forKey: Self.collectionEnabledDefaultsKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: Self.collectionEnabledDefaultsKey)
    }

    func configure() {
        client.configure(configuration)
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
        Dictionary(uniqueKeysWithValues: properties.map { key, value in
            (key.rawValue, value.rawValue)
        })
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

enum AnalyticsServiceFactory {
    static func makeService(
        bundle: Bundle = .main,
        userDefaults: UserDefaults = .standard,
        client: (any AnalyticsClientProtocol)? = nil
    ) -> any AnalyticsServiceProtocol {
        guard let configuration = AnalyticsConfiguration(bundle: bundle) else {
            return NoopAnalyticsService()
        }

        return AnalyticsService(
            client: client ?? PostHogAnalyticsClient(),
            configuration: configuration,
            userDefaults: userDefaults
        )
    }
}
