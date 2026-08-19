// RestAlarmPromptView.swift
// Repster's own ask, shown before the system's notification prompt.
// Scoping: REST_TIMER_ALARM_SCOPING.md §D2
//
// iOS grants exactly one permission prompt per install. This used to be spent from
// `RepsterApp.init()` — at cold start, before onboarding had drawn a screen — so a reflex
// "Don't Allow" from someone who had not seen the app yet permanently broke the rest alarm,
// with nothing in the app ever noticing or mentioning it.
//
// So this asks first, in context: the first time a rest timer actually starts, when a countdown
// has just appeared on screen and the reason explains itself. "Not now" never reaches iOS, which
// leaves the real prompt unspent and recoverable from Settings later.

import SwiftUI

struct RestAlarmPromptView: View {

    /// Called when the user opts in. The host awaits the system prompt and dismisses.
    let onEnable: () -> Void
    /// Called on "Not now". iOS is never touched.
    let onDecline: () -> Void

    /// Set while the system sheet is up, so the button can't be tapped twice.
    var isRequesting: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)

            Image(systemName: "bell.badge")
                .font(.system(size: 44))
                .foregroundStyle(Color.accent)

            VStack(spacing: 10) {
                Text("Know when rest is over")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("Repster can tell you the moment your rest ends — even if you lock your phone or leave this screen.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 14) {
                point("iphone.slash", "Works with your phone locked or in your pocket")
                point("square.on.square", "Works while you're checking history or another app")
                point("slider.horizontal.3", "Turn it off any time in Settings → Workout Preferences")
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button(action: onEnable) {
                    Text(isRequesting ? "Asking…" : "Turn on alerts")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accent)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)

                Button(action: onDecline) {
                    Text("Not now")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color.bg)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accent)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    RestAlarmPromptView(onEnable: {}, onDecline: {})
}
