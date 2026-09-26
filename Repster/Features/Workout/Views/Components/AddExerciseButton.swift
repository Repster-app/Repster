// AddExerciseButton.swift
// The "+ Exercise" button in the active-workout and edit-workout header bars.

import SwiftUI

/// Labelled rather than a bare glyph, and shared by both headers so they cannot drift apart.
///
/// In an active workout this is the only way to add an exercise once the first one exists — the
/// empty state's "Add Exercises" button is gone by then — and a lone "+" sitting above a set list
/// reads just as easily as "add a set". Styled as a secondary next to the solid accent button
/// beside it, so the two are not mistaken for each other mid-set.
struct AddExerciseButton: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))

                Text("Exercise")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.accent)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.accentSoft)
            .cornerRadius(8)
        }
        .accessibilityLabel("Add exercise")
    }
}

#Preview {
    ZStack {
        Color.bg.ignoresSafeArea()
        AddExerciseButton(action: {})
    }
}
