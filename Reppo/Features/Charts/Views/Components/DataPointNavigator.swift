// DataPointNavigator.swift
// Reusable ← → arrow navigation with value/date display.
// Used by Workouts and Exercises tabs for data point browsing.
// Feature: 016-charts-tab-v2 WP05 (T109)

import SwiftUI

struct DataPointNavigator: View {
    let value: String?
    let subtitle: String?
    /// Optional detail line (e.g. "85 kg x 8 reps") shown between value and subtitle.
    var detail: String? = nil
    let promptText: String
    let hasPrevious: Bool
    let hasNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgSubtle)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .opacity(hasPrevious ? 1 : 0.3)
            .disabled(!hasPrevious)

            Spacer()

            if let value {
                VStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                Text(promptText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.bgSubtle)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .opacity(hasNext ? 1 : 0.3)
            .disabled(!hasNext)
        }
        .padding(.top, 12)
    }
}
