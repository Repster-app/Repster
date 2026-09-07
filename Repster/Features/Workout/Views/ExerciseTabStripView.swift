// ExerciseTabStripView.swift
// Horizontal scrollable tab strip for navigating exercises in the active workout.
// Spec: design-system.md — Active tab = accent bg + white text, inactive = bgCard + textTertiary
// Contract: WP04 T018 (strip), T019 (styling), T020 (delete context menu), T021 (reorder)
//
// Connects to any SetTableDataSource for exercises and selectedExerciseIndex.
// All business logic delegates to the data source — this view only handles presentation and gestures.

import SwiftUI

/// Horizontal scrollable tab strip for switching between exercises.
///
/// Features:
/// - Tap a tab to switch to that exercise
/// - Active tab: accent blue background, white text
/// - Inactive tab: bgCard background, textTertiary text
/// - Auto-scrolls to keep the active tab visible
/// - Long-press shows "Delete Exercise" with confirmation
/// - Context menu includes "Move Left" / "Move Right" for reordering, and "Reorder
///   Exercises…" for the whole workout at once when `showsReorderSheet` is on
struct ExerciseTabStripView: View {

    // MARK: - Dependencies

    /// The data source providing exercise data and actions.
    var dataSource: any SetTableDataSource

    /// Needed only to build the replacement picker, which reuses `ExerciseListView` in browse mode.
    var services: ServiceContainer

    /// Whether the long-press menu offers "Reorder Exercises…".
    ///
    /// Off by default so `EditWorkoutView`, which shares this strip, is unchanged. Reordering a
    /// past workout works — `EditWorkoutViewModel.reorderExercises` persists as of 2026-08-29 —
    /// but shipping the sheet there was not part of what was scoped, and turning it on later is
    /// this one argument.
    var showsReorderSheet: Bool = false

    // MARK: - State

    /// Whether the delete confirmation alert is showing.
    @State private var showDeleteConfirmation = false

    /// The index of the exercise being deleted (set before showing confirmation).
    @State private var exerciseToDeleteIndex = 0

    /// The index of the exercise being replaced, or nil when no replace is in flight.
    ///
    /// Carried across the confirmation *and* the picker, so it is resolved to an identity at the
    /// moment the replacement is chosen rather than held as a stale integer.
    @State private var exerciseToReplaceIndex: Int?

    /// Whether the replacement picker is showing.
    @State private var showReplacePicker = false

    /// Whether the "this will remove logged sets" confirmation is showing.
    @State private var showReplaceConfirmation = false

    /// Whether the reorder sheet is showing.
    @State private var showReorderSheet = false

    /// The exercise a superset is being built around, or nil when no picker is in flight.
    ///
    /// Boxed rather than a bare `UUID` so `.sheet(item:)` can key on it — the anchor has to survive
    /// the sheet's lifetime, and holding it as an index would let a reorder or a replace behind the
    /// sheet silently repoint it at a different exercise.
    @State private var supersetAnchor: SupersetAnchor?

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(supersetRuns) { run in
                        if let color = markColor(for: run) {
                            supersetContainer(run: run, color: color)
                        } else {
                            // An unmarked run always holds exactly one exercise — see
                            // `SupersetGrouping.Run`. That covers ungrouped exercises, a group of
                            // one, and each half of a non-contiguous group.
                            tab(for: run.exercises[0], insideContainer: false)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 5)
            }
            // Auto-scroll needs *both* triggers, and neither subsumes the other:
            // the index moves when the selected tab changes position (a reorder), and the identity
            // changes when a different exercise takes the same slot (reorder past the selection, or
            // a replace). Keying on one alone leaves the active tab parked off-screen in the other
            // case. See EXERCISE_REPLACE_AND_REORDER_DESIGN.md §3.
            .onChange(of: dataSource.selectedExerciseIndex) { _, _ in
                scrollToSelectedExercise(proxy: proxy)
            }
            .onChange(of: dataSource.selectedExerciseId) { _, _ in
                scrollToSelectedExercise(proxy: proxy)
            }
        }
        .alert("Replace \(replaceTargetName)?", isPresented: $showReplaceConfirmation) {
            Button("Cancel", role: .cancel) { exerciseToReplaceIndex = nil }
            Button("Replace", role: .destructive) { showReplacePicker = true }
        } message: {
            Text("\(replaceTargetCompletedSetCount) logged \(replaceTargetCompletedSetCount == 1 ? "set" : "sets") will be removed.")
        }
        .sheet(isPresented: $showReplacePicker, onDismiss: { exerciseToReplaceIndex = nil }) {
            NavigationStack {
                ExerciseListView(
                    mode: .browse,
                    onExercisesSelected: { selectedIds in
                        guard let newId = selectedIds.first,
                              let index = exerciseToReplaceIndex else { return }
                        Task {
                            await dataSource.replaceExercise(at: index, with: newId)
                            showReplacePicker = false
                        }
                    },
                    services: services
                )
            }
        }
        .sheet(isPresented: $showReorderSheet) {
            NavigationStack {
                ReorderExercisesSheet(dataSource: dataSource) {
                    showReorderSheet = false
                }
            }
        }
        .sheet(item: $supersetAnchor) { anchor in
            let anchorId = anchor.id
            NavigationStack {
                SupersetPartnerPicker(
                    anchor: dataSource.exercises.first(where: { $0.id == anchorId }),
                    candidates: dataSource.exercises.filter { $0.id != anchorId },
                    isAdjacent: { candidateId in
                        guard let anchorIndex = dataSource.exercises.firstIndex(where: { $0.id == anchorId }),
                              let candidateIndex = dataSource.exercises.firstIndex(where: { $0.id == candidateId })
                        else { return true }
                        return abs(candidateIndex - anchorIndex) == 1
                    },
                    onPick: { partnerId in
                        Task {
                            await dataSource.createSuperset(
                                anchorExerciseId: anchorId,
                                partnerExerciseId: partnerId
                            )
                            supersetAnchor = nil
                        }
                    },
                    onCancel: { supersetAnchor = nil }
                )
            }
        }
        .alert("Delete Exercise?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await dataSource.removeExercise(at: exerciseToDeleteIndex)
                }
            }
        } message: {
            Text("This will remove the exercise and all its sets from this workout.")
        }
    }

    // MARK: - Supersets

    private var supersetRuns: [SupersetGrouping.Run] {
        SupersetGrouping.runs(
            exercises: dataSource.exercises,
            setsByExercise: dataSource.setsByExercise
        )
    }

    /// The container colour for a run, or nil when it must not be drawn as a group.
    ///
    /// Shared with `ReorderExercisesSheet` — the sheet is opened from this strip and draws the
    /// same groups, so the two have to agree on which group is which colour.
    private func markColor(for run: SupersetGrouping.Run) -> Color? {
        SupersetPalette.color(for: run, in: supersetRuns)
    }

    /// Two-plus adjacent members of one group, drawn as a single segmented control.
    ///
    /// Same grammar as `WorkoutSubTabBar` directly below the strip, which is the point: a superset
    /// is one control holding several things, and the app already has that shape. The container is
    /// 4pt taller than a loose tab (2pt padding each side) and the inner tabs keep their full
    /// height, so the tap target does not shrink — see SUPERSETS_IMPLEMENTATION_PLAN.md PR3.
    @ViewBuilder
    private func supersetContainer(run: SupersetGrouping.Run, color: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(run.exercises.enumerated()), id: \.element.id) { position, exercise in
                if position > 0 {
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                        .frame(width: 15)
                        .accessibilityHidden(true)
                }
                tab(for: exercise, insideContainer: true)
            }
        }
        .padding(2)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(color.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Superset: \(run.exercises.map(\.name).joined(separator: ", then "))")
    }

    /// One tab, with the tap and long-press behaviour that used to live inline in the `ForEach`.
    ///
    /// The index is resolved by identity rather than passed in: runs are built from display order,
    /// so an enumerated index over a run is a position *within the run*, not within the workout,
    /// and every action below addresses the workout.
    @ViewBuilder
    private func tab(for exercise: ChartExerciseData, insideContainer: Bool) -> some View {
        let index = dataSource.exercises.firstIndex(where: { $0.id == exercise.id }) ?? 0

        ExerciseTab(
            name: exercise.name,
            isActive: index == dataSource.selectedExerciseIndex,
            isCompleted: isExerciseCompleted(exercise),
            insideContainer: insideContainer
        )
        .id(exercise.id)
        .onTapGesture {
            guard index != dataSource.selectedExerciseIndex else { return }
            dataSource.recordExerciseTabSelected()
            withAnimation(.easeInOut(duration: 0.2)) {
                dataSource.selectedExerciseIndex = index
            }
        }
        .contextMenu {
            // Move Left (if not first)
            if index > 0 {
                Button {
                    dataSource.reorderExercises(
                        from: IndexSet(integer: index),
                        to: index - 1
                    )
                } label: {
                    Label("Move Left", systemImage: "arrow.left")
                }
            }

            // Move Right (if not last)
            if index < dataSource.exercises.count - 1 {
                Button {
                    dataSource.reorderExercises(
                        from: IndexSet(integer: index),
                        to: index + 2
                    )
                } label: {
                    Label("Move Right", systemImage: "arrow.right")
                }
            }

            // Same job as the two above at a different scale, so it belongs with them. Pointless
            // with one exercise, which is the rule Delete already follows.
            if showsReorderSheet && dataSource.exercises.count > 1 {
                Button {
                    showReorderSheet = true
                } label: {
                    Label("Reorder Exercises…", systemImage: "arrow.up.arrow.down")
                }
            }

            // Only when there is a movement group above it to separate. With one exercise every
            // item above is hidden, and this would otherwise open the menu.
            if dataSource.exercises.count > 1 {
                Divider()
            }

            if dataSource.supportsSupersetAuthoring {
                if dataSource.isInSuperset(exercise.id) {
                    Button {
                        Task { await dataSource.removeFromSuperset(exerciseId: exercise.id) }
                    } label: {
                        Label("Remove from Superset", systemImage: "arrow.left.and.right")
                    }
                } else if dataSource.exercises.count > 1 {
                    Button {
                        supersetAnchor = SupersetAnchor(id: exercise.id)
                    } label: {
                        Label("Superset with…", systemImage: "chevron.left.chevron.right")
                    }
                }
            }

            Button {
                beginReplace(at: index)
            } label: {
                Label("Replace Exercise…", systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()

            // Delete Exercise (only if more than 1 exercise)
            if dataSource.exercises.count > 1 {
                Button("Delete Exercise", role: .destructive) {
                    exerciseToDeleteIndex = index
                    showDeleteConfirmation = true
                }
            }
        }
    }

    /// Open the replacement flow for `index`.
    ///
    /// Silent when nothing is logged — substituting a movement you have not started is the common
    /// case and a confirmation there is friction for nothing. Confirms, naming the count, once any
    /// set is completed, because those rows are about to be deleted.
    private func beginReplace(at index: Int) {
        exerciseToReplaceIndex = index
        if completedSetCount(at: index) > 0 {
            showReplaceConfirmation = true
        } else {
            showReplacePicker = true
        }
    }

    private func completedSetCount(at index: Int) -> Int {
        guard index >= 0, index < dataSource.exercises.count else { return 0 }
        let exerciseId = dataSource.exercises[index].id
        return dataSource.setsByExercise[exerciseId]?.filter(\.completed).count ?? 0
    }

    private var replaceTargetName: String {
        guard let index = exerciseToReplaceIndex,
              index >= 0, index < dataSource.exercises.count else { return "Exercise" }
        return dataSource.exercises[index].name
    }

    private var replaceTargetCompletedSetCount: Int {
        completedSetCount(at: exerciseToReplaceIndex ?? -1)
    }

    /// Keep the active tab visible. Safe to call twice for one selection change — `scrollTo` on an
    /// already-centred id is a no-op.
    private func scrollToSelectedExercise(proxy: ScrollViewProxy) {
        guard let selectedId = dataSource.selectedExerciseId else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(selectedId, anchor: .center)
        }
    }

    /// Check if all sets for an exercise are completed.
    private func isExerciseCompleted(_ exercise: ChartExerciseData) -> Bool {
        guard let sets = dataSource.setsByExercise[exercise.id], !sets.isEmpty else { return false }
        return sets.allSatisfy { $0.completed }
    }
}

/// The exercise a superset is being built around, boxed for `.sheet(item:)`.
private struct SupersetAnchor: Identifiable {
    let id: UUID
}

// MARK: - ExerciseTab

/// A single tab in the exercise tab strip.
///
/// Active tab: accent background, white text, 8pt radius.
/// Inactive tab: bgCard background, textTertiary text, 8pt radius.
/// Minimum 44pt height for gym-friendly tap targets.
private struct ExerciseTab: View {

    /// The exercise name displayed in the tab.
    let name: String

    /// Whether this tab is currently selected.
    let isActive: Bool

    /// Whether all sets for this exercise are completed.
    var isCompleted: Bool = false

    /// Whether this tab sits inside a superset container.
    ///
    /// Only the surface changes: the container paints the group's tint, so an inactive tab must be
    /// transparent — a `bgCard` fill would read as a tab sitting *on* the group rather than in it.
    /// Height and padding are deliberately untouched, so the tap target inside a group is the same
    /// as outside one.
    var insideContainer: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .white.opacity(0.8) : .success)
            }
        }
        .foregroundColor(isActive ? .white : .textTertiary)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(isActive ? Color.accent : (insideContainer ? Color.clear : Color.bgCard))
        .cornerRadius(7)
        .contentShape(Rectangle())
    }
}

// MARK: - Previews

#Preview("Multiple Exercises") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(spacing: 0) {
            // Simulated tab strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ExerciseTab(name: "Bench Press", isActive: true)
                    ExerciseTab(name: "Incline DB Press", isActive: false)
                    ExerciseTab(name: "Cable Fly", isActive: false)
                    ExerciseTab(name: "Tricep Pushdown", isActive: false)
                    ExerciseTab(name: "Overhead Extension", isActive: false)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            Spacer()
        }
    }
}

#Preview("Single Exercise") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ExerciseTab(name: "Squat", isActive: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            Spacer()
        }
    }
}

#Preview("Long Names") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ExerciseTab(name: "Standing Barbell Overhead Press", isActive: true)
                    ExerciseTab(name: "Seated Dumbbell Lateral Raise", isActive: false)
                    ExerciseTab(name: "Face Pulls", isActive: false)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            Spacer()
        }
    }
}

#Preview("Active States") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(spacing: 16) {
            ExerciseTab(name: "Active Tab", isActive: true)
            ExerciseTab(name: "Inactive Tab", isActive: false)
        }
        .padding()
    }
}
