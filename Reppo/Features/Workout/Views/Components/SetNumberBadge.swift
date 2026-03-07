// SetNumberBadge.swift
// Displays the set number or warmup indicator ("W")
// in the leftmost column of the set table.
// Spec: design-system.md Section 6.3 (Set Number Badge)
//
// Pure presentational component — no business logic or service dependencies.

import SwiftUI

/// Badge showing set number or warmup "W".
///
/// Appears in the "Set" column (42pt wide) of the set table grid.
/// - Default: numbered badge with `bgSubtle` background
/// - Warmup: italic "W" with no background
/// - Completed: numbered badge with green background
struct SetNumberBadge: View {

    /// The set number (1-indexed).
    let number: Int

    /// The type of set — warmup gets special "W" treatment.
    let setType: SetType

    /// Whether this set has been completed — tints the badge green.
    let isCompleted: Bool

    /// Whether this set has a note — shows an orange indicator dot.
    var hasNote: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if setType == .warmup {
                    warmupBadge
                } else {
                    numberedBadge
                }
            }
            .frame(width: 26, height: 26)

            // Note indicator dot
            if hasNote {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Color.bgCard, lineWidth: 1.5)
                    )
                    .offset(x: 2, y: -2)
            }
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - Badge Variants

    /// Italic "W" with no background for warmup sets.
    private var warmupBadge: some View {
        Text("W")
            .font(.system(size: 13, weight: .semibold))
            .italic()
            .foregroundColor(.textTertiary)
    }

    /// Numbered badge — green background when completed, subtle background otherwise.
    private var numberedBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isCompleted ? Color.success : Color.bgSubtle)
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isCompleted ? .white : .textTertiary)
        }
    }
}

// MARK: - Previews

#Preview("Default (Set 1)") {
    ZStack {
        Color.bg.ignoresSafeArea()
        SetNumberBadge(number: 1, setType: .working, isCompleted: false)
            .padding()
    }
}

#Preview("Warmup") {
    ZStack {
        Color.bg.ignoresSafeArea()
        SetNumberBadge(number: 1, setType: .warmup, isCompleted: false)
            .padding()
    }
}

#Preview("Completed") {
    ZStack {
        Color.bg.ignoresSafeArea()
        SetNumberBadge(number: 3, setType: .working, isCompleted: true)
            .padding()
    }
}

#Preview("All States") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SetNumberBadge(number: 1, setType: .working, isCompleted: false)
                SetNumberBadge(number: 2, setType: .working, isCompleted: false)
                SetNumberBadge(number: 3, setType: .working, isCompleted: false)
            }
            HStack(spacing: 12) {
                SetNumberBadge(number: 1, setType: .warmup, isCompleted: false)
                SetNumberBadge(number: 2, setType: .warmup, isCompleted: false)
            }
            HStack(spacing: 12) {
                SetNumberBadge(number: 1, setType: .working, isCompleted: true)
                SetNumberBadge(number: 2, setType: .working, isCompleted: true)
            }
        }
        .padding()
    }
}
