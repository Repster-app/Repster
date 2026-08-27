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
                    id: "smarter_suggestions",
                    systemImage: "wand.and.stars",
                    tint: .accent,
                    // Written from the lifter's side of the screen. "Capacity baseline now reads
                    // reps in reserve" is what changed; "it stops going down when you're holding
                    // back" is what they noticed and complained about.
                    title: "Smarter suggestions",
                    body: "Telling the app you had reps left no longer makes it suggest less. It won't drop below a weight you just lifted with something in the tank, and drop sets no longer drag the rest of the exercise down."
                ),
                WhatsNewItem(
                    id: "suggestions_recalibrating",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .gold,
                    // The honest half. Suggestions shift for everyone on the same day and the
                    // per-exercise tuning restarts; saying so costs one tile and buys back the
                    // trust that a week of unexplained numbers would spend.
                    title: "Give it a week",
                    body: "Because the maths changed, per-exercise tuning starts fresh. Your numbers may look a little different until it has seen a few sessions."
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
