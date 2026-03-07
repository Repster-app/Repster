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
/// - Context menu includes "Move Left" / "Move Right" for reordering
struct ExerciseTabStripView: View {

    // MARK: - Dependencies

    /// The data source providing exercise data and actions.
    var dataSource: any SetTableDataSource

    // MARK: - State

    /// Whether the delete confirmation alert is showing.
    @State private var showDeleteConfirmation = false

    /// The index of the exercise being deleted (set before showing confirmation).
    @State private var exerciseToDeleteIndex = 0

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(dataSource.exercises.enumerated()), id: \.element.id) { index, exercise in
                        ExerciseTab(
                            name: exercise.name,
                            isActive: index == dataSource.selectedExerciseIndex,
                            isCompleted: isExerciseCompleted(exercise)
                        )
                        .id(exercise.id)
                        .onTapGesture {
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
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .onChange(of: dataSource.selectedExerciseIndex) { _, newIndex in
                // Auto-scroll to keep active tab visible
                if newIndex >= 0, newIndex < dataSource.exercises.count {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(dataSource.exercises[newIndex].id, anchor: .center)
                    }
                }
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

    /// Check if all sets for an exercise are completed.
    private func isExerciseCompleted(_ exercise: Exercise) -> Bool {
        guard let sets = dataSource.setsByExercise[exercise.id], !sets.isEmpty else { return false }
        return sets.allSatisfy { $0.completed }
    }
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

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? .white.opacity(0.8) : .success)
            }
        }
        .foregroundColor(isActive ? .white : .textTertiary)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
            .background(isActive ? Color.accent : Color.bgCard)
            .cornerRadius(8)
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
