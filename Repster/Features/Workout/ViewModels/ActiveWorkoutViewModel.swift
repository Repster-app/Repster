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

    /// Clear every rest-timer key in one call.
    ///
    /// Three places need this and two of them are outside `ActiveWorkoutViewModel` — a discard
    /// from `ContentView` and the data reset in `SettingsService` — which is exactly how they
    /// came to disagree about which keys existed. One list, one caller-visible name.
    static func clearRestTimerState(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: restTimerWorkoutId)
        defaults.removeObject(forKey: restTimerStartDate)
        defaults.removeObject(forKey: restTimerTotalDuration)
        defaults.removeObject(forKey: restTimerRemainingDuration)
        defaults.removeObject(forKey: restTimerIsPaused)
        defaults.removeObject(forKey: restTimerPauseSource)
    }
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
    private let analyticsService: any AnalyticsServiceProtocol
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
    var exercises: [ChartExerciseData] = []

    /// Index of the currently selected exercise tab.
    var selectedExerciseIndex: Int = 0 {
        didSet {
            guard selectedExerciseIndex != oldValue else { return }
            notifySelectedExerciseChangedIfNeeded()
        }
    }

    /// The exercise the last selection side effects were fired for.
    ///
    /// Lets `notifySelectedExerciseChangedIfNeeded()` be called from both the index `didSet` and the
    /// explicit re-anchor path without double-firing on the common tap-a-tab case, where both run.
    private var lastNotifiedExerciseId: UUID?

    /// Global default rest time from HealthProfile (fallback when exercise has none).
    private var globalDefaultRestTime: Int?

    /// Global default warmup rest time from HealthProfile. When nil, falls back to globalDefaultRestTime.
    private var globalDefaultWarmupRestTime: Int?

    /// Rest timer alert mode: "off", "vibration", "sound", or "both".
    private var restTimerAlertMode: String = HealthProfile.defaultAlertMode

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

    /// Whether Repster's own notification explainer is showing. See `RestAlarmPromptView`.
    var showRestAlarmPrompt: Bool = false

    /// True while the system permission sheet is up.
    var isRequestingRestAlarmAuthorization: Bool = false

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

    /// In-memory cache of suggestions snapshotted at the moment each set
    /// transitions pending → completed. Keyed by `WorkoutSet.id`. Used by the
    /// suggestion module's done strips to render "= suggested" / "+1 kg vs sug"
    /// comparisons. Not persisted — the comparison disappears once the workout
    /// closes (by design, per v1 spec).
    var completedSetSuggestionSnapshots: [UUID: SuggestionSnapshot] = [:]

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
    var currentExercise: ChartExerciseData? {
        guard selectedExerciseIndex >= 0,
              selectedExerciseIndex < exercises.count else { return nil }
        return exercises[selectedExerciseIndex]
    }

    /// `SetTableDataSource` conformance — identity of the selected exercise.
    ///
    /// Views observe this rather than `selectedExerciseIndex` so that reordering past the selection
    /// or replacing in place, both of which change the exercise without moving the integer, still
    /// reset the sub-tab, clear the derived caches and dismiss the keypad.
    var selectedExerciseId: UUID? { currentExercise?.id }

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
        analyticsService: any AnalyticsServiceProtocol = NoopAnalyticsService(),
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
        self.analyticsService = analyticsService
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

            // Held weakly by the coordinator: when this ViewModel goes away with the workout
            // cover, the reference nils itself and the rest alarm starts presenting as a banner
            // instead of alerting into a screen nobody is looking at.
            RestTimerAlarmCoordinator.shared.registerForegroundAlerter(self)

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
            var loadedExercises: [ChartExerciseData] = []
            for exerciseId in exerciseIds {
                if let exercise = try await exerciseService.fetchExerciseSnapshot(exerciseId) {
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
                self.restTimerAlertMode = profile.restTimerAlert ?? HealthProfile.defaultAlertMode
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

                // Also stash a display-layer snapshot for the done strip's
                // "= suggested" / "+1 kg vs sug" comparison. Captured here for
                // the same reason as predictionSnapshot — the suggestion is
                // about to be filtered out of the pending list.
                completedSetSuggestionSnapshots[set.id] = SuggestionSnapshot(
                    suggestedWeight: suggestion.suggestedWeight,
                    targetReps: suggestion.targetReps,
                    targetRepMin: suggestion.targetRepMin,
                    targetRepMax: suggestion.targetRepMax,
                    targetDisplayLabel: suggestion.targetDisplayLabel,
                    targetRIR: suggestion.targetRIR
                )
            } else {
                predictionSnapshot = nil
            }

            // 1/2. The typed values, the completion stamps and the pipeline all happen inside
            // the repository actor now. These twelve field writes used to run here, on the main
            // actor, against a model the repository's context owns.
            let result = try await setService.save(setId: set.id, input: input)

            // 3. Update local state with pipeline results
            set.effectiveWeight = result.effectiveWeight
            set.prStatus = result.prResult.newStatus

            // 4. Update any affected sets (e.g., demoted PR owners)
            PRBadgeApplier.apply(result.prResult.affectedSetIds, to: &setsByExercise)

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
            invalidateSetDerivedSubTabCaches()
            if currentExercise?.id == set.exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

            // 8. Analytics only — separates "opened a workout" from "logged something".
            trackFirstSetIfNeeded()

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to complete set: \(error)")
            #endif
        }
    }

    /// Emits `first set logged` once per workout, with the delay since the
    /// workout was started. A long or absent time-to-first-set is the clearest
    /// signal that someone opened a session and couldn't work out what to do.
    private func trackFirstSetIfNeeded() {
        ActiveWorkoutSessionMarker.incrementSetCount()
        guard ActiveWorkoutSessionMarker.markFirstSetLogged() else { return }

        let startedAt = ActiveWorkoutSessionMarker.startedAt() ?? Date()
        analyticsService.firstSetLogged(
            source: WorkoutStartContextStore.recall().source,
            secondsSinceStart: Date().timeIntervalSince(startedAt)
        )
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
            // Don't assign result.prResult.newStatus here — when the uncompleted
            // set owned the PR, handleDeletion → findNewPROwner returns the new
            // winner's setId/status, not this set's. SetService.uncomplete already
            // cleared set.prStatus = nil on the same @Model reference.
            PRBadgeApplier.apply(result.prResult.affectedSetIds, to: &setsByExercise)

            // The set is back in the pending list — drop any stale done-strip
            // snapshot so re-completing later captures a fresh suggestion.
            completedSetSuggestionSnapshots.removeValue(forKey: set.id)

            // Reassign array to trigger @Observable update
            if let sets = setsByExercise[exerciseId] {
                setsByExercise[exerciseId] = sets
            }

            // Update Live Activity (set progress changed)
            updateLiveActivityState()

            // Invalidate PR, history, and suggestion caches, then reload
            invalidateSetDerivedSubTabCaches()
            if currentExercise?.id == exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

            // Analytics only. Un-ticking a set is the user correcting something, so
            // this is the best confusion proxy the tap surface offers.
            analyticsService.recordWorkoutInteraction(.setsUncompleted)

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

        do {
            let newSet = try await setService.create(
                workoutId: workout.id,
                exerciseId: exerciseId,
                date: Date(),
                setType: .working,
                orderInWorkout: totalSets + 1,
                orderInExercise: exerciseSets.count + 1,
                weight: nil,
                reps: nil
            )

            // Append to local state
            var sets = setsByExercise[exerciseId] ?? []
            sets.append(newSet)
            setsByExercise[exerciseId] = sets

            // Update Live Activity (total sets changed)
            updateLiveActivityState()

            // A new set changes what the History and PRs sub-tabs would show.
            invalidateSetDerivedSubTabCaches()

            // Invalidate and refresh suggestions for the currently visible exercise
            if currentExercise?.id == exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

            analyticsService.recordWorkoutInteraction(.setsAdded)

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

        do {
            let newSet = try await setService.create(
                workoutId: workout.id,
                exerciseId: exerciseId,
                date: Date(),
                setType: .warmup,
                orderInWorkout: totalSets + 1,
                orderInExercise: insertionIndex + 1,
                weight: nil,
                reps: nil
            )

            // Insert at correct position and reindex
            exerciseSets.insert(newSet, at: insertionIndex)
            var orderingUpdates = reindexOrderInExercise(&exerciseSets)
            setsByExercise[exerciseId] = exerciseSets

            // Rewrite global orderInWorkout so the newly-inserted warmup isn't stranded
            // at the workout tail — keeps both order fields consistent.
            orderingUpdates += reindexOrderInWorkout()
            await persistSetOrdering(orderingUpdates)

            // A new set changes what the History and PRs sub-tabs would show.
            invalidateSetDerivedSubTabCaches()

            // Invalidate and refresh suggestions for the currently visible exercise
            if currentExercise?.id == exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

            // Same counter as `addSet` — the tally measures "sets added", and
            // splitting warmups out would answer a question nothing is asking.
            analyticsService.recordWorkoutInteraction(.setsAdded)

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
        let setId = set.id

        // Out of screen state before it leaves the store: `delete` awaits a PR and stats pipeline,
        // and the set table renders during it.
        var sets = setsByExercise[exerciseId] ?? []
        sets.removeAll { $0.id == setId }
        let orderingUpdates = reindexOrderInExercise(&sets)
        setsByExercise[exerciseId] = sets

        do {
            // Deleting a PR owner promotes another set; without this the new owner's badge
            // reaches the screen only because PRService mutated the instance we hold.
            let prResult = try await setService.delete(set)
            PRBadgeApplier.apply(prResult.affectedSetIds, to: &setsByExercise)

            await persistSetOrdering(orderingUpdates)

            // Update Live Activity (total sets changed)
            updateLiveActivityState()

            // Invalidate the sub-tab caches and refresh suggestions as needed
            invalidateSetDerivedSubTabCaches()

            // Deletion can change fatigue context and first-working-set freshness logic
            if currentExercise?.id == exerciseId {
                requestWeightSuggestionRefresh(mode: .preserveExisting, invalidateCache: true)
            }

            analyticsService.recordWorkoutInteraction(.setsDeleted)

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to delete set: \(error)")
            #endif
            // The row is still in the store but no longer on screen, and the reindex above already
            // renumbered the survivors in memory. Re-read instead of trying to unwind that.
            await loadActiveWorkout()
        }
    }

    /// Change the set type (e.g., working → warmup, warmup → dropset).
    ///
    /// Type change may affect PR eligibility, so the full edit pipeline runs.
    func changeSetType(_ set: WorkoutSet, to type: SetType) async {
        do {
            // The two field writes happen inside the repository actor now.
            let result = try await setService.changeSetType(setId: set.id, to: type)
            set.effectiveWeight = result.effectiveWeight
            set.prStatus = result.prResult.newStatus
            PRBadgeApplier.apply(result.prResult.affectedSetIds, to: &setsByExercise)

            // Invalidate the sub-tab caches and refresh suggestions as needed
            invalidateSetDerivedSubTabCaches()

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
                guard let exercise = try await exerciseService.fetchExerciseSnapshot(exerciseId) else {
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

        assertOrderingInvariant("addExercises")

        // Update Live Activity (exercise and set counts changed)
        updateLiveActivityState()
    }

    /// Remove an exercise and all its sets from the workout.
    ///
    /// The exercise leaves the screen *before* its rows leave the store. The loop below awaits once
    /// per set, and `ExerciseTabStripView` reads every exercise's sets on every render, so holding
    /// these across the loop would put deleted models in front of the main actor.
    func removeExercise(at index: Int) async {
        guard index >= 0, index < exercises.count else { return }

        let exercise = exercises[index]
        let exerciseSets = setsByExercise[exercise.id] ?? []

        // Anchor before the array shrinks — same reason as `reorderExercises`. Removing an exercise
        // *before* the selected one shifts the array left underneath a fixed integer, which used to
        // land the user on the exercise after the one they were on. When the anchor is the exercise
        // being removed, `setSelectedExercise` falls back to clamping, which is the old behaviour
        // and the right one for that case.
        let anchorId = currentExercise?.id

        // Remove from local state
        exercises.remove(at: index)
        setsByExercise.removeValue(forKey: exercise.id)

        setSelectedExercise(id: anchorId)
        assertOrderingInvariant("removeExercise")

        // Update Live Activity — unconditionally, because the exercise *count* changed even when
        // the selected exercise did not, and `setSelectedExercise` only fires on an identity change.
        updateLiveActivityState()

        // Delete all sets for this exercise
        var deleteFailed = false
        for set in exerciseSets {
            do {
                // Ignored deliberately: this exercise and all its rows are about to leave
                // the screen, so there is nothing on it left to re-badge.
                _ = try await setService.delete(set)
            } catch {
                deleteFailed = true
                #if DEBUG
                dbg("[ActiveWorkoutViewModel] Failed to delete set \(set.id) during exercise removal: \(error)")
                #endif
            }
        }

        // A partial failure leaves rows the screen has already forgotten. Re-read rather than guess.
        if deleteFailed {
            await loadActiveWorkout()
        }
    }

    /// Swap the exercise at `index` for `newExerciseId`, keeping its position in the strip.
    ///
    /// The outgoing exercise's sets are **deleted**, and one empty working set is seeded for the
    /// replacement. That makes replace exactly equivalent in data terms to the delete-then-add the
    /// user does today — the feature removes the tab-walking, not the semantics. Reassigning
    /// `exerciseId` onto the existing rows was rejected: 80 kg × 8 logged for Incline DB Press is
    /// not a Cable Fly set, and carrying it over would write fabricated history into the new
    /// exercise's PR table, e1RM series, charts and fatigue model.
    ///
    /// See EXERCISE_REPLACE_AND_REORDER_DESIGN.md §4.
    func replaceExercise(at index: Int, with newExerciseId: UUID) async {
        guard index >= 0, index < exercises.count else { return }
        let outgoing = exercises[index]
        guard outgoing.id != newExerciseId else { return }

        // The strip's `ForEach` is keyed by exercise ID, so a duplicate gives undefined selection
        // and animation. Rejected rather than merged — merging raises ordering questions that would
        // get answered implicitly.
        guard !exercises.contains(where: { $0.id == newExerciseId }) else { return }

        // Fetch before mutating anything. A failed fetch must leave the workout untouched rather
        // than punch a hole in it.
        let fetched: ChartExerciseData?
        do {
            fetched = try await exerciseService.fetchExerciseSnapshot(newExerciseId)
        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to fetch replacement exercise \(newExerciseId): \(error)")
            #endif
            return
        }
        guard let snapshot = fetched else { return }

        // That fetch suspended, so `index` is no longer trustworthy — never hold an index across an
        // await on this screen. Re-resolve by identity, the same discipline
        // `refreshCurrentExerciseSnapshot` follows.
        guard let slot = exercises.firstIndex(where: { $0.id == outgoing.id }) else { return }

        let outgoingSets = setsByExercise[outgoing.id] ?? []
        let selectedIdBefore = currentExercise?.id

        // Screen state first, store second. The rows must leave the screen *before* they leave the
        // store: the delete loop below awaits once per set, and `ExerciseTabStripView` reads every
        // exercise's sets on every render, so a deleted model would otherwise be handed to a view
        // body mid-loop. Same ordering, and the same reason, as `removeExercise`.
        exercises[slot] = snapshot
        setsByExercise[outgoing.id] = nil
        setsByExercise[snapshot.id] = []

        // Re-anchor before the awaits so the screen is coherent for the whole loop. When the
        // replaced slot was the selected one, the *identity* changed while the integer did not —
        // precisely the case `setSelectedExercise` exists for, and what dismisses the keypad still
        // bound to a row that is about to be deleted.
        setSelectedExercise(id: selectedIdBefore == outgoing.id ? snapshot.id : selectedIdBefore)

        for set in outgoingSets {
            do {
                // Ignored deliberately, as in `removeExercise`: PR badges are per-exercise, so no
                // set of any *other* exercise on screen can be affected by these deletions.
                _ = try await setService.delete(set)
            } catch {
                #if DEBUG
                dbg("[ActiveWorkoutViewModel] Failed to delete set \(set.id) during replace: \(error)")
                #endif
            }
        }

        // An exercise with no sets does not exist — it cannot be ordered and will not survive a
        // rebuild. `addSet` also handles the Live Activity, the sub-tab caches and the suggestion
        // refresh for the now-current exercise.
        await addSet(for: snapshot.id)

        // Mandatory, not tidy-up. `addSet` assigns the *global tail*, so the replacement's only set
        // has the highest `orderInWorkout` in the workout while sitting at position `slot` in the
        // array. Order is reconstructed from `MIN(orderInWorkout)` per exercise, so without this the
        // replacement looks correct on screen and jumps to the end of the strip the next time the
        // array is rebuilt — which is a back-tap and a resume away.
        let updates = reindexOrderInWorkout()
        assertOrderingInvariant("replaceExercise")
        await persistSetOrdering(updates)
    }

    /// Reorder exercises via drag gesture on tab strip.
    ///
    /// Rearranges the local exercises array and persists the new order
    /// by updating orderInWorkout on all sets so order survives screen transitions.
    func reorderExercises(from source: IndexSet, to destination: Int) {
        // Anchor on identity before the array moves. The old code corrected the index only when the
        // *moved* exercise was the selected one, so moving any other exercise past the selection
        // shifted the array underneath a fixed integer and silently switched the user to a different
        // exercise mid-set. One rule covers both cases: stay on the exercise you were on.
        let anchorId = currentExercise?.id

        exercises.move(fromOffsets: source, toOffset: destination)

        setSelectedExercise(id: anchorId)

        // Renumber synchronously, persist once. `reindexOrderInWorkout` produces exactly the
        // numbering the old loop did — walk `exercises` in array order, each exercise's sets in
        // `orderInExercise` order so warmups keep the lowest number within their exercise — but it
        // returns only what changed and hands it to a single transactional write.
        //
        // The loop this replaces ran the full `SetService.edit` pipeline once per set, inside an
        // unawaited `Task`, to change one integer. That is the pattern the SwiftData crash work
        // removed everywhere else (SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md §5.3 names it as the
        // concurrent writer that armed shipped crash B); the migration was scoped as "reindex after
        // a set insert/delete", so this caller fell outside it and was the last one left. It was
        // also the worst instance: reorder touches every set in the workout rather than one
        // exercise's, and Move Left is tapped repeatedly, so four taps spawned four overlapping
        // renumbering passes racing each other's `globalOrder` assignments.
        let updates = reindexOrderInWorkout()
        assertOrderingInvariant("reorderExercises")
        Task { await persistSetOrdering(updates) }
    }

    // MARK: - Workout Clock

    /// Toggle the workout clock between paused and running states.
    func toggleWorkoutPause() {
        guard workout != nil else { return }

        if isWorkoutPaused {
            resumeWorkoutClock()
        } else {
            pauseWorkoutClock()
            // Pauses only. Counting resumes as well would just double the number
            // for anyone who unpaused, which is nearly everyone.
            analyticsService.recordWorkoutInteraction(.workoutPauses)
        }
    }

    // MARK: - Analytics-only interaction hooks

    /// `SetTableDataSource` conformance — see that protocol for why the tap gesture
    /// reports this instead of the view observing `selectedExerciseIndex`.
    func recordExerciseTabSelected() {
        analyticsService.recordWorkoutInteraction(.exerciseSwitches)
    }

    /// Opens the add-exercise sheet. Exists so the count lives in one place rather
    /// than at each `showAddExerciseSheet = true` call site in the view.
    func presentAddExerciseSheet() {
        analyticsService.recordWorkoutInteraction(.exercisePickerOpens)
        showAddExerciseSheet = true
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

    private func exerciseHasPendingWork(_ exercise: ChartExerciseData) -> Bool {
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

        offerRestAlarmIfNeeded()

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

    /// Raise Repster's own explainer the first time a rest timer runs, and only then.
    ///
    /// Gated on `notDetermined` as well as the one-shot flag: someone who granted or denied in
    /// an older build has already spent the system prompt, and re-explaining would be noise.
    private func offerRestAlarmIfNeeded() {
        guard !RestTimerAlarmPreferences.hasBeenOffered,
              RestTimerAlarmPreferences.lastKnownAuthorization == .notDetermined else { return }
        showRestAlarmPrompt = true
    }

    /// The user asked for alerts. Only now does iOS get involved.
    func enableRestAlarmAuthorization() async {
        isRequestingRestAlarmAuthorization = true
        defer { isRequestingRestAlarmAuthorization = false }

        RestTimerAlarmPreferences.markOffered()
        let result = await RestTimerAlarmCoordinator.requestAuthorization()
        showRestAlarmPrompt = false

        // Granting mid-rest is useless unless the alarm already ticking gets scheduled — it was
        // skipped at start because there was no permission to schedule against.
        if result == .authorized, case .running(let remaining, _) = restTimer {
            scheduleRestTimerNotification(seconds: remaining)
        }
    }

    /// "Not now". iOS is never touched, so Settings can still turn this on later.
    func declineRestAlarmAuthorization() {
        RestTimerAlarmPreferences.markOffered()
        showRestAlarmPrompt = false
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
            // Derive the new total from elapsed + what is now displayed, rather than clamping
            // `total` on its own. Clamping the two independently let them disagree: subtracting
            // 15s at 0:05 showed 0:01 while `recalculateTimerAfterBackground` computed
            // `total - elapsed` = -10 and finished the timer instantly. Same end state, but the
            // band and the authoritative clock told different stories, and the notification was
            // scheduled off the displayed one.
            let elapsed: Int
            if let timerStartDate {
                elapsed = max(0, Int(Date().timeIntervalSince(timerStartDate)))
            } else {
                elapsed = max(0, total - remaining)
            }
            let newTotal = elapsed + newRemaining
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
            // Normally the background notification already alerted the user while the app was
            // suspended, so alerting again here would double up.
            //
            // When notifications are not authorized, nothing fired at all — and this branch
            // staying quiet on the assumption that something did is what made the alarm silent
            // in *every* state for those users. Alerting on return is late, but it is the only
            // chance left to say the rest is over.
            if RestTimerAlarmCoordinator.canAlertFromBackground {
                cancelRestTimerNotification()
            } else {
                fireTimerAlert()
            }
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
        ActiveWorkoutSessionDefaultsKeys.clearRestTimerState()
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
        // Before the alert, not after: a notification already in flight for this same expiry
        // can reach `willPresent` while this method is still running.
        RestTimerAlarmCoordinator.shared.noteInAppAlertFired()

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
    //
    // Owned by `RestTimerAlarmCoordinator` — REST_TIMER_ALARM_SCOPING.md §D1/§D5. It holds the
    // identifier where teardown paths outside this ViewModel can reach it, and it is the
    // notification-centre delegate that decides whether a foreground alarm becomes a banner.

    /// Schedule a local notification to fire when the rest timer expires.
    /// This ensures the user is alerted even when the app is backgrounded.
    private func scheduleRestTimerNotification(seconds: Int) {
        RestTimerAlarmCoordinator.schedule(seconds: seconds, alertMode: restTimerAlertMode)
    }

    /// Cancel any pending rest timer notification (e.g. timer dismissed or completed in foreground).
    private func cancelRestTimerNotification() {
        RestTimerAlarmCoordinator.cancel()
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

    /// Drop the sub-tab caches that any change to this workout's sets invalidates.
    ///
    /// Both sub-tabs read the *whole* exercise history, current workout included
    /// (`loadHistoryForCurrentExercise` does not filter by workout), so adding, deleting,
    /// completing, retyping or annotating a set makes both stale. They are guarded by
    /// `historyLoadedForExerciseId`/`prsLoadedForExerciseId`, so a stale cache survives until
    /// the user switches exercise.
    ///
    /// This is one call rather than two assignments at seven sites because four of those seven
    /// were missing the history half: `deleteSet`, `changeSetType`, `addSet` and `addWarmupSet`
    /// invalidated only the PR cache. Deleting a set therefore left it visible on the History
    /// tab. That was survivable while the tab held live models — the deleted row was undefined
    /// behaviour rather than obviously wrong — but the snapshot conversion turns it into
    /// deterministic staleness, so it has to be right now.
    private func invalidateSetDerivedSubTabCaches() {
        historyLoadedForExerciseId = nil
        prsLoadedForExerciseId = nil
    }

    /// Load history data for the current exercise. Used by the History sub-tab.
    ///
    /// Fetches all sets for the exercise, groups by workout, and sorts newest-first.
    /// Skips if already loaded for this exercise (cleared on exercise switch).
    func loadHistoryForCurrentExercise() async {
        guard let exercise = currentExercise else { return }
        guard historyLoadedForExerciseId != exercise.id else { return }

        do {
            // Snapshots: these are rendered by `ExerciseHistoryView` in a view body on the main
            // actor. Live models here were the same shape as crash B on the same screen.
            // Completed rows only. This fetch was unfiltered, so rows that exist but haven't
            // been performed — Copy Previous prefills, and the current workout's untouched
            // rows — were listed as history alongside genuinely logged sets. A workout whose
            // rows are all uncompleted drops out of the grouping entirely.
            let sets = try await setService.fetchSetSnapshots(for: exercise.id, limit: nil)
                .filter(\.completed)
            let grouped = Dictionary(grouping: sets) { $0.workoutId }
            let excludedWorkoutIds = try await workoutService.excludedWorkoutIdsForProgressionHistory(
                workoutIds: Set(grouped.keys),
                exerciseId: exercise.id
            )
            subTabHistory = grouped.map { workoutId, workoutSets in
                WorkoutHistoryGroup(
                    id: workoutId,
                    date: workoutSets.first?.date ?? Date(),
                    sets: workoutSets.sorted { $0.orderInExercise < $1.orderInExercise },
                    isExcludedFromProgression: excludedWorkoutIds.contains(workoutId)
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
        invalidateSetDerivedSubTabCaches()
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

        // Must run first: everything below reads `currentExercise`, so refreshing against a
        // stale snapshot would recompute the same pre-edit values.
        await refreshCurrentExerciseSnapshot()

        invalidateExerciseInfo()
        async let exerciseInfoRefresh: Void = loadExerciseInfo()
        async let suggestionRefresh: Void = refreshWeightSuggestions(
            invalidateCache: true,
            presentation: .preserveExisting
        )
        _ = await (exerciseInfoRefresh, suggestionRefresh)
    }

    /// Re-read the current exercise's snapshot from the store and splice it into `exercises`.
    ///
    /// `exercises` is otherwise written only on load and on add, so an edit made while the
    /// workout is open never reaches it: the rest timer keeps the old `defaultRestTime`, and
    /// `loadExerciseInfo`/the suggestion inputs keep the old `weightIncrement`. Before the
    /// snapshot conversion this array held the live `Exercise` the settings sheet mutated, so
    /// it updated for free — a frozen value type has to be refetched deliberately.
    /// The index is deliberately resolved *after* the fetch. `@MainActor` is reentrant, so
    /// `reorderExercises` or `removeExercise` can run during the await — an index captured
    /// before it would write the snapshot into the wrong slot, or out of bounds.
    private func refreshCurrentExerciseSnapshot() async {
        guard let exerciseId = currentExercise?.id,
              let refreshed = try? await exerciseService.fetchExerciseSnapshot(exerciseId),
              let index = exercises.firstIndex(where: { $0.id == exerciseId })
        else { return }

        exercises[index] = refreshed
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
                unitPreference: unitPreference,
                suggestionSnapshots: completedSetSuggestionSnapshots
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
                unitPreference: unitPreference,
                suggestionSnapshots: completedSetSuggestionSnapshots
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
        // Snapshots: this runs during `finishWorkout`, i.e. while the workout is being saved,
        // and every read below would otherwise fault a live model on the main actor.
        var completedWorkoutSets: [ChartSetData] = []
        var exerciseLookup: [UUID: ChartExerciseData] = [:]

        for exercise in exercises {
            let sets = (setsByExercise[exercise.id] ?? []).map(ChartSetData.init(from:))
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
        let completedSets = setsByExercise.values.flatMap { $0 }.filter(\.completed)
        let completedSetCount = completedSets.count
        let totalReps = completedSets.reduce(0) { $0 + ($1.reps ?? 0) }
        let prsHit = setsByExercise.values.flatMap { $0 }.filter { $0.prStatus == .current }.count
        let startContext = WorkoutStartContextStore.recall()
        // Read before the store is cleared below — `WorkoutStartContextStore.clear()`
        // resets the tally through the session marker.
        let interactions = WorkoutInteractionTally.snapshot()

        do {
            try await workoutService.finishWorkout(
                workout.id,
                title: title,
                notes: notes,
                perceivedEffort: perceivedEffort,
                durationSecondsOverride: durationSeconds
            )

            let accessSnapshot = await accessControlService.recordCompletedWorkoutIfNeeded()
            let accessTier: String = accessSnapshot.hasFullAccess ? "subscribed" : "free"

            let loggedRIRs = completedSets.compactMap(\.performanceRIR)
            let averageRIR: Double? = loggedRIRs.isEmpty
                ? nil
                : loggedRIRs.reduce(0, +) / Double(loggedRIRs.count)

            // Read before learning runs: `processSessionEnd` prunes, and the audit rows are what
            // carry prescribed-vs-actual. Failing to read them must never cost the user a finished
            // workout, so this degrades to "no data" rather than propagating.
            let adherence = (try? await fatigueLearningService.suggestionAdherence(
                workoutId: workout.id
            )) ?? .init()

            analyticsService.workoutCompleted(
                durationSeconds: TimeInterval(durationSeconds),
                completedSetCount: completedSetCount,
                exerciseCount: exercises.count,
                totalReps: totalReps,
                prsHit: prsHit,
                date: workout.date,
                source: startContext.source,
                templateUsed: startContext.templateUsed,
                unitSystem: unitPreference.rawValue,
                perceivedEffortEntered: perceivedEffort != nil,
                notesEntered: notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                excludedFromProgression: workout.excludesEntireWorkoutFromProgressionHistory,
                accessTier: accessTier,
                remainingFreeWorkouts: accessSnapshot.remainingFreeWorkouts,
                rirSetCount: loggedRIRs.count,
                averageRIR: averageRIR,
                suggestionSetsCompared: adherence.comparableSets,
                suggestionFollowedShare: adherence.followedShare,
                suggestionOverrideDirection: adherence.overrideDirection,
                interactions: interactions
            )
            WorkoutStartContextStore.clear()
            ReviewPromptService.recordCompletedWorkout()

            // Run adaptive fatigue learning before clearing local state
            await fatigueLearningService.processSessionEnd(workoutId: workout.id)

            stopWorkoutClockTicker()
            clearPersistedWorkoutClockState()
            clearPersistedSelectedExerciseState()
            clearScreenState()

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
    ///
    /// **Screen state is dropped before the delete, not after.** `deleteWorkout` commits the set
    /// deletions a third of the way through a pipeline that then rebuilds PRs and stats per
    /// exercise, and the main actor renders throughout — the workout clock alone invalidates every
    /// observer once a second. Reading a persisted property on a deleted model traps inside
    /// SwiftData, so nothing the view can reach may still point at these rows once the await starts.
    func discardWorkout() async {
        guard let workout else { return }
        let referenceDate = Date()
        ensureWorkoutClockInitialized(referenceDate: referenceDate)
        let durationSeconds = currentElapsedTime(referenceDate: referenceDate)
        let setCount = setsByExercise.values.flatMap { $0 }.count
        let startContext = WorkoutStartContextStore.recall()
        let interactions = WorkoutInteractionTally.snapshot()
        // Read off the model while it still exists — the analytics call below runs after the delete.
        let workoutId = workout.id
        let workoutDate = workout.date

        stopWorkoutClockTicker()
        clearScreenState()

        do {
            try await workoutService.deleteWorkout(workoutId)

            analyticsService.workoutDiscarded(
                durationSeconds: durationSeconds,
                setCount: setCount,
                date: workoutDate,
                source: startContext.source,
                templateUsed: startContext.templateUsed,
                interactions: interactions
            )
            WorkoutStartContextStore.clear()

            // The persisted clock and selection deliberately outlive the screen, so they are only
            // discarded once the workout really is gone — the failure path below reloads from them.
            clearPersistedWorkoutClockState()
            clearPersistedSelectedExerciseState()

            // End Live Activity (workout discarded)
            liveActivityManager.endActivity()

            // Signal the View layer to dismiss
            self.isWorkoutFinished = true

        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to discard workout: \(error)")
            #endif
            // The delete can fail partway, so the store is the only honest source for what is left.
            await loadActiveWorkout()
        }
    }

    /// Drop everything the workout screen renders from.
    ///
    /// Extracted because the discard runs it *before* its delete and the finish runs it *after*
    /// its save; keeping one list stops the two orderings from drifting apart.
    private func clearScreenState() {
        self.workout = nil
        self.exercises = []
        self.selectedExerciseIndex = 0
        self.setsByExercise = [:]
        self.isWorkoutPaused = false
        self.accumulatedElapsedSeconds = 0
        self.lastWorkoutResumedAt = nil
        self.elapsedTime = 0
        dismissTimer()
    }

    // MARK: - Private Helpers

    // MARK: - Reindexing
    //
    // These update local state for immediate UI feedback and *return* the persistence work
    // rather than doing it. Callers collect the updates and hand them to
    // `persistSetOrdering` in one batch.
    //
    // Previously each changed set was persisted by its own unawaited
    // `Task { setService.edit(set) }` — the full effectiveWeight → PR → stats → fatigue
    // pipeline for what is only an ordering change. With unchanged values that pipeline was
    // a no-op, so this loses no behaviour; what it removes is N concurrent saves per set
    // insert or delete, which is the concurrent writer described in §5.3 of
    // SWIFTDATA_CONCURRENCY_CRASH_ANALYSIS.md.

    /// Reindex orderInExercise for a set array after insertion/deletion.
    /// Returns the changes that still need persisting.
    private func reindexOrderInExercise(_ sets: inout [WorkoutSet]) -> [SetOrderUpdate] {
        var updates: [SetOrderUpdate] = []
        for (index, set) in sets.enumerated() {
            let newOrder = index + 1
            if set.orderInExercise != newOrder {
                set.orderInExercise = newOrder
                set.updatedAt = Date()
                updates.append(SetOrderUpdate(setId: set.id, orderInExercise: newOrder))
            }
        }
        return updates
    }

    /// Walk all exercises in their current order and reassign each set's orderInWorkout
    /// so it matches the visual (warmup-first) order inside every exercise.
    /// Returns the changes that still need persisting.
    private func reindexOrderInWorkout() -> [SetOrderUpdate] {
        var updates: [SetOrderUpdate] = []
        var global = 1
        for exercise in exercises {
            guard let sets = setsByExercise[exercise.id] else { continue }
            let ordered = sets.sorted { $0.orderInExercise < $1.orderInExercise }
            for set in ordered {
                if set.orderInWorkout != global {
                    set.orderInWorkout = global
                    set.updatedAt = Date()
                    updates.append(SetOrderUpdate(setId: set.id, orderInWorkout: global))
                }
                global += 1
            }
        }
        return updates
    }

    /// Trap in debug when the array order and the stored order disagree.
    ///
    /// The invariant: for exercises at array positions `i < j`, `MIN(orderInWorkout)` over `i`'s sets
    /// is strictly less than over `j`'s. `loadActiveWorkout` sorts on exactly that key, so the
    /// invariant holding in the store *is* "the strip reloads in the order the user left it".
    ///
    /// Worth asserting rather than trusting each call site, because a violation is invisible on
    /// screen by construction — the strip renders the in-memory array, so the damage only appears
    /// once that array is rebuilt from the store, which is a back-tap and a resume away. This is the
    /// only place it can be caught at the moment it is introduced.
    ///
    /// A trip here means either the mutation just made is wrong, or the workout's stored ordering
    /// was already corrupt on load — the shipped reorder race could leave it that way.
    /// See EXERCISE_REPLACE_AND_REORDER_DESIGN.md §1.1–1.3.
    private func assertOrderingInvariant(_ context: StaticString) {
        #if DEBUG
        let mins = exercises.compactMap { setsByExercise[$0.id]?.map(\.orderInWorkout).min() }
        // Strictly increasing, not merely sorted: two exercises sharing a MIN is also a violation,
        // and `sorted()` would wave it through.
        assert(
            zip(mins, mins.dropFirst()).allSatisfy(<),
            "ordering invariant violated at \(context): \(mins)"
        )
        #endif
    }

    /// Re-anchor the selection onto `exerciseId` after `exercises` has been mutated.
    ///
    /// Selection is identity-based, not positional. Reordering or replacing must keep the user on
    /// the exercise they were looking at, and must fire the switch side effects whenever the
    /// *exercise* changes — including when the resolved index lands on the same integer, which the
    /// `didSet` cannot see. See EXERCISE_REPLACE_AND_REORDER_DESIGN.md §3 and §5.
    ///
    /// Falls back to clamping the existing index when the anchor is gone (it was the exercise that
    /// was just removed), which keeps the user as close as possible to where they were.
    private func setSelectedExercise(id exerciseId: UUID?) {
        let resolvedIndex = exerciseId.flatMap { id in exercises.firstIndex(where: { $0.id == id }) }
            ?? min(max(0, selectedExerciseIndex), max(0, exercises.count - 1))

        selectedExerciseIndex = resolvedIndex       // didSet fires only if the integer moved
        notifySelectedExerciseChangedIfNeeded()     // fires if the exercise moved, integer or not
    }

    /// Fire the "the user is now looking at a different exercise" side effects exactly once.
    ///
    /// Selection changes arrive two ways: the index moves (tap a tab, clamp after a removal), or the
    /// index stays put while the exercise under it changes (reorder past the selection, replace in
    /// place). Both call through here, and `lastNotifiedExerciseId` keeps the common path — where
    /// both the index and the exercise changed — from firing twice.
    ///
    /// Neither side effect depends on the index: `persistSelectedExerciseState` stores the exercise
    /// *ID*, and the Live Activity shows the exercise name. So a pure position change correctly
    /// no-ops here, where the old `didSet` reissued both writes.
    private func notifySelectedExerciseChangedIfNeeded() {
        let currentId = currentExercise?.id
        guard currentId != lastNotifiedExerciseId else { return }
        lastNotifiedExerciseId = currentId

        persistSelectedExerciseState()
        updateLiveActivityState()
    }

    /// Persist a reindex in one transaction.
    ///
    /// Swallows and logs, matching what the previous per-set `Task`s did — an ordering
    /// write failing must not abort the caller's remaining work.
    private func persistSetOrdering(_ updates: [SetOrderUpdate]) async {
        guard !updates.isEmpty else { return }
        do {
            try await setService.applyOrdering(updates)
        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to persist set ordering: \(error)")
            #endif
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
        do {
            _ = try await setService.updateNote(setId: set.id, note: note)

            // Reassign array to trigger @Observable update for UI
            if let sets = setsByExercise[set.exerciseId] {
                setsByExercise[set.exerciseId] = sets
            }

            // The History rows carry a note indicator, so a note edit makes that tab stale too.
            invalidateSetDerivedSubTabCaches()
        } catch {
            #if DEBUG
            dbg("[ActiveWorkoutViewModel] Failed to update set note: \(error)")
            #endif
        }
    }

}

// MARK: - RestTimerForegroundAlerting

extension ActiveWorkoutViewModel: RestTimerForegroundAlerting {

    /// A running timer has a live Combine tick that will call `fireTimerAlert()` at zero, so a
    /// banner would be a second alert for the same event. Every other state — idle, paused,
    /// already finished — means nothing in-app is going to speak up.
    ///
    /// This has to be asked rather than assumed by either side: the tick and the notification
    /// trigger are scheduled for the same instant and genuinely race.
    var willAlertRestTimerInApp: Bool {
        if case .running = restTimer { return true }
        return false
    }
}
