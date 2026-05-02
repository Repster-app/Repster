// UnitsStepView.swift
// Unit selection step — metric or imperial.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T023

import SwiftUI

struct UnitsStepView: View {
    @Binding var selectedUnit: UnitPreference
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("Choose Your Units")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("You can change this anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 12) {
                unitOption(.metric, title: "Metric", subtitle: "Kilograms (kg)")
                unitOption(.imperial, title: "Imperial", subtitle: "Pounds (lbs)")
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

    private func unitOption(_ unit: UnitPreference, title: String, subtitle: String) -> some View {
        Button {
            selectedUnit = unit
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: selectedUnit == unit ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedUnit == unit ? Color.accent : Color.textSecondary)
            }
            .padding()
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedUnit == unit ? Color.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
