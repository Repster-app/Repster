// WelcomeStepView.swift
// First onboarding screen with app welcome and "Get Started" button.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T022

import SwiftUI

struct WelcomeStepView: View {
    @Binding var setupMode: OnboardingSetupMode
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "dumbbell.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accent)

            VStack(spacing: 12) {
                Text("Welcome to Reppo")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("Track your workouts, log your progress, and beat your personal records.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    setupMode = .quick
                    onNext()
                } label: {
                    Text("Quick Setup")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    setupMode = .advanced
                    onNext()
                } label: {
                    Text("Advanced Setup")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
