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
    case personalRecords
    case weeklyVolume
    case charts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startWorkout:     return "Start a workout"
        case .logSet:           return "Log a set"
        case .suggestions:      return "Smart Suggestions"
        case .rir:              return "What RIR means"
        case .personalRecords:  return "Every PR, caught"
        case .weeklyVolume:     return "Where your week went"
        case .charts:           return "Progress over time"
        }
    }

    var caption: String {
        switch self {
        case .startWorkout:
            return "Tap + to begin. Start fresh, repeat a past session, or load a routine you saved."
        case .logSet:
            return "Enter the weight and reps, then tap the circle to complete the set. That's the whole loop."
        case .suggestions:
            return "Repster reads your recent sets for an exercise and suggests a working weight. Take it, or type your own."
        case .rir:
            // Reps in reserve is the one piece of vocabulary the app can't avoid, and it
            // comes after Suggestions on purpose: by now the reader has seen a weight
            // appear from nowhere, so this answers a question they already have.
            return "Reps in reserve — how many good reps you had left. Logging it is what makes the next suggestion accurate."
        case .personalRecords:
            return "Repster flags personal records as you log them, and tracks your estimated 1RM for every exercise."
        case .weeklyVolume:
            // Matches the status card's own restraint: it states the comparison and
            // refuses to grade it, so the walkthrough shouldn't promise a verdict.
            return "Repster compares this week against your own average — and tells you the comparison, not a score."
        case .charts:
            return "Chart any exercise or muscle group over any window, and watch the line go where you want it."
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
