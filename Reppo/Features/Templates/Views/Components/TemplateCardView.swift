// TemplateCardView.swift
// A single row in the template list showing template name, exercise count,
// set count, muscle groups, and last used date.

import SwiftUI

struct TemplateCardView: View {

    let template: TemplateSummary
    let isExporting: Bool
    let onTap: () -> Void
    let onExport: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// Color palette for the template icon (cycles based on first letter).
    private var iconColor: Color {
        let colors: [Color] = [.accent, .success, .gold, .chart5, .chart7, .chart8]
        let index = Int(template.name.first?.asciiValue ?? 0) % colors.count
        return colors[index]
    }

    private var iconLetter: String {
        String(template.name.prefix(1)).uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    // Icon
                    Text(iconLetter)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(iconColor)
                        .frame(width: 44, height: 44)
                        .background(iconColor.opacity(0.15))
                        .cornerRadius(12)

                    // Info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)

                        HStack(spacing: 8) {
                            Text("\(template.exerciseCount) exercises")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.textSecondary)

                            Circle()
                                .fill(Color.textTertiary)
                                .frame(width: 3, height: 3)

                            Text("\(template.totalSetCount) sets")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.textSecondary)
                        }

                        if !template.muscleGroups.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(template.muscleGroups.prefix(4), id: \.self) { muscle in
                                    Text(muscle.capitalized)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.textSecondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.bgSubtle)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    Spacer()

                    if let lastUsed = template.lastUsedAt {
                        Text(relativeDate(lastUsed))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 6) {
                Button(action: onExport) {
                    Group {
                        if isExporting {
                            ProgressView()
                                .tint(Color.textSecondary)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isExporting)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.border),
            alignment: .bottom
        )
        .contextMenu {
            Button {
                onExport()
            } label: {
                Label("Export Template", systemImage: "square.and.arrow.up")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit Template", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Template", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
