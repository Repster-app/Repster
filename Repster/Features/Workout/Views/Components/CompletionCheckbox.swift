// CompletionCheckbox.swift
// Tap target for completing a set. Visual checkbox with expanded 44x44pt tap area.
// Spec: design-system.md Section 6.3 (Completion Checkbox)
// Constitution: All tap targets >= 44x44pt for gym-proof interaction.
//
// Pure presentational component — no business logic or service dependencies.

import SwiftUI

/// Completion checkbox with 44x44pt tap target for gym-friendly interaction.
///
/// Visual size is 26x26pt, but the tappable area extends to 44x44pt
/// per the constitution's minimum tap target requirement.
struct CompletionCheckbox: View {

    /// Whether the checkbox is currently checked (set completed).
    let isChecked: Bool

    /// Callback fired when the user taps the checkbox.
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                if isChecked {
                    checkedContent
                } else {
                    uncheckedContent
                }
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Checkbox States

    /// Blue filled square with white checkmark.
    private var checkedContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accent)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
    }

    /// Empty square with tertiary border.
    private var uncheckedContent: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.textTertiary, lineWidth: 2)
    }
}

// MARK: - Previews

#Preview("Unchecked") {
    ZStack {
        Color.bg.ignoresSafeArea()
        CompletionCheckbox(isChecked: false, onToggle: {})
            .padding()
    }
}

#Preview("Checked") {
    ZStack {
        Color.bg.ignoresSafeArea()
        CompletionCheckbox(isChecked: true, onToggle: {})
            .padding()
    }
}

#Preview("Both States") {
    ZStack {
        Color.bg.ignoresSafeArea()
        HStack(spacing: 20) {
            CompletionCheckbox(isChecked: false, onToggle: {})
            CompletionCheckbox(isChecked: true, onToggle: {})
        }
        .padding()
    }
}
