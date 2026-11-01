import XCTest
@testable import Repster

/// The free month for feedback and the subscriber thank-you
/// (FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md). The routing in `ContentView` has no harness,
/// so these cover the decisions: who is offered what, when the one notification is scheduled or
/// cancelled, what the questions are, and what analytics receives.
@MainActor
final class FreeMonthOfferTests: XCTestCase {

    // MARK: - Customer type

    func testCustomerTypeIsLapsedOnlyForAKnownInactiveEntitlement() {
        XCTAssertEqual(CustomerType.from(entitlementKnown: false, isActive: false), .new)
        XCTAssertEqual(CustomerType.from(entitlementKnown: true, isActive: false), .lapsed)
        XCTAssertEqual(CustomerType.from(entitlementKnown: true, isActive: true), .new)
    }

    func testSnapshotsBuiltWithoutTheNewFieldsDefaultToNewAndFullPrice() {
        let snapshot = SubscriptionSnapshot.unknown(entitlementIdentifier: "Repster")
        XCTAssertEqual(snapshot.customerType, .new)
        XCTAssertFalse(snapshot.isInFreePeriod)
    }

    // MARK: - Availability

    func testLockedFreeUserIsOfferedTheFreeMonth() {
        XCTAssertEqual(availability(subscription(.inactive), locked), .available(.new))
    }

    func testLockedLapsedSubscriberIsOfferedItAsLapsed() {
        XCTAssertEqual(availability(subscription(.inactive, .lapsed), locked), .available(.lapsed))
    }

    func testUnknownStatusNeverGetsTheOffer() {
        // An offline launch. Offering here could offer a subscriber what they already pay for.
        XCTAssertEqual(availability(subscription(.unknown), locked), .none)
    }

    func testPayingUserNeverGetsTheOffer() {
        XCTAssertEqual(availability(subscription(.active), subscribedAccess), .none)
    }

    func testFreeWorkoutsLeftMeansNoOfferYet() {
        // Includes a lapsed subscriber who bought before using up the free workouts: they get the
        // rest of them back first.
        XCTAssertEqual(availability(subscription(.inactive), stillFree), .none)
        XCTAssertEqual(availability(subscription(.inactive, .lapsed), stillFree), .none)
    }

    func testAnsweringTurnsTheOfferIntoAClaim() {
        var state = FreeMonthOfferState()
        state.answeredAt = Date()
        XCTAssertEqual(availability(subscription(.inactive), locked, state), .answered(.new))
    }

    // MARK: - Copy and link

    func testNotificationCopyFollowsTheCustomerType() {
        XCTAssertEqual(
            FreeMonthOfferPolicy.notificationBody(for: .new, freeWorkoutLimit: 10),
            "You've used your 10 free workouts. Answer 3 quick questions and the next month is on us."
        )
        XCTAssertEqual(
            FreeMonthOfferPolicy.notificationBody(for: .lapsed, freeWorkoutLimit: 10),
            "Your subscription has ended. Answer 3 quick questions and the next month is on us."
        )
    }

    func testRedeemLinkIsApplesOfferCodeURL() {
        XCTAssertEqual(
            FreeMonthOfferPolicy.redeemURL(appID: "6766094305", code: "REPSTERMONTH")?.absoluteString,
            "https://apps.apple.com/redeem?ctx=offercodes&id=6766094305&code=REPSTERMONTH"
        )
    }

    func testShippedRedeemLinkUsesTheConfiguredAppAndCode() {
        let url = FreeMonthOfferService.redeemURL?.absoluteString
        XCTAssertEqual(
            url,
            "https://apps.apple.com/redeem?ctx=offercodes&id=\(RevenueCatConfiguration.appStoreAppID)&code=\(RevenueCatConfiguration.freeMonthOfferCode)"
        )
    }

    func testRenewalLineQuotesTheMonthlyPriceOrDropsIt() {
        XCTAssertEqual(
            FeedbackFlowKind.renewalLine(monthlyPrice: "€1.99"),
            "Then €1.99 a month. Cancel anytime in your Apple ID settings."
        )
        XCTAssertEqual(
            FeedbackFlowKind.renewalLine(monthlyPrice: nil),
            "Then it renews monthly. Cancel anytime in your Apple ID settings."
        )
    }

    // MARK: - Service: the one notification

    func testFirstEligibleRefreshSchedulesTheNotificationOnce() async {
        let (service, store, scheduler, analytics) = makeService()

        await service.refresh(subscription: subscription(.inactive), access: locked)
        await service.refresh(subscription: subscription(.inactive), access: locked)

        XCTAssertEqual(service.availability, .available(.new))
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(scheduler.scheduled.first?.title, "Get a month of Repster free")
        XCTAssertEqual(scheduler.scheduled.first?.delay, 120)
        XCTAssertNotNil(store.state.notificationDecidedAt)
        XCTAssertEqual(analytics.events(.freeMonthNotificationScheduled).count, 1)
        XCTAssertEqual(
            analytics.events(.freeMonthNotificationScheduled).first?[.notificationPermission],
            .string("authorized")
        )
    }

    func testLapsedNotificationUsesTheLapsedCopy() async {
        let (service, _, scheduler, analytics) = makeService()

        await service.refresh(subscription: subscription(.inactive, .lapsed), access: locked)

        XCTAssertEqual(
            scheduler.scheduled.first?.body,
            "Your subscription has ended. Answer 3 quick questions and the next month is on us."
        )
        XCTAssertEqual(analytics.events(.freeMonthNotificationScheduled).first?[.customerType], .string("lapsed"))
    }

    func testWithoutPermissionNothingIsScheduledButTheDecisionIsRecordedOnce() async {
        let (service, store, scheduler, analytics) = makeService(permission: .denied)

        await service.refresh(subscription: subscription(.inactive), access: locked)
        await service.refresh(subscription: subscription(.inactive), access: locked)

        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertNotNil(store.state.notificationDecidedAt)
        // The sheet still carries the offer.
        XCTAssertEqual(service.availability, .available(.new))
        XCTAssertEqual(analytics.events(.freeMonthNotificationScheduled).count, 1)
        XCTAssertEqual(
            analytics.events(.freeMonthNotificationScheduled).first?[.notificationPermission],
            .string("denied")
        )
    }

    func testNotEligibleSchedulesNothing() async {
        let (service, store, scheduler, analytics) = makeService()

        await service.refresh(subscription: subscription(.inactive), access: stillFree)
        await service.refresh(subscription: subscription(.unknown), access: locked)
        await service.refresh(subscription: subscription(.active), access: subscribedAccess)

        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertNil(store.state.notificationDecidedAt)
        XCTAssertTrue(analytics.events(.freeMonthNotificationScheduled).isEmpty)
    }

    func testSubscribingCancelsThePendingNotification() async {
        let (service, _, scheduler, _) = makeService()

        await service.refresh(subscription: subscription(.inactive), access: locked)
        XCTAssertEqual(scheduler.cancelCount, 0)

        await service.refresh(subscription: subscription(.active), access: subscribedAccess)

        XCTAssertGreaterThan(scheduler.cancelCount, 0)
        XCTAssertEqual(service.availability, .none)
    }

    func testOpeningTheQuestionsCancelsTheNotification() async {
        let (service, _, scheduler, _) = makeService()
        await service.refresh(subscription: subscription(.inactive), access: locked)

        service.questionsOpened()

        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testAnsweringIsRememberedAndTurnsTheOfferIntoAClaim() async {
        let (service, store, scheduler, _) = makeService()
        await service.refresh(subscription: subscription(.inactive), access: locked)

        service.questionsCompleted()

        XCTAssertNotNil(store.state.answeredAt)
        XCTAssertEqual(service.availability, .answered(.new))
        XCTAssertGreaterThan(scheduler.cancelCount, 0)

        // A later refresh reads the stored answer rather than offering the questions again.
        await service.refresh(subscription: subscription(.inactive), access: locked)
        XCTAssertEqual(service.availability, .answered(.new))
        XCTAssertEqual(scheduler.scheduled.count, 1)
    }

    func testClaimTapIsRecorded() async {
        let (service, store, _, _) = makeService()
        await service.refresh(subscription: subscription(.inactive), access: locked)

        service.claimTapped()

        XCTAssertNotNil(store.state.claimTappedAt)
    }

    // MARK: - Questions

    func testFreeMonthQuestionsForANewCustomer() {
        let questions = FeedbackQuestions.freeMonth(customerType: .new, prices: PlanPrices())
        XCTAssertEqual(questions.map(\.id), ["why_not_upgraded", "miss_most", "plan_choice"])
        XCTAssertEqual(questions[0].text, "What stopped you from upgrading?")
        XCTAssertEqual(
            questions[0].options.map(\.id),
            ["price", "not_sure_worth_it", "prefer_one_time", "something_missing", "didnt_know_limit"]
        )
    }

    func testLapsedCustomersGetTheirOwnFirstQuestion() {
        let questions = FeedbackQuestions.freeMonth(customerType: .lapsed, prices: PlanPrices())
        XCTAssertEqual(questions.map(\.id), ["why_cancelled", "miss_most", "plan_choice"])
        XCTAssertEqual(questions[0].text, "Why did you stop your subscription?")
        XCTAssertEqual(
            questions[0].options.map(\.id),
            ["price", "not_training", "something_missing", "other_app", "didnt_mean_to_cancel"]
        )
    }

    func testPlanQuestionQuotesStorePricesWhenItHasThem() {
        let priced = FeedbackQuestions.freeMonth(
            customerType: .new,
            prices: PlanPrices(monthly: "€1.99", yearly: "€22.99", lifetime: "€34.99")
        )[2]
        XCTAssertEqual(
            priced.options.map(\.label),
            ["Monthly · €1.99", "Yearly · €22.99", "Lifetime · €34.99", "None of these"]
        )
        XCTAssertEqual(priced.options.map(\.id), ["monthly", "yearly", "lifetime", "none"])

        let unpriced = FeedbackQuestions.freeMonth(customerType: .new, prices: PlanPrices())[2]
        XCTAssertEqual(unpriced.options.map(\.label), ["Monthly", "Yearly", "Lifetime", "None of these"])
    }

    func testSubscriberQuestionsEndWithTheEmailFollowUp() {
        let questions = FeedbackQuestions.subscriber
        XCTAssertEqual(questions.map(\.id), ["why_upgraded", "improve_next", FeedbackQuestions.emailFollowUpId])
        XCTAssertEqual(
            questions.last?.options.map(\.id),
            [FeedbackQuestions.emailFollowUpYesId, "not_now"]
        )
    }

    /// Option ids are what analytics records, so two options in one question must never share one.
    func testOptionIdsAreUniqueWithinEveryQuestion() {
        let sets = [
            FeedbackQuestions.freeMonth(customerType: .new, prices: PlanPrices()),
            FeedbackQuestions.freeMonth(customerType: .lapsed, prices: PlanPrices()),
            FeedbackQuestions.subscriber
        ]
        for questions in sets {
            XCTAssertEqual(questions.count, 3)
            for question in questions {
                let ids = question.options.map(\.id)
                XCTAssertEqual(Set(ids).count, ids.count, "duplicate option id in \(question.id)")
            }
        }
    }

    func testFinePrint() {
        let freeMonth = FeedbackFlowKind.freeMonth(.new, PlanPrices())
        XCTAssertEqual(freeMonth.finePrint(at: 0), "Answer all 3 to get your free month. Answers are anonymous.")
        XCTAssertEqual(FeedbackFlowKind.subscriber.finePrint(at: 0), "Answers are anonymous.")
        XCTAssertEqual(
            FeedbackFlowKind.subscriber.finePrint(at: 2),
            "Yes opens an email to the developer. Nothing is sent until you send it."
        )
        XCTAssertEqual(freeMonth.questionSet, .freeMonth)
        XCTAssertEqual(FeedbackFlowKind.subscriber.questionSet, .subscriber)
    }

    // MARK: - Subscriber thank-you

    func testThankYouShowsToAPayingUserWhoEarnedItInAnEarlierVisit() {
        XCTAssertTrue(shouldShowThanks(subscription(.active)))
    }

    func testThankYouStaysHidden() {
        XCTAssertFalse(shouldShowThanks(subscription(.inactive)), "not paying")
        XCTAssertFalse(shouldShowThanks(subscription(.active, freePeriod: true)), "in a free month")
        XCTAssertFalse(shouldShowThanks(subscription(.active), earned: false), "no workout yet")
        XCTAssertFalse(shouldShowThanks(subscription(.active), dismissed: true), "already closed")
        XCTAssertFalse(shouldShowThanks(subscription(.active), reviewPrompt: true), "rating prompt this session")
    }

    func testOnlyASubscribedWorkoutEarnsTheThankYou() {
        let suiteName = "FreeMonthOfferTests.subscriberThanks"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SubscriberThanksPreferences.noteWorkoutFinished(subscribed: false, defaults: defaults)
        XCTAssertFalse(SubscriberThanksPreferences.isEarned(defaults: defaults))

        SubscriberThanksPreferences.noteWorkoutFinished(subscribed: true, defaults: defaults)
        XCTAssertTrue(SubscriberThanksPreferences.isEarned(defaults: defaults))
    }

    // MARK: - Notification taps

    func testRouterHandsOverATapExactlyOnce() {
        let router = NotificationOpenRouter.shared
        _ = router.consume(FreeMonthOfferService.notificationIdentifier)

        router.opened(FreeMonthOfferService.notificationIdentifier)
        XCTAssertFalse(router.consume("somethingElse"))
        XCTAssertTrue(router.consume(FreeMonthOfferService.notificationIdentifier))
        XCTAssertFalse(router.consume(FreeMonthOfferService.notificationIdentifier))
    }

    // MARK: - Analytics

    func testEventNamesAndValuesAreStable() {
        XCTAssertEqual(AnalyticsEvent.freeMonthNotificationScheduled.rawValue, "free month notification scheduled")
        XCTAssertEqual(AnalyticsEvent.freeMonthNotificationOpened.rawValue, "free month notification opened")
        XCTAssertEqual(AnalyticsEvent.freeMonthOfferShown.rawValue, "free month offer shown")
        XCTAssertEqual(AnalyticsEvent.freeMonthClaimTapped.rawValue, "free month claim tapped")
        XCTAssertEqual(AnalyticsEvent.questionsAnswered.rawValue, "questions answered")
        XCTAssertEqual(AnalyticsEvent.questionsCompleted.rawValue, "questions completed")
        XCTAssertEqual(AnalyticsEvent.questionsClosed.rawValue, "questions closed")
        XCTAssertEqual(AnalyticsEvent.subscriberCardShown.rawValue, "subscriber card shown")
        XCTAssertEqual(AnalyticsEvent.subscriberCardClosed.rawValue, "subscriber card closed")
        XCTAssertEqual(FreeLimitSheetResult.answerQuestions.rawValue, "answer_questions")
        XCTAssertEqual(FreeLimitSheetResult.claimFreeMonth.rawValue, "claim_free_month")
        XCTAssertEqual(FeedbackQuestionSet.freeMonth.rawValue, "free_month")
        XCTAssertEqual(FeedbackQuestionSet.subscriber.rawValue, "subscriber")
        XCTAssertEqual(RestTimerAlarmAuthorization.notDetermined.analyticsValue, "not_determined")
    }

    func testEventsCarryOnlyFixedIds() {
        let analytics = RecordingAnalytics()

        analytics.freeMonthOfferShown(entry: .notification, customerType: .lapsed)
        XCTAssertEqual(analytics.events(.freeMonthOfferShown).last?[.entryPoint], .string("notification"))
        XCTAssertEqual(analytics.events(.freeMonthOfferShown).last?[.customerType], .string("lapsed"))

        analytics.questionsAnswered(questionSet: .freeMonth, questionId: "why_cancelled", answer: "price")
        XCTAssertEqual(analytics.events(.questionsAnswered).last, [
            .questionSet: .string("free_month"),
            .questionId: .string("why_cancelled"),
            .answer: .string("price")
        ])

        analytics.questionsClosed(questionSet: .subscriber, lastQuestionId: "improve_next")
        XCTAssertEqual(analytics.events(.questionsClosed).last?[.lastQuestionId], .string("improve_next"))

        analytics.subscriberCardClosed(result: .email)
        XCTAssertEqual(analytics.events(.subscriberCardClosed).last?[.result], .string("email"))
    }

    // MARK: - Helpers

    private let locked = AccessSnapshot(state: .paywallRequired, freeWorkoutLimit: 10, freeWorkoutsUsed: 10)
    private let stillFree = AccessSnapshot(state: .free(remaining: 3), freeWorkoutLimit: 10, freeWorkoutsUsed: 7)
    private let subscribedAccess = AccessSnapshot(state: .subscribed, freeWorkoutLimit: 10, freeWorkoutsUsed: 10)

    private func subscription(
        _ status: SubscriptionStatus,
        _ customerType: CustomerType = .new,
        freePeriod: Bool = false
    ) -> SubscriptionSnapshot {
        SubscriptionSnapshot(
            status: status,
            entitlementIdentifier: RevenueCatConfiguration.entitlementIdentifier,
            expirationDate: nil,
            accessSource: status == .active ? .subscription : .none,
            managementURL: nil,
            customerType: customerType,
            isInFreePeriod: freePeriod
        )
    }

    private func availability(
        _ subscription: SubscriptionSnapshot,
        _ access: AccessSnapshot,
        _ state: FreeMonthOfferState = FreeMonthOfferState()
    ) -> FreeMonthOfferAvailability {
        FreeMonthOfferPolicy.availability(subscription: subscription, access: access, state: state)
    }

    private func shouldShowThanks(
        _ subscription: SubscriptionSnapshot,
        earned: Bool = true,
        dismissed: Bool = false,
        reviewPrompt: Bool = false
    ) -> Bool {
        SubscriberThanksPolicy.shouldShow(
            subscription: subscription,
            earnedBeforeThisForeground: earned,
            dismissed: dismissed,
            reviewPromptRequestedThisSession: reviewPrompt
        )
    }

    private func makeService(
        permission: RestTimerAlarmAuthorization = .authorized
    ) -> (FreeMonthOfferService, InMemoryFreeMonthOfferStore, SpyFreeMonthScheduler, RecordingAnalytics) {
        let store = InMemoryFreeMonthOfferStore()
        let scheduler = SpyFreeMonthScheduler(permission: permission)
        let analytics = RecordingAnalytics()
        let service = FreeMonthOfferService(
            analytics: analytics,
            store: store,
            scheduler: scheduler,
            notificationDelay: 120,
            freeWorkoutLimit: 10
        )
        return (service, store, scheduler, analytics)
    }
}

private final class InMemoryFreeMonthOfferStore: FreeMonthOfferStoreProtocol {
    var state = FreeMonthOfferState()

    func load() -> FreeMonthOfferState {
        state
    }

    func save(_ state: FreeMonthOfferState) {
        self.state = state
    }

    func reset() {
        state = FreeMonthOfferState()
    }
}

private final class SpyFreeMonthScheduler: FreeMonthNotificationScheduling {
    struct Scheduled {
        let title: String
        let body: String
        let delay: TimeInterval
    }

    let permission: RestTimerAlarmAuthorization
    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelCount = 0

    init(permission: RestTimerAlarmAuthorization) {
        self.permission = permission
    }

    func authorization() async -> RestTimerAlarmAuthorization {
        permission
    }

    func schedule(title: String, body: String, after delay: TimeInterval) async {
        scheduled.append(Scheduled(title: title, body: body, delay: delay))
    }

    func cancel() {
        cancelCount += 1
    }
}

private final class RecordingAnalytics: AnalyticsServiceProtocol {
    private var captured: [(event: AnalyticsEvent, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue])] = []

    var isCollectionEnabled: Bool { true }

    func configure() {}
    func setCollectionEnabled(_ enabled: Bool) {}
    func screen(_ screen: AnalyticsScreen, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) {}
    func captureError(_ error: Error, context: AnalyticsErrorContext) {}

    func track(_ event: AnalyticsEvent, properties: [AnalyticsPropertyKey: AnalyticsPropertyValue]) {
        captured.append((event, properties))
    }

    func events(_ event: AnalyticsEvent) -> [[AnalyticsPropertyKey: AnalyticsPropertyValue]] {
        captured.filter { $0.event == event }.map { $0.properties }
    }
}
