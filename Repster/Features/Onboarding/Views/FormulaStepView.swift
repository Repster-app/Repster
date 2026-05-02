// FormulaStepView.swift
// e1RM formula selection step with plain-English descriptions.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T024

import SwiftUI

struct FormulaStepView: View {
    @Binding var selectedFormula: E1RMFormula
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("e1RM Formula")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("Estimates your one-rep max from your working sets. You can change this later.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                ForEach(E1RMFormula.allCases, id: \.self) { formula in
                    formulaOption(formula)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button("Continue") { onNext() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
    }

    private func formulaOption(_ formula: E1RMFormula) -> some View {
        Button {
            selectedFormula = formula
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formula.displayName)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text(formula.description)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: selectedFormula == formula ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedFormula == formula ? Color.accent : Color.textSecondary)
            }
            .padding()
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedFormula == formula ? Color.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
