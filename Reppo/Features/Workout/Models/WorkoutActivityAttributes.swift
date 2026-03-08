// WorkoutActivityAttributes.swift
// Shared ActivityKit model between main app and widget extension for Live Activity.
//
// IMPORTANT: This file must have target membership in BOTH:
//   - Reppo (main app)
//   - WorkoutLiveActivity (widget extension)
//
// Architecture: Uses Date-based fields for timer rendering so ActivityKit handles
// countdown/elapsed-time display natively — no per-second data pushes needed.

import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {

    // MARK: - Static Context (set once when activity starts, immutable)

    /// Workout display title (e.g., "Morning Workout").
    let workoutTitle: String

    /// When the workout started — used with `Text(date:style:.timer)`
    /// for zero-cost elapsed time rendering in the widget.
    let workoutStartTime: Date

    // MARK: - Dynamic Content State (updated throughout workout)

    struct ContentState: Codable, Hashable {
        /// Name of the current exercise (e.g., "Bench Press").
        var exerciseName: String

        /// Current set number (1-based): the next set to be completed.
        var currentSetNumber: Int

        /// Total number of sets for the current exercise.
        var totalSets: Int

        /// Display name of the set type ("Working", "Warm-up", etc.).
        var setTypeLabel: String

        /// Whether the rest timer is currently counting down.
        var isRestTimerRunning: Bool

        /// Rest timer end date — used with `Text(timerInterval:countsDown:true)`
        /// for zero-cost countdown rendering. Nil when no timer is active.
        var restTimerEndDate: Date?

        /// Total rest timer duration in seconds (for progress bar width calculation).
        var restTimerTotalSeconds: Int

        /// Whether the rest timer has finished (shows "Rest complete" message).
        var isRestTimerFinished: Bool
    }
}
