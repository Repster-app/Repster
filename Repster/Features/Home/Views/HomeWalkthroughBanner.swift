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

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textTertiary)
        }
        .padding(12)
        .background(Color.bgCard)
        .cornerRadius(14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .overlay(alignment: .topTrailing) {
            // Outside the row's tap target so dismissing can't be mistaken for opening.
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
            .offset(x: 6, y: -6)
        }
        .accessibilityElement(children: .combine)
    }
}
