import Foundation
import RevenueCat
import Security
import UIKit

enum RevenueCatConfiguration {
    static let apiKey: String = {
        let keyName = "REVENUECAT_API_KEY"
        guard let rawKey = Bundle.main.object(forInfoDictionaryKey: keyName) as? String else {
            fatalError("Missing \(keyName) in Info.plist.")
        }

        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("$(") else {
            fatalError("\(keyName) must be set to a RevenueCat public SDK key.")
        }

        guard !key.hasPrefix("sk_") else {
            fatalError("Do not embed RevenueCat secret API keys in the app.")
        }

        #if !DEBUG
        guard !key.hasPrefix("test_") else {
            fatalError("Release builds must use the RevenueCat iOS public SDK key, not a Test Store key.")
        }
        #endif

        return key
    }()
    static let entitlementIdentifier = "Repster"
    static let freeWorkoutLimit = 5
}

enum SubscriptionStatus: Equatable {
    case unknown
    case inactive
    case active
}

enum SubscriptionAccessSource: Equatable {
    case none
    case subscription
    case lifetime
    case subscriptionAndLifetime

    var hasRenewableSubscription: Bool {
        switch self {
        case .subscription, .subscriptionAndLifetime:
            return true
        case .none, .lifetime:
            return false
        }
    }

    var hasLifetimePurchase: Bool {
        switch self {
        case .lifetime, .subscriptionAndLifetime:
            return true
        case .none, .subscription:
            return false
        }
    }
}

struct SubscriptionSnapshot: Equatable {
    let status: SubscriptionStatus
    let entitlementIdentifier: String
    let expirationDate: Date?
    let accessSource: SubscriptionAccessSource
    let managementURL: URL?

    var hasFullAccess: Bool {
        status == .active
    }

    var hasRenewableSubscription: Bool {
        accessSource.hasRenewableSubscription
    }

    var hasLifetimePurchase: Bool {
        accessSource.hasLifetimePurchase
    }

    var requiresSubscriptionCancellationReminder: Bool {
        accessSource == .subscriptionAndLifetime
    }

    static func unknown(entitlementIdentifier: String) -> SubscriptionSnapshot {
        SubscriptionSnapshot(
            status: .unknown,
            entitlementIdentifier: entitlementIdentifier,
            expirationDate: nil,
            accessSource: .none,
            managementURL: nil
        )
    }
}

enum MonetizationError: LocalizedError {
    case missingCurrentOffering
    case missingLifetimePackage
    case purchaseCancelled

    var errorDescription: String? {
        switch self {
        case .missingCurrentOffering:
            return "Lifetime purchase is not available right now. Please try again shortly."
        case .missingLifetimePackage:
            return "Lifetime access is not configured in the current offering yet."
        case .purchaseCancelled:
            return nil
        }
    }
}

enum AccessState: Equatable {
    case subscribed
    case free(remaining: Int)
    case paywallRequired
}

struct AccessSnapshot: Equatable {
    let state: AccessState
    let freeWorkoutLimit: Int
    let freeWorkoutsUsed: Int

    var remainingFreeWorkouts: Int {
        max(0, freeWorkoutLimit - freeWorkoutsUsed)
    }

    var hasFullAccess: Bool {
        if case .subscribed = state {
            return true
        }
        return false
    }

    var requiresPaywall: Bool {
        if case .paywallRequired = state {
            return true
        }
        return false
    }

    static func placeholder(limit: Int) -> AccessSnapshot {
        AccessSnapshot(state: .free(remaining: limit), freeWorkoutLimit: limit, freeWorkoutsUsed: 0)
    }
}

protocol SubscriptionServiceProtocol: Sendable {
    var entitlementIdentifier: String { get }
    func refreshSubscriptionStatus() async -> SubscriptionSnapshot
    func currentSubscriptionSnapshot() async -> SubscriptionSnapshot
    func purchaseLifetime() async throws -> SubscriptionSnapshot
    func restorePurchases() async throws -> SubscriptionSnapshot
    func openManageSubscriptions() async
}

protocol AccessControlServiceProtocol: Sendable {
    var freeWorkoutLimit: Int { get }
    func currentAccessSnapshot() async -> AccessSnapshot
    func currentAccessState() async -> AccessState
    func remainingFreeWorkouts() async -> Int
    func canStartNewWorkout() async -> Bool
    func recordCompletedWorkoutIfNeeded() async -> AccessSnapshot
}

protocol WorkoutQuotaStoreProtocol: Sendable {
    func loadConsumedWorkoutCount() -> Int
    func saveConsumedWorkoutCount(_ count: Int)
}

final class KeychainWorkoutQuotaStore: WorkoutQuotaStoreProtocol, @unchecked Sendable {
    private let service = (Bundle.main.bundleIdentifier ?? "Repster") + ".monetization"
    private let account = "completed_free_workout_count"

    func loadConsumedWorkoutCount() -> Int {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let string = String(data: data, encoding: .utf8),
                  let value = Int(string) else {
                return 0
            }
            return max(0, value)
        case errSecItemNotFound:
            return 0
        default:
            dbg("[Monetization] Keychain read failed: \(status)")
            return 0
        }
    }

    func saveConsumedWorkoutCount(_ count: Int) {
        let normalized = max(0, count)
        let data = Data(String(normalized).utf8)
        let query = baseQuery()

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            dbg("[Monetization] Keychain update failed: \(updateStatus)")
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus != errSecSuccess {
            dbg("[Monetization] Keychain add failed: \(addStatus)")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

actor SubscriptionService: SubscriptionServiceProtocol {
    let entitlementIdentifier: String
    private var cachedSnapshot: SubscriptionSnapshot
    private var customerInfoObservationTask: Task<Void, Never>?

    init(entitlementIdentifier: String = RevenueCatConfiguration.entitlementIdentifier) {
        self.entitlementIdentifier = entitlementIdentifier
        self.cachedSnapshot = .unknown(entitlementIdentifier: entitlementIdentifier)
        Task { await startCustomerInfoObservation() }
    }

    deinit {
        customerInfoObservationTask?.cancel()
    }

    func refreshSubscriptionStatus() async -> SubscriptionSnapshot {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let snapshot = snapshot(from: customerInfo)
            cachedSnapshot = snapshot
            return snapshot
        } catch {
            dbg("[Monetization] Failed to refresh subscription status: \(error)")
            return cachedSnapshot
        }
    }

    func currentSubscriptionSnapshot() async -> SubscriptionSnapshot {
        switch cachedSnapshot.status {
        case .unknown:
            return await refreshSubscriptionStatus()
        case .inactive, .active:
            return cachedSnapshot
        }
    }

    func restorePurchases() async throws -> SubscriptionSnapshot {
        let customerInfo = try await Purchases.shared.restorePurchases()
        let snapshot = snapshot(from: customerInfo)
        cachedSnapshot = snapshot
        return snapshot
    }

    func purchaseLifetime() async throws -> SubscriptionSnapshot {
        let offerings = try await Purchases.shared.offerings()
        guard let currentOffering = offerings.current else {
            throw MonetizationError.missingCurrentOffering
        }

        guard let lifetimePackage = currentOffering.lifetime
            ?? currentOffering.availablePackages.first(where: { $0.packageType == .lifetime }) else {
            throw MonetizationError.missingLifetimePackage
        }

        let purchaseResult = try await Purchases.shared.purchase(package: lifetimePackage)
        if purchaseResult.userCancelled {
            throw MonetizationError.purchaseCancelled
        }

        let snapshot = snapshot(from: purchaseResult.customerInfo)
        cachedSnapshot = snapshot
        return snapshot
    }

    func openManageSubscriptions() async {
        do {
            try await Purchases.shared.showManageSubscriptions()
            return
        } catch {
            let fallbackURL = cachedSnapshot.managementURL
                ?? URL(string: "https://apps.apple.com/account/subscriptions")

            guard let fallbackURL else { return }
            await MainActor.run {
                UIApplication.shared.open(fallbackURL)
            }
        }
    }

    private func snapshot(from customerInfo: CustomerInfo) -> SubscriptionSnapshot {
        Self.makeSnapshot(from: customerInfo, entitlementIdentifier: entitlementIdentifier)
    }

    private func startCustomerInfoObservation() {
        guard customerInfoObservationTask == nil else { return }

        customerInfoObservationTask = Task { [entitlementIdentifier] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                let snapshot = Self.makeSnapshot(
                    from: customerInfo,
                    entitlementIdentifier: entitlementIdentifier
                )
                self.storeCachedSnapshot(snapshot)
            }
        }
    }

    private func storeCachedSnapshot(_ snapshot: SubscriptionSnapshot) {
        cachedSnapshot = snapshot
    }

    private static func makeSnapshot(
        from customerInfo: CustomerInfo,
        entitlementIdentifier: String
    ) -> SubscriptionSnapshot {
        let entitlement = customerInfo.entitlements.all[entitlementIdentifier]
        let hasFullAccess = entitlement?.isActive == true
        let hasLifetimePurchase = hasFullAccess
            && entitlement?.expirationDate == nil
            && entitlement?.willRenew == false
        let hasRenewableSubscription = hasFullAccess && !customerInfo.activeSubscriptions.isEmpty
        let accessSource: SubscriptionAccessSource

        switch (hasRenewableSubscription, hasLifetimePurchase) {
        case (true, true):
            accessSource = .subscriptionAndLifetime
        case (true, false):
            accessSource = .subscription
        case (false, true):
            accessSource = .lifetime
        case (false, false):
            accessSource = .none
        }

        return SubscriptionSnapshot(
            status: hasFullAccess ? .active : .inactive,
            entitlementIdentifier: entitlementIdentifier,
            expirationDate: entitlement?.expirationDate,
            accessSource: accessSource,
            managementURL: customerInfo.managementURL
        )
    }
}

actor AccessControlService: AccessControlServiceProtocol {
    let freeWorkoutLimit: Int

    private let subscriptionService: any SubscriptionServiceProtocol
    private let quotaStore: WorkoutQuotaStoreProtocol

    init(
        subscriptionService: any SubscriptionServiceProtocol,
        freeWorkoutLimit: Int = RevenueCatConfiguration.freeWorkoutLimit,
        quotaStore: WorkoutQuotaStoreProtocol = KeychainWorkoutQuotaStore()
    ) {
        self.subscriptionService = subscriptionService
        self.freeWorkoutLimit = freeWorkoutLimit
        self.quotaStore = quotaStore
    }

    func currentAccessSnapshot() async -> AccessSnapshot {
        let subscription = await subscriptionService.currentSubscriptionSnapshot()
        return makeSnapshot(subscription: subscription)
    }

    func currentAccessState() async -> AccessState {
        let snapshot = await currentAccessSnapshot()
        return snapshot.state
    }

    func remainingFreeWorkouts() async -> Int {
        let snapshot = await currentAccessSnapshot()
        return snapshot.remainingFreeWorkouts
    }

    func canStartNewWorkout() async -> Bool {
        let subscription = await subscriptionService.refreshSubscriptionStatus()
        return !makeSnapshot(subscription: subscription).requiresPaywall
    }

    func recordCompletedWorkoutIfNeeded() async -> AccessSnapshot {
        let subscription = await subscriptionService.refreshSubscriptionStatus()
        guard !subscription.hasFullAccess else {
            return makeSnapshot(subscription: subscription)
        }

        let currentCount = quotaStore.loadConsumedWorkoutCount()
        if currentCount < freeWorkoutLimit {
            quotaStore.saveConsumedWorkoutCount(currentCount + 1)
        }

        return makeSnapshot(subscription: subscription)
    }

    private func makeSnapshot(subscription: SubscriptionSnapshot) -> AccessSnapshot {
        let usedCount = min(quotaStore.loadConsumedWorkoutCount(), freeWorkoutLimit)
        let state: AccessState

        if subscription.hasFullAccess {
            state = .subscribed
        } else {
            let remaining = max(0, freeWorkoutLimit - usedCount)
            state = remaining > 0 ? .free(remaining: remaining) : .paywallRequired
        }

        return AccessSnapshot(
            state: state,
            freeWorkoutLimit: freeWorkoutLimit,
            freeWorkoutsUsed: usedCount
        )
    }
}

actor NoopAccessControlService: AccessControlServiceProtocol {
    let freeWorkoutLimit: Int = RevenueCatConfiguration.freeWorkoutLimit

    func currentAccessSnapshot() async -> AccessSnapshot {
        AccessSnapshot(state: .subscribed, freeWorkoutLimit: freeWorkoutLimit, freeWorkoutsUsed: 0)
    }

    func currentAccessState() async -> AccessState {
        .subscribed
    }

    func remainingFreeWorkouts() async -> Int {
        freeWorkoutLimit
    }

    func canStartNewWorkout() async -> Bool {
        true
    }

    func recordCompletedWorkoutIfNeeded() async -> AccessSnapshot {
        await currentAccessSnapshot()
    }
}
