// PRBadgeView.swift
// Renders PR badge (gold star + "PR") or match badge (blue "=") based on cachedPRStatus.
// Spec: design-system.md Section 6.4 (Badges)
//
// Pure presentational component — no business logic or service dependencies.

import SwiftUI

/// Displays a PR or match badge based on the set's cached PR status.
///
/// - `.current` → Gold badge with star icon + "PR" text
/// - `.matched` → Blue badge with "=" text
/// - `.previous` or `nil` → Nothing (EmptyView)
struct PRBadgeView: View {

    /// The cached PR status of the set. Nil means no badge.
    let status: CachedPRStatus?

    var body: some View {
        switch status {
        case .current:
            badgeContent(
                icon: "star.fill",
                text: "PR",
                foregroundColor: .gold,
                backgroundColor: .goldSoft,
                borderColor: Color.gold.opacity(0.20)
            )
        case .matched:
            badgeContent(
                icon: nil,
                text: "=",
                foregroundColor: .accent,
                backgroundColor: .accentSoft,
                borderColor: Color.accent.opacity(0.20)
            )
        case .dominated, .previous, .none:
            EmptyView()
        }
    }

    // MARK: - Badge Content

    @ViewBuilder
    private func badgeContent(
        icon: String?,
        text: String,
        foregroundColor: Color,
        backgroundColor: Color,
        borderColor: Color
    ) -> some View {
        HStack(spacing: 2) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
            }
            Text(text)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(foregroundColor)
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: 1)
        )
        .cornerRadius(4)
    }
}

// MARK: - Previews

#Preview("PR Badge") {
    ZStack {
        Color.bg.ignoresSafeArea()
        PRBadgeView(status: .current)
            .padding()
    }
}

#Preview("Match Badge") {
    ZStack {
        Color.bg.ignoresSafeArea()
        PRBadgeView(status: .matched)
            .padding()
    }
}

#Preview("No Badge (previous)") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack {
            Text("Previous status — should be empty below:")
                .foregroundColor(.textSecondary)
            PRBadgeView(status: .previous)
            Text("Nil status — should be empty below:")
                .foregroundColor(.textSecondary)
            PRBadgeView(status: nil)
        }
        .padding()
    }
}

#Preview("All States") {
    ZStack {
        Color.bg.ignoresSafeArea()
        HStack(spacing: 12) {
            PRBadgeView(status: .current)
            PRBadgeView(status: .matched)
            // .previous and nil render nothing
        }
        .padding()
    }
}
