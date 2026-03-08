// LiveActivityManager.swift
// Manages the ActivityKit lifecycle for workout Live Activities.
//
// Responsibilities:
//   - Start a Live Activity when a workout begins
//   - Update it on meaningful state changes (set complete, exercise switch, timer events)
//   - End it when the workout finishes or is discarded
//   - Clean up stale activities from previous app sessions
//
// Design: @MainActor (called from the @MainActor ViewModel). NOT added to
// ServiceContainer — this is a presentation-layer concern, stored directly
// as a property on ActiveWorkoutViewModel.
//
// Timer rendering: Uses Date-based fields so ActivityKit renders countdowns
// natively via Text(timerInterval:). No per-second pushes needed.

import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {

    // MARK: - State

    /// The currently running Live Activity, if any.
    private(set) var currentActivity: Activity<WorkoutActivityAttributes>?

    // MARK: - Start

    /// Start a new Live Activity for the given workout.
    ///
    /// Called from `ActiveWorkoutViewModel.loadActiveWorkout()` after the workout
    /// and exercises are loaded. If an activity already exists (e.g., from a previous
    /// app process), updates it instead of creating a duplicate.
    ///
    /// - Parameters:
    ///   - workoutTitle: Display title (e.g., "Morning Workout")
    ///   - startTime: When the workout started
    ///   - exerciseName: Name of the current exercise
    ///   - currentSetNumber: Next set to complete (1-based)
    ///   - totalSets: Total sets for the current exercise
    ///   - setTypeLabel: Display label for the set type ("Working", "Warm-up", etc.)
    func startActivity(
        workoutTitle: String,
        startTime: Date,
        exerciseName: String,
        currentSetNumber: Int,
        totalSets: Int,
        setTypeLabel: String
    ) {
        // Guard: ActivityKit must be available
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityManager] Live Activities not enabled by user")
            return
        }

        // Recover existing activity from a previous app process (e.g., after app kill + relaunch)
        if currentActivity == nil {
            if let existing = Activity<WorkoutActivityAttributes>.activities.first {
                currentActivity = existing
                updateActivity(
                    exerciseName: exerciseName,
                    currentSetNumber: currentSetNumber,
                    totalSets: totalSets,
                    setTypeLabel: setTypeLabel,
                    isRestTimerRunning: false,
                    restTimerEndDate: nil,
                    restTimerTotalSeconds: 0,
                    isRestTimerFinished: false
                )
                print("[LiveActivityManager] Recovered existing activity: \(existing.id)")
                return
            }
        }

        // If activity already exists in-memory, update instead of duplicating
        if currentActivity != nil {
            updateActivity(
                exerciseName: exerciseName,
                currentSetNumber: currentSetNumber,
                totalSets: totalSets,
                setTypeLabel: setTypeLabel,
                isRestTimerRunning: false,
                restTimerEndDate: nil,
                restTimerTotalSeconds: 0,
                isRestTimerFinished: false
            )
            return
        }

        // Create new activity
        let attributes = WorkoutActivityAttributes(
            workoutTitle: workoutTitle,
            workoutStartTime: startTime
        )

        let initialState = WorkoutActivityAttributes.ContentState(
            exerciseName: exerciseName,
            currentSetNumber: currentSetNumber,
            totalSets: totalSets,
            setTypeLabel: setTypeLabel,
            isRestTimerRunning: false,
            restTimerEndDate: nil,
            restTimerTotalSeconds: 0,
            isRestTimerFinished: false
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil // Local updates only — no push token needed
            )
            currentActivity = activity
            print("[LiveActivityManager] Started activity: \(activity.id)")
        } catch {
            print("[LiveActivityManager] Failed to start activity: \(error)")
        }
    }

    // MARK: - Update

    /// Update the Live Activity with new state.
    ///
    /// Called on meaningful state changes only:
    /// - Set completed/uncompleted
    /// - Exercise switched
    /// - Rest timer started/dismissed/finished
    /// - Set or exercise added/removed
    /// - Timer adjusted (+15s, -30s)
    /// - Return from background (timer recalculated)
    ///
    /// NOT called every second — timer countdown is rendered by ActivityKit's
    /// `Text(timerInterval:)` text style.
    func updateActivity(
        exerciseName: String,
        currentSetNumber: Int,
        totalSets: Int,
        setTypeLabel: String,
        isRestTimerRunning: Bool,
        restTimerEndDate: Date?,
        restTimerTotalSeconds: Int,
        isRestTimerFinished: Bool
    ) {
        guard let activity = currentActivity else { return }

        let updatedState = WorkoutActivityAttributes.ContentState(
            exerciseName: exerciseName,
            currentSetNumber: currentSetNumber,
            totalSets: totalSets,
            setTypeLabel: setTypeLabel,
            isRestTimerRunning: isRestTimerRunning,
            restTimerEndDate: restTimerEndDate,
            restTimerTotalSeconds: restTimerTotalSeconds,
            isRestTimerFinished: isRestTimerFinished
        )

        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))
        }
    }

    // MARK: - End

    /// End the Live Activity.
    ///
    /// Called when the workout is finished or discarded.
    /// Uses `.immediate` dismissal policy — the activity disappears right away.
    func endActivity() {
        guard let activity = currentActivity else { return }

        let finalState = WorkoutActivityAttributes.ContentState(
            exerciseName: "",
            currentSetNumber: 0,
            totalSets: 0,
            setTypeLabel: "",
            isRestTimerRunning: false,
            restTimerEndDate: nil,
            restTimerTotalSeconds: 0,
            isRestTimerFinished: false
        )

        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
        print("[LiveActivityManager] Ended activity")
    }

    // MARK: - Cleanup

    /// End any stale activities from a previous app session.
    ///
    /// Called at app launch in ReppoApp.init(). If the app was killed while a
    /// workout was active, the Live Activity may still be lingering on the
    /// Lock Screen. This cleans them up before a fresh activity is started.
    func cleanupStaleActivities() {
        Task {
            for activity in Activity<WorkoutActivityAttributes>.activities {
                await activity.end(
                    .init(
                        state: WorkoutActivityAttributes.ContentState(
                            exerciseName: "",
                            currentSetNumber: 0,
                            totalSets: 0,
                            setTypeLabel: "",
                            isRestTimerRunning: false,
                            restTimerEndDate: nil,
                            restTimerTotalSeconds: 0,
                            isRestTimerFinished: false
                        ),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
        }
    }
}
