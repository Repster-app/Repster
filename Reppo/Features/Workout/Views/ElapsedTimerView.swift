// ElapsedTimerView.swift
// Tap-to-pause elapsed timer showing the workout clock state.
// Spec: FR-013 (Elapsed workout timer)
// Contract: WP05 T024
//
// Pure presentational — receives already-computed elapsed time plus pause state.

import SwiftUI

/// Displays the workout elapsed time and toggles pause/resume when tapped.
///
/// Format: "M:SS" under 1 hour, "H:MM:SS" over 1 hour.
/// Uses monospaced font design to prevent layout shifts as digits change.
struct ElapsedTimerView: View {

    /// The current workout elapsed time. Nil hides the timer until the workout is loaded.
    let elapsedTime: TimeInterval?

    /// Whether the workout clock is currently paused.
    let isPaused: Bool

    /// Called when the user taps the timer text.
    let onTap: () -> Void

    var body: some View {
        if let elapsedTime {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    Text(formatElapsed(elapsedTime))

                    if isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .frame(minWidth: 72, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaused ? "Workout timer paused" : "Workout timer running")
            .accessibilityHint(isPaused ? "Tap to resume the workout timer" : "Tap to pause the workout timer")
        }
    }

    // MARK: - Formatting

    /// Format elapsed seconds as "M:SS" or "H:MM:SS".
    private func formatElapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Previews

#Preview("Running Timer") {
    ZStack {
        Color.bg.ignoresSafeArea()
        ElapsedTimerView(
            elapsedTime: 3661,
            isPaused: false,
            onTap: {}
        )
            .padding()
    }
}

#Preview("Short Timer") {
    ZStack {
        Color.bg.ignoresSafeArea()
        ElapsedTimerView(
            elapsedTime: 125,
            isPaused: true,
            onTap: {}
        )
            .padding()
    }
}

#Preview("No Start Time") {
    ZStack {
        Color.bg.ignoresSafeArea()
        ElapsedTimerView(
            elapsedTime: nil,
            isPaused: false,
            onTap: {}
        )
            .padding()
    }
}
