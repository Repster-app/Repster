// SetTableDataSource.swift
// Shared protocol enabling SetTableView and ExerciseTabStripView to work with
// both ActiveWorkoutViewModel and EditWorkoutViewModel.
// Spec: 015-edit-historic-workout, contracts/view-contracts.md

import Foundation

/// Draft-edit field identity for set table rows.
enum SetDraftField: Sendable {
    case weight
    case reps
    case duration
    case distance
    case rir
}

struct SetCompletionInput: Sendable {
    let weight: Double?
    let reps: Int?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let rir: Double?
    let leftReps: Int?
    let rightReps: Int?
    let leftRIR: Double?
    let rightRIR: Double?

    init(
        weight: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rir: Double? = nil,
        leftReps: Int? = nil,
        rightReps: Int? = nil,
        leftRIR: Double? = nil,
        rightRIR: Double? = nil
    ) {
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rir = rir
        self.leftReps = leftReps
        self.rightReps = rightReps
        self.leftRIR = leftRIR
        self.rightRIR = rightRIR
    }
}

/// Applies the PR badge changes the pipeline reports to the sets a screen is holding.
///
/// One implementation, shared by `ActiveWorkoutViewModel` and `EditWorkoutViewModel`. They
/// carried byte-identical private copies, which is the drift risk that produced the Stage 1 RIR
/// near-miss — and they had already started to diverge in intent: `EditWorkoutViewModel`
/// separately re-reads statuses from the store in `refreshPersistedWorkoutPRState` and applies
/// them unconditionally, contradicting what its own copy of this function claimed to do.
///
/// **The "completed sets receive demotions but never promotions" rule used to live here and has
/// been removed** (decision recorded 2026-08-13). It never had an observable effect in any
/// shipped version: `PRService` writes each status onto the same `@Model` instance the ViewModel
/// holds *before* returning, so the guard compared a value against itself and never fired —
/// measured in `AffectedSetsPreconditionTests`. Step 5 replaces those shared instances with value
/// types, which would have brought the rule to life for the first time and made the screen
/// disagree with the store: delete or un-tick the set holding a record and the set that
/// legitimately inherits it would show no badge until the workout was reopened. The chosen
/// behaviour is that badges always match the stored state.
enum PRBadgeApplier {

    /// - Parameters:
    ///   - affectedSetIds: pipeline output. A **present but nil** value legitimately clears a
    ///     badge, so this must not be flattened with `??` — that would silently kill demotions.
    ///   - setsByExercise: the screen's set state, re-assigned per exercise where something
    ///     changed so `@Observable` notices.
    static func apply(
        _ affectedSetIds: [UUID: CachedPRStatus?],
        to setsByExercise: inout [UUID: [WorkoutSet]]
    ) {
        guard !affectedSetIds.isEmpty else { return }

        for (exerciseId, sets) in setsByExercise {
            var changed = false
            for set in sets {
                // `affectedSetIds[set.id]` is `CachedPRStatus??`; this unwraps the *outer*
                // optional only, so "present, but nil" reaches `set.prStatus` as a clear.
                guard let newStatus = affectedSetIds[set.id], set.prStatus != newStatus else {
                    continue
                }
                set.prStatus = newStatus
                changed = true
            }
            if changed {
                setsByExercise[exerciseId] = sets
            }
        }
    }
}

/// Data source protocol for set table and exercise tab strip components.
///
/// Conforming types provide exercise/set state and handle user actions
/// (complete set, add set, delete set, reorder exercises, etc.).
/// Both `ActiveWorkoutViewModel` and `EditWorkoutViewModel` conform.
@MainActor
protocol SetTableDataSource: AnyObject, Observable {

    // MARK: - State

    /// All exercises in the current workout, ordered by display position.
    ///
    /// Snapshots, not live models: these are read on the main actor during layout, and a
    /// live `Exercise` faults its properties back through the repository's background
    /// context — that is crash B (`SetTableView.inputHeaders` faulting `trackingType`
    /// while `ExerciseRepository.save` ran).
    var exercises: [ChartExerciseData] { get }

    /// Index of the currently selected exercise in the tab strip.
    ///
    /// This is the strip's tap target and nothing more. It is **not** a stable handle on what the
    /// user is looking at: mutating `exercises` shifts the array underneath a fixed integer, so the
    /// same index can silently come to mean a different exercise. Observe `selectedExerciseId` for
    /// that. See EXERCISE_REPLACE_AND_REORDER_DESIGN.md §3.
    var selectedExerciseIndex: Int { get set }

    /// Identity of the currently selected exercise.
    ///
    /// The screen's identity *is* the exercise; the index is an implementation detail of a
    /// horizontal strip. Views that need to react to "the user is now on a different exercise" —
    /// resetting the sub-tab, clearing derived caches, dismissing the keypad — must key off this
    /// rather than the index, because reordering past the selection or replacing in place changes
    /// the exercise while leaving the integer untouched.
    var selectedExerciseId: UUID? { get }

    // MARK: - Computed

    /// The currently selected exercise, or nil if no exercises exist.
    var currentExercise: ChartExerciseData? { get }

    /// Sets for the currently selected exercise, ordered by orderInExercise.
    var currentSets: [WorkoutSet] { get }

    /// Current display unit preference for set entry and read-only labels.
    var unitPreference: UnitPreference { get }

    /// Resolved global/default weight increment stored in kg.
    var defaultWeightIncrement: Double { get }

    // MARK: - Set Actions

    /// Complete or update a set with the given values.
    ///
    /// For new sets: persists via SetService.save().
    /// For existing sets: persists via SetService.edit().
    func completeSet(_ set: WorkoutSet, input: SetCompletionInput) async

    /// Add a new working set for the given exercise.
    func addSet(for exerciseId: UUID) async

    /// Add a new warmup set for the given exercise.
    func addWarmupSet(for exerciseId: UUID) async

    /// Uncomplete a set, flipping it back to incomplete state.
    func uncompleteSet(
        _ set: WorkoutSet,
        previousContribution: SetContributionSnapshot?
    ) async

    /// Delete a set from the workout.
    func deleteSet(_ set: WorkoutSet) async

    /// Change a set's type (e.g., warmup -> working -> dropset).
    func changeSetType(_ set: WorkoutSet, to type: SetType) async

    /// Mark a set as having unsaved text field changes.
    /// Called when the user edits a set-table field.
    func markSetDirty(_ set: WorkoutSet, field: SetDraftField)

    /// Update the note on a set. Called from the context menu note editor.
    func updateSetNote(_ set: WorkoutSet, note: String?) async

    /// Persist rep-target override guidance without invoking the full set edit pipeline.
    func persistTargetRepOverride(_ set: WorkoutSet, min: Int?, max: Int?) async

    // MARK: - Exercise Actions

    /// Reorder exercises by moving from source indices to destination.
    func reorderExercises(from source: IndexSet, to destination: Int)

    /// Remove the exercise at the given index and delete all its sets.
    func removeExercise(at index: Int) async

    /// Swap the exercise at `index` for `newExerciseId`, keeping its position in the strip.
    ///
    /// The outgoing exercise's sets are deleted and one empty working set is seeded, making this
    /// equivalent in data terms to delete-then-add — it removes the tab-walking, not the semantics.
    /// No-ops when the index is out of range or `newExerciseId` is already in the workout.
    func replaceExercise(at index: Int, with newExerciseId: UUID) async

    /// Analytics only: the user tapped an exercise tab.
    ///
    /// Exists because `selectedExerciseIndex` is written programmatically from nine
    /// places (restore on load, jump to a newly added exercise, clamp after
    /// removal, reorder, reset on finish and discard), so neither its `didSet` nor
    /// an `onChange` in the view can tell intent from bookkeeping. Only the tap
    /// gesture can.
    ///
    /// Default no-op, so the shared tab strip does not instrument the
    /// edit-historic-workout screen.
    func recordExerciseTabSelected()

    /// Sets grouped by exercise ID for checking completion status.
    var setsByExercise: [UUID: [WorkoutSet]] { get }

    /// Whether this screen can author superset grouping.
    ///
    /// False on the historic-edit screen. Marking is shared — grouping should be *visible* wherever
    /// the sets are — but authoring is not: creating a pair is a statement about how a session was
    /// trained, and the edit screen has no rest timer and no prompt for it to mean anything against.
    /// See SUPERSETS_IMPLEMENTATION_PLAN.md G2.
    var supportsSupersetAuthoring: Bool { get }

    /// Pair two exercises into a superset, mid-workout.
    func createSuperset(anchorExerciseId: UUID, partnerExerciseId: UUID) async

    /// Take an exercise out of its superset.
    func removeFromSuperset(exerciseId: UUID) async

    /// Optional row-addressable Smart Suggestion state for a specific pending set.
    /// Returns nil when suggestions are unavailable or the row has no pending state.
    func suggestionState(for setId: UUID) -> SetSuggestionState?

    /// Optional row-addressable suggested weight for a specific pending set.
    /// Returns nil when suggestions are unavailable or no mapping exists.
    func suggestedWeight(for setId: UUID) -> Double?
}

extension SetTableDataSource {
    func uncompleteSet(_ set: WorkoutSet) async {
        await uncompleteSet(set, previousContribution: nil)
    }
}

// MARK: - Supersets
//
// Derived, never stored. Grouping lives on `WorkoutSet.supersetGroupId`, and everything the screen
// needs about it is a read over `exercises` and `setsByExercise` — both already on this protocol.
// Putting it here rather than on a view model means the active-workout screen and the
// edit-historic-workout screen get identical grouping with no shared state and no duplication.
//
// Behaviour (rest suppression, the next-up prompt) deliberately does NOT live here: it belongs to
// `ActiveWorkoutViewModel` alone, which is the only conformer with a rest timer.
// See SUPERSETS_SCOPING.md and SUPERSETS_IMPLEMENTATION_PLAN.md G2.
extension SetTableDataSource {

    /// The superset group this exercise currently belongs to, or nil.
    func supersetGroupId(for exerciseId: UUID) -> UUID? {
        SupersetGrouping.groupId(for: exerciseId, in: setsByExercise)
    }

    /// Exercises in the given group, in the strip's own display order.
    func supersetMembers(of groupId: UUID) -> [ChartExerciseData] {
        SupersetGrouping.members(of: groupId, exercises: exercises, setsByExercise: setsByExercise)
    }

    /// Where to go after a set on this exercise, and whether getting there closes a round.
    func nextInSuperset(after exerciseId: UUID) -> SupersetGrouping.NextInGroup? {
        SupersetGrouping.next(after: exerciseId, exercises: exercises, setsByExercise: setsByExercise)
    }

    /// Whether this exercise is in a group with at least one partner.
    func isInSuperset(_ exerciseId: UUID) -> Bool {
        SupersetGrouping.isGrouped(exerciseId, exercises: exercises, setsByExercise: setsByExercise)
    }
}

/// The grouping rules, as free functions over the two things they actually need.
///
/// Deliberately not methods on the protocol: every rule here is a pure read over `exercises` and
/// `setsByExercise`, and conforming a test double to the whole of `SetTableDataSource` to check
/// "is this exercise in a group" would be ceremony around nothing. The protocol extension above is
/// thin delegation so both screens still get identical behaviour.
enum SupersetGrouping {

    /// Any non-nil set decides the exercise's group.
    ///
    /// Writes are all-or-nothing per exercise (SUPERSETS_SCOPING.md §6), so an exercise's sets
    /// always agree and the first non-nil is the only one there is. The scan is defensive: rows
    /// written before `SetService.create` carried the field can still disagree, and
    /// `sets.first?.supersetGroupId` would pick arbitrarily between them.
    static func groupId(for exerciseId: UUID, in setsByExercise: [UUID: [WorkoutSet]]) -> UUID? {
        setsByExercise[exerciseId]?.lazy.compactMap(\.supersetGroupId).first
    }

    /// Exercises in the group, in the order `exercises` already holds them.
    ///
    /// Returns the raw list including a group of one. **A group of fewer than two is not a
    /// group** — reachable by deleting or replacing one half of a pair, or by importing a
    /// template whose group names a single exercise — and every caller must treat it as ungrouped.
    /// `isGrouped`, `next` and `isLastMember` all do; a caller reading this directly must too.
    static func members(
        of groupId: UUID,
        exercises: [ChartExerciseData],
        setsByExercise: [UUID: [WorkoutSet]]
    ) -> [ChartExerciseData] {
        exercises.filter { self.groupId(for: $0.id, in: setsByExercise) == groupId }
    }

    static func isGrouped(
        _ exerciseId: UUID,
        exercises: [ChartExerciseData],
        setsByExercise: [UUID: [WorkoutSet]]
    ) -> Bool {
        guard let id = groupId(for: exerciseId, in: setsByExercise) else { return false }
        return members(of: id, exercises: exercises, setsByExercise: setsByExercise).count > 1
    }

    /// Where to go after finishing a set on `exerciseId`, and whether getting there closed a round.
    struct NextInGroup: Equatable {
        let exercise: ChartExerciseData

        /// True when the walk ran off the end of the group and came back to the start.
        ///
        /// This is what "the round is over" means, and it is the only thing rest depends on:
        /// alternating *within* a round earns no rest, completing one does.
        let wrapped: Bool
    }

    /// The next member of the group with work left, walking in strip order and wrapping once.
    ///
    /// Cyclic rather than one-directional so the prompt works on both legs of a round: Bench sends
    /// you to Incline, and Incline sends you back to Bench for the next round. Members with nothing
    /// incomplete left are skipped, which is what stops a finished partner from swallowing the rest
    /// of your rests — the previous one-directional version suppressed rest for every non-last
    /// member regardless of whether the partner still had sets.
    ///
    /// Returns nil when no *other* member has work left. `exerciseId` itself is never returned:
    /// there is nothing to jump to when the answer is "stay here".
    static func next(
        after exerciseId: UUID,
        exercises: [ChartExerciseData],
        setsByExercise: [UUID: [WorkoutSet]]
    ) -> NextInGroup? {
        guard let id = groupId(for: exerciseId, in: setsByExercise) else { return nil }
        let group = members(of: id, exercises: exercises, setsByExercise: setsByExercise)
        guard group.count > 1,
              let position = group.firstIndex(where: { $0.id == exerciseId })
        else { return nil }

        for offset in 1..<group.count {
            let index = (position + offset) % group.count
            let candidate = group[index]
            guard hasWorkLeft(candidate.id, in: setsByExercise) else { continue }
            // `offset` never reaches `group.count`, so a wrapped index is always < position.
            return NextInGroup(exercise: candidate, wrapped: index < position)
        }
        return nil
    }

    /// Whether an exercise still has a working set to perform.
    ///
    /// Warm-ups are excluded deliberately: a leftover un-ticked warm-up row is common
    /// (UNPERFORMED_SETS_SCOPING.md) and should not make the app send someone back to an exercise
    /// they are finished with.
    static func hasWorkLeft(_ exerciseId: UUID, in setsByExercise: [UUID: [WorkoutSet]]) -> Bool {
        (setsByExercise[exerciseId] ?? []).contains { !$0.completed && $0.setType != .warmup }
    }

    /// Contiguous runs of the display order, for anything that draws grouping.
    ///
    /// A run is either one ungrouped exercise or two-plus adjacent members of the same group.
    /// **Non-adjacent members of one group produce separate runs** — a template can already
    /// assign group A to exercises 1 and 3 with something else between them
    /// (`CreateEditTemplateViewModel.setSupersetGroup` has no contiguity check), and a container
    /// spanning an exercise that is not in the group is worse than no marking at all.
    /// See SUPERSETS_IMPLEMENTATION_PLAN.md G4.
    static func runs(
        exercises: [ChartExerciseData],
        setsByExercise: [UUID: [WorkoutSet]]
    ) -> [Run] {
        var result: [Run] = []
        for exercise in exercises {
            let id = groupId(for: exercise.id, in: setsByExercise)
            if let id, var last = result.last, last.groupId == id {
                last.exercises.append(exercise)
                result[result.count - 1] = last
            } else {
                result.append(Run(groupId: id, exercises: [exercise]))
            }
        }
        return result
    }

    /// One horizontal run in the tab strip.
    ///
    /// An **unmarked run always holds exactly one exercise** — ungrouped exercises never merge, and
    /// a non-contiguous group breaks into single-exercise runs. Renderers can rely on that.
    struct Run: Equatable, Identifiable {
        /// The leading exercise's id. Stable across re-renders because it comes from display order.
        var id: UUID { exercises[0].id }

        /// The group these exercises share, or nil when ungrouped. Non-nil with a single
        /// exercise is a group of one and must render unmarked — see `isMarked`.
        var groupId: UUID?
        var exercises: [ChartExerciseData]

        /// Whether this run should be drawn as a superset container.
        var isMarked: Bool { groupId != nil && exercises.count > 1 }
    }
}

extension SetTableDataSource {
    var supportsSupersetAuthoring: Bool { false }
    func createSuperset(anchorExerciseId: UUID, partnerExerciseId: UUID) async {}
    func removeFromSuperset(exerciseId: UUID) async {}
    func recordExerciseTabSelected() {}
    func suggestionState(for setId: UUID) -> SetSuggestionState? { nil }
    func suggestedWeight(for setId: UUID) -> Double? {
        suggestionState(for: setId)?.suggestion?.suggestedWeight
    }
    func persistTargetRepOverride(_ set: WorkoutSet, min: Int?, max: Int?) async {
        let _ = set
        let _ = min
        let _ = max
    }
}
