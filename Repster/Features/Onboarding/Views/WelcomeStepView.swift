// WelcomeStepView.swift
// First onboarding screen with app welcome and "Get Started" button.
// Spec: FR-010, User Story 5
// Feature: 010-settings-and-onboarding WP04 T022

import SwiftUI

struct WelcomeStepView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image("RepsterMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Repster learns what you can lift")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // The canonical value proposition. These three lines are one asset with three
            // surfaces — any change here must be mirrored on the App Store listing and the
            // paywall, so the promise that sells the app is the promise onboarding makes.
            // See ONBOARDING_REDESIGN_SCOPING.md §1.
            VStack(spacing: 10) {
                valueBullet("chart.line.uptrend.xyaxis", "Estimated 1RM from your first set")
                valueBullet("clock.arrow.circlepath", "Rest and fatigue tracked per muscle")
                valueBullet("chart.bar.fill", "Next-session targets, not just a log")
            }
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onNext()
                } label: {
                    Text("Get started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("A minute of setup, then you're training")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    /// One value-proposition line. Sized so all three fit on a single line at the default
    /// dynamic-type size — a wrapped line breaks the centred stack, so keep replacements
    /// to roughly the length of the ones already here.
    private func valueBullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 26, height: 26)
                .background(Color.accentSoft)
                .cornerRadius(8)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
