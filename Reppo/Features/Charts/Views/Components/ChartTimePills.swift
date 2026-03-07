// ChartTimePills.swift
// Reusable horizontal time range pill bar.
// Feature: 016-charts-tab-v2 WP05 (T108)

import SwiftUI

struct ChartTimePills<T: Identifiable & Hashable>: View {
    let options: [T]
    @Binding var selected: T
    let labelFor: (T) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selected = option
                    }
                } label: {
                    Text(labelFor(option))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(option.id == selected.id ? .white : Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(option.id == selected.id ? Color.accent : Color.bgCard)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
