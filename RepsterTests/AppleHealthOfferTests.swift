import XCTest
@testable import Repster

/// The Apple Health offer is raised on the user's behalf rather than at their request, so
/// the only thing standing between it and a prompt that reappears after every workout is
/// the one-shot flag. 1.4 raised it during onboarding and 6 of 9 people declined; 1.5
/// moved it to the first completed workout, which means it now sits on a path the user
/// walks repeatedly. These pin the rule.
final class AppleHealthOfferTests: XCTestCase {

    // MARK: - The rule

    func testOffersOnlyOnAFreshCapableDevice() {
        XCTAssertTrue(HealthKitPreferences.shouldOffer(
            isAvailable: true, isEnabled: false, hasBeenOffered: false
        ))
    }

    /// The requirement in one test: once asked, never again — whichever way it was
    /// answered, and whether or not it was answered at all.
    func testNeverOffersTwice() {
        XCTAssertFalse(HealthKitPreferences.shouldOffer(
            isAvailable: true, isEnabled: false, hasBeenOffered: true
        ))
    }

    /// Someone already connected is not a candidate, even on a device where the flag was
    /// never written — a backup restore or a hand-edited default could produce that pair.
    func testDoesNotOfferWhenAlreadyConnected() {
        XCTAssertFalse(HealthKitPreferences.shouldOffer(
            isAvailable: true, isEnabled: true, hasBeenOffered: false
        ))
    }

    func testDoesNotOfferWithoutHealthKit() {
        XCTAssertFalse(HealthKitPreferences.shouldOffer(
            isAvailable: false, isEnabled: false, hasBeenOffered: false
        ))
        XCTAssertFalse(HealthKitPreferences.shouldOffer(
            isAvailable: false, isEnabled: false, hasBeenOffered: true
        ))
    }

    /// Availability is the only input that can turn the offer back on, and it can't change
    /// on a given device. Enumerated so a future edit to the rule has to come through here.
    func testAvailableAndUnansweredIsTheOnlyOfferingState() {
        for isAvailable in [true, false] {
            for isEnabled in [true, false] {
                for hasBeenOffered in [true, false] {
                    let expected = isAvailable && !isEnabled && !hasBeenOffered
                    XCTAssertEqual(
                        HealthKitPreferences.shouldOffer(
                            isAvailable: isAvailable,
                            isEnabled: isEnabled,
                            hasBeenOffered: hasBeenOffered
                        ),
                        expected,
                        "available=\(isAvailable) enabled=\(isEnabled) offered=\(hasBeenOffered)"
                    )
                }
            }
        }
    }

    // MARK: - Every exit spends the offer

    /// `AppleHealthConnectionModel` is the only thing any surface calls, so if both of its
    /// terminal paths mark the offer spent, no surface can ask twice by forgetting to.
    ///
    /// Touches `UserDefaults.standard` because `HealthKitPreferences` writes there — the
    /// Settings screen binds the same keys through `@AppStorage`, so it can't be moved to
    /// a suite. Saved and restored around each test instead.
    private var savedOffered: Any?
    private var savedEnabled: Any?

    override func setUp() {
        super.setUp()
        savedOffered = UserDefaults.standard.object(forKey: HealthKitPreferences.hasBeenOfferedKey)
        savedEnabled = UserDefaults.standard.object(forKey: HealthKitPreferences.enabledKey)
        UserDefaults.standard.removeObject(forKey: HealthKitPreferences.hasBeenOfferedKey)
        UserDefaults.standard.removeObject(forKey: HealthKitPreferences.enabledKey)
    }

    override func tearDown() {
        restore(savedOffered, forKey: HealthKitPreferences.hasBeenOfferedKey)
        restore(savedEnabled, forKey: HealthKitPreferences.enabledKey)
        super.tearDown()
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @MainActor
    func testDeclineSpendsTheOffer() {
        XCTAssertFalse(HealthKitPreferences.hasBeenOffered)

        makeModel().decline()

        XCTAssertTrue(
            HealthKitPreferences.hasBeenOffered,
            "\"Not now\" has to spend the offer, or the prompt returns after the next workout"
        )
    }

    /// Reaching HealthKit at all counts, including when it answers unfavourably. The point
    /// of the flag is that the user was asked, not that they said yes.
    @MainActor
    func testConnectSpendsTheOfferEvenWhenItFails() async {
        XCTAssertFalse(HealthKitPreferences.hasBeenOffered)

        let connected = await makeModel().connect()

        XCTAssertFalse(connected, "NoopHealthKitService reports HealthKit as unavailable")
        XCTAssertTrue(HealthKitPreferences.hasBeenOffered)
        XCTAssertFalse(HealthKitPreferences.isEnabled)
    }

    @MainActor
    private func makeModel() -> AppleHealthConnectionModel {
        AppleHealthConnectionModel(
            healthKitService: NoopHealthKitService(),
            analyticsService: NoopAnalyticsService(),
            source: .workoutFinish
        )
    }
}
