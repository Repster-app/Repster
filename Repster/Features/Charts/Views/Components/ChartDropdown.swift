// ChartDropdown.swift
// Reusable dropdown picker for chart option selection.
// Uses SwiftUI Menu for native dropdown behavior.
// Feature: 016-charts-tab-v2 WP05 (T107)

import SwiftUI

struct ChartDropdown<T: Identifiable & Hashable>: View {
    let title: String?
    let options: [T]
    @Binding var selected: T
    let labelFor: (T) -> String

    init(title: String? = nil, options: [T], selected: Binding<T>, labelFor: @escaping (T) -> String) {
        self.title = title
        self.options = options
        self._selected = selected
        self.labelFor = labelFor
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selected = option
                } label: {
                    HStack {
                        Text(labelFor(option))
                        if option.id == selected.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(labelFor(selected))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.border, lineWidth: 1)
            )
            .cornerRadius(10)
        }
    }
}
