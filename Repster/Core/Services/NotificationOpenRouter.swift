// NotificationOpenRouter.swift
// Hands a tapped notification to the screen that should open for it.
//
// `RestTimerAlarmCoordinator` owns the app's one notification delegate and only makes decisions
// about the rest alarm. A tap on any other notification lands here, and `ContentView` picks it up:
// straight away when it is on screen, or on launch when the tap is what started the app — the
// delegate can hear about that tap before or after the first `.task` runs, so it is held until
// someone takes it.

import Foundation
import Observation

@MainActor
@Observable
final class NotificationOpenRouter {
    static let shared = NotificationOpenRouter()

    /// The identifier of a tapped notification nobody has handled yet.
    private(set) var pendingIdentifier: String?

    private init() {}

    func opened(_ identifier: String) {
        pendingIdentifier = identifier
    }

    /// Takes the pending tap if it is `identifier`, so it is handled exactly once.
    func consume(_ identifier: String) -> Bool {
        guard pendingIdentifier == identifier else { return false }
        pendingIdentifier = nil
        return true
    }
}
