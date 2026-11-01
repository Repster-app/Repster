// FreeMonthOfferService.swift
// The free month for feedback: who is offered it, the one notification that announces it, and
// the link that redeems it. Scoping: FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md §2.
//
// Who: someone locked out of new workouts who isn't paying — a free user who has used the quota,
// or a subscriber whose subscription ended. They answer three questions and get a month of the
// monthly plan through an Apple offer code. The code is Apple's, never a RevenueCat grant:
// unlocking access outside Apple's purchase system reads close to App Review guideline 3.1.1.
//
// One notification, sent once, 48 h after the app first sees someone eligible. It is not a
// reminder system — those were built and rolled back on 2026-08-09 — and the free-limit sheet
// carries the offer for everyone the notification can't reach.

import Foundation
import Observation
import Security
import UserNotifications

/// What the free-limit sheet offers, if anything.
enum FreeMonthOfferAvailability: Equatable {
    /// Not eligible: paying, still has free workouts, or the status couldn't be read.
    case none
    /// Eligible, and hasn't answered yet.
    case available(CustomerType)
    /// Answered. The code is theirs to redeem whenever they like.
    case answered(CustomerType)

    var customerType: CustomerType? {
        switch self {
        case .none:
            return nil
        case .available(let type), .answered(let type):
            return type
        }
    }
}

/// Where the offer was opened. Raw values are the `entry_point` analytics dimension.
enum FreeMonthOfferEntry: String {
    case sheet
    case notification
}

/// Progress through the offer. Kept in the Keychain beside the free-workout count, so a reinstall
/// neither sends the notification again nor asks the questions twice.
struct FreeMonthOfferState: Codable, Equatable {
    /// When the one notification was decided: scheduled, or skipped for lack of permission. Set
    /// either way, so the decision is only ever made once.
    var notificationDecidedAt: Date?
    var answeredAt: Date?
    var claimTappedAt: Date?
}

enum FreeMonthOfferPolicy {
    static func availability(
        subscription: SubscriptionSnapshot,
        access: AccessSnapshot,
        state: FreeMonthOfferState
    ) -> FreeMonthOfferAvailability {
        // `.unknown` is what an offline launch reports, and it must never produce an offer: a
        // subscriber whose status didn't load would be offered a free month of what they pay for.
        guard subscription.status == .inactive, access.requiresPaywall else { return .none }
        return state.answeredAt == nil
            ? .available(subscription.customerType)
            : .answered(subscription.customerType)
    }

    static func shouldDecideNotification(
        _ availability: FreeMonthOfferAvailability,
        state: FreeMonthOfferState
    ) -> Bool {
        guard case .available = availability else { return false }
        return state.notificationDecidedAt == nil
    }

    static let notificationTitle = "Get a month of Repster free"

    static func notificationBody(for customerType: CustomerType, freeWorkoutLimit: Int) -> String {
        switch customerType {
        case .new:
            return "You've used your \(freeWorkoutLimit) free workouts. Answer 3 quick questions and the next month is on us."
        case .lapsed:
            return "Your subscription has ended. Answer 3 quick questions and the next month is on us."
        }
    }

    /// Apple's offer code link. It opens the App Store with the code filled in, so the user only
    /// confirms. It always goes to the production App Store, never the sandbox.
    static func redeemURL(appID: String, code: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "apps.apple.com"
        components.path = "/redeem"
        components.queryItems = [
            URLQueryItem(name: "ctx", value: "offercodes"),
            URLQueryItem(name: "id", value: appID),
            URLQueryItem(name: "code", value: code)
        ]
        return components.url
    }
}

// MARK: - Notification

protocol FreeMonthNotificationScheduling {
    func authorization() async -> RestTimerAlarmAuthorization
    func schedule(title: String, body: String, after delay: TimeInterval) async
    func cancel()
}

struct UserNotificationFreeMonthScheduler: FreeMonthNotificationScheduling {
    /// The same live read the rest alarm uses, so the two can't disagree about permission.
    func authorization() async -> RestTimerAlarmAuthorization {
        await RestTimerAlarmCoordinator.refreshAuthorization()
    }

    func schedule(title: String, body: String, after delay: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(
            identifier: FreeMonthOfferService.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [FreeMonthOfferService.notificationIdentifier])
    }
}

// MARK: - Storage

protocol FreeMonthOfferStoreProtocol: AnyObject {
    func load() -> FreeMonthOfferState
    func save(_ state: FreeMonthOfferState)
    func reset()
}

final class KeychainFreeMonthOfferStore: FreeMonthOfferStoreProtocol, @unchecked Sendable {
    private let service = (Bundle.main.bundleIdentifier ?? "Repster") + ".monetization"
    private let account = "free_month_offer_state"

    func load() -> FreeMonthOfferState {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let state = try? JSONDecoder().decode(FreeMonthOfferState.self, from: data) else {
            if status != errSecSuccess && status != errSecItemNotFound {
                dbg("[FreeMonthOffer] Keychain read failed: \(status)")
            }
            return FreeMonthOfferState()
        }
        return state
    }

    func save(_ state: FreeMonthOfferState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let query = baseQuery()

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            dbg("[FreeMonthOffer] Keychain update failed: \(updateStatus)")
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus != errSecSuccess {
            dbg("[FreeMonthOffer] Keychain add failed: \(addStatus)")
        }
    }

    func reset() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

// MARK: - Service

@Observable
final class FreeMonthOfferService {
    /// Shared with nothing else: one offer, one pending notification at most.
    static let notificationIdentifier = "freeMonthOffer"
    static let defaultNotificationDelay: TimeInterval = 48 * 60 * 60

    private(set) var availability: FreeMonthOfferAvailability = .none

    private let analytics: any AnalyticsServiceProtocol
    private let store: any FreeMonthOfferStoreProtocol
    private let scheduler: any FreeMonthNotificationScheduling
    private let notificationDelay: TimeInterval
    private let freeWorkoutLimit: Int
    private let now: () -> Date

    init(
        analytics: any AnalyticsServiceProtocol,
        store: any FreeMonthOfferStoreProtocol = KeychainFreeMonthOfferStore(),
        scheduler: any FreeMonthNotificationScheduling = UserNotificationFreeMonthScheduler(),
        notificationDelay: TimeInterval = FreeMonthOfferService.configuredNotificationDelay,
        freeWorkoutLimit: Int = RevenueCatConfiguration.freeWorkoutLimit,
        now: @escaping () -> Date = Date.init
    ) {
        self.analytics = analytics
        self.store = store
        self.scheduler = scheduler
        self.notificationDelay = notificationDelay
        self.freeWorkoutLimit = freeWorkoutLimit
        self.now = now
    }

    static var redeemURL: URL? {
        FreeMonthOfferPolicy.redeemURL(
            appID: RevenueCatConfiguration.appStoreAppID,
            code: RevenueCatConfiguration.freeMonthOfferCode
        )
    }

    /// Called on every monetization refresh — launch, foreground, back from a workout or the
    /// paywall — so it has to be cheap and idempotent. The first refresh that finds someone
    /// eligible decides the notification; every later one only re-reads availability.
    @MainActor
    func refresh(subscription: SubscriptionSnapshot, access: AccessSnapshot) async {
        var state = store.load()
        let subscription = Self.applyingDebugCustomerType(to: subscription)
        let availability = FreeMonthOfferPolicy.availability(
            subscription: subscription,
            access: access,
            state: state
        )
        self.availability = availability

        // Paying again — through the code or the paywall — makes a pending notification wrong.
        if subscription.status == .active, state.notificationDecidedAt != nil {
            scheduler.cancel()
        }

        guard FreeMonthOfferPolicy.shouldDecideNotification(availability, state: state),
              let customerType = availability.customerType else { return }

        // Stamped before the first await: two refreshes often land together (the workout cover
        // closing and the scene becoming active), and only one of them may schedule.
        state.notificationDecidedAt = now()
        store.save(state)

        let permission = await scheduler.authorization()
        if permission == .authorized {
            await scheduler.schedule(
                title: FreeMonthOfferPolicy.notificationTitle,
                body: FreeMonthOfferPolicy.notificationBody(
                    for: customerType,
                    freeWorkoutLimit: freeWorkoutLimit
                ),
                after: notificationDelay
            )
        }
        analytics.freeMonthNotificationScheduled(permission: permission, customerType: customerType)
    }

    /// The questions opened, from the sheet or the notification. A pending notification would
    /// now only repeat what the user is already looking at.
    @MainActor
    func questionsOpened() {
        scheduler.cancel()
    }

    @MainActor
    func questionsCompleted() {
        var state = store.load()
        state.answeredAt = state.answeredAt ?? now()
        store.save(state)
        scheduler.cancel()
        if case .available(let type) = availability {
            availability = .answered(type)
        }
    }

    @MainActor
    func claimTapped() {
        var state = store.load()
        state.claimTappedAt = now()
        store.save(state)
    }
}

// MARK: - DEBUG launch arguments

extension FreeMonthOfferService {
    /// 48 h in release builds. In DEBUG, `-RepsterFreeMonthNotificationDelay N` makes it N seconds.
    static var configuredNotificationDelay: TimeInterval {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: debugNotificationDelayArgument),
           let seconds = TimeInterval(raw), seconds > 0 {
            return seconds
        }
        #endif
        return defaultNotificationDelay
    }

    static func applyingDebugCustomerType(to subscription: SubscriptionSnapshot) -> SubscriptionSnapshot {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: debugCustomerTypeArgument),
           let type = CustomerType(rawValue: raw) {
            var overridden = subscription
            overridden.customerType = type
            return overridden
        }
        #endif
        return subscription
    }

    /// Sends the notification N seconds after the offer is first seen instead of 48 h.
    static let debugNotificationDelayArgument = "RepsterFreeMonthNotificationDelay"
    /// `lapsed` shows the "Your subscription has ended" copy and the "Why did you stop" question
    /// without a real expired subscription. `new` forces the other way.
    static let debugCustomerTypeArgument = "RepsterFreeMonthCustomerType"
    /// `YES` forgets the offer on launch — notification decision, answers and claim — so the
    /// whole flow can be run again. Left on, it resets on every launch.
    static let debugResetArgument = "RepsterFreeMonthReset"

    #if DEBUG
    static func applyDebugLaunchOverride(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: debugResetArgument) else { return }
        KeychainFreeMonthOfferStore().reset()
        UserNotificationFreeMonthScheduler().cancel()
        dbg("[FreeMonthOffer] DEBUG launch override: offer state reset")
    }
    #endif
}
