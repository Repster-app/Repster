// SupersetPromptView.swift
// The bottom accessory shown after a set inside a superset, in place of the rest timer.
// Spec: SUPERSETS_SCOPING.md §4 — "the rest bar already owns what happens between sets".

import SwiftUI

/// A one-tap shortcut to the next lift in the current superset.
///
/// Deliberately the same shape as `RestTimerView`: a 2pt rule over a 43pt `bgCard` row, in the same
/// slot. Inside a group there is no rest to count down, so the slot answers the same question with
/// the other half of the pair instead — and because it is the same slot at the same height, nothing
/// on the screen above it moves.
///
/// Navigation is never automatic (SUPERSETS_SCOPING.md §0). This is an offer, not a jump: the tab
/// strip still works exactly as it did, and ignoring this bar costs nothing.
struct SupersetPromptView: View {

    /// The exercise the lifter should move to.
    let nextExerciseName: String

    /// Switch to that exercise.
    let onTap: () -> Void

    /// Dismiss without moving.
    let onDismiss: () -> Void

    private static let rowHeight: CGFloat = 43
    private static let ruleHeight: CGFloat = 2

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.accent.opacity(0.35))
                .frame(height: Self.ruleHeight)

            HStack(spacing: 10) {
                Button(action: onTap) {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left.chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accent)

                        Text("Next in superset")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)

                        Text(nextExerciseName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next in superset: \(nextExerciseName)")
                .accessibilityHint("Switches to that exercise")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 26, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss superset prompt")
            }
            .padding(.horizontal, 20)
            .frame(height: Self.rowHeight)
        }
        .frame(maxWidth: .infinity)
        .background(Color.bgCard)
    }
}

#Preview("Superset prompt") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Spacer()
            SupersetPromptView(nextExerciseName: "Incline DB Press", onTap: {}, onDismiss: {})
        }
    }
}

#Preview("Long exercise name") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Spacer()
            SupersetPromptView(
                nextExerciseName: "Seated Dumbbell Lateral Raise",
                onTap: {},
                onDismiss: {}
            )
        }
    }
}
