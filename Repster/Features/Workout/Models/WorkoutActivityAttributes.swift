// WorkoutActivityAttributes.swift
// Shared ActivityKit model between main app and widget extension for Live Activity.
//
// IMPORTANT: This file must have target membership in BOTH:
//   - Repster (main app)
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

        /// Reference date used for the workout elapsed timer while the workout is active.
        /// This shifts forward across pause/resume cycles so the timer excludes paused time.
        var elapsedTimerReferenceDate: Date

        /// Whether the workout clock is currently paused.
        var isWorkoutPaused: Bool

        /// Frozen elapsed workout seconds used while paused.
        var pausedElapsedSeconds: Int

        /// Whether the rest timer is currently counting down.
        var isRestTimerRunning: Bool

        /// Whether the rest timer is currently paused while the workout keeps running.
        var isRestTimerPaused: Bool

        /// Rest timer end date — used with `Text(timerInterval:countsDown:true)`
        /// for zero-cost countdown rendering. Nil when no timer is active.
        var restTimerEndDate: Date?

        /// Total rest timer duration in seconds (for progress bar width calculation).
        var restTimerTotalSeconds: Int

        /// Current rest timer remaining seconds. Used to freeze the timer while paused.
        var restTimerRemainingSeconds: Int?

        /// Whether the rest timer has finished (shows "Rest complete" message).
        var isRestTimerFinished: Bool
    }
}

// MARK: - Rest Section Display State

extension WorkoutActivityAttributes.ContentState {

    /// Which rest treatment the Live Activity should render.
    ///
    /// Extracted from the widget's view bodies so it can be tested: `ActivityViewContext` has
    /// no public initialiser, but `ContentState` is a plain struct, so every branch below is
    /// reachable from a unit test while the view chains are not.
    ///
    /// Both chains — Lock Screen and the Dynamic Island's expanded region — read this, which is
    /// what stops them from drifting apart. They rendered the same five states through two
    /// hand-maintained if/else ladders, and both carried the same `.complete` gap.
    enum RestDisplay: Equatable {
        case workoutPaused
        case restPaused
        /// Counting down to the given end date.
        case counting(until: Date)
        case complete
        case ready
    }

    /// - Parameter now: injected so tests can sit either side of the end date.
    func restDisplay(at now: Date = .now) -> RestDisplay {
        if isWorkoutPaused { return .workoutPaused }
        if isRestTimerPaused { return .restPaused }

        if isRestTimerRunning, let endDate = restTimerEndDate {
            // Past the end date this is a *finished* timer, not an absent one.
            //
            // Nothing pushes `isRestTimerFinished` while the app is suspended — the tick that
            // sets it needs the app to be executing — so relying on that flag alone left an
            // expired timer falling through to `.ready` ("Ready for next set"), or more often
            // frozen on a spent 0:00 because nothing re-rendered at all. The end date is
            // already here and is true whether or not anyone pushed anything.
            return endDate > now ? .counting(until: endDate) : .complete
        }

        if isRestTimerFinished { return .complete }
        return .ready
    }
}
