// SupersetPalette.swift
// The colours that separate one superset from another on screen.
//
// Shared by the exercise tab strip and the reorder sheet. Both draw the same groups at the same
// time, and a group that is blue in the strip has to be blue in the sheet — otherwise the sheet
// is unreadable against the screen it was opened from.

import SwiftUI

/// Colours for the superset groups currently on screen, assigned by order of appearance.
///
/// A group is identified by its container and where it sits, not by a letter, so the palette only
/// has to separate two groups that are both visible. It cycles rather than capping.
///
/// Green, red, gold and orange are deliberately absent: they mean completed, delete, PR and
/// "has a note" everywhere else in the app.
enum SupersetPalette {

    static let colors: [Color] = [.accent, .chart5, .chart7, .chart8]

    /// The container colour for a run, or nil when it must not be drawn as a group.
    ///
    /// `runs` is the full on-screen list, not just the marked ones: position is taken over the
    /// marked subset so the colours stay stable as ungrouped exercises move around them.
    static func color(for run: SupersetGrouping.Run, in runs: [SupersetGrouping.Run]) -> Color? {
        guard run.isMarked, let groupId = run.groupId else { return nil }
        let onScreen = runs.compactMap { $0.isMarked ? $0.groupId : nil }
        guard let position = onScreen.firstIndex(of: groupId) else { return nil }
        return colors[position % colors.count]
    }
}
