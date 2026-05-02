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

    private var muscleTagLayout: TemplateMuscleTagLayout {
        TemplateMuscleTagLayout(muscleGroups: template.muscleGroups)
    }

    private var visibleMuscleGroups: [String] {
        muscleTagLayout.visibleMuscleGroups
    }

    private var hiddenMuscleGroupCount: Int {
        muscleTagLayout.hiddenMuscleGroupCount
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 14) {
                    Text(iconLetter)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(iconColor)
                        .frame(width: 46, height: 46)
                        .background(iconColor.opacity(0.15))
                        .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(template.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)

                            Spacer(minLength: 0)

                            if let lastUsed = template.lastUsedAt {
                                Text(relativeDate(lastUsed))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textTertiary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.bgSubtle)
                                    .cornerRadius(8)
                            }
                        }

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

                            Circle()
                                .fill(Color.accent)
                                .frame(width: 3, height: 3)

                            Text("Tap to start")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.accent)
                        }

                        if !visibleMuscleGroups.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(visibleMuscleGroups, id: \.self) { muscle in
                                    muscleTag(ExercisePrimaryGroup.displayName(for: muscle))
                                }

                                if hiddenMuscleGroupCount > 0 {
                                    muscleTag("+\(hiddenMuscleGroupCount)")
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
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
            } label: {
                Group {
                    if isExporting {
                        ProgressView()
                            .tint(Color.textSecondary)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textSecondary)
                    }
                }
                .frame(width: 36, height: 36)
                .background(Color.bgSubtle)
                .cornerRadius(12)
                .contentShape(Rectangle())
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.border, lineWidth: 1)
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

    @ViewBuilder
    private func muscleTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.bgSubtle)
            .cornerRadius(4)
    }
}

struct TemplateMuscleTagLayout: Equatable {
    let visibleMuscleGroups: [String]
    let hiddenMuscleGroupCount: Int

    init(muscleGroups: [String], maxVisibleMuscleGroups: Int = 3) {
        let cappedVisibleCount = max(0, maxVisibleMuscleGroups)
        visibleMuscleGroups = Array(muscleGroups.prefix(cappedVisibleCount))
        hiddenMuscleGroupCount = max(0, muscleGroups.count - cappedVisibleCount)
    }
}
