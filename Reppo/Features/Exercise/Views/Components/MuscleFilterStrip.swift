// MuscleFilterStrip.swift
// Full-width wrapping pill layout for filtering exercises by muscle group.
// Spec: FR-004, design-system.md Section 6.1
// Feature: 007-exercise-list-and-detail WP02 T007

import SwiftUI

struct MuscleFilterStrip: View {
    let muscleGroups: [String]
    @Binding var selectedFilters: Set<String>

    var body: some View {
        WrappingHStack(spacing: 6, lineSpacing: 6) {
            ForEach(muscleGroups, id: \.self) { muscle in
                MuscleFilterPill(
                    title: muscle,
                    isSelected: selectedFilters.contains(muscle),
                    color: MuscleGroupColors.color(for: muscle),
                    action: { toggleFilter(muscle) }
                )
            }
        }
        .padding(.horizontal, 20)
    }

    private func toggleFilter(_ muscle: String) {
        if selectedFilters.contains(muscle) {
            selectedFilters.remove(muscle)
        } else {
            selectedFilters = [muscle]
        }
    }
}

// MARK: - Pill Sub-View

private struct MuscleFilterPill: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title.capitalized)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color.textTertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.accent : Color.bgCard)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Wrapping HStack Layout

/// A layout that arranges views horizontally, wrapping to the next line when needed.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangementResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return ArrangementResult(
            size: CGSize(width: maxX, height: y + lineHeight),
            positions: positions
        )
    }
}
