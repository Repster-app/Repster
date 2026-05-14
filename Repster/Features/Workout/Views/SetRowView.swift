// SetRowView.swift
// A single row in the set table, composing atomic components (WP01) into a horizontal layout.
// Spec: design-system.md Section 6.3 (Set Table), Section 10 (SetInputStyle)
// Contract: WP03 T012, T014 (column adaptation), T015 (warmup/completed styling), T017 (context menu)
//
// Pure presentational component — delegates all actions to closures.
// Does NOT reference ViewModel or Services directly.

import SwiftUI

enum UnilateralSetRowLayout {
    static let controlHeight: CGFloat = 36
    static let verticalSpacing: CGFloat = 6
    static let weightToRepsSpacing: CGFloat = 8
    static let sideLabelSpacing: CGFloat = 6
    static let sideLabelWidth: CGFloat = 10
    static let maxWeightWidth: CGFloat = 104
    static let weightWidthFraction: CGFloat = 0.42
    static let groupedColumnSpacing: CGFloat = 4
    static let weightRepsGroupFraction: CGFloat = 2.0 / 3.0

    static func weightWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, min(maxWeightWidth, availableWidth * weightWidthFraction))
    }

    static func durationWidth(for totalWidth: CGFloat) -> CGFloat {
        max(0, (totalWidth - groupedColumnSpacing) * (1 - weightRepsGroupFraction))
    }

    static func weightRepsGroupWidth(for totalWidth: CGFloat) -> CGFloat {
        let durationWidth = durationWidth(for: totalWidth)
        return max(0, totalWidth - durationWidth - groupedColumnSpacing)
    }
}

/// RIR picker options displayed in the Menu dropdown.
/// Values: nil (—), 0, 1, 2, 3, 4, 5 (represents 5+).
enum RIROption: CaseIterable, Identifiable {
    case none, rir0, rir1, rir2, rir3, rir4, rir5plus

    var id: String { displayName }

    var displayName: String {
        switch self {
        case .none:     return "—"
        case .rir0:     return "0"
        case .rir1:     return "1"
        case .rir2:     return "2"
        case .rir3:     return "3"
        case .rir4:     return "4"
        case .rir5plus: return "5+"
        }
    }

    var doubleValue: Double? {
        switch self {
        case .none:     return nil
        case .rir0:     return 0
        case .rir1:     return 1
        case .rir2:     return 2
        case .rir3:     return 3
        case .rir4:     return 4
        case .rir5plus: return 5
        }
    }

    var color: Color {
        switch self {
        case .none:     return .textTertiary
        case .rir0:     return .rir0
        case .rir1:     return .rir1
        case .rir2:     return .rir2
        case .rir3:     return .rir3
        case .rir4:     return .rir4
        case .rir5plus: return .rir5
        }
    }

    /// Convert from a stored Double? value to the corresponding RIROption.
    static func from(doubleValue: Double?) -> RIROption {
        guard let v = doubleValue else { return .none }
        switch v {
        case 0: return .rir0
        case 1: return .rir1
        case 2: return .rir2
        case 3: return .rir3
        case 4: return .rir4
        default: return .rir5plus
        }
    }
}

/// A single row in the set table showing set number, input fields, RIR picker, PR badge, and completion checkbox.
///
/// Columns adapt to the exercise's `trackingType`:
/// - `.weightReps` → weight + reps
/// - `.duration` → duration only
/// - `.durationDistance` → distance + duration
/// - `.weightDistance` → weight + distance
/// - `.weightRepsDuration` → weight + reps + duration
///
/// Row height: 52pt. Bottom divider at white 3% opacity.
/// Warmup rows render at 0.5 opacity. Completed rows have green tint background.
struct SetRowView: View {

    // MARK: - Data

    /// The set being displayed.
    let set: WorkoutSet

    /// The exercise this set belongs to (determines which input columns to show).
    let exercise: Exercise

    /// The display number for the set badge (1-indexed).
    let setNumber: Int

    // MARK: - Input Bindings

    /// Text binding for the weight input field.
    @Binding var weightText: String

    /// Text binding for the reps input field.
    @Binding var repsText: String

    /// Text binding for the left reps input field when unilateral logging is enabled.
    @Binding var leftRepsText: String

    /// Text binding for the right reps input field when unilateral logging is enabled.
    @Binding var rightRepsText: String

    /// Text binding for the duration input field.
    @Binding var durationText: String

    /// Text binding for the distance input field.
    @Binding var distanceText: String

    /// Binding for the RIR value (nil = not set, 0-5 = RIR value).
    @Binding var rirValue: Double?

    /// Binding for the left-side RIR value when unilateral logging is enabled.
    @Binding var leftRIRValue: Double?

    /// Binding for the right-side RIR value when unilateral logging is enabled.
    @Binding var rightRIRValue: Double?

    // MARK: - Template Targets

    /// Target RIR from template (nil = no target). Shown as a dimmed hint when actual RIR is not set.
    var targetRIR: Int? = nil

    /// Placeholder for the reps input field. Defaults to "0", but shows target rep range (e.g. "8-12") when set from a template.
    var repsPlaceholder: String = "0"

    /// Placeholder for the left reps input when unilateral logging is enabled.
    var leftRepsPlaceholder: String = "0"

    /// Placeholder for the right reps input when unilateral logging is enabled.
    var rightRepsPlaceholder: String = "0"

    /// Optional hint describing how unilateral rep targets should be interpreted.
    var unilateralTargetHint: String? = nil

    // MARK: - Actions

    /// Called when the completion checkbox is tapped.
    let onComplete: () -> Void

    /// Returns whether the current draft state can be completed from the custom keyboard.
    var canCompleteSet: () -> Bool = { true }

    /// Called when "Delete Set" is chosen from the context menu.
    let onDelete: () -> Void

    /// Called when a set type is selected from the context menu.
    let onChangeSetType: (SetType) -> Void

    /// Called when "Add Note" / "Edit Note" is chosen from the context menu.
    let onEditNote: () -> Void

    /// Called when the custom keyboard commits a rep-range target for this row.
    var onCommitTargetRepRange: (Int?, Int?) -> Void = { _, _ in }

    /// Shared custom keyboard manager for sketch-matching keyboard UX.
    var keyboardManager: SetEntryKeyboardManager? = nil

    /// Current display unit preference for weight-entry helpers.
    var unitPreference: UnitPreference = .metric

    /// Resolved global/default weight increment stored in kg.
    var defaultWeightIncrement: Double = 2.5

    /// Optional suggested weight shown in custom keyboard actions.
    var suggestedWeight: Double? = nil

    /// Overrides `set.prStatus` for badge display when non-nil (suppresses dominated matches).
    var prStatusOverride: CachedPRStatus?? = nil

    // MARK: - Body

    /// Row-local active input field, used by the custom set-entry keyboard flow.
    @State private var focusedInput: SetRowInputField?

    var body: some View {
        HStack(spacing: 4) {
            // Set number badge — fixed 36pt column (with note indicator)
            setBadge
                .frame(width: 36)

            // Input fields — flexible columns based on trackingType
            inputFields

            // RIR picker — fixed 42pt column
            rirPicker
                .frame(width: 42)

            // PR badge — fixed 44pt column (Color.clear ensures space is always reserved)
            Color.clear
                .frame(width: 44, height: 1)
                .overlay(alignment: .trailing) {
                    PRBadgeView(status: prStatusOverride ?? set.prStatus)
                }

            // Completion checkbox — fixed 40pt column
            CompletionCheckbox(
                isChecked: set.completed,
                onToggle: onComplete
            )
            .frame(width: 40)
        }
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .background(rowBackground)
        .opacity(set.setType == .warmup ? 0.5 : 1.0)
        .overlay {
            if isEditingRow {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accent.opacity(0.20), lineWidth: 1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.white.opacity(0.03)),
            alignment: .bottom
        )
        .contextMenu {
            // Edit Set Type submenu
            Menu("Edit Set Type") {
                ForEach(SetType.allCases, id: \.self) { type in
                    Button {
                        onChangeSetType(type)
                    } label: {
                        if type == set.setType {
                            Label(type.displayName, systemImage: "checkmark")
                        } else {
                            Text(type.displayName)
                        }
                    }
                }
            }

            // Add / Edit Note
            Button {
                onEditNote()
            } label: {
                let hasNote = set.notes != nil && !(set.notes?.isEmpty ?? true)
                Label(hasNote ? "Edit Note" : "Add Note", systemImage: "note.text")
            }

            Divider()

            // Delete Set (destructive)
            Button("Delete Set", role: .destructive) {
                onDelete()
            }
        }
        .onChange(of: focusedInput) { _, newValue in
            if newValue == nil {
                keyboardManager?.hide(ownerSetID: set.id)
            } else {
                keyboardManager?.refresh()
            }
        }
        .onChange(of: keyboardManager?.context?.ownerSetID) { _, ownerSetID in
            if let ownerSetID, ownerSetID != set.id, focusedInput != nil {
                focusedInput = nil
            }
        }
        .onDisappear {
            keyboardManager?.hide(ownerSetID: set.id)
        }
    }

    // MARK: - RIR Picker

    /// Menu-based RIR picker with color-coded display.
    /// When a target RIR is set from a template and no actual RIR has been chosen,
    /// the target is shown as a dimmed hint with its color.
    private var rirPicker: some View {
        if isUnilateralLogging {
            return AnyView(
                VStack(spacing: UnilateralSetRowLayout.verticalSpacing) {
                    unilateralRIRControl(title: "L", value: $leftRIRValue)
                    unilateralRIRControl(title: "R", value: $rightRIRValue)
                }
            )
        }

        let currentOption = RIROption.from(doubleValue: rirValue)
        let targetOption: RIROption? = targetRIR.map { RIROption.from(doubleValue: Double($0)) }
        let showTarget = currentOption == .none && targetOption != nil && targetOption != RIROption.none

        return AnyView(Menu {
            ForEach(RIROption.allCases) { option in
                Button {
                    rirValue = option.doubleValue
                } label: {
                    HStack {
                        Text(option.displayName)
                        if option == currentOption {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Group {
                if showTarget, let target = targetOption {
                    // Show target RIR as dimmed hint
                    Text(target.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(target.color.opacity(0.45))
                } else {
                    Text(currentOption.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(currentOption.color)
                }
            }
            .frame(width: 36, height: 32)
            .background(rirBackground(for: showTarget ? .none : currentOption))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(rirBorderColor(for: showTarget ? .none : currentOption), lineWidth: 1)
            )
            .cornerRadius(7)
        })
    }

    /// Background color for the RIR cell based on selected option.
    private func rirBackground(for option: RIROption) -> Color {
        if option == .none {
            return set.completed ? Color.success.opacity(0.06) : Color.bgInput
        }
        return option.color.opacity(0.08)
    }

    /// Border color for the RIR cell based on selected option.
    private func rirBorderColor(for option: RIROption) -> Color {
        if option == .none {
            return set.completed ? Color.success.opacity(0.15) : Color.border
        }
        return option.color.opacity(0.30)
    }

    // MARK: - Input Fields (Column Adaptation T014)

    /// Renders the correct input fields based on the exercise's trackingType.
    @ViewBuilder
    private var inputFields: some View {
        switch exercise.trackingType {
        case .weightReps:
            if isUnilateralLogging {
                unilateralWeightAndRepsFields
            } else {
                SetInputField(
                    value: $weightText,
                    placeholder: "0",
                    keyboardType: .decimalPad,
                    isCompleted: set.completed,
                    isActiveOverride: focusedInput == .weight,
                    isCustomEntry: true,
                    onCustomTap: { activateCustomKeyboard(for: .weight) }
                )
                .frame(maxWidth: .infinity)

                SetInputField(
                    value: $repsText,
                    placeholder: repsPlaceholder,
                    keyboardType: .numberPad,
                    isCompleted: set.completed,
                    isActiveOverride: focusedInput == .reps,
                    isCustomEntry: true,
                    onCustomTap: { activateCustomKeyboard(for: .reps) }
                )
                .frame(maxWidth: .infinity)
            }

        case .duration:
            SetInputField(
                value: $durationText,
                placeholder: "MM:SS",
                keyboardType: .numberPad,
                isCompleted: set.completed,
                isActiveOverride: focusedInput == .duration,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .duration) }
            )
            .frame(maxWidth: .infinity)

        case .durationDistance:
            SetInputField(
                value: $distanceText,
                placeholder: "0",
                keyboardType: .decimalPad,
                isCompleted: set.completed,
                isActiveOverride: focusedInput == .distance,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .distance) }
            )
            .frame(maxWidth: .infinity)

            SetInputField(
                value: $durationText,
                placeholder: "MM:SS",
                keyboardType: .numberPad,
                isCompleted: set.completed,
                isActiveOverride: focusedInput == .duration,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .duration) }
            )
            .frame(maxWidth: .infinity)

        case .weightDistance:
            SetInputField(
                value: $weightText,
                placeholder: "0",
                keyboardType: .decimalPad,
                isCompleted: set.completed,
                isActiveOverride: focusedInput == .weight,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .weight) }
            )
            .frame(maxWidth: .infinity)

            SetInputField(
                value: $distanceText,
                placeholder: "0",
                keyboardType: .decimalPad,
                isCompleted: set.completed,
                isActiveOverride: focusedInput == .distance,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .distance) }
            )
            .frame(maxWidth: .infinity)

        case .weightDuration:
            SetInputField(
                value: $weightText,
                placeholder: "0",
                keyboardType: .decimalPad,
                isCompleted: set.completed,
                isActiveOverride: focusedInput == .weight,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .weight) }
            )
            .frame(maxWidth: .infinity)

            SetInputField(
                value: $durationText,
                placeholder: "MM:SS",
                keyboardType: .numberPad,
                isCompleted: set.completed,
                isActiveOverride: focusedInput == .duration,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .duration) }
            )
            .frame(maxWidth: .infinity)

        case .weightRepsDuration:
            if isUnilateralLogging {
                unilateralWeightAndRepsDurationFields
            } else {
                SetInputField(
                    value: $weightText,
                    placeholder: "0",
                    keyboardType: .decimalPad,
                    isCompleted: set.completed,
                    isActiveOverride: focusedInput == .weight,
                    isCustomEntry: true,
                    onCustomTap: { activateCustomKeyboard(for: .weight) }
                )
                .frame(maxWidth: .infinity)

                SetInputField(
                    value: $repsText,
                    placeholder: repsPlaceholder,
                    keyboardType: .numberPad,
                    isCompleted: set.completed,
                    isActiveOverride: focusedInput == .reps,
                    isCustomEntry: true,
                    onCustomTap: { activateCustomKeyboard(for: .reps) }
                )
                .frame(maxWidth: .infinity)

                SetInputField(
                    value: $durationText,
                    placeholder: "MM:SS",
                    keyboardType: .numberPad,
                    isCompleted: set.completed,
                    isActiveOverride: focusedInput == .duration,
                    isCustomEntry: true,
                    onCustomTap: { activateCustomKeyboard(for: .duration) }
                )
                .frame(maxWidth: .infinity)
            }

        case .custom:
            // Fallback: same as weightReps
            SetInputField(
                value: $weightText,
                placeholder: "0",
                keyboardType: .decimalPad,
                isCompleted: set.completed,
                isActiveOverride: focusedInput == .weight,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .weight) }
            )
            .frame(maxWidth: .infinity)

            SetInputField(
                value: $repsText,
                placeholder: repsPlaceholder,
                keyboardType: .numberPad,
                isCompleted: set.completed,
                isActiveOverride: focusedInput == .reps,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .reps) }
            )
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Row Background (T015)

    /// Green tint for completed rows, clear otherwise.
    @ViewBuilder
    private var rowBackground: some View {
        if self.set.completed {
            Color.successSoft
        } else if isEditingRow {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accent.opacity(0.05))
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
        } else {
            Color.clear
        }
    }

    private var hasNote: Bool {
        self.set.notes != nil && !(self.set.notes?.isEmpty ?? true)
    }

    private var isEditingRow: Bool {
        !set.completed && focusedInput != nil
    }

    private var isUnilateralLogging: Bool {
        exercise.unilateral && exercise.supportsUnilateralLogging
    }

    private var rowHeight: CGFloat {
        isUnilateralLogging ? 86 : 52
    }

    @ViewBuilder
    private var setBadge: some View {
        let badge = SetNumberBadge(
            number: setNumber,
            setType: set.setType,
            isCompleted: set.completed,
            hasNote: hasNote,
            isEditing: isEditingRow
        )

        if hasNote {
            Button {
                onEditNote()
            } label: {
                badge
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit set note")
        } else {
            badge
        }
    }

    private var orderedInputs: [SetRowInputField] {
        switch exercise.trackingType {
        case .weightReps, .custom:
            if isUnilateralLogging {
                return [.weight, .leftReps, .rightReps]
            }
            return [.weight, .reps]
        case .duration:
            return [.duration]
        case .durationDistance:
            return [.distance, .duration]
        case .weightDistance:
            return [.weight, .distance]
        case .weightDuration:
            return [.weight, .duration]
        case .weightRepsDuration:
            if isUnilateralLogging {
                return [.weight, .leftReps, .rightReps, .duration]
            }
            return [.weight, .reps, .duration]
        }
    }

    private var canMoveToNextInput: Bool {
        guard let focusedInput else { return false }
        guard let index = orderedInputs.firstIndex(of: focusedInput) else { return false }
        return index < orderedInputs.count - 1
    }

    private var canMoveToPreviousInput: Bool {
        guard let focusedInput else { return false }
        guard let index = orderedInputs.firstIndex(of: focusedInput) else { return false }
        return index > 0
    }

    private func focusNextInput() {
        guard let focusedInput else {
            focusedInput = orderedInputs.first
            return
        }
        guard let index = orderedInputs.firstIndex(of: focusedInput) else {
            self.focusedInput = orderedInputs.first
            return
        }
        let nextIndex = index + 1
        self.focusedInput = nextIndex < orderedInputs.count ? orderedInputs[nextIndex] : nil
    }

    private func focusPreviousInput() {
        guard let focusedInput else {
            self.focusedInput = orderedInputs.last
            return
        }
        guard let index = orderedInputs.firstIndex(of: focusedInput) else {
            self.focusedInput = orderedInputs.last
            return
        }
        let previousIndex = index - 1
        self.focusedInput = previousIndex >= 0 ? orderedInputs[previousIndex] : nil
    }

    private func activateCustomKeyboard(for field: SetRowInputField) {
        focusedInput = field
        keyboardManager?.show(makeKeyboardContext(activeField: field))
    }

    private func makeKeyboardContext(activeField: SetRowInputField? = nil) -> SetEntryKeyboardContext {
        let setID = set.id
        let trackingType = exercise.trackingType
        let focusBinding = $focusedInput
        let weightBinding = $weightText
        let repsBinding = $repsText
        let leftRepsBinding = $leftRepsText
        let rightRepsBinding = $rightRepsText
        let durationBinding = $durationText
        let distanceBinding = $distanceText
        let bilateralRIRBinding = $rirValue
        let leftRIRBinding = $leftRIRValue
        let rightRIRBinding = $rightRIRValue

        return SetEntryKeyboardContext(
            ownerSetID: setID,
            trackingType: trackingType,
            equipmentType: exercise.equipmentType,
            inputOrder: orderedInputs,
            activeField: activeField,
            getFocusedField: { focusBinding.wrappedValue },
            setFocusedField: { focusBinding.wrappedValue = $0 },
            getFieldValue: { field in
                switch field {
                case .weight:
                    return weightBinding.wrappedValue
                case .reps:
                    return repsBinding.wrappedValue
                case .leftReps:
                    return leftRepsBinding.wrappedValue
                case .rightReps:
                    return rightRepsBinding.wrappedValue
                case .duration:
                    return durationBinding.wrappedValue
                case .distance:
                    return distanceBinding.wrappedValue
                }
            },
            setFieldValue: { field, newValue in
                switch field {
                case .weight:
                    weightBinding.wrappedValue = newValue
                case .reps:
                    repsBinding.wrappedValue = newValue
                case .leftReps:
                    leftRepsBinding.wrappedValue = newValue
                case .rightReps:
                    rightRepsBinding.wrappedValue = newValue
                case .duration:
                    durationBinding.wrappedValue = newValue
                case .distance:
                    distanceBinding.wrappedValue = newValue
                }
            },
            getBilateralRIRValue: { bilateralRIRBinding.wrappedValue },
            setBilateralRIRValue: { bilateralRIRBinding.wrappedValue = $0 },
            getLeftRIRValue: { leftRIRBinding.wrappedValue },
            setLeftRIRValue: { leftRIRBinding.wrappedValue = $0 },
            getRightRIRValue: { rightRIRBinding.wrappedValue },
            setRightRIRValue: { rightRIRBinding.wrappedValue = $0 },
            getSuggestedWeight: { suggestedWeight },
            getWeightIncrement: {
                UnitConversion.resolvedWeightIncrementOption(
                    exerciseIncrement: exercise.weightIncrement,
                    defaultIncrement: defaultWeightIncrement,
                    unitPreference: unitPreference
                ).display
            },
            unitPreference: unitPreference,
            getTargetRepRange: {
                if case let .range(min, max) = RepsTargetInputParser.parse(repsBinding.wrappedValue) {
                    return (min: min, max: max)
                }
                return set.preferredTargetRepBounds
            },
            commitTargetRepRange: onCommitTargetRepRange,
            onCompleteSet: { if !set.completed { onComplete() } },
            canCompleteSet: canCompleteSet,
            canMovePrevious: { canMoveToPreviousInput },
            canMoveNext: { canMoveToNextInput },
            movePrevious: { focusPreviousInput() },
            moveNext: { focusNextInput() },
            dismiss: { focusBinding.wrappedValue = nil }
        )
    }

    private var unilateralWeightAndRepsFields: some View {
        GeometryReader { geometry in
            unilateralWeightAndRepsContent(availableWidth: geometry.size.width)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }

    private var unilateralWeightAndRepsDurationFields: some View {
        GeometryReader { geometry in
            let durationWidth = UnilateralSetRowLayout.durationWidth(for: geometry.size.width)
            let weightRepsWidth = UnilateralSetRowLayout.weightRepsGroupWidth(for: geometry.size.width)

            HStack(spacing: UnilateralSetRowLayout.groupedColumnSpacing) {
                unilateralWeightAndRepsContent(availableWidth: weightRepsWidth)
                    .frame(width: weightRepsWidth, alignment: .leading)

                SetInputField(
                    value: $durationText,
                    placeholder: "MM:SS",
                    keyboardType: .numberPad,
                    isCompleted: set.completed,
                    controlHeight: UnilateralSetRowLayout.controlHeight,
                    isActiveOverride: focusedInput == .duration,
                    isCustomEntry: true,
                    onCustomTap: { activateCustomKeyboard(for: .duration) }
                )
                .frame(width: durationWidth)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }

    private func unilateralWeightAndRepsContent(availableWidth: CGFloat) -> some View {
        let weightWidth = UnilateralSetRowLayout.weightWidth(for: availableWidth)

        return HStack(spacing: UnilateralSetRowLayout.weightToRepsSpacing) {
            SetInputField(
                value: $weightText,
                placeholder: "0",
                keyboardType: .decimalPad,
                isCompleted: set.completed,
                controlHeight: UnilateralSetRowLayout.controlHeight,
                isActiveOverride: focusedInput == .weight,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: .weight) }
            )
            .frame(width: weightWidth)

            VStack(spacing: UnilateralSetRowLayout.verticalSpacing) {
                unilateralSideInput(
                    title: "L",
                    repsText: $leftRepsText,
                    focusedField: .leftReps,
                    placeholder: leftRepsPlaceholder
                )

                unilateralSideInput(
                    title: "R",
                    repsText: $rightRepsText,
                    focusedField: .rightReps,
                    placeholder: rightRepsPlaceholder
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func unilateralSideInput(
        title: String,
        repsText: Binding<String>,
        focusedField: SetRowInputField,
        placeholder: String
    ) -> some View {
        HStack(spacing: UnilateralSetRowLayout.sideLabelSpacing) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: UnilateralSetRowLayout.sideLabelWidth, alignment: .leading)

            SetInputField(
                value: repsText,
                placeholder: placeholder,
                keyboardType: .numberPad,
                isCompleted: set.completed,
                controlHeight: UnilateralSetRowLayout.controlHeight,
                isActiveOverride: focusedInput == focusedField,
                isCustomEntry: true,
                onCustomTap: { activateCustomKeyboard(for: focusedField) }
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func unilateralRIRControl(title: String, value: Binding<Double?>) -> some View {
        let currentOption = RIROption.from(doubleValue: value.wrappedValue)

        return Menu {
            ForEach(RIROption.allCases) { option in
                Button {
                    value.wrappedValue = option.doubleValue
                } label: {
                    HStack {
                        Text(option.displayName)
                        if option == currentOption {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)

                Text(currentOption.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(currentOption.color)
            }
            .frame(width: 36, height: UnilateralSetRowLayout.controlHeight)
            .background(rirBackground(for: currentOption))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(rirBorderColor(for: currentOption), lineWidth: 1)
            )
            .cornerRadius(7)
        }
    }
}

// MARK: - Previews

#Preview("Weight + Reps with RIR") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(spacing: 0) {
            SetRowView(
                set: WorkoutSet(
                    workoutId: UUID(),
                    exerciseId: UUID(),
                    setType: .working,
                    orderInWorkout: 1,
                    orderInExercise: 1,
                    completed: true,
                    cachedPRStatus: .current
                ),
                exercise: Exercise(
                    name: "Bench Press",
                    equipmentType: .barbell,
                    trackingType: .weightReps
                ),
                setNumber: 1,
                weightText: .constant("85"),
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
                    workoutId: UUID(),
                    exerciseId: UUID(),
                    setType: .working,
                    notes: "Felt strong today",
                    orderInWorkout: 2,
                    orderInExercise: 2,
                    completed: true
                ),
                exercise: Exercise(
                    name: "Bench Press",
                    equipmentType: .barbell,
                    trackingType: .weightReps
                ),
                setNumber: 2,
                weightText: .constant("80"),
                repsText: .constant("8"),
                leftRepsText: .constant(""),
                rightRepsText: .constant(""),
                durationText: .constant(""),
                distanceText: .constant(""),
                rirValue: .constant(2),
                leftRIRValue: .constant(nil),
                rightRIRValue: .constant(nil),
                onComplete: {},
                onDelete: {},
                onChangeSetType: { _ in },
                onEditNote: {}
            )
            SetRowView(
                set: WorkoutSet(
                    workoutId: UUID(),
                    exerciseId: UUID(),
                    setType: .working,
                    orderInWorkout: 3,
                    orderInExercise: 3
                ),
                exercise: Exercise(
                    name: "Bench Press",
                    equipmentType: .barbell,
                    trackingType: .weightReps
                ),
                setNumber: 3,
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
        }
        .background(Color.bgCard)
        .cornerRadius(12)
        .padding()
    }
}
