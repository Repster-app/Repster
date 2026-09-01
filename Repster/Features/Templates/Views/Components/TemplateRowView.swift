// TemplateRowView.swift
// One 60pt row in the templates list: muscle-coloured bar, name, and a facts line.
//
// Replaces the old 46pt-tile card. The tile's colour came from `name.first.asciiValue % 6`, so
// "Push A" and "Pull A" collided; the bar takes its colour from the template's first muscle group
// instead, which is both stable and meaningful. Tapping opens the template rather than starting it.

import SwiftUI

struct TemplateRowView: View {

    let template: TemplateSummary
    let showsDivider: Bool
    let onTap: () -> Void

    private var accentBarColor: Color {
        guard let muscle = template.muscleGroups.first else { return .textTertiary }
        return MuscleGroupColors.color(for: muscle)
    }

    private var factsLine: String {
        var parts = [
            "\(template.exerciseCount) ex",
            "\(template.totalSetCount) set\(template.totalSetCount == 1 ? "" : "s")"
        ]
        parts.append(lastUsedDescription)
        return parts.joined(separator: " · ")
    }

    /// "never used" rather than a blank: an untouched template is a real state, and an imported one
    /// having no history is worth saying out loud.
    private var lastUsedDescription: String {
        guard let lastUsed = template.lastUsedAt else { return "never used" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 13) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentBarColor)
                        .frame(width: 4, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(template.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)

                            if template.hasSuperset {
                                Image(systemName: "link")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.chart5)
                                    .accessibilityLabel("Contains a superset")
                            }
                        }

                        Text(factsLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .frame(height: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsDivider {
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)
                    .padding(.leading, 17)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.name), \(factsLine)")
        .accessibilityHint("Opens the template")
    }
}
