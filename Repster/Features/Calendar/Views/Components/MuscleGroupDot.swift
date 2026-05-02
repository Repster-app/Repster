// MuscleGroupDot.swift
// Small colored circle indicator for calendar day cells.

import SwiftUI

struct MuscleGroupDot: View {
    let muscleGroup: String

    var body: some View {
        Circle()
            .fill(MuscleGroupColors.color(for: muscleGroup))
            .frame(width: 6, height: 6)
    }
}
