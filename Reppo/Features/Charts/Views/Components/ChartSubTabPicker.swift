// ChartSubTabPicker.swift
// Horizontal pill bar for switching between Breakdown/Workouts/Exercises sub-tabs.
// Feature: 016-charts-tab-v2 WP05 (T106)

import SwiftUI

struct ChartSubTabPicker: View {
    @Binding var selectedTab: ChartsTabViewModel.SubTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartsTabViewModel.SubTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? .white : Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selectedTab == tab ? Color.accent : Color.bgCard)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
