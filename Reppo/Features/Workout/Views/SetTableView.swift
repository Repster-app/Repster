// SetTableView.swift
// Container view rendering the header row, all set rows, and add buttons for the current exercise.
// Spec: design-system.md Section 6.3 (Set Table)
// Contract: WP03 T013 (table structure), T014 (column adaptation), T016 (add buttons)
//
// Connects to any SetTableDataSource for data and actions.
// All business logic delegates to the data source — this view only handles presentation and input state.

import SwiftUI

enum RepsTargetInput: Equatable {
    case empty
    case single(Int)
    case range(Int, Int)
    case invalid

    var completionReps: Int? {
        guard case let .single(reps) = self else { return nil }
        return reps
    }

    var blocksCompletion: Bool {
        switch self {
        case .range, .invalid:
            return true
        case .empty, .single:
            return false
        }
    }
}

enum RepsTargetInputParser {
    static func parse(_ text: String) -> RepsTargetInput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }

        if let reps = Int(trimmed), reps > 0 {
            return .single(reps)
        }

        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return .invalid }

        let lowerText = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let upperText = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let lowerBound = Int(lowerText),
            let upperBound = Int(upperText),
            lowerBound > 0,
            upperBound > 0,
            lowerBound < upperBound
        else {
            return .invalid
        }

        return .range(lowerBound, upperBound)
    }
}

/// The set table for the currently selected exercise.
///
/// Renders a header row with column labels, set rows via `SetRowView`,
/// and "Add Set" / "Add Warmup" buttons at the bottom.
/// Columns adapt to the exercise's `trackingType` (T014).
struct SetTableView: View {

    // MARK: - Dependencies

    /// The data source providing workout data and action methods.
    var dataSource: any SetTableDataSource

    /// Shared custom keyboard manager used to render the sketch-style keypad.
    var keyboardManager: SetEntryKeyboardManager? = nil

    // MARK: - Body

    var body: some View {
        let exercise = dataSource.currentExercise
        let sets = dataSource.currentSets

        VStack(spacing: 0) {
            // Header row
            if let exercise {
                headerRow(for: exercise.trackingType)
            }

            // Set rows — warmups get W1/W2, working sets start at 1
            LazyVStack(spacing: 0) {
                let numberedSets: [(set: WorkoutSet, number: Int)] = {
                    var warmupCount = 0
                    var workingCount = 0
                    return sets.map { set in
                        if set.setType == .warmup {
                            warmupCount += 1
                            return (set, warmupCount)
                        } else {
                            workingCount += 1
                            return (set, workingCount)
                        }
                    }
                }()

                ForEach(numberedSets, id: \.set.id) { item in
                    SetRowWrapper(
                        set: item.set,
                        exercise: exercise,
                        setNumber: item.number,
                        siblingsSets: sets,
                        dataSource: dataSource,
                        keyboardManager: keyboardManager,
                        suggestedWeight: dataSource.suggestedWeight(for: item.set.id)
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
                Text("WEIGHT")
                    .frame(maxWidth: .infinity)
                Text("REPS")
                    .frame(maxWidth: .infinity)

            case .duration:
                Text("TIME")
                    .frame(maxWidth: .infinity)

            case .durationDistance:
                Text("TIME")
                    .frame(maxWidth: .infinity)
                Text("DIST")
                    .frame(maxWidth: .infinity)

            case .weightDistance:
                Text("WEIGHT")
                    .frame(maxWidth: .infinity)
                Text("DIST")
                    .frame(maxWidth: .infinity)

            case .weightRepsDuration:
                Text("WEIGHT")
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
        .kerning(0.8)
        .textCase(.uppercase)
        .foregroundColor(Color.textPrimary.opacity(0.78))
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(Color.bgInput.opacity(0.78))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.white.opacity(0.08)),
            alignment: .bottom
        )
    }

    // MARK: - Add Buttons (T016)

    /// "Add Set" and "Add Warmup" buttons below the set rows.
    @ViewBuilder
    private func addButtons(for exerciseId: UUID) -> some View {
        HStack(spacing: 12) {
            addActionButton(title: "Add Set") {
                Task {
                    await dataSource.addSet(for: exerciseId)
                }
            }

            addActionButton(title: "Add Warmup") {
                Task {
                    await dataSource.addWarmupSet(for: exerciseId)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func addActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(Color.bgInput)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
    let siblingsSets: [WorkoutSet]
    var dataSource: any SetTableDataSource
    var keyboardManager: SetEntryKeyboardManager? = nil
    var suggestedWeight: Double? = nil

    // Independent text state per row
    @State private var weightText: String
    @State private var repsText: String
    @State private var durationText: String
    @State private var distanceText: String
    @State private var rirValue: Double?

    // Note editor state
    @State private var showNoteAlert: Bool = false
    @State private var noteText: String = ""
    @State private var isAutoUncompleting: Bool = false

    init(
        set: WorkoutSet,
        exercise: Exercise?,
        setNumber: Int,
        siblingsSets: [WorkoutSet] = [],
        dataSource: any SetTableDataSource,
        keyboardManager: SetEntryKeyboardManager? = nil,
        suggestedWeight: Double? = nil
    ) {
        self.set = set
        self.exercise = exercise
        self.setNumber = setNumber
        self.siblingsSets = siblingsSets
        self.dataSource = dataSource
        self.keyboardManager = keyboardManager
        self.suggestedWeight = suggestedWeight

        // Initialize text from model values
        _weightText = State(initialValue: set.weight.map { Self.formatWeight($0) } ?? "")
        _repsText = State(initialValue: Self.repsTextValue(for: set))
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
                            let parsedReps = RepsTargetInputParser.parse(repsText)
                            guard !parsedReps.blocksCompletion else { return }
                            await dataSource.completeSet(
                                set,
                                weight: UnitConversion.parseDecimal(weightText),
                                reps: parsedReps.completionReps,
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
                },
                keyboardManager: keyboardManager,
                suggestedWeight: suggestedWeight,
                prStatusOverride: CachedPRStatus.effectiveStatus(for: set, among: siblingsSets)
            )
            .onChange(of: weightText) { _, newValue in
                handleFieldEdit(field: .weight) {
                    set.weight = UnitConversion.parseDecimal(newValue)
                }
            }
            .onChange(of: repsText) { _, newValue in
                handleFieldEdit(field: .reps) {
                    switch RepsTargetInputParser.parse(newValue) {
                    case .empty:
                        set.reps = nil
                        set.draftTargetRepMin = nil
                        set.draftTargetRepMax = nil
                    case let .single(reps):
                        set.reps = reps
                        set.draftTargetRepMin = nil
                        set.draftTargetRepMax = nil
                    case let .range(min, max):
                        set.reps = nil
                        set.draftTargetRepMin = min
                        set.draftTargetRepMax = max
                    case .invalid:
                        break
                    }
                }
            }
            .onChange(of: durationText) { _, newValue in
                handleFieldEdit(field: .duration) {
                    set.durationSeconds = Int(newValue)
                }
            }
            .onChange(of: distanceText) { _, newValue in
                handleFieldEdit(field: .distance) {
                    set.distanceMeters = UnitConversion.parseDecimal(newValue)
                }
            }
            .onChange(of: rirValue) { _, newValue in
                handleFieldEdit(field: .rir) {
                    set.rir = newValue
                }
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

    /// Apply an input edit and ensure completed sets are automatically uncompleted.
    private func handleFieldEdit(field: SetDraftField, _ edit: () -> Void) {
        edit()

        if set.completed {
            guard !isAutoUncompleting else {
                dataSource.markSetDirty(set, field: field)
                return
            }
            isAutoUncompleting = true
            Task { @MainActor in
                await dataSource.uncompleteSet(set)
                isAutoUncompleting = false
            }
        } else {
            dataSource.markSetDirty(set, field: field)
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

    private static func repsTextValue(for set: WorkoutSet) -> String {
        if let reps = set.reps {
            return "\(reps)"
        }
        if let draftRange = set.draftTargetRepRange {
            return "\(draftRange.lowerBound)-\(draftRange.upperBound)"
        }
        return ""
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

// MARK: - Custom Keyboard

/// Mutable editing context used by the custom set-entry keyboard.
final class SetEntryKeyboardContext {
    let ownerSetID: UUID
    let trackingType: TrackingType
    /// Tracked focused field — updated directly by the keyboard overlay on Prev/Next.
    /// Use this instead of getFocusedField() for rendering decisions.
    var trackedField: SetRowInputField?
    let getFocusedField: () -> SetRowInputField?
    let setFocusedField: (SetRowInputField?) -> Void
    let getFieldValue: (SetRowInputField) -> String
    let setFieldValue: (SetRowInputField, String) -> Void
    let getRIRValue: () -> Double?
    let setRIRValue: (Double?) -> Void
    let getSuggestedWeight: () -> Double?
    let getWeightIncrement: () -> Double
    let onCompleteSet: (() -> Void)?
    let canMovePrevious: () -> Bool
    let canMoveNext: () -> Bool
    let movePrevious: () -> Void
    let moveNext: () -> Void
    let dismiss: () -> Void

    init(
        ownerSetID: UUID,
        trackingType: TrackingType,
        activeField: SetRowInputField? = nil,
        getFocusedField: @escaping () -> SetRowInputField?,
        setFocusedField: @escaping (SetRowInputField?) -> Void,
        getFieldValue: @escaping (SetRowInputField) -> String,
        setFieldValue: @escaping (SetRowInputField, String) -> Void,
        getRIRValue: @escaping () -> Double?,
        setRIRValue: @escaping (Double?) -> Void,
        getSuggestedWeight: @escaping () -> Double?,
        getWeightIncrement: @escaping () -> Double = { 2.5 },
        onCompleteSet: (() -> Void)? = nil,
        canMovePrevious: @escaping () -> Bool,
        canMoveNext: @escaping () -> Bool,
        movePrevious: @escaping () -> Void,
        moveNext: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.ownerSetID = ownerSetID
        self.trackingType = trackingType
        self.getFocusedField = getFocusedField
        self.setFocusedField = setFocusedField
        self.getFieldValue = getFieldValue
        self.setFieldValue = setFieldValue
        self.getRIRValue = getRIRValue
        self.setRIRValue = setRIRValue
        self.getSuggestedWeight = getSuggestedWeight
        self.getWeightIncrement = getWeightIncrement
        self.onCompleteSet = onCompleteSet
        self.canMovePrevious = canMovePrevious
        self.canMoveNext = canMoveNext
        self.movePrevious = movePrevious
        self.moveNext = moveNext
        self.dismiss = dismiss
        self.trackedField = activeField ?? getFocusedField()
    }
}

/// Shared manager that coordinates a single active custom keyboard session.
final class SetEntryKeyboardManager: ObservableObject {
    @Published var context: SetEntryKeyboardContext?

    func show(_ context: SetEntryKeyboardContext) {
        // Clear focus on the previous set's row so it doesn't stay highlighted
        if let old = self.context, old.ownerSetID != context.ownerSetID {
            old.setFocusedField(nil)
        }
        self.context = context
    }

    func hide(ownerSetID: UUID? = nil) {
        guard let current = context else { return }
        if ownerSetID == nil || current.ownerSetID == ownerSetID {
            context = nil
        }
    }

    func refresh() {
        objectWillChange.send()
    }
}

/// Sketch-inspired keyboard surface rendered at screen bottom while editing set fields.
struct SetEntryKeyboardOverlay: View {
    @ObservedObject var manager: SetEntryKeyboardManager

    @State private var rirMode = false
    @State private var repMode: String = "F"
    @State private var refreshTick = 0

    var body: some View {
        Group {
            if let context = manager.context, context.trackedField != nil {
                VStack(spacing: 0) {
                    topStrip(for: context)
                    Divider().background(Color.border)
                    HStack(alignment: .top, spacing: 8) {
                        numberPad(for: context)
                        actionRail(for: context)
                    }
                    .padding(10)
                }
                .id(refreshTick)
                .background(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
                .background(Color.bgCard.ignoresSafeArea(.all, edges: .bottom))
                .onChange(of: manager.context?.ownerSetID) { _, _ in
                    rirMode = false
                    repMode = "F"
                    refreshTick = 0
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.context?.ownerSetID)
    }

    @ViewBuilder
    private func topStrip(for context: SetEntryKeyboardContext) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Set")
                    .foregroundColor(.accent)
                    .font(.system(size: 14, weight: .semibold))
                Text("· \(fieldTitle(context.trackedField))")
                    .foregroundColor(.textSecondary)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if showRIRChips(for: context) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        rirChip(context, label: "—", value: nil)
                        rirChip(context, label: "0", value: 0)
                        rirChip(context, label: "1", value: 1)
                        rirChip(context, label: "2", value: 2)
                        rirChip(context, label: "3", value: 3)
                        rirChip(context, label: "4", value: 4)
                        rirChip(context, label: "5+", value: 5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            } else {
                Text(weightHelperText(context))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
    }

    private func rirChip(_ context: SetEntryKeyboardContext, label: String, value: Double?) -> some View {
        let selected = (context.getRIRValue() == value) || (context.getRIRValue() == nil && value == nil)
        return Button {
            context.setRIRValue(value)
            refreshTick += 1
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(rirColor(for: value))
                .frame(width: 38, height: 38)
                .background(selected ? Color.bgHover : Color.bgSubtle)
                .overlay(
                    Circle().stroke(selected ? Color.accent.opacity(0.5) : Color.border, lineWidth: 1)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func numberPad(for context: SetEntryKeyboardContext) -> some View {
        let keys: [String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
        let focusedField = context.trackedField
        let decimalAllowed = allowsDecimal(focusedField)
        let isRepsField = focusedField == .reps
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { key in
                let isDecimalKey = key == "."
                // D6: Show dash key on reps field instead of disabled decimal
                let showDash = isDecimalKey && isRepsField
                let keyDisabled = isDecimalKey && !decimalAllowed && !isRepsField
                let keyLabel = showDash ? "-" : (keyDisabled ? "•" : key)
                let effectiveKey = showDash ? "-" : key
                Button {
                    handleKey(effectiveKey, context: context)
                } label: {
                    Text(keyLabel)
                        .font(.system(size: key == "⌫" ? 20 : 22, weight: .semibold))
                        .foregroundColor(keyDisabled ? .textTertiary : .textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .opacity(keyDisabled ? 0.55 : 1)
                }
                .buttonStyle(.plain)
                .disabled(keyDisabled)
            }
        }
        .frame(maxWidth: .infinity)
        .id(refreshTick)
    }

    private func actionRail(for context: SetEntryKeyboardContext) -> some View {
        let focusedField = context.trackedField
        let onWeightField = focusedField == .weight
        let canGoPrev = canMovePreviousInOverlay(context)
        let canGoNext = canMoveNextInOverlay(context)
        let suggestedWeight = context.getSuggestedWeight()

        let increment = context.getWeightIncrement()

        return VStack(spacing: 6) {
            // D1: Keyboard-dismiss icon instead of "Hide" text
            Button {
                rirMode = false
                context.dismiss()
                manager.hide(ownerSetID: context.ownerSetID)
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.bgHover)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // D2: Wand icon + weight value in blue for smart suggestion
            if onWeightField {
                Button {
                    applySuggestedWeight(context)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 13, weight: .semibold))
                        if let weight = suggestedWeight {
                            Text("\(UnitConversion.formatWeight(weight)) kg")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundColor(suggestedWeight == nil ? .textTertiary : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(suggestedWeight == nil ? Color.bgInput : Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(suggestedWeight == nil)
            }

            // D3: +/- with exercise increment; D5: +1/-1 for reps (replaces F/P)
            HStack(spacing: 8) {
                railOptionButton(title: "−", selected: false) {
                    if onWeightField {
                        nudgeWeight(context, delta: -increment)
                    } else {
                        nudgeReps(context, delta: -1)
                    }
                }
                railOptionButton(title: "+", selected: false) {
                    if onWeightField {
                        nudgeWeight(context, delta: increment)
                    } else {
                        nudgeReps(context, delta: 1)
                    }
                }
            }

            HStack(spacing: 8) {
                railNavButton(title: "Prev", disabled: !canGoPrev) {
                    if rirMode {
                        rirMode = false
                    } else {
                        moveToPreviousField(context)
                    }
                    refreshTick += 1
                    manager.show(context)
                }
                railNavButton(title: "Next", disabled: !canGoNext) {
                    if canMoveToNextField(context) {
                        moveToNextField(context)
                    }
                    refreshTick += 1
                    manager.show(context)
                }
            }

            // D5: Done marks set complete when weight + reps + RIR are filled
            Button {
                let weightFilled = !context.getFieldValue(.weight).isEmpty
                let repsFilled = !context.getFieldValue(.reps).isEmpty
                let rirFilled = context.getRIRValue() != nil
                if weightFilled && repsFilled && rirFilled {
                    context.onCompleteSet?()
                }
                rirMode = false
                context.dismiss()
                manager.hide(ownerSetID: context.ownerSetID)
            } label: {
                Text("Done")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.black.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 108)
        .id(refreshTick)
    }

    private func capsuleRailButton(title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(disabled ? .textTertiary : .textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(disabled ? Color.bgInput : Color.bgHover)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func railOptionButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(selected ? .black.opacity(0.9) : .textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(selected ? Color.white.opacity(0.85) : Color.bgHover)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.border, lineWidth: selected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func railNavButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(disabled ? .textTertiary : .textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(disabled ? Color.bgInput : Color.bgHover)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func handleKey(_ key: String, context: SetEntryKeyboardContext) {
        guard !rirMode, let field = context.trackedField else { return }
        var value = context.getFieldValue(field)

        if key == "⌫" {
            value = String(value.dropLast())
            context.setFieldValue(field, value)
            refreshTick += 1
            manager.refresh()
            return
        }

        if key == "." {
            guard allowsDecimal(field), !value.contains(".") else { return }
            context.setFieldValue(field, value.isEmpty ? "0." : value + ".")
            refreshTick += 1
            manager.refresh()
            return
        }

        // D6: Dash key for rep ranges (e.g. "8-12"), only one dash allowed
        if key == "-" {
            guard field == .reps, !value.contains("-"), !value.isEmpty else { return }
            context.setFieldValue(field, value + "-")
            refreshTick += 1
            manager.refresh()
            return
        }

        if value == "0" {
            value = ""
        }
        context.setFieldValue(field, value + key)
        refreshTick += 1
        manager.refresh()
    }

    private func allowsDecimal(_ field: SetRowInputField?) -> Bool {
        field == .weight || field == .distance
    }

    private func fieldTitle(_ field: SetRowInputField?) -> String {
        switch field {
        case .weight: return "Weight"
        case .reps: return "Reps"
        case .duration: return "Duration"
        case .distance: return "Distance"
        case .none: return "Input"
        }
    }

    private func canEnterRIRMode(_ context: SetEntryKeyboardContext) -> Bool {
        guard let field = context.trackedField else { return false }
        guard field == .reps else { return false }
        switch context.trackingType {
        case .weightReps, .weightRepsDuration, .custom:
            return true
        case .duration, .durationDistance, .weightDistance:
            return false
        }
    }

    private func showRIRChips(for context: SetEntryKeyboardContext) -> Bool {
        if rirMode {
            return true
        }
        return context.trackedField == .reps
    }

    private func orderedInputs(for trackingType: TrackingType) -> [SetRowInputField] {
        switch trackingType {
        case .weightReps, .custom:
            return [.weight, .reps]
        case .duration:
            return [.duration]
        case .durationDistance:
            return [.duration, .distance]
        case .weightDistance:
            return [.weight, .distance]
        case .weightRepsDuration:
            return [.weight, .reps, .duration]
        }
    }

    private func canMoveToPreviousField(_ context: SetEntryKeyboardContext) -> Bool {
        guard let focused = context.trackedField else { return false }
        guard let index = orderedInputs(for: context.trackingType).firstIndex(of: focused) else { return false }
        return index > 0
    }

    private func canMoveToNextField(_ context: SetEntryKeyboardContext) -> Bool {
        guard let focused = context.trackedField else { return false }
        guard let index = orderedInputs(for: context.trackingType).firstIndex(of: focused) else { return false }
        return index < orderedInputs(for: context.trackingType).count - 1
    }

    /// Move to previous field, updating trackedField and syncing with SetRowView.
    private func moveToPreviousField(_ context: SetEntryKeyboardContext) {
        let ordered = orderedInputs(for: context.trackingType)
        guard let current = context.trackedField,
              let idx = ordered.firstIndex(of: current),
              idx - 1 >= 0 else { return }
        let prevField = ordered[idx - 1]
        context.trackedField = prevField
        context.setFocusedField(prevField)
    }

    /// Move to next field, updating trackedField and syncing with SetRowView.
    private func moveToNextField(_ context: SetEntryKeyboardContext) {
        let ordered = orderedInputs(for: context.trackingType)
        guard let current = context.trackedField,
              let idx = ordered.firstIndex(of: current),
              idx + 1 < ordered.count else { return }
        let nextField = ordered[idx + 1]
        context.trackedField = nextField
        context.setFocusedField(nextField)
    }

    private func canMovePreviousInOverlay(_ context: SetEntryKeyboardContext) -> Bool {
        return canMoveToPreviousField(context)
    }

    private func canMoveNextInOverlay(_ context: SetEntryKeyboardContext) -> Bool {
        return canMoveToNextField(context)
    }

    private func applySuggestedWeight(_ context: SetEntryKeyboardContext) {
        guard let suggested = context.getSuggestedWeight() else { return }
        context.setFieldValue(.weight, UnitConversion.formatWeight(suggested))
        refreshTick += 1
        manager.refresh()
    }

    private func nudgeWeight(_ context: SetEntryKeyboardContext, delta: Double) {
        let raw = context.getFieldValue(.weight)
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        let current = Double(normalized) ?? 0
        let next = max(0, ((current + delta) * 10).rounded() / 10)
        let formatted = next.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(next)) : String(next)
        context.setFieldValue(.weight, formatted)
        refreshTick += 1
        manager.refresh()
    }

    private func nudgeReps(_ context: SetEntryKeyboardContext, delta: Int) {
        let raw = context.getFieldValue(.reps)
        // If reps contains a dash (rep range like "8-12"), don't nudge
        guard !raw.contains("-") else { return }
        let current = Int(raw) ?? 0
        let next = max(0, current + delta)
        context.setFieldValue(.reps, next == 0 ? "" : String(next))
        refreshTick += 1
        manager.refresh()
    }

    private func weightHelperText(_ context: SetEntryKeyboardContext) -> String {
        let raw = context.getFieldValue(.weight)
        let total = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
        let barWeight = 20.0
        if total <= barWeight {
            let extra = max(0, barWeight - total)
            return "0 kg on both sides + 20 kg bar weight = 0 kg + extra \(display(extra)) kg"
        }
        let side = max(0, (total - barWeight) / 2)
        return "\(display(side)) kg on both sides + 20 kg bar weight = \(display(total)) kg total"
    }

    private func display(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }

    private func rirColor(for value: Double?) -> Color {
        guard let value else { return .textSecondary }
        switch value {
        case 0: return .rir0
        case 1: return .rir1
        case 2: return .rir2
        case 3: return .rir3
        case 4: return .rir4
        default: return .rir5
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
