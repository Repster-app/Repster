// ActiveWorkoutViewModel.swift
// Core ViewModel for the active workout screen (feature 006).
// Manages workout lifecycle, set CRUD, exercise operations, and rest timer.
//
// Architecture: @Observable @MainActor — calls Services only, never Repositories.
// Contract: kitty-specs/006-active-workout-screen/contracts/ActiveWorkoutViewModelContract.swift
// Spec: specdoc S3, S4, S6.2, S8.8; AGENT_RULES S6, S7.3

import ActivityKit
import Combine
import Foundation
import SwiftUI

// MARK: - Workout Summary Types (T031)

/// Aggregated workout statistics for the summary sheet.
struct WorkoutSummaryData {
    let date: Date
    let duration: TimeInterval
    let totalSets: Int
    let totalVolume: Double
    let exerciseSummaries: [ExerciseSummary]
    let prsHit: Int
}

/// Per-exercise breakdown in the workout summary.
struct ExerciseSummary: Identifiable {
    let id: UUID
    let exerciseName: String
    let setCount: Int
    let bestWeight: Double?
    let bestReps: Int?
    let hadPR: Bool
}

// MARK: - Rest Timer State

/// Represents the state of the rest timer between sets.
enum RestTimerState: Equatable {
    /// No timer running.
    case idle
    /// Timer counting down: remaining seconds and total seconds.
    case running(remaining: Int, total: Int)
    /// Timer has reached zero.
    case finished
}

// MARK: - ActiveWorkoutViewModel

@Observable
@MainActor
final class ActiveWorkoutViewModel {

    // MARK: - Dependencies

    private let workoutService: any WorkoutServiceProtocol
    private let setService: any SetServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol
    private let statsService: any StatsServiceProtocol
    private let prService: any PRServiceProtocol
    private let healthProfileRepo: any HealthProfileRepositoryProtocol
    private let settingsService: any SettingsServiceProtocol
    private let loadPrescriptionService: any LoadPrescriptionServiceProtocol

    /// Live Activity manager for Lock Screen / Dynamic Island updates.
    private let liveActivityManager = LiveActivityManager()

    // MARK: - Workout State

    /// The current active workout (nil if none).
    var workout: Workout?

    /// Ordered list of exercises in this workout.
    var exercises: [Exercise] = []

    /// Index of the currently selected exercise tab.
    var selectedExerciseIndex: Int = 0

    /// Global default rest time from HealthProfile (fallback when exercise has none).
    private var globalDefaultRestTime: Int?

    /// Global default warmup rest time from HealthProfile. When nil, falls back to globalDefaultRestTime.
    private var globalDefaultWarmupRestTime: Int?

    /// Sets grouped by exerciseId.
    var setsByExercise: [UUID: [WorkoutSet]] = [:]

    // MARK: - UI State

    /// Whether the ViewModel is loading data.
    var isLoading: Bool = false

    /// Controls the finish workout summary sheet.
    var showFinishSheet: Bool = false

    /// Controls the add exercise picker sheet.
    var showAddExerciseSheet: Bool = false

    /// Rest timer state between sets.
    var restTimer: RestTimerState = .idle

    /// Whether the workout has been finished (triggers dismiss of active workout screen).
    var isWorkoutFinished: Bool = false

    /// Elapsed workout time in seconds (updated by a timer in the View layer).
    var elapsedTime: TimeInterval = 0

    // MARK: - Sub-Tab State (WP06 T026/T027)

    /// History data for the current exercise sub-tab.
    var subTabHistory: [WorkoutHistoryGroup] = []

    /// Tracks which exerciseId was last loaded for history to avoid redundant fetches.
    private var historyLoadedForExerciseId: UUID?

    /// PR table data for the current exercise sub-tab.
    var subTabPRTable: [PRTableEntry] = []

    /// Tracks which exerciseId was last loaded for PRs to avoid redundant fetches.
    private var prsLoadedForExerciseId: UUID?

    // MARK: - Exercise Info State (014 WP03)

    /// Computed exercise info data for the current exercise.
    var exerciseInfoData: ExerciseInfoData?

    /// Whether exercise info is currently being loaded.
    var isLoadingExerciseInfo: Bool = false

    /// User's unit preference for display formatting.
    var unitPreference: UnitPreference = .metric

    /// Tracks which exerciseId was last loaded for exercise info to avoid redundant fetches.
    private var exerciseInfoLoadedForExerciseId: UUID?

    // MARK: - Weight Suggestion Module State

    /// Computed suggestion data for the current exercise (nil = not available/disabled).
    var weightSuggestionData: WeightSuggestionData?

    /// Whether suggestions are currently being computed.
    var isLoadingWeightSuggestions: Bool = false

    /// Whether prescription is globally enabled (fetched from HealthProfile).
    var prescriptionEnabled: Bool = false

    /// Tracks exerciseId + completed set count to avoid redundant re-computation.
    private var suggestionsLoadedForKey: String?

    // MARK: - Timer Internals

    /// Combine subscription for the 1-second timer tick.
    private var timerSubscription: AnyCancellable?

    /// When the current rest timer was started (for background recalculation).
    private var timerStartDate: Date?

    /// Total duration of the current rest timer in seconds.
    private var timerTotalDuration: Int = 0

    // MARK: - Computed Properties

    /// The currently selected exercise (derived from selectedExerciseIndex).
    var currentExercise: Exercise? {
        guard selectedExerciseIndex >= 0,
              selectedExerciseIndex < exercises.count else { return nil }
        return exercises[selectedExerciseIndex]
    }

    /// Sets for the current exercise (derived from currentExercise + setsByExercise).
    /// Sorted by orderInExercise to maintain warmup-first ordering.
    var currentSets: [WorkoutSet] {
        guard let exercise = currentExercise else { return [] }
        return (setsByExercise[exercise.id] ?? []).sorted { $0.orderInExercise < $1.orderInExercise }
    }

    // MARK: - Init

    init(
        workoutService: any WorkoutServiceProtocol,
        setService: any SetServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        statsService: any StatsServiceProtocol,
        prService: any PRServiceProtocol,
        healthProfileRepo: any HealthProfileRepositoryProtocol,
        settingsService: any SettingsServiceProtocol,
        loadPrescriptionService: any LoadPrescriptionServiceProtocol
    ) {
        self.workoutService = workoutService
        self.setService = setService
        self.exerciseService = exerciseService
        self.statsService = statsService
        self.prService = prService
        self.healthProfileRepo = healthProfileRepo
        self.settingsService = settingsService
        self.loadPrescriptionService = loadPrescriptionService
    }

    // MARK: - Lifecycle (T007)

    /// Load or resume the active workout. Called on screen appear.
    ///
    /// Fetches the active workout, its sets, and the corresponding exercises.
    /// Sets are grouped by exerciseId. Exercises are ordered by their first set's orderInExercise.
    func loadActiveWorkout() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 1. Check for existing active workout
            guard let active = try await workoutService.getActiveWorkout() else {
                return // No active workout — screen shouldn't be shown
            }
            self.workout = active

            // 2. Fetch all sets for this workout (ordered by orderInWorkout)
            let allSets = try await setService.fetchSets(for: active.id)

            // 3. Group sets by exerciseId
            self.setsByExercise = Dictionary(grouping: allSets, by: \.exerciseId)

            // 4. Discover unique exerciseIds and fetch Exercise objects
            let exerciseIds = try await setService.fetchExerciseIds(for: active.id)
            var loadedExercises: [Exercise] = []
            for exerciseId in exerciseIds {
                if let exercise = try await exerciseService.fetchExercise(exerciseId) {
                    loadedExercises.append(exercise)
                }
            }

            // 5. Order exercises by the first set's orderInWorkout for each group
            loadedExercises.sort { lhs, rhs in
                let lhsOrder = setsByExercise[lhs.id]?.first?.orderInWorkout ?? 0
                let rhsOrder = setsByExercise[rhs.id]?.first?.orderInWorkout ?? 0
                return lhsOrder < rhsOrder
            }
            self.exercises = loadedExercises

            // 6. Start Live Activity for Lock Screen / Dynamic Island
            if let startTime = active.startTime {
                let firstExercise = loadedExercises.first
                let firstSets = firstExercise.flatMap { setsByExercise[$0.id] } ?? []
                let completedCount = firstSets.filter(\.completed).count
                liveActivityManager.startActivity(
                    workoutTitle: active.displayTitle,
                    startTime: startTime,
                    exerciseName: firstExercise?.name ?? "No exercise",
                    currentSetNumber: completedCount + 1,
                    totalSets: firstSets.count,
                    setTypeLabel: firstSets.first(where: { !$0.completed })?.setType.displayName ?? "Working"
                )
            }

            // 7. Fetch global default rest time for fallback
            if let profile = try? await settingsService.fetchSettings() {
                self.globalDefaultRestTime = profile.defaultRestTimeSeconds ?? 150
                self.globalDefaultWarmupRestTime = profile.defaultWarmupRestTimeSeconds
            }

            // 8. Restore persisted rest timer (survives view dismissal)
            if let savedStartDate = UserDefaults.standard.object(forKey: "restTimerStartDate") as? Date {
                let savedDuration = UserDefaults.standard.integer(forKey: "restTimerTotalDuration")
                if savedDuration > 0 {
                    let elapsed = Int(Date().timeIntervalSince(savedStartDate))
                    let remaining = savedDuration - elapsed
                    if remaining > 0 {
                        startRestTimer(duration: remaining)
                    } else {
                        restTimer = .finished
                        UserDefaults.standard.removeObject(forKey: "restTimerStartDate")
                        UserDefaults.standard.removeObject(forKey: "restTimerTotalDuration")
                    }
                }
            }

        } catch {
            print("[ActiveWorkoutViewModel] Failed to load active workout: \(error)")
        }
    }

    // MARK: - Set Operations (T008)

    /// Complete a set with the given input values.
    ///
    /// Persists via SetService.save() (triggers PR + stats pipeline),
    /// updates local state with results, and starts the rest timer.
    func completeSet(
        _ set: WorkoutSet,
        weight: Double?,
        reps: Int?,
        durationSeconds: Int?,
        distanceMeters: Double?
    ) async {
        do {
            // 1. Update the set object with input values
            set.weight = weight
            set.reps = reps
            set.durationSeconds = durationSeconds
            set.distanceMeters = distanceMeters
            set.completed = true
            set.completedAt = Date()
            set.updatedAt = Date()

            // 2. Save via SetService (triggers effectiveWeight + PR + stats pipeline)
            let result = try await setService.save(set)

            // 3. Update local state with pipeline results
            set.effectiveWeight = result.effectiveWeight
            set.cachedPRStatus = result.prResult.newStatus

            // 4. Update any affected sets (e.g., demoted PR owners)
            applyAffectedSets(result.prResult.affectedSetIds)

            // 4b. Reassign array to trigger @Observable update for UI
            if let sets = setsByExercise[set.exerciseId] {
                setsByExercise[set.exerciseId] = sets
            }

            // 5. Start rest timer: warmup sets use warmup rest time, working sets use default.
            // Note: startRestTimer() already calls updateLiveActivityState(),
            // so we only push a separate update if NO timer starts.
            let restTime: Int?
            if set.setType == .warmup {
                restTime = globalDefaultWarmupRestTime ?? currentExercise?.defaultRestTime ?? globalDefaultRestTime
            } else {
                restTime = currentExercise?.defaultRestTime ?? globalDefaultRestTime
            }
            if let restTime, restTime > 0 {
                startRestTimer(duration: restTime)
            } else {
                updateLiveActivityState()
            }

            // 6. Invalidate exercise info, PR, history, and suggestion caches, then reload
            exerciseInfoLoadedForExerciseId = nil
            prsLoadedForExerciseId = nil
            historyLoadedForExerciseId = nil
            suggestionsLoadedForKey = nil
            await loadExerciseInfo()
            await loadWeightSuggestions()

        } catch {
            print("[ActiveWorkoutViewModel] Failed to complete set: \(error)")
        }
    }

    /// Uncomplete a set, flipping it back to incomplete state.
    ///
    /// Uses setService.uncomplete() which models uncompleting as "removing a set's
    /// contribution" — demotes PRs and decrements stats without deleting the set.
    func uncompleteSet(_ set: WorkoutSet) async {
        let exerciseId = set.exerciseId
        let oldCompleted = set.completed

        do {
            let result = try await setService.uncomplete(set)
            set.effectiveWeight = result.effectiveWeight
            set.cachedPRStatus = result.prResult.newStatus
            applyAffectedSets(result.prResult.affectedSetIds)

            // Reassign array to trigger @Observable update
            if let sets = setsByExercise[exerciseId] {
                setsByExercise[exerciseId] = sets
            }

            // Update Live Activity (set progress changed)
            updateLiveActivityState()

            // Invalidate exercise info, PR, history, and suggestion caches, then reload
            exerciseInfoLoadedForExerciseId = nil
            prsLoadedForExerciseId = nil
            historyLoadedForExerciseId = nil
            suggestionsLoadedForKey = nil
            await loadExerciseInfo()
            await loadWeightSuggestions()
        } catch {
            // Revert on failure
            set.completed = oldCompleted
            print("[ActiveWorkoutViewModel] Failed to uncomplete set: \(error)")
        }
    }

    // MARK: - Set CRUD (T009)

    /// Add a new empty working set for the given exercise.
    ///
    /// Creates a WorkoutSet with setType = .working, persists immediately
    /// (survives app kill per FR-003), and appends to local state.
    func addSet(for exerciseId: UUID) async {
        guard let workout else { return }

        let totalSets = setsByExercise.values.flatMap { $0 }.count
        let exerciseSets = setsByExercise[exerciseId] ?? []

        let newSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exerciseId,
            date: Date(),
            setType: .working,
            orderInWorkout: totalSets + 1,
            orderInExercise: exerciseSets.count + 1,
            completed: false
        )

        do {
            _ = try await setService.save(newSet)

            // Append to local state
            var sets = setsByExercise[exerciseId] ?? []
            sets.append(newSet)
            setsByExercise[exerciseId] = sets

            // Update Live Activity (total sets changed)
            updateLiveActivityState()

            // Invalidate and refresh suggestions for the currently visible exercise
            suggestionsLoadedForKey = nil
            if currentExercise?.id == exerciseId {
                await loadWeightSuggestions()
            }

        } catch {
            print("[ActiveWorkoutViewModel] Failed to add set: \(error)")
        }
    }

    /// Add a new warmup set for the given exercise.
    ///
    /// Warmup sets are inserted before working sets in the exercise's set list.
    func addWarmupSet(for exerciseId: UUID) async {
        guard let workout else { return }

        let totalSets = setsByExercise.values.flatMap { $0 }.count
        var exerciseSets = setsByExercise[exerciseId] ?? []

        // Find insertion point: before the first non-warmup set
        let insertionIndex = exerciseSets.firstIndex(where: { $0.setType != .warmup }) ?? exerciseSets.count

        let newSet = WorkoutSet(
            workoutId: workout.id,
            exerciseId: exerciseId,
            date: Date(),
            setType: .warmup,
            orderInWorkout: totalSets + 1,
            orderInExercise: insertionIndex + 1,
            completed: false
        )

        do {
            _ = try await setService.save(newSet)

            // Insert at correct position and reindex
            exerciseSets.insert(newSet, at: insertionIndex)
            reindexOrderInExercise(&exerciseSets)
            setsByExercise[exerciseId] = exerciseSets

            // Invalidate and refresh suggestions for the currently visible exercise
            suggestionsLoadedForKey = nil
            if currentExercise?.id == exerciseId {
                await loadWeightSuggestions()
            }

        } catch {
            print("[ActiveWorkoutViewModel] Failed to add warmup set: \(error)")
        }
    }

    // MARK: - Set Operations (T010)

    /// Delete a set. Triggers PR/stats cascade via SetService.
    func deleteSet(_ set: WorkoutSet) async {
        let exerciseId = set.exerciseId

        do {
            try await setService.delete(set)

            // Remove from local state
            var sets = setsByExercise[exerciseId] ?? []
            sets.removeAll { $0.id == set.id }
            reindexOrderInExercise(&sets)
            setsByExercise[exerciseId] = sets

            // Update Live Activity (total sets changed)
            updateLiveActivityState()

            // Invalidate exercise info and PR caches, then reload
            exerciseInfoLoadedForExerciseId = nil
            prsLoadedForExerciseId = nil
            await loadExerciseInfo()

            // Deletion can change fatigue context and first-working-set freshness logic
            suggestionsLoadedForKey = nil
            if currentExercise?.id == exerciseId {
                await loadWeightSuggestions()
            }

        } catch {
            print("[ActiveWorkoutViewModel] Failed to delete set: \(error)")
        }
    }

    /// Change the set type (e.g., working → warmup, warmup → dropset).
    ///
    /// Type change may affect PR eligibility, so the full edit pipeline runs.
    func changeSetType(_ set: WorkoutSet, to type: SetType) async {
        set.setType = type
        set.updatedAt = Date()

        do {
            let result = try await setService.edit(set)
            set.effectiveWeight = result.effectiveWeight
            set.cachedPRStatus = result.prResult.newStatus
            applyAffectedSets(result.prResult.affectedSetIds)

            // Invalidate exercise info and PR caches, then reload
            exerciseInfoLoadedForExerciseId = nil
            prsLoadedForExerciseId = nil
            await loadExerciseInfo()

            // Type changes can add/remove a set from suggestion inputs
            suggestionsLoadedForKey = nil
            if currentExercise?.id == set.exerciseId {
                await loadWeightSuggestions()
            }

        } catch {
            print("[ActiveWorkoutViewModel] Failed to change set type: \(error)")
        }
    }

    // MARK: - Exercise Operations (T011)

    /// Add exercises to the workout from the picker sheet.
    ///
    /// For each exercise, fetches the Exercise object, creates an initial empty set,
    /// and switches to the newly added exercise tab.
    func addExercises(_ exerciseIds: [UUID]) async {
        for exerciseId in exerciseIds {
            do {
                guard let exercise = try await exerciseService.fetchExercise(exerciseId) else {
                    continue
                }

                // Add to exercises list
                exercises.append(exercise)

                // Initialize with an empty working set
                setsByExercise[exerciseId] = []
                await addSet(for: exerciseId)

            } catch {
                print("[ActiveWorkoutViewModel] Failed to add exercise \(exerciseId): \(error)")
            }
        }

        // Switch to the last added exercise
        if !exercises.isEmpty {
            selectedExerciseIndex = exercises.count - 1
        }

        // Update Live Activity (exercise and set counts changed)
        updateLiveActivityState()
    }

    /// Remove an exercise and all its sets from the workout.
    func removeExercise(at index: Int) async {
        guard index >= 0, index < exercises.count else { return }

        let exercise = exercises[index]
        let exerciseSets = setsByExercise[exercise.id] ?? []

        // Delete all sets for this exercise
        for set in exerciseSets {
            do {
                try await setService.delete(set)
            } catch {
                print("[ActiveWorkoutViewModel] Failed to delete set \(set.id) during exercise removal: \(error)")
            }
        }

        // Remove from local state
        exercises.remove(at: index)
        setsByExercise.removeValue(forKey: exercise.id)

        // Clamp selectedExerciseIndex to valid range
        if exercises.isEmpty {
            selectedExerciseIndex = 0
        } else if selectedExerciseIndex >= exercises.count {
            selectedExerciseIndex = exercises.count - 1
        }

        // Update Live Activity (exercise changed)
        updateLiveActivityState()
    }

    /// Reorder exercises via drag gesture on tab strip.
    ///
    /// Rearranges the local exercises array and persists the new order
    /// by updating orderInWorkout on all sets so order survives screen transitions.
    func reorderExercises(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)

        // Persist new order: update orderInWorkout on all sets to reflect new exercise order
        Task {
            var globalOrder = 1
            for exercise in exercises {
                guard let sets = setsByExercise[exercise.id] else { continue }
                for set in sets {
                    set.orderInWorkout = globalOrder
                    set.updatedAt = Date()
                    do {
                        _ = try await setService.edit(set)
                    } catch {
                        print("[ActiveWorkoutViewModel] Failed to persist reorder for set \(set.id): \(error)")
                    }
                    globalOrder += 1
                }
            }
        }
    }

    // MARK: - Rest Timer (T027, T028)

    /// Start or restart the rest timer with a given duration in seconds.
    ///
    /// Cancels any existing timer, stores the start timestamp for background
    /// recalculation, and starts a 1-second Combine tick.
    func startRestTimer(duration: Int) {
        // Cancel any existing timer
        timerSubscription?.cancel()

        // Store start time for background recalculation
        timerStartDate = Date()
        timerTotalDuration = duration
        restTimer = .running(remaining: duration, total: duration)

        // Persist timer state so it survives view dismissal
        UserDefaults.standard.set(timerStartDate, forKey: "restTimerStartDate")
        UserDefaults.standard.set(timerTotalDuration, forKey: "restTimerTotalDuration")

        // Start 1-second tick via Timer.publish
        timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.timerTick()
                }
            }

        // Update Live Activity (timer started with new end date)
        updateLiveActivityState()
    }

    /// Add seconds to the running timer (+30s button).
    func addTime(_ seconds: Int) {
        guard case .running(let remaining, let total) = restTimer else { return }
        let newTotal = total + seconds
        let newRemaining = remaining + seconds
        timerTotalDuration = newTotal
        restTimer = .running(remaining: newRemaining, total: newTotal)

        // Update Live Activity (timer end date changed)
        updateLiveActivityState()
    }

    /// Subtract seconds from the running timer (-15s, -30s buttons). Clamps to 1 second minimum.
    func subtractTime(_ seconds: Int) {
        guard case .running(let remaining, let total) = restTimer else { return }
        let newRemaining = max(1, remaining - seconds)
        let newTotal = max(1, total - seconds)
        timerTotalDuration = newTotal
        restTimer = .running(remaining: newRemaining, total: newTotal)

        // Update Live Activity (timer end date changed)
        updateLiveActivityState()
    }

    /// Set the timer to an exact duration in seconds.
    func setTimerDuration(_ seconds: Int) {
        guard seconds > 0 else { return }
        startRestTimer(duration: seconds)
    }

    /// Dismiss the rest timer and cancel the Combine subscription.
    func dismissTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
        timerStartDate = nil
        restTimer = .idle

        // Clear persisted timer state
        UserDefaults.standard.removeObject(forKey: "restTimerStartDate")
        UserDefaults.standard.removeObject(forKey: "restTimerTotalDuration")

        // Update Live Activity (timer dismissed)
        updateLiveActivityState()
    }

    /// Recalculate timer remaining time after returning from background.
    ///
    /// Uses the stored start timestamp to compute how much time has actually
    /// elapsed, avoiding drift from suspended Timer.publish ticks.
    func recalculateTimerAfterBackground() {
        guard case .running = restTimer,
              let startDate = timerStartDate else { return }

        let elapsed = Int(Date().timeIntervalSince(startDate))
        let remaining = timerTotalDuration - elapsed

        if remaining <= 0 {
            restTimer = .finished
            timerSubscription?.cancel()
            timerSubscription = nil
        } else {
            restTimer = .running(remaining: remaining, total: timerTotalDuration)
        }

        // Update Live Activity with corrected timer state after background return
        updateLiveActivityState()
    }

    /// Decrement the timer by one second. Called by the Combine subscription.
    private func timerTick() {
        guard case .running(let remaining, let total) = restTimer else { return }
        if remaining <= 1 {
            restTimer = .finished
            timerSubscription?.cancel()
            timerSubscription = nil
            // Clear persisted timer state
            UserDefaults.standard.removeObject(forKey: "restTimerStartDate")
            UserDefaults.standard.removeObject(forKey: "restTimerTotalDuration")
            // Update Live Activity only on state transition to .finished
            // (NOT every tick — countdown is rendered by ActivityKit's timer text style)
            updateLiveActivityState()
        } else {
            restTimer = .running(remaining: remaining - 1, total: total)
        }
    }

    // MARK: - Live Activity Updates

    /// Push the current workout state to the Live Activity.
    ///
    /// Called after any meaningful state change (set complete/uncomplete, exercise
    /// switch, timer start/stop/finish, set/exercise add/remove). NOT called on
    /// every timer tick — ActivityKit's `Text(timerInterval:)` handles countdown
    /// rendering natively.
    private func updateLiveActivityState() {
        let exerciseName = currentExercise?.name ?? "No exercise"
        let sets = currentSets
        let completedCount = sets.filter(\.completed).count
        let currentSetNumber = min(completedCount + 1, max(sets.count, 1))
        let totalSets = sets.count
        let nextIncompleteSet = sets.first { !$0.completed }
        let setTypeLabel = nextIncompleteSet?.setType.displayName ?? "Working"

        var isRestTimerRunning = false
        var restTimerEndDate: Date? = nil
        var restTimerTotalSeconds = 0
        var isRestTimerFinished = false

        switch restTimer {
        case .idle:
            break
        case .running(_, let total):
            isRestTimerRunning = true
            // Use the fixed start time + total duration for a stable end date.
            // This avoids flicker — each push won't shift the countdown.
            if let startDate = timerStartDate {
                restTimerEndDate = startDate.addingTimeInterval(TimeInterval(timerTotalDuration))
            }
            restTimerTotalSeconds = total
        case .finished:
            isRestTimerFinished = true
        }

        liveActivityManager.updateActivity(
            exerciseName: exerciseName,
            currentSetNumber: currentSetNumber,
            totalSets: totalSets,
            setTypeLabel: setTypeLabel,
            isRestTimerRunning: isRestTimerRunning,
            restTimerEndDate: restTimerEndDate,
            restTimerTotalSeconds: restTimerTotalSeconds,
            isRestTimerFinished: isRestTimerFinished
        )
    }

    // MARK: - Sub-Tab Data Loading (WP06 T026/T027)

    /// Load history data for the current exercise. Used by the History sub-tab.
    ///
    /// Fetches all sets for the exercise, groups by workout, and sorts newest-first.
    /// Skips if already loaded for this exercise (cleared on exercise switch).
    func loadHistoryForCurrentExercise() async {
        guard let exercise = currentExercise else { return }
        guard historyLoadedForExerciseId != exercise.id else { return }

        do {
            let sets = try await setService.fetchSets(for: exercise.id, limit: nil)
            let grouped = Dictionary(grouping: sets) { $0.workoutId }
            subTabHistory = grouped.map { workoutId, workoutSets in
                WorkoutHistoryGroup(
                    id: workoutId,
                    date: workoutSets.first?.date ?? Date(),
                    sets: workoutSets.sorted { $0.orderInExercise < $1.orderInExercise }
                )
            }
            .sorted { $0.date > $1.date }
            historyLoadedForExerciseId = exercise.id
        } catch {
            print("[ActiveWorkoutViewModel] Failed to load history: \(error)")
            subTabHistory = []
        }
    }

    /// Load PR table data for the current exercise. Used by the PRs sub-tab.
    ///
    /// Fetches the suffix-max filtered PR table via PRService.
    /// Skips if already loaded for this exercise (cleared on exercise switch).
    func loadPRsForCurrentExercise() async {
        guard let exercise = currentExercise else { return }
        guard prsLoadedForExerciseId != exercise.id else { return }

        do {
            subTabPRTable = try await prService.fetchPRTable(for: exercise.id)
            prsLoadedForExerciseId = exercise.id
        } catch {
            print("[ActiveWorkoutViewModel] Failed to load PRs: \(error)")
            subTabPRTable = []
        }
    }

    /// Clear cached sub-tab data when switching exercises (T028).
    /// Charts are now self-contained via EmbeddedExerciseChartView (recreated by .id()).
    func clearSubTabCache() {
        subTabHistory = []
        subTabPRTable = []
        historyLoadedForExerciseId = nil
        prsLoadedForExerciseId = nil
        exerciseInfoData = nil
        exerciseInfoLoadedForExerciseId = nil
        weightSuggestionData = nil
        suggestionsLoadedForKey = nil

        // Update Live Activity (exercise switched — new name, set counts)
        updateLiveActivityState()
    }

    // MARK: - Exercise Info Loading (014 WP03 T009)

    /// Load exercise info data for the current exercise.
    ///
    /// Delegates to ExerciseInfoProvider.compute(), caches by exerciseId,
    /// and fetches unit preference for view display.
    func loadExerciseInfo() async {
        guard let exercise = currentExercise,
              let workout = workout else { return }

        // Cache check — don't re-fetch if already loaded for this exercise
        if exerciseInfoLoadedForExerciseId == exercise.id {
            return
        }

        isLoadingExerciseInfo = true
        defer { isLoadingExerciseInfo = false }

        do {
            // Fetch unit preference and prescription toggle for display
            let profile = try await settingsService.fetchSettings()
            unitPreference = profile.unitPreference
            prescriptionEnabled = profile.prescriptionEnabled ?? true

            let data = try await ExerciseInfoProvider.compute(
                currentSets: currentSets,
                exerciseId: exercise.id,
                currentWorkoutId: workout.id,
                trackingType: exercise.trackingType,
                weightIncrement: exercise.weightIncrement,
                setService: setService,
                loadPrescriptionService: loadPrescriptionService,
                healthProfileRepo: healthProfileRepo
            )
            exerciseInfoData = data
            exerciseInfoLoadedForExerciseId = exercise.id
        } catch {
            exerciseInfoData = nil
            exerciseInfoLoadedForExerciseId = exercise.id
            print("[ActiveWorkoutViewModel] ExerciseInfo load failed: \(error)")
        }
    }

    // MARK: - Weight Suggestion Module

    /// Invalidate suggestion cache to force a refresh on next load.
    func invalidateSuggestions() {
        suggestionsLoadedForKey = nil
    }

    /// Load weight suggestions for unfilled working sets of the current exercise.
    ///
    /// Uses SuggestionCoordinator to gather app models, LoadPrescriptionService
    /// to normalize and evaluate, and SuggestionExplainer to build display data.
    /// Does NOT modify any WorkoutSet objects — purely read-only.
    func loadWeightSuggestions() async {
        guard let exercise = currentExercise else {
            weightSuggestionData = nil
            return
        }

        // Only compute for weight-based exercises
        guard exercise.trackingType == .weightReps ||
              exercise.trackingType == .weightRepsDuration else {
            weightSuggestionData = nil
            return
        }

        // Refresh setting-dependent inputs so cache keys and gating stay accurate.
        var resolvedProfile: HealthProfile? = try? await settingsService.fetchSettings()
        if resolvedProfile == nil {
            resolvedProfile = try? await healthProfileRepo.fetchOrCreate()
        }
        if let resolvedProfile {
            unitPreference = resolvedProfile.unitPreference
            prescriptionEnabled = resolvedProfile.prescriptionEnabled ?? true
        }

        // Check global toggle
        guard prescriptionEnabled else {
            weightSuggestionData = nil
            return
        }

        let sets = currentSets
        let completedWorking = sets.filter { $0.completed && $0.setType != .warmup }
        let completedSessionSets = SuggestionCoordinator.completedSessionSets(from: sets)
        let pendingSets = SuggestionCoordinator.pendingSetInputs(from: sets)

        let cacheKey = SuggestionCoordinator.cacheKey(
            exercise: exercise,
            completedWorking: completedWorking,
            pendingSets: pendingSets,
            profile: resolvedProfile
        )

        // Cache check — skip if already computed for this exact input state
        guard suggestionsLoadedForKey != cacheKey else { return }

        isLoadingWeightSuggestions = true
        defer { isLoadingWeightSuggestions = false }

        guard !pendingSets.isEmpty else {
            weightSuggestionData = nil
            suggestionsLoadedForKey = cacheKey
            return
        }

        do {
            let evaluation = try await loadPrescriptionService.evaluateSuggestions(
                exerciseId: exercise.id,
                pendingSets: pendingSets,
                completedSessionSets: completedSessionSets
            )
            weightSuggestionData = evaluation.flatMap(SuggestionExplainer.makeWeightSuggestionData)

            suggestionsLoadedForKey = cacheKey

        } catch {
            print("[WeightSuggestion] Failed to load suggestions: \(error)")
            weightSuggestionData = nil
            suggestionsLoadedForKey = cacheKey
        }
    }

    // MARK: - Summary Computation (T031)

    /// Compute workout summary statistics from in-memory state.
    ///
    /// Uses local ViewModel data (not database) — the sets are already loaded.
    func computeSummary() -> WorkoutSummaryData? {
        guard let workout else { return nil }

        let startTime = workout.startTime ?? Date()
        let duration = Date().timeIntervalSince(startTime)

        var totalSets = 0
        var totalVolume: Double = 0
        var prsHit = 0
        var exerciseSummaries: [ExerciseSummary] = []

        for exercise in exercises {
            let sets = setsByExercise[exercise.id] ?? []
            let completedSets = sets.filter { $0.completed }

            let exerciseSetCount = completedSets.count
            totalSets += exerciseSetCount

            // Volume: sum of effectiveWeight * reps for completed sets
            let exerciseVolume = completedSets.reduce(0.0) { sum, s in
                sum + (s.volume ?? 0)
            }
            totalVolume += exerciseVolume

            // Best weight and reps in this exercise
            let bestWeight = completedSets.compactMap(\.effectiveWeight).max()
            let bestReps = completedSets.compactMap(\.reps).max()

            // PRs hit (cachedPRStatus == .current)
            let exercisePRs = sets.filter { $0.cachedPRStatus == .current }.count
            prsHit += exercisePRs

            exerciseSummaries.append(ExerciseSummary(
                id: exercise.id,
                exerciseName: exercise.name,
                setCount: exerciseSetCount,
                bestWeight: bestWeight,
                bestReps: bestReps,
                hadPR: exercisePRs > 0
            ))
        }

        return WorkoutSummaryData(
            date: workout.date,
            duration: duration,
            totalSets: totalSets,
            totalVolume: totalVolume,
            exerciseSummaries: exerciseSummaries,
            prsHit: prsHit
        )
    }

    // MARK: - Finish / Discard Workout (T034, T035)

    /// Finish the workout with optional notes and RPE.
    ///
    /// Calls WorkoutService.finishWorkout(), clears local state, and sets
    /// isWorkoutFinished to trigger navigation dismissal.
    func finishWorkout(title: String?, notes: String?, perceivedEffort: Double?) async {
        guard let workout else { return }

        do {
            try await workoutService.finishWorkout(
                workout.id,
                title: title,
                notes: notes,
                perceivedEffort: perceivedEffort
            )

            // Clear local state
            self.workout = nil
            self.exercises = []
            self.setsByExercise = [:]
            dismissTimer()

            // End Live Activity (workout completed)
            liveActivityManager.endActivity()

            // Signal the View layer to dismiss (T035)
            self.isWorkoutFinished = true

        } catch {
            print("[ActiveWorkoutViewModel] Failed to finish workout: \(error)")
        }
    }

    /// Discard the workout, permanently deleting it and all its sets.
    ///
    /// Calls WorkoutService.deleteWorkout() which cascade-deletes all sets,
    /// the workout itself, and rebuilds PRs/stats for affected exercises.
    /// Clears local state and signals the View layer to dismiss.
    func discardWorkout() async {
        guard let workout else { return }

        do {
            try await workoutService.deleteWorkout(workout.id)

            // Clear local state
            self.workout = nil
            self.exercises = []
            self.setsByExercise = [:]
            dismissTimer()

            // End Live Activity (workout discarded)
            liveActivityManager.endActivity()

            // Signal the View layer to dismiss
            self.isWorkoutFinished = true

        } catch {
            print("[ActiveWorkoutViewModel] Failed to discard workout: \(error)")
        }
    }

    // MARK: - Private Helpers

    /// Apply affected set status changes from PR pipeline results.
    ///
    /// When a set is saved/edited/deleted, the PR pipeline may change
    /// cachedPRStatus on other sets (e.g., demoting a previous PR owner).
    /// To avoid confusing retroactive badge "upgrades" during a workout,
    /// completed in-session sets only receive demotions, not promotions.
    private func applyAffectedSets(_ affectedSetIds: [UUID: CachedPRStatus?]) {
        guard !affectedSetIds.isEmpty else { return }

        for (exerciseId, sets) in setsByExercise {
            let updatedSets = sets
            var changed = false
            for (index, set) in updatedSets.enumerated() {
                if let newStatus = affectedSetIds[set.id] {
                    // For completed sets, only apply demotions (not promotions).
                    // This prevents confusing badge changes on sets the user already saw.
                    if set.completed, isStatusUpgrade(from: set.cachedPRStatus, to: newStatus) {
                        continue
                    }
                    updatedSets[index].cachedPRStatus = newStatus
                    changed = true
                }
            }
            if changed {
                setsByExercise[exerciseId] = updatedSets
            }
        }
    }

    /// Returns true if the new status is a "promotion" (more prominent badge).
    /// Visibility hierarchy: .current (★) > .matched (=) > .dominated/.previous/nil (no badge)
    private func isStatusUpgrade(from old: CachedPRStatus?, to new: CachedPRStatus?) -> Bool {
        func rank(_ status: CachedPRStatus?) -> Int {
            switch status {
            case .current: return 3
            case .matched: return 2
            case .dominated, .previous: return 1
            case nil: return 0
            }
        }
        return rank(new) > rank(old)
    }

    /// Reindex orderInExercise for a set array after insertion/deletion
    /// and persist the updated order values.
    private func reindexOrderInExercise(_ sets: inout [WorkoutSet]) {
        for (index, set) in sets.enumerated() {
            let newOrder = index + 1
            if set.orderInExercise != newOrder {
                set.orderInExercise = newOrder
                set.updatedAt = Date()
                Task {
                    do {
                        _ = try await setService.edit(set)
                    } catch {
                        print("[ActiveWorkoutViewModel] Failed to persist orderInExercise for set \(set.id): \(error)")
                    }
                }
            }
        }
    }
}

// MARK: - SetTableDataSource Conformance

extension ActiveWorkoutViewModel: SetTableDataSource {
    var currentSuggestedWeight: Double? {
        weightSuggestionData?.suggestions.first?.suggestedWeight
    }

    func suggestedWeight(for setId: UUID) -> Double? {
        weightSuggestionData?.suggestion(for: setId)?.suggestedWeight
    }

    /// No-op in active workout — sets are saved when the checkbox is tapped.
    func markSetDirty(_ set: WorkoutSet) { }

    /// Update the note on a set and persist immediately.
    func updateSetNote(_ set: WorkoutSet, note: String?) async {
        set.notes = note
        set.updatedAt = Date()

        do {
            _ = try await setService.edit(set)

            // Reassign array to trigger @Observable update for UI
            if let sets = setsByExercise[set.exerciseId] {
                setsByExercise[set.exerciseId] = sets
            }
        } catch {
            print("[ActiveWorkoutViewModel] Failed to update set note: \(error)")
        }
    }
}
