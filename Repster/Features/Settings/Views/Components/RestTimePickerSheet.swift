// RestTimePickerSheet.swift
// Sheet for selecting default rest time between sets.
// Spec: FR-010
// Feature: 010-settings-and-onboarding WP02 T010

import SwiftUI

struct RestTimePickerSheet: View {
    let currentSeconds: Int?
    var title: String = "Default Rest Time"
    var noneOptionLabel: String? = nil
    let onSelect: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    private let options: [Int] = [30, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            List {
                if let noneOptionLabel {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        optionRow(title: noneOptionLabel, isSelected: currentSeconds == nil)
                    }
                }

                ForEach(options, id: \.self) { seconds in
                    Button {
                        onSelect(seconds)
                        dismiss()
                    } label: {
                        optionRow(title: displayName(for: seconds), isSelected: seconds == currentSeconds)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func displayName(for seconds: Int) -> String {
        return UnitConversion.formatDuration(seconds)
    }

    private func optionRow(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accent)
            }
        }
        .contentShape(Rectangle())
    }
}
