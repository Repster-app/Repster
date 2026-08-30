// ProgressionExclusionViews.swift
// The two ways the app says "this session doesn't count toward PRs".
//
// Both use the `stale` / `staleSoft` token pair rather than a warning colour. That pair already
// carries the right meaning elsewhere in the app (WeightSuggestionCardView's stale banner): the
// data is valid, it just isn't feeding the model. An excluded session is normally deliberate —
// travel, hotel gym, mismatched equipment — so this is a note, not an alarm.
//
// Copy rule: always name the scope. PRs, suggestions and insights honour this flag, but charts
// and volume totals ignore it entirely, so an excluded set really is still on the strength chart
// and still in the volume total. A bare "not counted" would be a lie on those screens.
// See PROGRESSION_EXCLUSION_VISIBILITY_SCOPING.md §1.

import SwiftUI

/// Compact form, for the session header on an exercise's history card.
///
/// Geometry deliberately matches `PRBadgeView` — same font size, padding, radius and border
/// opacity — because it occupies the same row and answers the same question: did this set count?
struct ProgressionExclusionChip: View {

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "nosign")
                .font(.system(size: 7, weight: .bold))

            Text("NOT COUNTED TOWARD PRs")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(.stale)
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .background(Color.staleSoft)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.stale.opacity(0.20), lineWidth: 1)
        )
        .cornerRadius(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Not counted toward PRs or future suggestions")
    }
}

/// Full-width form, for the top of a workout's detail screen.
///
/// Tapping opens the Progression sheet. That matters as much as the text: before this, the only
/// route to the setting was Edit → an unlabelled "…" → Progression, so a session could be
/// silently written out of PRs with no visible way back.
struct ProgressionExclusionBanner: View {

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "nosign")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.stale)

                Text("Not counted toward PRs or future suggestions")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.staleSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.stale.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens progression settings for this workout")
    }
}

// MARK: - Previews

#Preview("Chip") {
    ZStack {
        Color.bg
        HStack(spacing: 8) {
            Text("Mar 29, 2026")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            ProgressionExclusionChip()
            Spacer()
        }
        .padding()
    }
}

#Preview("Banner") {
    ZStack {
        Color.bg
        ProgressionExclusionBanner {}
            .padding()
    }
}
