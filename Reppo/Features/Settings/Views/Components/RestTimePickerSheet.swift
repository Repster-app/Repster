// RestTimePickerSheet.swift
// Sheet for selecting default rest time between sets.
// Spec: FR-010
// Feature: 010-settings-and-onboarding WP02 T010

import SwiftUI

struct RestTimePickerSheet: View {
    let currentSeconds: Int?
    let onSelect: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    private let options: [Int?] = [nil, 30, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.self) { seconds in
                    Button {
                        onSelect(seconds)
                        dismiss()
                    } label: {
                        HStack {
                            Text(displayName(for: seconds))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if seconds == currentSeconds {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accent)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Default Rest Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func displayName(for seconds: Int?) -> String {
        guard let seconds else { return "Not Set" }
        return UnitConversion.formatDuration(seconds)
    }
}
