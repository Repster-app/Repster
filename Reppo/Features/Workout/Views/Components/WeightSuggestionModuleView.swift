// WeightSuggestionModuleView.swift
// Section container for weight suggestion cards.
// Sits between SetTableView and ExerciseInfoSectionView in the Sets sub-tab.
// Follows the section pattern from ExerciseInfoSectionView.

import SwiftUI

struct WeightSuggestionModuleView: View {
    let data: WeightSuggestionData?
    let unitPreference: UnitPreference
    let isAdminModeEnabled: Bool
    let isLoading: Bool
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        if let data, !isLoading {
            if !data.rowStates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(showsRefreshButton: true)

                    WeightSuggestionCardView(
                        data: data,
                        unitPreference: unitPreference,
                        isAdminModeEnabled: isAdminModeEnabled
                    )
                }
            } else if let reason = data.unavailableReason, reason != .featureDisabled {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(showsRefreshButton: false)
                    unavailableCard(for: reason)
                }
            }
        }
    }

    private func sectionHeader(showsRefreshButton: Bool) -> some View {
        HStack(spacing: 8) {
            Text("SMART SUGGESTIONS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            if isRefreshing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.textSecondary)

                    Text("Updating...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if showsRefreshButton {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isRefreshing ? Color.textTertiary : Color.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh Smart Suggestions")
            }
        }
    }

    private func unavailableCard(for reason: SuggestionUnavailableReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Color.bg.opacity(0.55))
                    .cornerRadius(6)

                Text(reason.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Text(reason.message)
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.textSecondary)

                        Text("Updating...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onRefresh) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Retry")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(isRefreshing ? Color.textTertiary : Color.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.bg.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}
