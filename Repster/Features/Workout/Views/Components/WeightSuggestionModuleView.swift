// WeightSuggestionModuleView.swift
// Section container for weight suggestion strips.
// Sits between SetTableView and ExerciseInfoSectionView in the Sets sub-tab.
//
// Renders the section header (`SMART SUGGESTIONS` + count summary + refresh
// button) and forwards data to `WeightSuggestionCardView`, which is now a
// flat stack of per-set strips rather than a card.

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
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(
                        countSummary: availabilitySummary(for: data),
                        showsRefreshButton: true
                    )

                    WeightSuggestionCardView(
                        data: data,
                        unitPreference: unitPreference,
                        isAdminModeEnabled: isAdminModeEnabled
                    )
                }
            } else if let reason = data.unavailableReason, reason != .featureDisabled {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(countSummary: nil, showsRefreshButton: false)
                    unavailableCard(for: reason)
                }
            }
        }
    }

    private func sectionHeader(
        countSummary: String?,
        showsRefreshButton: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text("SMART SUGGESTIONS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .kerning(0.8)

            if let countSummary {
                Text("· \(countSummary)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            if isAdminModeEnabled {
                Text("ADMIN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.info)
                    .kerning(0.6)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.infoSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.info.opacity(0.32), lineWidth: 1)
                    )
            }

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

            if isAdminModeEnabled, let baseE1RM = data?.baseE1RM {
                Text("e1RM \(formatWeight(baseE1RM))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.info)
            }

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

    private func formatWeight(_ kg: Double) -> String {
        UnitConversion.formatWeightLabel(kg, unitPreference: unitPreference)
    }

    /// Compact count summary that lives next to the section header label.
    /// Returns e.g. "4 ready" / "2 ready · 1 unavailable".
    /// `nil` when there's nothing meaningful to show.
    private func availabilitySummary(for data: WeightSuggestionData) -> String? {
        let readyCount = data.suggestions.count
        let unavailableCount = data.rowStates.count - readyCount

        var parts: [String] = []
        if readyCount > 0 {
            parts.append("\(readyCount) ready")
        } else if unavailableCount > 0, let reason = data.unavailableReason {
            parts.append("\(unavailableCount) unavailable · \(reason.title)")
        }
        if unavailableCount > 0, readyCount > 0 {
            parts.append("\(unavailableCount) unavailable")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
