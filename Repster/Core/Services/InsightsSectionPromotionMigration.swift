// InsightsSectionPromotionMigration.swift
// Lifts the Insights section to the top of Home, once.
//
// `HomeSectionConfig.sanitized()` appends sections a saved config doesn't know about to
// the *end* of the list. That's a reasonable default in general, but Insights is the
// headline of 1.4 and has never shipped — so anyone who opened Customize Home before it
// existed would meet it as the last thing on the screen, on the release that announces it.
//
// This isn't overriding a preference. Overriding would be forcing the section visible
// after someone hid it, or reshuffling sections they arranged. Nobody chose to put
// Insights at the bottom; it wasn't there to choose. Picking a better default for a
// section the user has never seen is help.
//
// One-shot on purpose, rather than a rule inside `sanitized()`: re-applying on every load
// would fight a user who moves Insights back down deliberately. Choosing the default once
// is help, choosing it on every launch is an argument.

import Foundation

enum InsightsSectionPromotionMigration {

    static let userDefaultsKey = "insightsSectionPromotionVersion"
    static let currentVersion = 1

    static func runIfNeeded(userDefaults: UserDefaults = .standard) {
        guard userDefaults.integer(forKey: userDefaultsKey) < currentVersion else { return }
        userDefaults.set(currentVersion, forKey: userDefaultsKey)

        // A user with no saved config gets `.default`, which already leads with Insights,
        // so `load()` hands back an already-correct order and this exits without writing.
        var config = HomeSectionConfig.load()

        guard let index = config.sections.firstIndex(where: { $0.sectionId == .insights }),
              index != 0 else {
            return
        }

        let entry = config.sections.remove(at: index)
        config.sections.insert(entry, at: 0)
        config.save()
    }
}
