// UnitPickerSheet.swift
// Sheet for selecting between metric and imperial units.
// Spec: FR-010
// Feature: 010-settings-and-onboarding WP02 T008

import SwiftUI

struct UnitPickerSheet: View {
    let currentUnit: UnitPreference
    let onSelect: (UnitPreference) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(UnitPreference.allCases, id: \.self) { unit in
                    Button {
                        onSelect(unit)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unit == .metric ? "Metric" : "Imperial")
                                    .foregroundStyle(Color.textPrimary)
                                Text(unit == .metric ? "Kilograms (kg)" : "Pounds (lbs)")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            if unit == currentUnit {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accent)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Units")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
