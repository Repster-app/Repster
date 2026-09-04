// ExtrasStepView.swift
// The final onboarding step: a completion screen offering two optional extras.
//
// This replaces the old import prompt, and the difference is the hierarchy rather than the
// content. That screen asked a question with no obvious way out and five people stopped there
// permanently. Here the way out is the loudest thing on the screen and both extras are visibly
// optional. See ONBOARDING_REDESIGN_SCOPING.md §4.5.

import SwiftUI

struct ExtrasStepView: View {
    /// What was set up on step 2, for the confirmation line. Nil when "build my own" was chosen.
    let selectedProgram: ProgramSeedDTO?
    let isSaving: Bool
    let onOpenImport: () -> Void
    let onOpenWalkthrough: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Want a head start?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("Bring your history in, or take the tour. Both optional — you can start training now.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 18)

            confirmation
                .padding(.bottom, 20)

            VStack(spacing: 10) {
                optionRow(
                    icon: "square.and.arrow.down",
                    title: "Bring your history in",
                    detail: "From FitNotes, Strong or Hevy",
                    action: onOpenImport
                )

                optionRow(
                    icon: "questionmark.circle",
                    title: "See how it works",
                    detail: "Six quick pages, nothing to answer",
                    action: onOpenWalkthrough
                )
            }

            Spacer()

            Button(action: onFinish) {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Start training")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Confirmation

    /// Names what step 2 set up, so the screen opens by confirming progress rather than by
    /// asking for something else.
    private var confirmation: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.success)

            Text(confirmationText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.success.opacity(0.08))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.success.opacity(0.20), lineWidth: 1)
        )
    }

    private var confirmationText: String {
        guard let program = selectedProgram else {
            return "Empty library ready — add sessions as you go"
        }
        return "\(program.name) ready · \(program.sessionCount) sessions saved"
    }

    // MARK: - Option rows

    private func optionRow(
        icon: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgSubtle)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
