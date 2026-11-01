// SubscriberThanks.swift
// When Home shows the one-time thank-you card to a paying user, and what it remembers.
// Scoping: FREE_MONTH_AND_SUBSCRIBER_FEEDBACK_SCOPING.md §3.
//
// Earned by finishing a workout while subscribed, then shown from the next time the app comes to
// the foreground — never in the moment right after the workout, which already belongs to the
// Apple Health offer and the App Store rating prompt. Gone for good after any of its buttons.

import Foundation

enum SubscriberThanksPreferences {
    static let earnedKey = "subscriberThanks.earned"

    /// No dot, unlike `earnedKey`, because this one is bound with `@AppStorage`. A dotted key
    /// re-renders the view holding it on every `UserDefaults` write, and that view is `ContentView`:
    /// the rest timer saves once a second, which refreshed every open menu on the workout screen
    /// (measured 2026-11-01).
    static let dismissedKey = "subscriberThanksDismissed"

    /// Static and nonisolated, like `ReviewPromptService.recordCompletedWorkout`, so the call in
    /// the workout finish path stays one line with no new dependency.
    static func noteWorkoutFinished(subscribed: Bool, defaults: UserDefaults = .standard) {
        guard subscribed else { return }
        defaults.set(true, forKey: earnedKey)
    }

    static func isEarned(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: earnedKey)
    }

    #if DEBUG
    /// `-RepsterSubscriberThanksPreview YES` shows the card whatever the subscription, for
    /// checking it on screen without a sandbox purchase.
    static let debugPreviewArgument = "RepsterSubscriberThanksPreview"

    static var isDebugPreviewEnabled: Bool {
        UserDefaults.standard.bool(forKey: debugPreviewArgument)
    }
    #endif
}

enum SubscriberThanksPolicy {
    static func shouldShow(
        subscription: SubscriptionSnapshot,
        earnedBeforeThisForeground: Bool,
        dismissed: Bool,
        reviewPromptRequestedThisSession: Bool
    ) -> Bool {
        // "Thanks for supporting" reads oddly to someone in a free month they haven't paid for.
        subscription.hasFullAccess
            && !subscription.isInFreePeriod
            && earnedBeforeThisForeground
            && !dismissed
            && !reviewPromptRequestedThisSession
    }
}
