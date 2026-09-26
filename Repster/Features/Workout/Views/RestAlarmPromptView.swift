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
//
// It's one question with two answers, so — like its twin, `AppleHealthPromptView` — the sheet
// sizes itself to its content. It used to sit on a fixed `.medium` detent that the content
// outgrew: the subtitle was the only flexible view in the stack, so it absorbed the overflow
// and truncated mid-sentence, and both buttons were clipped off the bottom.

import SwiftUI

struct RestAlarmPromptView: View {

    /// Called when the user opts in. The host awaits the system prompt and dismisses.
    let onEnable: () -> Void
    /// Called on "Not now". iOS is never touched.
    let onDecline: () -> Void

    /// Set while the system sheet is up, so the button can't be tapped twice.
    var isRequesting: Bool = false

    @State private var measuredHeight: CGFloat = 480

    private var detentHeight: CGFloat {
        promptDetentHeight(for: measuredHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accent)

                        Text("Know when rest is over")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Repster can tell you the moment your rest ends.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        point("iphone.slash", "Works with your phone locked or in your pocket")
                        point("square.on.square", "Works while you're checking history or another app")
                        point("slider.horizontal.3", "Turn it off any time in Settings → Workout Preferences")
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bg, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 32)
                }
                .padding(.top, 24)
                .padding(.bottom, 12)
                .measuringHeight()
            }
            .scrollBounceBehavior(.basedOnSize)

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
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .measuringHeight()
        }
        .onPreferenceChange(PromptHeightKey.self) { measuredHeight = $0 }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgCard)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Color.accent)
                .frame(width: 20)

            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    Color.bg
        .sheet(isPresented: .constant(true)) {
            RestAlarmPromptView(onEnable: {}, onDecline: {})
        }
}
