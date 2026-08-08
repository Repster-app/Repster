// ReviewPromptService.swift
// Decides when to ask for an App Store rating.
//
// Apple's rules shape this design:
//   - The prompt must never be attached to a button. A "Rate Repster" button has
//     to deep-link to the App Store write-review URL instead (see `writeReviewURL`).
//   - StoreKit silently throttles to 3 prompts per 365 days, so asking at a bad
//     moment doesn't just annoy the user, it burns one of three annual chances.
//   - Nothing may be gated behind or incentivised by the prompt.
//
// So the job here is to spend those chances on genuinely good moments: a user who
// has finished several workouts, is not mid-paywall, and just closed a summary.

import Foundation

@MainActor
protocol ReviewPromptServiceProtocol {
    /// Whether this is a good moment to ask. Does not mutate state.
    func shouldRequestReview() -> Bool

    /// Records that the prompt was handed to StoreKit. Call even if the system
    /// swallowed it — we can't tell, and assuming it showed is the safe bet.
    func markReviewRequested()

    /// Suppresses the prompt for the rest of this app session. Used after the
    /// paywall appears, so we never ask for a rating right after asking for money.
    func suppressForThisSession()

    var completedWorkoutCount: Int { get }
}

@MainActor
final class ReviewPromptService: ReviewPromptServiceProtocol {
    static let completedWorkoutCountKey = "reviewPromptCompletedWorkoutCount"
    static let lastRequestedVersionKey = "reviewPromptLastRequestedVersion"
    static let lastRequestedAtKey = "reviewPromptLastRequestedAt"

    /// Completed-workout counts that earn a prompt. The first is deliberately not
    /// workout 1 — someone who logged a single workout has no basis for a rating,
    /// and that's exactly the user most likely to leave one star and churn.
    static let milestones: Set<Int> = [3, 12, 30]

    /// Our own floor on top of StoreKit's throttle, so two milestones reached in
    /// one heavy training month don't spend two of the three annual prompts.
    static let minimumDaysBetweenRequests = 60

    private let userDefaults: UserDefaults
    private let appVersion: String
    private let now: () -> Date

    private var suppressedForSession = false

    init(
        userDefaults: UserDefaults = .standard,
        appVersion: String = Bundle.infoDictionaryString("CFBundleShortVersionString"),
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        self.now = now
    }

    var completedWorkoutCount: Int {
        userDefaults.integer(forKey: Self.completedWorkoutCountKey)
    }

    /// Increments the lifetime completed-workout counter. Static and nonisolated so
    /// the call site inside the workout finish path stays a single line with no
    /// actor hop and no new dependency threaded through the view model.
    ///
    /// This is a lifetime counter, deliberately separate from the free-tier quota
    /// in `MonetizationService`, which caps at 5 and stops moving after purchase.
    static func recordCompletedWorkout(userDefaults: UserDefaults = .standard) {
        let current = userDefaults.integer(forKey: completedWorkoutCountKey)
        userDefaults.set(current + 1, forKey: completedWorkoutCountKey)
    }

    func shouldRequestReview() -> Bool {
        guard !suppressedForSession else { return false }
        guard Self.milestones.contains(completedWorkoutCount) else { return false }

        // Never ask twice on the same build — a user who ignored it once on this
        // version has effectively answered.
        if userDefaults.string(forKey: Self.lastRequestedVersionKey) == appVersion {
            return false
        }

        if let lastRequestedAt = userDefaults.object(forKey: Self.lastRequestedAtKey) as? Date {
            let elapsedDays = now().timeIntervalSince(lastRequestedAt) / 86_400
            if elapsedDays < Double(Self.minimumDaysBetweenRequests) {
                return false
            }
        }

        return true
    }

    func markReviewRequested() {
        userDefaults.set(appVersion, forKey: Self.lastRequestedVersionKey)
        userDefaults.set(now(), forKey: Self.lastRequestedAtKey)
    }

    func suppressForThisSession() {
        suppressedForSession = true
    }

    /// Destination for an explicit "Rate Repster" button in Settings. StoreKit's
    /// `requestReview` must not be used for that — Apple requires user-initiated
    /// rating flows to go to the App Store.
    static func writeReviewURL(appStoreID: String) -> URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}

private extension Bundle {
    static func infoDictionaryString(_ key: String) -> String {
        main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }
}
