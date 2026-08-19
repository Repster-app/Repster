// HowItWorksPage.swift
// The walkthrough's contents, and the rules for when it's offered.
//
// Deliberately only a tutorial: no page asks for anything or changes a setting. Onboarding
// used to ask for a target RIR before the user had logged a set — a decision with nothing
// to base it on — and the fix was to delete that question, not to move it in here behind
// an explanation.
//
// ---------------------------------------------------------------------------------------
// EDITING THE WALKTHROUGH
//
// Wording:      the `title` and `caption` switches below. One line each, nothing else
//               references them.
//
// Picture:      drop an image into Assets.xcassets named exactly `assetName` — so
//               `howitworks-logSet` replaces page 2's drawing. No code change: the view
//               prefers an asset when one exists and falls back to the built illustration
//               when it doesn't. Design for a 210pt-tall box on a dark background.
//
// Order:        the declaration order of the cases below is the page order.
//
// Add / remove: add or delete a case. Everything — the dots, "n of 7", the page-viewed
//               events — counts off `allCases`, so nothing else needs touching.
// ---------------------------------------------------------------------------------------

import Foundation

enum HowItWorksPage: String, CaseIterable, Identifiable {
    case startWorkout
    case logSet
    case suggestions
    case rir
    // No page for personal records: the gold PR badge appears in the set row the moment
    // one lands, which teaches itself. A page explaining it would spend a slot saying
    // "you'll notice the thing you can't miss".
    case weeklyVolume
    case charts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startWorkout:     return "Start a workout"
        case .logSet:           return "Log a set"
        case .suggestions:      return "Smart Suggestions"
        case .rir:              return "What RIR means"
        case .weeklyVolume:     return "Where your week went"
        case .charts:           return "Progress over time"
        }
    }

    var caption: String {
        switch self {
        case .startWorkout:
            return "Tap + to begin. Start fresh, repeat a past session, or load a routine you saved."
        case .logSet:
            // "Tick the box", not "tap the circle" — `CompletionCheckbox` is a rounded
            // square, and it fills blue when a set is done.
            return "Type the weight and reps, then tick the box. That's the whole loop, and everything else in Repster is built on it."
        case .suggestions:
            // The screenshot shows the weight stepping down across sets with "Easing off
            // slightly to manage session fatigue" underneath. That — a target per set,
            // adjusted as you tire, with its reasoning shown — is the actual product.
            // "Suggests a working weight" described a lookup table.
            return "A target for every set, easing off as fatigue builds through the session — and a line telling you why it landed there."
        case .rir:
            // Reps in reserve is the one piece of vocabulary the app can't avoid, and it
            // comes after Suggestions on purpose: by now the reader has seen a weight
            // appear from nowhere, so this answers a question they already have.
            //
            // Second sentence earns the page its keep — the same colours run down the RIR
            // column of every set table, so this is a legend for something they've already
            // looked at rather than a definition in the abstract.
            return "Reps in reserve — how many good reps you had left. You'll see these colours on every set you log, and they're what the next suggestion is built from."
        case .weeklyVolume:
            // Matches the panel's own restraint: every bar is measured against a tick
            // marked "your usual", and the deltas are left uncoloured on purpose. The
            // caption shouldn't promise a verdict the screen deliberately withholds.
            return "Every muscle group against your own usual week, in sets, reps, or volume. Repster shows you the comparison and leaves the verdict to you."
        case .charts:
            // The screenshot is four years of sessions with a trend line cut through
            // them. Individual sessions bounce enormously — the trend is the part that
            // answers the question, which is worth saying rather than "watch the line go
            // where you want it".
            return "Every session you've logged, over any window you like. Sessions bounce around; the trend line is the part that tells you whether it's working."
        }
    }

    /// Asset catalog name that overrides this page's drawn illustration, if it exists.
    /// Nothing has to be added for a page to work — this is the escape hatch for pages
    /// where a real picture beats a diagram.
    var assetName: String { "howitworks-\(rawValue)" }

    var analyticsName: String { rawValue }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

// MARK: - Offer rules

enum WalkthroughPreferences {

    /// Set the moment the walkthrough is opened, not when it's finished. Someone who
    /// reads two pages and closes has made a choice about how much they wanted; putting
    /// the banner back tomorrow re-asks a question they answered. Settings → About keeps
    /// it reachable forever.
    static let openedKey = "hasOpenedHowItWorks"

    static let bannerDismissedKey = "walkthroughBannerDismissed"

    /// Past this many completed workouts the banner retires on its own. Not one — pages
    /// on records, weekly volume and charts only start meaning anything once there's data
    /// behind them. Not five — that's the free-tier limit, and offering a tutorial to
    /// someone meeting a paywall is the wrong moment.
    static let completedWorkoutCeiling = 3

    static func completedWorkoutCount(userDefaults: UserDefaults = .standard) -> Int {
        // Only incremented on the workout-finish path, so imported history doesn't count.
        // That's correct: someone who brought 400 workouts over from Strong is new to
        // Repster even though they're not new to lifting.
        userDefaults.integer(forKey: ReviewPromptService.completedWorkoutCountKey)
    }

    static func markOpened(userDefaults: UserDefaults = .standard) {
        userDefaults.set(true, forKey: openedKey)
    }

    static func dismissBanner(userDefaults: UserDefaults = .standard) {
        userDefaults.set(true, forKey: bannerDismissedKey)
    }
}
