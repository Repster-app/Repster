// ImportStepView.swift
// Import prompt stub — CSV import coming in a future update.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T025

import SwiftUI

struct ImportStepView: View {
    let isSaving: Bool
    let onFinish: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accent)

                Text("Migrating from Another App?")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("CSV import is coming in a future update. For now, you can start fresh and add your exercises as you go.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Get Started") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSaving)

                Button("Skip") { onSkip() }
                    .foregroundStyle(Color.textSecondary)
                    .disabled(isSaving)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
