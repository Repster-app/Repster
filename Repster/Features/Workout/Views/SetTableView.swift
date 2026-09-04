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

struct UnilateralTargetPresentation: Equatable, Sendable {
    let leftPlaceholder: String
    let rightPlaceholder: String
    let sharedHint: String?
}

enum CustomRepRangeCommitter {
    static func commit(min: Int?, max: Int?, to set: WorkoutSet) -> Bool {
        let input = normalizedInput(min: min, max: max)
        guard input != .invalid else { return false }

        switch input {
        case .empty:
            set.overrideTargetRepMin = nil
            set.overrideTargetRepMax = nil
            // Emptying the range editor is the user removing the target, so the target the
            // set inherited from its template goes with it. Leaving those two fields set
            // hands `preferredTargetRepBounds` a fallback and the deleted number comes
            // straight back on the next read.
            set.targetRepMin = nil
            set.targetRepMax = nil
        case let .single(reps):
            set.overrideTargetRepMin = reps
            set.overrideTargetRepMax = reps
        case let .range(lowerBound, upperBound):
            set.overrideTargetRepMin = lowerBound
            set.overrideTargetRepMax = upperBound
        case .invalid:
            return false
        }

        return true
    }

    private static func normalizedInput(min: Int?, max: Int?) -> RepsTargetInput {
        switch (min, max) {
        case let (.some(lowerBound), .some(upperBound))
        where lowerBound > 0 && upperBound > 0 && lowerBound < upperBound:
            return .range(lowerBound, upperBound)
        case let (.some(value), .some(otherValue))
        where value > 0 && otherValue > 0 && value == otherValue:
            return .single(value)
        case let (.some(value), .none) where value > 0,
             let (.none, .some(value)) where value > 0:
            return .single(value)
        case (.none, .none):
            return .empty
        default:
            return .invalid
        }
    }
}

/// The set table for the currently selected exercise.
///
/// Renders a header row with column labels, set rows via `SetRowView`,
/// and "Warmup" / "Add Set" buttons at the bottom.
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
                headerRow(for: exercise)
            }

            // Set rows — warmups get W1/W2, drop sets D1/D2, working sets start at 1.
            // `SetBadgeLabel.assign` is shared with both history renderers so the same set
            // shows the same number wherever it is drawn.
            LazyVStack(spacing: 0) {
                let numberedSets: [(set: WorkoutSet, number: Int)] = zip(
                    sets,
                    SetBadgeLabel.assign(for: sets.map(\.setType))
                ).map { (set: $0, number: $1.number) }

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
        // The keypad outlives any single row, so its owner is checked against the exercise's own
        // set list rather than against a row's lifecycle. `onDisappear` on the row used to do this,
        // but rows live in a LazyVStack, where disappearing also means "scrolled out of view" — so
        // editing a set and scrolling down tore the keypad out mid-entry. This fires only when the
        // owning set genuinely leaves, and sits above the LazyVStack where scrolling can't reach it.
        .onChange(of: sets.map(\.id)) { _, ids in
            if let ownerSetID = keyboardManager?.context?.ownerSetID, !ids.contains(ownerSetID) {
                keyboardManager?.hide(ownerSetID: ownerSetID)
            }
        }
    }

    // MARK: - Header Row

    /// Renders column header labels matching the trackingType.
    ///
    /// Labels: SET | input column labels | RIR | PR | ✓
    /// Font: 11pt semibold, uppercase, textTertiary color.
    @ViewBuilder
    private func headerRow(for exercise: ChartExerciseData) -> some View {
        HStack(spacing: 4) {
            // Set column header
            Text("SET")
                .frame(width: 36)

            // Input column headers — adapt to trackingType
            inputHeaders(for: exercise)

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
        .frame(height: 34)
        .background(Color.bgInput.opacity(0.78))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.white.opacity(0.08)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func inputHeaders(for exercise: ChartExerciseData) -> some View {
        switch exercise.trackingType {
        case .weightReps:
            if isUnilateralLogging(for: exercise) {
                unilateralWeightRepsHeader
            } else {
                Text("WEIGHT")
                    .frame(maxWidth: .infinity)
                Text("REPS")
                    .frame(maxWidth: .infinity)
            }

        case .custom:
            Text("WEIGHT")
                .frame(maxWidth: .infinity)
            Text("REPS")
                .frame(maxWidth: .infinity)

        case .duration:
            Text("TIME")
                .frame(maxWidth: .infinity)

        case .durationDistance:
            Text("DIST")
                .frame(maxWidth: .infinity)
            Text("TIME")
                .frame(maxWidth: .infinity)

        case .weightDistance:
            Text("WEIGHT")
                .frame(maxWidth: .infinity)
            Text("DIST")
                .frame(maxWidth: .infinity)

        case .weightDuration:
            Text("WEIGHT")
                .frame(maxWidth: .infinity)
            Text("TIME")
                .frame(maxWidth: .infinity)

        case .weightRepsDuration:
            if isUnilateralLogging(for: exercise) {
                unilateralWeightRepsDurationHeader
            } else {
                Text("WEIGHT")
                    .frame(maxWidth: .infinity)
                Text("REPS")
                    .frame(maxWidth: .infinity)
                Text("TIME")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var unilateralWeightRepsHeader: some View {
        GeometryReader { geometry in
            unilateralWeightRepsHeaderContent(availableWidth: geometry.size.width)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unilateralWeightRepsDurationHeader: some View {
        GeometryReader { geometry in
            let durationWidth = UnilateralSetRowLayout.durationWidth(for: geometry.size.width)
            let weightRepsWidth = UnilateralSetRowLayout.weightRepsGroupWidth(for: geometry.size.width)

            HStack(spacing: UnilateralSetRowLayout.groupedColumnSpacing) {
                unilateralWeightRepsHeaderContent(availableWidth: weightRepsWidth)
                    .frame(width: weightRepsWidth, alignment: .leading)

                Text("TIME")
                    .frame(width: durationWidth)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unilateralWeightRepsHeaderContent(availableWidth: CGFloat) -> some View {
        let weightWidth = UnilateralSetRowLayout.weightWidth(for: availableWidth)

        return HStack(spacing: UnilateralSetRowLayout.weightToRepsSpacing) {
            Text("WEIGHT")
                .frame(width: weightWidth)

            Text("REPS")
                .frame(maxWidth: .infinity)
        }
    }

    private func isUnilateralLogging(for exercise: ChartExerciseData) -> Bool {
        exercise.unilateral && exercise.supportsUnilateralLogging
    }

    // MARK: - Add Buttons (T016)

    /// "Warmup" and "Add Set" buttons below the set rows.
    ///
    /// This is the template editor's row (`CreateEditTemplateView.addSetButtons`): warm-up first
    /// in a fixed, narrower slot, "Add Set" flexing to fill the rest. The two screens used to
    /// disagree on both the order and the relative weight of the same pair of actions — here they
    /// were equal halves with "Add Set" on the left, there a narrow warm-up on the left — so the
    /// muscle memory built on one misfired on the other.
    ///
    /// One deliberate divergence: the buttons stay 44pt tall rather than the template's 38pt.
    /// This row is tapped mid-set with one hand; the template editor is not.
    @ViewBuilder
    private func addButtons(for exerciseId: UUID) -> some View {
        HStack(spacing: 8) {
            addActionButton(title: "Warmup", tint: .warmup, background: .warmupSoft, width: 96) {
                Task {
                    await dataSource.addWarmupSet(for: exerciseId)
                }
            }

            addActionButton(title: "Add Set", tint: .accent, background: .accentSoft, width: nil) {
                Task {
                    await dataSource.addSet(for: exerciseId)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// A tinted add button. `width` nil means "take the remaining space" — the primary of the pair.
    private func addActionButton(
        title: String,
        tint: Color,
        background: Color,
        width: CGFloat?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(tint)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width)
            .frame(minHeight: 44)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "Warmup" ? "Add warmup set" : "Add set")
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
    let exercise: ChartExerciseData?
    let setNumber: Int
    let siblingsSets: [WorkoutSet]
    var dataSource: any SetTableDataSource
    var keyboardManager: SetEntryKeyboardManager? = nil
    var suggestedWeight: Double? = nil

    // Independent text state per row
    @State private var weightText: String
    @State private var repsText: String
    @State private var leftRepsText: String
    @State private var rightRepsText: String
    @State private var durationText: String
    @State private var distanceText: String
    @State private var rirValue: Double?
    @State private var leftRIRValue: Double?
    @State private var rightRIRValue: Double?
    @State private var lastUnitPreference: UnitPreference

    // Note editor state
    @State private var showNoteAlert: Bool = false
    @State private var noteText: String = ""
    @State private var isAutoUncompleting: Bool = false
    @State private var suppressNextRepsTextChange: Bool = false

    /// True when the user tapped the checkmark on a row missing a required reps value.
    /// Cleared on the next text edit so the red flag disappears as soon as they start typing.
    @State private var showsCompletionError: Bool = false

    /// Token bumped to ask SetRowView to focus the keypad on the first empty reps field
    /// after a blocked checkmark tap.
    @State private var keypadFocusRequestToken: UUID? = nil

    init(
        set: WorkoutSet,
        exercise: ChartExerciseData?,
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
        let unitPreference = dataSource.unitPreference
        _weightText = State(initialValue: set.weight.map { Self.formatWeight($0, unitPreference: unitPreference) } ?? "")
        _repsText = State(initialValue: Self.repsTextValue(for: set))
        _leftRepsText = State(initialValue: set.leftReps.map(String.init) ?? "")
        _rightRepsText = State(initialValue: set.rightReps.map(String.init) ?? "")
        _durationText = State(initialValue: set.durationSeconds.map(Self.formatDurationForInput) ?? "")
        _distanceText = State(initialValue: set.distanceMeters.map { Self.formatDistance($0) } ?? "")
        _rirValue = State(initialValue: set.rir)
        _leftRIRValue = State(initialValue: set.leftRIR)
        _rightRIRValue = State(initialValue: set.rightRIR)
        _lastUnitPreference = State(initialValue: unitPreference)
    }

    var body: some View {
        if let exercise {
            configuredRow(for: exercise)
        }
    }

    private func configuredRow(for exercise: ChartExerciseData) -> AnyView {
        let unilateralTargetPresentation = SetTableView.unilateralTargetPresentation(for: set, exercise: exercise)
        let prStatusOverride = CachedPRStatus.effectiveStatus(for: set, among: siblingsSets)
        let row = rowContent(
            for: exercise,
            presentation: unilateralTargetPresentation,
            prStatusOverride: prStatusOverride
        )
        let rowWithHandlers = applyingFieldChangeHandlers(to: row, exercise: exercise)
        return setNoteAlert(for: rowWithHandlers)
    }

    private func rowContent(
        for exercise: ChartExerciseData,
        presentation: UnilateralTargetPresentation,
        prStatusOverride: CachedPRStatus?
    ) -> AnyView {
        AnyView(
            SetRowView(
                set: set,
                exercise: exercise,
                setNumber: setNumber,
                weightText: $weightText,
                repsText: $repsText,
                leftRepsText: $leftRepsText,
                rightRepsText: $rightRepsText,
                durationText: $durationText,
                distanceText: $distanceText,
                rirValue: $rirValue,
                leftRIRValue: $leftRIRValue,
                rightRIRValue: $rightRIRValue,
                targetRIR: set.targetRIR,
                repsPlaceholder: Self.repsPlaceholder(for: set),
                leftRepsPlaceholder: presentation.leftPlaceholder,
                rightRepsPlaceholder: presentation.rightPlaceholder,
                unilateralTargetHint: presentation.sharedHint,
                onComplete: { completeOrToggleSet(for: exercise) },
                // Snapshot at construction time. The keyboard overlay re-reads
                // this via `context.canCompleteSet()`, and the closure stored in
                // the long-lived `SetEntryKeyboardContext` doesn't reliably see
                // live @State through self-capture. We keep the snapshot fresh
                // by overwriting `context.canCompleteSet` from the row's
                // `onChange` handlers (see `refreshCustomKeyboardIfOwned`).
                canCompleteSet: { completionInput(for: exercise) != nil },
                onDelete: deleteCurrentSet,
                onChangeSetType: changeSetType,
                onEditNote: beginEditingNote,
                onCommitTargetRepRange: commitTargetRepRange,
                keyboardManager: keyboardManager,
                unitPreference: dataSource.unitPreference,
                defaultWeightIncrement: dataSource.defaultWeightIncrement,
                suggestedWeight: suggestedWeight,
                prStatusOverride: prStatusOverride,
                showsCompletionError: showsCompletionError,
                keypadFocusRequestToken: keypadFocusRequestToken
            )
        )
    }

    private func applyingFieldChangeHandlers(to content: AnyView, exercise: ChartExerciseData) -> AnyView {
        AnyView(
            content
                .onChange(of: weightText) { _, newValue in
                    handleWeightChange(newValue)
                    refreshCustomKeyboardIfOwned(for: exercise)
                }
                .onChange(of: repsText) { _, newValue in
                    handleRepsChange(newValue)
                    refreshCustomKeyboardIfOwned(for: exercise)
                }
                .onChange(of: leftRepsText) { _, newValue in
                    handleLeftRepsChange(newValue, exercise: exercise)
                    refreshCustomKeyboardIfOwned(for: exercise)
                }
                .onChange(of: rightRepsText) { _, newValue in
                    handleRightRepsChange(newValue, exercise: exercise)
                    refreshCustomKeyboardIfOwned(for: exercise)
                }
                .onChange(of: durationText) { _, newValue in
                    handleDurationChange(newValue)
                    refreshCustomKeyboardIfOwned(for: exercise)
                }
                .onChange(of: distanceText) { _, newValue in
                    handleDistanceChange(newValue)
                    refreshCustomKeyboardIfOwned(for: exercise)
                }
                .onChange(of: rirValue) { _, newValue in
                    handleRIRChange(newValue)
                }
                .onChange(of: leftRIRValue) { _, newValue in
                    handleLeftRIRChange(newValue, exercise: exercise)
                }
                .onChange(of: rightRIRValue) { _, newValue in
                    handleRightRIRChange(newValue, exercise: exercise)
                }
                .onChange(of: dataSource.unitPreference) { oldValue, newValue in
                    refreshDisplayTextForUnitChange(from: oldValue, to: newValue)
                }
        )
    }

    /// Pushes a fresh `canCompleteSet` snapshot into the active keyboard context
    /// when this row owns it, then nudges the overlay to re-render.
    ///
    /// The Done button's `disabled` state is driven by `context.canCompleteSet()`.
    /// The closure originally captured into the context at activation time
    /// references `self` of this `SetRowWrapper`, and SwiftUI does not reliably
    /// propagate live @State through such a self-capture stored on a long-lived
    /// reference type — so the closure returns the value of `completionInput` as
    /// it was at the moment the keyboard was opened, leaving the Done button
    /// disabled until the keyboard is dismissed and re-opened. We work around
    /// that by computing the Bool here (inside an onChange handler, where `self`
    /// is current and reads live @State) and stashing a fresh trivial closure
    /// returning that snapshot.
    private func refreshCustomKeyboardIfOwned(for exercise: ChartExerciseData) {
        guard let keyboardManager else { return }
        guard let context = keyboardManager.context, context.ownerSetID == set.id else { return }
        let canComplete = completionInput(for: exercise) != nil
        context.canCompleteSet = { canComplete }
        keyboardManager.refresh()
    }

    private func setNoteAlert(for content: AnyView) -> AnyView {
        AnyView(
            // Free text, and an alert's field is built by `UIAlertController`, so a mask
            // never reaches it — see `ReplayPrivacy.swift`.
            content
                .replayPaused(while: showNoteAlert)
                .alert("Set Note", isPresented: $showNoteAlert) {
                    TextField("Add a note…", text: $noteText)
                    Button("Save") {
                        saveEditedNote()
                    }
                    Button("Cancel", role: .cancel) {}
                    if set.notes != nil && !(set.notes?.isEmpty ?? true) {
                        Button("Remove Note", role: .destructive) {
                            removeExistingNote()
                        }
                    }
                } message: {
                    Text("Add a note to this set")
                }
        )
    }

    private func completeOrToggleSet(for exercise: ChartExerciseData) {
        Task {
            if set.completed {
                await dataSource.uncompleteSet(set)
                return
            }

            attemptAutoFillRepsFromTarget(for: exercise)

            if let input = completionInput(for: exercise) {
                await dataSource.completeSet(set, input: input)
            } else {
                // Range / no target with empty reps → flag the row and guide the user
                // straight to the missing field.
                showsCompletionError = true
                keypadFocusRequestToken = UUID()
            }
        }
    }

    /// If the user taps the checkmark with empty reps, populate the text field(s)
    /// from a single-value rep target (e.g. `6-6`) so the saved set carries that
    /// value. Range or absent targets are left untouched — `completionInput`
    /// returns nil in that case so completion is blocked.
    private func attemptAutoFillRepsFromTarget(for exercise: ChartExerciseData) {
        let bounds = set.preferredTargetRepBounds
        guard let lo = bounds.min, let hi = bounds.max, lo == hi, lo > 0 else { return }

        if exercise.supportsUnilateralLogging, exercise.unilateral {
            guard !exercise.usesTotalAcrossSidesRepTargets else { return }
            if leftRepsText.isEmpty {
                leftRepsText = String(lo)
            }
            if rightRepsText.isEmpty {
                rightRepsText = String(lo)
            }
        } else if repsText.isEmpty {
            suppressNextRepsTextChange = true
            repsText = String(lo)
        }
    }

    private func deleteCurrentSet() {
        Task {
            await dataSource.deleteSet(set)
        }
    }

    private func changeSetType(_ newType: SetType) {
        Task {
            await dataSource.changeSetType(set, to: newType)
        }
    }

    private func beginEditingNote() {
        noteText = set.notes ?? ""
        showNoteAlert = true
    }

    private func saveEditedNote() {
        Task {
            let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            await dataSource.updateSetNote(set, note: trimmed.isEmpty ? nil : trimmed)
        }
    }

    private func removeExistingNote() {
        Task {
            await dataSource.updateSetNote(set, note: nil)
        }
    }

    private func handleWeightChange(_ newValue: String) {
        handleFieldEdit(field: .weight) {
            set.weight = UnitConversion.parseDisplayedWeight(newValue, unitPreference: dataSource.unitPreference)
        }
    }

    private func handleRepsChange(_ newValue: String) {
        showsCompletionError = false
        if suppressNextRepsTextChange {
            suppressNextRepsTextChange = false
            return
        }
        applyParsedRepsInput(RepsTargetInputParser.parse(newValue))
    }

    private func handleLeftRepsChange(_ newValue: String, exercise: ChartExerciseData) {
        showsCompletionError = false
        handleFieldEdit(field: .reps) {
            set.leftReps = Self.singleRepsValue(from: newValue)
            syncDerivedSetFields(for: exercise)
        }
    }

    private func handleRightRepsChange(_ newValue: String, exercise: ChartExerciseData) {
        showsCompletionError = false
        handleFieldEdit(field: .reps) {
            set.rightReps = Self.singleRepsValue(from: newValue)
            syncDerivedSetFields(for: exercise)
        }
    }

    private func handleDurationChange(_ newValue: String) {
        handleFieldEdit(field: .duration) {
            set.durationSeconds = Self.durationSecondsValue(from: newValue)
        }
    }

    private func handleDistanceChange(_ newValue: String) {
        handleFieldEdit(field: .distance) {
            set.distanceMeters = UnitConversion.parseDecimal(newValue)
        }
    }

    private func handleRIRChange(_ newValue: Double?) {
        handleFieldEdit(field: .rir) {
            set.rir = newValue
        }
    }

    private func handleLeftRIRChange(_ newValue: Double?, exercise: ChartExerciseData) {
        handleFieldEdit(field: .rir) {
            set.leftRIR = newValue
            syncDerivedSetFields(for: exercise)
        }
    }

    private func handleRightRIRChange(_ newValue: Double?, exercise: ChartExerciseData) {
        handleFieldEdit(field: .rir) {
            set.rightRIR = newValue
            syncDerivedSetFields(for: exercise)
        }
    }

    /// Apply an input edit and ensure completed sets are automatically uncompleted.
    @discardableResult
    private func handleFieldEdit(field: SetDraftField, _ edit: () -> Void) -> Bool {
        let contributionBeforeEdit = set.completed ? SetContributionSnapshot(set: set) : nil
        edit()

        if set.completed {
            guard !isAutoUncompleting else {
                dataSource.markSetDirty(set, field: field)
                return true
            }
            isAutoUncompleting = true
            Task { @MainActor in
                await dataSource.uncompleteSet(
                    set,
                    previousContribution: contributionBeforeEdit
                )
                isAutoUncompleting = false
            }
            return true
        } else {
            dataSource.markSetDirty(set, field: field)
            return false
        }
    }

    private func applyParsedRepsInput(_ input: RepsTargetInput) {
        guard input != .invalid else {
            handleFieldEdit(field: .reps) {}
            return
        }

        let startedAutoUncomplete = handleFieldEdit(field: .reps) {
            switch input {
            case .empty:
                set.reps = nil
                set.overrideTargetRepMin = nil
                set.overrideTargetRepMax = nil
            case let .single(reps):
                set.reps = nil
                set.overrideTargetRepMin = reps
                set.overrideTargetRepMax = reps
            case let .range(min, max):
                set.reps = nil
                set.overrideTargetRepMin = min
                set.overrideTargetRepMax = max
            case .invalid:
                break
            }
        }

        guard !startedAutoUncomplete else { return }

        Task {
            // Emptying the reps field is "never mind", not "remove the target" — the template's
            // prescription has to survive a backspace, so the inherited layer is left alone.
            await dataSource.persistTargetRepOverride(
                set,
                min: set.overrideTargetRepMin,
                max: set.overrideTargetRepMax,
                clearsInheritedTarget: false
            )
        }
    }

    private func commitTargetRepRange(_ min: Int?, _ max: Int?) {
        let currentInput = RepsTargetInputParser.parse(repsText)
        var didCommit = false
        let startedAutoUncomplete = handleFieldEdit(field: .reps) {
            didCommit = CustomRepRangeCommitter.commit(min: min, max: max, to: set)
            guard didCommit else { return }

            switch currentInput {
            case .range, .invalid:
                suppressNextRepsTextChange = true
                repsText = ""
            case .empty, .single:
                break
            }
        }

        guard didCommit else { return }
        guard !startedAutoUncomplete else { return }

        Task {
            await dataSource.persistTargetRepOverride(
                set,
                min: set.overrideTargetRepMin,
                max: set.overrideTargetRepMax,
                clearsInheritedTarget: min == nil && max == nil
            )
        }
    }

    private func completionInput(for exercise: ChartExerciseData) -> SetCompletionInput? {
        if exercise.supportsUnilateralLogging, exercise.unilateral {
            let leftReps = Self.singleRepsValue(from: leftRepsText)
            let rightReps = Self.singleRepsValue(from: rightRepsText)
            let durationSeconds = Self.durationSecondsValue(from: durationText)

            if !leftRepsText.isEmpty && leftReps == nil {
                return nil
            }
            if !rightRepsText.isEmpty && rightReps == nil {
                return nil
            }
            if !durationText.isEmpty && durationSeconds == nil {
                return nil
            }

            let distance = UnitConversion.parseDecimal(distanceText)
            guard
                (leftReps ?? 0) > 0 ||
                (rightReps ?? 0) > 0 ||
                (durationSeconds ?? 0) > 0 ||
                (distance ?? 0) > 0
            else { return nil }

            return SetCompletionInput(
                weight: UnitConversion.parseDisplayedWeight(weightText, unitPreference: dataSource.unitPreference),
                durationSeconds: durationSeconds,
                distanceMeters: distance,
                leftReps: leftReps,
                rightReps: rightReps,
                leftRIR: leftRIRValue,
                rightRIR: rightRIRValue
            )
        }

        let parsedReps = RepsTargetInputParser.parse(repsText)
        guard !parsedReps.blocksCompletion else { return nil }
        let durationSeconds = Self.durationSecondsValue(from: durationText)
        if !durationText.isEmpty && durationSeconds == nil {
            return nil
        }

        let distance = UnitConversion.parseDecimal(distanceText)
        guard
            (parsedReps.completionReps ?? 0) > 0 ||
            (durationSeconds ?? 0) > 0 ||
            (distance ?? 0) > 0
        else { return nil }

        return SetCompletionInput(
            weight: UnitConversion.parseDisplayedWeight(weightText, unitPreference: dataSource.unitPreference),
            reps: parsedReps.completionReps,
            durationSeconds: durationSeconds,
            distanceMeters: distance,
            rir: rirValue
        )
    }

    private func syncDerivedSetFields(for exercise: ChartExerciseData) {
        guard exercise.supportsUnilateralLogging, exercise.unilateral else { return }
        set.syncDerivedPerformanceFields(for: exercise)
    }

    // MARK: - Formatters

    /// Format weight for display using locale-aware decimal separator.
    private static func formatWeight(_ value: Double, unitPreference: UnitPreference) -> String {
        UnitConversion.formatDisplayedWeight(value, unitPreference: unitPreference)
    }

    /// Format distance for display using locale-aware decimal separator.
    private static func formatDistance(_ value: Double) -> String {
        UnitConversion.formatWeight(value)
    }

    private func refreshDisplayTextForUnitChange(from oldValue: UnitPreference, to newValue: UnitPreference) {
        defer { lastUnitPreference = newValue }
        guard oldValue != newValue else { return }
        let oldWeightText = set.weight.map { Self.formatWeight($0, unitPreference: oldValue) } ?? ""
        guard weightText.isEmpty || weightText == oldWeightText else { return }
        weightText = set.weight.map { Self.formatWeight($0, unitPreference: newValue) } ?? ""
    }

    private static func formatDurationForInput(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private static func durationSecondsValue(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let seconds = Int(trimmed), seconds >= 0 {
            return seconds
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let minutesText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let secondsText = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !minutesText.isEmpty,
            !secondsText.isEmpty,
            let minutes = Int(minutesText),
            let seconds = Int(secondsText),
            minutes >= 0,
            (0..<60).contains(seconds)
        else {
            return nil
        }

        return (minutes * 60) + seconds
    }

    private static func repsTextValue(for set: WorkoutSet) -> String {
        if let reps = set.reps {
            return "\(reps)"
        }
        return ""
    }

    private static func singleRepsValue(from text: String) -> Int? {
        switch RepsTargetInputParser.parse(text) {
        case let .single(reps):
            return reps
        case .empty, .range, .invalid:
            return nil
        }
    }

    /// Compute the reps placeholder from the active target rep guidance.
    ///
    /// - Both min & max set and different → "8-12"
    /// - Both min & max set and equal → "8"
    /// - Only min set → "8"
    /// - Only max set → "12"
    /// - Neither set → "0" (default)
    static func repsPlaceholder(for set: WorkoutSet) -> String {
        let bounds = set.preferredTargetRepBounds
        let min = bounds.min
        let max = bounds.max

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

extension SetTableView {
    static func unilateralTargetPresentation(
        for set: WorkoutSet,
        exercise: ChartExerciseData
    ) -> UnilateralTargetPresentation {
        let defaultPlaceholder = SetRowWrapper.repsPlaceholder(for: set)
        guard exercise.usesTotalAcrossSidesRepTargets else {
            return UnilateralTargetPresentation(
                leftPlaceholder: defaultPlaceholder,
                rightPlaceholder: defaultPlaceholder,
                sharedHint: nil
            )
        }

        return UnilateralTargetPresentation(
            leftPlaceholder: "0",
            rightPlaceholder: "0",
            sharedHint: totalAcrossSidesHint(for: set)
        )
    }

    static func totalAcrossSidesHint(for set: WorkoutSet) -> String? {
        let bounds = set.preferredTargetRepBounds
        let min = bounds.min
        let max = bounds.max

        switch (min, max) {
        case let (.some(lo), .some(hi)) where lo == hi:
            return "\(lo) total"
        case let (.some(lo), .some(hi)):
            return "\(lo)-\(hi) total"
        case let (.some(lo), .none):
            return "\(lo) total"
        case let (.none, .some(hi)):
            return "\(hi) total"
        case (.none, .none):
            return nil
        }
    }
}

// MARK: - Custom Keyboard

/// Mutable editing context used by the custom set-entry keyboard.
final class SetEntryKeyboardContext {
    let ownerSetID: UUID
    let trackingType: TrackingType
    let equipmentType: EquipmentType
    let inputOrder: [SetRowInputField]
    /// Tracked focused field — updated directly by the keyboard overlay on Prev/Next.
    /// Use this instead of getFocusedField() for rendering decisions.
    var trackedField: SetRowInputField?
    let getFocusedField: () -> SetRowInputField?
    let setFocusedField: (SetRowInputField?) -> Void
    let getFieldValue: (SetRowInputField) -> String
    let setFieldValue: (SetRowInputField, String) -> Void
    private let getBilateralRIRValue: () -> Double?
    private let setBilateralRIRValue: (Double?) -> Void
    private let getLeftRIRValue: () -> Double?
    private let setLeftRIRValue: (Double?) -> Void
    private let getRightRIRValue: () -> Double?
    private let setRightRIRValue: (Double?) -> Void
    let getSuggestedWeight: () -> Double?
    let getWeightIncrement: () -> Double
    let unitPreference: UnitPreference
    let getTargetRepRange: () -> (min: Int?, max: Int?)
    let commitTargetRepRange: (Int?, Int?) -> Void
    let onCompleteSet: (() -> Void)?
    /// `var` so the owning row can replace this with a fresh snapshot closure on
    /// every text edit. Capturing self into a closure stored on this long-lived
    /// class doesn't reliably read live @State, so we re-stuff the snapshot from
    /// the row's onChange handlers instead.
    var canCompleteSet: () -> Bool
    let canMovePrevious: () -> Bool
    let canMoveNext: () -> Bool
    let movePrevious: () -> Void
    let moveNext: () -> Void
    let dismiss: () -> Void

    init(
        ownerSetID: UUID,
        trackingType: TrackingType,
        equipmentType: EquipmentType,
        inputOrder: [SetRowInputField],
        activeField: SetRowInputField? = nil,
        getFocusedField: @escaping () -> SetRowInputField?,
        setFocusedField: @escaping (SetRowInputField?) -> Void,
        getFieldValue: @escaping (SetRowInputField) -> String,
        setFieldValue: @escaping (SetRowInputField, String) -> Void,
        getBilateralRIRValue: @escaping () -> Double?,
        setBilateralRIRValue: @escaping (Double?) -> Void,
        getLeftRIRValue: @escaping () -> Double? = { nil },
        setLeftRIRValue: @escaping (Double?) -> Void = { _ in },
        getRightRIRValue: @escaping () -> Double? = { nil },
        setRightRIRValue: @escaping (Double?) -> Void = { _ in },
        getSuggestedWeight: @escaping () -> Double?,
        getWeightIncrement: @escaping () -> Double = { 2.5 },
        unitPreference: UnitPreference = .metric,
        getTargetRepRange: @escaping () -> (min: Int?, max: Int?) = { (nil, nil) },
        commitTargetRepRange: @escaping (Int?, Int?) -> Void = { _, _ in },
        onCompleteSet: (() -> Void)? = nil,
        canCompleteSet: @escaping () -> Bool = { true },
        canMovePrevious: @escaping () -> Bool,
        canMoveNext: @escaping () -> Bool,
        movePrevious: @escaping () -> Void,
        moveNext: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.ownerSetID = ownerSetID
        self.trackingType = trackingType
        self.equipmentType = equipmentType
        self.inputOrder = inputOrder
        self.getFocusedField = getFocusedField
        self.setFocusedField = setFocusedField
        self.getFieldValue = getFieldValue
        self.setFieldValue = setFieldValue
        self.getBilateralRIRValue = getBilateralRIRValue
        self.setBilateralRIRValue = setBilateralRIRValue
        self.getLeftRIRValue = getLeftRIRValue
        self.setLeftRIRValue = setLeftRIRValue
        self.getRightRIRValue = getRightRIRValue
        self.setRightRIRValue = setRightRIRValue
        self.getSuggestedWeight = getSuggestedWeight
        self.getWeightIncrement = getWeightIncrement
        self.unitPreference = unitPreference
        self.getTargetRepRange = getTargetRepRange
        self.commitTargetRepRange = commitTargetRepRange
        self.onCompleteSet = onCompleteSet
        self.canCompleteSet = canCompleteSet
        self.canMovePrevious = canMovePrevious
        self.canMoveNext = canMoveNext
        self.movePrevious = movePrevious
        self.moveNext = moveNext
        self.dismiss = dismiss
        self.trackedField = activeField ?? getFocusedField()
    }

    var canMovePreviousInTrackedOrder: Bool {
        guard let trackedField else { return false }
        guard let index = inputOrder.firstIndex(of: trackedField) else { return false }
        return index > 0
    }

    var canMoveNextInTrackedOrder: Bool {
        guard let trackedField else { return false }
        guard let index = inputOrder.firstIndex(of: trackedField) else { return false }
        return index < inputOrder.count - 1
    }

    func movePreviousInTrackedOrder() {
        guard let trackedField else { return }
        guard let index = inputOrder.firstIndex(of: trackedField), index > 0 else { return }
        let previousField = inputOrder[index - 1]
        self.trackedField = previousField
        setFocusedField(previousField)
    }

    func moveNextInTrackedOrder() {
        guard let trackedField else { return }
        guard let index = inputOrder.firstIndex(of: trackedField), index < inputOrder.count - 1 else { return }
        let nextField = inputOrder[index + 1]
        self.trackedField = nextField
        setFocusedField(nextField)
    }

    var canEditActiveRIR: Bool {
        resolvedRIRField != nil
    }

    var resolvedRIRField: SetRowInputField? {
        Self.rirField(for: trackedField)
    }

    func resolvedRIRValue(for field: SetRowInputField? = nil) -> Double? {
        switch Self.rirField(for: field ?? trackedField) {
        case .some(.reps):
            return getBilateralRIRValue()
        case .some(.leftReps):
            return getLeftRIRValue()
        case .some(.rightReps):
            return getRightRIRValue()
        case .some(.weight), .some(.duration), .some(.distance), .none:
            return nil
        }
    }

    func setResolvedRIRValue(_ value: Double?, for field: SetRowInputField? = nil) {
        switch Self.rirField(for: field ?? trackedField) {
        case .some(.reps):
            setBilateralRIRValue(value)
        case .some(.leftReps):
            setLeftRIRValue(value)
        case .some(.rightReps):
            setRightRIRValue(value)
        case .some(.weight), .some(.duration), .some(.distance), .none:
            break
        }
    }

    private static func rirField(for field: SetRowInputField?) -> SetRowInputField? {
        switch field {
        case .some(.reps), .some(.leftReps), .some(.rightReps):
            return field
        case .some(.weight), .some(.duration), .some(.distance), .none:
            return nil
        }
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
            // Clear the context before the focus: releasing focus re-enters here through the
            // row's `onChange(of: focusedInput)`, and the guard above has to already be false.
            context = nil
            current.setFocusedField(nil)
        }
    }

    func refresh() {
        objectWillChange.send()
    }
}

/// Sketch-inspired keyboard surface rendered at screen bottom while editing set fields.
struct SetEntryKeyboardOverlay: View {
    @ObservedObject var manager: SetEntryKeyboardManager

    @State private var refreshTick = 0
    @State private var repRangeEditMode = false
    @State private var repRangeMinText = ""
    @State private var repRangeMaxText = ""
    @State private var repRangeActiveField: RepRangeField = .min

    private enum RepRangeField { case min, max }

    /// One rung of the RIR scale. A struct rather than a tuple because `ForEach` needs a key path
    /// for its id, and Swift has none into tuple elements.
    private struct RIRChoice {
        let label: String
        let value: Double?
    }

    /// The scale, in the order it is offered. `nil` is "not recorded".
    private static let rirChoices: [RIRChoice] = [
        RIRChoice(label: "—", value: nil),
        RIRChoice(label: "0", value: 0),
        RIRChoice(label: "1", value: 1),
        RIRChoice(label: "2", value: 2),
        RIRChoice(label: "3", value: 3),
        RIRChoice(label: "4", value: 4),
        RIRChoice(label: "5+", value: 5)
    ]

    /// Height of the tallest thing that goes in the top strip's slot: an RIR chip, and the
    /// rep-range editor's input fields, are both 38pt.
    private static let slotContentHeight: CGFloat = 38

    /// Breathing room above and below that content.
    ///
    /// Sized by eye rather than derived. The slot is the card's first child now, so at the old
    /// 3pt the chips sat almost on the rounded top edge.
    private static let slotPadding: CGFloat = 8

    /// Height of the top strip's single content slot.
    ///
    /// The RIR chips and the rep-range editor swap in and out of it, so they must match exactly —
    /// any difference shows up as the set list nudging every time you toggle the editor.
    private static let slotHeight: CGFloat = slotContentHeight + slotPadding * 2

    var body: some View {
        Group {
            if let context = manager.context, context.trackedField != nil {
                VStack(spacing: 0) {
                    topStrip(for: context)
                    if hasTopStripContent(for: context) {
                        Divider().background(Color.border)
                    }
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
                    repRangeEditMode = false
                    refreshTick = 0
                }
                .onChange(of: manager.context?.trackedField) { _, newField in
                    guard !supportsRepRangeEditing(for: newField) else { return }
                    repRangeEditMode = false
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.context?.ownerSetID)
    }

    /// The band above the keys: one `slotHeight` row on a recessed ground, or nothing at all.
    ///
    /// There is no longer a "Set · Reps" label above it. Which field has focus is already said by
    /// the table's column headers, by the `L` / `R` labels beside each unilateral reps field, and
    /// by the accent border on the field itself — so the label row was 37pt spent on a duplicate.
    /// Note that this makes the slot the card's first child, against an 18pt corner radius, which
    /// is why every occupant centres its content in a fixed height rather than sitting flush.
    ///
    /// The fill is `bgCard`, the keypad's own ground. It was briefly `bg` — a step *down*, so the
    /// band would read as a well cut into the keys — but the strip is the card's first child, and
    /// a darker fill running into the 18pt top corners erased the card's silhouette: the band
    /// merged with the rest-timer bar above it, which is `bgCard` full-bleed. On the card's own
    /// ground the strip is one surface with the keys, and the chips carry the contrast the same
    /// way the number keys do (`bgSubtle` on `bgCard`). The divider does the separating.
    @ViewBuilder
    private func topStrip(for context: SetEntryKeyboardContext) -> some View {
        if hasTopStripContent(for: context) {
            slotContent(for: context)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgCard)
        }
    }

    /// Whichever of the three occupants this state calls for.
    ///
    /// The rep-range editor takes precedence while it is open. It and the chips answer to exactly
    /// the same three fields (`canEditActiveRIR` and `supportsRepRangeEditing` both gate on reps /
    /// leftReps / rightReps), so replacing one with the other leaves no state uncovered. Stacking
    /// them — which is what this did — dropped the set list 88pt the moment you opened the editor,
    /// with a thumb already on the keypad.
    @ViewBuilder
    private func slotContent(for context: SetEntryKeyboardContext) -> some View {
        if repRangeEditMode {
            repRangeEditor(for: context)
        } else if showRIRChips(for: context) {
            // Seven equal columns across the band, not a left-packed run inside a scroll view.
            // The chips only need 266pt of the ~378pt the card has, so packing them left put a
            // hole at the trailing edge — and the scroll view dragged under the thumb even with
            // nothing to scroll, because a SwiftUI scroll view bounces along its axis whether or
            // not the content overflows. Equal columns also keep the gaps even at the two ends.
            HStack(spacing: 0) {
                ForEach(Self.rirChoices, id: \.label) { choice in
                    rirChip(context, label: choice.label, value: choice.value)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: Self.slotHeight)
        } else if shouldShowWeightHelper(for: context) {
            Text(weightHelperText(context))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: Self.slotHeight, alignment: .leading)
        }
    }

    /// Whether `topStrip` renders anything for this state.
    ///
    /// Drives the divider: on a duration or distance field the strip is empty, and without this
    /// the divider would sit flush against the card's rounded top edge with nothing above it.
    private func hasTopStripContent(for context: SetEntryKeyboardContext) -> Bool {
        repRangeEditMode || showRIRChips(for: context) || shouldShowWeightHelper(for: context)
    }

    /// The rep-range editor, as one fixed-height row sharing the top strip's single slot with the
    /// RIR chips. `Self.slotHeight` is deliberately the same height as the chips: the two swap in
    /// place, so opening the editor must not move the set list underneath it.
    ///
    /// Cancel is an icon, not a word. A text Cancel next to the full "Rep Range" label needed
    /// 402pt inside the 378pt an SE gives the card, so it was cut altogether — which left Apply
    /// as the only exit visible from the row itself, the reverting one hidden behind the rail
    /// button's "Editing" state. A 30pt ✕ puts it back and still fits: worst case (an SE, with
    /// the error text in the label) the row wants 379pt of 339pt, and only the label scales.
    private func repRangeEditor(for context: SetEntryKeyboardContext) -> some View {
        let hasInvalidDraft = repRangeDraftState == .invalid

        return HStack(spacing: 8) {
            // The label doubles as the error line. The long form ("Use one rep value or an
            // ascending range.") has nowhere to live in a fixed-height row, and letting the row
            // grow to hold it would reintroduce the shift this layout exists to remove. The
            // fields and the buttons hold their widths; the label scales down ahead of them, far
            // enough (0.65) that even the longer error survives the narrowest phone unclipped.
            Label(
                hasInvalidDraft ? repRangeErrorText : "Range",
                systemImage: hasInvalidDraft ? "exclamationmark.triangle.fill" : "target"
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(hasInvalidDraft ? .danger : .accent)
            .lineLimit(1)
            .minimumScaleFactor(0.65)

            // Min, dash and max are one group on a tighter 6pt rhythm: they read as a single
            // range, and the 8pt the outer spacing would have spent between them pays for Cancel.
            HStack(spacing: 6) {
                repRangeInputField(
                    text: $repRangeMinText,
                    placeholder: "Min",
                    isActive: repRangeActiveField == .min,
                    showsError: hasInvalidDraft
                )
                .onTapGesture { repRangeActiveField = .min }

                Text("—")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textSecondary)

                repRangeInputField(
                    text: $repRangeMaxText,
                    placeholder: "Max",
                    isActive: repRangeActiveField == .max,
                    showsError: hasInvalidDraft
                )
                .onTapGesture { repRangeActiveField = .max }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            repRangeCancelButton { dismissRepRangeEditMode(context) }
                .layoutPriority(1)

            repRangeEditorButton(title: "Apply", prominent: true, disabled: hasInvalidDraft) {
                applyRepRange(context)
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.slotHeight)
    }

    /// Leave the editor without committing the draft, from inside the row.
    ///
    /// Reverts rather than closes: `dismissRepRangeEditMode` reloads both fields from the stored
    /// range, so a half-typed draft does not survive to the next time the editor opens.
    private func repRangeCancelButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textSecondary)
                .frame(width: 30, height: 30)
                .background(Color.bgHover)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel rep range")
    }

    /// Which half of the draft is wrong, short enough to sit in the label's place.
    ///
    /// `repRangeDraftState` collapses both failures into `.invalid`, but they need different
    /// wording: a zero is reachable because `handleRepRangeKey` accepts "0" as a first digit.
    private var repRangeErrorText: String {
        let values = [Int(repRangeMinText), Int(repRangeMaxText)].compactMap { $0 }
        return values.contains(where: { $0 <= 0 }) ? "Reps must be 1+" : "Min below max"
    }

    private func repRangeEditorButton(
        title: String,
        prominent: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(disabled ? .textTertiary : (prominent ? .white : .textPrimary))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(disabled ? Color.bgInput : (prominent ? Color.accent : Color.bgHover))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(prominent ? Color.clear : Color.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func repRangeInputField(
        text: Binding<String>,
        placeholder: String,
        isActive: Bool,
        showsError: Bool = false
    ) -> some View {
        Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(text.wrappedValue.isEmpty ? .textTertiary : .textPrimary)
            .frame(width: 56, height: 38)
            .background(isActive ? Color.bgHover : Color.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        showsError ? Color.danger : (isActive ? Color.accent : Color.border),
                        lineWidth: showsError || isActive ? 1.5 : 1
                    )
            )
    }

    private func enterRepRangeEditMode(_ context: SetEntryKeyboardContext) {
        let range = context.getTargetRepRange()
        repRangeMinText = range.min.map { "\($0)" } ?? ""
        repRangeMaxText = range.max.map { "\($0)" } ?? ""
        repRangeActiveField = .min
        repRangeEditMode = true
        refreshTick += 1
    }

    private func dismissRepRangeEditMode(_ context: SetEntryKeyboardContext) {
        let range = context.getTargetRepRange()
        repRangeMinText = range.min.map { "\($0)" } ?? ""
        repRangeMaxText = range.max.map { "\($0)" } ?? ""
        repRangeActiveField = .min
        repRangeEditMode = false
        refreshTick += 1
    }

    private func applyRepRange(_ context: SetEntryKeyboardContext) {
        guard repRangeDraftState != .invalid else {
            refreshTick += 1
            return
        }
        let minVal = Int(repRangeMinText)
        let maxVal = Int(repRangeMaxText)
        context.commitTargetRepRange(minVal, maxVal)
        repRangeEditMode = false
        refreshTick += 1
        manager.refresh()
    }

    private func repRangeButton(for context: SetEntryKeyboardContext) -> some View {
        let range = context.getTargetRepRange()
        let hasRange = range.min != nil || range.max != nil
        let rangeLabel: String? = {
            switch (range.min, range.max) {
            case let (.some(lo), .some(hi)) where lo == hi:
                return "\(lo)"
            case let (.some(lo), .some(hi)):
                return "\(lo)-\(hi)"
            case let (.some(lo), .none):
                return "\(lo)"
            case let (.none, .some(hi)):
                return "\(hi)"
            default:
                return nil
            }
        }()
        let isEditing = repRangeEditMode

        return Button {
            if isEditing {
                dismissRepRangeEditMode(context)
            } else {
                enterRepRangeEditMode(context)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "target")
                    .font(.system(size: 13, weight: .semibold))
                if let label = rangeLabel {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                } else if isEditing {
                    Text("Editing")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("Set Range")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundColor(isEditing || hasRange ? .white : .accent)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isEditing ? Color.accent.opacity(0.85) : (hasRange ? Color.accent : Color.accent.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isEditing || hasRange ? Color.clear : Color.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func rirChip(_ context: SetEntryKeyboardContext, label: String, value: Double?) -> some View {
        let currentValue = context.resolvedRIRValue()
        let selected = (currentValue == value) || (currentValue == nil && value == nil)
        return Button {
            context.setResolvedRIRValue(value)
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
        let isDurationField = focusedField == .duration
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { key in
                let isDecimalKey = key == "."
                let showColon = isDecimalKey && isDurationField && !repRangeEditMode
                // D6: Show dash key on reps field or rep range edit mode
                let showDash = isDecimalKey && (isRepsField || repRangeEditMode)
                let keyDisabled = isDecimalKey && !decimalAllowed && !isRepsField && !isDurationField && !repRangeEditMode
                let keyLabel = showColon ? ":" : (showDash ? "-" : (keyDisabled ? "•" : key))
                let effectiveKey = showColon ? ":" : (showDash ? "-" : key)
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
        let onRepsField = focusedField == .reps || focusedField == .leftReps || focusedField == .rightReps
        let canGoPrev = context.canMovePreviousInTrackedOrder
        let canGoNext = context.canMoveNextInTrackedOrder
        let suggestedWeight = context.getSuggestedWeight()
        let increment = context.getWeightIncrement()
        let canNudgeWeight = focusedField == .weight
        let canNudgeReps = onRepsField
        let canNudgeActiveField = canNudgeWeight || canNudgeReps

        return VStack(spacing: 6) {
            // D1: Keyboard-dismiss icon instead of "Hide" text
            Button {
                repRangeEditMode = false
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

            // D2: Context-aware suggestion button — weight suggestion or rep range
            if onWeightField {
                Button {
                    applySuggestedWeight(context)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 13, weight: .semibold))
                        if let weight = suggestedWeight {
                            Text(UnitConversion.formatWeightLabel(weight, unitPreference: context.unitPreference))
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
            } else if onRepsField {
                repRangeButton(for: context)
            } else {
                Color.clear.frame(height: 44)
            }

            // D3: +/- with exercise increment; D5: +1/-1 for reps (replaces F/P)
            HStack(spacing: 8) {
                railOptionButton(title: "−", selected: false, disabled: !canNudgeActiveField) {
                    if canNudgeWeight {
                        nudgeWeight(context, delta: -increment)
                    } else if canNudgeReps {
                        nudgeReps(context, delta: -1)
                    }
                }
                railOptionButton(title: "+", selected: false, disabled: !canNudgeActiveField) {
                    if canNudgeWeight {
                        nudgeWeight(context, delta: increment)
                    } else if canNudgeReps {
                        nudgeReps(context, delta: 1)
                    }
                }
            }

            HStack(spacing: 8) {
                railNavButton(title: "Prev", disabled: !canGoPrev) {
                    repRangeEditMode = false
                    context.movePreviousInTrackedOrder()
                    refreshTick += 1
                    manager.show(context)
                }
                railNavButton(title: "Next", disabled: !canGoNext) {
                    repRangeEditMode = false
                    if canGoNext {
                        context.moveNextInTrackedOrder()
                    }
                    refreshTick += 1
                    manager.show(context)
                }
            }

            Button {
                if context.canCompleteSet() {
                    context.onCompleteSet?()
                }
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
            .disabled(!context.canCompleteSet())
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

    private func railOptionButton(title: String, selected: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(disabled ? .textTertiary : (selected ? .black.opacity(0.9) : .textPrimary))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(disabled ? Color.bgInput : (selected ? Color.white.opacity(0.85) : Color.bgHover))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.border, lineWidth: selected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
        // Route input to rep range mini-fields when in edit mode
        if repRangeEditMode {
            handleRepRangeKey(key)
            return
        }
        guard let field = context.trackedField else { return }
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

        if key == ":" {
            guard field == .duration, !value.contains(":") else { return }
            context.setFieldValue(field, value.isEmpty ? "0:" : value + ":")
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

    private func handleRepRangeKey(_ key: String) {
        var text = repRangeActiveField == .min ? repRangeMinText : repRangeMaxText

        if key == "⌫" {
            text = String(text.dropLast())
        } else if key == "-" {
            // Dash switches from min to max field
            repRangeActiveField = .max
            refreshTick += 1
            return
        } else if key == "." || key == ":" {
            // Not valid for integer rep range fields
            return
        } else {
            // Only allow up to 3 digits
            guard text.count < 3 else { return }
            if text == "0" { text = "" }
            text += key
        }

        if repRangeActiveField == .min {
            repRangeMinText = text
        } else {
            repRangeMaxText = text
        }
        refreshTick += 1
    }

    private func allowsDecimal(_ field: SetRowInputField?) -> Bool {
        field == .weight || field == .distance
    }

    private var repRangeDraftState: RepsTargetInput {
        let minValue = Int(repRangeMinText)
        let maxValue = Int(repRangeMaxText)

        switch (minValue, maxValue) {
        case let (.some(lowerBound), .some(upperBound))
        where lowerBound > 0 && upperBound > 0 && lowerBound < upperBound:
            return .range(lowerBound, upperBound)
        case let (.some(value), .some(otherValue))
        where value > 0 && otherValue > 0 && value == otherValue:
            return .single(value)
        case let (.some(value), .none) where value > 0,
             let (.none, .some(value)) where value > 0:
            return .single(value)
        case (.none, .none):
            return .empty
        default:
            return .invalid
        }
    }

    private func showRIRChips(for context: SetEntryKeyboardContext) -> Bool {
        context.canEditActiveRIR
    }

    private func supportsRepRangeEditing(for field: SetRowInputField?) -> Bool {
        switch field {
        case .reps, .leftReps, .rightReps:
            return true
        case .weight, .duration, .distance, .none:
            return false
        }
    }

    private func shouldShowWeightHelper(for context: SetEntryKeyboardContext) -> Bool {
        context.trackedField == .weight && context.equipmentType == .barbell
    }

    private func applySuggestedWeight(_ context: SetEntryKeyboardContext) {
        guard let suggested = context.getSuggestedWeight() else { return }
        context.setFieldValue(
            .weight,
            UnitConversion.formatDisplayedWeight(suggested, unitPreference: context.unitPreference)
        )
        refreshTick += 1
        manager.refresh()
    }

    private func nudgeWeight(_ context: SetEntryKeyboardContext, delta: Double) {
        guard delta.isFinite else { return }
        let increment = abs(delta)
        guard increment > 0 else { return }

        let raw = context.getFieldValue(.weight)
        let current = UnitConversion.parseDecimal(raw) ?? 0
        let quotient = current / increment
        let roundedQuotient = quotient.rounded()
        let isOnGrid = abs(quotient - roundedQuotient) < 1e-9
        let nextMultiple: Double

        if delta > 0 {
            nextMultiple = isOnGrid ? roundedQuotient + 1 : ceil(quotient)
        } else {
            nextMultiple = isOnGrid ? roundedQuotient - 1 : floor(quotient)
        }

        let next = max(0, nextMultiple * increment)
        let formatted = UnitConversion.formatWeight(next)
        context.setFieldValue(.weight, formatted)
        refreshTick += 1
        manager.refresh()
    }

    private func nudgeReps(_ context: SetEntryKeyboardContext, delta: Int) {
        guard let field = context.trackedField else { return }
        guard field == .reps || field == .leftReps || field == .rightReps else { return }

        let raw = context.getFieldValue(field)
        // If reps contains a dash (rep range like "8-12"), don't nudge
        guard !raw.contains("-") else { return }
        let current = Int(raw) ?? 0
        let next = max(0, current + delta)
        context.setFieldValue(field, next == 0 ? "" : String(next))
        refreshTick += 1
        manager.refresh()
    }

    private func weightHelperText(_ context: SetEntryKeyboardContext) -> String {
        let raw = context.getFieldValue(.weight)
        let total = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
        let barWeight = context.unitPreference == .imperial ? 45.0 : 20.0
        let unit = UnitConversion.weightUnitLabel(for: context.unitPreference)
        if total <= barWeight {
            let extra = max(0, barWeight - total)
            return "0 \(unit) on both sides + \(display(barWeight)) \(unit) bar weight = 0 \(unit) + extra \(display(extra)) \(unit)"
        }
        let side = max(0, (total - barWeight) / 2)
        return "\(display(side)) \(unit) on both sides + \(display(barWeight)) \(unit) bar weight = \(display(total)) \(unit) total"
    }

    private func display(_ value: Double) -> String {
        UnitConversion.formatWeight(value)
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
                exercise: ChartExerciseData(from: Exercise(
                    name: "Bench Press",
                    equipmentType: .barbell,
                    trackingType: .weightReps
                )),
                setNumber: 1,
                weightText: .constant("40"),
                repsText: .constant("10"),
                leftRepsText: .constant(""),
                rightRepsText: .constant(""),
                durationText: .constant(""),
                distanceText: .constant(""),
                rirValue: .constant(nil),
                leftRIRValue: .constant(nil),
                rightRIRValue: .constant(nil),
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
                exercise: ChartExerciseData(from: Exercise(
                    name: "Bench Press",
                    equipmentType: .barbell,
                    trackingType: .weightReps
                )),
                setNumber: 1,
                weightText: .constant("80"),
                repsText: .constant("8"),
                leftRepsText: .constant(""),
                rightRepsText: .constant(""),
                durationText: .constant(""),
                distanceText: .constant(""),
                rirValue: .constant(0),
                leftRIRValue: .constant(nil),
                rightRIRValue: .constant(nil),
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
                exercise: ChartExerciseData(from: Exercise(
                    name: "Bench Press",
                    equipmentType: .barbell,
                    trackingType: .weightReps
                )),
                setNumber: 2,
                weightText: .constant(""),
                repsText: .constant(""),
                leftRepsText: .constant(""),
                rightRepsText: .constant(""),
                durationText: .constant(""),
                distanceText: .constant(""),
                rirValue: .constant(nil),
                leftRIRValue: .constant(nil),
                rightRIRValue: .constant(nil),
                onComplete: {},
                onDelete: {},
                onChangeSetType: { _ in },
                onEditNote: {}
            )

            // Add buttons
            HStack(spacing: 8) {
                Text("+ Warmup")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.warmup)
                    .frame(width: 96)
                    .frame(minHeight: 44)
                    .background(Color.warmupSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("+ Add Set")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(Color.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color.bgCard)
        .cornerRadius(12)
        .padding()
    }
}
