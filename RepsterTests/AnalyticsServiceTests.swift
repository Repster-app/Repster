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

    func testDurationBucketsCoverFinerRanges() {
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 0), "under_15m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 14 * 60), "under_15m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 15 * 60), "15-30m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 29 * 60), "15-30m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 30 * 60), "30-45m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 45 * 60), "45-60m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 60 * 60), "60-90m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 89 * 60), "60-90m")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 90 * 60), "90m_or_more")
        XCTAssertEqual(AnalyticsBuckets.duration(seconds: 180 * 60), "90m_or_more")
    }

    func testCountBucketsForSmallTallies() {
        XCTAssertEqual(AnalyticsBuckets.count(0), "0")
        XCTAssertEqual(AnalyticsBuckets.count(1), "1")
        XCTAssertEqual(AnalyticsBuckets.count(3), "2-3")
        XCTAssertEqual(AnalyticsBuckets.count(6), "4-6")
        XCTAssertEqual(AnalyticsBuckets.count(10), "7-10")
        XCTAssertEqual(AnalyticsBuckets.count(11), "11+")
    }

    func testWideCountBucketsForCumulativeTallies() {
        XCTAssertEqual(AnalyticsBuckets.wideCount(0), "0")
        XCTAssertEqual(AnalyticsBuckets.wideCount(10), "1-10")
        XCTAssertEqual(AnalyticsBuckets.wideCount(11), "11-25")
        XCTAssertEqual(AnalyticsBuckets.wideCount(50), "26-50")
        XCTAssertEqual(AnalyticsBuckets.wideCount(100), "51-100")
        XCTAssertEqual(AnalyticsBuckets.wideCount(200), "101-200")
        XCTAssertEqual(AnalyticsBuckets.wideCount(201), "200+")
    }

    func testTimeOfDayBuckets() {
        let calendar = Calendar(identifier: .gregorian)
        func date(hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 19, hour: hour))!
        }
        XCTAssertEqual(AnalyticsBuckets.timeOfDay(date(hour: 7), calendar: calendar), "morning")
        XCTAssertEqual(AnalyticsBuckets.timeOfDay(date(hour: 13), calendar: calendar), "afternoon")
        XCTAssertEqual(AnalyticsBuckets.timeOfDay(date(hour: 18), calendar: calendar), "evening")
        XCTAssertEqual(AnalyticsBuckets.timeOfDay(date(hour: 2), calendar: calendar), "night")
        XCTAssertEqual(AnalyticsBuckets.timeOfDay(date(hour: 22), calendar: calendar), "night")
    }

    func testDayOfWeekBuckets() {
        let calendar = Calendar(identifier: .gregorian)
        // 2026-05-19 is a Tuesday.
        let tue = calendar.date(from: DateComponents(year: 2026, month: 5, day: 19))!
        XCTAssertEqual(AnalyticsBuckets.dayOfWeek(tue, calendar: calendar), "tue")
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
        service.track(.workoutCompleted, properties: [.durationBucket: .string("under_15m")])

        XCTAssertEqual(client.optOutCount, 1)
        XCTAssertEqual(client.captures.count, 1)
    }

    /// PostHog captures `Application Installed` / `Opened` inside `setup(_:)`, so
    /// an opted-out user would leak one lifecycle event per launch unless the
    /// preference is applied at setup time rather than immediately afterwards.
    func testOptedOutUserStartsSDKAlreadyOptedOut() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        defaults.set(false, forKey: AnalyticsService.collectionEnabledDefaultsKey)
        service.configure()

        XCTAssertEqual(client.configuredStartOptedOut, true)
    }

    func testOptedInUserStartsSDKCollecting() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()

        XCTAssertEqual(client.configuredStartOptedOut, false)
    }

    func testOnboardingStepEventsCarryStepIdentity() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        service.onboardingStepViewed(.bodyweight)
        service.onboardingStepSkipped(.bodyweight)

        let viewed = client.captures[client.captures.count - 2]
        XCTAssertEqual(viewed.event, "onboarding step viewed")
        XCTAssertEqual(viewed.properties["step"] as? String, "bodyweight")
        XCTAssertEqual(viewed.properties["step_index"] as? Int, 2)

        XCTAssertEqual(client.captures.last?.event, "onboarding step skipped")
        XCTAssertEqual(client.captures.last?.properties["step"] as? String, "bodyweight")
    }

    func testScreenViewedWithoutDataAlsoEmitsEmptyState() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        service.screenViewed(.charts, hasData: false)

        XCTAssertEqual(client.screens.last?.screen, "Charts")
        XCTAssertEqual(client.screens.last?.properties["has_data"] as? Bool, false)
        XCTAssertEqual(client.captures.last?.event, "empty state shown")
        XCTAssertEqual(client.captures.last?.properties["screen_name"] as? String, "Charts")
    }

    func testScreenViewedWithDataDoesNotEmitEmptyState() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        service.screenViewed(.charts, hasData: true)

        XCTAssertTrue(client.captures.isEmpty)
    }

    func testFirstSetLoggedBucketsTimeSinceWorkoutStart() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        service.firstSetLogged(source: .template, secondsSinceStart: 125)

        XCTAssertEqual(client.captures.last?.event, "first set logged")
        XCTAssertEqual(client.captures.last?.properties["elapsed_seconds_bucket"] as? String, "1-3m")
        XCTAssertEqual(client.captures.last?.properties["source"] as? String, "template")
    }

    func testEveryEventStampsAppVersionAndBuildNumber() {
        let (service, client, defaults) = makeService(appVersion: "1.4.2", buildNumber: "312")
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        service.track(.workoutStarted, properties: [.source: .string("empty")])
        service.screen(.home)

        let capture = client.captures.first
        XCTAssertEqual(capture?.properties["app_version"] as? String, "1.4.2")
        XCTAssertEqual(capture?.properties["build_number"] as? String, "312")

        let screen = client.screens.first
        XCTAssertEqual(screen?.properties["app_version"] as? String, "1.4.2")
        XCTAssertEqual(screen?.properties["build_number"] as? String, "312")
    }

    func testImportStartedHelperEmitsSourceAndUnit() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        service.importStarted(sourceType: "fitnotes", unitSystem: "metric")

        XCTAssertEqual(client.captures.last?.event, "import started")
        XCTAssertEqual(client.captures.last?.properties["source_type"] as? String, "fitnotes")
        XCTAssertEqual(client.captures.last?.properties["unit_system"] as? String, "metric")
    }

    func testWorkoutCompletedHelperIncludesEnrichedProperties() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        let calendar = Calendar(identifier: .gregorian)
        let morningTuesday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 19, hour: 7))!

        service.workoutCompleted(
            durationSeconds: 50 * 60,
            completedSetCount: 12,
            exerciseCount: 4,
            totalReps: 80,
            prsHit: 2,
            date: morningTuesday,
            source: .template,
            templateUsed: true,
            unitSystem: "metric",
            perceivedEffortEntered: true,
            notesEntered: false,
            excludedFromProgression: false,
            accessTier: "free",
            remainingFreeWorkouts: 3,
            rirSetCount: 8,
            averageRIR: 2.4
        )

        let capture = client.captures.last
        XCTAssertEqual(capture?.event, "workout completed")
        XCTAssertEqual(capture?.properties["duration_bucket"] as? String, "45-60m")
        XCTAssertEqual(capture?.properties["set_count_bucket"] as? String, "11+")
        XCTAssertEqual(capture?.properties["exercise_count_bucket"] as? String, "4-6")
        XCTAssertEqual(capture?.properties["total_reps_bucket"] as? String, "51-100")
        XCTAssertEqual(capture?.properties["prs_hit"] as? Int, 2)
        XCTAssertEqual(capture?.properties["time_of_day"] as? String, "morning")
        XCTAssertEqual(capture?.properties["day_of_week"] as? String, "tue")
        XCTAssertEqual(capture?.properties["source"] as? String, "template")
        XCTAssertEqual(capture?.properties["template_used"] as? Bool, true)
        XCTAssertEqual(capture?.properties["unit_system"] as? String, "metric")
        XCTAssertEqual(capture?.properties["access_tier"] as? String, "free")
        XCTAssertEqual(capture?.properties["remaining_free_workouts"] as? Int, 3)
        XCTAssertEqual(capture?.properties["rir_entered"] as? Bool, true)
        XCTAssertEqual(capture?.properties["rir_set_count_bucket"] as? String, "7-10")
        XCTAssertEqual(capture?.properties["average_rir_bucket"] as? String, "2")
    }

    func testRIRBucketsBoundaries() {
        XCTAssertEqual(AnalyticsBuckets.rir(0), "0")
        XCTAssertEqual(AnalyticsBuckets.rir(0.4), "0")
        XCTAssertEqual(AnalyticsBuckets.rir(0.5), "1")
        XCTAssertEqual(AnalyticsBuckets.rir(1.4), "1")
        XCTAssertEqual(AnalyticsBuckets.rir(2), "2")
        XCTAssertEqual(AnalyticsBuckets.rir(2.6), "3")
        XCTAssertEqual(AnalyticsBuckets.rir(4.4), "4")
        XCTAssertEqual(AnalyticsBuckets.rir(4.5), "5+")
        XCTAssertEqual(AnalyticsBuckets.rir(7), "5+")
    }

    func testWorkoutCompletedOmitsRIRBucketWhenNoSetsLogged() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 19, hour: 7))!

        service.workoutCompleted(
            durationSeconds: 20 * 60,
            completedSetCount: 4,
            exerciseCount: 2,
            totalReps: 30,
            prsHit: 0,
            date: date,
            source: .empty,
            templateUsed: false,
            unitSystem: "imperial",
            perceivedEffortEntered: false,
            notesEntered: false,
            excludedFromProgression: false,
            accessTier: "subscribed",
            remainingFreeWorkouts: nil,
            rirSetCount: 0,
            averageRIR: nil
        )

        let capture = client.captures.last
        XCTAssertEqual(capture?.properties["access_tier"] as? String, "subscribed")
        XCTAssertNil(capture?.properties["remaining_free_workouts"])
        XCTAssertEqual(capture?.properties["rir_entered"] as? Bool, false)
        XCTAssertEqual(capture?.properties["rir_set_count_bucket"] as? String, "0")
        XCTAssertNil(capture?.properties["average_rir_bucket"])
    }

    func testPaywallShownEmitsBothScreenAndEventWithSource() {
        let (service, client, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        service.configure()
        service.paywallShown(source: .paywall)

        XCTAssertEqual(client.screens.last?.screen, "Paywall")
        XCTAssertEqual(client.screens.last?.properties["source"] as? String, "paywall")
        XCTAssertEqual(client.captures.last?.event, "paywall shown")
        XCTAssertEqual(client.captures.last?.properties["source"] as? String, "paywall")
    }

    func testWorkoutStartContextStoreRoundTrips() {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        WorkoutStartContextStore.remember(
            source: .template,
            templateUsed: true,
            userDefaults: defaults
        )
        let recalled = WorkoutStartContextStore.recall(userDefaults: defaults)
        XCTAssertEqual(recalled.source, .template)
        XCTAssertEqual(recalled.templateUsed, true)

        WorkoutStartContextStore.clear(userDefaults: defaults)
        let cleared = WorkoutStartContextStore.recall(userDefaults: defaults)
        XCTAssertNil(cleared.source)
        XCTAssertNil(cleared.templateUsed)
    }

    func testSessionMarkerReportsFirstSetExactlyOnce() {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        ActiveWorkoutSessionMarker.markStarted(userDefaults: defaults)

        XCTAssertTrue(ActiveWorkoutSessionMarker.markFirstSetLogged(userDefaults: defaults))
        XCTAssertFalse(ActiveWorkoutSessionMarker.markFirstSetLogged(userDefaults: defaults))
        XCTAssertFalse(ActiveWorkoutSessionMarker.markFirstSetLogged(userDefaults: defaults))
    }

    func testSessionMarkerTreatsStaleWorkoutAsAbandoned() {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let start = Date()
        ActiveWorkoutSessionMarker.markStarted(at: start, userDefaults: defaults)

        let withinSession = start.addingTimeInterval(3 * 60 * 60)
        XCTAssertFalse(ActiveWorkoutSessionMarker.isAbandoned(now: withinSession, userDefaults: defaults))

        let nextDay = start.addingTimeInterval(20 * 60 * 60)
        XCTAssertTrue(ActiveWorkoutSessionMarker.isAbandoned(now: nextDay, userDefaults: defaults))
    }

    func testSessionMarkerWithNoWorkoutIsNeverAbandoned() {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        XCTAssertFalse(ActiveWorkoutSessionMarker.isAbandoned(userDefaults: defaults))
    }

    /// The marker has to be cleared by the same call that clears the start
    /// context, otherwise a finished workout would later be reported abandoned.
    func testClearingStartContextAlsoClearsSessionMarker() {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        WorkoutStartContextStore.remember(source: .empty, templateUsed: false, userDefaults: defaults)
        XCTAssertNotNil(ActiveWorkoutSessionMarker.startedAt(userDefaults: defaults))

        WorkoutStartContextStore.clear(userDefaults: defaults)
        XCTAssertNil(ActiveWorkoutSessionMarker.startedAt(userDefaults: defaults))
    }

    func testMissingConfigurationFailsClosed() {
        XCTAssertNil(AnalyticsConfiguration(projectToken: "", host: "https://eu.i.posthog.com"))
        XCTAssertNil(AnalyticsConfiguration(projectToken: "$(POSTHOG_PROJECT_TOKEN)", host: "https://eu.i.posthog.com"))
        XCTAssertFalse(NoopAnalyticsService().isCollectionEnabled)
    }

    private var defaultsSuiteName: String {
        "AnalyticsServiceTests.\(name)"
    }

    private func makeService(
        appVersion: String? = nil,
        buildNumber: String? = nil
    ) -> (
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
            AnalyticsService(
                client: client,
                configuration: configuration,
                userDefaults: defaults,
                appVersion: appVersion,
                buildNumber: buildNumber
            ),
            client,
            defaults
        )
    }
}

@MainActor
final class ReviewPromptServiceTests: XCTestCase {
    private let suiteName = "ReviewPromptServiceTests"

    private func makeService(
        appVersion: String = "1.4.0",
        now: @escaping () -> Date = Date.init
    ) -> (ReviewPromptService, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (
            ReviewPromptService(userDefaults: defaults, appVersion: appVersion, now: now),
            defaults
        )
    }

    func testDoesNotPromptBeforeFirstMilestone() {
        let (service, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for _ in 0..<2 {
            ReviewPromptService.recordCompletedWorkout(userDefaults: defaults)
            XCTAssertFalse(service.shouldRequestReview())
        }
    }

    func testPromptsAtFirstMilestone() {
        let (service, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for _ in 0..<3 {
            ReviewPromptService.recordCompletedWorkout(userDefaults: defaults)
        }

        XCTAssertEqual(service.completedWorkoutCount, 3)
        XCTAssertTrue(service.shouldRequestReview())
    }

    func testDoesNotPromptTwiceOnTheSameVersion() {
        let (service, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for _ in 0..<3 {
            ReviewPromptService.recordCompletedWorkout(userDefaults: defaults)
        }
        XCTAssertTrue(service.shouldRequestReview())

        service.markReviewRequested()
        XCTAssertFalse(service.shouldRequestReview())
    }

    /// A user who trains hard could reach two milestones inside one release.
    /// StoreKit only allows three prompts a year, so we keep our own floor.
    func testEnforcesMinimumGapAcrossVersions() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ReviewPromptService(userDefaults: defaults, appVersion: "1.4.0", now: { day0 })
        for _ in 0..<3 { ReviewPromptService.recordCompletedWorkout(userDefaults: defaults) }
        XCTAssertTrue(first.shouldRequestReview())
        first.markReviewRequested()

        for _ in 0..<9 { ReviewPromptService.recordCompletedWorkout(userDefaults: defaults) }
        XCTAssertEqual(first.completedWorkoutCount, 12)

        let tooSoon = day0.addingTimeInterval(30 * 86_400)
        let second = ReviewPromptService(userDefaults: defaults, appVersion: "1.5.0", now: { tooSoon })
        XCTAssertFalse(second.shouldRequestReview())

        let longEnough = day0.addingTimeInterval(90 * 86_400)
        let third = ReviewPromptService(userDefaults: defaults, appVersion: "1.5.0", now: { longEnough })
        XCTAssertTrue(third.shouldRequestReview())
    }

    func testSessionSuppressionBlocksPrompt() {
        let (service, defaults) = makeService()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for _ in 0..<3 {
            ReviewPromptService.recordCompletedWorkout(userDefaults: defaults)
        }
        XCTAssertTrue(service.shouldRequestReview())

        service.suppressForThisSession()
        XCTAssertFalse(service.shouldRequestReview())
    }

    func testWriteReviewURLTargetsAppStoreReviewForm() {
        let url = ReviewPromptService.writeReviewURL(appStoreID: "123456789")
        XCTAssertEqual(
            url?.absoluteString,
            "https://apps.apple.com/app/id123456789?action=write-review"
        )
    }
}

private final class SpyAnalyticsClient: AnalyticsClientProtocol {
    private(set) var configured: AnalyticsConfiguration?
    private(set) var configuredStartOptedOut: Bool?
    private(set) var captures: [(event: String, properties: [String: Any])] = []
    private(set) var screens: [(screen: String, properties: [String: Any])] = []
    private(set) var optInCount = 0
    private(set) var optOutCount = 0
    private var optedOut = false

    func configure(_ configuration: AnalyticsConfiguration, startOptedOut: Bool) {
        configured = configuration
        configuredStartOptedOut = startOptedOut
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
