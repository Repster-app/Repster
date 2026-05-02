// StartWorkoutSheet.swift
// Bottom sheet with workout start options: Empty, Copy Previous, Templates.
// Variant A design: card-style options with icons.
// Spec: 013-home-screen

import SwiftUI

struct StartWorkoutSheet: View {
    let accessMessage: String?
    let onStartEmpty: (WorkoutStartOptions) -> Void
    let onCopyPrevious: (WorkoutStartOptions) -> Void
    let onTemplates: (WorkoutStartOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var countTowardProgressionHistory = true
    @State private var showProgressionInfo = false

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Start Workout")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 12)
                .padding(.bottom, 4)

            Text("How do you want to begin?")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 14)

            if let accessMessage, !accessMessage.isEmpty {
                Text(accessMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
            }

            // Primary: Empty Workout
            Button {
                dismiss()
                onStartEmpty(startOptions)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accent)
                        .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Empty Workout")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Start fresh and add exercises as you go")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.accentSoft)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accent.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            // Divider with "or pre-fill from"
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)
                Text("OR PRE-FILL FROM")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .kerning(0.5)
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            // Copy Previous
            Button {
                dismiss()
                onCopyPrevious(startOptions)
            } label: {
                optionRow(
                    icon: "doc.on.doc",
                    title: "Copy Previous",
                    description: "Repeat a past workout with the same exercises"
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            // Templates
            Button {
                onTemplates(startOptions)
                dismiss()
            } label: {
                optionRow(
                    icon: "doc.text",
                    title: "Use Template",
                    description: "Start from a saved workout routine"
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                Text("Count toward PRs")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Button { showProgressionInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Toggle("", isOn: $countTowardProgressionHistory)
                    .labelsHidden()
                    .tint(Color.accent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgCard.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgCard)
        .preferredColorScheme(.dark)
        .alert("Count toward PRs", isPresented: $showProgressionInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Turn this off for hotel, travel, or mismatched-equipment sessions. Live Smart Suggestions still work during the workout.")
        }
    }

    private var startOptions: WorkoutStartOptions {
        WorkoutStartOptions(countTowardProgressionHistory: countTowardProgressionHistory)
    }

    // MARK: - Option Row

    private func optionRow(
        icon: String,
        title: String,
        description: String,
        badge: String? = nil
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, height: 44)
                .background(Color.bgSubtle)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                    .kerning(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.bgSubtle)
                    .cornerRadius(6)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bg)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border, lineWidth: 1)
        )
    }
}
