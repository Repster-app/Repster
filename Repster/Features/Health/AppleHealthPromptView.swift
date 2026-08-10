// AppleHealthPromptView.swift
// Repster's own ask, shown before HealthKit's.
//
// iOS shows its permission sheet once per install. Anything that offers the integration
// on its own initiative therefore has to explain itself first and reach HealthKit only
// when the user says yes — a "Not now" here costs nothing and stays recoverable.
//
// Built to drop into any container: the onboarding step uses it as a full page, and a
// What's New sheet can present it as-is.

import SwiftUI

struct AppleHealthPromptView: View {
    /// Owned by the host, so presenting the prompt twice can't lose in-flight state.
    let model: AppleHealthConnectionModel

    /// Called after authorization succeeds. Onboarding advances; a sheet would dismiss.
    let onConnected: () -> Void
    /// Called when the user taps "Not now".
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accent)

                        Text("Apple Health")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textPrimary)

                        Text("Send your finished workouts to Health, so they count towards your rings and show up alongside everything else you track.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        promptPoint(
                            icon: "arrow.up.forward.square",
                            text: "Repster only writes. It never reads your health data."
                        )
                        promptPoint(
                            icon: "checkmark.shield",
                            text: "It can only touch the workouts it wrote itself."
                        )
                        promptPoint(
                            icon: "switch.2",
                            text: "Turn it off any time in Settings → Body."
                        )
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32)
                }
                .padding(.top, 24)
                .padding(.bottom, 12)
            }

            VStack(spacing: 12) {
                Button("Connect Apple Health") {
                    Task {
                        if await model.connect() { onConnected() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isConnecting)

                Button("Not now") {
                    model.decline()
                    onDecline()
                }
                .foregroundStyle(Color.textSecondary)
                .disabled(model.isConnecting)
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 48)
            .background(Color.bg)
        }
        // No `onAppear` reporting here on purpose: inside a paged TabView that fires for
        // neighbouring pages too. The host calls `model.promptShown()` when the prompt is
        // genuinely on screen.
        //
        // A denial isn't an error worth an alert here — the user just chose. It's shown
        // because it's the one place to say where the decision can be reversed.
        .alert("Apple Health", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { onDecline() }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private func promptPoint(icon: String, text: String) -> some View {
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
