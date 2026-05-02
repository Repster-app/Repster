// BodyweightStepView.swift
// Optional bodyweight entry step during onboarding.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T025

import SwiftUI

struct BodyweightStepView: View {
    @Binding var bodyweightInput: String
    let unitPreference: UnitPreference
    let onNext: () -> Void
    let onSkip: () -> Void

    @FocusState private var isWeightFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("Your Bodyweight")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("Optional. Used for accurate tracking of bodyweight exercises.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack {
                TextField("Enter weight", text: $bodyweightInput)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 150)
                    .focused($isWeightFocused)
                Text(unitPreference == .metric ? "kg" : "lbs")
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 48)

            Spacer()

            VStack(spacing: 12) {
                Button("Continue") {
                    isWeightFocused = false
                    onNext()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Skip") {
                    isWeightFocused = false
                    onSkip()
                }
                .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
