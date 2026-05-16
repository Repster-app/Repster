// SmartSuggestionsOnboardingStepView.swift
// Smart Suggestions defaults step during onboarding.

import SwiftUI

struct SmartSuggestionsOnboardingStepView: View {
    @Binding var defaultTargetReps: Int
    @Binding var defaultTargetRIR: Int
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accent)

                        Text("Smart Suggestions")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textPrimary)

                        Text("Repster can suggest useful working weights from your history. These defaults are used when a set does not already have a target rep count or reps in reserve.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    VStack(spacing: 0) {
                        Stepper(value: $defaultTargetReps, in: 1...30) {
                            HStack {
                                Text("Default Suggested Reps")
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer()
                                Text("\(defaultTargetReps)")
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding()

                        Divider()
                            .padding(.leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reps in Reserve")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("How many good reps you think you could still do after a set. Lower is harder; higher leaves more room.")
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top])

                        HStack {
                            Text("Default Suggested RIR")
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Picker("", selection: $defaultTargetRIR) {
                                ForEach(0...5, id: \.self) { rir in
                                    Text(rir == 5 ? "5+" : "\(rir)").tag(rir)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding([.horizontal, .bottom])
                    }
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32)
                }
                .padding(.top, 24)
                .padding(.bottom, 12)
            }

            Button("Continue") { onNext() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 48)
                .background(Color.bg)
        }
    }
}
