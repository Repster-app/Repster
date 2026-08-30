// UnitsBodyweightStepView.swift
// Units and optional bodyweight, on one screen.
//
// These were two steps. They belong together: a bodyweight figure means nothing without a
// unit, so the split forced the second screen to silently assume an answer given on the
// first. Here the field's suffix tracks the selection, and there is nothing to misread.
//
// The unit selection is preseeded from the device locale, so for most people this screen
// is a confirmation rather than a decision.

import SwiftUI

struct UnitsBodyweightStepView: View {
    @Binding var selectedUnit: UnitPreference
    @Binding var bodyweightInput: String
    let onNext: () -> Void

    @FocusState private var isWeightFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Units and bodyweight")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("You can change both anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 24)

            VStack(spacing: 10) {
                unitOption(.metric, title: "Metric", subtitle: "Kilograms (kg)")
                unitOption(.imperial, title: "Imperial", subtitle: "Pounds (lb)")
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 8) {
                Text("BODYWEIGHT · OPTIONAL")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Color.textTertiary)

                HStack(spacing: 10) {
                    TextField("Enter weight", text: $bodyweightInput)
                        .keyboardType(.decimalPad)
                        .focused($isWeightFocused)
                        .foregroundStyle(Color.textPrimary)

                    Text(UnitConversion.weightUnitLabel(for: selectedUnit))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(12)
                .background(Color.bgInput, in: RoundedRectangle(cornerRadius: 11))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Color.border, lineWidth: 1)
                )
                // Bodyweight is a health figure and the policy promises it is masked
                // wherever it appears.
                .replayMasked()

                Text("Used for accurate tracking of bodyweight exercises.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.top, 24)

            Spacer(minLength: 16)

            // No Skip button: leaving the weight blank is the skip, and the unit always
            // holds a value.
            Button("Continue") {
                isWeightFocused = false
                onNext()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { isWeightFocused = false }
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
