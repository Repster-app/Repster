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

/// PostHog's iOS SDK has no per-event switch for application lifecycle events:
/// `captureApplicationLifecycleEvents` brings `Application Installed`, `Updated`,
/// `Opened` and `Backgrounded`, or none of them. Only the first three answer a
/// question, and the other two dominate volume — on 1.1, the last released version
/// with lifecycle capture enabled, `Opened` and `Backgrounded` were 76% of every
/// event the project ingested (623 of 817).
///
/// Turning the flag off is not the answer — that is exactly what 1.2 did, and it
/// left 1.2 and 1.3 with no `Application Installed` at all, so every activation
/// funnel ran on a denominator of zero for the whole live period. The flag stays
/// on and this drops the noise in `beforeSend`, before it is cached or sent.
enum LifecycleEventFilter {
    static func allows(event: String, properties: [String: Any]) -> Bool {
        switch event {
        case "Application Backgrounded":
            // Fires on every app switch, and a workout is full of them.
            return false
        case "Application Opened":
            // A cold launch is the real session start and carries `version` /
            // `build`. A resume from background carries only `from_background`.
            return properties["from_background"] as? Bool != true
        default:
            return true
        }
    }
}

protocol AnalyticsClientProtocol {
    /// - Parameter startOptedOut: Applied at SDK setup time rather than immediately
    ///   after, because PostHog captures `Application Installed` / `Application Opened`
    ///   during `setup(_:)` itself. Opting out afterwards would still leak one
    ///   lifecycle event per launch for users who turned analytics off.
    func configure(_ configuration: AnalyticsConfiguration, startOptedOut: Bool)
    func capture(_ event: String, properties: [String: Any])
    func capture(
        _ event: String,
        properties: [String: Any],
        personPropertiesSetOnce: [String: Any]
    )
    func screen(_ screen: String, properties: [String: Any])
    func captureException(_ error: Error, properties: [String: Any])
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

        // Supplies `Application Installed` / `Updated` / `Opened`, which are the
        // denominator for every activation and retention funnel. See
        // `LifecycleEventFilter` for why the noisy half is dropped here rather
        // than by turning this off.
        config.captureApplicationLifecycleEvents = true
        config.setBeforeSend { event in
            LifecycleEventFilter.allows(event: event.event, properties: event.properties)
                ? event
                : nil
        }

        // Screen views stay manual so they use the curated `AnalyticsScreen` names.
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.rageClickConfig.enabled = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false

        // In-app surveys (multiple choice only — see the privacy policy) are the
        // qualitative counterpart to the funnel events.
        config.surveys = true

        configureErrorTracking(on: config)
        configureSessionReplay(on: config)

        #if DEBUG
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)
    }

    /// Crash and exception capture, via PLCrashReporter under the hood. Catches Mach
    /// exceptions (`EXC_BAD_ACCESS`, the class of the crash 1.3 shipped with), POSIX
    /// signals and uncaught `NSException`s; the report is written to disk and sent as
    /// `$exception` on the next launch.
    ///
    /// Two things outside this file have to be true for it to work:
    /// - **Enable exception autocapture** must be on in PostHog project settings. The
    ///   SDK reads that remote config at startup and skips installing the crash handler
    ///   when it is off, so a build with this line can still capture nothing.
    /// - dSYMs must be uploaded per release, or every frame arrives as a hex address.
    ///   See `PRE_1.4_CHECKLIST.md` §1.5.
    ///
    /// Opt-out is already honoured: `config.optOut` is applied at setup, above.
    private func configureErrorTracking(on config: PostHogConfig) {
        config.errorTrackingConfig.autoCapture = true
    }

    /// Session replay records the app legibly and masks named values, rather than the
    /// other way round. Until 1.5 the default was to mask everything and opt screens in
    /// one at a time; that left six whole sections and 41 of the app's 45 sheets black,
    /// because a sheet is a separate presentation and does not inherit an enclosing
    /// unmask. What survived was too patchy to diagnose anything with.
    ///
    /// So `maskAllTextInputs` is off, and the values that must never leave the device
    /// are masked at the field via `replayMasked()` — `Repster/Core/Extensions/ReplayPrivacy.swift`
    /// holds the modifier and the reasoning. `grep -r replayMasked` is the complete list
    /// of what a recording hides, and `ReplayMaskCoverageTests` fails the build when a
    /// new free-text field is added without one.
    ///
    /// Keep this in sync with `docs/privacy.html` and
    /// `marketing/app-store/privacy-review-checklist.md`.
    private func configureSessionReplay(on config: PostHogConfig) {
        config.sessionReplay = true

        // Wireframe mode renders almost nothing for SwiftUI hierarchies; screenshot
        // mode is the supported path, and is only safe because of the masking below.
        config.sessionReplayConfig.screenshotMode = true

        // Off: see the note above. Free text and bodyweight are masked per field.
        config.sessionReplayConfig.maskAllTextInputs = false

        // Repster has no photo picker and no remote imagery — every image in the app is
        // one Repster ships or an SF Symbol. PostHog spares those for `UIImageView`, but
        // SwiftUI images arrive as `SwiftUI.ImageLayer`, where `isSwiftUIImageSensitive`
        // cannot tell an asset from a photo and blacks out all of them. Nothing here is
        // user content, so the flag only cost us the icons.
        config.sessionReplayConfig.maskAllImages = false

        // Stays on: `_UIRemoteView` is drawn by another process — the share sheet, the
        // Health permission sheet — and its contents are not ours to record.
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

    func capture(
        _ event: String,
        properties: [String: Any],
        personPropertiesSetOnce: [String: Any]
    ) {
        PostHogSDK.shared.capture(
            event,
            properties: properties,
            userPropertiesSetOnce: personPropertiesSetOnce
        )
    }

    func screen(_ screen: String, properties: [String: Any]) {
        PostHogSDK.shared.screen(screen, properties: properties)
    }

    func captureException(_ error: Error, properties: [String: Any]) {
        PostHogSDK.shared.captureException(error, properties: properties)
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
    func capture(
        _ event: String,
        properties: [String: Any],
        personPropertiesSetOnce: [String: Any]
    ) {}
    func screen(_ screen: String, properties: [String: Any]) {}
    func captureException(_ error: Error, properties: [String: Any]) {}
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
    func captureError(_ error: Error, context: AnalyticsErrorContext) {}
}

final class AnalyticsService: AnalyticsServiceProtocol {
    static let collectionEnabledDefaultsKey = "shareAnonymousAnalyticsEnabled"
    /// DEBUG-only escape hatch — see `AnalyticsServiceFactory.makeService`.
    static let debugCaptureEnabledDefaultsKey = "analyticsDebugCaptureEnabled"

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

    func track(
        _ event: AnalyticsEvent,
        properties: [AnalyticsPropertyKey: AnalyticsPropertyValue],
        personPropertiesSetOnce: [AnalyticsPropertyKey: AnalyticsPropertyValue]
    ) {
        guard isCollectionEnabled else { return }
        client.capture(
            event.rawValue,
            properties: sanitize(properties),
            personPropertiesSetOnce: sanitize(personPropertiesSetOnce)
        )
    }

    /// The only real implementation of the tally — the protocol default is a no-op.
    ///
    /// The opt-out gate is here, at increment time rather than at send time, so an
    /// opted-out user accumulates nothing at all rather than accumulating locally
    /// and having it dropped on the way out.
    func recordWorkoutInteraction(_ interaction: WorkoutInteraction) {
        guard isCollectionEnabled else { return }
        WorkoutInteractionTally.increment(interaction, userDefaults: userDefaults)
    }

    /// Only the error's type and description travel with this — deliberately no
    /// payload, so a failed Health write can never carry workout contents off the
    /// device. Keep thrown error messages free of user data (`WorkoutHistoryBackupError`
    /// interpolates ids, never names or notes) and that stays true.
    func captureError(_ error: Error, context: AnalyticsErrorContext) {
        guard isCollectionEnabled else { return }
        client.captureException(error, properties: sanitize([
            .errorContext: .string(context.rawValue),
            .errorType: .string(String(describing: type(of: error)))
        ]))
    }

    /// Version is deliberately not stamped here. PostHog's static context already
    /// puts `$app_version` / `$app_build` on *every* event, including the SDK's own
    /// lifecycle events — a custom copy could only ever cover the events the app
    /// fires itself, which is how 1.2 through 1.4 ended up with two version
    /// properties that disagreed about which events they applied to.
    func sanitize(_ properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in properties {
            result[key.rawValue] = value.rawValue
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

// MARK: - Error reporting port

/// The half of `AnalyticsServiceProtocol` that actors need. `HealthKitService` and
/// `SubscriptionService` are actors, so they hold this rather than the service itself
/// — same arrangement, and the same reason, as `AnalyticsAttributionReporter`.
protocol AnalyticsErrorReporting: Sendable {
    func report(_ error: Error, context: AnalyticsErrorContext)
}

struct AnalyticsErrorReporter: AnalyticsErrorReporting, @unchecked Sendable {
    // `AnalyticsServiceProtocol` predates strict concurrency and is not Sendable,
    // but `AnalyticsService` holds only immutable state and forwards to the
    // PostHog SDK, which is thread-safe by contract.
    private let analytics: any AnalyticsServiceProtocol

    init(analytics: any AnalyticsServiceProtocol) {
        self.analytics = analytics
    }

    func report(_ error: Error, context: AnalyticsErrorContext) {
        analytics.captureError(error, context: context)
    }
}

struct NoopAnalyticsErrorReporter: AnalyticsErrorReporting {
    func report(_ error: Error, context: AnalyticsErrorContext) {}
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
            userDefaults: userDefaults
        )
    }
}
