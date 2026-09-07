// WhatsNewRelease.swift
// The hand-written catalogue of changes worth telling people about.
//
// Silence is the default and not a gap to fill: `current` returning nil means no sheet
// appears at all, which is the right outcome for most releases. PRE_1.4_CHECKLIST.md §3.3
// carries the test an item has to pass — can the user go and look at it in ten seconds —
// and the reasoning for capping at three.

import Foundation

// MARK: - Item

struct WhatsNewItem: Identifiable {

    /// The one thing an item may offer beyond describing itself. Most items have none;
    /// a "What's New" that asks for something on every row is a pitch, not a changelog.
    enum Action: Equatable {
        /// Offers the Apple Health integration in the row itself. Resolved against
        /// `HealthKitPreferences` when the sheet renders rather than baked in here, so
        /// reopening from Settings can't show a live Connect button to someone who has
        /// already answered.
        case connectAppleHealth
    }

    enum Tint {
        case accent, gold, red, green
    }

    let id: String
    let systemImage: String
    let tint: Tint
    let title: String
    let body: String
    let action: Action?

    init(
        id: String,
        systemImage: String,
        tint: Tint,
        title: String,
        body: String,
        action: Action? = nil
    ) {
        self.id = id
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.body = body
        self.action = action
    }
}

// MARK: - Release

struct WhatsNewRelease {

    /// Matched against `CFBundleShortVersionString` by equality, never by ordering — a
    /// version rolled back in TestFlight should still show its sheet once.
    let version: String
    let items: [WhatsNewItem]

    static let all: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: "1.5",
            items: [
                WhatsNewItem(
                    id: "supersets",
                    systemImage: "link",
                    tint: .accent,
                    // First because it is the only genuinely new capability in the release, and
                    // the only one nobody finds by accident — templates and the summary screen
                    // announce themselves by looking different.
                    title: "Supersets",
                    body: "Repster now supports supersets — find them in templates, during the workout, and in your history."
                ),
                WhatsNewItem(
                    id: "smarter_suggestions",
                    systemImage: "wand.and.stars",
                    // Gold rather than accent because of the second sentence. This tile carries
                    // the warning that used to be its own "Give it a week" row, folded in when
                    // the third slot went elsewhere. It must not be trimmed to the good news:
                    // the epoch-2 engine resets every existing user's learned rates on upgrade,
                    // so suggestions move for everybody on the same day, and this sheet is the
                    // only place that is explained. See PRE_1.5_CHECKLIST.md §2.2.
                    tint: .gold,
                    // Written from the lifter's side of the screen, and deliberately with no
                    // before-and-after: the row says what the engine does now rather than
                    // confessing what it used to do. The recalibration still has to be said —
                    // it just arrives as the engine starting fresh, not as an apology.
                    title: "Smarter suggestions",
                    body: "Suggestions now factor in how hard each set actually felt, and handle drop sets properly. They're learning your numbers from today, so give them a few sessions to settle."
                ),
                WhatsNewItem(
                    id: "fresh_look",
                    systemImage: "sparkles",
                    tint: .green,
                    // Broad on purpose, and the one row where the ten-second test is met by the
                    // release rather than by the copy: everything named here is met unprompted
                    // after the next workout. What it must not soften into is "various
                    // improvements" — a row with nothing to go and look at is what teaches
                    // people to dismiss the sheet unread.
                    title: "A fresh look",
                    body: "A rebuilt workout summary you can share, redesigned templates, and a cleaner look throughout."
                )
            ]
        ),
        WhatsNewRelease(
            version: "1.4",
            items: [
                WhatsNewItem(
                    id: "apple_health",
                    // `heart.text.square` is what the Settings row and the onboarding page
                    // use, but it turns to mush in a 32pt tile. A plain heart survives the
                    // size and still reads as Health.
                    systemImage: "heart.fill",
                    tint: .red,
                    title: "Apple Health",
                    body: "Send finished workouts to Health, so they count towards your rings.",
                    action: .connectAppleHealth
                ),
                WhatsNewItem(
                    id: "insights",
                    systemImage: "lightbulb.fill",
                    tint: .gold,
                    title: "Insights",
                    // Deliberately outcomes rather than internals: nobody updating has seen
                    // a training status card, so naming one explains nothing.
                    body: "Findings from your own training — where your volume goes, what's improving, when to back off."
                )
            ]
        )
    ]

    /// The release notes for the build that is running, or nil when this version has
    /// nothing user-facing to say.
    static var current: WhatsNewRelease? {
        all.first { $0.version == appVersion }
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

// MARK: - Preferences

enum WhatsNewPreferences {

    static let lastSeenVersionKey = "lastSeenWhatsNewVersion"

    static func lastSeenVersion(userDefaults: UserDefaults = .standard) -> String? {
        userDefaults.string(forKey: lastSeenVersionKey)
    }

    /// Whether the sheet should present itself on this launch.
    ///
    /// Only ever called from inside the main app shell, which is unreachable until
    /// onboarding is complete. New installs are stamped current the moment onboarding
    /// finishes, so nobody is greeted with news about the only version they have run.
    static func shouldPresent(userDefaults: UserDefaults = .standard) -> Bool {
        guard let release = WhatsNewRelease.current else { return false }
        return lastSeenVersion(userDefaults: userDefaults) != release.version
    }

    /// Spends this version's sheet. Called on any dismissal, including a swipe — an
    /// unanswered sheet that returns every launch is worse than one that was ignored once.
    static func markSeen(userDefaults: UserDefaults = .standard) {
        userDefaults.set(WhatsNewRelease.appVersion, forKey: lastSeenVersionKey)
    }
}
