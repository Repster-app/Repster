// SortOptionMenu.swift
// Sort picker with 3 options: A-Z, Most Recent, Most Used.
// Spec: FR-004, plan.md Decision 6
// Feature: 007-exercise-list-and-detail WP02 T008

import SwiftUI

struct SortOptionMenu: View {
    @Binding var sortOrder: ExerciseListSortOrder

    var body: some View {
        Menu {
            ForEach(ExerciseListSortOrder.allCases, id: \.self) { order in
                Button {
                    sortOrder = order
                } label: {
                    HStack {
                        Text(order.rawValue)
                        if sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text(sortOrder.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.bgCard)
            .cornerRadius(8)
        }
    }
}
