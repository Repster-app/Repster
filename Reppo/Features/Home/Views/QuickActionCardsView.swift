// QuickActionCardsView.swift
// Two side-by-side action cards: "Copy Previous" and "Templates".
// Spec: 013-home-screen, WP03 T014

import SwiftUI

struct QuickActionCardsView: View {
    let onCopyPrevious: () -> Void
    let onTemplates: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            quickActionCard(
                icon: "doc.on.doc",
                title: "Copy Previous",
                action: onCopyPrevious
            )

            quickActionCard(
                icon: "doc.text",
                title: "Templates",
                action: onTemplates
            )
        }
    }

    private func quickActionCard(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accent)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)

                Spacer()
            }
            .padding(14)
            .frame(minHeight: 44)
            .background(Color.bgCard)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
