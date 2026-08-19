// RestTimerAlarmCoordinator.swift
// Owns the rest timer's local notification: scheduling, cancellation, and the decision
// about whether to show a banner when one arrives while Repster is in the foreground.
// Scoping: REST_TIMER_ALARM_SCOPING.md §D1, §D5
//
// Why this exists at all. The rest alarm used to live entirely inside
// `ActiveWorkoutViewModel`, which `ActiveWorkoutView` owns as `@State`. Tapping the header
// back chevron dismisses that `fullScreenCover`, deallocates the ViewModel and kills the
// Combine tick — while the workout deliberately stays active. The scheduled notification
// survives, but iOS suppresses foreground notifications unless a delegate says otherwise,
// and no delegate was ever set. The result was a rest timer that expired in total silence
// whenever the user backed out of the workout screen without leaving the app.
//
// Two jobs, therefore:
//   1. Be the `UNUserNotificationCenterDelegate`, so a foreground alarm can be presented.
//   2. Hold the notification identifier somewhere reachable, so teardown paths that run
//      outside the ViewModel (`ContentView.discardActiveAndCopy`, `SettingsService`) can
//      cancel a pending alarm instead of letting it fire for a workout that is gone.

import Foundation
import UserNotifications

/// Whether the rest alarm can actually reach the user.
///
/// Deliberately three-valued. `notDetermined` is the only state in which asking is still
/// possible — iOS shows its permission sheet once per install and never again — so collapsing it
/// into `denied` would throw away the single chance to explain first.
enum RestTimerAlarmAuthorization: String, Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

enum RestTimerAlarmPreferences {
    /// Mirrors the live authorization so view bodies and the alert path can read it
    /// synchronously. Same trick, same reason, as `HealthKitPreferences`.
    static let authorizationKey = "restTimerAlarm.authorization"
    /// Set once Repster has explained the alarm in its own UI, so a decline is not re-asked.
    static let hasBeenOfferedKey = "restTimerAlarm.hasBeenOffered"

    static var lastKnownAuthorization: RestTimerAlarmAuthorization {
        guard let raw = UserDefaults.standard.string(forKey: authorizationKey),
              let value = RestTimerAlarmAuthorization(rawValue: raw) else {
            return .notDetermined
        }
        return value
    }

    static var hasBeenOffered: Bool {
        UserDefaults.standard.bool(forKey: hasBeenOfferedKey)
    }

    static func store(_ authorization: RestTimerAlarmAuthorization) {
        UserDefaults.standard.set(authorization.rawValue, forKey: authorizationKey)
    }

    static func markOffered() {
        UserDefaults.standard.set(true, forKey: hasBeenOfferedKey)
    }
}

/// Implemented by whoever will alert the user in-app when the rest timer reaches zero.
///
/// The coordinator holds this **weakly** and deliberately asks nothing else about it. A
/// ViewModel that has been deallocated — the back-button case above — nils the reference on
/// its own, with no teardown call to forget and no view lifecycle to get wrong.
@MainActor
protocol RestTimerForegroundAlerting: AnyObject {
    /// `true` when a live timer will fire the in-app alert itself, making a banner redundant.
    var willAlertRestTimerInApp: Bool { get }
}

@MainActor
final class RestTimerAlarmCoordinator: NSObject {

    /// A singleton because `UNUserNotificationCenter.delegate` is a weak, process-wide slot
    /// that must be filled during launch. The decision logic is a static pure function so
    /// it stays testable without one.
    static let shared = RestTimerAlarmCoordinator()

    /// Shared with nothing else — one pending rest alarm at a time, replaced on every
    /// reschedule rather than accumulating.
    nonisolated static let notificationId = "restTimerComplete"

    private weak var foregroundAlerter: (any RestTimerForegroundAlerting)?

    /// When the in-app alert last fired. See `inAppAlertGrace`.
    private var lastInAppAlertAt: Date?

    /// How long after an in-app alert a rest notification counts as the same event.
    ///
    /// `timerTick()` sets `restTimer = .finished` *before* it fires the alert, and the pending
    /// notification is cancelled a line later — but cancelling only removes a request iOS has
    /// not committed to yet. When it has, `willPresent` runs with the state already `.finished`,
    /// so asking "will anything alert in-app?" answers *no* about an alert that has this instant
    /// happened, and the user gets both. That is the double alert; the window is sub-second,
    /// which is why it shows up once and then refuses to reproduce.
    ///
    /// Five seconds is far wider than the race and costs nothing: the only thing that could be
    /// wrongly suppressed is a second rest alarm within five seconds of the first, and there is
    /// only ever one rest timer.
    private static let inAppAlertGrace: TimeInterval = 5

    private override init() {
        super.init()
    }

    /// Claim the delegate slot. Must run during app launch, before the first notification
    /// can be delivered.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Foreground handoff

    func registerForegroundAlerter(_ alerter: any RestTimerForegroundAlerting) {
        foregroundAlerter = alerter
    }

    /// Identity-checked so a ViewModel tearing down *after* its replacement registered
    /// cannot clear the newer one. SwiftUI can briefly hold both across a cover transition.
    func resignForegroundAlerter(_ alerter: any RestTimerForegroundAlerting) {
        if foregroundAlerter === alerter {
            foregroundAlerter = nil
        }
    }

    // MARK: - Scheduling
    //
    // `nonisolated` because `UNUserNotificationCenter` is thread-safe and two of the callers
    // are not on the main actor: `SettingsService` is an actor, and cancellation on a
    // teardown path should never have to wait for a main-actor hop to land.

    /// Schedule the alarm for `seconds` from now, replacing any pending one.
    /// A `nil`/`"off"` alert mode schedules nothing and clears what's pending.
    nonisolated static func schedule(seconds: Int, alertMode: String) {
        guard alertMode != "off" else {
            cancel()
            return
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])

        let content = UNMutableNotificationContent()
        content.title = "Rest Timer"
        content.body = "Rest period is over — time for your next set!"
        content.sound = usesSystemSound(for: alertMode) ? .default : nil

        // A rest timer ending is the textbook time-sensitive notification, and Focus modes are
        // the normal state during a workout — at the default `.active` level iOS delivers this
        // quietly and the alarm is silent for anyone training with Focus on.
        //
        // This is inert until `com.apple.developer.usernotifications.time-sensitive` is on the
        // App ID and in the entitlements file; without it iOS silently downgrades to `.active`,
        // which is exactly today's behaviour. Safe to ship ahead of the provisioning work.
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, TimeInterval(seconds)),
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger))
    }

    /// Cancel any pending rest alarm. Safe to call when there is none.
    nonisolated static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId])
    }

    nonisolated static func usesSystemSound(for alertMode: String) -> Bool {
        switch alertMode {
        case "off":
            return false
        case "vibration", "sound", "both":
            // Local notifications do not produce a background vibration if no
            // sound is attached, so "vibration" still needs the system alert.
            return true
        default:
            return true
        }
    }

    // MARK: - Authorization

    /// Read the live status from iOS and cache it for synchronous readers.
    @discardableResult
    nonisolated static func refreshAuthorization() async -> RestTimerAlarmAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let value = authorization(for: settings.authorizationStatus)
        RestTimerAlarmPreferences.store(value)
        return value
    }

    /// Show the system permission sheet. Call only from an explicit user action — iOS spends
    /// the one prompt this install gets whether or not the user was ready for it.
    @discardableResult
    nonisolated static func requestAuthorization() async -> RestTimerAlarmAuthorization {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        let value: RestTimerAlarmAuthorization = granted ? .authorized : .denied
        RestTimerAlarmPreferences.store(value)
        return value
    }

    nonisolated static func authorization(
        for status: UNAuthorizationStatus
    ) -> RestTimerAlarmAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            // Provisional delivers quietly to Notification Centre rather than not at all, but
            // for this purpose — will the user be told rest is over — quiet is not reaching them.
            return status == .provisional ? .denied : .authorized
        @unknown default:
            return .denied
        }
    }

    /// Whether a *backgrounded* rest timer expiry will announce itself.
    ///
    /// The one caller that matters is `recalculateTimerAfterBackground`, which stays silent on
    /// return because "the notification already alerted them". That is only true when this is
    /// `true`; when it is `false` the user got nothing at all, and late is better than never.
    nonisolated static var canAlertFromBackground: Bool {
        RestTimerAlarmPreferences.lastKnownAuthorization == .authorized
    }

    // MARK: - Foreground presentation

    /// Whether a foreground alarm should be shown, given that something in-app may already
    /// be handling it.
    ///
    /// Suppressing rather than always presenting is deliberate. The Combine tick and the
    /// notification trigger are scheduled for the same instant and race every single set, so
    /// "always present" would drop a banner over the workout screen most of the time — while
    /// the in-app sound and haptic played underneath it.
    nonisolated static func presentationOptions(
        hasInAppAlerter: Bool,
        lastInAppAlertAt: Date? = nil,
        now: Date = .now
    ) -> UNNotificationPresentationOptions {
        // Past tense first: something already alerted for this timer.
        if let lastInAppAlertAt, now.timeIntervalSince(lastInAppAlertAt) < inAppAlertGrace {
            return []
        }
        // Then future tense: something is about to.
        return hasInAppAlerter ? [] : [.banner, .sound, .list]
    }

    /// Called by the in-app alert as it fires, so a notification already in flight for the same
    /// expiry is recognised as a duplicate rather than presented on top of it.
    ///
    /// Lives on the coordinator rather than the ViewModel deliberately: it then also covers a
    /// ViewModel that alerts while a *newer* one holds the registration, which SwiftUI can
    /// briefly produce across a cover transition.
    func noteInAppAlertFired(at date: Date = .now) {
        lastInAppAlertAt = date
    }

    /// Test seam. This object is a process-wide singleton, so the marker outlives any one test
    /// case and would otherwise leak suppression into whichever test ran next.
    func resetInAppAlertMarker() {
        lastInAppAlertAt = nil
    }

    /// What the delegate would return for the rest alarm right now.
    ///
    /// Split out from the delegate callback so the weak-reference behaviour — the whole point
    /// of the design — can be tested without manufacturing a `UNNotification`, which has no
    /// public initialiser.
    func currentPresentationOptions(now: Date = .now) -> UNNotificationPresentationOptions {
        Self.presentationOptions(
            hasInAppAlerter: foregroundAlerter?.willAlertRestTimerInApp ?? false,
            lastInAppAlertAt: lastInAppAlertAt,
            now: now
        )
    }
}

extension RestTimerAlarmCoordinator: UNUserNotificationCenterDelegate {

    /// Anything that isn't the rest alarm is presented normally — this delegate exists only
    /// to make a decision about the alarm, not to become a gatekeeper for future features.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier == Self.notificationId else {
            return [.banner, .sound, .list]
        }
        return currentPresentationOptions()
    }
}
