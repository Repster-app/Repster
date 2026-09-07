// ReorderExercisesSheet.swift
// Reorder every exercise in the workout in one place, instead of walking one left at a time.
// Spec: EXERCISE_REPLACE_AND_REORDER_DESIGN.md §7 (step 5) — deferred until replace shipped, taken
// up once the complaint survived it.
//
// Reached from the tab strip's long-press menu. Move Left / Move Right stay where they are: they
// are the accessible path, and moving one place should not cost a screen.

import SwiftUI

/// A drag-to-reorder list over the workout's exercises.
///
/// Deliberately a plain `List` with `.onMove`. Drag handles, autoscroll past the edge of the
/// screen and VoiceOver's move actions all arrive correct rather than being rebuilt by hand on the
/// most safety-critical screen in the app — which is the whole reason this was chosen over
/// drag-to-reorder directly on the strip, where the gesture would have to arbitrate against the
/// horizontal scroll view's pan and the long-press menu on the same views.
///
/// **Rows are runs, not exercises.** A marked superset is one row carrying both members, so it
/// moves as a unit and nothing can be dropped between its halves — which is what the contiguity
/// rule in SUPERSETS_SCOPING.md §6 already requires. Un-grouping stays in the tab menu; this sheet
/// moves things, it does not restructure them.
///
/// **There is no Cancel.** Every drop commits through `reorderExercises(from:to:)`, which renumbers
/// synchronously and persists in one transactional write. A Cancel would need a second ordering
/// path to un-persist mid-workout, for an action you reverse by dragging the row back.
struct ReorderExercisesSheet: View {

    /// The workout being reordered.
    var dataSource: any SetTableDataSource

    /// Dismiss. Owned by the presenter so the sheet does not have to know how it was shown.
    let onDone: () -> Void

    // MARK: - Body

    var body: some View {
        List {
            Section {
                ForEach(runs) { run in
                    row(for: run)
                        .listRowBackground(rowBackground(for: run))
                }
                .onMove(perform: move)
            } header: {
                Text(headerText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            }
        }
        // Always on. The sheet exists only to reorder, so an Edit button would be a tap between
        // the user and the one thing this screen does.
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Reorder Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Rows

    private var runs: [SupersetGrouping.Run] {
        SupersetGrouping.runs(
            exercises: dataSource.exercises,
            setsByExercise: dataSource.setsByExercise
        )
    }

    /// Only mentions supersets when one is actually on screen.
    private var headerText: String {
        runs.contains(where: \.isMarked)
            ? "Drag to reorder. A superset moves as one."
            : "Drag to reorder."
    }

    private func rowBackground(for run: SupersetGrouping.Run) -> Color {
        guard let color = SupersetPalette.color(for: run, in: runs) else { return .bgCard }
        return color.opacity(0.10)
    }

    @ViewBuilder
    private func row(for run: SupersetGrouping.Run) -> some View {
        if let color = SupersetPalette.color(for: run, in: runs) {
            supersetRow(run: run, color: color)
        } else {
            // An unmarked run always holds exactly one exercise — see `SupersetGrouping.Run`.
            Text(run.exercises[0].name)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.textPrimary)
                .frame(minHeight: 44, alignment: .leading)
        }
    }

    /// Two-plus members of one group, drawn as a single row.
    ///
    /// One row, one grab handle: the affordance has to say that this moves as a unit, because the
    /// list will not offer a drop target inside it.
    private func supersetRow(run: SupersetGrouping.Run, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SUPERSET")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundColor(color)

            ForEach(Array(run.exercises.enumerated()), id: \.element.id) { position, exercise in
                HStack(spacing: 7) {
                    // Same grammar as the strip's container: the chevron marks the alternation,
                    // so it sits between members rather than in front of the first.
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                        .frame(width: 13)
                        .opacity(position == 0 ? 0 : 1)

                    Text(exercise.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.textPrimary)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Superset: \(run.exercises.map(\.name).joined(separator: ", then "))")
    }

    // MARK: - Moving

    private func move(from source: IndexSet, to destination: Int) {
        guard let move = SupersetGrouping.exerciseMove(
            forRunMove: source,
            to: destination,
            in: runs
        ) else { return }

        dataSource.reorderExercises(from: move.source, to: move.destination)
    }
}

// MARK: - Run → exercise translation

extension SupersetGrouping {

    /// Translate a move of *runs* into the move of *exercises* it stands for.
    ///
    /// This is the only genuinely new logic behind the reorder sheet, and the only place a
    /// superset could be split, so it is a pure function rather than a method on the view.
    ///
    /// `runs` walks `exercises` in order and never reorders, so flattening the runs reproduces the
    /// exercise array exactly — that is what makes these offsets line up. `toOffset` is a
    /// *pre-move* index for `move(fromOffsets:toOffset:)`, so a run destination maps to the
    /// flattened start of the run currently sitting there, or to the end of the array when the row
    /// was dropped past the last run.
    ///
    /// Returns nil when the move is not one this sheet can express, or when it would not change
    /// anything — a no-op still costs a renumber and a write.
    static func exerciseMove(
        forRunMove source: IndexSet,
        to destination: Int,
        in runs: [Run]
    ) -> (source: IndexSet, destination: Int)? {
        // A `List` drag moves exactly one row. Anything else is not something the sheet can
        // express, and guessing would be how a group gets split.
        guard source.count == 1,
              let runIndex = source.first,
              runs.indices.contains(runIndex),
              (0...runs.count).contains(destination)
        else { return nil }

        var starts: [Int] = []
        var total = 0
        for run in runs {
            starts.append(total)
            total += run.exercises.count
        }

        let start = starts[runIndex]
        let length = runs[runIndex].exercises.count
        let flatDestination = destination < runs.count ? starts[destination] : total

        // Dropped back where it came from — on itself, or immediately after itself.
        guard flatDestination != start, flatDestination != start + length else { return nil }

        return (IndexSet(integersIn: start..<(start + length)), flatDestination)
    }
}
