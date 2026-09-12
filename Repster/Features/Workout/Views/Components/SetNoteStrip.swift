// SetNoteStrip.swift
// A set's note, opened under its row in a read-only history list.
// See SET_NOTES_IN_HISTORY_SCOPING.md §2.

import SwiftUI

/// The one place a set note is drawn outside its editor — exercise history and the Calendar
/// card both show notes through this.
///
/// Masks the note for session replay itself. The privacy policy promises set notes are hidden
/// from recordings (docs/privacy.html), and a note is free text that can hold anything, so the
/// mask lives in the component rather than being left for each screen to remember.
/// `ReplayMaskCoverageTests` fails the build if this stops masking, or if a note is drawn
/// anywhere else without one.
struct SetNoteStrip: View {

    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.top, 1)

            // No line limit: typed notes are one line, but an imported one can run long, and
            // the reader asked to see it.
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .replayMasked()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
