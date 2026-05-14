// ActiveWorkoutViewModel.swift
// Core ViewModel for the active workout screen (feature 006).
// Manages workout lifecycle, set CRUD, exercise operations, and rest timer.
//
// Architecture: @Observable @MainActor — calls Services only, never Repositories.
// Contract: kitty-specs/006-active-workout-screen/contracts/ActiveWorkoutViewModelContract.swift
// Spec: specdoc S3, S4, S6.2, S8.8; AGENT_RULES S6, S7.3

import ActivityKit
import AudioToolbox
import Combine
import Foundation
import UserNotifications
import SwiftUI

// MARK: - Workout Summary Types (T031)

/// Aggregated workout statistics for the summary sheet.
struct WorkoutSummaryData {
    let date: Date
    let duration: TimeInterval
    let totalSets: Int
    let primaryMetric: WorkoutPrimaryMetric?
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

enum RestTimerPauseSource: String, Equatable {
    case manual
    case workout
}

/// Represents the state of the rest timer between sets.
enum RestTimerState: Equatable {
    /// No timer running.
    case idle
    /// Timer counting down: remaining seconds and total seconds.
    case running(remaining: Int, total: Int)
    /// Timer is frozen with remaining time preserved.
    case paused(remaining: Int, total: Int, source: RestTimerPauseSource)
    /// Timer has reached zero.
    case finished
}

enum ActiveWorkoutSessionDefaultsKeys {
    static let workoutClockWorkoutId = "activeWorkoutClockWorkoutId"
    static let workoutClockAccumulatedElapsedSeconds = "activeWorkoutClockAccumulatedElapsedSeconds"
    static let workoutClockLastResumedAt = "activeWorkoutClockLastResumedAt"
    static let workoutClockIsPaused = "activeWorkoutClockIsPaused"
    static let selectedExerciseWorkoutId = "activeWorkoutSelectedExerciseWorkoutId"
    static let selectedExerciseId = "activeWorkoutSelectedExerciseId"
    static let restTimerWorkoutId = "activeWorkoutRestTimerWorkoutId"
    static let restTimerStartDate = "restTimerStartDate"
    static let restTimerTotalDuration = "restTimerTotalDuration"
    static let restTimerRemainingDuration = "activeWorkoutRestTimerRemainingDuration"
    static let restTimerIsPaused = "activeWorkoutRestTimerIsPaused"
    static let restTimerPauseSource = "activeWorkoutRestTimerPauseSource"
}

// MARK: - ActiveWorkoutViewModel

@Observable
@MainActor
final class ActiveWorkoutViewModel {

    enum SuggestionRefreshPresentation {
        case blocking
        case preserveExisting
    }

    // MARK: - Dependencies

    private let workoutService: any WorkoutServiceProtocol
    private let setService: any SetServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol
    private let statsService: any StatsServiceProtocol
    private let prService: any PRServiceProtocol
    private let healthProfileRepo: any HealthProfileRepositoryProtocol
    private let settingsService: any SettingsServiceProtocol
    private let loadPrescriptionService: any LoadPrescriptionServiceProtocol
    private let accessControlService: any AccessControlServiceProtocol
    let fatigueLearningService: FatigueLearningService

    /// Exercise IDs that had at least one prediction snapshot recorded during this workout.
    /// Used by WorkoutSummarySheet to show fatigue feedback options.
    private(set) var exerciseIdsWithPredictions: Set<UUID> = []

    /// Live Activity manager for Lock Screen / Dynamic Island updates.
    private let liveActivityManager = LiveActivityManager()

    // MARK: - Workout State

    /// The current active workout (nil if none).
    var workout: Workout?

    /// Ordered list of exercises in this workout.
    var exercises: [Exercise] = []

    /// Index of the currently selected exercise tab.
    var selectedExerciseIndex: Int = 0 {
        didSet {
            guard selectedExerciseIndex != oldValue else { return }
            persistSelectedExerciseState()
            updateLiveActivityState()
        }
    }

    /// Global default rest time from HealthProfile (fallback when exercise has none).
    private var globalDefaultRestTime: Int?

    /// Global default warmup rest time from HealthProfile. When nil, falls back to globalDefaultRestTime.
    private var globalDefaultWarmupRestTime: Int?

    /// Rest timer alert mode: "off", "vibration", "sound", or "both".
    private var restTimerAlertMode: String = "both"

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

    /// Whether the workout clock is currently paused.
    var isWorkoutPaused: Bool = false

    /// Whether the workout has been finished (triggers dismiss of active workout screen).
    var isWorkoutFinished: Bool = false

    /// Elapsed workout time in seconds, excluding paused time.
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

    /// Resolved default weight increment stored in kg.
    var defaultWeightIncrement: Double = 2.5

    /// Tracks which exerciseId was last loaded for exercise info to avoid redundant fetches.
    private var exerciseInfoLoadedForExerciseId: UUID?

    // MARK: - Weight Suggestion Module State

    /// Computed suggestion data for the current exercise.
    /// The data can represent either available suggestions or a typed unavailable state.
    var weightSuggestionData: WeightSuggestionData?

    /// Whether the module should show blocking loading UI.
    var isLoadingWeightSuggestions: Bool = false

    /// Whether the module is refreshing in the background while preserving visible rows.
    var isRefreshingWeightSuggestions: Bool = false

    /// Whether prescription is globally enabled (fetched from HealthProfile).
    var prescriptionEnabled: Bool = false

    /// Whether Smart Suggestions admin diagnostics should be shown.
    var suggestionAdminModeEnabled: Bool = false

    /// Tracks exerciseId + completed set count to avoid redundant re-computation.
    private var suggestionsLoadedForKey: String?

    /// Debounce applied to live recompute after reps/RIR draft edits.
    private let suggestionDraftEditDebounce: Duration = .milliseconds(300)

    /// Pending or in-flight suggestion refresh work.
    private var suggestionRefreshTask: Task<Void, Never>?

    /// Monotonic generation used to drop stale suggestion refresh completions.
    private var suggestionRefreshGeneration: UInt64 = 0

    // MARK: - Workout Clock Internals

    /// Elapsed workout seconds accumulated before the current active run segment.
    private var accumulatedElapsedSeconds: TimeInterval = 0

    /// Start date of the current active run segment. Nil while paused.
    private var lastWorkoutResumedAt: Date?

    /// Combine subscription for the workout elapsed clock updates.
    private var workoutTimerSubscription: AnyCancellable?

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
        loadPrescriptionService: any LoadPrescriptionServiceProtocol,
        accessControlService: any AccessControlServiceProtocol = NoopAccessControlService(),
        fatigueLearningService: FatigueLearningService
    ) {
        self.workoutService = workoutService
        self.setService = setService
        self.exerciseService = exerciseService
        self.statsService = statsService
        self.prService = prService
        self.healthProfileRepo = healthProfileRepo
        self.settingsService = settingsService
        self.loadPrescriptionService = loadPrescriptionService
        self.accessControlService = accessControlService
        self.fatigueLearningService = fatigueLearningService
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
                clearPersistedWorkoutClockState()
                clearPersistedSelectedExerciseState()
                clearPersistedRestTimerState()
                timerSubscription?.cancel()
                timerSubscription = nil
                workoutTimerSubscription?.cancel()
                workoutTimerSubscription = nil
                workout = nil
                exercises = []
                selectedExerciseIndex = 0
                setsByExercise = [:]
                restTimer = .idle
                isWorkoutPaused = false
                accumulatedElapsedSeconds = 0
                lastWorkoutResumedAt = nil
                elapsedTime = 0
                return // No active workout — screen shouldn't be shown
            }
            self.workout = active

            // 2. Fetch all sets for this workout (ordered by orderInWorkout)
            let allSets = try await setService.fetchSets(for: active.id)

            // 3. Group sets by exerciseId, then sort each group by orderInExercise
            //    so warmups stay on top regardless of orderInWorkout drift.
            var grouped = Dictionary(grouping: allSets, by: \.exerciseId)
            for (exerciseId, exerciseSets) in grouped {
                grouped[exerciseId] = exerciseSets.sorted { $0.orderInExercise < $1.orderInExercise }
            }
            self.setsByExercise = grouped

            // 4. Discover unique exerciseIds and fetch Exercise objects
            let exerciseIds = try await setService.fetchExerciseIds(for: active.id)
            var loadedExercises: [Exercise] = []
            for exerciseId in exerciseIds {
                if let exercise = try await exerciseService.fetchExercise(exerciseId) {
                    loadedExercises.append(exercise)
                }
            }

            // 5. Order exercises by the MIN orderInWorkout across their sets
            //    (robust to warmups having been appended at the global tail).
            loadedExercises.sort { lhs, rhs in
                let lhsOrder = setsByExercise[lhs.id]?.map(\.orderInWorkout).min() ?? 0
                let rhsOrder = setsByExercise[rhs.id]?.map(\.orderInWorkout).min() ?? 0
                return lhsOrder < rhsOrder
            }
            self.exercises = loadedExercises
            restoreSelectedExerciseState(for: active)

            // 6. Start Live Activity for Lock Screen / Dynamic Island
            if let startTime = active.startTime {
                let firstExercise = currentExercise ?? loadedExercises.first
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
                self.unitPreference = profile.unitPreference
                self.defaultWeightIncrement = UnitConversion.resolvedStoredWeightIncrement(
                    exerciseIncrement: nil,
                    defaultIncrement: profile.prescriptionDefaultIncrement,
                    unitPreference: profile.unitPreference
                )
                self.globalDefaultRestTime = profile.defaultRestTimeSeconds ?? 150
                self.globalDefaultWarmupRestTime = profile.defaultWarmupRestTimeSeconds
                self.restTimerAlertMode = profile.restTimerAlert ?? "both"
                self.suggestionAdminModeEnabled = profile.prescriptionAdminModeEnabled ?? false
            }

            // 8. Restore persisted workout clock and rest timer state (survives view dismissal).
            restoreWorkoutClockState(for: active)
            restoreRestTimerState(for: active)
            updateLiveActivityState()

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to load active workout: \(error)")
            #endif
        }
    }

    // MARK: - Set Operations (T008)

    /// Complete a set with the given input values.
    ///
    /// Persists via SetService.save() (triggers PR + stats pipeline),
    /// updates local state with results, and starts the rest timer.
    func completeSet(_ set: WorkoutSet, input: SetCompletionInput) async {
        do {
            // 0. Capture the current suggestion state before the set leaves the pending list.
            let suggestionState = weightSuggestionData?.rowState(for: set.id)
            let predictionSnapshot: PredictionSnapshot?
            if let suggestion = suggestionState?.suggestion {
                let formulaRawValue = (try? await healthProfileRepo.fetchOrCreate().e1RMFormula) ?? "epley"
                predictionSnapshot = PredictionSnapshot(
                    effectiveE1RM: suggestion.diagnostics.effectiveE1RM,
                    baseE1RM: suggestion.diagnostics.baseE1RM,
                    prescribedWeight: suggestion.suggestedWeight,
                    formula: E1RMFormula(rawValue: formulaRawValue) ?? .epley
                )
                exerciseIdsWithPredictions.insert(set.exerciseId)
            } else {
                predictionSnapshot = nil
            }

            // 1. Update the set object with input values
            applyCompletionInput(input, to: set)
            set.completed = true
            set.completedAt = Date()
            set.updatedAt = Date()

            // 2. Save via SetService (triggers effectiveWeight + PR + stats pipeline)
            let result = try await setService.save(set)

            // 3. Update local state with pipeline results
            set.effectiveWeight = result.effectiveWeight
            set.prStatus = result.prResult.newStatus

            // 4. Update any affected sets (e.g., demoted PR owners)
            applyAffectedSets(result.prResult.affectedSetIds)

            // 4b. Reassign array to trigger @Observable update for UI
            if let sets = setsByExercise[set.exerciseId] {
                setsByExercise[set.exerciseId] = sets
            }

            // 5. Record fatigue learning capture deterministically for every completed set.
            let completedWorkingSetCount = setsByExercise[set.exerciseId]?
                .filter { $0.completed && $0.setType != .warmup && $0.id != set.id }
                .count ?? 0

            do {
                _ = try await fatigueLearningService.captureCompletedSet(
                    setId: set.id,
                    exerciseId: set.exerciseId,
                    workoutId: set.workoutId,
                    visibleSetNumber: set.orderInExercise,
                    setType: set.setType,
                    priorCompletedWorkingSetCount: completedWorkingSetCount,
                    suggestionUnavailableReason: suggestionState?.unavailableReason,
                    prediction: predictionSnapshot,
                    actualWeight: set.effectiveWeight ?? set.weight,
                    actualReps: set.reps,
                    actualRIR: set.rir,
                    restDurationSeconds: set.restDurationSeconds
                )
            } catch {
                #if DEBUG
                dbg("[ActiveWorkoutViewModel] Failed to capture fatigue learning for set \(set.id): \(error)")
                #endif
            }

            // 6. Start rest timer: warmup sets use warmup rest time, working sets use default.
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

            // 7. Invalidate PR, history, and suggestion caches, then reload
            prsLoadedForExerciseId = nil
            historyLoadedForExerciseId = nil
            if currentExercise?.id == set.exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to complete set: \(error)")
            #endif
        }
    }

    /// Uncomplete a set, flipping it back to incomplete state.
    ///
    /// Uses setService.uncomplete() which models uncompleting as "removing a set's
    /// contribution" — demotes PRs and decrements stats without deleting the set.
    func uncompleteSet(
        _ set: WorkoutSet,
        previousContribution: SetContributionSnapshot? = nil
    ) async {
        let exerciseId = set.exerciseId
        let oldCompleted = set.completed

        do {
            let result = try await setService.uncomplete(
                set,
                previousContribution: previousContribution
            )
            set.effectiveWeight = result.effectiveWeight
            set.prStatus = result.prResult.newStatus
            applyAffectedSets(result.prResult.affectedSetIds)

            // Reassign array to trigger @Observable update
            if let sets = setsByExercise[exerciseId] {
                setsByExercise[exerciseId] = sets
            }

            // Update Live Activity (set progress changed)
            updateLiveActivityState()

            // Invalidate PR, history, and suggestion caches, then reload
            prsLoadedForExerciseId = nil
            historyLoadedForExerciseId = nil
            if currentExercise?.id == exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

        } catch {
            // Revert on failure
            set.completed = oldCompleted
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to uncomplete set: \(error)")
            #endif
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
            if currentExercise?.id == exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to add set: \(error)")
            #endif
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

            // Rewrite global orderInWorkout so the newly-inserted warmup isn't stranded
            // at the workout tail — keeps both order fields consistent.
            reindexOrderInWorkout()

            // Invalidate and refresh suggestions for the currently visible exercise
            if currentExercise?.id == exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to add warmup set: \(error)")
            #endif
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

            // Invalidate PR cache and refresh suggestions as needed
            prsLoadedForExerciseId = nil

            // Deletion can change fatigue context and first-working-set freshness logic
            if currentExercise?.id == exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to delete set: \(error)")
            #endif
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
            set.prStatus = result.prResult.newStatus
            applyAffectedSets(result.prResult.affectedSetIds)

            // Invalidate PR cache and refresh suggestions as needed
            prsLoadedForExerciseId = nil

            // Type changes can add/remove a set from suggestion inputs
            if currentExercise?.id == set.exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to change set type: \(error)")
            #endif
        }
    }

    // MARK: - Exercise Operations (T011)

    /// Add exercises to the workout from the picker sheet.
    ///
    /// For each exercise, fetches the Exercise object, creates an initial empty set,
    /// and switches to the first newly added exercise tab.
    func addExercises(_ exerciseIds: [UUID]) async {
        let firstAddedIndex = exercises.count
        var addedExerciseCount = 0

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
                addedExerciseCount += 1

            } catch {
                #if DEBUG
                dbg("[ActiveWorkoutViewModel] Failed to add exercise \(exerciseId): \(error)")
                #endif
            }
        }

        // Switch to the first newly added exercise so the user starts at the front of the new block.
        if addedExerciseCount > 0 {
            selectedExerciseIndex = firstAddedIndex
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
                #if DEBUG
                dbg("[ActiveWorkoutViewModel] Failed to delete set \(set.id) during exercise removal: \(error)")
                #endif
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

        // Keep the moved exercise selected (mirrors EditWorkoutViewModel behavior).
        if let sourceIndex = source.first, sourceIndex == selectedExerciseIndex {
            selectedExerciseIndex = destination > sourceIndex ? destination - 1 : destination
        }

        // Persist new order: update orderInWorkout on all sets to reflect new exercise order.
        // Iterate each exercise's sets in orderInExercise order so warmups keep the lowest
        // orderInWorkout within their exercise.
        Task {
            var globalOrder = 1
            for exercise in exercises {
                guard let sets = setsByExercise[exercise.id] else { continue }
                let orderedSets = sets.sorted { $0.orderInExercise < $1.orderInExercise }
                for set in orderedSets {
                    set.orderInWorkout = globalOrder
                    set.updatedAt = Date()
                    do {
                        _ = try await setService.edit(set)
                    } catch {
                        #if DEBUG
                        dbg("[ActiveWorkoutViewModel] Failed to persist reorder for set \(set.id): \(error)")
                        #endif
                    }
                    globalOrder += 1
                }
            }
        }
    }

    // MARK: - Workout Clock

    /// Toggle the workout clock between paused and running states.
    func toggleWorkoutPause() {
        guard workout != nil else { return }

        if isWorkoutPaused {
            resumeWorkoutClock()
        } else {
            pauseWorkoutClock()
        }
    }

    func currentElapsedTime(referenceDate: Date = Date()) -> TimeInterval {
        let runningSegment: TimeInterval
        if !isWorkoutPaused, let lastWorkoutResumedAt {
            runningSegment = max(0, referenceDate.timeIntervalSince(lastWorkoutResumedAt))
        } else {
            runningSegment = 0
        }
        return max(0, accumulatedElapsedSeconds + runningSegment)
    }

    private func restoreWorkoutClockState(for workout: Workout, referenceDate: Date = Date()) {
        let defaults = UserDefaults.standard
        let workoutId = workout.id.uuidString
        let persistedWorkoutId = defaults.string(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockWorkoutId)

        guard persistedWorkoutId == workoutId else {
            clearPersistedWorkoutClockState()
            initializeWorkoutClockState(from: workout.startTime ?? referenceDate, referenceDate: referenceDate)
            return
        }

        accumulatedElapsedSeconds = max(
            0,
            defaults.double(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockAccumulatedElapsedSeconds)
        )
        isWorkoutPaused = defaults.bool(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockIsPaused)

        if isWorkoutPaused {
            lastWorkoutResumedAt = nil
            stopWorkoutClockTicker()
        } else {
            lastWorkoutResumedAt = (
                defaults.object(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockLastResumedAt) as? Date
            ) ?? workout.startTime ?? referenceDate
            startWorkoutClockTicker()
        }

        refreshElapsedTime(referenceDate: referenceDate)
        persistWorkoutClockState()
    }

    private func initializeWorkoutClockState(from startTime: Date, referenceDate: Date = Date()) {
        accumulatedElapsedSeconds = 0
        isWorkoutPaused = false
        lastWorkoutResumedAt = startTime
        refreshElapsedTime(referenceDate: referenceDate)
        startWorkoutClockTicker()
        persistWorkoutClockState()
    }

    private func pauseWorkoutClock(referenceDate: Date = Date()) {
        ensureWorkoutClockInitialized(referenceDate: referenceDate)
        accumulatedElapsedSeconds = currentElapsedTime(referenceDate: referenceDate)
        isWorkoutPaused = true
        lastWorkoutResumedAt = nil
        stopWorkoutClockTicker()
        refreshElapsedTime(referenceDate: referenceDate)
        pauseRestTimerIfNeeded(referenceDate: referenceDate, source: .workout)
        persistWorkoutClockState()
        updateLiveActivityState()
    }

    private func resumeWorkoutClock(referenceDate: Date = Date()) {
        ensureWorkoutClockInitialized(referenceDate: referenceDate)
        isWorkoutPaused = false
        lastWorkoutResumedAt = referenceDate
        startWorkoutClockTicker()
        refreshElapsedTime(referenceDate: referenceDate)
        resumeRestTimerIfNeeded(referenceDate: referenceDate)
        persistWorkoutClockState()
        updateLiveActivityState()
    }

    private func ensureWorkoutClockInitialized(referenceDate: Date = Date()) {
        if lastWorkoutResumedAt == nil, elapsedTime == 0, accumulatedElapsedSeconds == 0, let workout {
            initializeWorkoutClockState(from: workout.startTime ?? referenceDate, referenceDate: referenceDate)
        }
    }

    private func startWorkoutClockTicker() {
        workoutTimerSubscription?.cancel()
        guard !isWorkoutPaused else { return }

        workoutTimerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshElapsedTime()
                }
            }
    }

    private func stopWorkoutClockTicker() {
        workoutTimerSubscription?.cancel()
        workoutTimerSubscription = nil
    }

    private func refreshElapsedTime(referenceDate: Date = Date()) {
        elapsedTime = currentElapsedTime(referenceDate: referenceDate)
    }

    private func persistWorkoutClockState() {
        let defaults = UserDefaults.standard
        guard let workout else {
            clearPersistedWorkoutClockState()
            return
        }

        defaults.set(workout.id.uuidString, forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockWorkoutId)
        defaults.set(
            accumulatedElapsedSeconds,
            forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockAccumulatedElapsedSeconds
        )
        defaults.set(isWorkoutPaused, forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockIsPaused)

        if let lastWorkoutResumedAt, !isWorkoutPaused {
            defaults.set(lastWorkoutResumedAt, forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockLastResumedAt)
        } else {
            defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockLastResumedAt)
        }
    }

    private func clearPersistedWorkoutClockState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockWorkoutId)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockAccumulatedElapsedSeconds)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockLastResumedAt)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.workoutClockIsPaused)
    }

    private func restoreSelectedExerciseState(for workout: Workout) {
        guard !exercises.isEmpty else {
            selectedExerciseIndex = 0
            clearPersistedSelectedExerciseState()
            return
        }

        let defaults = UserDefaults.standard
        let workoutId = workout.id.uuidString
        let persistedWorkoutId = defaults.string(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseWorkoutId)

        if persistedWorkoutId == workoutId,
           let persistedExerciseId = defaults.string(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseId),
           let selectedExerciseId = UUID(uuidString: persistedExerciseId),
           let restoredIndex = exercises.firstIndex(where: { $0.id == selectedExerciseId }) {
            selectedExerciseIndex = restoredIndex
            persistSelectedExerciseState()
            return
        }

        selectedExerciseIndex = inferredCurrentExerciseIndex()
        persistSelectedExerciseState()
    }

    private func inferredCurrentExerciseIndex() -> Int {
        guard !exercises.isEmpty else { return 0 }

        if let firstPendingIndex = exercises.firstIndex(where: exerciseHasPendingWork(_:)) {
            return firstPendingIndex
        }

        return exercises.count - 1
    }

    private func exerciseHasPendingWork(_ exercise: Exercise) -> Bool {
        let sets = setsByExercise[exercise.id] ?? []
        return sets.isEmpty || sets.contains(where: { !$0.completed })
    }

    private func persistSelectedExerciseState() {
        let defaults = UserDefaults.standard
        guard let workout, let currentExercise else {
            clearPersistedSelectedExerciseState()
            return
        }

        defaults.set(workout.id.uuidString, forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseWorkoutId)
        defaults.set(currentExercise.id.uuidString, forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseId)
    }

    private func clearPersistedSelectedExerciseState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseWorkoutId)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.selectedExerciseId)
    }

    // MARK: - Rest Timer (T027, T028)

    /// Start or restart the rest timer with a given duration in seconds.
    func startRestTimer(duration: Int) {
        guard duration > 0 else { return }

        if isWorkoutPaused {
            setPausedRestTimer(
                remaining: duration,
                total: duration,
                source: .workout
            )
        } else {
            startRestTimer(remaining: duration, total: duration)
        }
    }

    /// Add seconds to the running timer (+30s button).
    func addTime(_ seconds: Int) {
        switch restTimer {
        case .running(let remaining, let total):
            let newTotal = total + seconds
            let newRemaining = remaining + seconds
            timerTotalDuration = newTotal
            restTimer = .running(remaining: newRemaining, total: newTotal)
            persistRunningRestTimerState(remaining: newRemaining, total: newTotal)
            scheduleRestTimerNotification(seconds: newRemaining)
            updateLiveActivityState()

        case .paused(let remaining, let total, let source):
            let newTotal = total + seconds
            let newRemaining = remaining + seconds
            setPausedRestTimer(
                remaining: newRemaining,
                total: newTotal,
                source: source
            )

        case .idle, .finished:
            return
        }
    }

    /// Subtract seconds from the running timer (-15s, -30s buttons). Clamps to 1 second minimum.
    func subtractTime(_ seconds: Int) {
        switch restTimer {
        case .running(let remaining, let total):
            let newRemaining = max(1, remaining - seconds)
            let newTotal = max(1, total - seconds)
            timerTotalDuration = newTotal
            restTimer = .running(remaining: newRemaining, total: newTotal)
            persistRunningRestTimerState(remaining: newRemaining, total: newTotal)
            scheduleRestTimerNotification(seconds: newRemaining)
            updateLiveActivityState()

        case .paused(let remaining, let total, let source):
            let newRemaining = max(1, remaining - seconds)
            let newTotal = max(1, total - seconds)
            setPausedRestTimer(
                remaining: newRemaining,
                total: newTotal,
                source: source
            )

        case .idle, .finished:
            return
        }
    }

    /// Set the timer to an exact duration in seconds.
    func setTimerDuration(_ seconds: Int) {
        guard seconds > 0 else { return }

        if case .paused(_, _, let source) = restTimer {
            setPausedRestTimer(
                remaining: seconds,
                total: seconds,
                source: source
            )
        } else if isWorkoutPaused {
            setPausedRestTimer(
                remaining: seconds,
                total: seconds,
                source: .workout
            )
        } else {
            startRestTimer(remaining: seconds, total: seconds)
        }
    }

    /// Toggle the rest timer between running and manually paused.
    func toggleRestTimerPause() {
        guard !isWorkoutPaused else { return }

        switch restTimer {
        case .running:
            pauseRestTimerIfNeeded(referenceDate: Date(), source: .manual)

        case .paused(let remaining, let total, let source):
            guard source == .manual else { return }
            startRestTimer(remaining: remaining, total: total)

        case .idle, .finished:
            return
        }
    }

    /// Dismiss the rest timer and cancel the Combine subscription.
    func dismissTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
        timerStartDate = nil
        timerTotalDuration = 0
        restTimer = .idle

        clearPersistedRestTimerState()
        cancelRestTimerNotification()
        updateLiveActivityState()
    }

    /// Recalculate timer remaining time after returning from background.
    ///
    /// Uses the stored start timestamp to compute how much time has actually
    /// elapsed, avoiding drift from suspended Timer.publish ticks.
    func recalculateTimerAfterBackground() {
        let referenceDate = Date()
        refreshElapsedTime(referenceDate: referenceDate)

        if isWorkoutPaused {
            updateLiveActivityState()
            return
        }

        guard case .running = restTimer,
              let startDate = timerStartDate else {
            updateLiveActivityState()
            return
        }

        let elapsed = Int(referenceDate.timeIntervalSince(startDate))
        let remaining = timerTotalDuration - elapsed

        if remaining <= 0 {
            restTimer = .finished
            timerSubscription?.cancel()
            timerSubscription = nil
            timerStartDate = nil
            captureRestDurationOnLastCompletedSet()
            clearPersistedRestTimerState()
            // Don't fire the in-app alert here — the background notification
            // already alerted the user while the app was suspended.
            cancelRestTimerNotification()
        } else {
            restTimer = .running(remaining: remaining, total: timerTotalDuration)
            persistRunningRestTimerState(remaining: remaining, total: timerTotalDuration)
        }

        updateLiveActivityState()
    }

    /// Decrement the timer by one second. Called by the Combine subscription.
    private func timerTick() {
        guard case .running(let remaining, let total) = restTimer else { return }
        if remaining <= 1 {
            restTimer = .finished
            timerSubscription?.cancel()
            timerSubscription = nil
            timerStartDate = nil
            captureRestDurationOnLastCompletedSet()
            clearPersistedRestTimerState()
            fireTimerAlert()
            // Update Live Activity only on state transition to .finished
            // (NOT every tick — countdown is rendered by ActivityKit's timer text style)
            updateLiveActivityState()
        } else {
            let newRemaining = remaining - 1
            restTimer = .running(remaining: newRemaining, total: total)
            persistRunningRestTimerState(remaining: newRemaining, total: total)
        }
    }

    private func startRestTimer(remaining: Int, total: Int, referenceDate: Date = Date()) {
        guard remaining > 0, total > 0 else { return }

        timerSubscription?.cancel()

        let elapsedBeforeResume = max(0, total - remaining)
        timerStartDate = referenceDate.addingTimeInterval(TimeInterval(-elapsedBeforeResume))
        timerTotalDuration = total
        restTimer = .running(remaining: remaining, total: total)

        persistRunningRestTimerState(remaining: remaining, total: total)

        timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.timerTick()
                }
            }

        scheduleRestTimerNotification(seconds: remaining)
        updateLiveActivityState()
    }

    private func setPausedRestTimer(
        remaining: Int,
        total: Int,
        source: RestTimerPauseSource
    ) {
        timerSubscription?.cancel()
        timerSubscription = nil
        timerStartDate = nil
        timerTotalDuration = total
        restTimer = .paused(remaining: remaining, total: total, source: source)
        persistPausedRestTimerState(remaining: remaining, total: total, source: source)
        cancelRestTimerNotification()
        updateLiveActivityState()
    }

    private func pauseRestTimerIfNeeded(
        referenceDate: Date = Date(),
        source: RestTimerPauseSource
    ) {
        guard case .running(let stateRemaining, let total) = restTimer else { return }

        let remaining: Int
        if let timerStartDate {
            let elapsed = Int(referenceDate.timeIntervalSince(timerStartDate))
            remaining = max(1, timerTotalDuration - elapsed)
        } else {
            remaining = stateRemaining
        }

        setPausedRestTimer(remaining: remaining, total: total, source: source)
    }

    private func resumeRestTimerIfNeeded(referenceDate: Date = Date()) {
        guard case .paused(let remaining, let total, let source) = restTimer,
              source == .workout,
              !isWorkoutPaused else { return }
        startRestTimer(remaining: remaining, total: total, referenceDate: referenceDate)
    }

    private func restoreRestTimerState(for workout: Workout, referenceDate: Date = Date()) {
        let defaults = UserDefaults.standard
        let persistedWorkoutId = defaults.string(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId)

        guard persistedWorkoutId == workout.id.uuidString else {
            clearPersistedRestTimerState()
            return
        }

        let savedTotal = defaults.integer(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration)
        guard savedTotal > 0 else {
            clearPersistedRestTimerState()
            return
        }

        timerTotalDuration = savedTotal

        if defaults.bool(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused) {
            let savedRemaining = max(
                1,
                defaults.integer(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration)
            )
            let savedSourceRaw = defaults.string(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource)
            let savedSource = RestTimerPauseSource(rawValue: savedSourceRaw ?? "") ?? (
                isWorkoutPaused ? .workout : .manual
            )
            if savedSource == .workout, !isWorkoutPaused {
                startRestTimer(remaining: savedRemaining, total: savedTotal, referenceDate: referenceDate)
            } else {
                restTimer = .paused(remaining: savedRemaining, total: savedTotal, source: savedSource)
                timerStartDate = nil
                timerSubscription?.cancel()
                timerSubscription = nil
                cancelRestTimerNotification()
            }
            return
        }

        guard let savedStartDate = defaults.object(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerStartDate) as? Date else {
            clearPersistedRestTimerState()
            return
        }

        let elapsed = Int(referenceDate.timeIntervalSince(savedStartDate))
        let remaining = savedTotal - elapsed
        if remaining > 0 {
            startRestTimer(remaining: remaining, total: savedTotal, referenceDate: referenceDate)
        } else {
            restTimer = .finished
            timerStartDate = nil
            timerSubscription?.cancel()
            timerSubscription = nil
            clearPersistedRestTimerState()
        }
    }

    private func persistRunningRestTimerState(remaining: Int, total: Int) {
        let defaults = UserDefaults.standard
        guard let workout, let timerStartDate else {
            clearPersistedRestTimerState()
            return
        }

        defaults.set(workout.id.uuidString, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId)
        defaults.set(timerStartDate, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerStartDate)
        defaults.set(total, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration)
        defaults.set(remaining, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration)
        defaults.set(false, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource)
    }

    private func persistPausedRestTimerState(
        remaining: Int,
        total: Int,
        source: RestTimerPauseSource
    ) {
        let defaults = UserDefaults.standard
        guard let workout else {
            clearPersistedRestTimerState()
            return
        }

        defaults.set(workout.id.uuidString, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerStartDate)
        defaults.set(total, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration)
        defaults.set(remaining, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration)
        defaults.set(true, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused)
        defaults.set(source.rawValue, forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource)
    }

    private func clearPersistedRestTimerState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerWorkoutId)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerStartDate)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerTotalDuration)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerRemainingDuration)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerIsPaused)
        defaults.removeObject(forKey: ActiveWorkoutSessionDefaultsKeys.restTimerPauseSource)
        cancelRestTimerNotification()
    }

    /// Capture the rest timer's total duration onto the most recently completed set
    /// for fatigue model v2. Only called when the timer runs to zero (not on early dismissal).
    private func captureRestDurationOnLastCompletedSet() {
        guard let exercise = currentExercise else { return }
        let sets = setsByExercise[exercise.id] ?? []
        // Find the most recently completed set (by completedAt timestamp).
        guard let lastCompleted = sets
            .filter({ $0.completed })
            .max(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) })
        else { return }
        lastCompleted.restDurationSeconds = timerTotalDuration
    }

    /// Fire haptic feedback and/or sound based on the restTimerAlertMode setting.
    private func fireTimerAlert() {
        let mode = restTimerAlertMode
        if mode == "vibration" || mode == "both" {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        if mode == "sound" || mode == "both" {
            AudioServicesPlaySystemSound(1007)
        }
        cancelRestTimerNotification()
    }

    // MARK: - Local Notification for Background Timer

    private static let restTimerNotificationId = "restTimerComplete"

    /// Schedule a local notification to fire when the rest timer expires.
    /// This ensures the user is alerted even when the app is backgrounded.
    private func scheduleRestTimerNotification(seconds: Int) {
        guard restTimerAlertMode != "off" else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.restTimerNotificationId])

        let content = UNMutableNotificationContent()
        content.title = "Rest Timer"
        content.body = "Rest period is over — time for your next set!"
        content.sound = Self.restTimerBackgroundNotificationUsesSystemSound(for: restTimerAlertMode) ? .default : nil

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, TimeInterval(seconds)), repeats: false)
        let request = UNNotificationRequest(identifier: Self.restTimerNotificationId, content: content, trigger: trigger)
        center.add(request)
    }

    /// Cancel any pending rest timer notification (e.g. timer dismissed or completed in foreground).
    private func cancelRestTimerNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.restTimerNotificationId])
    }

    static func restTimerBackgroundNotificationUsesSystemSound(for alertMode: String) -> Bool {
        switch alertMode {
        case "off":
            return false
        case "vibration", "sound", "both":
            // Local notifications do not produce a background vibration if no
            // sound is attached, so "vibration" still needs the system alert.
            return true
        default:
            return true
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
        let referenceDate = Date()
        let pausedElapsedSeconds = Int(currentElapsedTime(referenceDate: referenceDate))
        let elapsedTimerReferenceDate = referenceDate.addingTimeInterval(-TimeInterval(pausedElapsedSeconds))

        var isRestTimerRunning = false
        var isRestTimerPaused = false
        var restTimerEndDate: Date? = nil
        var restTimerTotalSeconds = 0
        var restTimerRemainingSeconds: Int? = nil
        var isRestTimerFinished = false

        switch restTimer {
        case .idle:
            break
        case .running(let remaining, let total):
            isRestTimerRunning = !isWorkoutPaused
            // Use the fixed start time + total duration for a stable end date.
            // This avoids flicker — each push won't shift the countdown.
            if let startDate = timerStartDate, !isWorkoutPaused {
                restTimerEndDate = startDate.addingTimeInterval(TimeInterval(timerTotalDuration))
            }
            restTimerTotalSeconds = total
            restTimerRemainingSeconds = remaining
        case .paused(let remaining, let total, _):
            isRestTimerPaused = true
            restTimerTotalSeconds = total
            restTimerRemainingSeconds = remaining
        case .finished:
            isRestTimerFinished = true
        }

        liveActivityManager.updateActivity(
            exerciseName: exerciseName,
            currentSetNumber: currentSetNumber,
            totalSets: totalSets,
            setTypeLabel: setTypeLabel,
            elapsedTimerReferenceDate: elapsedTimerReferenceDate,
            isWorkoutPaused: isWorkoutPaused,
            pausedElapsedSeconds: pausedElapsedSeconds,
            isRestTimerRunning: isRestTimerRunning,
            isRestTimerPaused: isRestTimerPaused,
            restTimerEndDate: restTimerEndDate,
            restTimerTotalSeconds: restTimerTotalSeconds,
            restTimerRemainingSeconds: restTimerRemainingSeconds,
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
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to load history: \(error)")
            #endif
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
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to load PRs: \(error)")
            #endif
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
        isLoadingWeightSuggestions = false
        isRefreshingWeightSuggestions = false

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
            defaultWeightIncrement = UnitConversion.resolvedStoredWeightIncrement(
                exerciseIncrement: nil,
                defaultIncrement: profile.prescriptionDefaultIncrement,
                unitPreference: profile.unitPreference
            )
            prescriptionEnabled = profile.prescriptionEnabled ?? true
            suggestionAdminModeEnabled = profile.prescriptionAdminModeEnabled ?? false

            let data = try await ExerciseInfoProvider.compute(
                currentSets: currentSets,
                exercise: exercise,
                exerciseId: exercise.id,
                currentWorkoutId: workout.id,
                trackingType: exercise.trackingType,
                weightIncrement: exercise.weightIncrement,
                setService: setService,
                loadPrescriptionService: loadPrescriptionService,
                healthProfileRepo: healthProfileRepo,
                unitPreference: unitPreference
            )
            exerciseInfoData = data
            exerciseInfoLoadedForExerciseId = exercise.id
        } catch {
            exerciseInfoData = nil
            exerciseInfoLoadedForExerciseId = exercise.id
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] ExerciseInfo load failed: \(error)")
            #endif
        }
    }

    // MARK: - Weight Suggestion Module

    /// Invalidate suggestion cache to force a refresh on next load.
    func invalidateSuggestions() {
        suggestionsLoadedForKey = nil
    }

    /// Invalidate exercise-info cache to force a refresh on next load.
    func invalidateExerciseInfo() {
        exerciseInfoData = nil
        exerciseInfoLoadedForExerciseId = nil
    }

    func refreshDisplaySettings() async {
        guard let profile = try? await settingsService.fetchSettings() else { return }
        unitPreference = profile.unitPreference
        defaultWeightIncrement = UnitConversion.resolvedStoredWeightIncrement(
            exerciseIncrement: nil,
            defaultIncrement: profile.prescriptionDefaultIncrement,
            unitPreference: profile.unitPreference
        )
        prescriptionEnabled = profile.prescriptionEnabled ?? true
        suggestionAdminModeEnabled = profile.prescriptionAdminModeEnabled ?? false
        invalidateExerciseInfo()
        invalidateSuggestions()
    }

    /// Refresh suggestions for the current exercise with explicit cache invalidation and presentation behavior.
    func refreshWeightSuggestions(
        invalidateCache: Bool = true,
        presentation: SuggestionRefreshPresentation = .preserveExisting,
        debounce: Duration? = nil
    ) async {
        let task = requestWeightSuggestionRefresh(
            mode: presentation,
            invalidateCache: invalidateCache,
            debounce: debounce
        )
        await task.value
    }

    /// Refresh configuration-dependent workout data after exercise settings change.
    func refreshCurrentExerciseConfigurationData() async {
        guard currentExercise != nil else { return }

        invalidateExerciseInfo()
        async let exerciseInfoRefresh: Void = loadExerciseInfo()
        async let suggestionRefresh: Void = refreshWeightSuggestions(
            invalidateCache: true,
            presentation: .preserveExisting
        )
        _ = await (exerciseInfoRefresh, suggestionRefresh)
    }

    /// Load weight suggestions for unfilled working sets of the current exercise.
    ///
    /// Uses SuggestionCoordinator to gather app models, resolve targets, and
    /// produce typed unavailable states. LoadPrescriptionService evaluates only
    /// when the current exercise is eligible. SuggestionExplainer then builds
    /// the read-only UI model from the evaluation result.
    func loadWeightSuggestions() async {
        await refreshWeightSuggestions(invalidateCache: false, presentation: .blocking)
    }

    @discardableResult
    private func requestWeightSuggestionRefresh(
        mode: SuggestionRefreshPresentation,
        invalidateCache: Bool = false,
        debounce: Duration? = nil
    ) -> Task<Void, Never> {
        suggestionRefreshTask?.cancel()
        suggestionRefreshGeneration &+= 1

        let generation = suggestionRefreshGeneration
        let expectedExerciseId = currentExercise?.id

        if invalidateCache {
            invalidateSuggestions()
        }

        isLoadingWeightSuggestions = mode == .blocking
        isRefreshingWeightSuggestions = mode == .preserveExisting

        let task = Task { [weak self] in
            if let debounce {
                do {
                    try await Task.sleep(for: debounce)
                } catch {
                    await self?.finishSuggestionRefreshIfCurrent(
                        generation: generation,
                        expectedExerciseId: expectedExerciseId,
                        mode: mode
                    )
                    return
                }
            }

            guard !Task.isCancelled else {
                await self?.finishSuggestionRefreshIfCurrent(
                    generation: generation,
                    expectedExerciseId: expectedExerciseId,
                    mode: mode
                )
                return
            }
            await self?.performWeightSuggestionRefresh(
                generation: generation,
                expectedExerciseId: expectedExerciseId,
                mode: mode
            )
        }

        suggestionRefreshTask = task
        return task
    }

    private func performWeightSuggestionRefresh(
        generation: UInt64,
        expectedExerciseId: UUID?,
        mode: SuggestionRefreshPresentation
    ) async {
        defer {
            finishSuggestionRefreshIfCurrent(
                generation: generation,
                expectedExerciseId: expectedExerciseId,
                mode: mode
            )
        }

        guard isCurrentSuggestionRefresh(generation, expectedExerciseId: expectedExerciseId) else { return }

        // Refresh setting-dependent inputs so cache keys and gating stay accurate.
        let resolvedProfile = await resolveSuggestionProfile()

        guard isCurrentSuggestionRefresh(generation, expectedExerciseId: expectedExerciseId) else { return }

        if let resolvedProfile {
            unitPreference = resolvedProfile.unitPreference
            defaultWeightIncrement = UnitConversion.resolvedStoredWeightIncrement(
                exerciseIncrement: nil,
                defaultIncrement: resolvedProfile.prescriptionDefaultIncrement,
                unitPreference: resolvedProfile.unitPreference
            )
            prescriptionEnabled = resolvedProfile.prescriptionEnabled ?? true
            suggestionAdminModeEnabled = resolvedProfile.prescriptionAdminModeEnabled ?? false
        }

        guard let currentExercise else {
            weightSuggestionData = nil
            suggestionsLoadedForKey = nil
            return
        }

        let preparation = SuggestionCoordinator.prepare(
            exercise: currentExercise,
            workout: workout,
            sets: currentSets,
            profile: resolvedProfile
        )

        // Cache check — skip if already computed for this exact input state
        guard suggestionsLoadedForKey != preparation.cacheKey else { return }

        do {
            let evaluation: SuggestionEvaluation
            if preparation.unavailableReason == nil {
                evaluation = try await loadPrescriptionService.evaluateSuggestions(
                    exerciseId: currentExercise.id,
                    pendingSets: preparation.pendingSets,
                    completedSessionSets: preparation.completedSessionSets
                )
            } else {
                evaluation = .unavailable(preparation.unavailableReason ?? .calculationFailed)
            }

            guard isCurrentSuggestionRefresh(generation, expectedExerciseId: expectedExerciseId) else { return }
            weightSuggestionData = SuggestionExplainer.makeWeightSuggestionData(
                preparation: preparation,
                evaluation: evaluation,
                unitPreference: unitPreference
            )
            suggestionsLoadedForKey = preparation.cacheKey
        } catch {
            guard isCurrentSuggestionRefresh(generation, expectedExerciseId: expectedExerciseId) else { return }
            #if DEBUG
            dbg("[WeightSuggestion] Failed to load suggestions: \(error)")
            #endif
            weightSuggestionData = SuggestionExplainer.makeWeightSuggestionData(
                preparation: preparation,
                evaluation: .unavailable(.calculationFailed),
                unitPreference: unitPreference
            )
            suggestionsLoadedForKey = nil
        }
    }

    private func resolveSuggestionProfile() async -> HealthProfile? {
        var resolvedProfile: HealthProfile? = try? await settingsService.fetchSettings()
        if resolvedProfile == nil {
            resolvedProfile = try? await healthProfileRepo.fetchOrCreate()
        }
        return resolvedProfile
    }

    private func isCurrentSuggestionRefresh(
        _ generation: UInt64,
        expectedExerciseId: UUID?
    ) -> Bool {
        suggestionRefreshGeneration == generation && currentExercise?.id == expectedExerciseId
    }

    private func finishSuggestionRefreshIfCurrent(
        generation: UInt64,
        expectedExerciseId: UUID?,
        mode: SuggestionRefreshPresentation
    ) {
        guard isCurrentSuggestionRefresh(generation, expectedExerciseId: expectedExerciseId) else { return }

        suggestionRefreshTask = nil
        switch mode {
        case .blocking:
            isLoadingWeightSuggestions = false
        case .preserveExisting:
            isRefreshingWeightSuggestions = false
        }
    }

    // MARK: - Summary Computation (T031)

    /// Compute workout summary statistics from in-memory state.
    ///
    /// Uses local ViewModel data (not database) — the sets are already loaded.
    func computeSummary() -> WorkoutSummaryData? {
        guard let workout else { return nil }
        let referenceDate = Date()
        ensureWorkoutClockInitialized(referenceDate: referenceDate)
        let duration = currentElapsedTime(referenceDate: referenceDate)

        var totalSets = 0
        var prsHit = 0
        var exerciseSummaries: [ExerciseSummary] = []
        var completedWorkoutSets: [WorkoutSet] = []
        var exerciseLookup: [UUID: Exercise] = [:]

        for exercise in exercises {
            let sets = setsByExercise[exercise.id] ?? []
            let completedSets = sets.filter { $0.completed }
            exerciseLookup[exercise.id] = exercise
            completedWorkoutSets.append(contentsOf: completedSets)

            let exerciseSetCount = completedSets.count
            totalSets += exerciseSetCount

            // Best weight and reps in this exercise
            let bestWeight = completedSets.compactMap(\.effectiveWeight).max()
            let bestReps = completedSets.map(\.prReps).max()

            // PRs hit (prStatus == .current)
            let exercisePRs = sets.filter { $0.prStatus == .current }.count
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
        let aggregate = WorkoutAggregateSummary.summarize(
            sets: completedWorkoutSets,
            exercisesById: exerciseLookup
        )

        return WorkoutSummaryData(
            date: workout.date,
            duration: duration,
            totalSets: totalSets,
            primaryMetric: aggregate.primaryMetric,
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
        let referenceDate = Date()
        ensureWorkoutClockInitialized(referenceDate: referenceDate)
        let durationSeconds = Int(currentElapsedTime(referenceDate: referenceDate))

        do {
            try await workoutService.finishWorkout(
                workout.id,
                title: title,
                notes: notes,
                perceivedEffort: perceivedEffort,
                durationSecondsOverride: durationSeconds
            )

            _ = await accessControlService.recordCompletedWorkoutIfNeeded()

            // Run adaptive fatigue learning before clearing local state
            await fatigueLearningService.processSessionEnd(workoutId: workout.id)

            stopWorkoutClockTicker()
            clearPersistedWorkoutClockState()
            clearPersistedSelectedExerciseState()

            // Clear local state
            self.workout = nil
            self.exercises = []
            self.selectedExerciseIndex = 0
            self.setsByExercise = [:]
            self.isWorkoutPaused = false
            self.accumulatedElapsedSeconds = 0
            self.lastWorkoutResumedAt = nil
            self.elapsedTime = 0
            dismissTimer()

            // End Live Activity (workout completed)
            liveActivityManager.endActivity()

            // Signal the View layer to dismiss (T035)
            self.isWorkoutFinished = true

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to finish workout: \(error)")
            #endif
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

            stopWorkoutClockTicker()
            clearPersistedWorkoutClockState()
            clearPersistedSelectedExerciseState()

            // Clear local state
            self.workout = nil
            self.exercises = []
            self.selectedExerciseIndex = 0
            self.setsByExercise = [:]
            self.isWorkoutPaused = false
            self.accumulatedElapsedSeconds = 0
            self.lastWorkoutResumedAt = nil
            self.elapsedTime = 0
            dismissTimer()

            // End Live Activity (workout discarded)
            liveActivityManager.endActivity()

            // Signal the View layer to dismiss
            self.isWorkoutFinished = true

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to discard workout: \(error)")
            #endif
        }
    }

    // MARK: - Private Helpers

    /// Apply affected set status changes from PR pipeline results.
    ///
    /// When a set is saved/edited/deleted, the PR pipeline may change
    /// PR status on other sets (e.g., demoting a previous PR owner).
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
                    if set.completed, isStatusUpgrade(from: set.prStatus, to: newStatus) {
                        continue
                    }
                    updatedSets[index].prStatus = newStatus
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
                        #if DEBUG
                        dbg("[ActiveWorkoutViewModel] Failed to persist orderInExercise for set \(set.id): \(error)")
                        #endif
                    }
                }
            }
        }
    }

    /// Walk all exercises in their current order and reassign each set's orderInWorkout
    /// so it matches the visual (warmup-first) order inside every exercise.
    /// Persists only sets whose value changed.
    private func reindexOrderInWorkout() {
        var global = 1
        for exercise in exercises {
            guard let sets = setsByExercise[exercise.id] else { continue }
            let ordered = sets.sorted { $0.orderInExercise < $1.orderInExercise }
            for set in ordered {
                if set.orderInWorkout != global {
                    set.orderInWorkout = global
                    set.updatedAt = Date()
                    Task {
                        do {
                            _ = try await setService.edit(set)
                        } catch {
                            #if DEBUG
                            dbg("[ActiveWorkoutViewModel] Failed to persist orderInWorkout for set \(set.id): \(error)")
                            #endif
                        }
                    }
                }
                global += 1
            }
        }
    }
}

// MARK: - SetTableDataSource Conformance

extension ActiveWorkoutViewModel: SetTableDataSource {
    func suggestionState(for setId: UUID) -> SetSuggestionState? {
        weightSuggestionData?.rowState(for: setId)
    }

    func suggestedWeight(for setId: UUID) -> Double? {
        weightSuggestionData?.suggestedWeight(for: setId)
    }

    func persistTargetRepOverride(_ set: WorkoutSet, min: Int?, max: Int?) async {
        do {
            try await setService.updateInProgressTargetRepOverride(
                setId: set.id,
                min: min,
                max: max
            )

            if let sets = setsByExercise[set.exerciseId] {
                setsByExercise[set.exerciseId] = sets
            }
        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to persist target rep override for set \(set.id): \(error)")
            #endif
        }
    }

    /// Draft edits only affect live suggestions for reps and RIR on incomplete sets.
    func markSetDirty(_ set: WorkoutSet, field: SetDraftField) {
        guard currentExercise?.id == set.exerciseId else { return }

        switch field {
        case .reps, .rir:
            requestWeightSuggestionRefresh(
                mode: .preserveExisting,
                invalidateCache: true,
                debounce: suggestionDraftEditDebounce
            )
        case .weight, .duration, .distance:
            break
        }
    }

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
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to update set note: \(error)")
            #endif
        }
    }

    private func applyCompletionInput(_ input: SetCompletionInput, to set: WorkoutSet) {
        let exercise = exercises.first { $0.id == set.exerciseId }

        set.weight = input.weight
        set.durationSeconds = input.durationSeconds
        set.distanceMeters = input.distanceMeters
        set.leftReps = input.leftReps
        set.rightReps = input.rightReps
        set.leftRIR = input.leftRIR
        set.rightRIR = input.rightRIR

        if exercise?.supportsUnilateralLogging == true, exercise?.unilateral == true {
            set.reps = input.reps
            set.rir = input.rir
            set.syncDerivedPerformanceFields(for: exercise)
        } else {
            set.reps = input.reps
            set.rir = input.rir
            set.side = nil
        }
    }
}
