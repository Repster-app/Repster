// HomeWalkthroughBanner.swift
// One row on Home offering the walkthrough, for people who haven't got going yet.
//
// Styled as a card rather than a whisper because of who sees it: it only appears below
// three completed workouts, and at that point Home is almost entirely empty states —
// Insights says "Unlocks as you log workouts", records and recent workouts have nothing
// in them. It isn't competing with content, it's competing with placeholders.
//
// It still sits below Start Workout, which stays the loudest thing on the screen.

import SwiftUI

struct HomeWalkthroughBanner: View {
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 11) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.accent)
                        .frame(width: 30, height: 30)
                        .background(Color.accentSoft)
                        .cornerRadius(9)

                    Text("New to Repster? See how it works")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inside the card, in the slot the chevron used to hold. The dismiss used to
            // be an overlay hung off the top-right corner at `offset(x: 6, y: -6)`, which
            // put a bare glyph outside the rounded edge with the page behind it — it read
            // as a rendering fault rather than a control. There's no chevron to lose:
            // the whole row left of this button is already the tap target for opening.
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        // Trailing inset is smaller than the leading one on purpose: the dismiss button's
        // own 30pt frame supplies the rest, so the glyph sits optically level with the
        // leading icon while keeping a full-size tap target.
        .padding(.trailing, 6)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}
