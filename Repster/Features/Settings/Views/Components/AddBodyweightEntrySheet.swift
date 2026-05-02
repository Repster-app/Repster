// AddBodyweightEntrySheet.swift
// Sheet for entering a new bodyweight measurement with weight and date.
// Spec: FR-008, User Story 3
// Feature: 010-settings-and-onboarding WP03 T017

import SwiftUI

struct AddBodyweightEntrySheet: View {
    let unitPreference: UnitPreference
    let onSave: (Double, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var date = Date()

    private var parsedWeight: Double? {
        guard let value = UnitConversion.parseDecimal(weightText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text(unitPreference == .metric ? "kg" : "lbs")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Add Bodyweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let inputWeight = parsedWeight else { return }
                        let weightKg = unitPreference == .imperial
                            ? UnitConversion.lbsToKg(inputWeight)
                            : inputWeight
                        onSave(weightKg, date)
                        dismiss()
                    }
                    .disabled(parsedWeight == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
