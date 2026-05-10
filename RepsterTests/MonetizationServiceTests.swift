import XCTest
@testable import Repster

final class MonetizationServiceTests: XCTestCase {

    func testRevenueCatEntitlementMatchesDashboardIdentifier() {
        XCTAssertEqual(RevenueCatConfiguration.entitlementIdentifier, "Repster")
    }

    func testInactiveUserUsesRemainingFreeWorkoutQuota() async {
        let subscription = StubSubscriptionService(snapshot: .inactive)
        let store = InMemoryWorkoutQuotaStore(consumed: 2)
        let service = AccessControlService(
            subscriptionService: subscription,
            freeWorkoutLimit: 5,
            quotaStore: store
        )

        let snapshot = await service.currentAccessSnapshot()

        XCTAssertEqual(snapshot.state, .free(remaining: 3))
        XCTAssertEqual(snapshot.freeWorkoutsUsed, 2)
    }

    func testRecordingCompletionConsumesOneFreeWorkout() async {
        let subscription = StubSubscriptionService(snapshot: .inactive)
        let store = InMemoryWorkoutQuotaStore(consumed: 4)
        let service = AccessControlService(
            subscriptionService: subscription,
            freeWorkoutLimit: 5,
            quotaStore: store
        )

        let snapshot = await service.recordCompletedWorkoutIfNeeded()

        XCTAssertEqual(snapshot.state, .paywallRequired)
        XCTAssertEqual(snapshot.freeWorkoutsUsed, 5)
        XCTAssertEqual(store.consumed, 5)
    }

    func testRenewableSubscriptionBypassesQuotaAndDoesNotConsumeWorkout() async {
        let subscription = StubSubscriptionService(snapshot: .active, accessSource: .subscription)
        let store = InMemoryWorkoutQuotaStore(consumed: 5)
        let service = AccessControlService(
            subscriptionService: subscription,
            freeWorkoutLimit: 5,
            quotaStore: store
        )

        let canStart = await service.canStartNewWorkout()
        let snapshot = await service.recordCompletedWorkoutIfNeeded()

        XCTAssertTrue(canStart)
        XCTAssertEqual(snapshot.state, .subscribed)
        XCTAssertEqual(store.consumed, 5)
    }

    func testSubscriptionAndLifetimeRequiresCancellationReminder() {
        let snapshot = makeSubscriptionSnapshot(accessSource: .subscriptionAndLifetime)

        XCTAssertTrue(snapshot.hasRenewableSubscription)
        XCTAssertTrue(snapshot.hasLifetimePurchase)
        XCTAssertTrue(snapshot.requiresSubscriptionCancellationReminder)
    }

    func testLifetimeOnlyDoesNotRequireSubscriptionCancellationReminder() {
        let snapshot = makeSubscriptionSnapshot(accessSource: .lifetime)

        XCTAssertFalse(snapshot.hasRenewableSubscription)
        XCTAssertTrue(snapshot.hasLifetimePurchase)
        XCTAssertFalse(snapshot.requiresSubscriptionCancellationReminder)
    }

    private func makeSubscriptionSnapshot(accessSource: SubscriptionAccessSource) -> SubscriptionSnapshot {
        SubscriptionSnapshot(
            status: .active,
            entitlementIdentifier: RevenueCatConfiguration.entitlementIdentifier,
            expirationDate: nil,
            accessSource: accessSource,
            managementURL: nil
        )
    }
}

private actor StubSubscriptionService: SubscriptionServiceProtocol {
    let entitlementIdentifier = RevenueCatConfiguration.entitlementIdentifier
    private let snapshot: SubscriptionSnapshot

    init(snapshot status: SubscriptionStatus, accessSource: SubscriptionAccessSource = .none) {
        self.snapshot = SubscriptionSnapshot(
            status: status,
            entitlementIdentifier: RevenueCatConfiguration.entitlementIdentifier,
            expirationDate: nil,
            accessSource: accessSource,
            managementURL: nil
        )
    }

    func refreshSubscriptionStatus() async -> SubscriptionSnapshot {
        snapshot
    }

    func currentSubscriptionSnapshot() async -> SubscriptionSnapshot {
        snapshot
    }

    func purchaseLifetime() async throws -> SubscriptionSnapshot {
        snapshot
    }

    func restorePurchases() async throws -> SubscriptionSnapshot {
        snapshot
    }

    func openManageSubscriptions() async {}
}

private final class InMemoryWorkoutQuotaStore: WorkoutQuotaStoreProtocol, @unchecked Sendable {
    var consumed: Int

    init(consumed: Int) {
        self.consumed = consumed
    }

    func loadConsumedWorkoutCount() -> Int {
        consumed
    }

    func saveConsumedWorkoutCount(_ count: Int) {
        consumed = count
    }
}
