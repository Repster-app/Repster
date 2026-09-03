// SetNumberBadge.swift
// Displays the set number or warmup indicator ("W1", "W2", etc.)
// in the leftmost column of the set table.
// Spec: design-system.md Section 6.3 (Set Number Badge)
//
// Pure presentational component — no business logic or service dependencies.

import SwiftUI

/// How one set is labelled in the set-number column, and the number it carries.
///
/// Warm-ups, drop sets and working sets each number within their own series, so a drop set
/// never consumes a working-set number. `1, 2, D1, D2, 3` reads as "three working sets, with
/// two drops taken after the second" — which is what a drop set is.
///
/// This is the single source of truth for set numbering. The live set table and both history
/// renderers all go through ``assign(for:)``; before it existed they numbered independently and
/// disagreed, with history counting warm-ups into the working-set numbers.
///
/// Known limitation: two separate drop sequences in one exercise number D1–D4 continuously
/// rather than restarting, because nothing yet records which working set a drop belongs to.
/// Suffixed numbering (`3a`, `3b`) is the upgrade once that grouping exists.
enum SetBadgeLabel: Equatable {
    case warmup(Int)
    case dropset(Int)
    case working(Int)

    /// The text drawn in the badge — "W1", "D1", "3".
    var text: String {
        switch self {
        case let .warmup(number):  return "W\(number)"
        case let .dropset(number): return "D\(number)"
        case let .working(number): return "\(number)"
        }
    }

    /// The number within this label's own series.
    var number: Int {
        switch self {
        case let .warmup(number), let .dropset(number), let .working(number):
            return number
        }
    }

    /// Label every set in an exercise, in display order.
    static func assign(for setTypes: [SetType]) -> [SetBadgeLabel] {
        var warmups = 0
        var dropsets = 0
        var working = 0
        return setTypes.map { type in
            switch type {
            case .warmup:
                warmups += 1
                return .warmup(warmups)
            case .dropset:
                dropsets += 1
                return .dropset(dropsets)
            default:
                working += 1
                return .working(working)
            }
        }
    }
}

/// Badge showing set number or warmup "W1", "W2", etc.
///
/// Appears in the "Set" column (42pt wide) of the set table grid.
/// - Default: numbered badge with `bgSubtle` background
/// - Warmup: italic "W1", "W2" with no background
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

    /// Whether this set is currently active for editing.
    var isEditing: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch setType {
                case .warmup:
                    letterBadge(SetBadgeLabel.warmup(number).text, tint: .textTertiary)
                case .dropset:
                    letterBadge(SetBadgeLabel.dropset(number).text, tint: .chart5)
                default:
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

    /// Italic "W1" / "D1" with no background — the annotated set types.
    ///
    /// `tint` is what separates them at a glance: warm-ups stay in the quiet tertiary grey they
    /// have always used, drop sets take `chart5` so they read as a deliberate technique rather
    /// than a set someone went light on.
    private func letterBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .italic()
            .foregroundColor(isEditing ? .textPrimary : tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(isEditing ? Color.accent.opacity(0.08) : Color.clear)
            .clipShape(Capsule())
    }

    /// Numbered badge — green background when completed, subtle background otherwise.
    private var numberedBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(numberedBadgeBackground)
            RoundedRectangle(cornerRadius: 8)
                .stroke(numberedBadgeBorder, lineWidth: isEditing && !isCompleted ? 1 : 0)
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(numberedBadgeForeground)
        }
    }

    private var numberedBadgeBackground: Color {
        if isCompleted {
            return .success
        }
        if isEditing {
            return Color.accent.opacity(0.09)
        }
        return .bgSubtle
    }

    private var numberedBadgeBorder: Color {
        if isCompleted {
            return .clear
        }
        return Color.accent.opacity(0.18)
    }

    private var numberedBadgeForeground: Color {
        if isCompleted {
            return .white
        }
        if isEditing {
            return .textPrimary
        }
        return .textTertiary
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
