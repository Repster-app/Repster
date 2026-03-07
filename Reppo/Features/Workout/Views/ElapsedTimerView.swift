// ElapsedTimerView.swift
// Live-updating elapsed timer showing time since workout started.
// Spec: FR-013 (Elapsed workout timer)
// Contract: WP05 T024
//
// Uses TimelineView for efficient once-per-second updates.
// Pure presentational — receives startTime, computes display string.

import SwiftUI

/// Displays elapsed time since the workout started, updating every second.
///
/// Format: "M:SS" under 1 hour, "H:MM:SS" over 1 hour.
/// Uses monospaced font design to prevent layout shifts as digits change.
struct ElapsedTimerView: View {

    /// The workout's start time. Nil hides the timer.
    let startTime: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let startTime {
                let elapsed = max(0, context.date.timeIntervalSince(startTime))
                Text(formatElapsed(elapsed))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
            }
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
        ElapsedTimerView(startTime: Date().addingTimeInterval(-3661)) // 1h 1m 1s
            .padding()
    }
}

#Preview("Short Timer") {
    ZStack {
        Color.bg.ignoresSafeArea()
        ElapsedTimerView(startTime: Date().addingTimeInterval(-125)) // 2:05
            .padding()
    }
}

#Preview("No Start Time") {
    ZStack {
        Color.bg.ignoresSafeArea()
        ElapsedTimerView(startTime: nil)
            .padding()
    }
}
