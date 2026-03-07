// SetTableView.swift
// Container view rendering the header row, all set rows, and add buttons for the current exercise.
// Spec: design-system.md Section 6.3 (Set Table)
// Contract: WP03 T013 (table structure), T014 (column adaptation), T016 (add buttons)
//
// Connects to any SetTableDataSource for data and actions.
// All business logic delegates to the data source — this view only handles presentation and input state.

import SwiftUI

/// The set table for the currently selected exercise.
///
/// Renders a header row with column labels, set rows via `SetRowView`,
/// and "Add Set" / "Add Warmup" buttons at the bottom.
/// Columns adapt to the exercise's `trackingType` (T014).
struct SetTableView: View {

    // MARK: - Dependencies

    /// The data source providing workout data and action methods.
    var dataSource: any SetTableDataSource

    // MARK: - Body

    var body: some View {
        let exercise = dataSource.currentExercise
        let sets = dataSource.currentSets.filter { $0.modelContext != nil }

        VStack(spacing: 0) {
            // Header row
            if let exercise {
                headerRow(for: exercise.trackingType)
            }

            // Set rows
            LazyVStack(spacing: 0) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    SetRowWrapper(
                        set: set,
                        exercise: exercise,
                        setNumber: index + 1,
                        dataSource: dataSource
                    )
                }
            }

            // Add buttons (T016)
            if let exercise {
                addButtons(for: exercise.id)
            }
        }
        .background(Color.bgCard)
        .cornerRadius(12)
    }

    // MARK: - Header Row

    /// Renders column header labels matching the trackingType.
    ///
    /// Labels: SET | input column labels | RIR | PR | ✓
    /// Font: 11pt semibold, uppercase, textTertiary color.
    @ViewBuilder
    private func headerRow(for trackingType: TrackingType) -> some View {
        HStack(spacing: 4) {
            // Set column header
            Text("SET")
                .frame(width: 36)

            // Input column headers — adapt to trackingType
            switch trackingType {
            case .weightReps, .custom:
                Text("KG")
                    .frame(maxWidth: .infinity)
                Text("REPS")
                    .frame(maxWidth: .infinity)

            case .duration:
                Text("TIME")
                    .frame(maxWidth: .infinity)

            case .weightDistance:
                Text("KG")
                    .frame(maxWidth: .infinity)
                Text("DIST")
                    .frame(maxWidth: .infinity)

            case .weightRepsDuration:
                Text("KG")
                    .frame(maxWidth: .infinity)
                Text("REPS")
                    .frame(maxWidth: .infinity)
                Text("TIME")
                    .frame(maxWidth: .infinity)
            }

            // RIR column header
            Text("RIR")
                .frame(width: 42)

            // PR column header
            Text("PR")
                .frame(width: 44)

            // Checkbox column header
            Image(systemName: "checkmark")
                .frame(width: 40)
        }
        .font(.system(size: 11, weight: .semibold))
        .textCase(.uppercase)
        .foregroundColor(.textTertiary)
        .padding(.horizontal, 8)
        .frame(height: 36)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.white.opacity(0.03)),
            alignment: .bottom
        )
    }

    // MARK: - Add Buttons (T016)

    /// "Add Set" and "Add Warmup" buttons below the set rows.
    @ViewBuilder
    private func addButtons(for exerciseId: UUID) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await dataSource.addSet(for: exerciseId)
                }
            } label: {
                Text("+ Add Set")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await dataSource.addWarmupSet(for: exerciseId)
                }
            } label: {
                Text("+ Add Warmup")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - SetRowWrapper

/// Wrapper that owns the `@State` text bindings for a single set row.
///
/// Each row needs independent text state for its input fields.
/// This wrapper initializes text from the set's current values
/// and converts back to model types when the checkbox is tapped.
private struct SetRowWrapper: View {

    let set: WorkoutSet
    let exercise: Exercise?
    let setNumber: Int
    var dataSource: any SetTableDataSource

    // Independent text state per row
    @State private var weightText: String
    @State private var repsText: String
    @State private var durationText: String
    @State private var distanceText: String
    @State private var rirValue: Double?

    // Note editor state
    @State private var showNoteAlert: Bool = false
    @State private var noteText: String = ""

    init(set: WorkoutSet, exercise: Exercise?, setNumber: Int, dataSource: any SetTableDataSource) {
        self.set = set
        self.exercise = exercise
        self.setNumber = setNumber
        self.dataSource = dataSource

        // Initialize text from model values
        _weightText = State(initialValue: set.weight.map { Self.formatWeight($0) } ?? "")
        _repsText = State(initialValue: set.reps.map { "\($0)" } ?? "")
        _durationText = State(initialValue: set.durationSeconds.map { "\($0)" } ?? "")
        _distanceText = State(initialValue: set.distanceMeters.map { Self.formatDistance($0) } ?? "")
        _rirValue = State(initialValue: set.rir)
    }

    var body: some View {
        if let exercise {
            SetRowView(
                set: set,
                exercise: exercise,
                setNumber: setNumber,
                weightText: $weightText,
                repsText: $repsText,
                durationText: $durationText,
                distanceText: $distanceText,
                rirValue: $rirValue,
                targetRIR: set.targetRIR,
                repsPlaceholder: Self.repsPlaceholder(for: set),
                onComplete: {
                    Task {
                        if set.completed {
                            await dataSource.uncompleteSet(set)
                        } else {
                            await dataSource.completeSet(
                                set,
                                weight: UnitConversion.parseDecimal(weightText),
                                reps: Int(repsText),
                                durationSeconds: Int(durationText),
                                distanceMeters: UnitConversion.parseDecimal(distanceText)
                            )
                        }
                    }
                },
                onDelete: {
                    Task {
                        await dataSource.deleteSet(set)
                    }
                },
                onChangeSetType: { newType in
                    Task {
                        await dataSource.changeSetType(set, to: newType)
                    }
                },
                onEditNote: {
                    noteText = set.notes ?? ""
                    showNoteAlert = true
                }
            )
            .onChange(of: weightText) { _, newValue in
                set.weight = UnitConversion.parseDecimal(newValue)
                dataSource.markSetDirty(set)
            }
            .onChange(of: repsText) { _, newValue in
                set.reps = Int(newValue)
                dataSource.markSetDirty(set)
            }
            .onChange(of: durationText) { _, newValue in
                set.durationSeconds = Int(newValue)
                dataSource.markSetDirty(set)
            }
            .onChange(of: distanceText) { _, newValue in
                set.distanceMeters = UnitConversion.parseDecimal(newValue)
                dataSource.markSetDirty(set)
            }
            .onChange(of: rirValue) { _, newValue in
                set.rir = newValue
                dataSource.markSetDirty(set)
            }
            .alert("Set Note", isPresented: $showNoteAlert) {
                TextField("Add a note…", text: $noteText)
                Button("Save") {
                    Task {
                        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        await dataSource.updateSetNote(set, note: trimmed.isEmpty ? nil : trimmed)
                    }
                }
                Button("Cancel", role: .cancel) {}
                if set.notes != nil && !(set.notes?.isEmpty ?? true) {
                    Button("Remove Note", role: .destructive) {
                        Task {
                            await dataSource.updateSetNote(set, note: nil)
                        }
                    }
                }
            } message: {
                Text("Add a note to this set")
            }
        }
    }

    // MARK: - Formatters

    /// Format weight for display using locale-aware decimal separator.
    private static func formatWeight(_ value: Double) -> String {
        UnitConversion.formatWeight(value)
    }

    /// Format distance for display using locale-aware decimal separator.
    private static func formatDistance(_ value: Double) -> String {
        UnitConversion.formatWeight(value)
    }

    /// Compute the reps placeholder from template target rep range.
    ///
    /// - Both min & max set and different → "8-12"
    /// - Both min & max set and equal → "8"
    /// - Only min set → "8"
    /// - Only max set → "12"
    /// - Neither set → "0" (default)
    static func repsPlaceholder(for set: WorkoutSet) -> String {
        let min = set.targetRepMin
        let max = set.targetRepMax

        switch (min, max) {
        case let (.some(lo), .some(hi)) where lo == hi:
            return "\(lo)"
        case let (.some(lo), .some(hi)):
            return "\(lo)-\(hi)"
        case let (.some(lo), .none):
            return "\(lo)"
        case let (.none, .some(hi)):
            return "\(hi)"
        case (.none, .none):
            return "0"
        }
    }
}

// MARK: - Previews

#Preview("Weight + Reps Table") {
    let exerciseId = UUID()
    let workoutId = UUID()

    ZStack {
        Color.bg.ignoresSafeArea()

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Text("SET").frame(width: 36)
                Text("KG").frame(maxWidth: .infinity)
                Text("REPS").frame(maxWidth: .infinity)
                Text("RIR").frame(width: 42)
                Text("PR").frame(width: 44)
                Image(systemName: "checkmark").frame(width: 40)
            }
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .foregroundColor(.textTertiary)
            .padding(.horizontal, 8)
            .frame(height: 36)

            // Sample rows
            SetRowView(
                set: WorkoutSet(
                    workoutId: workoutId,
                    exerciseId: exerciseId,
                    setType: .warmup,
                    orderInWorkout: 1,
                    orderInExercise: 1
                ),
                exercise: Exercise(
                    name: "Bench Press",
                    equipmentType: .barbell,
                    trackingType: .weightReps
                ),
                setNumber: 1,
                weightText: .constant("40"),
                repsText: .constant("10"),
                durationText: .constant(""),
                distanceText: .constant(""),
                rirValue: .constant(nil),
                onComplete: {},
                onDelete: {},
                onChangeSetType: { _ in },
                onEditNote: {}
            )

            SetRowView(
                set: WorkoutSet(
                    workoutId: workoutId,
                    exerciseId: exerciseId,
                    setType: .working,
                    orderInWorkout: 2,
                    orderInExercise: 2,
                    completed: true,
                    cachedPRStatus: .current
                ),
                exercise: Exercise(
                    name: "Bench Press",
                    equipmentType: .barbell,
                    trackingType: .weightReps
                ),
                setNumber: 1,
                weightText: .constant("80"),
                repsText: .constant("8"),
                durationText: .constant(""),
                distanceText: .constant(""),
                rirValue: .constant(0),
                onComplete: {},
                onDelete: {},
                onChangeSetType: { _ in },
                onEditNote: {}
            )

            SetRowView(
                set: WorkoutSet(
                    workoutId: workoutId,
                    exerciseId: exerciseId,
                    setType: .working,
                    orderInWorkout: 3,
                    orderInExercise: 3
                ),
                exercise: Exercise(
                    name: "Bench Press",
                    equipmentType: .barbell,
                    trackingType: .weightReps
                ),
                setNumber: 2,
                weightText: .constant(""),
                repsText: .constant(""),
                durationText: .constant(""),
                distanceText: .constant(""),
                rirValue: .constant(nil),
                onComplete: {},
                onDelete: {},
                onChangeSetType: { _ in },
                onEditNote: {}
            )

            // Add buttons
            HStack(spacing: 12) {
                Text("+ Add Set")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                Text("+ Add Warmup")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color.bgCard)
        .cornerRadius(12)
        .padding()
    }
}
