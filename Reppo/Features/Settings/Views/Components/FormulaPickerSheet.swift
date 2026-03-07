// FormulaPickerSheet.swift
// Sheet for selecting the e1RM formula with descriptions.
// Spec: FR-010
// Feature: 010-settings-and-onboarding WP02 T009

import SwiftUI

struct FormulaPickerSheet: View {
    let currentFormula: E1RMFormula
    let onSelect: (E1RMFormula) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(E1RMFormula.allCases, id: \.self) { formula in
                    Button {
                        onSelect(formula)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formula.displayName)
                                    .foregroundStyle(Color.textPrimary)
                                Text(formula.description)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            if formula == currentFormula {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accent)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("e1RM Formula")
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
