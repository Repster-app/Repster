// SetInputField.swift
// Reusable numeric input field for set table values (weight, reps, duration, distance).
// Spec: design-system.md Section 6.3 (Input Field), Section 10 (SetInputStyle)
//
// Pure presentational component — no business logic or service dependencies.

import SwiftUI

/// Focus targets for fields inside a set row.
enum SetRowInputField: Hashable {
    case weight
    case reps
    case leftReps
    case rightReps
    case duration
    case distance
}

/// Numeric input field with three visual states: default, focused, and completed.
///
/// Used in every set row for weight, reps, duration, and distance values.
/// Accepts a string binding (caller converts to/from numeric types).
struct SetInputField: View {

    /// The text value displayed and edited in the field.
    @Binding var value: String

    /// Placeholder text shown when value is empty (e.g., "0", "kg").
    let placeholder: String

    /// Keyboard type for numeric input (.decimalPad for weight, .numberPad for reps).
    let keyboardType: UIKeyboardType

    /// Whether this set has been completed — triggers green completed state.
    let isCompleted: Bool

    /// Optional explicit control height used for compact custom layouts.
    var controlHeight: CGFloat? = nil

    /// Optional external focus binding for row-level keyboard navigation.
    var externalFocus: FocusState<SetRowInputField?>.Binding? = nil

    /// Which field this input represents when external focus is used.
    var focusField: SetRowInputField? = nil

    /// Optional explicit active-state override (used by custom keyboard mode).
    var isActiveOverride: Bool? = nil

    /// Whether to use tappable custom-entry mode instead of the native iOS keyboard.
    var isCustomEntry: Bool = false

    /// Tap handler used in custom-entry mode.
    var onCustomTap: (() -> Void)? = nil

    /// Internal focus state for tracking keyboard focus.
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isCustomEntry, let onCustomTap {
                customEntryButton(onTap: onCustomTap)
            } else {
                if let externalFocus, let focusField {
                    baseTextField
                        .focused(externalFocus, equals: focusField)
                } else {
                    baseTextField
                        .focused($isFocused)
                }
            }
        }
    }

    // MARK: - Computed Colors

    private var backgroundColor: Color {
        if isCompleted {
            return Color.success.opacity(0.06)
        } else if isCurrentlyFocused {
            return Color.accent.opacity(0.06)
        } else {
            return Color.bgInput
        }
    }

    private var borderColor: Color {
        if isCompleted {
            return Color.success.opacity(0.15)
        } else if isCurrentlyFocused {
            return Color.accent
        } else {
            return Color.border
        }
    }

    private var isCurrentlyFocused: Bool {
        if let isActiveOverride {
            return isActiveOverride
        }
        if let externalFocus, let focusField {
            return externalFocus.wrappedValue == focusField
        }
        return isFocused
    }

    private var baseTextField: some View {
        Group {
            if let controlHeight {
                TextField(placeholder, text: $value)
                    .keyboardType(keyboardType)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .frame(height: controlHeight)
            } else {
                TextField(placeholder, text: $value)
                    .keyboardType(keyboardType)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
            }
        }
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private func customEntryButton(onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Group {
                if let controlHeight {
                    Text(value.isEmpty ? placeholder : value)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(value.isEmpty ? .textTertiary : .textPrimary)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .frame(height: controlHeight)
                } else {
                    Text(value.isEmpty ? placeholder : value)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(value.isEmpty ? .textTertiary : .textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                }
            }
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Default") {
    ZStack {
        Color.bg.ignoresSafeArea()
        SetInputField(
            value: .constant("80"),
            placeholder: "0",
            keyboardType: .decimalPad,
            isCompleted: false
        )
        .frame(width: 100)
        .padding()
    }
}

#Preview("Completed") {
    ZStack {
        Color.bg.ignoresSafeArea()
        SetInputField(
            value: .constant("80"),
            placeholder: "0",
            keyboardType: .decimalPad,
            isCompleted: true
        )
        .frame(width: 100)
        .padding()
    }
}

#Preview("Empty Placeholder") {
    ZStack {
        Color.bg.ignoresSafeArea()
        SetInputField(
            value: .constant(""),
            placeholder: "0",
            keyboardType: .numberPad,
            isCompleted: false
        )
        .frame(width: 100)
        .padding()
    }
}

#Preview("All States") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(spacing: 16) {
            SetInputField(
                value: .constant("80"),
                placeholder: "0",
                keyboardType: .decimalPad,
                isCompleted: false
            )
            SetInputField(
                value: .constant("80"),
                placeholder: "0",
                keyboardType: .decimalPad,
                isCompleted: true
            )
            SetInputField(
                value: .constant(""),
                placeholder: "0",
                keyboardType: .numberPad,
                isCompleted: false
            )
        }
        .frame(width: 100)
        .padding()
    }
}
